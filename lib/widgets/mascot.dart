import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../theme.dart';

/// Controle global do mascote: posição do último toque e eventos.
class MascotController extends ChangeNotifier {
  Offset? pointer;
  int _happyCount = 0;
  int get happyCount => _happyCount;

  void setPointer(Offset p) => pointer = p; // sem notificar (lido a cada frame)

  /// Pulinho feliz (atalho aberto com sucesso).
  void happy() {
    _happyCount++;
    notifyListeners();
  }
}

final MascotController mascotController = MascotController();

enum _Mood { normal, annoyed, dizzy, happy, sad }

/// Mola simples integrada por frame (leve e sem alocações).
class _Spring {
  double x, v = 0, target;
  final double k, d;
  _Spring(this.x, this.target, {this.k = 260, this.d = 11});
  void step(double dt) {
    // sub-passos para estabilidade
    final n = (dt / 0.008).ceil().clamp(1, 6);
    final h = dt / n;
    for (var i = 0; i < n; i++) {
      v += (-k * (x - target) - d * v) * h;
      x += v * h;
    }
  }
}

/// Mascote original do TAPKEY: um "squircle" com dois olhos grandes,
/// desenhado só com CustomPainter.
class Mascot extends StatefulWidget {
  final bool connected;
  final double size;
  const Mascot({super.key, required this.connected, this.size = 34});

  @override
  State<Mascot> createState() => _MascotState();
}

class _MascotState extends State<Mascot> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final _repaint = ValueNotifier<int>(0);
  final _rng = math.Random();

  Duration _last = Duration.zero;
  double t = 0;

  // molas
  final _pop = _Spring(-1.2, 0, k: 190, d: 9); // entrada (de baixo)
  final _squish = _Spring(0, 0, k: 380, d: 13); // amassar
  final _jump = _Spring(0, 0, k: 300, d: 10); // pulo

  // estados
  double _waveUntil = 0;
  double _annoyedUntil = 0;
  double _dizzyUntil = 0;
  double _happyUntil = 0;
  double _nextBlink = 2.0;
  double _blinkStart = -1;
  final List<double> _taps = [];
  Offset _look = Offset.zero; // direção suavizada [-1,1]
  int _seenHappy = 0;

  @override
  void initState() {
    super.initState();
    mascotController.addListener(_onHappy);
    _seenHappy = mascotController.happyCount;
    _waveUntil = 2.6;
    _pop.x = -1.2;
    _ticker = createTicker(_tick)..start();
  }

  @override
  void dispose() {
    mascotController.removeListener(_onHappy);
    _ticker.dispose();
    _repaint.dispose();
    super.dispose();
  }

  void _onHappy() {
    if (mascotController.happyCount == _seenHappy) return;
    _seenHappy = mascotController.happyCount;
    _happyUntil = t + 0.9;
    _jump.v = -9; // impulso para cima
  }

  void _onTap() {
    _taps.add(t);
    _taps.removeWhere((x) => t - x > 1.4);
    _squish.v = 9;
    if (_taps.length >= 3) {
      _dizzyUntil = t + 3.5;
      _annoyedUntil = 0;
      _taps.clear();
    } else {
      _annoyedUntil = t + 1.1;
    }
  }

  _Mood get _mood {
    if (t < _dizzyUntil) return _Mood.dizzy;
    if (t < _annoyedUntil) return _Mood.annoyed;
    if (t < _happyUntil) return _Mood.happy;
    if (!widget.connected) return _Mood.sad;
    return _Mood.normal;
  }

  void _tick(Duration elapsed) {
    final dt = ((elapsed - _last).inMicroseconds / 1e6).clamp(0.0, 0.05);
    _last = elapsed;
    t = elapsed.inMicroseconds / 1e6;
    _pop.step(dt);
    _squish.step(dt);
    _jump.step(dt);

    // piscadas periódicas
    if (_blinkStart < 0 && t >= _nextBlink) _blinkStart = t;
    if (_blinkStart >= 0 && t - _blinkStart > 0.16) {
      _blinkStart = -1;
      _nextBlink = t + 2 + _rng.nextDouble() * 3;
    }

    // pupilas seguem o último toque
    final p = mascotController.pointer;
    var target = Offset.zero;
    final ro = context.findRenderObject();
    if (p != null && ro is RenderBox && ro.attached) {
      final c = ro.localToGlobal(ro.size.center(Offset.zero));
      final dv = p - c;
      final dist = dv.distance;
      if (dist > 1) target = dv / dist * math.min(1.0, dist / 120);
    }
    if (_mood == _Mood.sad) target = Offset(target.dx * 0.5, 0.5);
    _look = Offset.lerp(_look, target, 1 - math.exp(-dt * 14))!;

    _repaint.value++;
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _onTap,
      child: SizedBox(
        width: s,
        height: s,
        child: RepaintBoundary(
          child: CustomPaint(painter: _MascotPainter(this, _repaint)),
        ),
      ),
    );
  }
}

