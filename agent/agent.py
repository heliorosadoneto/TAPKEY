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
import subprocess
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import unquote, urlparse

PORT = int(os.environ.get("MEU_NOTEBOOK_PORT", "8765"))
CONFIG_DIR = os.path.expanduser("~/.config/tapkey")
LEGACY_CONFIG_DIR = os.path.expanduser("~/.config/meu_notebook")
TOKEN_FILE = os.path.join(CONFIG_DIR, "token")
CLIENTS_FILE = os.path.join(CONFIG_DIR, "clients.json")
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


def record_client(ip, action=None):
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
        if action or now - _clients_saved > 2:
            _clients_saved = now
            data = sorted(_clients.values(), key=lambda x: -x["last_seen"])
            try:
                tmp = CLIENTS_FILE + ".tmp"
                with open(tmp, "w") as f:
                    json.dump({"updated": now, "clients": data}, f)
                os.replace(tmp, CLIENTS_FILE)
            except OSError:
                pass


class Handler(BaseHTTPRequestHandler):
    server_version = "MeuNotebook/1.0"

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

    def do_POST(self):
        path = urlparse(self.path).path
        if not self._auth():
            return
        if path != "/launch":
            self._send(404, {"error": "Não encontrado"})
            return
        try:
            n = int(self.headers.get("Content-Length", "0"))
            data = json.loads(self.rfile.read(min(n, 65536)) or b"{}")
            app_id = str(data["id"])
        except Exception:
            self._send(400, {"error": "Requisição inválida"})
            return
        ok, msg = launch(app_id)
        if ok:
            record_client(self.client_address[0], (scan_apps().get(app_id) or {}).get("name", app_id))
        self._send(200 if ok else 404, {"ok": ok, "message": msg})


def main():
    global TOKEN
    TOKEN = load_token()
    ip = lan_ip()
    print("=" * 50)
    print(" TAPKEY - agente")
    print(" Endereço : http://%s:%d" % (ip, PORT))
    print(" Pareamento: tapkey://pair?host=%s&port=%d&token=%s" % (ip, PORT, TOKEN))
    print(" Token    : %s" % TOKEN)
    print(" (token salvo em %s)" % TOKEN_FILE)
    print(" Aplicativos encontrados: %d" % len(scan_apps(force=True)))
    print("=" * 50, flush=True)
    srv = ThreadingHTTPServer(("0.0.0.0", PORT), Handler)
    srv.daemon_threads = True
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        print("\nEncerrado.")


if __name__ == "__main__":
    main()
