#!/usr/bin/env python3
"""Agente do TAPKEY: recebe toques do celular e abre aplicativos (Linux).

Somente biblioteca padrão. Veja README.md.
"""
import configparser
import glob
import hashlib
import hmac
import json
import os
import secrets
import shlex
import shutil
import socket
import ssl
import subprocess
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import quote, unquote, urlparse

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import cursor_bridge  # noqa: E402

PORT = int(os.environ.get("MEU_NOTEBOOK_PORT", "8765"))
CONFIG_DIR = os.path.expanduser("~/.config/tapkey")
LEGACY_CONFIG_DIR = os.path.expanduser("~/.config/meu_notebook")
TOKEN_FILE = os.path.join(CONFIG_DIR, "token")
CLIENTS_FILE = os.path.join(CONFIG_DIR, "clients.json")
TLS_DIR = os.path.join(CONFIG_DIR, "tls")
CERT_FILE = os.path.join(TLS_DIR, "cert.pem")
KEY_FILE = os.path.join(TLS_DIR, "key.pem")
FP_FILE = os.path.join(TLS_DIR, "fingerprint")
HOOK_INFO_FILE = os.path.join(CONFIG_DIR, "hook.json")
HOOK_PORT = int(os.environ.get("TAPKEY_HOOK_PORT", str(PORT + 1)))
HOME = os.path.expanduser("~")

APP_DIRS = [
    os.path.join(HOME, ".local/share/applications"),
    "/usr/share/applications",
    "/usr/local/share/applications",
    "/var/lib/flatpak/exports/share/applications",
    os.path.join(HOME, ".local/share/flatpak/exports/share/applications"),
    "/var/lib/snapd/desktop/applications",
]
ICON_BASES = [
    os.path.join(HOME, ".local/share/icons"),
    os.path.join(HOME, ".icons"),
    "/usr/share/icons",
    "/var/lib/flatpak/exports/share/icons",
    os.path.join(HOME, ".local/share/flatpak/exports/share/icons"),
    "/var/lib/snapd/desktop/icons",
]
PIXMAP_DIRS = ["/usr/share/pixmaps", os.path.join(HOME, ".local/share/pixmaps")]
PREFERRED_THEMES = ["hicolor", "Mint-Y", "Mint-X", "Adwaita", "Yaru", "breeze", "gnome", "HighContrast"]

_lock = threading.Lock()
_apps = {}
_apps_time = 0.0
_icon_cache = {}


def load_token():
    os.makedirs(CONFIG_DIR, exist_ok=True)
    legacy = os.path.join(LEGACY_CONFIG_DIR, "token")
    if not os.path.exists(TOKEN_FILE) and os.path.exists(legacy):
        shutil.copyfile(legacy, TOKEN_FILE)  # migra do nome antigo
        os.chmod(TOKEN_FILE, 0o600)
    if os.path.exists(TOKEN_FILE):
        t = open(TOKEN_FILE).read().strip()
        if t:
            return t
    t = secrets.token_urlsafe(18)
    with open(TOKEN_FILE, "w") as f:
        f.write(t + "\n")
    os.chmod(TOKEN_FILE, 0o600)
    return t


def lan_ip():
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        s.connect(("192.168.255.255", 1))
        return s.getsockname()[0]
    except OSError:
        return "127.0.0.1"
    finally:
        s.close()


def parse_desktop(path):
    cp = configparser.RawConfigParser(strict=False, interpolation=None)
    cp.optionxform = str
    try:
        cp.read(path, encoding="utf-8")
        e = cp["Desktop Entry"]
    except Exception:
        return None
    if e.get("Type", "Application") != "Application":
        return None
    if e.get("NoDisplay", "false").lower() == "true" or e.get("Hidden", "false").lower() == "true":
        return None
    name, exec_ = e.get("Name"), e.get("Exec")
    if not name or not exec_:
        return None
    return {
        "name": name,
        "exec": exec_,
        "icon": e.get("Icon", ""),
        "terminal": e.get("Terminal", "false").lower() == "true",
        "path": e.get("Path", ""),
    }


