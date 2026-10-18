import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../theme.dart';

// =============================================================================
// Tapi: mascote original do TAPKEY (corpo de "tecla", antena com ponta
// luminosa). Desenhado só com CustomPainter. Motor de estados com suavização
// exponencial, keyframes (squash & stretch), molas e partículas.
// =============================================================================

enum TapiEmote {
  idle,
  love,
  surprised,
  proud,
  yawn,
  happy,
  wink,
  heartEyes,
  starEyes,
  dizzy,
  annoyed,
  worried,
  working,
  error,
  finished,
  sleeping,
}

enum _CmdType { emote, squish, jump, spin, shake, wake, pop, tap, working, sleeping }

class _Cmd {
  final _CmdType type;
  final TapiEmote? emote;
  final double seconds;
  final bool flag;
  const _Cmd(this.type, {this.emote, this.seconds = 1, this.flag = true});
}

/// Controla um ou mais mascotes. Existe uma instância global ([mascotController]).
class MascotController {
  Offset? pointer;
  final List<void Function(_Cmd)> _cmdListeners = [];
  final List<VoidCallback> _wakers = [];

  void setPointer(Offset p) {
    pointer = p;
    for (final w in List.of(_wakers)) {
      w();
    }
  }

  void _send(_Cmd c) {
    for (final l in List.of(_cmdListeners)) {
      l(c);
    }
  }

  // ----- eventos de alto nível -----
  /// Atalho aberto com sucesso: carinha feliz, pulinho e giro.
  void happy() => _send(const _Cmd(_CmdType.jump, emote: TapiEmote.happy, seconds: 1.1));

  /// Carinho (toque longo).
  void love() => _send(const _Cmd(_CmdType.emote, emote: TapiEmote.love, seconds: 2.6));
  void squish() => _send(const _Cmd(_CmdType.squish));
  void error() => _send(const _Cmd(_CmdType.shake, emote: TapiEmote.error, seconds: 1.6));
  void finished() => _send(const _Cmd(_CmdType.spin, emote: TapiEmote.finished, seconds: 2.0));
  void surprised() => _send(const _Cmd(_CmdType.emote, emote: TapiEmote.surprised, seconds: 1.2));
  void proud() => _send(const _Cmd(_CmdType.emote, emote: TapiEmote.proud, seconds: 2.0));
  void yawn() => _send(const _Cmd(_CmdType.emote, emote: TapiEmote.yawn, seconds: 2.4));
  void wink() => _send(const _Cmd(_CmdType.emote, emote: TapiEmote.wink, seconds: 1.0));
  void emote(TapiEmote e, {double seconds = 1.5}) =>
      _send(_Cmd(_CmdType.emote, emote: e, seconds: seconds));
  void working(bool on) => _send(_Cmd(_CmdType.working, flag: on));
  void sleeping(bool on) => _send(_Cmd(_CmdType.sleeping, flag: on));

  /// Acorda esticando e acenando.
  void wake() => _send(const _Cmd(_CmdType.wake));
  void pop() => _send(const _Cmd(_CmdType.pop));
}

final MascotController mascotController = MascotController();

// -----------------------------------------------------------------------------
// Utilidades
// -----------------------------------------------------------------------------

/// Valor suavizado: `v` persegue `target` com decaimento exponencial.
class _Sm {
  double v;
  double target;
  final double rate;
  _Sm(this.v, this.rate) : target = v;
  void step(double dt) => v += (target - v) * (1 - math.exp(-rate * dt));
  void snap() => v = target;
}

class _K {
  final double t;
  final double v;
  final Curve curve;
  const _K(this.t, this.v, [this.curve = Curves.linear]);
}

enum _Prop { sx, sy, dx, dy, rot }

class _Trk {
  final _Prop prop;
  final List<_K> keys;
  const _Trk(this.prop, this.keys);

  double sample(double t) {
    if (t <= keys.first.t) return keys.first.v;
    for (var i = 1; i < keys.length; i++) {
      if (t <= keys[i].t) {
        final a = keys[i - 1], b = keys[i];
        final l = ((t - a.t) / (b.t - a.t)).clamp(0.0, 1.0);
        return a.v + (b.v - a.v) * b.curve.transform(l);
      }
    }
    return keys.last.v;
  }
}

class _Fx {
  final double start;
  final double dur;
  final List<_Trk> trks;
  _Fx(this.start, this.dur, this.trks);
}

const _twoPi = math.pi * 2;

_Fx _fxSquish(double t0) => _Fx(t0, 0.5, const [
      _Trk(_Prop.sx, [_K(0, 1), _K(.07, 1.28, Curves.easeOutCubic), _K(.2, .9, Curves.easeInOutCubic), _K(.5, 1, Curves.easeOutBack)]),
      _Trk(_Prop.sy, [_K(0, 1), _K(.07, .7, Curves.easeOutCubic), _K(.2, 1.1, Curves.easeInOutCubic), _K(.5, 1, Curves.easeOutBack)]),
    ]);

