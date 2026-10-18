import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';

import '../theme.dart';
import 'mascot.dart';
import 'screensaver.dart';

/// "Palco" do Tapi na Home: um Tapi grande que vive, passeia, olha para onde você toca,
/// reage a cada atalho e tem comportamentos ociosos (olhar em volta, bocejar, espreguiçar,
/// acenar, piscadinha, pulinho, corações/estrelas). Fica sonolento antes do protetor de tela.
class TapiStage extends StatefulWidget {
  final bool connected;
  final int screensaverSeconds;
  final double height;
  const TapiStage({super.key, required this.connected, required this.screensaverSeconds, this.height = 112});

  static final List<void Function(Offset)> _tapListeners = [];
  static final List<VoidCallback> _scrollListeners = [];

  /// O usuário tocou num cartão em [globalPos]: o Tapi vai até lá, olha e pula.
  static void reactToTap(Offset globalPos) {
    for (final l in List.of(_tapListeners)) {
      l(globalPos);
    }
  }

  /// A lista rolou: o Tapi fica curioso.
  static void reactToScroll() {
    for (final l in List.of(_scrollListeners)) {
      l();
    }
  }

  @override
  State<TapiStage> createState() => _TapiStageState();
}

class _TapiStageState extends State<TapiStage> with SingleTickerProviderStateMixin {
  final MascotController _ctl = MascotController();
  late final AnimationController _pos = AnimationController.unbounded(vsync: this, value: -1);
  final math.Random _rng = math.Random();
  Timer? _clock;
  double _width = 0;
  DateTime _nextIdle = DateTime.now().add(const Duration(seconds: 5));
  DateTime _lastScroll = DateTime.fromMillisecondsSinceEpoch(0);
  final List<DateTime> _tapTimes = [];
  bool _sleepy = false;
  static const double _size = 92;
  static final _spring = SpringDescription.withDampingRatio(mass: 1, stiffness: 90, ratio: .62);

  @override
  void initState() {
    super.initState();
    mascotController.link(_ctl);
    TapiStage._tapListeners.add(_onTileTap);
    TapiStage._scrollListeners.add(_onScroll);
    _clock = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    Future.delayed(const Duration(milliseconds: 700), () {
      if (mounted) _ctl.pop(); // "coucou" ao abrir o app
    });
  }

  @override
  void dispose() {
    mascotController.unlink(_ctl);
    TapiStage._tapListeners.remove(_onTileTap);
    TapiStage._scrollListeners.remove(_onScroll);
    _clock?.cancel();
    _pos.dispose();
    super.dispose();
  }

  double _clampX(double x) => x.clamp(_size * .6, math.max(_size * .6, _width - _size * .6)).toDouble();

  void _goto(double x) {
    if (_width <= 0) return;
    _pos.animateWith(SpringSimulation(_spring, _pos.value, _clampX(x), _pos.velocity));
  }

  void _onTileTap(Offset global) {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached) return;
    final local = box.globalToLocal(global);
    _nextIdle = DateTime.now().add(const Duration(seconds: 6));
    final now = DateTime.now();
    _tapTimes.removeWhere((t) => now.difference(t).inMilliseconds > 1500);
    _tapTimes.add(now);
    if (_tapTimes.length >= 5) {
      _tapTimes.clear();
      _ctl.emote(TapiEmote.dizzy, seconds: 2.6);
      HapticFeedback.heavyImpact();
      return;
    }
    _goto(local.dx);
    Future.delayed(const Duration(milliseconds: 380), () {
      if (mounted) _ctl.hop();
    });
  }

  void _onScroll() {
    final now = DateTime.now();
    if (now.difference(_lastScroll).inMilliseconds < 2600) return;
    _lastScroll = now;
    if (!_sleepy) _ctl.curious();
  }

  void _tick() {
    if (!mounted) return;
    final idle = DateTime.now().difference(lastAppActivity);
    final sleepyAfter = widget.screensaverSeconds > 0
        ? Duration(seconds: (widget.screensaverSeconds * .6).round().clamp(12, 180))
        : const Duration(seconds: 90);
    if (idle > sleepyAfter && !_sleepy) {
      _sleepy = true;
      _ctl.sleepy(true);
      return;
    }
    if (_sleepy && idle < const Duration(seconds: 2)) {
      _sleepy = false;
      _ctl.sleepy(false);
      _ctl.stretch();
      _nextIdle = DateTime.now().add(const Duration(seconds: 4));
      return;
    }
    if (_sleepy) return;
    if (idle.inMilliseconds < 2500 || DateTime.now().isBefore(_nextIdle)) return;
    _nextIdle = DateTime.now().add(Duration(milliseconds: 3500 + _rng.nextInt(4500)));
    _idleAction();
  }

  void _idleAction() {
    final r = _rng.nextInt(100);
    if (r < 22) {
      _ctl.lookAround();
    } else if (r < 36) {
      _ctl.hop();
    } else if (r < 48) {
      _ctl.wink();
    } else if (r < 56) {
      _ctl.yawn();
    } else if (r < 64) {
      _ctl.stretch();
    } else if (r < 72) {
      _ctl.pop(); // coucou
    } else if (r < 90) {
      _goto(_size * .6 + _rng.nextDouble() * math.max(1, _width - _size * 1.2));
      Future.delayed(const Duration(milliseconds: 900), () {
        if (mounted) _ctl.lookAround();
      });
    } else if (r < 94) {
      _ctl.love();
    } else if (r < 97) {
      _ctl.emote(TapiEmote.starEyes, seconds: 1.8);
    } else {
      _ctl.curious();
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.height,
      child: LayoutBuilder(builder: (context, c) {
        _width = c.maxWidth;
        if (_pos.value < 0) _pos.value = _width / 2;
        return AnimatedBuilder(
          animation: _pos,
          builder: (context, _) {
            final x = _clampX(_pos.value);
            final lean = (_pos.velocity / 1500).clamp(-.22, .22);
            return Stack(children: [
              // "chão": linha suave sob o Tapi
              Positioned(
                left: 28,
                right: 28,
                bottom: 10,
                child: Container(
                  height: 1,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [Colors.transparent, kBorder.withValues(alpha: .8), Colors.transparent]),
                  ),
                ),
              ),
              Positioned(
                left: x - _size / 2,
                bottom: 6,
                child: Transform.rotate(
                  angle: lean,
                  alignment: Alignment.bottomCenter,
                  child: Mascot(controller: _ctl, connected: widget.connected, size: _size),
                ),
              ),
            ]);
          },
        );
      }),
    );
  }
}
