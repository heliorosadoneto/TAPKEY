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
  int totalLaunches = 0;
  int _lastLaunches = -1;
  void Function()? onNewLaunch;

  Process? _child;
  Timer? _timer;

  Future<void> init() async {
    await Directory(configDir).create(recursive: true);
    await _loadToken();
    autostart = File(autostartFile).existsSync();
    await refresh();
    _timer = Timer.periodic(const Duration(seconds: 2), (_) => refresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String get pairUri => 'tapkey://pair?host=$lanIp&port=$port&token=${Uri.encodeQueryComponent(token)}';
  String get address => '$lanIp:$port';

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

  Future<bool> _ping() async {
    final c = HttpClient()..connectionTimeout = const Duration(seconds: 1);
    try {
      final req = await c.getUrl(Uri.parse('http://127.0.0.1:$port/ping'));
      req.headers.set('X-Token', token);
      final res = await req.close().timeout(const Duration(seconds: 2));
      await res.drain();
      return res.statusCode == 200;
    } catch (_) {
      return false;
    } finally {
      c.close(force: true);
    }
  }

  Future<void> refresh() async {
    final ip = await _detectLanIp();
    final up = await _ping();
    var list = <ClientInfo>[];
    var launches = 0;
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
      }
    } catch (_) {}
    final newLaunch = _lastLaunches >= 0 && launches > _lastLaunches;
    _lastLaunches = launches;
    totalLaunches = launches;
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
