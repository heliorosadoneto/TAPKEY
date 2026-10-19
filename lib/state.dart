import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'config.dart';
import 'cursor.dart';

class AppItem {
  final String id;
  final String name;
  final String icon;
  const AppItem({required this.id, required this.name, this.icon = ''});

  factory AppItem.fromJson(Map<String, dynamic> j) => AppItem(
    id: j['id'] as String,
    name: j['name'] as String,
    icon: (j['icon'] ?? '') as String,
  );

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'icon': icon};
}

class AppState extends ChangeNotifier {
  late SharedPreferences _prefs;
  String host = kDefaultHost;
  int port = kDefaultPort;
  /// Token do QR (pareamento). Depois do registro ele é descartado e o app passa
  /// a usar só o token deste aparelho (revogável no TAPKEY Desktop).
  String token = kDefaultToken;

  /// Identidade estável deste celular (gerada uma vez e guardada no aparelho).
  String deviceId = '';
  String deviceName = 'Celular';
  String deviceToken = '';

  /// O notebook revogou este aparelho: precisa escanear o QR de novo.
  bool revoked = false;
  static const _deviceChannel = MethodChannel('tapkey/device');

  /// Fingerprint SHA-256 (hex) do certificado do notebook. Vazio = HTTP legado (sem TLS).
  String fp = kDefaultFp;
  String notebookName = '';
  late final CursorService cursor = CursorService(this);
  List<AppItem> favorites = [];
  bool connected = false;
  bool loaded = false;
  int screensaverSeconds = 60; // 0 = desligado
  bool locked = false;
  bool unlockAllowed = false;

  /// Chamado quando a conexão muda (após a inicialização).
  void Function(bool connected)? onConnectionChanged;
  Timer? _timer;

  bool get secure => fp.isNotEmpty;
  String get baseUrl => '${secure ? 'https' : 'http'}://$host:$port';
  bool get paired => deviceToken.isNotEmpty;
  Map<String, String> get headers => {
    'X-Device-Id': deviceId,
    'X-Device-Name': deviceName,
    if (paired) 'X-Device-Token': deviceToken else 'X-Token': token,
  };

  static String _newDeviceId() {
    final r = Random.secure();
    return base64Url
        .encode(List<int>.generate(16, (_) => r.nextInt(256)))
        .replaceAll('=', '');
  }

  Future<void> _loadDevice() async {
    deviceId = _prefs.getString('device_id') ?? '';
    if (!RegExp(r'^[A-Za-z0-9_-]{8,64}$').hasMatch(deviceId)) {
      deviceId = _newDeviceId();
      await _prefs.setString('device_id', deviceId);
    }
    deviceToken = _prefs.getString('device_token') ?? '';
    try {
      final m = await _deviceChannel.invokeMethod<String>('model');
      if (m != null && m.trim().isNotEmpty) deviceName = m.trim();
    } catch (_) {}
    // cabeçalhos HTTP: só ASCII imprimível
    deviceName = deviceName.replaceAll(RegExp(r'[^\x20-\x7E]'), '').trim();
    if (deviceName.isEmpty) deviceName = 'Celular';
    if (deviceName.length > 60) deviceName = deviceName.substring(0, 60);
  }

