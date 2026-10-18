import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../theme.dart';

/// Fundo "vivo": pontos monocromáticos à deriva, brilho que respira e ondas que
/// nascem onde você toca. Roda a ~30 fps e para quando o app sai de foco.
class LivingBackground extends StatefulWidget {
  const LivingBackground({super.key});

  /// Pausa (ex.: protetor de tela cobrindo tudo).
  static final ValueNotifier<bool> paused = ValueNotifier(false);

  /// Cria uma onda em [globalPos].
  static void ripple(Offset globalPos) {
    for (final l in List.of(_listeners)) {
      l(globalPos);
    }
  }

  static final List<void Function(Offset)> _listeners = [];

  @override
  State<LivingBackground> createState() => _LivingBackgroundState();
}

class _Dot {
  double x, y, vx, vy, r, phase, a;
  _Dot(this.x, this.y, this.vx, this.vy, this.r, this.phase, this.a);
}

class _Ripple {
  final Offset at;
  final double born;
  _Ripple(this.at, this.born);
}

class _LivingBackgroundState extends State<LivingBackground> with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final _repaint = ValueNotifier<int>(0);
  final _rng = math.Random(11);
  late final List<_Dot> _dots;
  final List<_Ripple> _ripples = [];
  double _t = 0;
  Duration _prev = Duration.zero;
  double _acc = 0;
  bool _fg = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _dots = List.generate(
      30,
      (_) => _Dot(
        _rng.nextDouble(),
        _rng.nextDouble(),
        (_rng.nextDouble() - .5) * .012,
        (_rng.nextDouble() - .5) * .012 - .003,
        .6 + _rng.nextDouble() * 1.6,
        _rng.nextDouble() * 6.28,
        .05 + _rng.nextDouble() * .09,
      ),
    );
    LivingBackground._listeners.add(_onRipple);
    LivingBackground.paused.addListener(_syncTicker);
    _ticker = createTicker(_tick)..start();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    LivingBackground._listeners.remove(_onRipple);
    LivingBackground.paused.removeListener(_syncTicker);
    _ticker.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    _fg = s == AppLifecycleState.resumed;
    _syncTicker();
  }

  void _syncTicker() {
    final run = _fg && !LivingBackground.paused.value;
    if (run && !_ticker.isActive) {
      _prev = Duration.zero;
      _ticker.start();
    } else if (!run && _ticker.isActive) {
      _ticker.stop();
    }
  }

  void _onRipple(Offset p) {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached) return;
    _ripples.add(_Ripple(box.globalToLocal(p), _t));
    if (_ripples.length > 5) _ripples.removeAt(0);
    if (!_ticker.isActive && _fg) _syncTicker();
  }

  void _tick(Duration el) {
    final dt = ((el - _prev).inMicroseconds / 1e6).clamp(0.0, .1);
    _prev = el;
    _acc += dt;
    if (_acc < 1 / 30) return; // ~30 fps é suficiente e poupa bateria
    final step = _acc;
    _acc = 0;
    _t += step;
    for (final d in _dots) {
      d.x += d.vx * step;
      d.y += d.vy * step;
      if (d.x < -.02) d.x = 1.02;
      if (d.x > 1.02) d.x = -.02;
      if (d.y < -.02) d.y = 1.02;
      if (d.y > 1.02) d.y = -.02;
    }
    _ripples.removeWhere((r) => _t - r.born > 1.6);
    _repaint.value++;
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        painter: _BgPainter(this, _repaint),
        size: Size.infinite,
      ),
    );
  }
}

class _BgPainter extends CustomPainter {
  final _LivingBackgroundState s;
  _BgPainter(this.s, Listenable repaint) : super(repaint: repaint);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = kBg);
    // brilho muito sutil que passeia devagar
    final t = s._t;
    final c = Offset(size.width * (.5 + .28 * math.sin(t * .11)), size.height * (.35 + .18 * math.cos(t * .08)));
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = RadialGradient(
          colors: [Colors.white.withValues(alpha: .035), Colors.transparent],
        ).createShader(Rect.fromCircle(center: c, radius: size.shortestSide * .9)),
    );
    final p = Paint();
    for (final d in s._dots) {
      final tw = .55 + .45 * math.sin(t * .9 + d.phase);
      p.color = Colors.white.withValues(alpha: d.a * tw);
      canvas.drawCircle(Offset(d.x * size.width, d.y * size.height), d.r, p);
    }
    for (final r in s._ripples) {
      final k = ((t - r.born) / 1.6).clamp(0.0, 1.0);
      final e = Curves.easeOutCubic.transform(k);
      final line = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6 * (1 - k) + .4
        ..color = Colors.white.withValues(alpha: .13 * (1 - k));
      canvas.drawCircle(r.at, 12 + e * 150, line);
      canvas.drawCircle(r.at, 6 + e * 90, line..color = Colors.white.withValues(alpha: .07 * (1 - k)));
    }
  }

  @override
  bool shouldRepaint(covariant _BgPainter old) => true;
}
