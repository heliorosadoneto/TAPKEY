import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../state.dart';
import '../theme.dart';
import '../widgets/app_icon.dart';
import '../widgets/glow_tile.dart';
import '../widgets/island.dart';
import '../widgets/mascot.dart';
import '../widgets/stage.dart';
import 'add_screen.dart';

class HomeScreen extends StatefulWidget {
  final AppState state;
  const HomeScreen({super.key, required this.state});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  AppState get state => widget.state;

  bool _editing = false;
  String? _dragId;
  Offset _dragTopLeft = Offset.zero;
  Offset _grab = Offset.zero;
  String? _settleId;
  List<String> _order = [];
  final Set<String> _removing = {};
  final Map<String, int> _delays = {};
  final ScrollController _scroll = ScrollController();
  final GlobalKey _viewKey = GlobalKey();
  late final AnimationController _wobble = AnimationController(vsync: this, duration: const Duration(milliseconds: 420));

  // geometria atual do grid
  int _cols = 3;
  double _ts = 100;
  double _gap = 14;
  double _pad = 16;

  @override
  void initState() {
    super.initState();
    state.addListener(_onState);
  }

  @override
  void dispose() {
    state.removeListener(_onState);
    _wobble.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onState() {
    if (mounted) setState(() {});
  }

  Future<void> _launch(BuildContext context, AppItem a, Offset? at) async {
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

  // ---------- edição / arrastar ----------

  void _setEditing(bool v) {
    if (_editing == v) return;
    setState(() => _editing = v);
    if (v) {
      _wobble.repeat(reverse: false);
      mascotController.surprised();
    } else {
      _wobble.stop();
      mascotController.happy();
    }
  }

  Offset _slot(int i) => Offset(_pad + (i % _cols) * (_ts + _gap), _pad + (i ~/ _cols) * (_ts + _gap));

  Offset _viewLocal(Offset global) {
    final box = _viewKey.currentContext?.findRenderObject();
    if (box is! RenderBox) return global;
    final off = _scroll.hasClients ? _scroll.offset : 0.0;
    return box.globalToLocal(global) + Offset(0, off);
  }

  void _dragStart(String id, Offset global) {
    HapticFeedback.mediumImpact();
    final idx = _order.indexOf(id);
    if (idx < 0) return;
    _setEditing(true);
    final f = _viewLocal(global);
    setState(() {
      _dragId = id;
      _grab = f - _slot(idx);
      _dragTopLeft = _slot(idx);
    });
    mascotController.hop();
  }

  void _dragMove(Offset global) {
    if (_dragId == null) return;
    // rolagem automática perto das bordas
    final box = _viewKey.currentContext?.findRenderObject();
    if (box is RenderBox && _scroll.hasClients) {
      final y = box.globalToLocal(global).dy;
      final max = _scroll.position.maxScrollExtent;
      if (y < 70 && _scroll.offset > 0) {
        _scroll.jumpTo(math.max(0, _scroll.offset - 14));
      } else if (y > box.size.height - 70 && _scroll.offset < max) {
        _scroll.jumpTo(math.min(max, _scroll.offset + 14));
      }
    }
    final f = _viewLocal(global);
    final tl = f - _grab;
    final center = tl + Offset(_ts / 2, _ts / 2);
    final col = ((center.dx - _pad) / (_ts + _gap)).floor().clamp(0, _cols - 1);
    final row = ((center.dy - _pad) / (_ts + _gap)).floor().clamp(0, (_order.length / _cols).ceil() - 1);
    final target = (row * _cols + col).clamp(0, _order.length - 1);
    final cur = _order.indexOf(_dragId!);
    setState(() {
      _dragTopLeft = tl;
      if (target != cur) {
        _order.removeAt(cur);
        _order.insert(target, _dragId!);
        HapticFeedback.selectionClick();
      }
    });
  }

  void _dragEnd() {
    final id = _dragId;
    if (id == null) return;
    HapticFeedback.lightImpact();
    setState(() {
      _dragId = null;
      _settleId = id;
    });
    state.setOrder(List.of(_order));
    Future.delayed(const Duration(milliseconds: 900), () {
      if (mounted && _settleId == id) setState(() => _settleId = null);
    });
  }

  void _remove(AppItem a) {
    HapticFeedback.mediumImpact();
    mascotController.squish();
    setState(() => _removing.add(a.id));
    Future.delayed(const Duration(milliseconds: 260), () async {
      await state.removeFavorite(a.id);
      _removing.remove(a.id);
      if (mounted) {
        if (state.favorites.isEmpty) _setEditing(false);
        setState(() {});
      }
    });
  }

  // ---------- opções (com Hero do ícone) ----------

  void _options(BuildContext context, AppItem a) {
    HapticFeedback.selectionClick();
    Navigator.of(context).push(PageRouteBuilder(
      opaque: false,
      barrierDismissible: true,
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 460),
      reverseTransitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (ctx, anim, _) => _OptionsPage(state: state, app: a, anim: anim),
      transitionsBuilder: (ctx, anim, _, child) => child,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final favs = state.favorites;
    if (_dragId == null) {
      _order = favs.map((e) => e.id).toList();
    } else {
      // mantém a ordem viva do arrasto, mas descarta ids removidos
      _order.removeWhere((id) => !favs.any((e) => e.id == id));
    }
    final byId = {for (final a in favs) a.id: a};
    final landscape = MediaQuery.orientationOf(context) == Orientation.landscape;
    return PopScope(
      canPop: !_editing,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _editing) _setEditing(false);
      },
      child: Scaffold(
        backgroundColor: Colors.transparent,
        floatingActionButton: AnimatedSwitcher(
          duration: const Duration(milliseconds: 380),
          switchInCurve: Curves.easeOutBack,
          switchOutCurve: Curves.easeIn,
          transitionBuilder: (c, a) => ScaleTransition(scale: a, child: FadeTransition(opacity: a, child: c)),
          child: _editing
              ? FloatingActionButton.extended(
                  key: const ValueKey('done'),
                  heroTag: null,
                  backgroundColor: kAccent,
                  foregroundColor: Colors.black,
                  icon: const Icon(Icons.check),
                  label: const Text('Concluir'),
                  onPressed: () {
                    HapticFeedback.lightImpact();
                    _setEditing(false);
                  },
                )
              : _addFab(context, landscape),
        ),
        body: favs.isEmpty ? _empty() : _grid(context, byId, landscape),
      ),
    );
  }

  Widget _addFab(BuildContext context, bool landscape) {
    return Container(
      key: const ValueKey('add'),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(landscape ? 16 : 18),
        boxShadow: [BoxShadow(color: kAccent.withValues(alpha: 0.18), blurRadius: 18)],
      ),
      child: landscape
          ? FloatingActionButton.small(
              heroTag: 'add-hero',
              backgroundColor: kAccent,
              foregroundColor: Colors.black,
              tooltip: 'Adicionar atalho',
              onPressed: () => _openAdd(context),
              child: const Icon(Icons.add),
            )
          : FloatingActionButton.extended(
              heroTag: 'add-hero',
              backgroundColor: kAccent,
              foregroundColor: Colors.black,
              icon: const Icon(Icons.add),
              label: const Text('Adicionar atalho'),
              onPressed: () => _openAdd(context),
            ),
    );
  }

