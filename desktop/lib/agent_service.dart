import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

class ClientInfo {
  final String ip;
  final DateTime lastSeen;
  final DateTime firstSeen;
  final int requests;
  final int launches;
  final String lastApp;
  const ClientInfo(this.ip, this.firstSeen, this.lastSeen, this.requests, this.launches, this.lastApp);

  factory ClientInfo.fromJson(Map<String, dynamic> j) => ClientInfo(
        j['ip'] as String,
        DateTime.fromMillisecondsSinceEpoch(((j['first_seen'] as num) * 1000).round()),
        DateTime.fromMillisecondsSinceEpoch(((j['last_seen'] as num) * 1000).round()),
        (j['requests'] as num).toInt(),
        (j['launches'] as num).toInt(),
        (j['last_app'] ?? '') as String,
      );
}

class EventInfo {
  final DateTime time;
  final String ip;
  final String event;
  final bool ok;
  final String detail;
  const EventInfo(this.time, this.ip, this.event, this.ok, this.detail);

  factory EventInfo.fromJson(Map<String, dynamic> j) => EventInfo(
        DateTime.fromMillisecondsSinceEpoch(((j['t'] as num) * 1000).round()),
        (j['ip'] ?? '') as String,
        (j['event'] ?? '') as String,
        j['ok'] == true,
        (j['detail'] ?? '') as String,
      );
}

/// Controla o agente Python: iniciar/parar, token, autostart e status.
class AgentService extends ChangeNotifier {
  static final int port = int.tryParse(Platform.environment['TAPKEY_PORT'] ?? '') ?? 8765;
  final String home = Platform.environment['HOME'] ?? '/tmp';
  late final String configDir = '$home/.config/tapkey';
  late final String tokenFile = '$configDir/token';
  late final String clientsFile = '$configDir/clients.json';
  late final String autostartFile = '$home/.config/autostart/tapkey-desktop.desktop';

  String token = '';
  String lanIp = '127.0.0.1';
  bool running = false;
  bool busy = false;
  bool autostart = false;
  String? error;
  List<ClientInfo> clients = [];
  List<EventInfo> events = [];
  bool allowUnlock = false;
  bool legacyHttp = false;
  bool cursorApprovals = false;
  bool allowInstructions = false;
  bool cursorHooksInstalled = false;
  bool tls = true;
  String fingerprint = '';
  String cursorMsg = '';
  static int get hookPort => int.tryParse(Platform.environment['TAPKEY_HOOK_PORT'] ?? '') ?? port + 1;
  late final String settingsFile = '$configDir/settings.json';
  int totalLaunches = 0;
  int _lastLaunches = -1;
  void Function()? onNewLaunch;

  Process? _child;
  Timer? _timer;