def scan_apps(force=False):
    global _apps, _apps_time
    with _lock:
        if not force and _apps and time.time() - _apps_time < 30:
            return _apps
        found = {}
        for d in APP_DIRS:  # diretórios anteriores têm prioridade
            for root, _dirs, files in os.walk(d):
                for fn in files:
                    if not fn.endswith(".desktop"):
                        continue
                    rel = os.path.relpath(os.path.join(root, fn), d)
                    app_id = rel[:-8].replace(os.sep, "-")
                    if app_id in found:
                        continue
                    info = parse_desktop(os.path.join(root, fn))
                    if info:
                        info["id"] = app_id
                        found[app_id] = info
        _apps, _apps_time = found, time.time()
        return _apps


def find_icon_file(icon):
    """Retorna caminho de um PNG para o ícone, ou None."""
    if not icon:
        return None
    if icon in _icon_cache:
        return _icon_cache[icon]
    result = _resolve_icon(icon)
    _icon_cache[icon] = result
    return result


def _svg_to_png(svg):
    out_dir = os.path.join(CONFIG_DIR, "icon_cache")
    os.makedirs(out_dir, exist_ok=True)
    out = os.path.join(out_dir, hashlib.md5(svg.encode()).hexdigest()[:12] + ".png")
    if os.path.exists(out):
        return out
    for cmd in (
        ["rsvg-convert", "-w", "128", "-h", "128", "-o", out, svg],
        ["convert", "-background", "none", "-resize", "128x128", svg, out],
        ["inkscape", "-w", "128", "-h", "128", svg, "-o", out],
    ):
        if shutil.which(cmd[0]):
            try:
                subprocess.run(cmd, check=True, timeout=15, capture_output=True)
                if os.path.exists(out):
                    return out
            except Exception:
                pass
    return None


def _resolve_icon(icon):
    if os.path.isabs(icon):
        if icon.lower().endswith(".png") and os.path.isfile(icon):
            return icon
        if icon.lower().endswith(".svg") and os.path.isfile(icon):
            return _svg_to_png(icon)
        for ext in (".png",):
            if os.path.isfile(icon + ext):
                return icon + ext
        return None
    base_name = icon
    for ext in (".png", ".svg", ".xpm"):
        if base_name.endswith(ext):
            base_name = base_name[: -len(ext)]
    best, best_score = None, -1
    svg_fallback = None
    themes = list(PREFERRED_THEMES)
    for b in ICON_BASES:
        if os.path.isdir(b):
            for t in sorted(os.listdir(b)):
                if t not in themes:
                    themes.append(t)
    for ti, theme in enumerate(themes):
        for b in ICON_BASES:
            troot = os.path.join(b, theme)
            if not os.path.isdir(troot):
                continue
            for p in glob.glob(os.path.join(troot, "**", base_name + ".png"), recursive=True):
                size = 0
                for part in p.split(os.sep):
                    head = part.split("x")[0]
                    if "x" in part and head.isdigit():
                        size = int(head)
                        break
                    if part.isdigit():
                        size = int(part)
                        break
                if "/apps/" not in p and "/applications/" not in p:
                    size = size // 4
                # preferir ~128px
                score = 1000 - abs(size - 128) - ti
                if score > best_score:
                    best, best_score = p, score
            if svg_fallback is None:
                for p in glob.glob(os.path.join(troot, "**", base_name + ".svg"), recursive=True):
                    svg_fallback = p
                    break
        if best and ti >= 2:
            break
    if best:
        return best
    for d in PIXMAP_DIRS:
        p = os.path.join(d, base_name + ".png")
        if os.path.isfile(p):
            return p
    if svg_fallback:
        return _svg_to_png(svg_fallback)
    return None