class _MascotPainter extends CustomPainter {
  final _MascotState s;
  _MascotPainter(this.s, Listenable repaint) : super(repaint: repaint);

  static final _bodyFill = Paint()..style = PaintingStyle.fill;
  static final _stroke = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round;

  @override
  void paint(Canvas canvas, Size size) {
    final u = size.width; // unidade
    final mood = s._mood;
    final t = s.t;

    // transformações: entrada, pulo, respiração, amassar
    final breathe = math.sin(t * 2.2) * 0.025;
    final sq = s._squish.x.clamp(-0.4, 0.4);
    final sx = 1 + breathe * -0.5 + sq * 0.5;
    final sy = 1 + breathe - sq * 0.6;
    final popY = s._pop.x * u * 0.9;
    final jumpY = s._jump.x * u * 0.06;
    final popScale = (1 + s._pop.x * 0.35).clamp(0.3, 1.3);
    var wobble = 0.0;
    if (mood == _Mood.dizzy) wobble = math.sin(t * 9) * 0.12;

    canvas.save();
    canvas.translate(u / 2, u * 0.56 + popY + jumpY);
    canvas.rotate(wobble);
    canvas.scale(sx * popScale, sy * popScale);

    final body = u * 0.8;
    final r = Rect.fromCenter(center: Offset.zero, width: body, height: body * 0.92);
    final rr = RRect.fromRectAndRadius(r, Radius.circular(body * 0.36));

    // brilho sutil (acento)
    final glow = mood == _Mood.happy ? 0.35 : 0.08;
    canvas.drawRRect(
      rr.inflate(1),
      Paint()
        ..color = kAccent.withValues(alpha: glow)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, u * 0.18),
    );

    // braço acenando (só na entrada)
    if (t < s._waveUntil && s._pop.x.abs() < 0.6) {
      final ang = -0.9 + math.sin(t * 14) * 0.45;
      canvas.save();
      canvas.translate(body * 0.46, -body * 0.05);
      canvas.rotate(ang);
      _stroke
        ..color = const Color(0xFF3A3A41)
        ..strokeWidth = u * 0.14;
      canvas.drawLine(Offset.zero, Offset(u * 0.0, -u * 0.26), _stroke);
      canvas.restore();
    }

