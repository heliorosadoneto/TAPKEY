"""Ponte TAPKEY <-> Cursor (somente biblioteca padrão).

Guarda o estado das sessões do Cursor (vindo dos hooks), aprovações pendentes,
fila de instruções e a execução opcional do Cursor CLI. Nada aqui abre portas:
quem expõe isso é agent.py (celular, por TLS) e o listener de loopback (hooks).
"""
import hashlib
import json
import os
import shutil
import subprocess
import threading
import time
import uuid

APPROVAL_TIMEOUT = int(os.environ.get("TAPKEY_APPROVAL_TIMEOUT", "60"))  # segundos esperando o celular
LONG_COMMAND = 500             # acima disso, o celular só pode negar
MAX_INSTRUCTION = 4000
MAX_QUEUE_PER_SESSION = 5
INSTR_PER_MIN = 6
SESSION_TTL = 6 * 3600
WORKING_STALE = 600            # "trabalhando" sem sinal por 10 min vira "parado"
CLI_TIMEOUT = 30 * 60
CLI_OUT_LIMIT = 200_000


def _short(s, n):
    s = "" if s is None else str(s)
    return s if len(s) <= n else s[: n - 1] + "…"


def ws_id(path):
    return hashlib.sha1(path.encode()).hexdigest()[:10]