def build_command(info):
    """Converte a linha Exec em argv, removendo códigos de campo (%U, %f, ...)."""
    try:
        parts = shlex.split(info["exec"])
    except ValueError:
        parts = info["exec"].split()
    argv = []
    for p in parts:
        if p == "%%":
            argv.append("%")
            continue
        if len(p) == 2 and p[0] == "%" and p[1] in "fFuUdDnNickvm":
            continue
        # códigos embutidos em argumentos
        for code in ("%f", "%F", "%u", "%U", "%d", "%D", "%n", "%N", "%i", "%c", "%k", "%v", "%m"):
            p = p.replace(code, "")
        if p:
            argv.append(p.replace("%%", "%"))
    if info.get("terminal"):
        term = shutil.which("x-terminal-emulator") or shutil.which("gnome-terminal") or shutil.which("xterm")
        if term:
            argv = [term, "-e"] + argv
    return argv


def launch(app_id):
    apps = scan_apps()
    info = apps.get(app_id)
    if info is None:
        info = scan_apps(force=True).get(app_id)
    if info is None:
        return False, "Aplicativo não encontrado"
    argv = build_command(info)
    if not argv:
        return False, "Comando vazio"
    env = dict(os.environ)
    env.setdefault("DISPLAY", ":0")
    env.setdefault("XAUTHORITY", os.path.join(HOME, ".Xauthority"))
    env.setdefault("XDG_RUNTIME_DIR", "/run/user/%d" % os.getuid())
    cwd = info["path"] if info.get("path") and os.path.isdir(info["path"]) else HOME
    try:
        subprocess.Popen(
            argv, cwd=cwd, env=env, start_new_session=True,
            stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )
        return True, "Abrindo " + info["name"]
    except Exception as ex:  # noqa: BLE001
        return False, "Falha ao abrir: %s" % ex


TOKEN = ""

_clients = {}
_clients_lock = threading.Lock()
_clients_saved = 0.0


def record_client(ip, action=None, force_save=False):
    """Guarda quem está falando com o agente (lido pelo TAPKEY Desktop)."""
    global _clients_saved
    now = time.time()
    with _clients_lock:
        c = _clients.setdefault(ip, {"ip": ip, "first_seen": now, "requests": 0, "launches": 0, "last_app": ""})
        c["last_seen"] = now
        c["requests"] += 1
        if action:
            c["launches"] += 1
            c["last_app"] = action
        if action or force_save or now - _clients_saved > 2:
            _clients_saved = now
            data = sorted(_clients.values(), key=lambda x: -x["last_seen"])
            try:
                tmp = CLIENTS_FILE + ".tmp"
                with open(tmp, "w") as f:
                    json.dump({"updated": now, "clients": data, "events": _events}, f)
                os.replace(tmp, CLIENTS_FILE)
            except OSError:
                pass


SETTINGS_FILE = os.path.join(CONFIG_DIR, "settings.json")
EVENTS_FILE = os.path.join(CONFIG_DIR, "events.log")
_events = []
NONCE_TTL = 20  # segundos de validade do desafio
UNLOCK_MAX_PER_MIN = 5
_nonces = {}  # nonce -> (expira, ip)
_unlock_attempts = {}  # ip -> [timestamps]
_sec_lock = threading.Lock()


def read_settings():
    try:
        with open(SETTINGS_FILE) as f:
            return json.load(f)
    except (OSError, ValueError):
        return {}


def unlock_allowed():
    """Opção 'Permitir desbloqueio pelo celular' (padrão: DESLIGADA)."""
    return bool(read_settings().get("allow_unlock", False))


def log_event(ip, event, ok=True, detail=""):
    """Registra bloqueio/desbloqueio no log e na lista de conexões recentes."""
    now = time.time()
    entry = {"t": now, "ip": ip, "event": event, "ok": ok, "detail": detail}
    with _clients_lock:
        _events.insert(0, entry)
        del _events[30:]
    try:
        with open(EVENTS_FILE, "a") as f:
            f.write("%s %s %s ok=%s %s\n" % (time.strftime("%Y-%m-%d %H:%M:%S"), ip, event, ok, detail))
    except OSError:
        pass
    record_client(ip, force_save=True)


def _session_env():
    env = dict(os.environ)
    env["LC_ALL"] = "C"
    env["LANGUAGE"] = "C"
    env.setdefault("DISPLAY", ":0")
    env.setdefault("XDG_RUNTIME_DIR", "/run/user/%d" % os.getuid())
    env.setdefault("DBUS_SESSION_BUS_ADDRESS", "unix:path=%s/bus" % env["XDG_RUNTIME_DIR"])
    return env


