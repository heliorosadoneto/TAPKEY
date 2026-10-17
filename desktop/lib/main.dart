import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import 'agent_service.dart';
import 'home_page.dart';
import 'theme.dart';
import 'widgets/mascot.dart';

final AgentService agent = AgentService();

void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  final minimized = args.contains('--minimized');
  await windowManager.ensureInitialized();
  const opts = WindowOptions(
    size: Size(360, 540),
    minimumSize: Size(340, 500),
    center: true,
    maximumSize: Size(520, 760),
    title: 'TAPKEY Desktop',
    backgroundColor: kBg,
  );
  await windowManager.waitUntilReadyToShow(opts, () async {
    if (!minimized) {
      await windowManager.show();
      await windowManager.focus();
    }
  });
  await agent.init();
  agent.startAgent(); // companheiro: já sobe o agente ao abrir
  runApp(const TapkeyDesktopApp());
}

class TapkeyDesktopApp extends StatefulWidget {
  const TapkeyDesktopApp({super.key});

  @override
  State<TapkeyDesktopApp> createState() => _TapkeyDesktopAppState();
}

class _TapkeyDesktopAppState extends State<TapkeyDesktopApp> with TrayListener, WindowListener {
  bool _trayOk = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    trayManager.addListener(this);
    agent.addListener(_updateMenu);
    agent.onNewLaunch = mascotController.happy;
    _initTray();
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    trayManager.removeListener(this);
    agent.removeListener(_updateMenu);
    super.dispose();
  }

  String _iconPath() {
    final dir = File(Platform.resolvedExecutable).parent.path;
    final p = '$dir/data/flutter_assets/assets/icon.png';
    if (File(p).existsSync()) return p;
    return '${Directory.current.path}/assets/icon.png';
  }

  Future<void> _initTray() async {
    try {
      await trayManager.setIcon(_iconPath());
      await trayManager.setToolTip('TAPKEY Desktop');
      await _updateMenu();
      await windowManager.setPreventClose(true);
      _trayOk = true;
    } catch (_) {
      _trayOk = false; // sem bandeja: fechar a janela encerra o app
    }
  }

  Future<void> _updateMenu() async {
    if (!_trayOk && !mounted) return;
    try {
      await trayManager.setContextMenu(Menu(items: [
        MenuItem(key: 'open', label: 'Abrir TAPKEY'),
        MenuItem(
            key: 'toggle',
            label: agent.running ? 'Parar agente' : 'Iniciar agente'),
        MenuItem.separator(),
        MenuItem(key: 'quit', label: 'Sair'),
      ]));
    } catch (_) {}
  }

  Future<void> _quit() async {
    agent.shutdown();
    await trayManager.destroy();
    await windowManager.setPreventClose(false);
    await windowManager.destroy();
    exit(0);
  }

  @override
  void onTrayIconMouseDown() => _show();

  @override
  void onTrayIconRightMouseDown() => trayManager.popUpContextMenu();

  Future<void> _show() async {
    await windowManager.show();
    await windowManager.focus();
  }

  @override
  void onTrayMenuItemClick(MenuItem item) {
    switch (item.key) {
      case 'open':
        _show();
      case 'toggle':
        agent.running ? agent.stopAgent() : agent.startAgent();
      case 'quit':
        _quit();
    }
  }

  @override
  void onWindowClose() async {
    // Com bandeja: só esconde a janela; o agente continua rodando.
    if (_trayOk) {
      await windowManager.hide();
    } else {
      _quit();
    }
  }

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light);
    return MaterialApp(
      title: 'TAPKEY Desktop',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      builder: (context, child) => Listener(
        behavior: HitTestBehavior.translucent,
        onPointerHover: (e) => mascotController.setPointer(e.position),
        onPointerDown: (e) => mascotController.setPointer(e.position),
        onPointerMove: (e) => mascotController.setPointer(e.position),
        child: child,
      ),
      home: HomePage(agent: agent, onQuit: _quit),
    );
  }
}