  Widget _empty() {
    return Column(children: [
      if (MediaQuery.orientationOf(context) == Orientation.portrait)
        TapiStage(connected: state.connected, screensaverSeconds: state.screensaverSeconds),
      Expanded(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.apps_rounded, size: 56, color: kMuted)
                  .animate(onPlay: (c) => c.repeat(reverse: true))
                  .scale(begin: const Offset(0.92, 0.92), end: const Offset(1.08, 1.08), duration: 1200.ms),
              const SizedBox(height: 12),
              const Text('Nenhum atalho ainda', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              const Text('Toque em “Adicionar atalho” para escolher os aplicativos do seu notebook.',
                  textAlign: TextAlign.center, style: TextStyle(color: kMuted)),
            ]),
          ),
        ),
      ),
    ]);
  }

  Widget _grid(BuildContext context, Map<String, AppItem> byId, bool landscape) {
    return Column(children: [
      if (!landscape) TapiStage(connected: state.connected, screensaverSeconds: state.screensaverSeconds),
      Expanded(
        child: LayoutBuilder(builder: (context, c) {
          final n = _order.length;
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
          final ts = (availW - gap * (cols - 1)) / cols;
          _cols = cols;
          _ts = ts;
          _gap = gap;
          _pad = pad;
          final rows = (n / cols).ceil();
          final totalH = pad + rows * ts + (rows - 1) * gap + (landscape ? pad : 90);

          final ids = List<String>.of(_order);
          // o item arrastado fica por último (em cima)
          if (_dragId != null) {
            ids.remove(_dragId);
            ids.add(_dragId!);
          }
          return NotificationListener<ScrollNotification>(
            onNotification: (n) {
              if (n is ScrollStartNotification || n is ScrollUpdateNotification) {
                if (_dragId == null) TapiStage.reactToScroll();
              }
              return false;
            },
            child: SingleChildScrollView(
              key: _viewKey,
              controller: _scroll,
              clipBehavior: Clip.none,
              physics: _dragId != null ? const NeverScrollableScrollPhysics() : const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
              child: SizedBox(
                height: totalH,
                width: c.maxWidth,
                child: Stack(clipBehavior: Clip.none, children: [
                  for (final id in ids)
                    if (byId[id] != null) _positionedTile(context, byId[id]!, _order.indexOf(id)),
                ]),
              ),
            ),
          );
        }),
      ),
    ]);
  }

  Widget _positionedTile(BuildContext context, AppItem a, int index) {
    final dragging = _dragId == a.id;
    final pos = dragging ? _dragTopLeft : _slot(index);
    final settle = _settleId == a.id;
    _delays.putIfAbsent(a.id, () => _delays.isEmpty ? 0 : (_delays.length < 14 ? 70 * _delays.length : 0));
    final removing = _removing.contains(a.id);
    return AnimatedPositioned(
      key: ValueKey(a.id),
      duration: dragging ? Duration.zero : Duration(milliseconds: settle ? 700 : 420),
      curve: settle ? Curves.elasticOut : Curves.easeOutBack,
      left: pos.dx,
      top: pos.dy,
      width: _ts,
      height: _ts,
      child: AnimatedScale(
        scale: removing ? 0 : 1,
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeInBack,
        child: AnimatedOpacity(
          opacity: removing ? 0 : 1,
          duration: const Duration(milliseconds: 240),
          child: GlowTile(
            state: state,
            app: a,
            editing: _editing,
            lifted: dragging,
            wobble: _wobble,
            phase: (a.id.hashCode % 100) / 100.0,
            onRemove: () => _remove(a),
            onTap: () async {
              if (_editing) {
                _options(context, a);
                return;
              }
              final box = context.findRenderObject();
              Offset? at;
              if (box is RenderBox && box.attached) {
                // posição global aproximada do cartão (para o Tapi olhar para ele)
                final vb = _viewKey.currentContext?.findRenderObject();
                if (vb is RenderBox) {
                  final off = _scroll.hasClients ? _scroll.offset : 0.0;
                  at = vb.localToGlobal(_slot(index) + Offset(_ts / 2, _ts / 2 - off));
                }
              }
              if (at != null) TapiStage.reactToTap(at);
              await _launch(context, a, at);
            },
            onLongPressStart: (d) => _dragStart(a.id, d.globalPosition),
            onLongPressMoveUpdate: (d) => _dragMove(d.globalPosition),
            onLongPressEnd: (_) => _dragEnd(),
          ),
        ),
      )
          .animate(delay: _delays[a.id]!.ms)
          .fadeIn(duration: 450.ms)
          .slideY(begin: 0.3, duration: 550.ms, curve: Curves.easeOutCubic)
          .scale(begin: const Offset(0.6, 0.6), duration: 900.ms, curve: Curves.elasticOut),
    );
  }

  void _openAdd(BuildContext context) {
    HapticFeedback.selectionClick();
    mascotController.curious();
    Navigator.push(
      context,
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 520),
        reverseTransitionDuration: const Duration(milliseconds: 380),
        pageBuilder: (_, _, _) => AddScreen(state: state),
        transitionsBuilder: (ctx, a, sec, child) =>
            const SharedAxisTransitions().buildTransitions<void>(
              MaterialPageRoute<void>(builder: (_) => const SizedBox()),
              ctx,
              a,
              sec,
              child,
            ),
      ),
    );
  }
}