def _run(cmd, timeout=6):
    try:
        r = subprocess.run(cmd, env=_session_env(), capture_output=True, text=True, timeout=timeout)
        return r.returncode, (r.stdout + r.stderr).strip()
    except (OSError, subprocess.SubprocessError) as ex:
        return 1, str(ex)


def _session_id():
    sid = os.environ.get("XDG_SESSION_ID")
    if sid:
        return sid
    code, out = _run(["loginctl", "list-sessions", "--no-legend"])
    for line in out.splitlines():
        parts = line.split()
        if len(parts) >= 3 and parts[2] == os.environ.get("USER", ""):
            return parts[0]
    return ""


def is_locked():
    """True se a tela está bloqueada (Cinnamon screensaver ou LockedHint do logind)."""
    if shutil.which("cinnamon-screensaver-command"):
        code, out = _run(["cinnamon-screensaver-command", "--query"])
        low = out.lower()
        # a mensagem pode vir traduzida ("ativo"/"inativo")
        if "inactive" in low or "inativ" in low:
            return False
        if "active" in low or "ativ" in low:
            return True
    sid = _session_id()
    if sid:
        code, out = _run(["loginctl", "show-session", sid, "-p", "LockedHint", "--value"])
        return out.strip() == "yes"
    return False


def _wait_state(want_locked, seconds=2.5):
    end = time.time() + seconds
    while time.time() < end:
        if is_locked() == want_locked:
            return True
        time.sleep(0.25)
    return is_locked() == want_locked


def do_lock():
    sid = _session_id()
    if shutil.which("loginctl") and sid:
        _run(["loginctl", "lock-session", sid])
        if _wait_state(True):
            return True, "Notebook bloqueado", "loginctl"
    if shutil.which("cinnamon-screensaver-command"):
        _run(["cinnamon-screensaver-command", "--lock"])
        if _wait_state(True):
            return True, "Notebook bloqueado", "cinnamon-screensaver-command"
    return False, "Não consegui bloquear a tela", ""


def do_unlock():
    if not is_locked():
        return True, "A tela já estava desbloqueada", ""
    sid = _session_id()
    if shutil.which("loginctl") and sid:
        _run(["loginctl", "unlock-session", sid])
        if _wait_state(False):
            return True, "Notebook desbloqueado", "loginctl"
    if shutil.which("cinnamon-screensaver-command"):
        _run(["cinnamon-screensaver-command", "--deactivate"])
        if _wait_state(False):
            return True, "Notebook desbloqueado", "cinnamon-screensaver-command"
    return False, "O Cinnamon não aceitou o desbloqueio remoto. Digite a senha no notebook.", ""


def new_challenge(ip):
    now = time.time()
    nonce = secrets.token_hex(16)
    with _sec_lock:
        for k in [k for k, v in _nonces.items() if v[0] < now]:
            del _nonces[k]
        _nonces[nonce] = (now + NONCE_TTL, ip)
    return nonce


def consume_challenge(nonce, proof, ip):
    """Desafio de uso único, curto e atrelado ao IP; prova = HMAC-SHA256(token, nonce)."""
    now = time.time()
    with _sec_lock:
        item = _nonces.pop(nonce, None)
    if not item or item[0] < now or item[1] != ip:
        return False
    expected = hmac.new(TOKEN.encode(), nonce.encode(), hashlib.sha256).hexdigest()
    return hmac.compare_digest(expected, str(proof or ""))


def rate_limited(ip):
    now = time.time()
    with _sec_lock:
        lst = [t for t in _unlock_attempts.get(ip, []) if now - t < 60]
        if len(lst) >= UNLOCK_MAX_PER_MIN:
            _unlock_attempts[ip] = lst
            return True
        lst.append(now)
        _unlock_attempts[ip] = lst
    return False


