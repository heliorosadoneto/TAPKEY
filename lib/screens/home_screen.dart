import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../state.dart';
import '../theme.dart';
import '../widgets/app_icon.dart';
import '../widgets/glow_tile.dart';
import '../widgets/island.dart';
import '../widgets/mascot.dart';
import 'add_screen.dart';

class HomeScreen extends StatelessWidget {
  final AppState state;
  const HomeScreen({super.key, required this.state});

  Future<void> _launch(BuildContext context, AppItem a) async {
    island.show('Abrindo ${a.name}…', kind: IslandKind.info, duration: const Duration(seconds: 6));
    mascotController.working(true);
    final (ok, msg) = await state.launch(a);
    mascotController.working(false);
    if (ok) {
      mascotController.happy();
      island.show('Abrindo ${a.name}…', kind: IslandKind.success);
    } else {
      mascotController.error();
      island.show(msg, kind: IslandKind.error, duration: const Duration(seconds: 3));
    }
  }

  void _options(BuildContext context, AppItem a) {
    final idx = state.favorites.indexWhere((e) => e.id == a.id);
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF14142A),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 16),
          AppIcon(state: state, app: a, size: 48),
          const SizedBox(height: 8),
          Text(a.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          if (idx > 0)
            ListTile(
              leading: const Icon(Icons.vertical_align_top, color: kAccent),
              title: const Text('Mover para o início'),
              onTap: () { state.moveToFront(a.id); Navigator.pop(ctx); },
            ),
          if (idx > 0)
            ListTile(
              leading: const Icon(Icons.arrow_back, color: kAccent),
              title: const Text('Mover para trás'),
              onTap: () { state.move(a.id, -1); Navigator.pop(ctx); },
            ),
          if (idx < state.favorites.length - 1)
            ListTile(
              leading: const Icon(Icons.arrow_forward, color: kAccent),
              title: const Text('Mover para frente'),
              onTap: () { state.move(a.id, 1); Navigator.pop(ctx); },
            ),
          ListTile(
            leading: const Icon(Icons.delete_outline, color: kErr),
            title: const Text('Remover dos favoritos'),
            onTap: () { state.removeFavorite(a.id); Navigator.pop(ctx); },
          ),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final favs = state.favorites;
    final landscape = MediaQuery.orientationOf(context) == Orientation.landscape;
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(landscape ? 16 : 18),
          boxShadow: [BoxShadow(color: kAccent.withValues(alpha: 0.18), blurRadius: 18)],
        ),
        child: landscape
            ? FloatingActionButton.small(
                backgroundColor: kAccent,
                foregroundColor: Colors.black,
                tooltip: 'Adicionar atalho',
                onPressed: () => _openAdd(context),
                child: const Icon(Icons.add),
              )
            : FloatingActionButton.extended(
                backgroundColor: kAccent,
                foregroundColor: Colors.black,
                icon: const Icon(Icons.add),
                label: const Text('Adicionar atalho'),
                onPressed: () => _openAdd(context),
              ),
      ).animate().scale(delay: 500.ms, duration: 500.ms, curve: Curves.elasticOut),
      body: favs.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.apps_rounded, size: 56, color: kMuted)
                      .animate(onPlay: (c) => c.repeat(reverse: true))
                      .scale(begin: const Offset(0.92, 0.92), end: const Offset(1.08, 1.08), duration: 1200.ms),
                  const SizedBox(height: 12),
                  const Text('Nenhum atalho ainda',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  const Text('Toque em “Adicionar atalho” para escolher os aplicativos do seu notebook.',
                      textAlign: TextAlign.center, style: TextStyle(color: kMuted)),
                ]),
              ),
            )
          : LayoutBuilder(builder: (context, c) {
              final n = favs.length;
              final gap = landscape ? 10.0 : 14.0;
              final pad = landscape ? 10.0 : 16.0;
              final availW = c.maxWidth - 2 * pad;
              final availH = c.maxHeight - 2 * pad;
              // Cartões sempre QUADRADOS (1:1). Escolhe o nº de colunas para
              // preencher a tela com cartões do maior tamanho possível.
              int cols;
              if (landscape) {
                cols = 0;
                double tileFor(int k) => (availW - gap * (k - 1)) / k;
                for (var k = 2; k <= 14; k++) {
                  final w = tileFor(k);
                  final rows = (n / k).ceil();
                  if (w <= 170 && w >= 80 && rows * w + (rows - 1) * gap <= availH) {
                    cols = k;
                    break;
                  }
                }
                if (cols == 0) cols = (availW / 120).round().clamp(2, 14);
              } else {
                cols = c.maxWidth < 300 ? 2 : 3;
              }
              return GridView.builder(
                padding: EdgeInsets.fromLTRB(pad, pad, pad, landscape ? pad : 90),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: cols,
                  mainAxisSpacing: gap,
                  crossAxisSpacing: gap,
                  childAspectRatio: 1,
                ),
                itemCount: n,
                itemBuilder: (context, i) {
                  final a = favs[i];
                  return GlowTile(
                    key: ValueKey(a.id),
                    state: state,
                    app: a,
                    onTap: () => _launch(context, a),
                    onLongPress: () => _options(context, a),
                  )
                      .animate(delay: (70 * i).ms)
                      .fadeIn(duration: 450.ms)
                      .slideY(begin: 0.3, duration: 550.ms, curve: Curves.easeOutCubic)
                      .scale(begin: const Offset(0.6, 0.6), duration: 900.ms, curve: Curves.elasticOut);
                },
              );
            }),
    );
  }

  void _openAdd(BuildContext context) => Navigator.push(
        context,
        PageRouteBuilder(
          transitionDuration: const Duration(milliseconds: 450),
          pageBuilder: (_, _, _) => AddScreen(state: state),
          transitionsBuilder: (_, a, _, child) => FadeTransition(
            opacity: a,
            child: SlideTransition(
              position: Tween(begin: const Offset(0, 0.15), end: Offset.zero)
                  .animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic)),
              child: child,
            ),
          ),
        ),
      );
}
