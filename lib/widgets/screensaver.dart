import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../state.dart';
import 'island.dart';
import 'mascot.dart';

/// Envolve o app: ilha no topo + protetor de tela após inatividade.
class AppOverlays extends StatefulWidget {
  final AppState state;
  final Widget child;
  const AppOverlays({super.key, required this.state, required this.child});

  @override
  State<AppOverlays> createState() => _AppOverlaysState();
}

class _AppOverlaysState extends State<AppOverlays> with WidgetsBindingObserver {
  DateTime _last = DateTime.now();
  Timer? _timer;
  bool _active = false;
  bool _visible = false;
  bool _foreground = true;
  final MascotController _ssCtl = MascotController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _check());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    if (_active) WakelockPlus.disable().catchError((_) {});
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    _foreground = s == AppLifecycleState.resumed;
    widget.state.cursor.setForeground(_foreground);
    if (_foreground) _last = DateTime.now();
  }

  void _poke() {
    _last = DateTime.now();
  }

  void _check() {
    final secs = widget.state.screensaverSeconds;
    if (_active || secs <= 0 || !_foreground) return;
    if (DateTime.now().difference(_last).inSeconds >= secs) _start();
  }

  void _start() {
    setState(() {
      _active = true;
      _visible = false;
    });
    WakelockPlus.enable().catchError((_) {});
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    // começa a aparecer no próximo frame (fade in)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _visible = true);
    });
  }

  Future<void> _dismiss() async {
    if (!_active || !_visible) return;
    _last = DateTime.now();
    _ssCtl.wake(); // Tapi acorda esticando e acenando
    setState(() => _visible = false);
    WakelockPlus.disable().catchError((_) {});
    final landscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    SystemChrome.setEnabledSystemUIMode(
      landscape ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
    );
    await Future.delayed(const Duration(milliseconds: 520));
    if (mounted) setState(() => _active = false);
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: Stack(
        textDirection: TextDirection.ltr,
        children: [
          Positioned.fill(
            child: Listener(
              behavior: HitTestBehavior.translucent,
              onPointerDown: (_) => _poke(),
              onPointerMove: (_) => _poke(),
              child: widget.child,
            ),
          ),
          const IslandHost(),
          if (_active)
            Positioned.fill(
              child: Listener(
                behavior: HitTestBehavior.opaque,
                onPointerDown: (_) => _dismiss(),
                child: AnimatedOpacity(
                  opacity: _visible ? 1 : 0,
                  duration: Duration(milliseconds: _visible ? 700 : 450),
                  curve: Curves.easeInOut,
                  child: _SaverScene(controller: _ssCtl),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Cena: Tapi dormindo, à deriva como o logo do DVD (amassa nas bordas),
/// partículas suaves e um relógio discreto. Fundo preto (OLED).
class _SaverScene extends StatefulWidget {
  final MascotController controller;
  const _SaverScene({required this.controller});

  @override
  State<_SaverScene> createState() => _SaverSceneState();
}

class _SaverSceneState extends State<_SaverScene>
    with SingleTickerProviderStateMixin {
  static const double _size = 120;
  late final Ticker _ticker;
  final _repaint = ValueNotifier<int>(0);
  final _rng = math.Random();
  Offset _pos = const Offset(60, 120);
  late Offset _vel;
  Size _area = Size.zero;
  Duration _last = Duration.zero;
  late final List<_Dot> _dots;
  Timer? _clock;
  DateTime _now = DateTime.now();
  double _squishCooldown = 0;

  @override
  void initState() {
    super.initState();
    final a = _rng.nextDouble() * math.pi * 2;
    _vel = Offset(math.cos(a), math.sin(a)) * 42;
    _dots = List.generate(16, (_) => _Dot(_rng));
    _ticker = createTicker(_tick)..start();
    _clock = Timer.periodic(const Duration(seconds: 10), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _ticker.dispose();
    _clock?.cancel();
    _repaint.dispose();
    super.dispose();
  }

  void _tick(Duration elapsed) {
    final dt = ((elapsed - _last).inMicroseconds / 1e6).clamp(0.0, 0.05);
    _last = elapsed;
    if (_area == Size.zero) return;
    _squishCooldown -= dt;
    var p = _pos + _vel * dt;
    var v = _vel;
    final maxX = _area.width - _size, maxY = _area.height - _size - 10;
    var hit = false;
    if (p.dx < 0) {
      p = Offset(0, p.dy);
      v = Offset(v.dx.abs(), v.dy);
      hit = true;
    }
    if (p.dx > maxX) {
      p = Offset(maxX, p.dy);
      v = Offset(-v.dx.abs(), v.dy);
      hit = true;
    }
    if (p.dy < 0) {
      p = Offset(p.dx, 0);
      v = Offset(v.dx, v.dy.abs());
      hit = true;
    }
    if (p.dy > maxY) {
      p = Offset(p.dx, maxY);
      v = Offset(v.dx, -v.dy.abs());
      hit = true;
    }
    if (hit && _squishCooldown <= 0) {
      widget.controller.squish();
      _squishCooldown = .4;
    }
    _pos = p;
    _vel = v;
    for (final d in _dots) {
      d.step(dt, _area);
    }
    _repaint.value++;
  }

  @override
  Widget build(BuildContext context) {
    String two(int n) => n.toString().padLeft(2, '0');
    const days = ['seg', 'ter', 'qua', 'qui', 'sex', 'sáb', 'dom'];
    return LayoutBuilder(
      builder: (context, c) {
        _area = Size(c.maxWidth, c.maxHeight);
        // desloca o relógio um pouco a cada minuto (evita marca na tela OLED)
        final shift = ((_now.minute % 5) - 2) * 7.0;
        return ColoredBox(
          color: Colors.black,
          child: Stack(
            children: [
              Positioned.fill(
                child: RepaintBoundary(
                  child: CustomPaint(painter: _DotsPainter(_dots, _repaint)),
                ),
              ),
              Align(
                alignment: Alignment(0, .62),
                child: Transform.translate(
                  offset: Offset(shift, shift),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${two(_now.hour)}:${two(_now.minute)}',
                        style: TextStyle(
                          fontSize: 46,
                          fontWeight: FontWeight.w200,
                          letterSpacing: 2,
                          color: Colors.white.withValues(alpha: .30),
                          decoration: TextDecoration.none,
                        ),
                      ),
                      Text(
                        '${days[_now.weekday - 1]}, ${_now.day}/${two(_now.month)}',
                        style: TextStyle(
                          fontSize: 13,
                          letterSpacing: 1.5,
                          color: Colors.white.withValues(alpha: .20),
                          decoration: TextDecoration.none,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              AnimatedBuilder(
                animation: _repaint,
                builder: (context, child) =>
                    Positioned(left: _pos.dx, top: _pos.dy, child: child!),
                child: Mascot(
                  controller: widget.controller,
                  size: _size,
                  sleeping: true,
                  alwaysOn: true,
                  interactive: false,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Dot {
  late double x, y, vx, vy, r, a, ph;
  _Dot(math.Random rng) {
    x = rng.nextDouble();
    y = rng.nextDouble();
    vx = (rng.nextDouble() - .5) * .006;
    vy = -rng.nextDouble() * .008 - .002;
    r = 1 + rng.nextDouble() * 2;
    a = .06 + rng.nextDouble() * .12;
    ph = rng.nextDouble() * 6;
  }

  void step(double dt, Size area) {
    x += vx * dt * 6;
    y += vy * dt * 6;
    if (y < -.02) y = 1.02;
    if (x < -.02) x = 1.02;
    if (x > 1.02) x = -.02;
    ph += dt;
  }
}

class _DotsPainter extends CustomPainter {
  final List<_Dot> dots;
  _DotsPainter(this.dots, Listenable repaint) : super(repaint: repaint);

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint();
    for (final d in dots) {
      p.color = Colors.white.withValues(
        alpha: d.a * (.6 + .4 * math.sin(d.ph * 1.3)),
      );
      canvas.drawCircle(Offset(d.x * size.width, d.y * size.height), d.r, p);
    }
  }

  @override
  bool shouldRepaint(covariant _DotsPainter old) => true;
}
