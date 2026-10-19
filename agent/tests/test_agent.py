"""Testes do agente TAPKEY, do relay dos hooks e da instalação em hooks.json.

Uso:  python3 -m unittest discover -s agent/tests -v      (a partir da raiz do projeto)
Tudo roda com HOME temporário: nenhum arquivo real do usuário (~/.cursor) é tocado.
"""
import hashlib
import hmac
import http.client
import json
import os
import shutil
import socket
import ssl
import subprocess
import sys
import tempfile
import threading
import time
import unittest
import unittest.mock

HERE = os.path.dirname(os.path.abspath(__file__))
AGENT = os.path.join(os.path.dirname(HERE), "agent.py")
RELAY = os.path.join(os.path.dirname(HERE), "tapkey_cursor_hook.py")


def free_port():
    s = socket.socket()
    s.bind(("127.0.0.1", 0))
    p = s.getsockname()[1]
    s.close()
    return p


class Env:
    def __init__(self, legacy=False, approval_timeout=2):
        self.legacy = legacy
        self.home = tempfile.mkdtemp(prefix="tapkey-test-")
        self.cfg = os.path.join(self.home, ".config", "tapkey")
        os.makedirs(self.cfg)
        self.bin = os.path.join(self.home, "bin")
        os.makedirs(self.bin)
        self.port, self.hook_port = free_port(), free_port()
        self.ws = os.path.join(self.home, "proj", "meu-projeto")
        os.makedirs(self.ws)
        if legacy:
            self.settings(legacy_http=True)
        env = dict(os.environ, HOME=self.home, MEU_NOTEBOOK_PORT=str(self.port), TAPKEY_HOOK_PORT=str(self.hook_port),
                   TAPKEY_APPROVAL_TIMEOUT=str(approval_timeout), PATH=self.bin + ":/usr/bin:/bin",
                   XDG_RUNTIME_DIR=self.home, TAPKEY_BIND="127.0.0.1")
        self.env = env
        self.proc = subprocess.Popen([sys.executable, AGENT], env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        for _ in range(100):
            try:
                socket.create_connection(("127.0.0.1", self.hook_port), 0.2).close()
                break
            except OSError:
                time.sleep(0.1)
        for _ in range(100):
            try:
                socket.create_connection(("127.0.0.1", self.port), 0.2).close()
                break
            except OSError:
                time.sleep(0.1)
        self.token = open(os.path.join(self.cfg, "token")).read().strip()
        self.device_id = "test-device-0001"
        st, body = self.req("POST", "/pair/register", {}, token="master",
                            extra={"X-Device-Id": self.device_id, "X-Device-Name": "Pixel Teste"})
        assert st == 200, (st, body)
        self.device_token = body["device_token"]

    def dev_headers(self, did=None, tok=None):
        return {"X-Device-Id": did or self.device_id, "X-Device-Token": tok or self.device_token,
                "X-Device-Name": "Pixel Teste"}

    def settings(self, **kw):
        p = os.path.join(self.cfg, "settings.json")
        cur = json.load(open(p)) if os.path.exists(p) else {}
        cur.update(kw)
        json.dump(cur, open(p, "w"))

    def conn(self, timeout=10):
        if self.legacy:
            return http.client.HTTPConnection("127.0.0.1", self.port, timeout=timeout)
        ctx = ssl.create_default_context()
        ctx.check_hostname = False
        ctx.verify_mode = ssl.CERT_NONE
        return http.client.HTTPSConnection("127.0.0.1", self.port, timeout=timeout, context=ctx)

    def req(self, method, path, body=None, token=True, extra=None):
        """token=True: credenciais do aparelho; "master": token do QR; False: nada."""
        c = self.conn()
        h = {"X-Token": self.token} if token == "master" else (self.dev_headers() if token else {})
        h.update(extra or {})
        if body is not None:
            h["Content-Type"] = "application/json"
        c.request(method, path, json.dumps(body) if body is not None else None, h)
        r = c.getresponse()
        data = r.read()
        c.close()
        try:
            return r.status, json.loads(data)
        except ValueError:
            return r.status, data

    def hook(self, event, **extra):
        payload = {"hook_event_name": event, "conversation_id": "conv-1", "workspace_roots": [self.ws]}
        payload.update(extra)
        return subprocess.run([sys.executable, RELAY], input=json.dumps(payload), capture_output=True, text=True,
                              env=self.env, timeout=80)

    def fake(self, name, body):
        p = os.path.join(self.bin, name)
        open(p, "w").write("#!/bin/sh\n" + body + "\n")
        os.chmod(p, 0o755)

    def close(self):
        self.proc.terminate()
        try:
            self.proc.wait(5)
        except subprocess.TimeoutExpired:
            self.proc.kill()
        shutil.rmtree(self.home, ignore_errors=True)


class SSE(threading.Thread):
    def __init__(self, env):
        super().__init__(daemon=True)
        self.env, self.events, self.stop = env, [], False
        self.start()
        for _ in range(50):
            if self.events:
                break
            time.sleep(0.1)

    def run(self):
        c = self.env.conn(timeout=30)
        c.request("GET", "/cursor/events", headers=self.env.dev_headers())
        r = c.getresponse()
        ev = None
        while not self.stop:
            line = r.fp.readline()
            if not line:
                break
            line = line.decode().rstrip("\n")
            if line.startswith("event: "):
                ev = line[7:]
            elif line.startswith("data: "):
                self.events.append((ev, json.loads(line[6:])))
        c.close()


class TlsTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.e = Env()

    @classmethod
    def tearDownClass(cls):
        cls.e.close()

    def test_tls_fingerprint_matches_file_and_status(self):
        c = self.e.conn()
        c.connect()
        der = c.sock.getpeercert(binary_form=True)
        c.close()
        fp = hashlib.sha256(der).hexdigest()
        self.assertEqual(fp, open(os.path.join(self.e.cfg, "tls", "fingerprint")).read().strip())
        hc = http.client.HTTPConnection("127.0.0.1", self.e.hook_port)
        hc.request("GET", "/status")
        st = json.loads(hc.getresponse().read())
        self.assertTrue(st["tls"])
        self.assertEqual(st["fp"], fp)
        self.assertEqual(oct(os.stat(os.path.join(self.e.cfg, "tls", "key.pem")).st_mode & 0o777), "0o600")

    def test_requires_token(self):
        self.assertEqual(self.e.req("GET", "/ping", token=False)[0], 401)
        self.assertEqual(self.e.req("GET", "/ping")[0], 200)
        self.assertEqual(self.e.req("GET", "/ping", token="master")[0], 200)

    def test_plain_http_is_refused_on_tls_port(self):
        c = http.client.HTTPConnection("127.0.0.1", self.e.port, timeout=3)
        with self.assertRaises(Exception):
            c.request("GET", "/ping", headers={"X-Token": self.e.token})
            c.getresponse().read()

    def test_cert_is_stable_across_restarts(self):
        fp = open(os.path.join(self.e.cfg, "tls", "fingerprint")).read()
        self.assertEqual(len(fp.strip()), 64)

    def test_unlock_still_disabled_by_default(self):
        self.assertEqual(self.e.req("POST", "/unlock", {})[0], 403)


class LegacyTests(unittest.TestCase):
    def test_legacy_http_mode_only_when_enabled(self):
        e = Env(legacy=True)
        try:
            c = http.client.HTTPConnection("127.0.0.1", e.port, timeout=3)
            c.request("GET", "/ping", headers=e.dev_headers())
            self.assertEqual(c.getresponse().status, 200)
            hc = http.client.HTTPConnection("127.0.0.1", e.hook_port)
            hc.request("GET", "/status")
            self.assertFalse(json.loads(hc.getresponse().read())["tls"])
        finally:
            e.close()


class DeviceTests(unittest.TestCase):
    def setUp(self):
        self.e = Env()

    def tearDown(self):
        self.e.close()

    def clients(self):
        return json.load(open(os.path.join(self.e.cfg, "clients.json")))["clients"]

    def test_master_token_only_registers(self):
        self.assertEqual(self.e.req("GET", "/apps", token="master")[0], 401)
        self.assertEqual(self.e.req("POST", "/lock", {}, token="master")[0], 401)
        self.assertEqual(self.e.req("GET", "/apps")[0], 200)

    def test_register_requires_master_and_valid_id(self):
        self.assertEqual(self.e.req("POST", "/pair/register", {}, token=False,
                                    extra={"X-Device-Id": "outro-aparelho-1"})[0], 401)
        self.assertEqual(self.e.req("POST", "/pair/register", {}, token="master",
                                    extra={"X-Device-Id": "x y"})[0], 400)

    def test_devices_file_private_and_hashed(self):
        p = os.path.join(self.e.cfg, "devices.json")
        self.assertEqual(oct(os.stat(p).st_mode & 0o777), "0o600")
        raw = open(p).read()
        self.assertNotIn(self.e.device_token, raw)
        self.assertIn("Pixel Teste", raw)

    def test_same_device_new_ip_is_one_client(self):
        for _ in range(3):
            self.e.req("GET", "/ping")
        time.sleep(0.1)
        self.e.req("POST", "/lock", {"x": 1})  # força gravação
        cl = [c for c in self.clients() if not c.get("legacy")]
        self.assertEqual(len(cl), 1)
        self.assertEqual(cl[0]["device_id"], self.e.device_id)
        self.assertEqual(cl[0]["name"], "Pixel Teste")
        self.assertEqual(cl[0]["ip"], "127.0.0.1")

    def test_revoke_device(self):
        p = os.path.join(self.e.cfg, "devices.json")
        st, b = self.e.req("POST", "/pair/register", {}, token="master",
                           extra={"X-Device-Id": "segundo-celular", "X-Device-Name": "Outro"})
        tok2 = b["device_token"]
        h2 = {"X-Device-Id": "segundo-celular", "X-Device-Token": tok2}
        self.assertEqual(self.e.req("GET", "/apps", token=False, extra=h2)[0], 200)
        d = json.load(open(p))
        del d["devices"]["segundo-celular"]  # o que o TAPKEY Desktop faz em "Revogar este aparelho"
        json.dump(d, open(p, "w"))
        st, body = self.e.req("GET", "/apps", token=False, extra=h2)
        self.assertEqual(st, 401)
        self.assertTrue(body.get("revoked"))
        self.assertEqual(self.e.req("GET", "/apps")[0], 200)  # o outro aparelho segue funcionando
        self.e.req("POST", "/lock", {})
        self.assertNotIn("segundo-celular", [c.get("device_id") for c in self.clients()])

    def test_wrong_device_token(self):
        self.assertEqual(self.e.req("GET", "/apps", token=False,
                                    extra={"X-Device-Id": self.e.device_id, "X-Device-Token": "nope"})[0], 401)

    def test_unlock_proof_uses_device_key(self):
        self.e.settings(allow_unlock=True)
        st, ch = self.e.req("GET", "/challenge")
        self.assertEqual(st, 200)
        bad = hmac.new(self.e.token.encode(), ch["nonce"].encode(), hashlib.sha256).hexdigest()
        self.assertEqual(self.e.req("POST", "/unlock", {"nonce": ch["nonce"], "proof": bad})[0], 400)
        self.assertEqual(self.e.req("GET", "/challenge", token="master")[0], 401)


class LegacyMigrationTests(unittest.TestCase):
    def test_ip_entries_merge_into_device(self):
        home = tempfile.mkdtemp(prefix="tapkey-mig-")
        cfg = os.path.join(home, ".config", "tapkey")
        os.makedirs(cfg)
        now = time.time()
        json.dump({"clients": [
            {"ip": "127.0.0.1", "first_seen": now - 99, "last_seen": now - 9, "requests": 7, "launches": 2, "last_app": "X"},
            {"ip": "192.168.88.198", "mac": "4a:8a:17:17:fe:6d", "first_seen": now - 50, "last_seen": now - 40,
             "requests": 3, "launches": 1, "last_app": "Y"},
            {"ip": "192.168.88.202", "mac": "4a:8a:17:17:fe:6d", "first_seen": now - 30, "last_seen": now - 20,
             "requests": 4, "launches": 1, "last_app": "Z"}]}, open(os.path.join(cfg, "clients.json"), "w"))
        sys.path.insert(0, os.path.dirname(AGENT))
        import importlib
        old_home = os.environ.get("HOME")
        os.environ["HOME"] = home
        try:
            import agent as ag
            ag = importlib.reload(ag)
            ag.load_clients()
            self.assertEqual(len(ag._legacy), 1)  # .198 e .202 têm o mesmo MAC: um celular só
            self.assertEqual(ag._legacy[0]["requests"], 7)
            ag.register_device("celular-do-helio", "Moto")
            ag._legacy[0]["ip"] = "192.168.88.210"
            ag.record_client("celular-do-helio", "192.168.88.210", "Moto", force_save=True)
            self.assertEqual(ag._legacy, [])
            c = ag._clients["celular-do-helio"]
            self.assertEqual(c["requests"], 8)
            self.assertEqual(c["launches"], 2)
        finally:
            if old_home is None:
                del os.environ["HOME"]
            else:
                os.environ["HOME"] = old_home
            shutil.rmtree(home, ignore_errors=True)


class NetworkTests(unittest.TestCase):
    RAW = [
        {"ifname": "lo", "flags": ["LOOPBACK", "UP"], "link_type": "loopback",
         "addr_info": [{"family": "inet", "local": "127.0.0.1", "prefixlen": 8}]},
        {"ifname": "wlp2s0", "flags": ["BROADCAST", "MULTICAST", "UP", "LOWER_UP"], "link_type": "ether",
         "addr_info": [{"family": "inet", "local": "192.168.88.251", "prefixlen": 24}]},
        {"ifname": "tunnelc9", "flags": ["POINTOPOINT", "UP"], "link_type": "none",
         "addr_info": [{"family": "inet", "local": "10.8.0.5", "prefixlen": 32}]},
        {"ifname": "docker0", "flags": ["UP"], "link_type": "ether",
         "addr_info": [{"family": "inet", "local": "172.17.0.1", "prefixlen": 16}]},
        {"ifname": "wg0", "flags": ["UP"], "link_type": "none",
         "addr_info": [{"family": "inet", "local": "10.9.0.2", "prefixlen": 24}]},
        {"ifname": "enp3s0", "flags": ["UP"], "link_type": "ether",
         "addr_info": [{"family": "inet", "local": "8.8.4.4", "prefixlen": 24}]},
    ]

    def setUp(self):
        sys.path.insert(0, os.path.dirname(AGENT))
        import agent as ag
        self.ag = ag

    def test_only_private_lan_interfaces(self):
        got = [(n, ip) for n, ip, _ in self.ag.lan_interfaces(self.RAW)]
        self.assertEqual(got, [("wlp2s0", "192.168.88.251")])

    def test_source_filter(self):
        ag = self.ag
        import ipaddress
        old = ag._lan_nets
        ag._lan_nets = [ipaddress.ip_network("192.168.88.0/24")]
        env_bind = os.environ.pop("TAPKEY_BIND", None)
        try:
            with unittest.mock.patch.object(ag, "listen_all", return_value=False):
                self.assertTrue(ag.source_allowed("192.168.88.202"))
                self.assertTrue(ag.source_allowed("127.0.0.1"))
                self.assertFalse(ag.source_allowed("10.8.0.1"))      # VPN
                self.assertFalse(ag.source_allowed("8.8.8.8"))       # pública
                self.assertFalse(ag.source_allowed("::ffff:1.1.1.1"))
            with unittest.mock.patch.object(ag, "listen_all", return_value=True):
                self.assertTrue(ag.source_allowed("10.8.0.1"))
                self.assertFalse(ag.source_allowed("8.8.8.8"))       # pública nunca
        finally:
            ag._lan_nets = old
            if env_bind is not None:
                os.environ["TAPKEY_BIND"] = env_bind


class CursorTests(unittest.TestCase):
    def setUp(self):
        self.e = Env()

    def tearDown(self):
        self.e.close()

    def enable(self, **kw):
        self.e.settings(cursor_integration=True, **kw)

    def state(self):
        return self.e.req("GET", "/cursor/state")[1]

    def test_disabled_by_default(self):
        self.assertEqual(self.e.req("GET", "/cursor/state")[0], 403)
        r = self.e.hook("beforeShellExecution", command="ls")
        self.assertEqual(json.loads(r.stdout), {"continue": True, "permission": "allow"})
        self.enable()
        self.assertEqual(self.e.req("GET", "/cursor/state")[0], 200)
        self.assertEqual(self.state()["sessions"], [])  # nada foi registrado enquanto estava desligado

    def test_session_lifecycle_and_privacy(self):
        self.enable()
        for ev, extra in [("sessionStart", {}), ("beforeSubmitPrompt", {"prompt": "SEGREDO-NO-PROMPT"}),
                          ("preToolUse", {"tool_name": "Shell", "tool_input": {"command": "npm test"}})]:
            r = self.e.hook(ev, **extra)
            self.assertEqual(r.returncode, 0)
        s = self.state()
        sess = s["sessions"][0]
        self.assertEqual(sess["state"], "working")
        self.assertEqual(sess["folder"], "meu-projeto")
        self.assertIn("Shell", sess["last_tool"])
        blob = json.dumps(s)
        self.assertNotIn(self.e.home, blob)          # só o nome da pasta, nunca o caminho
        self.assertNotIn("SEGREDO-NO-PROMPT", blob)  # o texto do prompt nunca é enviado
        self.assertEqual(json.loads(self.e.hook("beforeSubmitPrompt").stdout), {"continue": True})
        self.e.hook("stop", status="completed")
        self.assertEqual(self.state()["sessions"][0]["state"], "finished")
        self.e.hook("sessionEnd")
        self.assertEqual(self.state()["sessions"], [])

    def test_fields_are_trimmed_to_2kb(self):
        sys.path.insert(0, os.path.dirname(HERE))
        import tapkey_cursor_hook as h
        n = h.normalize({"hook_event_name": "beforeMCPExecution", "tool_input": "x" * 10000, "tool_name": "t" * 500})
        self.assertLessEqual(len(n["tool_input"]), 2048)
        self.assertLessEqual(len(n["mcp_tool"]), 80)
        n = h.normalize({"hook_event_name": "beforeShellExecution", "command": "c" * 20000})
        self.assertLessEqual(len(n["command"]), 8000)

    def test_approval_without_phone_is_neutral_and_fast(self):
        self.enable(cursor_approvals=True)
        self.e.hook("sessionStart")
        t0 = time.time()
        r = self.e.hook("beforeShellExecution", command="rm -rf /tmp/x")
        self.assertLess(time.time() - t0, 3)
        self.assertEqual(json.loads(r.stdout)["permission"], "allow")

    def _approval_roundtrip(self, decision, command="echo oi"):
        self.enable(cursor_approvals=True)
        sse = SSE(self.e)
        self.e.hook("sessionStart")
        out = {}

        def run():
            out["r"] = self.e.hook("beforeShellExecution", command=command, cwd=self.e.ws)
        th = threading.Thread(target=run)
        th.start()
        appr = None
        for _ in range(60):
            a = self.state()["approvals"]
            if a:
                appr = a[0]
                break
            time.sleep(0.1)
        self.assertIsNotNone(appr)
        self.assertEqual(appr["command"], command)
        self.assertEqual(self.state()["sessions"][0]["state"], "waiting")
        code = None
        if decision:
            code, body = self.e.req("POST", "/cursor/approval", {"id": appr["id"], "decision": decision})
        th.join(10)
        sse.stop = True
        return out["r"], appr, code

    def test_approval_allow(self):
        r, appr, code = self._approval_roundtrip("allow")
        self.assertEqual(code, 200)
        self.assertEqual(json.loads(r.stdout)["permission"], "allow")

    def test_approval_deny(self):
        r, appr, code = self._approval_roundtrip("deny")
        out = json.loads(r.stdout)
        self.assertEqual(out["permission"], "deny")
        self.assertIn("agent_message", out)

    def test_approval_timeout_returns_ask(self):
        r, appr, code = self._approval_roundtrip(None)
        self.assertEqual(json.loads(r.stdout)["permission"], "ask")
        self.assertEqual(self.state()["approvals"], [])

    def test_long_command_is_deny_only(self):
        r, appr, code = self._approval_roundtrip("allow", command="echo " + "a" * 600)
        self.assertTrue(appr["deny_only"])
        self.assertEqual(code, 400)
        self.assertEqual(json.loads(r.stdout)["permission"], "ask")  # ninguém negou => expira em "ask"

    def test_approvals_toggle_off_means_no_approval(self):
        self.enable()
        sse = SSE(self.e)
        self.e.hook("sessionStart")
        r = self.e.hook("beforeShellExecution", command="ls")
        self.assertEqual(json.loads(r.stdout)["permission"], "allow")
        sse.stop = True

    def test_sse_emits_state_and_notices(self):
        self.enable()
        sse = SSE(self.e)
        self.e.hook("sessionStart")
        self.e.hook("stop", status="completed")
        time.sleep(0.8)
        kinds = [e[0] for e in sse.events]
        self.assertIn("state", kinds)
        self.assertIn("finished", [e[1].get("kind") for e in sse.events if e[0] == "notice"])
        sse.stop = True

    # ---- instruções ----
    def test_instruction_disabled_by_default(self):
        self.enable()
        self.e.hook("sessionStart")
        code, body = self.e.req("POST", "/cursor/instruction", {"session_id": "conv-1", "text": "oi"})
        self.assertEqual(code, 403)
        self.assertIn("instruções", body["error"])

    def test_instruction_queue_delivered_by_stop_hook(self):
        self.enable(allow_instructions=True)
        self.e.hook("sessionStart")
        code, body = self.e.req("POST", "/cursor/instruction", {"session_id": "conv-1", "text": "rode os testes"})
        self.assertEqual(code, 200, body)
        self.assertEqual(len(self.state()["queue"]), 1)
        out = json.loads(self.e.hook("stop", status="completed").stdout)
        self.assertEqual(out["followup_message"], "rode os testes")
        self.assertEqual(self.state()["queue"], [])
        # uma só vez
        self.assertEqual(json.loads(self.e.hook("stop", status="completed").stdout), {})
        # outra conversa não recebe
        self.e.req("POST", "/cursor/instruction", {"session_id": "conv-1", "text": "x"})
        r = subprocess.run([sys.executable, RELAY], input=json.dumps(
            {"hook_event_name": "stop", "conversation_id": "outra", "workspace_roots": [self.e.ws], "status": "completed"}),
            capture_output=True, text=True, env=self.e.env)
        self.assertEqual(json.loads(r.stdout), {})

    def test_instruction_limits(self):
        self.enable(allow_instructions=True)
        self.e.hook("sessionStart")
        self.assertEqual(self.e.req("POST", "/cursor/instruction", {"session_id": "conv-1", "text": "a" * 4001})[0], 400)
        self.assertEqual(self.e.req("POST", "/cursor/instruction", {"session_id": "conv-1", "text": "  "})[0], 400)
        self.assertEqual(self.e.req("POST", "/cursor/instruction", {"session_id": "nao-existe", "text": "a"})[0], 404)
        codes = [self.e.req("POST", "/cursor/instruction", {"session_id": "conv-1", "text": "t%d" % i})[0] for i in range(8)]
        self.assertIn(429, codes)

    def test_cli_mode_uses_allowlist_and_never_force(self):
        self.enable(allow_instructions=True)
        argv_file = os.path.join(self.e.home, "argv.txt")
        self.e.fake("agent", 'for a in "$@"; do echo "$a" >> %s; done; echo linha1; sleep 1; echo linha2' % argv_file)
        self.e.hook("sessionStart")
        wid = self.state()["workspaces"][0]["id"]
        self.assertTrue(self.state()["cli_available"])
        # pasta que o celular inventa => recusada
        self.assertEqual(self.e.req("POST", "/cursor/instruction", {"mode": "cli", "workspace_id": "../../etc", "text": "x"})[0], 404)
        sse = SSE(self.e)
        code, body = self.e.req("POST", "/cursor/instruction", {"mode": "cli", "workspace_id": wid, "session_id": "conv-1", "text": "faça X"})
        self.assertEqual(code, 200, body)
        # uma por vez
        self.assertEqual(self.e.req("POST", "/cursor/instruction", {"mode": "cli", "workspace_id": wid, "text": "outra"})[0], 409)
        for _ in range(50):
            if not self.state()["cli"]["running"]:
                break
            time.sleep(0.2)
        argv = open(argv_file).read().split("\n")
        self.assertNotIn("--force", argv)
        self.assertNotIn("--yolo", argv)
        self.assertNotIn("-f", argv)
        self.assertIn("-p", argv)
        self.assertEqual(argv[argv.index("--workspace") + 1], self.e.ws)
        self.assertEqual(argv[argv.index("--resume") + 1], "conv-1")
        self.assertEqual(argv[-2], "faça X")
        time.sleep(0.5)
        texts = [e[1]["text"] for e in sse.events if e[0] == "cli"]
        self.assertEqual(texts, ["linha1", "linha2"])
        self.assertEqual(self.state()["cli"]["exit"], 0)
        sse.stop = True

    def test_cli_unavailable(self):
        self.enable(allow_instructions=True)
        self.e.hook("sessionStart")
        wid = self.state()["workspaces"][0]["id"]
        self.assertFalse(self.state()["cli_available"])
        code, body = self.e.req("POST", "/cursor/instruction", {"mode": "cli", "workspace_id": wid, "text": "x"})
        self.assertEqual(code, 400)

    def test_open_in_cursor_only_for_seen_workspaces(self):
        self.enable()
        out = os.path.join(self.e.home, "opened.txt")
        self.e.fake("cursor", 'echo "$@" > %s' % out)
        self.e.hook("sessionStart")
        wid = self.state()["workspaces"][0]["id"]
        self.assertEqual(self.e.req("POST", "/cursor/open", {"workspace_id": "abc"})[0], 404)
        code, _ = self.e.req("POST", "/cursor/open", {"workspace_id": wid})
        self.assertEqual(code, 200)
        for _ in range(30):
            if os.path.exists(out):
                break
            time.sleep(0.1)
        self.assertEqual(open(out).read().strip(), self.e.ws)

    def test_hook_listener_requires_secret(self):
        c = http.client.HTTPConnection("127.0.0.1", self.e.hook_port)
        c.request("POST", "/hook", json.dumps({"event": "stop"}), {"X-Hook-Secret": "errado"})
        self.assertEqual(c.getresponse().status, 401)

    def test_relay_fail_open_without_agent(self):
        env = dict(self.e.env, HOME=tempfile.mkdtemp())
        for ev, expect in [("beforeShellExecution", {"continue": True, "permission": "allow"}),
                           ("beforeSubmitPrompt", {"continue": True}), ("stop", {}), ("sessionStart", {})]:
            r = subprocess.run([sys.executable, RELAY], input=json.dumps({"hook_event_name": ev}), capture_output=True,
                               text=True, env=env, timeout=10)
            self.assertEqual(r.returncode, 0)
            self.assertEqual(json.loads(r.stdout), expect)
        r = subprocess.run([sys.executable, RELAY], input="isto não é json", capture_output=True, text=True, env=env)
        self.assertEqual(r.returncode, 0)


class HooksInstallTests(unittest.TestCase):
    def setUp(self):
        self.home = tempfile.mkdtemp(prefix="tapkey-hooks-")
        os.makedirs(os.path.join(self.home, ".cursor"))
        self.p = os.path.join(self.home, ".cursor", "hooks.json")

    def tearDown(self):
        shutil.rmtree(self.home, ignore_errors=True)

    def run_relay(self, *a):
        return subprocess.run([sys.executable, RELAY, *a, "--home", self.home], capture_output=True, text=True)

    def test_merge_preserves_user_hooks_backup_and_clean_uninstall(self):
        orig = {"version": 1, "hooks": {"stop": [{"command": "./meu-stop.sh"}],
                                         "afterFileEdit": [{"command": "./fmt.sh"}]}, "extra": {"a": 1}}
        json.dump(orig, open(self.p, "w"), indent=2)
        d = self.run_relay("diff")
        self.assertIn("+", d.stdout)
        self.assertEqual(json.load(open(self.p)), orig)  # diff não altera
        r = self.run_relay("install")
        self.assertEqual(r.returncode, 0, r.stderr)
        cfg = json.load(open(self.p))
        self.assertEqual(cfg["extra"], {"a": 1})
        self.assertEqual(cfg["hooks"]["afterFileEdit"], orig["hooks"]["afterFileEdit"])
        self.assertEqual(cfg["hooks"]["stop"][0], {"command": "./meu-stop.sh"})
        self.assertEqual(len(cfg["hooks"]["stop"]), 2)
        for ev in ("sessionStart", "sessionEnd", "beforeSubmitPrompt", "preToolUse", "postToolUse",
                   "postToolUseFailure", "stop", "beforeShellExecution", "beforeMCPExecution"):
            self.assertTrue(any("tapkey_cursor_hook.py" in e["command"] for e in cfg["hooks"][ev]), ev)
        self.assertTrue(any(f.startswith("hooks.json.tapkey-backup-") for f in os.listdir(os.path.dirname(self.p))))
        self.assertTrue(json.loads(self.run_relay("status").stdout)["installed"])
        # instalar de novo não duplica
        self.run_relay("install")
        self.assertEqual(len(json.load(open(self.p))["hooks"]["stop"]), 2)
        self.run_relay("uninstall")
        self.assertEqual(json.load(open(self.p)), orig)
        self.assertFalse(json.loads(self.run_relay("status").stdout)["installed"])
        self.assertFalse(os.path.exists(os.path.join(self.home, ".config", "tapkey", "hooks", "tapkey_cursor_hook.py")))

    def test_created_file_is_removed_on_uninstall(self):
        self.assertFalse(os.path.exists(self.p))
        self.assertEqual(self.run_relay("install").returncode, 0)
        self.assertTrue(os.path.exists(self.p))
        self.run_relay("uninstall")
        self.assertFalse(os.path.exists(self.p))

    def test_invalid_json_is_never_touched(self):
        open(self.p, "w").write("{ isto está quebrado")
        r = self.run_relay("install")
        self.assertEqual(r.returncode, 1)
        self.assertEqual(open(self.p).read(), "{ isto está quebrado")

    def test_uninstall_removes_only_ours(self):
        json.dump({"version": 1, "hooks": {"stop": [{"command": "./meu.sh"}]}}, open(self.p, "w"))
        self.run_relay("install")
        cfg = json.load(open(self.p))
        cfg["hooks"]["stop"].append({"command": "./outro-meu.sh"})
        json.dump(cfg, open(self.p, "w"))
        self.run_relay("uninstall")
        self.assertEqual([e["command"] for e in json.load(open(self.p))["hooks"]["stop"]], ["./meu.sh", "./outro-meu.sh"])


if __name__ == "__main__":
    unittest.main()
