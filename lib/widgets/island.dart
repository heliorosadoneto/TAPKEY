import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

import '../theme.dart';
import 'mascot.dart';

enum IslandKind { info, success, error, lock }

/// Controla a "ilha": pílula no topo da tela que mostra eventos e feedback.
class IslandController extends ChangeNotifier {
  String text = '';
  IslandKind kind = IslandKind.info;
  Duration duration = const Duration(milliseconds: 2400);
  int seq = 0;

  void show(String text, {IslandKind kind = IslandKind.info, Duration? duration}) {
    this.text = text;
    this.kind = kind;
    if (duration != null) this.duration = duration;
    seq++;
    notifyListeners();
  }
}

final IslandController island = IslandController();

/// Pílula no topo: entra com mola (resposta ~0,5 s, amortecimento 0,72) e fecha
/// em ~340 ms com ease. O mascote mora dentro dela.
class IslandHost extends StatefulWidget {
  const IslandHost({super.key});

  @override
  State<IslandHost> createState() => _IslandHostState();
}

class _IslandHostState extends State<IslandHost> with SingleTickerProviderStateMixin {
  late final AnimationController _ctl = AnimationController.unbounded(vsync: this, value: 0);
  final MascotController _mc = MascotController();
  Timer? _timer;
  int _shownSeq = 0;

  // resposta 0,5 s => rigidez = (2π / 0,5)²; amortecimento 0,72
  static final _spring = SpringDescription.withDampingRatio(
    mass: 1,
    stiffness: (2 * 3.141592653589793 / 0.5) * (2 * 3.141592653589793 / 0.5),
    ratio: 0.72,
  );

  @override
  void initState() {
    super.initState();
    island.addListener(_onShow);
  }

  @override
  void dispose() {
    island.removeListener(_onShow);
    _timer?.cancel();
    _ctl.dispose();
    super.dispose();
  }

  void _onShow() {
    if (!mounted) return;
    _timer?.cancel();
    _shownSeq = island.seq;
    setState(() {});
    _ctl.animateWith(SpringSimulation(_spring, _ctl.value, 1, _ctl.velocity));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      switch (island.kind) {
        case IslandKind.success:
          _mc.happy();
        case IslandKind.error:
          _mc.error();
        case IslandKind.lock:
          _mc.wink();
        case IslandKind.info:
          break;
      }
    });
    _timer = Timer(island.duration, _close);
  }

  void _close() {
    if (!mounted) return;
    _ctl.animateTo(0, duration: const Duration(milliseconds: 340), curve: Curves.easeInOutCubic);
  }

  IconData? get _icon => switch (island.kind) {
        IslandKind.lock => Icons.lock_outline,
        _ => null,
      };

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: IgnorePointer(
        child: AnimatedBuilder(
          animation: _ctl,
          builder: (context, _) {
            final v = _ctl.value;
            if (v <= 0.002) return const SizedBox.shrink();
            final err = island.kind == IslandKind.error;
            return Padding(
              padding: EdgeInsets.only(top: top + 6),
              child: Align(
                alignment: Alignment.topCenter,
                child: Opacity(
                  opacity: (v * 1.6).clamp(0.0, 1.0),
                  child: Transform.translate(
                    offset: Offset(0, -60 * (1 - v)),
                    child: Transform.scale(
                      scale: 0.4 + 0.6 * v,
                      alignment: Alignment.topCenter,
                      child: Container(
                        key: ValueKey(_shownSeq),
                        constraints: const BoxConstraints(minHeight: 44, maxWidth: 340),
                        padding: const EdgeInsets.fromLTRB(8, 4, 18, 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF121214),
                          borderRadius: BorderRadius.circular(26),
                          border: Border.all(color: err ? kErr.withValues(alpha: .55) : kBorder),
                          boxShadow: [
                            BoxShadow(color: Colors.black.withValues(alpha: .6), blurRadius: 18, offset: const Offset(0, 6)),
                            BoxShadow(color: kAccent.withValues(alpha: .06), blurRadius: 14),
                          ],
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Mascot(
                            controller: _mc,
                            size: 34,
                            interactive: false,
                            alwaysOn: true,
                            connected: !err,
                          ),
                          const SizedBox(width: 6),
                          if (_icon != null) ...[
                            Icon(_icon, size: 16, color: kAccent),
                            const SizedBox(width: 6),
                          ],
                          Flexible(
                            child: Text(
                              island.text,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w600,
                                color: err ? const Color(0xFFFFB4B4) : Colors.white,
                                decoration: TextDecoration.none,
                              ),
                            ),
                          ),
                        ]),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