/// Folha de opções do atalho: o ícone voa do cartão até aqui (Hero) e a folha sobe com mola.
class _OptionsPage extends StatelessWidget {
  final AppState state;
  final AppItem app;
  final Animation<double> anim;
  const _OptionsPage({required this.state, required this.app, required this.anim});

  @override
  Widget build(BuildContext context) {
    final idx = state.favorites.indexWhere((e) => e.id == app.id);
    final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutBack, reverseCurve: Curves.easeInCubic);
    Widget item(int i, IconData icon, Color color, String label, VoidCallback onTap) {
      return ListTile(
        leading: Icon(icon, color: color),
        title: Text(label),
        onTap: () {
          HapticFeedback.selectionClick();
          Navigator.pop(context);
          onTap();
        },
      )
          .animate(delay: (60 + 35 * i).ms)
          .fadeIn(duration: 260.ms)
          .slideX(begin: .08, duration: 320.ms, curve: Curves.easeOutCubic);
    }

    var i = 0;
    return Align(
      alignment: Alignment.bottomCenter,
      child: SlideTransition(
        position: Tween(begin: const Offset(0, 1), end: Offset.zero).animate(curved),
        child: Material(
          color: const Color(0xFF14142A),
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
          child: SafeArea(
            top: false,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const SizedBox(height: 16),
              Hero(tag: 'icon-${app.id}', child: AppIcon(state: state, app: app, size: 48)),
              const SizedBox(height: 8),
              Text(app.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              if (idx > 0) item(i++, Icons.vertical_align_top, kAccent, 'Mover para o início', () => state.moveToFront(app.id)),
              if (idx > 0) item(i++, Icons.arrow_back, kAccent, 'Mover para trás', () => state.move(app.id, -1)),
              if (idx < state.favorites.length - 1)
                item(i++, Icons.arrow_forward, kAccent, 'Mover para frente', () => state.move(app.id, 1)),
              item(i++, Icons.delete_outline, kErr, 'Remover dos favoritos', () => state.removeFavorite(app.id)),
              const SizedBox(height: 8),
            ]),
          ),
        ),
      ),
    );
  }
}