  Future<void> init() async {
    await Directory(configDir).create(recursive: true);
    await _loadToken();
    autostart = File(autostartFile).existsSync();
    _loadSettings();
    await refreshHooksStatus();
    await refresh();
    _timer = Timer.periodic(const Duration(seconds: 2), (_) => refresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  /// QR de pareamento: com TLS leva o fingerprint SHA-256 do certificado (fixado pelo celular).
  String get pairUri {
    final name = Uri.encodeQueryComponent(Platform.localHostname);
    final t = Uri.encodeQueryComponent(token);
    if (tls && fingerprint.isNotEmpty) {
      return 'tapkey://pair?host=$lanIp&port=$port&fp=$fingerprint&token=$t&name=$name';
    }
    return 'tapkey://pair?host=$lanIp&port=$port&token=$t&name=$name';
  }

  String get address => '$lanIp:$port';

  Map<String, dynamic> _readSettings() {
    try {
      return jsonDecode(File(settingsFile).readAsStringSync()) as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }

  void _loadSettings() {
    final m = _readSettings();
    allowUnlock = m['allow_unlock'] == true;
    legacyHttp = m['legacy_http'] == true;
    cursorApprovals = m['cursor_approvals'] == true;
    allowInstructions = m['allow_instructions'] == true;
  }

  Future<void> _writeSetting(String key, Object value) async {
    final m = _readSettings()..[key] = value;
    await File(settingsFile).writeAsString(jsonEncode(m));
    await Process.run('chmod', ['600', settingsFile]);
  }

  /// "Permitir desbloqueio pelo celular" (padrão: desligado).
  Future<void> setAllowUnlock(bool on) async {
    await _writeSetting('allow_unlock', on);
    allowUnlock = on;
    notifyListeners();
  }

  Future<void> setCursorApprovals(bool on) async {
    await _writeSetting('cursor_approvals', on);
    cursorApprovals = on;
    notifyListeners();
  }

  Future<void> setAllowInstructions(bool on) async {
    await _writeSetting('allow_instructions', on);
    allowInstructions = on;
    notifyListeners();
  }

  /// "Modo HTTP legado" (sem criptografia). Exige reiniciar o agente.
  Future<void> setLegacyHttp(bool on) async {
    await _writeSetting('legacy_http', on);
    legacyHttp = on;
    notifyListeners();
    if (running) {
      await stopAgent();
      await startAgent();
    }
  }

  // ---- integração com o Cursor (hooks) ----
  String? _hookScript() {
    final agent = _findAgent();
    if (agent == null) return null;
    final p = '${File(agent).parent.path}/tapkey_cursor_hook.py';
    return File(p).existsSync() ? p : null;
  }

  Future<ProcessResult?> _hookCmd(String cmd) async {
    final p = _hookScript();
    if (p == null) return null;
    return Process.run('/usr/bin/python3', [p, cmd]);
  }

  Future<void> refreshHooksStatus() async {
    try {
      final r = await _hookCmd('status');
      if (r != null && r.exitCode == 0) {
        cursorHooksInstalled = (jsonDecode(r.stdout as String) as Map)['installed'] == true;
      }
    } catch (_) {}
    notifyListeners();
  }

  /// Diff do que será acrescentado a ~/.cursor/hooks.json (nada é gravado).
  Future<String> cursorDiff() async {
    final r = await _hookCmd('diff');
    if (r == null) return 'tapkey_cursor_hook.py não encontrado.';
    return (r.stdout as String).trim().isEmpty ? (r.stderr as String) : r.stdout as String;
  }

  /// Instala/remove os hooks. Só é chamado depois que o usuário confirma o diff.
  Future<bool> setCursorIntegration(bool on) async {
    final r = await _hookCmd(on ? 'install' : 'uninstall');
    if (r == null) {
      cursorMsg = 'tapkey_cursor_hook.py não encontrado.';
      notifyListeners();
      return false;
    }
    cursorMsg = (r.stdout as String).trim();
    final ok = r.exitCode == 0;
    if (ok) await _writeSetting('cursor_integration', on);
    await refreshHooksStatus();
    return ok;
  }

  /// Revoga todos os celulares: novo token + novo certificado (novo fingerprint).
  Future<void> revokeAll() async {
    final dir = Directory('$configDir/tls');
    if (dir.existsSync()) await dir.delete(recursive: true);
    fingerprint = '';
    await regenerateToken(restart: false);
    if (running) {
      await stopAgent();
      await startAgent();
    }
    notifyListeners();
  }

  Future<void> _loadToken() async {
    final f = File(tokenFile);
    if (f.existsSync() && f.readAsStringSync().trim().isNotEmpty) {
      token = f.readAsStringSync().trim();
    } else {
      await regenerateToken(restart: false);
    }
  }

  static String _randomToken() {
    final r = Random.secure();
    return base64Url.encode(List<int>.generate(18, (_) => r.nextInt(256))).replaceAll('=', '');
  }

  Future<void> regenerateToken({bool restart = true}) async {
    token = _randomToken();
    final f = File(tokenFile);
    await f.writeAsString('$token\n');
    await Process.run('chmod', ['600', tokenFile]);
    notifyListeners();
    if (restart && running) {
      await stopAgent();
      await startAgent();
    }
  }

  Future<String> _detectLanIp() async {
    try {
      final ifs = await NetworkInterface.list(type: InternetAddressType.IPv4);
      bool skip(String n) => RegExp(r'^(lo|docker|br-|veth|virbr|tun|tap|vmnet|tailscale|zt)').hasMatch(n);
      final good = ifs.where((i) => !skip(i.name) && i.addresses.isNotEmpty).toList();
      good.sort((a, b) {
        int rank(String n) => RegExp(r'^(wl|en|eth)').hasMatch(n) ? 0 : 1;
        return rank(a.name).compareTo(rank(b.name));
      });
      if (good.isNotEmpty) return good.first.addresses.first.address;
    } catch (_) {}
    return '127.0.0.1';
  }

  /// Pergunta ao listener de loopback do agente (HTTP simples, só 127.0.0.1).
  Future<bool> _ping() async {
    final c = HttpClient()..connectionTimeout = const Duration(seconds: 1);
    try {
      final req = await c.getUrl(Uri.parse('http://127.0.0.1:$hookPort/status'));
      final res = await req.close().timeout(const Duration(seconds: 2));
      final body = await res.transform(utf8.decoder).join();
      if (res.statusCode != 200) return false;
      final j = jsonDecode(body) as Map<String, dynamic>;
      tls = j['tls'] == true;
      fingerprint = (j['fp'] ?? '') as String;
      return true;
    } catch (_) {
      return false;
    } finally {
      c.close(force: true);
    }
  }

  Future<void> refresh() async {
    final ip = await _detectLanIp();
    final up = await _ping();
    _loadSettings();
    var list = <ClientInfo>[];
    var launches = 0;
    var evs = <EventInfo>[];
    try {
      final f = File(clientsFile);
      if (f.existsSync()) {
        final j = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
        list = (j['clients'] as List)
            .map((e) => ClientInfo.fromJson(e as Map<String, dynamic>))
            // "127.0.0.1" são testes locais (ping do próprio app)
            .where((c) => c.ip != '127.0.0.1')
            .toList();
        launches = list.fold(0, (a, c) => a + c.launches);
        evs = ((j['events'] ?? []) as List)
            .map((e) => EventInfo.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    } catch (_) {}
    final newEvent = evs.isNotEmpty && (events.isEmpty || evs.first.time != events.first.time);
    events = evs;
    final newLaunch = _lastLaunches >= 0 && launches > _lastLaunches;
    _lastLaunches = launches;
    totalLaunches = launches;
    if (newEvent) notifyListeners();
    if (up != running || ip != lanIp || list.length != clients.length || newLaunch ||
        (list.isNotEmpty && clients.isNotEmpty && list.first.lastSeen != clients.first.lastSeen)) {
      running = up;
      lanIp = ip;
      clients = list;
      notifyListeners();
    }
    if (newLaunch) onNewLaunch?.call();
  }

  String? _findAgent() {
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    final candidates = [
      Platform.environment['TAPKEY_AGENT'],
      '$exeDir/agent/agent.py',
      '/opt/tapkey-desktop/agent/agent.py',
      '$exeDir/../../../../../../agent/agent.py',
      '${Directory.current.path}/../agent/agent.py',
    ];
    for (final c in candidates) {
      if (c != null && File(c).existsSync()) return File(c).absolute.path;
    }
    return null;
  }

  Future<void> startAgent() async {
    if (busy) return;
    busy = true;
    error = null;
    notifyListeners();
    try {
      if (await _ping()) {
        running = true;
        return;
      }
      final path = _findAgent();
      if (path == null) {
        error = 'agent.py não encontrado.';
        return;
      }
      _child = await Process.start('/usr/bin/python3', [path],
          environment: {...Platform.environment, 'PYTHONUNBUFFERED': '1', 'MEU_NOTEBOOK_PORT': '$port'});
      _child!.stdout.drain();
      _child!.stderr.drain();
      _child!.exitCode.then((_) {
        _child = null;
      });
      for (var i = 0; i < 20; i++) {
        await Future.delayed(const Duration(milliseconds: 250));
        if (await _ping()) {
          running = true;
          break;
        }
      }
      if (!running) error = 'O agente não respondeu (porta $port ocupada?).';
    } catch (e) {
      error = 'Falha ao iniciar o agente: $e';
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> stopAgent() async {
    busy = true;
    notifyListeners();
    try {
      if (_child != null) {
        _child!.kill();
        _child = null;
      } else {
        await Process.run('pkill', ['-f', 'python3 .*agent.py']);
      }
      for (var i = 0; i < 12; i++) {
        await Future.delayed(const Duration(milliseconds: 250));
        if (!await _ping()) break;
      }
      running = await _ping();
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  /// Chamado ao sair do app.
  void shutdown() {
    _child?.kill();
  }

  Future<void> setAutostart(bool on) async {
    final f = File(autostartFile);
    if (on) {
      await f.parent.create(recursive: true);
      await f.writeAsString('''[Desktop Entry]
Type=Application
Name=TAPKEY Desktop
Comment=Controle seu notebook pelo celular
Exec=tapkey-desktop --minimized
Icon=tapkey-desktop
Terminal=false
X-GNOME-Autostart-enabled=true
''');
    } else if (f.existsSync()) {
      await f.delete();
    }
    autostart = on;
    notifyListeners();
  }
}