class Bridge:
    def __init__(self, config_dir, get_settings, log=None):
        self.cfg = config_dir
        self.get_settings = get_settings
        self.cond = threading.Condition(threading.RLock())
        self.sessions = {}
        self.workspaces = {}
        self.approvals = {}
        self.queue = []
        self.cli = {"running": False}
        self._cli_proc = None
        self.version = 0
        self.watchers = 0
        self.log_seq = 0
        self.events = []          # [{seq,type,data}] (últimos 200)
        self._instr_times = {}
        self._log_path = os.path.join(config_dir, "cursor.log")
        self._ws_path = os.path.join(config_dir, "workspaces.json")
        self._log_cb = log
        self._load_workspaces()

    # ---------- util ----------
    def settings(self):
        s = self.get_settings() or {}
        return {
            "enabled": bool(s.get("cursor_integration", False)),
            "approvals": bool(s.get("cursor_approvals", False)),
            "instructions": bool(s.get("allow_instructions", False)),
        }

    def log(self, msg):
        try:
            with open(self._log_path, "a") as f:
                f.write("%s %s\n" % (time.strftime("%Y-%m-%d %H:%M:%S"), msg))
        except OSError:
            pass

    def _bump(self):
        self.version += 1
        self.cond.notify_all()

    def _emit(self, typ, **data):
        self.log_seq += 1
        self.events.append({"seq": self.log_seq, "type": typ, "data": data})
        del self.events[:-200]
        self.cond.notify_all()

    def _load_workspaces(self):
        try:
            with open(self._ws_path) as f:
                for w in json.load(f):
                    if os.path.isabs(w.get("path", "")):
                        self.workspaces[ws_id(w["path"])] = {
                            "id": ws_id(w["path"]), "path": w["path"],
                            "name": os.path.basename(w["path"].rstrip("/")) or w["path"],
                            "last_seen": w.get("last_seen", 0)}
        except (OSError, ValueError, TypeError):
            pass

    def _save_workspaces(self):
        try:
            tmp = self._ws_path + ".tmp"
            with open(tmp, "w") as f:
                json.dump([{"path": w["path"], "last_seen": w["last_seen"]} for w in self.workspaces.values()], f)
            os.replace(tmp, self._ws_path)
            os.chmod(self._ws_path, 0o600)
        except OSError:
            pass

    def _register_workspace(self, path):
        """A allowlist de pastas vem SOMENTE dos hooks vistos, nunca do celular."""
        if not path or not os.path.isabs(path) or not os.path.isdir(path):
            return None
        path = os.path.normpath(path)
        wid = ws_id(path)
        new = wid not in self.workspaces
        self.workspaces[wid] = {"id": wid, "path": path, "name": os.path.basename(path) or path, "last_seen": time.time()}
        if new:
            self._save_workspaces()
        return wid

    # ---------- snapshot para o celular (sem caminhos completos) ----------
    def snapshot(self):
        with self.cond:
            now = time.time()
            for s in self.sessions.values():
                if s["state"] == "working" and now - s["updated"] > WORKING_STALE:
                    s["state"] = "idle"
            for sid in [k for k, s in self.sessions.items() if now - s["updated"] > SESSION_TTL]:
                del self.sessions[sid]
            st = self.settings()
            cli_path = self.cli_binary()
            sess = sorted(self.sessions.values(), key=lambda s: -s["updated"])
            return {
                "version": self.version,
                "enabled": st["enabled"],
                "approvals_enabled": st["approvals"],
                "instructions_enabled": st["instructions"],
                "cli_available": bool(cli_path),
                "sessions": [{
                    "id": s["id"], "workspace_id": s["wid"], "folder": s["folder"], "state": s["state"],
                    "last_tool": s["last_tool"], "updated": s["updated"], "started": s["started"],
                    "queued": sum(1 for q in self.queue if q["cid"] == s["id"] and q["status"] == "queued"),
                } for s in sess[:12]],
                "approvals": [{
                    "id": a["id"], "session_id": a["cid"], "folder": a["folder"], "kind": a["kind"],
                    "title": a["title"], "command": a["command"], "tool": a["tool"], "server": a["server"],
                    "created": a["created"], "expires": a["expires"], "deny_only": a["deny_only"],
                } for a in self.approvals.values() if a["status"] == "pending"],
                "workspaces": [{"id": w["id"], "name": w["name"]} for w in
                               sorted(self.workspaces.values(), key=lambda w: -w["last_seen"])[:20]],
                "queue": [{"id": q["id"], "session_id": q["cid"], "folder": q["folder"],
                           "preview": _short(q["text"], 80), "created": q["created"]}
                          for q in self.queue if q["status"] == "queued"],
                "cli": {k: v for k, v in self.cli.items() if k != "pid"},
                "now": now,
            }

    # ---------- hooks ----------
    def handle_hook(self, d):
        """Chamado pelo listener de loopback. Retorna dict para o relay imprimir."""
        st = self.settings()
        if not st["enabled"]:
            return {}
        ev = str(d.get("event", ""))
        cid = _short(d.get("cid") or "", 80)
        roots = [r for r in (d.get("roots") or []) if isinstance(r, str)]
        path = roots[0] if roots else str(d.get("cwd") or "")
        with self.cond:
            wid = self._register_workspace(path)
            for r in roots[1:3]:
                self._register_workspace(r)
            sess = None
            if cid:
                sess = self.sessions.get(cid)
                if not sess:
                    folder = (self.workspaces.get(wid) or {}).get("name") or (os.path.basename(path.rstrip("/")) if path else "?")
                    sess = {"id": cid, "wid": wid, "folder": _short(folder, 60), "state": "idle", "last_tool": "",
                            "started": time.time(), "updated": time.time()}
                    self.sessions[cid] = sess
                    self._emit("notice", kind="started", folder=sess["folder"], text="Sessão do Cursor iniciada")
                sess["updated"] = time.time()
                if wid:
                    sess["wid"] = wid
            out = {}
            if ev == "sessionStart":
                if sess:
                    sess["state"] = "idle"
            elif ev == "sessionEnd":
                if sess:
                    self.sessions.pop(cid, None)
                    self._emit("notice", kind="ended", folder=sess["folder"], text="Sessão encerrada")
            elif ev == "beforeSubmitPrompt":
                if sess:
                    sess["state"] = "thinking"
                    sess["last_tool"] = ""
            elif ev in ("preToolUse", "postToolUse"):
                if sess:
                    sess["state"] = "working"
                    sess["last_tool"] = _short(d.get("detail") or d.get("tool") or "", 90)
            elif ev == "postToolUseFailure":
                if sess:
                    sess["state"] = "working"
                    sess["last_tool"] = _short("%s falhou" % (d.get("tool") or "ferramenta"), 90)
                    self._emit("notice", kind="error", folder=sess["folder"], text="Uma ferramenta falhou")
            elif ev == "stop":
                status = str(d.get("status") or "completed")
                if sess:
                    sess["state"] = {"completed": "finished", "aborted": "idle", "error": "error"}.get(status, "finished")
                    kind = {"completed": "finished", "aborted": "aborted", "error": "error"}.get(status, "finished")
                    txt = {"finished": "Cursor terminou", "aborted": "Execução interrompida", "error": "Cursor terminou com erro"}[kind]
                    self._emit("notice", kind=kind, folder=sess["folder"], text=txt)
                    # entrega a próxima instrução na MESMA conversa
                    if st["instructions"] and status == "completed":
                        for q in self.queue:
                            if q["status"] == "queued" and q["cid"] == cid:
                                q["status"] = "delivered"
                                out["followup_message"] = q["text"]
                                sess["state"] = "thinking"
                                self.log("instrução %s entregue via hook stop em '%s' (%d chars)" % (q["id"], sess["folder"], len(q["text"])))
                                self._emit("notice", kind="delivered", folder=sess["folder"], text="Instrução enviada ao Cursor")
                                break
            elif ev in ("beforeShellExecution", "beforeMCPExecution"):
                pass  # tratado fora do lock (bloqueia)
            self._bump()
        if ev in ("beforeShellExecution", "beforeMCPExecution"):
            out = self._approval(ev, sess, d)
        return out

    def _approval(self, ev, sess, d):
        st = self.settings()
        if not st["approvals"] or self.watchers <= 0 or not sess:
            return {"decision": "none"}
        kind = "shell" if ev == "beforeShellExecution" else "mcp"
        if kind == "shell":
            command = str(d.get("command") or "")
            title = "Comando no terminal"
        else:
            command = "%s\n%s" % (d.get("mcp_tool") or d.get("tool") or "ferramenta MCP", _short(d.get("tool_input") or "", 1500))
            title = "Ferramenta MCP: %s" % _short(d.get("server") or "", 40)
        command = command[:8000]
        aid = uuid.uuid4().hex[:12]
        a = {"id": aid, "cid": sess["id"], "folder": sess["folder"], "kind": kind, "title": title, "command": command,
             "tool": _short(d.get("mcp_tool") or d.get("tool") or "", 60), "server": _short(d.get("server") or "", 60),
             "created": time.time(), "expires": time.time() + APPROVAL_TIMEOUT, "status": "pending",
             "deny_only": len(command) > LONG_COMMAND}
        with self.cond:
            self.approvals[aid] = a
            prev = sess["state"]
            sess["state"] = "waiting"
            self._emit("notice", kind="approval", folder=sess["folder"], text="Cursor pede aprovação", id=aid)
            self._bump()
            self.log("aprovação %s pedida (%s, %d chars) em '%s'" % (aid, kind, len(command), sess["folder"]))
            end = a["expires"]
            while a["status"] == "pending" and time.time() < end:
                self.cond.wait(timeout=max(0.05, min(1.0, end - time.time())))
            if a["status"] == "pending":
                a["status"] = "timeout"
            if sess["state"] == "waiting":
                sess["state"] = "working" if a["status"] != "deny" else prev
            self._bump()
            status = a["status"]
            self.log("aprovação %s resultado=%s" % (aid, status))
            # limpeza
            for k in [k for k, v in self.approvals.items() if v["status"] != "pending" and time.time() - v["created"] > 300]:
                del self.approvals[k]
        return {"decision": {"allow": "allow", "deny": "deny", "timeout": "ask"}.get(status, "ask")}

    def decide(self, aid, decision, ip=""):
        with self.cond:
            a = self.approvals.get(aid)
            if not a or a["status"] != "pending":
                return False, 404, "Esta aprovação não está mais pendente."
            if decision not in ("allow", "deny"):
                return False, 400, "Decisão inválida."
            if decision == "allow" and a["deny_only"]:
                return False, 400, "Comando longo demais: só é possível negar pelo celular."
            a["status"] = decision
            self.log("aprovação %s %s por %s" % (aid, decision, ip))
            self._emit("notice", kind="decided", folder=a["folder"], text="Permitido" if decision == "allow" else "Negado", decision=decision)
            self._bump()
            return True, 200, "ok"

    # ---------- instruções ----------
    def _instr_rate(self, ip):
        now = time.time()
        lst = [t for t in self._instr_times.get(ip, []) if now - t < 60]
        if len(lst) >= INSTR_PER_MIN:
            self._instr_times[ip] = lst
            return True
        lst.append(now)
        self._instr_times[ip] = lst
        return False

    def cli_binary(self):
        for c in (shutil.which("agent"), shutil.which("cursor-agent"),
                  os.path.expanduser("~/.local/bin/agent"), os.path.expanduser("~/.local/bin/cursor-agent")):
            if c and os.path.isfile(c) and os.access(c, os.X_OK):
                return c
        return None

    def cursor_binary(self):
        for c in (shutil.which("cursor"), os.path.expanduser("~/.local/bin/cursor")):
            if c and os.path.isfile(c) and os.access(c, os.X_OK):
                return c
        return None

    def instruct(self, ip, body):
        st = self.settings()
        if not st["enabled"]:
            return 403, {"error": "A integração com o Cursor está desativada. Ative em TAPKEY Desktop > Integrar com o Cursor."}
        if not st["instructions"]:
            return 403, {"error": "Enviar instruções pelo celular está desativado. Ative em TAPKEY Desktop > Permitir enviar instruções do celular."}
        text = str(body.get("text") or "").strip()
        mode = str(body.get("mode") or "ide")
        if not text:
            return 400, {"error": "Escreva a instrução."}
        if len(text) > MAX_INSTRUCTION:
            return 400, {"error": "Instrução longa demais (máximo %d caracteres)." % MAX_INSTRUCTION}
        if mode not in ("ide", "cli"):
            return 400, {"error": "Modo inválido."}
        with self.cond:
            if self._instr_rate(ip):
                self.log("instrução recusada (limite) de %s" % ip)
                return 429, {"error": "Muitas instruções em pouco tempo. Aguarde um minuto."}
            sid = str(body.get("session_id") or "")
            wid = str(body.get("workspace_id") or "")
            sess = self.sessions.get(sid)
            if mode == "ide":
                if not sess:
                    return 404, {"error": "Sessão do Cursor não encontrada. Ela precisa estar aberta no Cursor."}
                if sum(1 for q in self.queue if q["cid"] == sid and q["status"] == "queued") >= MAX_QUEUE_PER_SESSION:
                    return 429, {"error": "Fila cheia para esta sessão."}
                q = {"id": uuid.uuid4().hex[:10], "cid": sid, "wid": sess["wid"], "folder": sess["folder"], "text": text,
                     "created": time.time(), "status": "queued"}
                self.queue.append(q)
                del self.queue[:-50]
                self.log("instrução %s enfileirada de %s para '%s' (%d chars, IDE)" % (q["id"], ip, sess["folder"], len(text)))
                self._bump()
                return 200, {"ok": True, "id": q["id"], "message": "Instrução na fila. O Cursor a recebe quando terminar a execução atual."}
            # modo CLI
            if sess and not wid:
                wid = sess["wid"] or ""
            ws = self.workspaces.get(wid)
            if not ws:
                return 404, {"error": "Pasta não encontrada entre os projetos vistos pelo Cursor."}
            binary = self.cli_binary()
            if not binary:
                return 400, {"error": "Cursor CLI (agent) não está instalado neste notebook."}
            if self.cli.get("running"):
                return 409, {"error": "Já existe uma execução do Cursor CLI em andamento."}
            resume = bool(body.get("resume", True)) and bool(sid)
            cmd = [binary, "-p", "--workspace", ws["path"], "--output-format", "text"]
            if resume:
                cmd += ["--resume", sid]
            cmd += ["--", text]   # nunca --force/--yolo
            self.log("CLI iniciado de %s em '%s' (%d chars, resume=%s)" % (ip, ws["name"], len(text), resume))
            self.cli = {"running": True, "folder": ws["name"], "started": time.time(), "text": _short(text, 120), "exit": None, "lines": 0}
            threading.Thread(target=self._run_cli, args=(cmd, ws["path"], ws["name"]), daemon=True).start()
            self._bump()
            return 200, {"ok": True, "message": "Executando no Cursor CLI…"}

    def cancel_instruction(self, qid):
        with self.cond:
            for q in self.queue:
                if q["id"] == qid and q["status"] == "queued":
                    q["status"] = "canceled"
                    self.log("instrução %s cancelada" % qid)
                    self._bump()
                    return True
        return False

    def _run_cli(self, cmd, cwd, name):
        total = 0
        code = None
        try:
            p = subprocess.Popen(cmd, cwd=cwd, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                 text=True, bufsize=1, start_new_session=True)
            self._cli_proc = p
            timer = threading.Timer(CLI_TIMEOUT, lambda: self._kill_cli(p))
            timer.daemon = True
            timer.start()
            for line in p.stdout:
                line = line.rstrip("\n")
                total += len(line)
                if total > CLI_OUT_LIMIT:
                    continue
                with self.cond:
                    self.cli["lines"] = self.cli.get("lines", 0) + 1
                    self._emit("cli", text=_short(line, 2000))
            code = p.wait()
            timer.cancel()
        except OSError as ex:
            with self.cond:
                self._emit("cli", text="Falha ao iniciar o Cursor CLI: %s" % ex)
        finally:
            with self.cond:
                self._cli_proc = None
                self.cli["running"] = False
                self.cli["exit"] = code
                self._emit("notice", kind="cli_done" if code == 0 else "error", folder=name,
                           text="Cursor CLI terminou" if code == 0 else "Cursor CLI terminou com erro")
                self.log("CLI terminou em '%s' código=%s" % (name, code))
                self._bump()

    def _kill_cli(self, p):
        try:
            os.killpg(p.pid, 15)
        except OSError:
            pass

    def cancel_cli(self):
        p = self._cli_proc
        if p:
            self._kill_cli(p)
            return True
        return False

    def open_workspace(self, ip, wid):
        st = self.settings()
        if not st["enabled"]:
            return 403, {"error": "A integração com o Cursor está desativada."}
        with self.cond:
            ws = self.workspaces.get(str(wid))
        if not ws or not os.path.isdir(ws["path"]):
            return 404, {"error": "Pasta não encontrada entre os projetos vistos pelo Cursor."}
        b = self.cursor_binary()
        if not b:
            return 400, {"error": "O comando 'cursor' não foi encontrado."}
        env = dict(os.environ)
        env.setdefault("DISPLAY", ":0")
        try:
            subprocess.Popen([b, ws["path"]], env=env, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                             stderr=subprocess.DEVNULL, start_new_session=True)
        except OSError as ex:
            return 500, {"error": "Falha ao abrir o Cursor: %s" % ex}
        self.log("abrir no Cursor '%s' pedido por %s" % (ws["name"], ip))
        return 200, {"ok": True, "message": "Abrindo %s no Cursor…" % ws["name"]}

    # ---------- SSE ----------
    def stream(self, send, alive, since=None):
        """Loop do SSE: `send(event, data)`; `alive()` retorna False se o cliente caiu."""
        with self.cond:
            self.watchers += 1
            self._bump()
            seq = self.log_seq if since is None else since
            ver = -1
        try:
            last_ping = time.time()
            while alive():
                with self.cond:
                    news = [e for e in self.events if e["seq"] > seq]
                    changed = self.version != ver
                    if not news and not changed:
                        self.cond.wait(timeout=5)
                        news = [e for e in self.events if e["seq"] > seq]
                        changed = self.version != ver
                if changed:
                    snap = self.snapshot()
                    ver = snap["version"]
                    send("state", snap)
                    last_ping = time.time()
                for e in news:
                    seq = e["seq"]
                    send(e["type"], dict(e["data"], seq=e["seq"]))
                    last_ping = time.time()
                if time.time() - last_ping > 12:
                    send("ping", {"t": time.time()})
                    last_ping = time.time()
        finally:
            with self.cond:
                self.watchers = max(0, self.watchers - 1)
                self._bump()
