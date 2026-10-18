import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../state.dart';
import '../theme.dart';
import 'app_icon.dart';

/// Cartão cinza com brilho sutil prata e microanimações:
/// - aperta com squash/stretch e solta com mola; inclina (tilt 3D) na direção do toque
///   e o ícone faz parallax; brilho radial nasce no ponto tocado;
/// - ao lançar: pulso no cartão, anel que se expande e partículas;
/// - modo edição: balança (jiggle), selo de remover; ao arrastar, levanta com sombra.
class GlowTile extends StatefulWidget {
  final AppState state;
  final AppItem app;
  final Future<void> Function() onTap;
  final bool editing;
  final bool lifted;
  final Animation<double>? wobble;
  final double phase;
  final VoidCallback? onRemove;
  final GestureLongPressStartCallback? onLongPressStart;
  final GestureLongPressMoveUpdateCallback? onLongPressMoveUpdate;
  final GestureLongPressEndCallback? onLongPressEnd;
  const GlowTile({
    super.key,
    required this.state,
    required this.app,
    required this.onTap,
    this.editing = false,
    this.lifted = false,
    this.wobble,
    this.phase = 0,
    this.onRemove,
    this.onLongPressStart,
    this.onLongPressMoveUpdate,
    this.onLongPressEnd,
  });

  @override
  State<GlowTile> createState() => _GlowTileState();
}

class _GlowTileState extends State<GlowTile> with SingleTickerProviderStateMixin {
  bool _down = false;
  Offset _tilt = Offset.zero; // -1..1
  Alignment _touch = Alignment.center;
  late final AnimationController _fx = AnimationController(vsync: this, duration: const Duration(milliseconds: 780));

  @override
  void dispose() {
    _fx.dispose();
    super.dispose();
  }

  void _track(Offset local, Size size) {
    final nx = ((local.dx / size.width) * 2 - 1).clamp(-1.0, 1.0);
    final ny = ((local.dy / size.height) * 2 - 1).clamp(-1.0, 1.0);
    _tilt = Offset(nx, ny);
    _touch = Alignment(nx, ny);
  }