    // corpo
    _bodyFill.shader = const LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0xFF3F3F46), Color(0xFF2A2A30)],
    ).createShader(r);
    canvas.drawRRect(rr, _bodyFill);
    _stroke
      ..color = const Color(0xFF55555D)
      ..strokeWidth = math.max(1, u * 0.03);
    canvas.drawRRect(rr, _stroke);

    // olhos
    final ex = body * 0.215;
    final ey = -body * 0.02;
    final er = body * 0.17;
    var blink = 0.0;
    if (s._blinkStart >= 0) {
      blink = math.sin(((t - s._blinkStart) / 0.16).clamp(0.0, 1.0) * math.pi);
    }
    for (final side in [-1.0, 1.0]) {
      final c = Offset(ex * side, ey);
      _eye(canvas, c, er, mood, blink, side, t, u);
    }

    // boca
    _mouth(canvas, mood, body, u, t);
    canvas.restore();
  }

  void _eye(Canvas canvas, Offset c, double er, _Mood mood, double blink,
      double side, double t, double u) {
    final white = Paint()..color = const Color(0xFFF2F2F5);
    final dark = Paint()..color = const Color(0xFF111114);
    _stroke
      ..color = const Color(0xFFF2F2F5)
      ..strokeWidth = u * 0.07;

    if (mood == _Mood.happy) {
      // olhos fechados sorrindo ^ ^
      final p = Path()
        ..moveTo(c.dx - er * 0.8, c.dy + er * 0.3)
        ..quadraticBezierTo(c.dx, c.dy - er * 1.0, c.dx + er * 0.8, c.dy + er * 0.3);
      canvas.drawPath(p, _stroke);
      return;
    }
    if (mood == _Mood.dizzy) {
      // olhos em espiral
      canvas.drawCircle(c, er, white);
      final sp = Path();
      const turns = 2.4;
      for (var i = 0; i <= 40; i++) {
        final a = i / 40 * turns * 2 * math.pi + t * 8 * side;
        final rad = er * 0.85 * (i / 40);
        final pt = Offset(c.dx + math.cos(a) * rad, c.dy + math.sin(a) * rad);
        i == 0 ? sp.moveTo(pt.dx, pt.dy) : sp.lineTo(pt.dx, pt.dy);
      }
      _stroke
        ..color = const Color(0xFF111114)
        ..strokeWidth = math.max(1, u * 0.03);
      canvas.drawPath(sp, _stroke);
      return;
    }

    final vy = 1 - blink * 0.92; // piscar achata o olho
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.scale(1, vy);
    canvas.drawCircle(Offset.zero, er, white);
    // pupila segue o toque
    final look = s._look;
    final pr = er * (mood == _Mood.sad ? 0.5 : 0.55);
    final maxOff = er - pr - 0.5;
    final po = Offset(look.dx * maxOff, look.dy * maxOff);
    canvas.drawCircle(po, pr, dark);
    canvas.drawCircle(po + Offset(-pr * 0.3, -pr * 0.3), pr * 0.28, white);
    canvas.restore();

    if (mood == _Mood.annoyed) {
      // pálpebra reta cobrindo metade de cima
      final lid = Paint()..color = const Color(0xFF34343A);
      canvas.drawRect(
          Rect.fromLTRB(c.dx - er - 1, c.dy - er - 1, c.dx + er + 1, c.dy - er * 0.15), lid);
      _stroke
        ..color = const Color(0xFFF2F2F5)
        ..strokeWidth = u * 0.045;
      canvas.drawLine(Offset(c.dx - er, c.dy - er * 0.15), Offset(c.dx + er, c.dy - er * 0.15), _stroke);
    } else if (mood == _Mood.sad) {
      // sobrancelha inclinada (preocupada)
      _stroke
        ..color = const Color(0xFFB5B5BC)
        ..strokeWidth = u * 0.05;
      final o = side; // lado externo mais baixo
      canvas.drawLine(Offset(c.dx - er * o, c.dy - er * 1.15 + er * 0.35),
          Offset(c.dx + er * o * 0.9, c.dy - er * 1.25 - er * 0.1), _stroke..color = const Color(0xFFB5B5BC));
    }
  }

  void _mouth(Canvas canvas, _Mood mood, double body, double u, double t) {
    _stroke
      ..color = const Color(0xFFF2F2F5)
      ..strokeWidth = u * 0.05;
    final y = body * 0.27;
    final w = body * 0.11;
    final p = Path();
    switch (mood) {
      case _Mood.happy:
        p
          ..moveTo(-w, y - 1)
          ..quadraticBezierTo(0, y + w * 1.6, w, y - 1);
      case _Mood.sad:
        p
          ..moveTo(-w * 0.8, y + w * 0.6)
          ..quadraticBezierTo(0, y - w * 0.6, w * 0.8, y + w * 0.6);
      case _Mood.annoyed:
        p
          ..moveTo(-w * 0.9, y + 1)
          ..lineTo(w * 0.9, y + 1);
      case _Mood.dizzy:
        // boquinha ondulada
        p.moveTo(-w, y);
        p.quadraticBezierTo(-w * 0.5, y - w * 0.5, 0, y);
        p.quadraticBezierTo(w * 0.5, y + w * 0.5, w, y);
      case _Mood.normal:
        p
          ..moveTo(-w * 0.55, y)
          ..quadraticBezierTo(0, y + w * 0.55, w * 0.55, y);
    }
    canvas.drawPath(p, _stroke);
  }

  @override
  bool shouldRepaint(covariant _MascotPainter old) => true;
}
