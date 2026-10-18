import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'pinning.dart';
import 'screens/cursor_screen.dart';
import 'screens/home_screen.dart';
import 'screens/settings_screen.dart';
import 'state.dart';
import 'theme.dart';
import 'widgets/approval_sheet.dart';
import 'widgets/header.dart';
import 'widgets/island.dart';
import 'widgets/lock_sheet.dart';
import 'widgets/screensaver.dart';
import 'widgets/mascot.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light.copyWith(
    statusBarColor: Colors.transparent,
    systemNavigationBarColor: const Color(0xFF0F0F11),
  ));
  final state = AppState();
  HttpOverrides.global = PinningOverrides(state); // TLS com certificado fixado (fingerprint do QR)
  await state.init();
  runApp(TapkeyApp(state: state));
}

class TapkeyApp extends StatelessWidget {
  final AppState state;
  const TapkeyApp({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TAPKEY',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      builder: (context, child) => Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (e) => mascotController.setPointer(e.position),
        onPointerMove: (e) => mascotController.setPointer(e.position),
        child: AppOverlays(state: state, child: child!),
      ),
      home: Shell(state: state),
    );
  }
}

class Shell extends StatefulWidget {
  final AppState state;
  const Shell({super.key, required this.state});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _tab = 0;
  Orientation? _lastOrientation;

  @override
  void initState() {
    super.initState();
    widget.state.addListener(_rebuild);
    final cur = widget.state.cursor;
    cur.addListener(_rebuild);
    cur.onApproval = (a) {
      HapticFeedback.heavyImpact();
      island.show('Cursor pede aprovação', kind: IslandKind.warn, duration: const Duration(seconds: 4));
      mascotController.surprised();
      if (mounted) showApprovalSheet(context, widget.state, a);
    };
    cur.onNotice = (kind, folder, text) {
      switch (kind) {
        case 'finished':
        case 'cli_done':
          HapticFeedback.mediumImpact();
          island.show('$text: $folder', kind: IslandKind.success, duration: const Duration(seconds: 3));
          mascotController.finished();
        case 'error':
          HapticFeedback.heavyImpact();
          island.show('$text: $folder', kind: IslandKind.error, duration: const Duration(seconds: 3));
          mascotController.error();
        case 'delivered':
          island.show('$text: $folder', kind: IslandKind.cursor);
          mascotController.proud();
        case 'started':
          island.show('Cursor: sessão em $folder', kind: IslandKind.cursor);
          mascotController.wink();
      }
    };
    widget.state.onConnectionChanged = (ok) {
      if (ok) {
        island.show('Notebook conectado', kind: IslandKind.success);
      } else {
        island.show('Notebook desconectado', kind: IslandKind.error);
      }
    };
  }

  @override
  void dispose() {
    widget.state.removeListener(_rebuild);
    widget.state.cursor.removeListener(_rebuild);
    super.dispose();
  }

  void _rebuild() => setState(() {});

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final o = MediaQuery.orientationOf(context);
    if (o != _lastOrientation) {
      _lastOrientation = o;
      // Paisagem: barras do sistema ocultas (imersivo); retrato: normal.
      SystemChrome.setEnabledSystemUIMode(
        o == Orientation.landscape ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
      );
    }
  }

  static const _dests = [
    (Icons.home_outlined, Icons.home, 'Início'),
    (Icons.terminal_outlined, Icons.terminal, 'Cursor'),
    (Icons.settings_outlined, Icons.settings, 'Configurações'),
  ];

  Widget _badge((IconData, IconData, String) d, Widget icon) {
    final n = widget.state.cursor.pendingCount;
    if (d.$3 != 'Cursor' || n == 0) return icon;
    return Badge(label: Text('$n'), child: icon);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    final landscape = MediaQuery.orientationOf(context) == Orientation.landscape;
    final pages = [
      HomeScreen(state: s),
      CursorScreen(state: s),
      SettingsScreen(state: s),
    ];
    final content = AnimatedSwitcher(
      duration: const Duration(milliseconds: 350),
      switchInCurve: Curves.easeOutCubic,
      transitionBuilder: (c, a) => FadeTransition(
        opacity: a,
        child: SlideTransition(
          position: Tween(begin: const Offset(0, 0.03), end: Offset.zero).animate(a),
          child: c,
        ),
      ),
      child: KeyedSubtree(key: ValueKey(_tab), child: pages[_tab]),
    );

    if (landscape) {
      // Trilho fino à esquerda; a grade ocupa todo o resto da tela.
      return Scaffold(
        body: Row(children: [
          ColoredBox(
            color: const Color(0xFF0F0F11),
            child: SafeArea(
              right: false,
              child: SizedBox(
                width: 60,
                child: Column(children: [
                  const SizedBox(height: 6),
                  Mascot(connected: s.connected, size: 34),
                  const SizedBox(height: 2),
                  const Text('TAPKEY',
                      style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.w800, letterSpacing: 1.2, color: kAccent)),
                  const SizedBox(height: 6),
                  Tooltip(
                    message: s.connected ? 'Conectado' : 'Desconectado',
                    child: StatusDot(connected: s.connected, size: 8),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Bloquear / desbloquear',
                    icon: Icon(s.locked ? Icons.lock : Icons.lock_open, color: s.locked ? kAccent : kMuted),
                    onPressed: () => showLockSheet(context, s),
                  ),
                  for (var i = 0; i < _dests.length; i++)
                    IconButton(
                      tooltip: _dests[i].$3,
                      isSelected: _tab == i,
                      icon: Icon(_tab == i ? _dests[i].$2 : _dests[i].$1,
                          color: _tab == i ? kAccent : kMuted),
                      onPressed: () => setState(() => _tab = i),
                    ),
                  const SizedBox(height: 8),
                ]),
              ),
            ),
          ),
          Expanded(
            child: SafeArea(
              left: false,
              child: Container(color: kBg, child: content),
            ),
          ),
        ]),
      );
    }

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(children: [
          AppHeader(
            connected: s.connected,
            locked: s.locked,
            onLock: () => showLockSheet(context, s),
          ),
          Expanded(child: content),
        ]),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: [
          for (final d in _dests)
            NavigationDestination(
              icon: _badge(d, Icon(d.$1)),
              selectedIcon: _badge(d, Icon(d.$2)),
              label: d.$3,
            ),
        ],
      ),
    );
  }
}
