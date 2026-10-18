import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../theme.dart';
import 'mascot.dart';

/// Ponto de conexão com "sonar": um anel que se expande e some (ritmo lento = ok,
/// rápido = desconectado). Muda de cor com transição suave.
class StatusDot extends StatefulWidget {
  final bool connected;
  final double size;
  const StatusDot({super.key, required this.connected, this.size = 7});

  @override
  State<StatusDot> createState() => _StatusDotState();
}

class _StatusDotState extends State<StatusDot> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: _dur)..repeat();

  Duration get _dur => widget.connected ? const Duration(milliseconds: 2200) : const Duration(milliseconds: 900);

  @override
  void didUpdateWidget(StatusDot old) {
    super.didUpdateWidget(old);
    if (old.connected != widget.connected) {
      _c.duration = _dur;
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.connected ? kOk : kErr;
    final s = widget.size;
    return RepaintBoundary(
      child: SizedBox(
        width: s,
        height: s,
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) {
            final k = Curves.easeOut.transform(_c.value);
            return CustomPaint(
              painter: _SonarPainter(color, k, s),
              child: const SizedBox.expand(),
            );
          },
        ),
      ),
    );
  }
}

class _SonarPainter extends CustomPainter {
  final Color color;
  final double k;
  final double s;
  _SonarPainter(this.color, this.k, this.s);

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    canvas.drawCircle(
      c,
      s / 2 + k * s * 1.3,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = color.withValues(alpha: .55 * (1 - k)),
    );
    canvas.drawCircle(c, s / 2 * (1 + .12 * (1 - k)), Paint()..color = color.withValues(alpha: .35)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4));
    canvas.drawCircle(c, s / 2, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _SonarPainter o) => o.k != k || o.color != color;
}

/// Barra fina (retrato): TAPKEY + status.
class AppHeader extends StatelessWidget {
  final bool connected;
  final bool locked;
  final VoidCallback onLock;
  const AppHeader({super.key, required this.connected, required this.locked, required this.onLock});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18),
        child: Row(
          children: [
            Mascot(connected: connected, size: 38),
            const SizedBox(width: 10),
            const Text(
              'TAPKEY',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, letterSpacing: 3.5, color: kAccent),
            ),
            const Spacer(),
            IconButton(
              tooltip: 'Bloquear / desbloquear',
              visualDensity: VisualDensity.compact,
              onPressed: onLock,
              icon: AnimatedSwitcher(
                duration: const Duration(milliseconds: 380),
                switchInCurve: Curves.elasticOut,
                transitionBuilder: (c, a) => ScaleTransition(
                  scale: a,
                  child: RotationTransition(turns: Tween(begin: -.12, end: 0.0).animate(a), child: c),
                ),
                child: Icon(locked ? Icons.lock : Icons.lock_open,
                    key: ValueKey(locked), size: 19, color: locked ? kAccent : kMuted),
              ),
            ),
            const SizedBox(width: 4),
            StatusDot(connected: connected),
            const SizedBox(width: 7),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              transitionBuilder: (c, a) => FadeTransition(
                opacity: a,
                child: SlideTransition(position: Tween(begin: const Offset(0, .5), end: Offset.zero).animate(a), child: c),
              ),
              child: Text(connected ? 'Conectado' : 'Desconectado',
                  key: ValueKey(connected),
                  style: TextStyle(color: connected ? kOk : kErr, fontWeight: FontWeight.w500, fontSize: 12)),
            ),
          ],
        ),
      ),
    ).animate().fadeIn(duration: 400.ms).slideY(begin: -0.4, curve: Curves.easeOutCubic);
  }
}
