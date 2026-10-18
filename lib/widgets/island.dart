import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';

import '../theme.dart';
import 'mascot.dart';

enum IslandKind { info, success, error, lock, cursor, warn, greet }

/// Controla a "ilha": pílula no topo da tela que mostra eventos e feedback.
class IslandController extends ChangeNotifier {
  String text = '';
  IslandKind kind = IslandKind.info;
  Duration duration = const Duration(milliseconds: 2400);
  int seq = 0;

  void show(
    String text, {
    IslandKind kind = IslandKind.info,
    Duration? duration,
  }) {
    this.text = text;
    this.kind = kind;
    this.duration = duration ?? const Duration(milliseconds: 2400);
    seq++;
    // tato por tipo de evento (centralizado aqui)
    switch (kind) {
      case IslandKind.error:
        HapticFeedback.heavyImpact();
      case IslandKind.success:
      case IslandKind.cursor:
        HapticFeedback.lightImpact();
      case IslandKind.warn:
        HapticFeedback.mediumImpact();
      case IslandKind.lock:
        HapticFeedback.selectionClick();
      case IslandKind.info:
      case IslandKind.greet:
        break;
    }
    notifyListeners();
  }
}

final IslandController island = IslandController();

/// Pílula no topo ("ilha"). Nasce como uma bolinha com o Tapi (mola com
/// overshoot), depois a forma se expande até o tamanho do conteúdo (morph), o
/// texto entra palavra por palavra (35 ms entre elas) com fade + desfoque, e ao
/// fechar tudo recolhe de volta numa bolinha antes de sumir.
class IslandHost extends StatefulWidget {
  const IslandHost({super.key});

  @override
  State<IslandHost> createState() => _IslandHostState();
}

class _IslandHostState extends State<IslandHost> with TickerProviderStateMixin {
  // aparecimento (0 → 1, com overshoot)
  late final AnimationController _open = AnimationController.unbounded(vsync: this, value: 0);
  // largura atual da pílula (mola)
  late final AnimationController _w = AnimationController.unbounded(vsync: this, value: _kDot);
  // revelação do conteúdo 0 → 1
  late final AnimationController _content = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
  final MascotController _mc = MascotController();
  Timer? _timer;
  Timer? _contentTimer;
  double _targetW = _kDot;
  double _targetH = 44;
  List<String> _words = const [];
  double _textMaxW = 200;
  double _textW = 100;
  int _shownSeq = 0;
  bool _closing = false;

  static const double _kDot = 44;
  static final _spring = SpringDescription.withDampingRatio(
    mass: 1,
    stiffness: (2 * 3.141592653589793 / 0.5) * (2 * 3.141592653589793 / 0.5),
    ratio: 0.68,
  );
  static final _widthSpring = SpringDescription.withDampingRatio(mass: 1, stiffness: 260, ratio: .78);

  @override
  void initState() {
    super.initState();
    island.addListener(_onShow);
  }

  @override
  void dispose() {
    island.removeListener(_onShow);
    _timer?.cancel();
    _contentTimer?.cancel();
    _open.dispose();
    _w.dispose();
    _content.dispose();
    super.dispose();
  }

  IconData? get _icon => switch (island.kind) {
    IslandKind.lock => Icons.lock_outline,
    IslandKind.cursor => Icons.terminal_rounded,
    IslandKind.warn => Icons.help_outline_rounded,
    IslandKind.success => Icons.check_rounded,
    IslandKind.error => Icons.error_outline_rounded,
    _ => null,
  };