def ensure_cert():
    """Gera (uma vez por instalação) um certificado autoassinado e retorna o fingerprint SHA-256."""
    os.makedirs(TLS_DIR, mode=0o700, exist_ok=True)
    if not (os.path.exists(CERT_FILE) and os.path.exists(KEY_FILE)):
        openssl = shutil.which("openssl")
        if not openssl:
            raise RuntimeError("openssl não encontrado (instale o pacote 'openssl') ou ative o modo HTTP legado.")
        cmd = [openssl, "req", "-x509", "-newkey", "ec", "-pkeyopt", "ec_paramgen_curve:prime256v1", "-nodes",
               "-days", "3650", "-subj", "/CN=tapkey-%s" % socket.gethostname(), "-keyout", KEY_FILE, "-out", CERT_FILE]
        r = subprocess.run(cmd, capture_output=True, text=True)
        if r.returncode != 0:
            raise RuntimeError("falha ao gerar certificado: %s" % r.stderr.strip())
        os.chmod(KEY_FILE, 0o600)
    with open(CERT_FILE) as f:
        der = ssl.PEM_cert_to_DER_cert(f.read())
    fp = hashlib.sha256(der).hexdigest()
    with open(FP_FILE, "w") as f:
        f.write(fp + "\n")
    return fp


def pair_uri(host, port, token, fp):
    q = "host=%s&port=%d&token=%s&name=%s" % (host, port, quote(token), quote(socket.gethostname()))
    if fp:
        q = "host=%s&port=%d&fp=%s&token=%s&name=%s" % (host, port, fp, quote(token), quote(socket.gethostname()))
    return "tapkey://pair?" + q


def load_hook_secret():
    p = os.path.join(CONFIG_DIR, "hook_secret")
    if os.path.exists(p):
        v = open(p).read().strip()
        if v:
            return v
    v = secrets.token_urlsafe(24)
    with open(p, "w") as f:
        f.write(v + "\n")
    os.chmod(p, 0o600)
    return v


BRIDGE = None
HOOK_SECRET = ""
TLS_ON = False
TLS_FP = ""


