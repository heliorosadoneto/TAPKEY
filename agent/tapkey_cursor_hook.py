#!/usr/bin/env python3
"""tapkey-cursor-hook: relay entre os hooks do Cursor e o agente TAPKEY (somente stdlib).

Uso pelo Cursor (hook):   python3 tapkey_cursor_hook.py            (JSON em stdin)
Gerência (TAPKEY Desktop): python3 tapkey_cursor_hook.py install|uninstall|status|diff [--home DIR]

Regras de segurança/robustez:
- NUNCA bloqueia o Cursor: timeouts curtos, qualquer erro => saída neutra e exit 0 (fail-open).
- Só repassa campos úteis, cortados em 2 KB (o comando de aprovação, até 8 KB). O texto do prompt
  do usuário nunca é enviado.
- Fala só com 127.0.0.1 (listener de loopback do agente), autenticado por segredo local (0600).
"""
import difflib
import json
import os
import shutil
import sys
import time
import urllib.request

MARK = "tapkey_cursor_hook.py"      # marcador: remove SÓ as entradas que contêm isto
EVENTS = ["sessionStart", "sessionEnd", "beforeSubmitPrompt", "preToolUse", "postToolUse",
          "postToolUseFailure", "stop", "beforeShellExecution", "beforeMCPExecution"]
BLOCKING = {"beforeShellExecution", "beforeMCPExecution"}
FIELD_MAX = 2048
CMD_MAX = 8000
NEUTRAL_PERMISSION = {"continue": True, "permission": "allow"}


def trim(v, n=FIELD_MAX):
    if v is None:
        return ""
    if not isinstance(v, str):
        try:
            v = json.dumps(v, ensure_ascii=False)
        except (TypeError, ValueError):
            v = str(v)
    return v if len(v) <= n else v[: n - 1] + "…"


def config_dir(home=None):
    return os.path.join(home or os.path.expanduser("~"), ".config", "tapkey")


def load_info(home=None):
    with open(os.path.join(config_dir(home), "hook.json")) as f:
        return json.load(f)


def normalize(d):
    ev = str(d.get("hook_event_name") or "")
    ti = d.get("tool_input")
    out = {
        "event": ev,
        "cid": trim(d.get("conversation_id") or d.get("session_id"), 100),
        "roots": [trim(r, 500) for r in (d.get("workspace_roots") or [])[:3] if isinstance(r, str)],
        "cwd": trim(d.get("cwd"), 500),
        "tool": trim(d.get("tool_name"), 80),
        "status": trim(d.get("status") or d.get("reason"), 40),
    }
    if ev in ("preToolUse", "postToolUse", "postToolUseFailure"):
        detail = out["tool"]
        if isinstance(ti, dict):
            if ti.get("command"):
                detail = "%s: %s" % (out["tool"], trim(ti["command"], 80))
            elif ti.get("path") or ti.get("file_path"):
                detail = "%s: %s" % (out["tool"], os.path.basename(str(ti.get("path") or ti.get("file_path"))))
        out["detail"] = trim(detail, 120)
    if ev == "beforeShellExecution":
        out["command"] = trim(d.get("command"), CMD_MAX)
        out["cwd"] = trim(d.get("cwd"), 500)
    if ev == "beforeMCPExecution":
        out["mcp_tool"] = trim(d.get("tool_name"), 80)
        out["server"] = trim(d.get("mcp_server_name"), 80)
        out["tool_input"] = trim(d.get("tool_input"), FIELD_MAX)
    return out


def neutral(ev):
    if ev in BLOCKING or ev == "preToolUse":
        return dict(NEUTRAL_PERMISSION)
    if ev == "beforeSubmitPrompt":
        return {"continue": True}
    return {}


def render(ev, resp):
    """Converte a resposta do agente na saída que o Cursor espera."""
    out = neutral(ev)
    if ev in BLOCKING:
        dec = (resp or {}).get("decision", "none")
        if dec == "deny":
            out = {"continue": True, "permission": "deny",
                   "user_message": "Negado pelo celular (TAPKEY).",
                   "agent_message": "O usuário negou esta ação pelo TAPKEY no celular. Não tente contornar; "
                                    "explique o que pretendia fazer e pergunte como proceder."}
        elif dec == "ask":
            out = {"continue": True, "permission": "ask",
                   "user_message": "Sem resposta do celular a tempo (TAPKEY): confirme na tela."}
    elif ev == "stop" and (resp or {}).get("followup_message"):
        out = {"followup_message": str(resp["followup_message"])[:4000]}
    return out


def post(info, payload, timeout):
    req = urllib.request.Request(
        "http://127.0.0.1:%d/hook" % int(info["port"]),
        data=json.dumps(payload, ensure_ascii=False).encode("utf-8"),
        headers={"Content-Type": "application/json", "X-Hook-Secret": info["secret"]})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.loads(r.read() or b"{}")


def run_hook(stdin_text, home=None):
    ev = ""
    try:
        d = json.loads(stdin_text or "{}")
        ev = str(d.get("hook_event_name") or os.environ.get("TAPKEY_HOOK_EVENT", ""))
        d["hook_event_name"] = ev
        info = load_info(home)
        timeout = 66 if ev in BLOCKING else 3
        resp = post(info, normalize(d), timeout)
        return render(ev, resp)
    except Exception:
        return neutral(ev)  # fail-open


# ---------------- instalação em ~/.cursor/hooks.json ----------------
def hooks_path(home=None):
    return os.path.join(home or os.path.expanduser("~"), ".cursor", "hooks.json")


def script_dest(home=None):
    return os.path.join(config_dir(home), "hooks", MARK)