_Fx _fxJump(double t0, {bool spin = false}) => _Fx(t0, 0.95, [
      const _Trk(_Prop.sy, [
        _K(0, 1), _K(.14, .78, Curves.easeOutCubic), _K(.24, 1.2, Curves.easeOutBack),
        _K(.5, 1.04, Curves.easeInOutCubic), _K(.62, 1.1, Curves.easeInOutCubic),
        _K(.72, .8, Curves.easeInCubic), _K(.84, 1.06, Curves.easeOutBack), _K(.95, 1, Curves.easeOutCubic),
      ]),
      const _Trk(_Prop.sx, [
        _K(0, 1), _K(.14, 1.2, Curves.easeOutCubic), _K(.24, .88, Curves.easeOutBack),
        _K(.5, .98, Curves.easeInOutCubic), _K(.62, .92, Curves.easeInOutCubic),
        _K(.72, 1.22, Curves.easeInCubic), _K(.84, .97, Curves.easeOutBack), _K(.95, 1, Curves.easeOutCubic),
      ]),
      const _Trk(_Prop.dy, [_K(0, 0), _K(.14, 0), _K(.5, -.26, Curves.easeOutCubic), _K(.72, 0, Curves.easeInCubic), _K(.95, 0)]),
      if (spin) const _Trk(_Prop.rot, [_K(0, 0), _K(.2, 0), _K(.68, _twoPi, Curves.easeInOutCubic), _K(.95, _twoPi)]),
    ]);

_Fx _fxSpin(double t0) => _Fx(t0, 1.1, const [
      _Trk(_Prop.rot, [_K(0, 0), _K(1.0, _twoPi, Curves.easeInOutBack)]),
      _Trk(_Prop.dy, [_K(0, 0), _K(.5, -.14, Curves.easeOutCubic), _K(1.0, 0, Curves.easeInCubic)]),
    ]);

_Fx _fxWake(double t0) => _Fx(t0, 1.1, const [
      _Trk(_Prop.sy, [_K(0, 1), _K(.35, 1.22, Curves.easeOutCubic), _K(.7, 1.18), _K(1.1, 1, Curves.easeOutBack)]),
      _Trk(_Prop.sx, [_K(0, 1), _K(.35, .88, Curves.easeOutCubic), _K(.7, .9), _K(1.1, 1, Curves.easeOutBack)]),
      _Trk(_Prop.rot, [_K(0, 0), _K(.4, 0), _K(.5, .12, Curves.easeInOutCubic), _K(.6, -.12, Curves.easeInOutCubic), _K(.7, .1, Curves.easeInOutCubic), _K(.8, -.08, Curves.easeInOutCubic), _K(1.0, 0, Curves.easeOutCubic)]),
    ]);

_Fx _fxPop(double t0) => _Fx(t0, 0.9, const [
      _Trk(_Prop.dy, [_K(0, .75), _K(.45, -.07, Curves.easeOutCubic), _K(.9, 0, Curves.easeOutBack)]),
      _Trk(_Prop.sx, [_K(0, .7), _K(.45, 1.08, Curves.easeOutCubic), _K(.9, 1, Curves.easeOutBack)]),
      _Trk(_Prop.sy, [_K(0, 1.25), _K(.45, .95, Curves.easeOutCubic), _K(.9, 1, Curves.easeOutBack)]),
    ]);

_Fx _fxShake(double t0) => _Fx(t0, 0.6, const [
      _Trk(_Prop.dx, [
        _K(0, 0), _K(.06, .04, Curves.easeInOutCubic), _K(.12, -.04, Curves.easeInOutCubic),
        _K(.2, .035, Curves.easeInOutCubic), _K(.28, -.03, Curves.easeInOutCubic),
        _K(.38, .02, Curves.easeInOutCubic), _K(.5, -.01, Curves.easeInOutCubic), _K(.6, 0),
      ]),
    ]);

enum _PType { heart, star, z, spark }

class _P {
  _PType type;
  double x, y, vx, vy, age = 0, life, size, rot, vr;
  _P(this.type, this.x, this.y, this.vx, this.vy, this.life, this.size, this.rot, this.vr);
}

const _rose = Color(0xFFFF9BB0);
const _warm = Color(0xFFFFF0C4);
const _silver = Color(0xFFEDEDEF);

// -----------------------------------------------------------------------------
// Motor
// -----------------------------------------------------------------------------

class TapiEngine {
  final math.Random _rng = math.Random(7);
  double t = 0;

  // parâmetros suavizados
  final lookX = _Sm(0, 14), lookY = _Sm(0, 14);
  final eyeOpen = _Sm(1, 24), eyeScale = _Sm(1, 14);
  final arc = _Sm(0, 16), winkR = _Sm(0, 26);
  final heartEyes = _Sm(0, 14), starEyes = _Sm(0, 14), spiral = _Sm(0, 12);
  final brow = _Sm(0, 12), smile = _Sm(0.35, 12), mouthOpen = _Sm(0, 14);
  final blush = _Sm(0, 6), glow = _Sm(0.35, 5), lift = _Sm(0, 10);

  // entradas
  Offset lookTarget = Offset.zero;
  bool connected = true;
  bool sleeping = false;
  bool working = false;
  bool alwaysOn = false;

