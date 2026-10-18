import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'state.dart';

class CursorSession {
  final String id, workspaceId, folder, state, lastTool;
  final int queued;
  final double updated;
  CursorSession.fromJson(Map<String, dynamic> j)
    : id = j['id'] as String,
      workspaceId = (j['workspace_id'] ?? '') as String,
      folder = (j['folder'] ?? '?') as String,
      state = (j['state'] ?? 'idle') as String,
      lastTool = (j['last_tool'] ?? '') as String,
      queued = (j['queued'] ?? 0) as int,
      updated = ((j['updated'] ?? 0) as num).toDouble();
}

class CursorApproval {
  final String id, sessionId, folder, kind, title, command, tool, server;
  final bool denyOnly;
  final double created, expires;
  CursorApproval.fromJson(Map<String, dynamic> j)
    : id = j['id'] as String,
      sessionId = (j['session_id'] ?? '') as String,
      folder = (j['folder'] ?? '?') as String,
      kind = (j['kind'] ?? 'shell') as String,
      title = (j['title'] ?? '') as String,
      command = (j['command'] ?? '') as String,
      tool = (j['tool'] ?? '') as String,
      server = (j['server'] ?? '') as String,
      denyOnly = j['deny_only'] == true,
      created = ((j['created'] ?? 0) as num).toDouble(),
      expires = ((j['expires'] ?? 0) as num).toDouble();
}

class CursorWorkspace {
  final String id, name;
  CursorWorkspace(this.id, this.name);
}

class CursorQueued {
  final String id, folder, preview;
  CursorQueued.fromJson(Map<String, dynamic> j)
    : id = j['id'] as String,
      folder = (j['folder'] ?? '') as String,
      preview = (j['preview'] ?? '') as String;
}

/// Eventos do agente (SSE) sobre as sessões do Cursor + ações do celular.
class CursorService extends ChangeNotifier {
  final AppState app;
  CursorService(this.app) {
    app.addListener(_appChanged);
    _appChanged();
  }

  bool enabled = false; // integração ligada no Desktop?
  bool? disabledKnown; // null = ainda não sabemos
  bool approvalsEnabled = false;
  bool instructionsEnabled = false;
  bool cliAvailable = false;
  bool streaming = false;
  List<CursorSession> sessions = [];
  List<CursorApproval> approvals = [];
  List<CursorWorkspace> workspaces = [];
  List<CursorQueued> queue = [];
  Map<String, dynamic> cli = {'running': false};
  final List<String> cliLines = [];
  String? lastError;

  /// (kind, folder, text) para ilha e mascote.
  void Function(String kind, String folder, String text)? onNotice;
  void Function(CursorApproval a)? onApproval;

  http.Client? _client;
  bool _foreground = true;
  bool _wanted = false;
  int _gen = 0;
  final Set<String> _seenApprovals = {};

  int get pendingCount => approvals.length;
  bool get anyWorking =>
      sessions.any((s) => s.state == 'working' || s.state == 'thinking');

  void _appChanged() {
    final want = app.connected && _foreground;
    if (want && !_wanted) {
      start();
    } else if (!want && _wanted) {
      stop();
    }
  }

  void setForeground(bool fg) {
    _foreground = fg;
    _appChanged();
  }

  void start() {
    if (_wanted) return;
    _wanted = true;
    _loop(++_gen);
  }

  void stop() {
    _wanted = false;
    _gen++;
    _client?.close();
    _client = null;
    if (streaming) {
      streaming = false;
      notifyListeners();
    }
  }

  Future<void> _loop(int gen) async {
    var backoff = 1;
    while (_wanted && gen == _gen) {
      try {
        _client = http.Client();
        final req = http.Request(
          'GET',
          Uri.parse('${app.baseUrl}/cursor/events'),
        )..headers.addAll(app.headers);
        final res = await _client!
            .send(req)
            .timeout(const Duration(seconds: 8));
        if (res.statusCode == 403) {
          enabled = false;
          disabledKnown = true;
          streaming = false;
          sessions = [];
          approvals = [];
          notifyListeners();
          _client?.close();
          // tenta de novo em 15 s (o usuário pode ligar no Desktop)
          await Future.delayed(const Duration(seconds: 15));
          continue;
        }
        if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
        backoff = 1;
        String? ev;
        final lines = res.stream
            .transform(utf8.decoder)
            .transform(const LineSplitter());
        await for (final line in lines) {
          if (!_wanted || gen != _gen) break;
          if (line.startsWith('event: ')) {
            ev = line.substring(7);
          } else if (line.startsWith('data: ') && ev != null) {
            try {
              _onEvent(
                ev,
                jsonDecode(line.substring(6)) as Map<String, dynamic>,
              );
            } catch (_) {}
          }
        }
      } catch (_) {
        // cai para o backoff
      }
      if (streaming) {
        streaming = false;
        notifyListeners();
      }
      _client?.close();
      if (!_wanted || gen != _gen) break;
      await Future.delayed(Duration(seconds: backoff));
      backoff = (backoff * 2).clamp(1, 20);
    }
  }

