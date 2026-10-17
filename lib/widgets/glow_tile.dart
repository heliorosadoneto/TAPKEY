import 'package:flutter/material.dart';

import '../state.dart';
import '../theme.dart';
import 'app_icon.dart';

/// Cartão cinza com brilho sutil prata e animação de toque.
class GlowTile extends StatefulWidget {
  final AppState state;
  final AppItem app;
  final Future<void> Function() onTap;
  final VoidCallback onLongPress;
  const GlowTile({
    super.key,
    required this.state,
    required this.app,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  State<GlowTile> createState() => _GlowTileState();
}

class _GlowTileState extends State<GlowTile> {
  bool _down = false;
  bool _pulse = false;

  Future<void> _tap() async {
    setState(() => _pulse = true);
    Future.delayed(const Duration(milliseconds: 450), () {
      if (mounted) setState(() => _pulse = false);
    });
    await widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    final glow = _pulse ? 0.30 : (_down ? 0.16 : 0.05);
    return AnimatedScale(
      // aperta rápido; solta com mola (elástico)
      scale: _down ? 0.90 : 1.0,
      duration: Duration(milliseconds: _down ? 110 : 650),
      curve: _down ? Curves.easeOut : Curves.elasticOut,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _pulse ? kAccent.withValues(alpha: 0.7) : kBorder),
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [kCardTop, kCard],
          ),
          boxShadow: [
            BoxShadow(color: kAccent.withValues(alpha: glow), blurRadius: _pulse ? 26 : 14),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            splashColor: Colors.white.withValues(alpha: 0.12),
            highlightColor: Colors.white.withValues(alpha: 0.05),
            onTap: _tap,
            onLongPress: widget.onLongPress,
            onHighlightChanged: (v) => setState(() => _down = v),
            child: LayoutBuilder(builder: (context, c) {
              // Responsivo ao tamanho do cartão
              final base = c.maxWidth < c.maxHeight ? c.maxWidth : c.maxHeight;
              final iconSize = (base * 0.46).clamp(28.0, 96.0);
              final font = (base * 0.095).clamp(11.0, 15.0);
              return Padding(
                padding: EdgeInsets.symmetric(horizontal: 6, vertical: base * 0.07),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Center(
                        child: AppIcon(state: widget.state, app: widget.app, size: iconSize),
                      ),
                    ),
                    Text(
                      widget.app.name,
                      maxLines: 1,
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: font, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}