  // estado
  TapiEmote _timed = TapiEmote.idle;
  double _timedUntil = 0;
  TapiEmote? _applied;
  final List<_Fx> _fx = [];
  final List<_P> _parts = [];
  double _nextBlink = 2.4;
  double _blinkStart = -1;
  double _secondBlinkAt = -1;
  double _idleSince = 0;
  bool _yawned = false;
  double _waveUntil = 0;
  double _partTimer = 0;
  final List<double> _taps = [];

  // valores compostos do frame
  double _sx = 1, _sy = 1, _dx = 0, _dy = 0, _rot = 0;

  // antena (mola macia: rigidez 60, amortecimento 9)
  double _tipX = 0, _tipY = 0, _tipVx = 0, _tipVy = 0;
  double _prevAx = 0, _prevAy = 0, _prevVx = 0, _prevVy = 0;

  bool rest = false;

  void touch() {
    _idleSince = t;
    _yawned = false;
    rest = false;
  }

  TapiEmote get effective {
    if (t < _timedUntil) return _timed;
    if (sleeping) return TapiEmote.sleeping;
    if (working) return TapiEmote.working;
    if (!connected) return TapiEmote.worried;
    return TapiEmote.idle;
  }

  void _handle(_Cmd c) {
    touch();
    switch (c.type) {
      case _CmdType.emote:
        _setTimed(c.emote!, c.seconds);
      case _CmdType.squish:
        _fx.add(_fxSquish(t));
      case _CmdType.jump:
        _fx.add(_fxJump(t, spin: true));
        _setTimed(c.emote!, c.seconds);
        _burst(_PType.spark, 4);
      case _CmdType.spin:
        _fx.add(_fxSpin(t));
        _setTimed(c.emote!, c.seconds);
        _burst(_PType.star, 6);
        _burst(_PType.spark, 4);
      case _CmdType.shake:
        _fx.add(_fxShake(t));
        _setTimed(c.emote!, c.seconds);
      case _CmdType.wake:
        sleeping = false;
        _fx.add(_fxWake(t));
        _waveUntil = t + 1.6;
        _setTimed(TapiEmote.happy, 1.4);
      case _CmdType.pop:
        _fx.add(_fxPop(t));
        _waveUntil = t + 2.4;
        _setTimed(TapiEmote.happy, 1.2);
      case _CmdType.tap:
        break;
      case _CmdType.working:
        working = c.flag;
      case _CmdType.sleeping:
        sleeping = c.flag;
    }
  }

  /// Toque simples: amassa. Três toques rápidos: tontura.
  void tap() {
    touch();
    _taps.add(t);
    _taps.removeWhere((x) => t - x > 1.5);
    _fx.add(_fxSquish(t));
    if (_taps.length >= 3) {
      _taps.clear();
      _setTimed(TapiEmote.dizzy, 3.4);
    } else if (t >= _timedUntil || _timed != TapiEmote.dizzy) {
      _setTimed(TapiEmote.annoyed, 1.0);
    }
  }

  void _setTimed(TapiEmote e, double seconds) {
    _timed = e;
    _timedUntil = t + seconds;
  }

  void _burst(_PType type, int n) {
    for (var i = 0; i < n; i++) {
      final a = -math.pi / 2 + (_rng.nextDouble() - .5) * 2.4;
      final sp = .25 + _rng.nextDouble() * .3;
      _parts.add(_P(type, (_rng.nextDouble() - .5) * .3, -.35, math.cos(a) * sp, math.sin(a) * sp,
          .9 + _rng.nextDouble() * .5, .04 + _rng.nextDouble() * .03, 0, (_rng.nextDouble() - .5) * 3));
    }
    if (_parts.length > 22) _parts.removeRange(0, _parts.length - 22);
  }

  void _applyTargets(TapiEmote e) {
    // padrão (idle)
    var eo = 1.0, es = 1.0, ar = 0.0, wk = 0.0, he = 0.0, se = 0.0, sp = 0.0;
    var br = 0.0, sm = 0.35, mo = 0.0, bl = 0.0, gl = 0.35, lf = 0.0;
    switch (e) {
      case TapiEmote.idle:
        break;
      case TapiEmote.love:
        he = 1; bl = 1; sm = 1; gl = .9;
      case TapiEmote.surprised:
        es = 1.2; eo = 1.1; sm = 0; mo = .55; gl = .9; lf = .6;
      case TapiEmote.proud:
        ar = 1; sm = 1; gl = 1; lf = 1; bl = .3;
      case TapiEmote.yawn:
        eo = .12; sm = 0; mo = 1; gl = .15;
      case TapiEmote.happy:
        ar = 1; sm = 1; gl = .85; bl = .25;
      case TapiEmote.wink:
        wk = 1; sm = .85; gl = .7;
      case TapiEmote.heartEyes:
        he = 1; sm = .9; bl = .6; gl = .9;
      case TapiEmote.starEyes:
        se = 1; sm = 1; gl = 1;
      case TapiEmote.dizzy:
        sp = 1; sm = -.2; gl = .2;
      case TapiEmote.annoyed:
        eo = .55; br = 1; sm = -.35; gl = .15;
      case TapiEmote.worried:
        br = -1; sm = -.8; eo = .92; es = 1.05; gl = .08;
      case TapiEmote.working:
        eo = .92; sm = 0; gl = .9;
      case TapiEmote.error:
        br = -1; sm = -1; eo = .8; gl = .05;
      case TapiEmote.finished:
        se = 1; sm = 1; gl = 1; lf = .7;
      case TapiEmote.sleeping:
        eo = 1; ar = -1; sm = .15; gl = .08;
    }
    eyeOpen.target = eo; eyeScale.target = es; arc.target = ar; winkR.target = wk;
    heartEyes.target = he; starEyes.target = se; spiral.target = sp;
    brow.target = br; smile.target = sm; mouthOpen.target = mo;
    blush.target = bl; glow.target = gl; lift.target = lf;
  }

