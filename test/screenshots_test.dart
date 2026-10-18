import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meu_notebook/main.dart';
import 'package:meu_notebook/state.dart';
import 'package:meu_notebook/widgets/island.dart';

/// Gera capturas de tela (sem celular) em /tmp/shots/*.png usando dados de demonstração.
/// Uso: flutter test test/screenshots_test.dart
class _Demo extends AppState {
  @override
  Future<bool> checkConnection() async => connected;
  @override
  Future<void> refreshSession() async {}
  @override
  Future<(bool, String)> launch(AppItem a) async => (true, 'Abrindo ${a.name} no notebook…');
}

Future<void> _font(String family, List<String> files) async {
  final l = FontLoader(family);
  for (final f in files) {
    l.addFont(Future.value(ByteData.sublistView(File(f).readAsBytesSync())));
  }
  await l.load();
}

/// Avança o relógio em quadros de ~16 ms (o motor do Tapi limita dt a 50 ms).
Future<void> adv(WidgetTester t, int ms) async {
  for (var i = 0; i < ms ~/ 16; i++) {
    await t.pump(const Duration(milliseconds: 16));
  }
}

void main() {
  const fonts = '/home/helio/sdk/flutter/bin/cache/artifacts/material_fonts';
  Future<void> shot(WidgetTester t, GlobalKey k, String name) async {
    await t.runAsync(() async {
      final b = k.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final img = await b.toImage(pixelRatio: 1.0);
      final d = await img.toByteData(format: ui.ImageByteFormat.png);
      Directory('/tmp/shots').createSync(recursive: true);
      File('/tmp/shots/$name.png').writeAsBytesSync(d!.buffer.asUint8List());
    });
  }

  Future<(AppState, GlobalKey)> boot(WidgetTester t, Size size) async {
    await _font('Roboto', ['$fonts/Roboto-Regular.ttf', '$fonts/Roboto-Medium.ttf', '$fonts/Roboto-Bold.ttf']);
    await _font('MaterialIcons', ['$fonts/MaterialIcons-Regular.otf']);
    t.view.physicalSize = size;
    t.view.devicePixelRatio = 1.0;
    final s = _Demo()
      ..loaded = true
      ..connected = true
      ..unlockAllowed = true
      ..screensaverSeconds = 3
      ..favorites = const [
        AppItem(id: 'spotify', name: 'Spotify', icon: 'music'),
        AppItem(id: 'firefox', name: 'Firefox', icon: 'web'),
        AppItem(id: 'terminal', name: 'Terminal', icon: 'terminal'),
        AppItem(id: 'files', name: 'Arquivos', icon: 'folder'),
        AppItem(id: 'code', name: 'Code', icon: 'code'),
        AppItem(id: 'calc', name: 'Calculadora', icon: 'calculate'),
      ];
    final k = GlobalKey();
    await t.pumpWidget(RepaintBoundary(key: k, child: TapkeyApp(state: s)));
    await adv(t, 600);
    await adv(t, 600);
    await adv(t, 600);
    return (s, k);
  }

  testWidgets('portrait', (t) async {
    final (s, k) = await boot(t, const Size(412, 892));
    await shot(t, k, 'portrait');
    island.show('Abrindo Spotify…', kind: IslandKind.info, duration: const Duration(seconds: 30));
    await adv(t, 100);
    await adv(t, 400);
    await shot(t, k, 'island');
    island.show('Notebook desconectado', kind: IslandKind.error, duration: const Duration(milliseconds: 2500));
    await adv(t, 600);
    await adv(t, 1500);
    await shot(t, k, 'island_error');
    await t.tap(find.byIcon(Icons.lock_open));
    await adv(t, 300);
    await adv(t, 700);
    await shot(t, k, 'lock');
    await t.tapAt(const Offset(200, 100));
    await adv(t, 1000);
    await t.runAsync(() => Future.delayed(const Duration(seconds: 4)));
    await adv(t, 1000);
    await adv(t, 1200);
    await shot(t, k, 'screensaver');
    await adv(t, 3000);
    await shot(t, k, 'screensaver2');
  });

  testWidgets('landscape', (t) async {
    await boot(t, const Size(892, 412));
    final k = find.byType(RepaintBoundary).first;
    final key = (k.evaluate().first.widget.key as GlobalKey);
    await shot(t, key, 'landscape');
  });

  testWidgets('gif frames', (t) async {
    final (s, k) = await boot(t, const Size(412, 892));
    Directory('/tmp/shots/frames').createSync(recursive: true);
    var n = 0;
    Future<void> rec(int ms, {int every = 5}) async {
      for (var i = 0; i < ms ~/ 16; i++) {
        await t.pump(const Duration(milliseconds: 16));
        if (i % every == 0) {
          await t.runAsync(() async {
            final b = k.currentContext!.findRenderObject() as RenderRepaintBoundary;
            final img = await b.toImage(pixelRatio: 0.7);
            final d = await img.toByteData(format: ui.ImageByteFormat.png);
            File('/tmp/shots/frames/f${(n++).toString().padLeft(3, '0')}.png').writeAsBytesSync(d!.buffer.asUint8List());
          });
        }
      }
    }
    await rec(700);
    await t.tap(find.text('Spotify'));
    await rec(2600);
    await t.tap(find.byIcon(Icons.lock_open));
    await rec(1400);
    await t.tapAt(const Offset(200, 100));
    await rec(1000);
    await t.runAsync(() => Future.delayed(const Duration(seconds: 4)));
    await rec(4200, every: 6);
    await t.tapAt(const Offset(200, 400));
    await rec(1800);
    expect(s.connected, true);
  });
}
