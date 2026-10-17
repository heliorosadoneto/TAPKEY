import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'config.dart';

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
  String token = kDefaultToken;
  List<AppItem> favorites = [];
  bool connected = false;
  bool loaded = false;
  Timer? _timer;

  String get baseUrl => 'http://$host:$port';
  Map<String, String> get headers => {'X-Token': token};

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    host = _prefs.getString('host') ?? kDefaultHost;
    port = _prefs.getInt('port') ?? kDefaultPort;
    token = _prefs.getString('token') ?? kDefaultToken;
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
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => checkConnection());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> saveSettings(String h, int p, String t) async {
    host = h.trim();
    port = p;
    token = t.trim();
    await _prefs.setString('host', host);
    await _prefs.setInt('port', port);
    await _prefs.setString('token', token);
    notifyListeners();
    await checkConnection();
  }

  Future<bool> checkConnection() async {
    bool ok = false;
    try {
      final r = await http
          .get(Uri.parse('$baseUrl/ping'), headers: headers)
          .timeout(const Duration(seconds: 3));
      ok = r.statusCode == 200;
    } catch (_) {}
    if (ok != connected) {
      connected = ok;
      notifyListeners();
    }
    return ok;
  }

  Future<void> _saveFavs() async {
    await _prefs.setString(
        'favorites', jsonEncode(favorites.map((e) => e.toJson()).toList()));
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
          .post(Uri.parse('$baseUrl/launch'),
              headers: {...headers, 'Content-Type': 'application/json'},
              body: jsonEncode({'id': a.id}))
          .timeout(const Duration(seconds: 5));
      if (r.statusCode == 200) {
        if (!connected) {
          connected = true;
          notifyListeners();
        }
        return (true, 'Abrindo ${a.name} no notebook…');
      }
      if (r.statusCode == 401) return (false, 'Token inválido. Verifique em Configurações.');
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
    if (r.statusCode == 401) throw Exception('Token inválido');
    if (r.statusCode != 200) throw Exception('Erro ${r.statusCode}');
    final list = jsonDecode(utf8.decode(r.bodyBytes)) as List;
    return list.map((e) => AppItem.fromJson(e as Map<String, dynamic>)).toList();
  }
}