  void _onEvent(String ev, Map<String, dynamic> d) {
    switch (ev) {
      case 'state':
        _applyState(d);
      case 'notice':
        onNotice?.call(
          (d['kind'] ?? '') as String,
          (d['folder'] ?? '') as String,
          (d['text'] ?? '') as String,
        );
      case 'cli':
        cliLines.add((d['text'] ?? '') as String);
        if (cliLines.length > 300) {
          cliLines.removeRange(0, cliLines.length - 300);
        }
        notifyListeners();
    }
  }

  void _applyState(Map<String, dynamic> d) {
    enabled = d['enabled'] == true;
    disabledKnown = !enabled;
    streaming = true;
    approvalsEnabled = d['approvals_enabled'] == true;
    instructionsEnabled = d['instructions_enabled'] == true;
    cliAvailable = d['cli_available'] == true;
    sessions = ((d['sessions'] ?? []) as List)
        .map((e) => CursorSession.fromJson(e as Map<String, dynamic>))
        .toList();
    approvals = ((d['approvals'] ?? []) as List)
        .map((e) => CursorApproval.fromJson(e as Map<String, dynamic>))
        .toList();
    workspaces = ((d['workspaces'] ?? []) as List)
        .map(
          (e) =>
              CursorWorkspace((e as Map)['id'] as String, e['name'] as String),
        )
        .toList();
    queue = ((d['queue'] ?? []) as List)
        .map((e) => CursorQueued.fromJson(e as Map<String, dynamic>))
        .toList();
    cli = (d['cli'] ?? {'running': false}) as Map<String, dynamic>;
    for (final a in approvals) {
      if (_seenApprovals.add(a.id)) onApproval?.call(a);
    }
    notifyListeners();
  }

  // ---- ações ----
  Future<(bool, String)> decide(CursorApproval a, bool allow) async {
    final (code, j) = await app.postJson('/cursor/approval', {
      'id': a.id,
      'decision': allow ? 'allow' : 'deny',
    });
    if (code == 200) return (true, allow ? 'Permitido' : 'Negado');
    return (false, (j['error'] ?? 'Não consegui enviar a decisão.') as String);
  }

  Future<(bool, String)> sendInstruction(
    String text, {
    required bool viaCli,
    String? sessionId,
    String? workspaceId,
  }) async {
    if (viaCli) cliLines.clear();
    final (code, j) = await app.postJson('/cursor/instruction', {
      'mode': viaCli ? 'cli' : 'ide',
      'text': text,
      'session_id': ?sessionId,
      'workspace_id': ?workspaceId,
    });
    if (code == 200) return (true, (j['message'] ?? 'Enviado') as String);
    return (
      false,
      (j['error'] ?? 'Não consegui enviar a instrução.') as String,
    );
  }

  Future<void> cancelQueued(String id) =>
      app.postJson('/cursor/instruction/cancel', {'id': id});
  Future<void> cancelCli() => app.postJson('/cursor/cli/cancel', {});

  Future<(bool, String)> openWorkspace(String workspaceId) async {
    final (code, j) = await app.postJson('/cursor/open', {
      'workspace_id': workspaceId,
    });
    if (code == 200) {
      return (true, (j['message'] ?? 'Abrindo no Cursor…') as String);
    }
    return (false, (j['error'] ?? 'Não consegui abrir no Cursor.') as String);
  }

  @override
  void dispose() {
    app.removeListener(_appChanged);
    stop();
    super.dispose();
  }
}

String stateLabel(String s) => switch (s) {
  'working' => 'Trabalhando',
  'thinking' => 'Pensando',
  'waiting' => 'Aguardando você',
  'finished' => 'Terminou',
  'error' => 'Erro',
  _ => 'Parado',
};