  /// Vai direto para a pose de [e] (usado para gerar ícones estáticos).
  void snapTo(TapiEmote e) {
    _applyTargets(e);
    _applied = e;
    for (final s in [lookX, lookY, eyeOpen, eyeScale, arc, winkR, heartEyes, starEyes, spiral, brow, smile, mouthOpen, blush, glow, lift]) {
      s.snap();
    }
  }

  void step(double dt) {
    t += dt;
    final e = effective;
    if (e != _applied) {
      _applyTargets(e);
      _applied = e;
    }

    // olhar: acompanha o toque (esferas), varre os lados ao "trabalhar"
    var lx = lookTarget.dx, ly = lookTarget.dy;
    if (e == TapiEmote.working) {
      lx = math.sin(t * 3.2) * .8;
      ly = 0;
      glow.target = .65 + .35 * math.sin(t * 9);
    }
    if (e == TapiEmote.sleeping || e == TapiEmote.dizzy || e == TapiEmote.yawn) {
      lx = 0;
      ly = 0;
    }
    if (e == TapiEmote.worried || e == TapiEmote.error) ly = ly * .5 + .35;
    lookX.target = lx.clamp(-1.0, 1.0);
    lookY.target = ly.clamp(-1.0, 1.0);

    // piscadas aleatórias (2,2-5,4 s), às vezes duplas
    if (e != TapiEmote.sleeping && _blinkStart < 0 && t >= _nextBlink) {
      _blinkStart = t;
      if (_rng.nextDouble() < .25) _secondBlinkAt = t + .24;
    }
    if (_secondBlinkAt > 0 && t >= _secondBlinkAt && t - _blinkStart > .16) {
      _blinkStart = t;
      _secondBlinkAt = -1;
    }
    var blinkK = 0.0;
    if (_blinkStart >= 0) {
      final l = (t - _blinkStart) / .15;
      if (l >= 1) {
        _blinkStart = -1;
        if (_secondBlinkAt < 0) _nextBlink = t + 2.2 + _rng.nextDouble() * 3.2;
      } else {
        blinkK = math.sin(l * math.pi);
      }
    }
    _blink = blinkK;

    for (final s in [lookX, lookY, eyeOpen, eyeScale, arc, winkR, heartEyes, starEyes, spiral, brow, smile, mouthOpen, blush, glow, lift]) {
      s.step(dt);
    }

    // keyframes
    var sx = 1.0, sy = 1.0, dx = 0.0, dy = 0.0, rot = 0.0;
    _fx.removeWhere((f) => t - f.start > f.dur + .05);
    for (final f in _fx) {
      final lt = t - f.start;
      for (final tr in f.trks) {
        final v = tr.sample(lt);
        switch (tr.prop) {
          case _Prop.sx: sx *= v;
          case _Prop.sy: sy *= v;
          case _Prop.dx: dx += v;
          case _Prop.dy: dy += v;
          case _Prop.rot: rot += v;
        }
      }
    }
    // respiração
    final br = math.sin(t * (e == TapiEmote.sleeping ? 1.1 : 2.1)) * (e == TapiEmote.sleeping ? .035 : .02);
    sy *= 1 + br;
    sx *= 1 - br * .6;
    // tontura: balanço + rolagem
    if (e == TapiEmote.dizzy) {
      rot += math.sin(t * 9) * .14;
      dx += math.sin(t * 5) * .012;
    }
    _sx = sx; _sy = sy; _dx = dx; _dy = dy; _rot = rot;

    // antena: mola que reage à aceleração do corpo
    final ax = dx + math.sin(rot) * .4;
    final ay = dy;
    if (dt > 0) {
      final vx = (ax - _prevAx) / dt, vy = (ay - _prevAy) / dt;
      final accX = ((vx - _prevVx) / dt).clamp(-60.0, 60.0);
      final accY = ((vy - _prevVy) / dt).clamp(-60.0, 60.0);
      _prevAx = ax; _prevAy = ay; _prevVx = vx; _prevVy = vy;
      const k = 60.0, d = 9.0;
      final n = (dt / .008).ceil().clamp(1, 6);
      final h = dt / n;
      for (var i = 0; i < n; i++) {
        _tipVx += (-k * _tipX - d * _tipVx - accX * 3) * h;
        _tipVy += (-k * _tipY - d * _tipVy + accY * 2) * h;
        _tipX += _tipVx * h;
        _tipY += _tipVy * h;
      }
      _tipX = _tipX.clamp(-.2, .2);
      _tipY = _tipY.clamp(-.1, .1);
    }

    // partículas
    _partTimer -= dt;
    if (_partTimer <= 0) {
      if (e == TapiEmote.love || e == TapiEmote.heartEyes) {
        _spawn(_PType.heart);
        _partTimer = .22;
      } else if (e == TapiEmote.proud) {
        _spawn(_PType.star);
        _partTimer = .25;
      } else if (e == TapiEmote.finished) {
        _spawn(_PType.spark);
        _partTimer = .12;
      } else if (e == TapiEmote.yawn || e == TapiEmote.sleeping) {
        _spawn(_PType.z);
        _partTimer = e == TapiEmote.sleeping ? 1.3 : .7;
      } else {
        _partTimer = .2;
      }
    }
    for (final p in _parts) {
      p.age += dt;
      p.x += p.vx * dt;
      p.y += p.vy * dt;
      p.rot += p.vr * dt;
      if (p.type == _PType.z || p.type == _PType.heart) p.vy -= .02 * dt;
    }
    _parts.removeWhere((p) => p.age >= p.life);

    // ociosidade: boceja e depois "descansa" (ticker pausa para poupar bateria)
    final idleFor = t - _idleSince;
    if (!alwaysOn && !sleeping && !working && e == TapiEmote.idle && !_yawned && idleFor > 20) {
      _yawned = true;
      _setTimed(TapiEmote.yawn, 2.4);
    }
    final busy = _fx.isNotEmpty || t < _timedUntil || _parts.isNotEmpty;
    rest = !alwaysOn && !sleeping && !working && !busy && idleFor > 45;
  }

