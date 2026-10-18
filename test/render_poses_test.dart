import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meu_notebook/widgets/mascot.dart';

/// Gera uma folha de poses do Tapi em /tmp/tapi_poses.png (para revisão visual).
void main() {
  testWidgets('render poses', (tester) async {
    final key = GlobalKey();
    final poses = TapiEmote.values;
    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: RepaintBoundary(
        key: key,
        child: Container(
          color: const Color(0xFF0B0B0C),
          width: 6 * 170,
          height: 3 * 170,
          child: Wrap(children: [
            for (final p in poses)
              SizedBox(
                width: 170,
                height: 170,
                child: CustomPaint(painter: TapiStaticPainter(p)),
              ),
          ]),
        ),
      ),
    ));
    await tester.runAsync(() async {
      final b = key.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final img = await b.toImage(pixelRatio: 1.5);
      final data = await img.toByteData(format: ui.ImageByteFormat.png);
      File('/tmp/tapi_poses.png').writeAsBytesSync(data!.buffer.asUint8List());
    });
  });
}