class Handler(BaseHTTPRequestHandler):
    server_version = "TAPKEY/2.0"
    timeout = 30

    def log_message(self, fmt, *args):
        sys.stderr.write("%s - %s\n" % (self.address_string(), fmt % args))

    def _send(self, code, body, ctype="application/json"):
        if not isinstance(body, (bytes, bytearray)):
            body = json.dumps(body, ensure_ascii=False).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", ctype + ("; charset=utf-8" if ctype == "application/json" else ""))
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "max-age=300" if ctype == "image/png" else "no-store")
        self.end_headers()
        self.wfile.write(body)

    def _auth(self):
        tok = self.headers.get("X-Token", "")
        if not hmac.compare_digest(tok.encode(), TOKEN.encode()):
            self._send(401, {"error": "Token inválido"})
            return False
        record_client(self.client_address[0])
        return True

    def do_GET(self):
        path = unquote(urlparse(self.path).path)
        if not self._auth():
            return
        if path == "/ping":
            self._send(200, {"ok": True, "host": socket.gethostname()})
        elif path == "/session":
            self._send(200, {"locked": is_locked(), "unlock_allowed": unlock_allowed()})
        elif path == "/challenge":
            self._send(200, {"nonce": new_challenge(self.client_address[0]), "expires_in": NONCE_TTL})
        elif path == "/cursor/state":
            if self._cursor_enabled():
                self._send(200, BRIDGE.snapshot())
        elif path == "/cursor/events":
            self._sse()
        elif path == "/apps":
            apps = scan_apps(force=True)
            lst = [{"id": a["id"], "name": a["name"], "icon": a["icon"]}
                   for a in sorted(apps.values(), key=lambda x: x["name"].lower())]
            self._send(200, lst)
        elif path.startswith("/icon/"):
            info = scan_apps().get(path[len("/icon/"):])
            f = find_icon_file(info["icon"]) if info else None
            if not f:
                self._send(404, {"error": "Sem ícone"})
                return
            try:
                with open(f, "rb") as fh:
                    self._send(200, fh.read(), "image/png")
            except OSError:
                self._send(404, {"error": "Sem ícone"})
        else:
            self._send(404, {"error": "Não encontrado"})

    def _cursor_enabled(self):
        if not BRIDGE.settings()["enabled"]:
            self._send(403, {"error": "A integração com o Cursor está desativada. Ative em TAPKEY Desktop > Integrar com o Cursor."})
            return False
        return True

    def _sse(self):
        if not self._cursor_enabled():
            return
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream; charset=utf-8")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Connection", "close")
        self.end_headers()
        dead = [False]

        def send(event, data):
            try:
                self.wfile.write(("event: %s\ndata: %s\n\n" % (event, json.dumps(data, ensure_ascii=False))).encode("utf-8"))
                self.wfile.flush()
            except (OSError, ssl.SSLError):
                dead[0] = True

        BRIDGE.stream(send, lambda: not dead[0] and not _SHUTDOWN.is_set())
        self.close_connection = True

    def _body(self):
        try:
            n = int(self.headers.get("Content-Length", "0"))
            return json.loads(self.rfile.read(min(n, 65536)) or b"{}")
        except Exception:
            return None

    def do_POST(self):
        path = urlparse(self.path).path
        if not self._auth():
            return
        ip = self.client_address[0]
        data = self._body()
        if data is None:
            self._send(400, {"error": "Requisição inválida"})
            return
        if path == "/launch":
            try:
                app_id = str(data["id"])
            except KeyError:
                self._send(400, {"error": "Requisição inválida"})
                return
            ok, msg = launch(app_id)
            if ok:
                record_client(ip, (scan_apps().get(app_id) or {}).get("name", app_id))
            self._send(200 if ok else 404, {"ok": ok, "message": msg})
        elif path == "/cursor/approval":
            if not self._cursor_enabled():
                return
            ok, code, msg = BRIDGE.decide(str(data.get("id", "")), str(data.get("decision", "")), ip)
            self._send(200 if ok else code, {"ok": ok, "message": msg} if ok else {"error": msg})
        elif path == "/cursor/instruction":
            code, body = BRIDGE.instruct(ip, data)
            self._send(code, body)
        elif path == "/cursor/instruction/cancel":
            if not self._cursor_enabled():
                return
            self._send(200, {"ok": BRIDGE.cancel_instruction(str(data.get("id", "")))})
        elif path == "/cursor/cli/cancel":
            if not self._cursor_enabled():
                return
            self._send(200, {"ok": BRIDGE.cancel_cli()})
        elif path == "/cursor/open":
            code, body = BRIDGE.open_workspace(ip, data.get("workspace_id", ""))
            self._send(code, body)
        elif path == "/lock":
            ok, msg, how = do_lock()
            log_event(ip, "Bloqueio", ok, how or msg)
            self._send(200 if ok else 500, {"ok": ok, "message": msg, "locked": is_locked()})
        elif path == "/unlock":
            if not unlock_allowed():
                log_event(ip, "Desbloqueio negado", False, "opção desativada")
                self._send(403, {"error": "O desbloqueio pelo celular está desativado. Ative em TAPKEY Desktop > Permitir desbloqueio pelo celular."})
                return
            if rate_limited(ip):
                log_event(ip, "Desbloqueio negado", False, "limite de tentativas")
                self._send(429, {"error": "Muitas tentativas. Aguarde um minuto."})
                return
            if not consume_challenge(str(data.get("nonce", "")), data.get("proof"), ip):
                log_event(ip, "Desbloqueio negado", False, "desafio inválido")
                self._send(400, {"error": "Desafio inválido ou expirado. Tente de novo."})
                return
            ok, msg, how = do_unlock()
            log_event(ip, "Desbloqueio", ok, how or msg)
            self._send(200 if ok else 500, {"ok": ok, "message": msg, "locked": is_locked()})
        else:
            self._send(404, {"error": "Não encontrado"})


class QuietServer(ThreadingHTTPServer):
    """Silencia erros de conexão/handshake TLS (varreduras de rede, clientes que caem)."""
    daemon_threads = True

    def handle_error(self, request, client_address):
        et = sys.exc_info()[0]
        if et and issubclass(et, (OSError, ssl.SSLError)):
            return
        super().handle_error(request, client_address)