  double _blink = 0;

  void _spawn(_PType type) {
    final x = (_rng.nextDouble() - .5) * .3;
    switch (type) {
      case _PType.z:
        _parts.add(_P(type, .22, -.62, .03, -.07, 2.2, .045, 0, 0));
      case _PType.heart:
        _parts.add(_P(type, x, -.55, (_rng.nextDouble() - .5) * .12, -.2, 1.4, .05 + _rng.nextDouble() * .02, 0, (_rng.nextDouble() - .5) * .8));
      default:
        _burst(type, 1);
    }
    if (_parts.length > 22) _parts.removeAt(0);
  }

  // ---------------------------------------------------------------------------
  // Desenho
  // ---------------------------------------------------------------------------

  static Path _roundedPoly(List<Offset> pts, List<double> radii) {
    final p = Path();
    final n = pts.length;
    for (var i = 0; i < n; i++) {
      final prev = pts[(i - 1 + n) % n], cur = pts[i], next = pts[(i + 1) % n];
      final v1 = prev - cur, v2 = next - cur;
      final l1 = v1.distance, l2 = v2.distance;
      final rr = math.min(radii[i], math.min(l1, l2) / 2);
      final a = cur + v1 / l1 * rr, b = cur + v2 / l2 * rr;
      i == 0 ? p.moveTo(a.dx, a.dy) : p.lineTo(a.dx, a.dy);
      p.quadraticBezierTo(cur.dx, cur.dy, b.dx, b.dy);
    }
    p.close();
    return p;
  }

  static Path _heart(double s) => Path()
    ..moveTo(0, s * .9)
    ..cubicTo(-s * 1.6, -s * .2, -s * .7, -s * 1.3, 0, -s * .4)
    ..cubicTo(s * .7, -s * 1.3, s * 1.6, -s * .2, 0, s * .9)
    ..close();

  static Path _star(double r, {int pts = 5, double inner = .45}) {
    final p = Path();
    for (var i = 0; i < pts * 2; i++) {
      final rad = i.isEven ? r : r * inner;
      final a = -math.pi / 2 + i * math.pi / pts;
      final x = math.cos(a) * rad, y = math.sin(a) * rad;
      i == 0 ? p.moveTo(x, y) : p.lineTo(x, y);
    }
    return p..close();
  }

  void paint(Canvas canvas, Size size) {
    final u = math.min(size.width, size.height);
    final fill = Paint();
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final bw = .80 * u, tw = .68 * u, h = .56 * u;

    canvas.save();
    canvas.translate(size.width / 2 + _dx * u, size.height * .9 + _dy * u - lift.v * .03 * u);
    canvas.rotate(_rot);
    canvas.scale(_sx, _sy);

    // sombra de contato
    fill
      ..shader = null
      ..color = Colors.black.withValues(alpha: .35)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, u * .03);
    canvas.drawOval(Rect.fromCenter(center: Offset(0, u * .015), width: bw * .95, height: u * .06), fill);
    fill.maskFilter = null;