  static const _textStyle = TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, decoration: TextDecoration.none);

  void _measure() {
    final screenW = MediaQuery.sizeOf(context).width;
    final maxPill = (screenW - 32).clamp(180.0, 340.0);
    final iconW = _icon != null ? 22.0 : 0.0;
    _textMaxW = maxPill - (8 + 34 + 6 + iconW + 18);
    final tp = TextPainter(
      text: TextSpan(text: island.text, style: DefaultTextStyle.of(context).style.merge(_textStyle)),
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 2,
    )..layout(maxWidth: _textMaxW);
    _textW = (tp.width.ceilToDouble() + 18).clamp(0.0, _textMaxW + 18).toDouble();
    _targetW = 8 + 34 + 6 + iconW + _textW + 8;
    _targetH = (tp.height + 16).clamp(44.0, 70.0);
    _words = island.text.split(' ');
  }

  void _onShow() {
    if (!mounted) return;
    _timer?.cancel();
    _contentTimer?.cancel();
    _shownSeq = island.seq;
    _closing = false;
    _measure();
    final wasClosed = _open.value < .02;
    if (wasClosed) {
      _w.value = _kDot;
      _content.value = 0;
      _open.animateWith(SpringSimulation(_spring, 0, 1, 0));
      // forma se expande logo depois do "pop"
      _contentTimer = Timer(const Duration(milliseconds: 170), _expand);
    } else {
      _open.animateWith(SpringSimulation(_spring, _open.value, 1, _open.velocity));
      _content.value = 0;
      _expand();
    }
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      switch (island.kind) {
        case IslandKind.success:
          _mc.happy();
        case IslandKind.error:
          _mc.error();
        case IslandKind.lock:
          _mc.wink();
        case IslandKind.cursor:
          _mc.happy();
        case IslandKind.warn:
          _mc.surprised();
        case IslandKind.greet:
          _mc.pop();
        case IslandKind.info:
          _mc.curious();
      }
    });
    _timer = Timer(island.duration + const Duration(milliseconds: 170), _close);
  }

  void _expand() {
    if (!mounted || _closing) return;
    _w.animateWith(SpringSimulation(_widthSpring, _w.value, _targetW, _w.velocity));
    _content.forward(from: 0);
  }

  void _close() {
    if (!mounted) return;
    _closing = true;
    _content.animateTo(0, duration: const Duration(milliseconds: 160), curve: Curves.easeIn);
    _w.animateWith(SpringSimulation(_widthSpring, _w.value, _kDot, _w.velocity));
    _contentTimer = Timer(const Duration(milliseconds: 210), () {
      if (!mounted || !_closing) return;
      _open.animateTo(0, duration: const Duration(milliseconds: 300), curve: Curves.easeInBack);
    });
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: IgnorePointer(
        child: AnimatedBuilder(
          animation: Listenable.merge([_open, _w, _content]),
          builder: (context, _) {
            final v = _open.value;
            if (v <= 0.002) return const SizedBox.shrink();
            final err = island.kind == IslandKind.error;
            final w = _w.value.clamp(_kDot, 400.0).toDouble();
            final c = _content.value;
            final reveal = ((w - _kDot) / (_targetW - _kDot).clamp(1, 999)).clamp(0.0, 1.0);
            final h = _kDot + (_targetH - _kDot) * reveal;
            final accent = switch (island.kind) {
              IslandKind.error => kErr,
              IslandKind.success => kOk,
              _ => kAccent,
            };
            return Padding(
              padding: EdgeInsets.only(top: top + 6),
              child: Align(
                alignment: Alignment.topCenter,
                child: Opacity(
                  opacity: (v * 2).clamp(0.0, 1.0),
                  child: Transform.translate(
                    offset: Offset(0, -56 * (1 - v)),
                    child: Transform.scale(
                      scale: 0.35 + 0.65 * v,
                      alignment: Alignment.topCenter,
                      child: Container(
                        key: ValueKey(_shownSeq),
                        width: w,
                        height: h,
                        decoration: BoxDecoration(
                          color: const Color(0xFF121214),
                          borderRadius: BorderRadius.circular(h / 2 < 26 ? h / 2 : 26),
                          border: Border.all(
                            color: Color.lerp(kBorder, accent.withValues(alpha: .55), reveal * (err ? 1 : .35))!,
                          ),
                          boxShadow: [
                            BoxShadow(color: Colors.black.withValues(alpha: .6), blurRadius: 18, offset: const Offset(0, 6)),
                            BoxShadow(color: accent.withValues(alpha: .05 + .08 * (1 - reveal)), blurRadius: 16),
                          ],
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: OverflowBox(
                          alignment: Alignment.centerLeft,
                          minWidth: _targetW,
                          maxWidth: _targetW,
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(5, 0, 0, 0),
                            child: Row(
                              children: [
                                // mascote: elemento compartilhado (cresce com overshoot)
                                Transform.scale(
                                  scale: (0.6 + 0.4 * v).clamp(0.0, 1.3),
                                  child: Mascot(
                                    controller: _mc,
                                    size: 34,
                                    interactive: false,
                                    alwaysOn: true,
                                    connected: !err,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                if (_icon != null) _stagger(c, 0, Icon(_icon, size: 16, color: accent)),
                                if (_icon != null) const SizedBox(width: 6),
                                SizedBox(
                                  width: _textW,
                                  child: _words.isEmpty ? const SizedBox() : _wordsWrap(c, err),
                                ),
                              ],
                            ),
                          ),
                        ),
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

  /// Anima um item: fade + deslize + desfoque, com atraso de 35 ms por posição.
  Widget _stagger(double c, int index, Widget child, {double delayMs = 35}) {
    const total = 700.0;
    final t = ((c * total - index * delayMs) / 240).clamp(0.0, 1.0);
    final e = Curves.easeOutCubic.transform(t);
    Widget w = Opacity(
      opacity: e,
      child: Transform.translate(offset: Offset(0, 6 * (1 - e)), child: child),
    );
    if (t < .98) {
      final sigma = 4 * (1 - e);
      w = ImageFiltered(
        imageFilter: ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma, tileMode: TileMode.decal),
        child: w,
      );
    }
    return w;
  }

  Widget _wordsWrap(double c, bool err) {
    final n = _words.length;
    // limita o escalonamento total a ~350 ms
    final delay = n <= 1 ? 35.0 : (350.0 / n).clamp(12.0, 35.0);
    final color = err ? const Color(0xFFFFB4B4) : Colors.white;
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (var i = 0; i < n; i++)
          _stagger(
            c,
            i + 1,
            Text(i < n - 1 ? '${_words[i]} ' : _words[i], style: _textStyle.copyWith(color: color)),
            delayMs: delay,
          ),
      ],
    );
  }
}