  Future<void> _tap() async {
    if (widget.editing) return;
    _fx.forward(from: 0);
    HapticFeedback.lightImpact();
    await widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.editing;
    final lifted = widget.lifted;
    return LayoutBuilder(builder: (context, c) {
      final size = Size(c.maxWidth, c.maxHeight);
      final base = math.min(size.width, size.height);
      Widget tile = Listener(
        onPointerMove: (e) {
          if (_down && !editing) setState(() => _track(e.localPosition, size));
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) {
            if (editing) return;
            HapticFeedback.selectionClick();
            setState(() {
              _down = true;
              _track(d.localPosition, size);
            });
          },
          onTapUp: (_) => setState(() => _down = false),
          onTapCancel: () => setState(() => _down = false),
          onTap: _tap,
          onLongPressStart: widget.onLongPressStart,
          onLongPressMoveUpdate: widget.onLongPressMoveUpdate,
          onLongPressEnd: widget.onLongPressEnd,
          child: _body(size, base),
        ),
      );
      // balanço (jiggle) no modo edição
      if (editing && widget.wobble != null && !lifted) {
        final w = widget.wobble!;
        tile = AnimatedBuilder(
          animation: w,
          builder: (context, child) {
            final a = math.sin((w.value + widget.phase) * 2 * math.pi) * .026;
            return Transform.rotate(angle: a, child: child);
          },
          child: tile,
        );
      }
      return AnimatedScale(
        scale: lifted ? 1.1 : 1,
        duration: Duration(milliseconds: lifted ? 220 : 520),
        curve: lifted ? Curves.easeOutBack : Curves.elasticOut,
        child: tile,
      );
    });
  }

  Widget _body(Size size, double base) {
    final pressed = _down;
    final lifted = widget.lifted;
    return TweenAnimationBuilder<Offset>(
      // squash/stretch: aperta rápido; solta com mola
      tween: Tween(end: pressed ? const Offset(.93, .88) : const Offset(1, 1)),
      duration: Duration(milliseconds: pressed ? 90 : 700),
      curve: pressed ? Curves.easeOut : Curves.elasticOut,
      builder: (context, sc, child) => TweenAnimationBuilder<Offset>(
        tween: Tween(end: pressed ? _tilt : Offset.zero),
        duration: Duration(milliseconds: pressed ? 80 : 650),
        curve: pressed ? Curves.easeOut : Curves.elasticOut,
        builder: (context, t, _) => AnimatedBuilder(
          animation: _fx,
          builder: (context, _) {
            final k = _fx.value;
            final pulse = _fx.isAnimating ? math.sin(math.pi * math.min(1, k * 1.6)) * .07 : 0.0;
            return Transform(
              alignment: Alignment.center,
              transform: Matrix4.identity()
                ..setEntry(3, 2, .0014)
                ..rotateX(-t.dy * .22)
                ..rotateY(t.dx * .22)
                ..scaleByDouble(sc.dx + pulse, sc.dy + pulse, 1, 1),
              child: Stack(clipBehavior: Clip.none, children: [
                Positioned.fill(child: _card(size, base, t, pressed, lifted, k)),
                if (_fx.isAnimating)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(painter: _LaunchPainter(k, base)),
                    ),
                  ),
              ]),
            );
          },
        ),
      ),
    );
  }

  Widget _card(Size size, double base, Offset t, bool pressed, bool lifted, double k) {
    final launching = _fx.isAnimating && k < .55;
    final glow = launching ? 0.30 : (pressed ? 0.16 : (lifted ? 0.12 : 0.05));
    final iconSize = (base * 0.46).clamp(28.0, 96.0);
    final font = (base * 0.095).clamp(11.0, 15.0);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: launching || lifted ? kAccent.withValues(alpha: 0.7) : kBorder),
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [kCardTop, kCard],
        ),
        boxShadow: [
          BoxShadow(color: kAccent.withValues(alpha: glow), blurRadius: launching ? 26 : 14),
          if (lifted) BoxShadow(color: Colors.black.withValues(alpha: .7), blurRadius: 30, offset: const Offset(0, 16)),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Stack(children: [
          // brilho radial no ponto tocado
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedOpacity(
                opacity: pressed ? 1 : 0,
                duration: Duration(milliseconds: pressed ? 70 : 520),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: _touch,
                      radius: .85,
                      colors: [Colors.white.withValues(alpha: .20), Colors.white.withValues(alpha: 0)],
                    ),
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 6, vertical: base * 0.07),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Expanded(
                  child: Center(
                    // parallax: o ícone acompanha o dedo, o texto vai no sentido oposto
                    child: Transform.translate(
                      offset: Offset(t.dx * 7, t.dy * 7),
                      child: Hero(
                        tag: 'icon-${widget.app.id}',
                        child: AppIcon(state: widget.state, app: widget.app, size: iconSize),
                      ),
                    ),
                  ),
                ),
                Transform.translate(
                  offset: Offset(-t.dx * 2.5, -t.dy * 2.5),
                  child: Text(
                    widget.app.name,
                    maxLines: 1,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: font, fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
          ),
          // selo de remover (modo edição)
          Positioned(
            left: 5,
            top: 5,
            child: AnimatedScale(
              scale: widget.editing && !widget.lifted ? 1 : 0,
              duration: const Duration(milliseconds: 380),
              curve: Curves.easeOutBack,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: widget.onRemove,
                child: Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: const Color(0xFF3A3A40),
                    shape: BoxShape.circle,
                    border: Border.all(color: kBorder),
                  ),
                  child: const Icon(Icons.remove, size: 15, color: kAccent),
                ),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

/// Anel que se expande + partículas minúsculas ao lançar um atalho.
class _LaunchPainter extends CustomPainter {
  final double k;
  final double base;
  _LaunchPainter(this.k, this.base);

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final e = Curves.easeOutCubic.transform(k);
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2 * (1 - k) + .5
      ..color = kAccent.withValues(alpha: .75 * (1 - k));
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: c, width: size.width + e * base * .5, height: size.height + e * base * .5),
        Radius.circular(20 + e * 16),
      ),
      ring,
    );
    final rng = math.Random(7);
    final p = Paint();
    for (var i = 0; i < 10; i++) {
      final ang = (i / 10) * 2 * math.pi + rng.nextDouble() * .5;
      final dist = base * (.5 + rng.nextDouble() * .35) * e;
      final pos = c + Offset(math.cos(ang), math.sin(ang)) * (dist + base * .3) + Offset(0, 10 * k * k);
      p.color = Colors.white.withValues(alpha: (1 - k) * .85);
      canvas.drawCircle(pos, (1 - k) * (1.6 + rng.nextDouble() * 1.8), p);
    }
  }

  @override
  bool shouldRepaint(covariant _LaunchPainter o) => o.k != k;
}