    // halo suave de acento (corpo)
    if (glow.v > .5) {
      fill
        ..color = kAccent.withValues(alpha: (glow.v - .5) * .12)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, u * .12);
      canvas.drawOval(Rect.fromCenter(center: Offset(0, -h * .5), width: bw * 1.1, height: h * 1.1), fill);
      fill.maskFilter = null;
    }

    // braço acenando
    if (t < _waveUntil) {
      final a = -.9 + math.sin(t * 14) * .45;
      canvas.save();
      canvas.translate(bw * .46, -h * .28);
      canvas.rotate(a);
      line
        ..color = const Color(0xFF3C3C43)
        ..strokeWidth = u * .1;
      canvas.drawLine(Offset.zero, Offset(0, -u * .2), line);
      canvas.restore();
    }

    // antena
    final baseA = Offset(0, -h + u * .015);
    final tip = Offset(_tipX * u * 1.6, -h - u * .2 + _tipY * u * 1.2);
    final ctrl = Offset(_tipX * u * .4, (baseA.dy + tip.dy) / 2);
    line
      ..color = const Color(0xFF8D8D96)
      ..strokeWidth = u * .028;
    canvas.drawPath(Path()..moveTo(baseA.dx, baseA.dy)..quadraticBezierTo(ctrl.dx, ctrl.dy, tip.dx, tip.dy), line);
    final g = glow.v.clamp(0.0, 1.0);
    if (g > .05) {
      fill
        ..color = Colors.white.withValues(alpha: .38 * g)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, u * .05);
      canvas.drawCircle(tip, u * (.07 + .06 * g), fill);
      fill.maskFilter = null;
    }
    fill.color = Color.lerp(const Color(0xFF6D6D76), Colors.white, g)!;
    canvas.drawCircle(tip, u * .048, fill);

    // corpo (tecla): trapézio arredondado
    final body = _roundedPoly(
      [Offset(-bw / 2, 0), Offset(bw / 2, 0), Offset(tw / 2, -h), Offset(-tw / 2, -h)],
      [u * .13, u * .13, u * .2, u * .2],
    );
    final bodyRect = Rect.fromLTWH(-bw / 2, -h, bw, h);
    fill.color = Colors.white;
    fill.shader = const LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0xFF47474F), Color(0xFF26262B)],
    ).createShader(bodyRect);
    canvas.drawPath(body, fill);
    fill.shader = null;
    // face da tecla (leve relevo)
    final face = _roundedPoly(
      [Offset(-bw / 2 + u * .06, -u * .06), Offset(bw / 2 - u * .06, -u * .06), Offset(tw / 2 - u * .05, -h + u * .05), Offset(-tw / 2 + u * .05, -h + u * .05)],
      [u * .09, u * .09, u * .15, u * .15],
    );
    fill.color = Colors.white.withValues(alpha: .055);
    canvas.drawPath(face, fill);
    line
      ..color = Colors.white.withValues(alpha: .07)
      ..strokeWidth = u * .012;
    canvas.drawPath(face, line);
    line
      ..color = const Color(0xFF5E5E68)
      ..strokeWidth = math.max(1, u * .024);
    canvas.drawPath(body, line);

    // olhos
    final ey = -h * .56;
    final ex = u * .175;
    final er = u * .125 * eyeScale.v;
    for (final side in [1.0, -1.0]) {
      final open = (eyeOpen.v * (1 - _blink * .95) * (side > 0 ? (1 - winkR.v * .97) : 1)).clamp(0.0, 1.3);
      _eye(canvas, Offset(ex * side, ey), er, open, side, u, fill, line);
    }
    // sobrancelhas
    if (brow.v.abs() > .05) {
      final a = (brow.v.abs() * 1.5).clamp(0.0, 1.0);
      line
        ..color = const Color(0xFFB8B8C0).withValues(alpha: a)
        ..strokeWidth = u * .03;
      for (final side in [-1.0, 1.0]) {
        final c = Offset(ex * side, ey);
        final by = c.dy - er * 1.22;
        final inner = Offset(c.dx - side * er * .75, by + brow.v * er * .5);
        final outer = Offset(c.dx + side * er * .75, by - brow.v * er * .15);
        canvas.drawLine(inner, outer, line);
      }
    }
    // bochechas
    if (blush.v > .02) {
      fill.color = _rose.withValues(alpha: blush.v * .42);
      for (final side in [-1.0, 1.0]) {
        canvas.drawOval(Rect.fromCenter(center: Offset(ex * 1.38 * side, ey + er * 1.15), width: u * .1, height: u * .055), fill);
      }
    }
    _mouth(canvas, h, u, fill, line);
    canvas.restore();

    // partículas (fora da transformação do corpo)
    final ox = size.width / 2, oy = size.height * .9;
    for (final p in _parts) {
      final l = p.age / p.life;
      final a = (l < .15 ? l / .15 : (1 - l) / .85).clamp(0.0, 1.0);
      canvas.save();
      canvas.translate(ox + p.x * u, oy + p.y * u);
      canvas.rotate(p.rot);
      final s = p.size * u * (.7 + .5 * (1 - (1 - l) * (1 - l)));
      switch (p.type) {
        case _PType.heart:
          fill.color = _rose.withValues(alpha: a);
          canvas.drawPath(_heart(s), fill);
        case _PType.star:
          fill.color = _warm.withValues(alpha: a);
          canvas.drawPath(_star(s * 1.3), fill);
        case _PType.spark:
          fill.color = Colors.white.withValues(alpha: a);
          canvas.drawPath(_star(s * 1.4, pts: 4, inner: .25), fill);
        case _PType.z:
          line
            ..color = _silver.withValues(alpha: a * .9)
            ..strokeWidth = math.max(1, u * .02);
          final z = s * 1.2;
          canvas.drawPath(Path()..moveTo(-z, -z)..lineTo(z, -z)..lineTo(-z, z)..lineTo(z, z), line);
      }
      canvas.restore();
    }
  }

  void _eye(Canvas canvas, Offset c, double er, double open, double side, double u, Paint fill, Paint line) {
    final arcK = arc.v;
    final sphereA = (1 - arcK.abs()).clamp(0.0, 1.0);

    // pálpebras fechadas: linha fina
    if (sphereA > .05 && open < .18) {
      line
        ..color = _silver.withValues(alpha: sphereA * (1 - open / .18))
        ..strokeWidth = u * .035;
      canvas.drawLine(c + Offset(-er * .8, 0), c + Offset(er * .8, 0), line);
    }
    // arcos: ^ (feliz) e ‿ (dormindo)
    if (arcK.abs() > .02) {
      line
        ..color = _silver.withValues(alpha: arcK.abs().clamp(0.0, 1.0))
        ..strokeWidth = u * .04;
      final dir = arcK > 0 ? -1.0 : 1.0;
      canvas.drawPath(
        Path()
          ..moveTo(c.dx - er * .85, c.dy + er * .3 * -dir)
          ..quadraticBezierTo(c.dx, c.dy + dir * er * 1.05 - er * .3 * -dir * 0, c.dx + er * .85, c.dy + er * .3 * -dir),
        line,
      );
    }
    if (sphereA < .05 || open < .08) return;

    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.scale(1, open.clamp(0.0, 1.2));
    final a = sphereA;
    // esfera (esclera) com sombreamento
    fill.color = Colors.white;
    fill.shader = RadialGradient(
      center: const Alignment(-.35, -.4),
      radius: 1.05,
      colors: [Colors.white.withValues(alpha: a), const Color(0xFFEFEFF3).withValues(alpha: a), const Color(0xFFBDBDC6).withValues(alpha: a)],
      stops: const [0, .55, 1],
    ).createShader(Rect.fromCircle(center: Offset.zero, radius: er));
    canvas.drawCircle(Offset.zero, er, fill);
    fill.shader = null;

    final noPupil = (heartEyes.v + starEyes.v + spiral.v).clamp(0.0, 1.0);
    // pupila: segue o toque (yaw/pitch da esfera)
    final pr = er * .58;
    final yaw = lookX.v, pitch = lookY.v;
    final po = Offset(yaw * er * .38, pitch * er * .32);
    canvas.save();
    canvas.translate(po.dx, po.dy);
    canvas.scale(math.cos(yaw * .55).clamp(.6, 1.0), math.cos(pitch * .4).clamp(.7, 1.0));
    fill.color = const Color(0xFF111114).withValues(alpha: a * (1 - noPupil));
    canvas.drawCircle(Offset.zero, pr, fill);
    fill.color = Colors.white.withValues(alpha: a * (1 - noPupil));
    canvas.drawCircle(Offset(-pr * .3, -pr * .34), pr * .3, fill);
    fill.color = Colors.white.withValues(alpha: a * (1 - noPupil) * .5);
    canvas.drawCircle(Offset(pr * .3, pr * .32), pr * .13, fill);
    canvas.restore();

    if (heartEyes.v > .02) {
      fill.color = _rose.withValues(alpha: heartEyes.v * a);
      canvas.save();
      canvas.scale(1 + .08 * math.sin(t * 8));
      canvas.drawPath(_heart(er * .62), fill);
      canvas.restore();
    }
    if (starEyes.v > .02) {
      fill.color = const Color(0xFFFFD98A).withValues(alpha: starEyes.v * a);
      canvas.save();
      canvas.rotate(t * 1.5);
      canvas.drawPath(_star(er * .85), fill);
      canvas.restore();
    }
    if (spiral.v > .02) {
      final sp = Path();
      for (var i = 0; i <= 36; i++) {
        final an = i / 36 * 2.4 * _twoPi + t * 8 * side;
        final rad = er * .85 * (i / 36);
        final pt = Offset(math.cos(an) * rad, math.sin(an) * rad);
        i == 0 ? sp.moveTo(pt.dx, pt.dy) : sp.lineTo(pt.dx, pt.dy);
      }
      line
        ..color = const Color(0xFF111114).withValues(alpha: spiral.v * a)
        ..strokeWidth = math.max(1, u * .028);
      canvas.drawPath(sp, line);
    }
    canvas.restore();
  }

  void _mouth(Canvas canvas, double h, double u, Paint fill, Paint line) {
    final y = -h * .2;
    final w = u * .07;
    if (mouthOpen.v > .05) {
      final mo = mouthOpen.v;
      fill.color = const Color(0xFF111114);
      canvas.drawOval(Rect.fromCenter(center: Offset(0, y + u * .02 * mo), width: w * (1.1 + .5 * mo), height: u * (.035 + .1 * mo)), fill);
      return;
    }
    line
      ..color = _silver
      ..strokeWidth = u * .028;
    if (spiral.v > .5) {
      canvas.drawPath(
        Path()
          ..moveTo(-w, y)
          ..quadraticBezierTo(-w * .5, y - w * .5, 0, y)
          ..quadraticBezierTo(w * .5, y + w * .5, w, y),
        line,
      );
      return;
    }
    final s = smile.v;
    canvas.drawPath(Path()..moveTo(-w * (.7 + .3 * s.abs()), y)..quadraticBezierTo(0, y + s * u * .075, w * (.7 + .3 * s.abs()), y), line);
  }
}