def our_command(home=None):
    return "/usr/bin/python3 %s" % script_dest(home)


def _is_ours(entry):
    return isinstance(entry, dict) and MARK in str(entry.get("command", ""))


def _read_cfg(path):
    if not os.path.exists(path):
        return None
    with open(path) as f:
        txt = f.read()
    if not txt.strip():
        return {}
    return json.loads(txt)  # ValueError se estiver inválido: NÃO mexemos


def _strip(cfg):
    cfg = json.loads(json.dumps(cfg))
    hooks = cfg.get("hooks")
    if isinstance(hooks, dict):
        for ev in list(hooks):
            if isinstance(hooks[ev], list):
                hooks[ev] = [e for e in hooks[ev] if not _is_ours(e)]
                if not hooks[ev]:
                    del hooks[ev]
    return cfg


def merged(cfg, home=None):
    cfg = _strip(cfg if isinstance(cfg, dict) else {})
    cfg.setdefault("version", 1)
    hooks = cfg.setdefault("hooks", {})
    for ev in EVENTS:
        entry = {"command": our_command(home), "timeout": 70 if ev in BLOCKING else 10}
        hooks.setdefault(ev, []).append(entry)
    return cfg


def _dump(cfg):
    return json.dumps(cfg, indent=2, ensure_ascii=False) + "\n"


def diff_text(home=None):
    p = hooks_path(home)
    cur = _read_cfg(p)
    before = _dump(cur) if cur is not None else ""
    after = _dump(merged(cur, home))
    return "".join(difflib.unified_diff(before.splitlines(True), after.splitlines(True),
                                        "hooks.json (atual)", "hooks.json (com TAPKEY)"))


def status(home=None):
    p = hooks_path(home)
    try:
        cfg = _read_cfg(p)
    except ValueError:
        return {"installed": False, "error": "hooks.json inválido"}
    n = 0
    if isinstance(cfg, dict) and isinstance(cfg.get("hooks"), dict):
        for lst in cfg["hooks"].values():
            if isinstance(lst, list):
                n += sum(1 for e in lst if _is_ours(e))
    return {"installed": n >= len(EVENTS), "entries": n, "path": p}


def install(home=None):
    p = hooks_path(home)
    try:
        cur = _read_cfg(p)
    except ValueError as ex:
        return False, "O ~/.cursor/hooks.json atual não é um JSON válido; não alterei nada (%s)." % ex
    os.makedirs(os.path.dirname(p), exist_ok=True)
    dest = script_dest(home)
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    shutil.copyfile(os.path.abspath(__file__), dest)
    os.chmod(dest, 0o755)
    state_p = os.path.join(config_dir(home), "cursor_hooks_state.json")
    backup = None
    if cur is not None:
        backup = "%s.tapkey-backup-%s" % (p, time.strftime("%Y%m%d-%H%M%S"))
        shutil.copyfile(p, backup)
    new = merged(cur, home)
    tmp = p + ".tapkey-tmp"
    with open(tmp, "w") as f:
        f.write(_dump(new))
    os.replace(tmp, p)
    created = cur is None
    try:
        created = created or bool(json.load(open(state_p)).get("created_file"))
    except (OSError, ValueError):
        pass
    with open(state_p, "w") as f:
        json.dump({"created_file": created, "backup": backup}, f)
    return True, "Hooks do TAPKEY instalados em %s%s." % (p, " (backup: %s)" % backup if backup else "")


def uninstall(home=None):
    p = hooks_path(home)
    state_p = os.path.join(config_dir(home), "cursor_hooks_state.json")
    try:
        cur = _read_cfg(p)
    except ValueError as ex:
        return False, "hooks.json inválido; não alterei nada (%s)." % ex
    msg = "Nada a remover."
    if cur is not None:
        new = _strip(cur)
        created = False
        try:
            created = bool(json.load(open(state_p)).get("created_file"))
        except (OSError, ValueError):
            pass
        empty = not new.get("hooks") and set(new.keys()) <= {"version", "hooks"}
        if empty and created:
            os.remove(p)
            msg = "Hooks do TAPKEY removidos (arquivo criado por nós foi apagado)."
        else:
            tmp = p + ".tapkey-tmp"
            with open(tmp, "w") as f:
                f.write(_dump(new))
            os.replace(tmp, p)
            msg = "Hooks do TAPKEY removidos; o restante do hooks.json foi mantido."
    for x in (script_dest(home), state_p):
        try:
            os.remove(x)
        except OSError:
            pass
    return True, msg


def main(argv):
    home = None
    if "--home" in argv:
        i = argv.index("--home")
        home = argv[i + 1]
        del argv[i:i + 2]
    cmd = argv[1] if len(argv) > 1 else ""
    if cmd in ("install", "uninstall", "status", "diff"):
        if cmd == "diff":
            try:
                print(diff_text(home) or "(sem mudanças)")
            except ValueError as ex:
                print("hooks.json inválido: %s" % ex)
                return 1
            return 0
        if cmd == "status":
            print(json.dumps(status(home)))
            return 0
        ok, msg = (install if cmd == "install" else uninstall)(home)
        print(msg)
        return 0 if ok else 1
    # modo hook: nunca falha
    try:
        text = sys.stdin.read()
    except Exception:
        text = ""
    out = run_hook(text, home)
    sys.stdout.write(json.dumps(out, ensure_ascii=False))
    sys.stdout.flush()
    return 0


if __name__ == "__main__":
    try:
        code = main(sys.argv)
    except Exception:
        sys.stdout.write("{}")
        code = 0
    sys.exit(code)