class HookHandler(BaseHTTPRequestHandler):
    """Listener SOMENTE de loopback usado pelo relay dos hooks do Cursor."""
    server_version = "TAPKEY-hook/1.0"
    timeout = 90

    def log_message(self, fmt, *args):
        pass

    def _send(self, code, body):
        b = json.dumps(body, ensure_ascii=False).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(b)))
        self.end_headers()
        self.wfile.write(b)

    def do_GET(self):
        if urlparse(self.path).path == "/status":
            self._send(200, {"ok": True, "tls": TLS_ON, "fp": TLS_FP, "host": socket.gethostname()})
        else:
            self._send(404, {"error": "Não encontrado"})

    def do_POST(self):
        if urlparse(self.path).path != "/hook":
            self._send(404, {"error": "Não encontrado"})
            return
        if not hmac.compare_digest(self.headers.get("X-Hook-Secret", "").encode(), HOOK_SECRET.encode()):
            self._send(401, {"error": "segredo inválido"})
            return
        try:
            n = int(self.headers.get("Content-Length", "0"))
            data = json.loads(self.rfile.read(min(n, 131072)) or b"{}")
        except Exception:
            self._send(400, {"error": "json inválido"})
            return
        try:
            self._send(200, BRIDGE.handle_hook(data) or {})
        except Exception as ex:  # nunca derruba o Cursor
            sys.stderr.write("hook erro: %r\n" % (ex,))
            self._send(200, {})


_SHUTDOWN = threading.Event()


def main():
    global TOKEN, BRIDGE, HOOK_SECRET, TLS_ON, TLS_FP
    TOKEN = load_token()
    HOOK_SECRET = load_hook_secret()
    BRIDGE = cursor_bridge.Bridge(CONFIG_DIR, read_settings)
    ip = lan_ip()
    legacy = bool(read_settings().get("legacy_http", False))
    if not legacy:
        try:
            TLS_FP = ensure_cert()
            TLS_ON = True
        except RuntimeError as ex:
            print("ERRO TLS: %s" % ex, file=sys.stderr)
            sys.exit(2)
    scheme = "https" if TLS_ON else "http"
    print("=" * 50)
    print(" TAPKEY - agente")
    print(" Endereço : %s://%s:%d" % (scheme, ip, PORT))
    if TLS_ON:
        print(" TLS      : certificado autoassinado, fingerprint SHA-256")
        print("            %s" % TLS_FP)
    else:
        print(" ATENÇÃO  : modo HTTP legado (sem criptografia). Use só em rede confiável.")
    print(" Pareamento: %s" % pair_uri(ip, PORT, TOKEN, TLS_FP))
    print(" Token    : %s" % TOKEN)
    print(" (token salvo em %s)" % TOKEN_FILE)
    print(" Aplicativos encontrados: %d" % len(scan_apps(force=True)))
    print("=" * 50, flush=True)
    srv = QuietServer(("0.0.0.0", PORT), Handler)
    srv.daemon_threads = True
    if TLS_ON:
        ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        ctx.minimum_version = ssl.TLSVersion.TLSv1_2
        ctx.load_cert_chain(CERT_FILE, KEY_FILE)
        # handshake feito na thread da conexão (não trava o accept)
        srv.socket = ctx.wrap_socket(srv.socket, server_side=True, do_handshake_on_connect=False)
    hook_srv = None
    try:
        hook_srv = ThreadingHTTPServer(("127.0.0.1", HOOK_PORT), HookHandler)
        hook_srv.daemon_threads = True
        threading.Thread(target=hook_srv.serve_forever, daemon=True).start()
        with open(HOOK_INFO_FILE, "w") as f:
            json.dump({"port": HOOK_PORT, "secret": HOOK_SECRET, "pid": os.getpid()}, f)
        os.chmod(HOOK_INFO_FILE, 0o600)
    except OSError as ex:
        print("Aviso: listener de hooks indisponível (%s)" % ex, file=sys.stderr)
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        print("\nEncerrado.")
    finally:
        _SHUTDOWN.set()


if __name__ == "__main__":
    main()