  /// Troca o token do QR por um token só deste aparelho.
  Future<bool> _ensureRegistered() async {
    if (paired) return true;
    if (token.isEmpty) return false;
    try {
      final r = await http
          .post(
            Uri.parse('$baseUrl/pair/register'),
            headers: {...headers, 'Content-Type': 'application/json'},
            body: jsonEncode({'name': deviceName}),
          )
          .timeout(const Duration(seconds: 5));
      if (r.statusCode != 200) return false;
      final j = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
      final t = (j['device_token'] ?? '') as String;
      if (t.isEmpty) return false;
      deviceToken = t;
      token = '';
      revoked = false;
      await _prefs.setString('device_token', deviceToken);
      await _prefs.remove('token');
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  void _checkRevoked(http.Response r) {
    if (r.statusCode != 401 || !paired) return;
    try {
      final j = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
      if (j['revoked'] != true) return;
    } catch (_) {
      return;
    }
    deviceToken = '';
    revoked = true;
    _prefs.remove('device_token');
    notifyListeners();
  }

  String get authError => revoked
      ? 'Este aparelho foi revogado no notebook. Escaneie o QR de novo.'
      : 'Token inválido. Verifique em Configurações.';

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    host = _prefs.getString('host') ?? kDefaultHost;
    port = _prefs.getInt('port') ?? kDefaultPort;
    token = _prefs.getString('token') ?? kDefaultToken;
    await _loadDevice();
    fp = _prefs.getString('fp') ?? kDefaultFp;
    notebookName = _prefs.getString('name') ?? '';
    screensaverSeconds = _prefs.getInt('screensaver') ?? 60;
    final raw = _prefs.getString('favorites');
    if (raw != null) {
      try {
        favorites = (jsonDecode(raw) as List)
            .map((e) => AppItem.fromJson(e as Map<String, dynamic>))
            .toList();
      } catch (_) {}
    }
    loaded = true;
    notifyListeners();
    checkConnection();
    _timer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => checkConnection(),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> saveSettings(
    String h,
    int p,
    String t, {
    String? fingerprint,
    String? name,
  }) async {
    host = h.trim();
    port = p;
    // Token novo (QR ou digitado) = novo pareamento; vazio = mantém o deste aparelho.
    if (t.trim().isNotEmpty) {
      token = t.trim();
      deviceToken = '';
      await _prefs.remove('device_token');
    }
    if (fingerprint != null) {
      fp = fingerprint.trim().toLowerCase().replaceAll(':', '');
    }
    if (name != null) notebookName = name;
    await _prefs.setString('host', host);
    await _prefs.setInt('port', port);
    if (token.isNotEmpty) await _prefs.setString('token', token);
    await _prefs.setString('fp', fp);
    await _prefs.setString('name', notebookName);
    notifyListeners();
    await checkConnection();
  }

  Future<bool> checkConnection() async {
    bool ok = false;
    try {
      await _ensureRegistered();
      final r = await http
          .get(Uri.parse('$baseUrl/ping'), headers: headers)
          .timeout(const Duration(seconds: 3));
      _checkRevoked(r);
      ok = r.statusCode == 200 && paired;
    } catch (_) {}
    final changed = ok != connected;
    if (changed) {
      connected = ok;
      notifyListeners();
      if (loaded) onConnectionChanged?.call(ok);
    }
    if (ok) await refreshSession();
    return ok;
  }

  Future<void> setScreensaver(int seconds) async {
    screensaverSeconds = seconds;
    await _prefs.setInt('screensaver', seconds);
    notifyListeners();
  }

  /// Estado da sessão do notebook (bloqueado? desbloqueio permitido?).
  Future<void> refreshSession() async {
    try {
      final r = await http
          .get(Uri.parse('$baseUrl/session'), headers: headers)
          .timeout(const Duration(seconds: 3));
      if (r.statusCode == 200) {
        final j = jsonDecode(r.body) as Map<String, dynamic>;
        final l = j['locked'] == true, u = j['unlock_allowed'] == true;
        if (l != locked || u != unlockAllowed) {
          locked = l;
          unlockAllowed = u;
          notifyListeners();
        }
      }
    } catch (_) {}
  }

  /// POST genérico: devolve (status HTTP, corpo JSON). status 0 = sem conexão.
  Future<(int, Map<String, dynamic>)> postJson(
    String path,
    Map<String, dynamic> body, {
    Duration timeout = const Duration(seconds: 12),
  }) async {
    try {
      final r = await http
          .post(
            Uri.parse('$baseUrl$path'),
            headers: {...headers, 'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(timeout);
      var j = <String, dynamic>{};
      try {
        j = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
      } catch (_) {}
      return (r.statusCode, j);
    } catch (_) {
      return (
        0,
        <String, dynamic>{
          'error': 'Notebook desconectado. Verifique o agente e o Wi‑Fi.',
        },
      );
    }
  }

  Future<(int, Map<String, dynamic>)> getJson(String path) async {
    try {
      final r = await http
          .get(Uri.parse('$baseUrl$path'), headers: headers)
          .timeout(const Duration(seconds: 6));
      var j = <String, dynamic>{};
      try {
        j = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
      } catch (_) {}
      return (r.statusCode, j);
    } catch (_) {
      return (0, <String, dynamic>{'error': 'Notebook desconectado.'});
    }
  }

  Future<(bool, String)> post(String path, Map<String, dynamic> body) async {
    try {
      final r = await http
          .post(
            Uri.parse('$baseUrl$path'),
            headers: {...headers, 'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 12));
      final j = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
      if (r.statusCode == 200) {
        return (true, (j['message'] ?? 'Pronto') as String);
      }
      if (r.statusCode == 401) {
        _checkRevoked(r);
        return (false, authError);
      }
      return (
        false,
        (j['error'] ?? j['message'] ?? 'Erro ${r.statusCode}') as String,
      );
    } catch (_) {
      return (false, 'Notebook desconectado. Verifique o agente e o Wi‑Fi.');
    }
  }

  Future<(bool, String)> lockNotebook() async {
    final res = await post('/lock', {});
    await refreshSession();
    return res;
  }

  /// Desbloqueio: pede um desafio de uso único e responde com HMAC(token, nonce).
  Future<(bool, String)> unlockNotebook() async {
    try {
      final r = await http
          .get(Uri.parse('$baseUrl/challenge'), headers: headers)
          .timeout(const Duration(seconds: 5));
      if (r.statusCode != 200) {
        return (false, 'Não consegui obter o desafio de segurança.');
      }
      final nonce =
          (jsonDecode(r.body) as Map<String, dynamic>)['nonce'] as String;
      // chave = SHA-256 (hex) do token deste aparelho (o agente só guarda o hash)
      final key = sha256.convert(utf8.encode(deviceToken)).toString();
      final proof = Hmac(
        sha256,
        utf8.encode(key),
      ).convert(utf8.encode(nonce)).toString();
      final res = await post('/unlock', {'nonce': nonce, 'proof': proof});
      await refreshSession();
      return res;
    } catch (_) {
      return (false, 'Notebook desconectado. Verifique o agente e o Wi‑Fi.');
    }
  }

  Future<void> _saveFavs() async {
    await _prefs.setString(
      'favorites',
      jsonEncode(favorites.map((e) => e.toJson()).toList()),
    );
    notifyListeners();
  }

  bool isFavorite(String id) => favorites.any((e) => e.id == id);

  Future<void> addFavorite(AppItem a) async {
    if (isFavorite(a.id)) return;
    favorites.add(a);
    await _saveFavs();
  }

  Future<void> removeFavorite(String id) async {
    favorites.removeWhere((e) => e.id == id);
    await _saveFavs();
  }

  Future<void> move(String id, int delta) async {
    final i = favorites.indexWhere((e) => e.id == id);
    final j = i + delta;
    if (i < 0 || j < 0 || j >= favorites.length) return;
    final it = favorites.removeAt(i);
    favorites.insert(j, it);
    await _saveFavs();
  }

  /// Reordena os favoritos conforme [ids] (usado pelo arrastar-e-soltar).
  Future<void> setOrder(List<String> ids) async {
    final byId = {for (final a in favorites) a.id: a};
    final next = [for (final id in ids) if (byId[id] != null) byId[id]!];
    for (final a in favorites) {
      if (!ids.contains(a.id)) next.add(a);
    }
    favorites = next;
    await _saveFavs();
  }

  Future<void> moveToFront(String id) async {
    final i = favorites.indexWhere((e) => e.id == id);
    if (i <= 0) return;
    favorites.insert(0, favorites.removeAt(i));
    await _saveFavs();
  }

  /// Retorna mensagem e se deu certo.
  Future<(bool, String)> launch(AppItem a) async {
    try {
      final r = await http
          .post(
            Uri.parse('$baseUrl/launch'),
            headers: {...headers, 'Content-Type': 'application/json'},
            body: jsonEncode({'id': a.id}),
          )
          .timeout(const Duration(seconds: 5));
      if (r.statusCode == 200) {
        if (!connected) {
          connected = true;
          notifyListeners();
        }
        return (true, 'Abrindo ${a.name} no notebook…');
      }
      if (r.statusCode == 401) {
        _checkRevoked(r);
        return (false, authError);
      }
      return (false, 'Não consegui abrir ${a.name}.');
    } catch (_) {
      connected = false;
      notifyListeners();
      return (false, 'Notebook desconectado. Verifique o agente e o Wi‑Fi.');
    }
  }

  Future<List<AppItem>> fetchApps() async {
    final r = await http
        .get(Uri.parse('$baseUrl/apps'), headers: headers)
        .timeout(const Duration(seconds: 8));
    if (r.statusCode == 401) {
      _checkRevoked(r);
      throw Exception(authError);
    }
    if (r.statusCode != 200) throw Exception('Erro ${r.statusCode}');
    final list = jsonDecode(utf8.decode(r.bodyBytes)) as List;
    return list
        .map((e) => AppItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
