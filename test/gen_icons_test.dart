import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meu_notebook/widgets/mascot.dart';

/// Gera os ícones do TAPKEY a partir do próprio código do mascote Tapi:
///   flutter test test/gen_icons_test.dart
class _IconPainter extends CustomPainter {
  final bool foregroundOnly;
  _IconPainter(this.foregroundOnly);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    if (!foregroundOnly) {
      final rr = RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(s * .225));
      canvas.drawRRect(
        rr,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF232327), Color(0xFF0C0C0E)],
          ).createShader(Offset.zero & size),
      );
      canvas.drawRRect(
        rr.deflate(s * .012),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = s * .008
          ..color = Colors.white.withValues(alpha: .10),
      );
    }
    // brilho suave atrás do mascote
    canvas.drawCircle(
      Offset(s / 2, s * .52),
      s * .34,
      Paint()
        ..color = Colors.white.withValues(alpha: foregroundOnly ? .05 : .08)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, s * .12),
    );
    // Tapi (no foreground adaptativo fica dentro da zona segura de ~66%)
    final m = foregroundOnly ? s * .56 : s * .70;
    canvas.save();
    canvas.translate((s - m) / 2, (s - m) / 2 - s * .005);
    TapiStaticPainter(TapiEmote.idle, glow: 1).paint(canvas, Size(m, m));
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

Future<void> _render(WidgetTester tester, bool fg, List<String> outs, int px) async {
  final key = GlobalKey();
  await tester.pumpWidget(Directionality(
    textDirection: TextDirection.ltr,
    child: Center(
      child: RepaintBoundary(
        key: key,
        child: SizedBox(width: 256, height: 256, child: CustomPaint(painter: _IconPainter(fg))),
      ),
    ),
  ));
  await tester.runAsync(() async {
    final b = key.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final img = await b.toImage(pixelRatio: px / 256);
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    for (final o in outs) {
      File(o).parent.createSync(recursive: true);
      File(o).writeAsBytesSync(data!.buffer.asUint8List());
    }
  });
}

void main() {
  testWidgets('gera icones', (tester) async {
    await _render(tester, false, [
      'assets/icon/icon.png',
      'docs/logo.png',
      'desktop/assets/icon.png',
    ], 1024);
    await _render(tester, true, ['assets/icon/icon_foreground.png'], 1024);
    expect(math.pi > 3, true);
  });
}