// -----------------------------------------------------------------------------
// Widget
// -----------------------------------------------------------------------------

class Mascot extends StatefulWidget {
  final bool connected;
  final double size;
  final MascotController? controller;
  final bool sleeping;
  final bool alwaysOn;
  final bool interactive;
  const Mascot({
    super.key,
    this.connected = true,
    this.size = 34,
    this.controller,
    this.sleeping = false,
    this.alwaysOn = false,
    this.interactive = true,
  });

  @override
  State<Mascot> createState() => _MascotState();
}

class _MascotState extends State<Mascot> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final _repaint = ValueNotifier<int>(0);
  final TapiEngine engine = TapiEngine();
  Duration _last = Duration.zero;
  late final MascotController _ctl = widget.controller ?? mascotController;

  @override
  void initState() {
    super.initState();
    engine
      ..connected = widget.connected
      ..sleeping = widget.sleeping
      ..alwaysOn = widget.alwaysOn;
    _ctl._cmdListeners.add(_onCmd);
    _ctl._wakers.add(_wake);
    _ticker = createTicker(_tick)..start();
    if (!widget.sleeping) engine._handle(const _Cmd(_CmdType.pop));
  }

  @override
  void didUpdateWidget(covariant Mascot old) {
    super.didUpdateWidget(old);
    if (old.connected != widget.connected) {
      engine.connected = widget.connected;
      if (!widget.connected) {
        engine._handle(const _Cmd(_CmdType.shake, emote: TapiEmote.worried, seconds: .9));
      }
      _wake();
    }
    engine.alwaysOn = widget.alwaysOn;
    if (old.sleeping != widget.sleeping) {
      engine.sleeping = widget.sleeping;
      _wake();
    }
  }

  @override
  void dispose() {
    _ctl._cmdListeners.remove(_onCmd);
    _ctl._wakers.remove(_wake);
    _ticker.dispose();
    _repaint.dispose();
    super.dispose();
  }

  void _onCmd(_Cmd c) {
    engine._handle(c);
    _wake(touch: false);
  }

  void _wake({bool touch = true}) {
    if (touch) engine.touch();
    if (!_ticker.isActive) {
      _last = Duration.zero;
      _ticker.start();
    }
  }

  void _tick(Duration elapsed) {
    final dt = ((elapsed - _last).inMicroseconds / 1e6).clamp(0.0, 0.05);
    _last = elapsed;
    // olhar na direção do último toque
    final p = _ctl.pointer;
    final ro = context.findRenderObject();
    var look = Offset.zero;
    if (p != null && ro is RenderBox && ro.attached) {
      final c = ro.localToGlobal(ro.size.center(Offset.zero));
      final dv = p - c;
      final d = dv.distance;
      if (d > 1) look = dv / d * math.min(1.0, d / 140);
    }
    engine.lookTarget = look;
    engine.step(dt);
    _repaint.value++;
    if (engine.rest) _ticker.stop();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    final paint = SizedBox(
      width: s,
      height: s,
      child: RepaintBoundary(
        child: CustomPaint(painter: _TapiPainter(engine, _repaint)),
      ),
    );
    if (!widget.interactive) return paint;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        engine.tap();
        _wake(touch: false);
      },
      onLongPress: () {
        engine._handle(const _Cmd(_CmdType.emote, emote: TapiEmote.love, seconds: 2.6));
        _wake(touch: false);
      },
      child: paint,
    );
  }
}

class _TapiPainter extends CustomPainter {
  final TapiEngine e;
  _TapiPainter(this.e, Listenable repaint) : super(repaint: repaint);

  @override
  void paint(Canvas canvas, Size size) => e.paint(canvas, size);

  @override
  bool shouldRepaint(covariant _TapiPainter old) => true;
}

/// Pintor estático (ícone do app, README): desenha o Tapi numa pose fixa.
class TapiStaticPainter extends CustomPainter {
  final TapiEngine engine = TapiEngine();
  TapiStaticPainter(TapiEmote pose, {double glow = .9}) {
    engine.snapTo(pose);
    engine.glow
      ..target = glow
      ..snap();
    engine.lookX
      ..target = .15
      ..snap();
    engine.lookY
      ..target = -.05
      ..snap();
  }

  @override
  void paint(Canvas canvas, Size size) => engine.paint(canvas, size);

  @override
  bool shouldRepaint(covariant TapiStaticPainter old) => false;
}
