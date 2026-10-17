import 'package:flutter/material.dart';

import '../state.dart';
import '../theme.dart';

/// Ícone do app vindo do notebook, com avatar de letra como alternativa.
class AppIcon extends StatelessWidget {
  final AppState state;
  final AppItem app;
  final double size;
  const AppIcon({super.key, required this.state, required this.app, this.size = 48});

  @override
  Widget build(BuildContext context) {
    final letter = app.name.isEmpty ? '?' : app.name[0].toUpperCase();
    final fallback = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFF2C2C31),
        border: Border.all(color: kBorder),
      ),
      child: Text(letter,
          style: TextStyle(fontSize: size * 0.45, fontWeight: FontWeight.w600, color: kAccent)),
    );
    return SizedBox(
      width: size,
      height: size,
      child: Image.network(
        '${state.baseUrl}/icon/${Uri.encodeComponent(app.id)}',
        headers: state.headers,
        width: size,
        height: size,
        fit: BoxFit.contain,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => fallback,
      ),
    );
  }
}
