import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../theme.dart';
import 'mascot.dart';

/// Ponto de conexão (verde/vermelho) com leve pulsação.
class StatusDot extends StatelessWidget {
  final bool connected;
  final double size;
  const StatusDot({super.key, required this.connected, this.size = 7});

  @override
  Widget build(BuildContext context) {
    final color = connected ? kOk : kErr;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: [BoxShadow(color: color.withValues(alpha: 0.7), blurRadius: 6)],
      ),
    )
        .animate(key: ValueKey(connected), onPlay: (c) => c.repeat(reverse: true))
        .fade(begin: 0.55, end: 1, duration: 1000.ms);
  }
}

/// Barra fina (retrato): TAPKEY + status.
class AppHeader extends StatelessWidget {
  final bool connected;
  const AppHeader({super.key, required this.connected});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18),
        child: Row(
          children: [
            Mascot(connected: connected, size: 36),
            const SizedBox(width: 10),
            const Text(
              'TAPKEY',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, letterSpacing: 3.5, color: kAccent),
            ),
            const Spacer(),
            StatusDot(connected: connected),
            const SizedBox(width: 7),
            Text(connected ? 'Conectado' : 'Desconectado',
                style: TextStyle(
                    color: connected ? kOk : kErr, fontWeight: FontWeight.w500, fontSize: 12)),
          ],
        ),
      ),
    ).animate().fadeIn(duration: 400.ms).slideY(begin: -0.4, curve: Curves.easeOutCubic);
  }
}
