import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../state.dart';
import '../theme.dart';
import '../widgets/app_icon.dart';
import '../widgets/island.dart';
import '../widgets/mascot.dart';

class AddScreen extends StatefulWidget {
  final AppState state;
  const AddScreen({super.key, required this.state});

  @override
  State<AddScreen> createState() => _AddScreenState();
}

class _AddScreenState extends State<AddScreen> {
  List<AppItem> _all = [];
  String _q = '';
  bool _loading = true;
  String? _error;
  final Set<String> _flash = {};

  @override
  void initState() {
    super.initState();
    widget.state.addListener(_rebuild);
    _load();
  }

  @override
  void dispose() {
    widget.state.removeListener(_rebuild);
    super.dispose();
  }

  void _rebuild() => setState(() {});

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final l = await widget.state.fetchApps();
      if (mounted) setState(() { _all = l; _loading = false; });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Não foi possível buscar os aplicativos do notebook.\nVerifique se o agente está rodando e as Configurações.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    final q = _q.toLowerCase();
    final list = _all.where((a) => a.name.toLowerCase().contains(q)).toList();
    return Scaffold(
      appBar: AppBar(title: Row(mainAxisSize: MainAxisSize.min, children: [
        Hero(
          tag: 'add-hero',
          child: Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(color: kAccent, borderRadius: BorderRadius.circular(9)),
            child: const Icon(Icons.add, size: 18, color: Colors.black),
          ),
        ),
        const SizedBox(width: 10),
        const Text('Adicionar atalho'),
      ]), actions: [
        IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
      ]),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: TextField(
            onChanged: (v) => setState(() => _q = v),
            decoration: const InputDecoration(
              hintText: 'Buscar aplicativo…',
              prefixIcon: Icon(Icons.search),
            ),
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator(color: kAccent))
              : _error != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          const Icon(Icons.wifi_off, size: 56, color: kErr),
                          const SizedBox(height: 12),
                          Text(_error!, textAlign: TextAlign.center),
                          const SizedBox(height: 12),
                          FilledButton(onPressed: _load, child: const Text('Tentar de novo')),
                        ]),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.only(bottom: 24),
                      itemCount: list.length,
                      itemBuilder: (context, i) {
                        final a = list[i];
                        final fav = s.isFavorite(a.id);
                        final flash = _flash.contains(a.id);
                        return AnimatedContainer(
                          duration: const Duration(milliseconds: 350),
                          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            color: flash ? Colors.white.withValues(alpha: .09) : Colors.transparent,
                          ),
                          child: ListTile(
                            leading: AppIcon(state: s, app: a, size: 40),
                            title: Text(a.name),
                            subtitle: Text(a.id, maxLines: 1, overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 11, color: kMuted)),
                            trailing: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 420),
                              switchInCurve: Curves.elasticOut,
                              transitionBuilder: (c, a) => ScaleTransition(scale: a, child: RotationTransition(turns: Tween(begin: -.15, end: 0.0).animate(a), child: c)),
                              child: fav
                                  ? const Icon(Icons.check_circle, key: ValueKey('on'), color: kAccent)
                                  : const Icon(Icons.add_circle_outline, key: ValueKey('off'), color: kAccent),
                            ),
                            onTap: () {
                              if (fav) {
                                HapticFeedback.selectionClick();
                                s.removeFavorite(a.id);
                                mascotController.squish();
                              } else {
                                HapticFeedback.lightImpact();
                                s.addFavorite(a);
                                island.show('${a.name} adicionado', kind: IslandKind.success, duration: const Duration(milliseconds: 1400));
                                mascotController.love();
                                setState(() => _flash.add(a.id));
                                Future.delayed(const Duration(milliseconds: 600), () {
                                  if (mounted) setState(() => _flash.remove(a.id));
                                });
                              }
                            },
                          ),
                        ).animate().fadeIn(delay: (22 * (i < 15 ? i : 0)).ms, duration: 320.ms).slideX(begin: 0.12, curve: Curves.easeOutCubic);
                      },
                    ),
        ),
      ]),
    );
  }
}
