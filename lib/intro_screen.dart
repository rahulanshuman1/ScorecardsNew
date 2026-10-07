import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// Pre-match presentation: team + captain intro, league title, toss and toss result.

const _gold = Color(0xFFFFC107);

class TeamCard {
  final String team, captain;
  final String? photo;
  final Color color;
  const TeamCard(this.team, this.captain, this.photo, this.color);
}

class TossResult {
  final int winner; // 0 = first team, 1 = second team
  final bool bat; // true = elected to bat, false = elected to field
  const TossResult(this.winner, this.bat);
}

enum IntroKind { team, versus, league, tossResult, winner }

Route<T> _route<T>(Widget page) => PageRouteBuilder<T>(
      opaque: true,
      transitionDuration: const Duration(milliseconds: 260),
      reverseTransitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (_, __, ___) => page,
      transitionsBuilder: (_, anim, __, child) => FadeTransition(opacity: anim, child: child),
    );

/// Full-screen animated presentation that closes by itself (tap or Esc closes early).
Future<void> showIntro(
  BuildContext context, {
  required IntroKind kind,
  TeamCard? a,
  TeamCard? b,
  String? league,
  String? subtitle,
  String? line,
  String? decision,
  bool bat = true,
}) =>
    Navigator.of(context).push(_route<void>(IntroScreen(
      kind: kind,
      a: a,
      b: b,
      league: league,
      subtitle: subtitle,
      line: line,
      decision: decision,
      bat: bat,
    )));

/// Interactive toss: teams -> start -> coin flip -> result -> winner -> bat/field -> confirm.
Future<TossResult?> showToss(BuildContext context,
        {required TeamCard a, required TeamCard b, String? league}) =>
    Navigator.of(context).push(_route<TossResult>(TossScreen(a: a, b: b, league: league)));

// ------------------------------------------------------------------ helpers

/// Scales its child down (never up) so everything is visible at once - no scrolling.
class _Fit extends StatelessWidget {
  final Widget child;
  const _Fit({required this.child});
  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, c) {
        final w = c.maxWidth.isFinite ? c.maxWidth : MediaQuery.sizeOf(context).width;
        final h = c.maxHeight.isFinite ? c.maxHeight : MediaQuery.sizeOf(context).height;
        return SizedBox(
          width: w,
          height: h,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: SizedBox(width: w * 0.96, child: child),
          ),
        );
      });
}

class _NoScroll extends StatelessWidget {
  final Widget child;
  const _NoScroll({required this.child});
  @override
  Widget build(BuildContext context) => child;
}

double _ease(double t, double from, double to, Curve c) =>
    c.transform(((t - from) / (to - from)).clamp(0.0, 1.0));

Text _tx(String s, double size,
        {Color color = Colors.white,
        FontWeight w = FontWeight.w700,
        double ls = 0,
        TextAlign? align}) =>
    Text(
      s,
      textAlign: align,
      style: TextStyle(
        fontSize: size,
        color: color,
        fontWeight: w,
        letterSpacing: ls,
        decoration: TextDecoration.none,
        shadows: const [Shadow(color: Colors.black54, blurRadius: 6, offset: Offset(0, 3))],
      ),
    );

class _Cf {
  final double x, offset, speed, size, sway, spin;
  final Color color;
  _Cf(this.x, this.offset, this.speed, this.size, this.sway, this.spin, this.color);
}

List<_Cf> _makeConf(int n) {
  final rnd = math.Random();
  const palette = [
    Color(0xFFFFD600), Colors.white, Color(0xFFFF4081), Color(0xFF00E5FF),
    Color(0xFF69F0AE), Color(0xFFFF9100),
  ];
  return [
    for (var i = 0; i < n; i++)
      _Cf(rnd.nextDouble(), rnd.nextDouble(), 0.6 + rnd.nextDouble() * 1.4,
          8 + rnd.nextDouble() * 12, 10 + rnd.nextDouble() * 30,
          (rnd.nextDouble() - 0.5) * 2, palette[rnd.nextInt(palette.length)]),
  ];
}

class _ConfPainter extends CustomPainter {
  final double t;
  final List<_Cf> cs;
  final int alpha;
  _ConfPainter(this.t, this.cs, this.alpha);

  @override
  void paint(Canvas canvas, Size size) {
    for (final p in cs) {
      final phase = (t * p.speed * 3 + p.offset) % 1.0;
      final y = phase * (size.height + 60) - 30;
      final x = p.x * size.width + math.sin(phase * 8 + p.offset * 10) * p.sway;
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(phase * p.spin * 10);
      canvas.drawRect(
        Rect.fromCenter(center: Offset.zero, width: p.size, height: p.size * 0.55),
        Paint()..color = p.color.withAlpha(alpha),
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfPainter old) => true;
}

// ---------------------------------------------------------------- backdrop

class _Backdrop extends StatefulWidget {
  final Color c1, c2;
  const _Backdrop(this.c1, this.c2);
  @override
  State<_Backdrop> createState() => _BackdropState();
}

class _BackdropState extends State<_Backdrop> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(seconds: 24))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
        child: AnimatedBuilder(
          animation: _c,
          builder: (_, __) => SizedBox.expand(
            child: CustomPaint(painter: _BdPainter(_c.value, widget.c1, widget.c2)),
          ),
        ),
      );
}

class _BdPainter extends CustomPainter {
  final double t;
  final Color a1, a2;
  _BdPainter(this.t, this.a1, this.a2);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF04060F), Color(0xFF0A1030)],
        ).createShader(rect),
    );
    final cols = [a1, a2, _gold];
    for (var i = 0; i < 3; i++) {
      final cx = size.width * (0.5 + 0.4 * math.sin(2 * math.pi * (t * (i + 1) + i * 0.33)));
      final cy = size.height * (0.5 + 0.34 * math.cos(2 * math.pi * (t * (i + 1) + i * 0.61)));
      final rad = size.shortestSide * 0.75;
      final c = Offset(cx, cy);
      canvas.drawCircle(
        c,
        rad,
        Paint()
          ..shader = RadialGradient(colors: [cols[i].withAlpha(i == 2 ? 36 : 62), Colors.transparent])
              .createShader(Rect.fromCircle(center: c, radius: rad)),
      );
    }
    final rnd = math.Random(11);
    final sp = Paint();
    for (var i = 0; i < 36; i++) {
      final x = rnd.nextDouble() * size.width;
      final y = rnd.nextDouble() * size.height;
      final ph = rnd.nextDouble();
      final r = 0.8 + rnd.nextDouble() * 1.8;
      sp.color = Colors.white.withAlpha(((math.sin(2 * math.pi * (t * 24 + ph)) * 0.5 + 0.5) * 120).round());
      canvas.drawCircle(Offset(x, y), r, sp);
    }
  }

  @override
  bool shouldRepaint(_BdPainter old) => true;
}

// ------------------------------------------------------------ photo badge

class _PhotoBadge extends StatefulWidget {
  final String? path;
  final String name;
  final double size;
  final Color ring;
  const _PhotoBadge({required this.path, required this.name, required this.size, required this.ring});
  @override
  State<_PhotoBadge> createState() => _PhotoBadgeState();
}

class _PhotoBadgeState extends State<_PhotoBadge> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(seconds: 6))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Widget _initials(double s) {
    final parts = widget.name.trim().split(RegExp(r'\s+')).where((e) => e.isNotEmpty).toList();
    final ini = parts.isEmpty ? '?' : parts.take(2).map((e) => e[0].toUpperCase()).join();
    return Container(
      color: widget.ring.withAlpha(150),
      alignment: Alignment.center,
      child: Text(ini,
          style: TextStyle(
              fontSize: s * 0.38,
              color: Colors.white,
              fontWeight: FontWeight.w900,
              decoration: TextDecoration.none)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    final inner = s * 0.84;
    return RepaintBoundary(
        child: SizedBox(
      width: s,
      height: s,
      child: Stack(alignment: Alignment.center, children: [
        AnimatedBuilder(
          animation: _c,
          builder: (_, __) => CustomPaint(
            size: Size.square(s),
            painter: _RingPainter(_c.value * 2 * math.pi, widget.ring),
          ),
        ),
        SizedBox(
          width: inner,
          height: inner,
          child: ClipOval(
            child: widget.path != null
                ? Image.file(File(widget.path!),
                    fit: BoxFit.cover,
                    alignment: Alignment.topCenter,
                    cacheWidth: math.max(256, (s * 2).round()),
                    filterQuality: FilterQuality.medium,
                    errorBuilder: (_, __, ___) => _initials(inner))
                : _initials(inner),
          ),
        ),
      ]),
    ));
  }
}

class _RingPainter extends CustomPainter {
  final double angle;
  final Color color;
  _RingPainter(this.angle, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2 - size.width * 0.04;
    final glowR = r + size.width * 0.05;
    canvas.drawCircle(
      c,
      glowR,
      Paint()
        ..shader = RadialGradient(
          colors: [Colors.transparent, color.withAlpha(120), Colors.transparent],
          stops: const [0.80, 0.92, 1.0],
        ).createShader(Rect.fromCircle(center: c, radius: glowR)),
    );
    final rect = Rect.fromCircle(center: c, radius: r);
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.width * 0.03
        ..shader = SweepGradient(
          colors: [color, Colors.white, color.withAlpha(40), color],
          transform: GradientRotation(angle),
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) => true;
}

Widget _teamTile(TeamCard c, double photo, double pop, double txt) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Transform.scale(
          scale: pop.clamp(0.0, 1.15),
          child: _PhotoBadge(
            path: c.photo,
            name: c.captain.isEmpty ? c.team : c.captain,
            size: photo,
            ring: c.color,
          ),
        ),
        SizedBox(height: photo * 0.07),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: _tx(c.team.toUpperCase(), photo * 0.2, w: FontWeight.w900, ls: 2),
        ),
        Opacity(
          opacity: txt.clamp(0.0, 1.0),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            _tx('CAPTAIN', photo * 0.085, color: _gold, ls: 5, w: FontWeight.w800),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: _tx(c.captain.toUpperCase(), photo * 0.13, w: FontWeight.w800, ls: 1),
            ),
          ]),
        ),
      ],
    );

// ================================================================ INTRO SCREEN

class IntroScreen extends StatefulWidget {
  final IntroKind kind;
  final TeamCard? a, b;
  final String? league, subtitle, line, decision;
  final bool bat;
  const IntroScreen({
    super.key,
    required this.kind,
    this.a,
    this.b,
    this.league,
    this.subtitle,
    this.line,
    this.decision,
    this.bat = true,
  });
  @override
  State<IntroScreen> createState() => _IntroScreenState();
}

class _IntroScreenState extends State<IntroScreen> with TickerProviderStateMixin {
  late final AnimationController _c;
  late final AnimationController _loop =
      AnimationController(vsync: this, duration: const Duration(seconds: 8))..repeat();
  late final List<_Cf> _conf = _makeConf(120);
  bool _closing = false;

  /// Every presentation stays on screen until the user closes it (X button / Esc).
  bool get _persistent => true;

  Color get _c1 => widget.a?.color ?? _gold;
  Color get _c2 => widget.kind == IntroKind.versus
      ? (widget.b?.color ?? _gold)
      : (widget.kind == IntroKind.league ? const Color(0xFF7C4DFF) : _gold);

  @override
  void initState() {
    super.initState();
    final ms = switch (widget.kind) {
      IntroKind.team => 2800,
      IntroKind.versus => 3200,
      IntroKind.league => 3800,
      IntroKind.tossResult => 3200,
      IntroKind.winner => 3600,
    };
    _c = AnimationController(vsync: this, duration: Duration(milliseconds: ms))
      ..addStatusListener((s) {
        if (s == AnimationStatus.completed && !_persistent) _close();
      })
      ..forward();
  }

  @override
  void dispose() {
    _c.dispose();
    _loop.dispose();
    super.dispose();
  }

  void _close() {
    if (_closing || !mounted) return;
    _closing = true;
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    return MediaQuery.withNoTextScaling(
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Focus(
          autofocus: true,
          onKeyEvent: (n, e) {
            if (e is KeyDownEvent && e.logicalKey == LogicalKeyboardKey.escape) {
              _close();
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _persistent ? null : _close,
            child: Stack(fit: StackFit.expand, children: [
              _Backdrop(_c1, _c2),
              if (widget.kind == IntroKind.winner)
                AnimatedBuilder(
                  animation: _loop,
                  builder: (_, __) => SizedBox.expand(
                    child: CustomPaint(painter: _ConfPainter(_loop.value, _conf, 190)),
                  ),
                ),
              AnimatedBuilder(
                animation: _c,
                builder: (context, _) {
                  final t = _c.value;
                  final out = (!_persistent && t > 0.93)
                      ? 1 - (t - 0.93) / 0.07
                      : 1.0;
                  return Opacity(
                    opacity: out.clamp(0.0, 1.0),
                    child: LayoutBuilder(builder: (context, box) => _body(box, t)),
                  );
                },
              ),
              Positioned(
                bottom: 10,
                left: 0,
                right: 0,
                child: Center(
                  child: Text(
                    _persistent
                        ? 'Stays on screen until you close it  •  press Esc or the ✕ button'
                        : 'Tap anywhere or press Esc to close',
                    style: const TextStyle(
                        color: Colors.white38, fontSize: 12, decoration: TextDecoration.none),
                  ),
                ),
              ),
              Positioned(
                top: 10,
                right: 10,
                child: SafeArea(
                  child: Material(
                    color: Colors.black.withAlpha(120),
                    shape: const CircleBorder(),
                    child: IconButton(
                      tooltip: 'Close (Esc)',
                      iconSize: 30,
                      color: Colors.white,
                      icon: const Icon(Icons.close),
                      onPressed: _close,
                    ),
                  ),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _body(BoxConstraints box, double t) => Padding(
        padding: const EdgeInsets.only(top: 48, bottom: 36),
        child: _Fit(child: _bodyInner(box, t)),
      );

  Widget _bodyInner(BoxConstraints box, double t) {
    switch (widget.kind) {
      case IntroKind.team:
        return _captainLayout(box, t, widget.a!,
            top: (widget.league == null || widget.league!.isEmpty)
                ? 'TEAM PRESENTATION'
                : widget.league!.toUpperCase());
      case IntroKind.tossResult:
        return _captainLayout(box, t, widget.a!,
            top: 'TOSS RESULT',
            slam: 'WON THE TOSS',
            decision: widget.bat ? 'ELECTED TO BAT' : 'ELECTED TO FIELD',
            line: widget.line);
      case IntroKind.winner:
        return _captainLayout(box, t, widget.a!,
            top: (widget.league == null || widget.league!.isEmpty)
                ? 'MATCH RESULT'
                : widget.league!.toUpperCase(),
            slam: 'MATCH WINNER',
            decision: widget.decision,
            decisionIcon: Icons.emoji_events,
            line: widget.line);
      case IntroKind.versus:
        return _versusBody(box, t);
      case IntroKind.league:
        return _leagueBody(box, t);
    }
  }

  // Team name + captain photo + captain name (also used for the toss winner).
  Widget _captainLayout(BoxConstraints box, double t, TeamCard card,
      {required String top,
      String? slam,
      String? line,
      String? decision,
      IconData? decisionIcon}) {
    final wide = box.maxWidth / box.maxHeight > 1.2;
    final photoSize = wide
        ? math.min(box.maxHeight * 0.6, box.maxWidth * 0.34)
        : math.min(box.maxWidth * 0.66, box.maxHeight * 0.34);
    final nameSize = wide
        ? math.min(box.maxHeight * 0.14, box.maxWidth * 0.07)
        : box.maxWidth * 0.11;
    final photoT = _ease(t, 0.04, 0.40, Curves.elasticOut);
    final fadeP = _ease(t, 0.02, 0.15, Curves.easeOut);
    final nameT = _ease(t, 0.18, 0.46, Curves.easeOutCubic);
    final slamT = _ease(t, 0.40, 0.55, Curves.easeOutBack);
    final capT = _ease(t, 0.46, 0.66, Curves.easeOutCubic);
    final lineT = _ease(t, 0.60, 0.80, Curves.easeOutCubic);
    final align = wide ? CrossAxisAlignment.start : CrossAxisAlignment.center;

    final photo = Opacity(
      opacity: fadeP,
      child: Transform.scale(
        scale: photoT.clamp(0.0, 1.15),
        child: _PhotoBadge(
          path: card.photo,
          name: card.captain.isEmpty ? card.team : card.captain,
          size: photoSize,
          ring: card.color,
        ),
      ),
    );

    final texts = Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: align, children: [
      Opacity(
        opacity: nameT,
        child: _tx(top, nameSize * 0.26, color: Colors.white70, ls: 6, w: FontWeight.w700),
      ),
      SizedBox(height: nameSize * 0.2),
      ClipRect(
        child: Align(
          alignment: wide ? Alignment.centerLeft : Alignment.center,
          widthFactor: nameT.clamp(0.001, 1.0),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: _tx(card.team.toUpperCase(), nameSize, w: FontWeight.w900, ls: 3),
          ),
        ),
      ),
      SizedBox(height: nameSize * 0.12),
      Container(
        height: 4,
        width: nameSize * 5 * nameT,
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [card.color, _gold]),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
      if (slam != null) ...[
        SizedBox(height: nameSize * 0.25),
        Opacity(
          opacity: slamT.clamp(0.0, 1.0),
          child: Transform.scale(
            scale: 1 + (1 - slamT.clamp(0.0, 1.0)) * 2.2,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.emoji_events, color: _gold, size: nameSize * 0.6),
              SizedBox(width: nameSize * 0.15),
              _tx(slam, nameSize * 0.55, color: _gold, w: FontWeight.w900, ls: 5),
            ]),
          ),
        ),
      ],
      if (card.captain.isNotEmpty) ...[
      SizedBox(height: nameSize * 0.3),
      Opacity(
        opacity: capT,
        child: Transform.translate(
          offset: Offset(0, (1 - capT) * 24),
          child: Column(crossAxisAlignment: align, mainAxisSize: MainAxisSize.min, children: [
            _tx('CAPTAIN', nameSize * 0.3, color: _gold, ls: 8, w: FontWeight.w800),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: _tx(card.captain.toUpperCase(), nameSize * 0.62, w: FontWeight.w800, ls: 2),
            ),
          ]),
        ),
      ),
      ],
      if (decision != null) ...[
        SizedBox(height: nameSize * 0.3),
        Opacity(
          opacity: lineT,
          child: Transform.scale(
            scale: 0.85 + 0.15 * lineT,
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: nameSize * 0.4, vertical: nameSize * 0.15),
              decoration: BoxDecoration(
                color: _gold.withAlpha(30),
                border: Border.all(color: _gold, width: 2),
                borderRadius: BorderRadius.circular(nameSize),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(decisionIcon ?? (widget.bat ? Icons.sports_cricket : Icons.sports_baseball),
                    color: _gold, size: nameSize * 0.55),
                SizedBox(width: nameSize * 0.2),
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: _tx(decision, nameSize * 0.5, w: FontWeight.w900, ls: 3, color: _gold),
                  ),
                ),
              ]),
            ),
          ),
        ),
      ],
      if (line != null) ...[
        SizedBox(height: nameSize * 0.35),
        Opacity(
          opacity: lineT,
          child: Transform.translate(
            offset: Offset(0, (1 - lineT) * 20),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (decision == null) ...[
                Icon(widget.bat ? Icons.sports_cricket : Icons.sports_baseball,
                    color: _gold, size: nameSize * 0.6),
                SizedBox(width: nameSize * 0.2),
              ],
              Flexible(
                child: _tx(line, nameSize * 0.42,
                    w: FontWeight.w700, align: wide ? TextAlign.left : TextAlign.center),
              ),
            ]),
          ),
        ),
      ],
    ]);

    if (wide) {
      return Center(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: box.maxWidth * 0.05),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            photo,
            SizedBox(width: box.maxWidth * 0.04),
            Flexible(child: texts),
          ]),
        ),
      );
    }
    return Center(
      child: _NoScroll(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          photo,
          SizedBox(height: box.maxHeight * 0.03),
          SizedBox(width: box.maxWidth * 0.92, child: texts),
        ]),
      ),
    );
  }

  Widget _versusBody(BoxConstraints box, double t) {
    final a = widget.a!, b = widget.b!;
    final wide = box.maxWidth / box.maxHeight > 1.2;
    final photo = wide
        ? math.min(box.maxHeight * 0.5, box.maxWidth * 0.26)
        : math.min(box.maxWidth * 0.42, box.maxHeight * 0.22);
    final slide = _ease(t, 0.03, 0.35, Curves.easeOutCubic);
    final pop = _ease(t, 0.12, 0.45, Curves.elasticOut);
    final vsT = _ease(t, 0.38, 0.52, Curves.easeOutBack).clamp(0.0, 1.2);
    final txt = _ease(t, 0.30, 0.55, Curves.easeOutCubic);
    final topT = _ease(t, 0.02, 0.2, Curves.easeOut);

    Widget side(TeamCard c, bool left) => Transform.translate(
          offset: Offset((1 - slide) * (left ? -1 : 1) * box.maxWidth * 0.5, 0),
          child: Opacity(opacity: slide, child: _teamTile(c, photo, pop, txt)),
        );

    final vs = Opacity(
      opacity: vsT.clamp(0.0, 1.0),
      child: Transform.scale(
        scale: 0.4 + vsT * 0.6 + (vsT < 1 ? (1 - vsT) * 1.6 : 0),
        child: _tx('VS', photo * 0.4, color: _gold, w: FontWeight.w900, ls: 4),
      ),
    );

    final title = Opacity(
      opacity: topT,
      child: _tx(
        (widget.league == null || widget.league!.isEmpty) ? 'MATCH DAY' : widget.league!.toUpperCase(),
        photo * 0.14,
        color: Colors.white70,
        ls: 8,
      ),
    );

    if (wide) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          title,
          SizedBox(height: photo * 0.2),
          Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            Expanded(child: side(a, true)),
            SizedBox(width: photo * 0.7, child: Center(child: vs)),
            Expanded(child: side(b, false)),
          ]),
        ]),
      );
    }
    return Center(
      child: _NoScroll(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          title,
          SizedBox(height: photo * 0.1),
          side(a, true),
          SizedBox(height: photo * 0.12),
          vs,
          SizedBox(height: photo * 0.12),
          side(b, false),
        ]),
      ),
    );
  }

  Widget _leagueBody(BoxConstraints box, double t) {
    final name = (widget.league ?? '').toUpperCase();
    final base = math.min(box.maxWidth, box.maxHeight * 1.7);
    final size = base * (name.length > 22 ? 0.055 : (name.length > 12 ? 0.075 : 0.095));
    final lineT = _ease(t, 0.02, 0.30, Curves.easeOutCubic);
    final trophyT = _ease(t, 0.05, 0.35, Curves.elasticOut);
    final shine = ((t - 0.30) / 0.45).clamp(0.0, 1.0);
    final subT = _ease(t, 0.68, 0.85, Curves.easeOutCubic);
    final n = math.max(1, name.length);

    final letters = <Widget>[];
    for (var i = 0; i < name.length; i++) {
      final ch = name[i];
      if (ch == ' ') {
        letters.add(SizedBox(width: size * 0.4));
        continue;
      }
      final st = 0.12 + i * (0.34 / n);
      final lt = _ease(t, st, st + 0.18, Curves.easeOutBack);
      letters.add(Transform.translate(
        offset: Offset(0, (1 - lt) * size * 0.9),
        child: Text(
          ch,
          style: TextStyle(
            fontSize: size,
            fontWeight: FontWeight.w900,
            color: Colors.white.withAlpha((lt.clamp(0.0, 1.0) * 255).round()),
            letterSpacing: size * 0.06,
            decoration: TextDecoration.none,
          ),
        ),
      ));
    }

    Widget bar() => Container(
          height: 4,
          width: base * 0.7 * lineT,
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [Colors.transparent, _gold, Colors.transparent]),
            borderRadius: BorderRadius.circular(2),
          ),
        );

    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: box.maxWidth * 0.05),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Transform.scale(
            scale: trophyT.clamp(0.0, 1.2),
            child: Icon(Icons.emoji_events,
                size: base * 0.13,
                color: _gold,
                shadows: [Shadow(color: _gold.withAlpha(180), blurRadius: base * 0.04)]),
          ),
          SizedBox(height: size * 0.3),
          bar(),
          SizedBox(height: size * 0.4),
          shine >= 1.0 || shine <= 0.0
              ? Wrap(
                  alignment: WrapAlignment.center,
                  runSpacing: size * 0.2,
                  children: letters,
                )
              : ShaderMask(
                  blendMode: BlendMode.srcATop,
                  shaderCallback: (r) => LinearGradient(
                    begin: Alignment(-2.0 + 4.0 * shine, -0.4),
                    end: Alignment(-1.0 + 4.0 * shine, 0.4),
                    colors: const [Colors.white, _gold, Colors.white],
                    stops: const [0.0, 0.5, 1.0],
                  ).createShader(r),
                  child: Wrap(
                    alignment: WrapAlignment.center,
                    runSpacing: size * 0.2,
                    children: letters,
                  ),
                ),
          SizedBox(height: size * 0.4),
          bar(),
          if (widget.subtitle != null) ...[
            SizedBox(height: size * 0.5),
            Opacity(
              opacity: subT,
              child: Transform.translate(
                offset: Offset(0, (1 - subT) * 20),
                child: _tx(widget.subtitle!.toUpperCase(), size * 0.32,
                    color: Colors.white70, ls: 6),
              ),
            ),
          ],
        ]),
      ),
    );
  }
}

// =================================================================== TOSS

enum _Ph { ready, flipping, pick, winner, done }

class TossScreen extends StatefulWidget {
  final TeamCard a, b;
  final String? league;
  const TossScreen({super.key, required this.a, required this.b, this.league});
  @override
  State<TossScreen> createState() => _TossScreenState();
}

class _TossScreenState extends State<TossScreen> with TickerProviderStateMixin {
  _Ph _ph = _Ph.ready;
  int? _winner;
  bool? _bat;
  late final AnimationController _in =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1700))..forward();
  late final AnimationController _coin =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 2900));
  late final AnimationController _pulse =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))
        ..repeat(reverse: true);
  late final AnimationController _loop =
      AnimationController(vsync: this, duration: const Duration(seconds: 8))..repeat();
  late final List<_Cf> _conf = _makeConf(90);

  TeamCard get _w => _winner == 0 ? widget.a : widget.b;

  @override
  void dispose() {
    _in.dispose();
    _coin.dispose();
    _pulse.dispose();
    _loop.dispose();
    super.dispose();
  }

  void _go(_Ph p) {
    setState(() => _ph = p);
    _in.forward(from: 0);
  }

  void _start() {
    _go(_Ph.flipping);
    HapticFeedback.mediumImpact();
    _coin.forward(from: 0).whenComplete(() {
      if (mounted && _ph == _Ph.flipping) {
        HapticFeedback.heavyImpact();
        _go(_Ph.pick);
      }
    });
  }

  String get _sentence =>
      '${_w.team} won the toss and elected to ${_bat == true ? 'bat' : 'field'}.';

  @override
  Widget build(BuildContext context) {
    final showConf = _ph == _Ph.winner || _ph == _Ph.done;
    return MediaQuery.withNoTextScaling(
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Focus(
          autofocus: true,
          onKeyEvent: (n, e) {
            if (e is KeyDownEvent &&
                e.logicalKey == LogicalKeyboardKey.escape &&
                _ph != _Ph.flipping) {
              Navigator.of(context).maybePop();
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: Stack(fit: StackFit.expand, children: [
            _Backdrop(widget.a.color, widget.b.color),
            if (showConf)
              AnimatedBuilder(
                animation: _loop,
                builder: (_, __) => SizedBox.expand(
                  child: CustomPaint(painter: _ConfPainter(_loop.value, _conf, 200)),
                ),
              ),
            SafeArea(
              child: AnimatedBuilder(
                animation: _in,
                builder: (context, _) => LayoutBuilder(builder: (context, box) => _phase(box)),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _phase(BoxConstraints box) => _Fit(child: _phaseInner(box));

  Widget _phaseInner(BoxConstraints box) {
    switch (_ph) {
      case _Ph.ready:
        return _ready(box);
      case _Ph.flipping:
        return _flipping(box);
      case _Ph.pick:
        return _pick(box);
      case _Ph.winner:
        return _winnerView(box);
      case _Ph.done:
        return _doneView(box);
    }
  }

  Widget _head(double base, String title) {
    final t = _ease(_in.value, 0, 0.25, Curves.easeOutCubic);
    return Opacity(
      opacity: t,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (widget.league != null && widget.league!.isNotEmpty)
          _tx(widget.league!.toUpperCase(), base * 0.028, color: _gold, ls: 6),
        SizedBox(height: base * 0.01),
        Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.monetization_on, color: _gold, size: base * 0.06),
          SizedBox(width: base * 0.015),
          _tx(title, base * 0.06, w: FontWeight.w900, ls: 8),
        ]),
      ]),
    );
  }

  Widget _bigButton(String label, IconData icon, VoidCallback onTap, double base,
      {Color bg = _gold, Color fg = Colors.black}) {
    return FilledButton.icon(
      style: FilledButton.styleFrom(
        backgroundColor: bg,
        foregroundColor: fg,
        padding: EdgeInsets.symmetric(horizontal: base * 0.04, vertical: base * 0.022),
        textStyle: TextStyle(fontSize: base * 0.03, fontWeight: FontWeight.w900, letterSpacing: 2),
      ),
      onPressed: onTap,
      icon: Icon(icon, size: base * 0.04),
      label: Text(label),
    );
  }

  Widget _ready(BoxConstraints box) {
    final base = math.min(box.maxWidth, box.maxHeight * 1.7);
    final wide = box.maxWidth / box.maxHeight > 1.2;
    final photo = wide
        ? math.min(box.maxHeight * 0.42, box.maxWidth * 0.24)
        : math.min(box.maxWidth * 0.4, box.maxHeight * 0.2);
    final t = _in.value;
    final slide = _ease(t, 0.05, 0.4, Curves.easeOutCubic);
    final pop = _ease(t, 0.1, 0.5, Curves.elasticOut);
    final txt = _ease(t, 0.35, 0.6, Curves.easeOutCubic);
    final btn = _ease(t, 0.55, 0.85, Curves.easeOutBack).clamp(0.0, 1.1);

    Widget side(TeamCard c, bool left) => Transform.translate(
          offset: Offset((1 - slide) * (left ? -1 : 1) * box.maxWidth * 0.4, 0),
          child: Opacity(opacity: slide, child: _teamTile(c, photo, pop, txt)),
        );
    final vs = _tx('VS', photo * 0.34, color: _gold, w: FontWeight.w900, ls: 4);

    final tiles = wide
        ? Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            Expanded(child: side(widget.a, true)),
            SizedBox(width: photo * 0.6, child: Center(child: vs)),
            Expanded(child: side(widget.b, false)),
          ])
        : Column(mainAxisSize: MainAxisSize.min, children: [
            side(widget.a, true),
            SizedBox(height: photo * 0.1),
            vs,
            SizedBox(height: photo * 0.1),
            side(widget.b, false),
          ]);

    return Center(
      child: _NoScroll(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          _head(base, 'TOSS'),
          SizedBox(height: base * 0.03),
          tiles,
          SizedBox(height: base * 0.04),
          Opacity(
            opacity: btn.clamp(0.0, 1.0),
            child: Transform.scale(
              scale: 0.8 + btn * 0.2,
              child: ScaleTransition(
                scale: Tween<double>(begin: 1.0, end: 1.05).animate(_pulse),
                child: _bigButton('START TOSS', Icons.monetization_on, _start, base),
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).maybePop(),
            child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
          ),
        ]),
      ),
    );
  }

  Widget _flipping(BoxConstraints box) {
    final base = math.min(box.maxWidth, box.maxHeight * 1.7);
    final size = math.min(box.maxWidth, box.maxHeight) * 0.26;
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        _head(base, 'TOSS'),
        SizedBox(height: size * 0.3),
        SizedBox(
          height: size * 2.8,
          width: size * 2,
          child: AnimatedBuilder(
            animation: _coin,
            builder: (_, __) {
              final t = _coin.value;
              final h = math.sin(t * math.pi) * size * 1.5;
              final angle = t * math.pi * 2 * 7;
              final front = math.cos(angle) >= 0;
              final sc = 0.85 + 0.4 * math.sin(t * math.pi);
              return Stack(alignment: Alignment.bottomCenter, children: [
                Positioned(
                  bottom: 0,
                  child: Container(
                    width: size * (0.9 - 0.4 * math.sin(t * math.pi)),
                    height: size * 0.14,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.black.withAlpha(110),
                    ),
                  ),
                ),
                Positioned(
                  bottom: size * 0.2 + h,
                  child: Transform.scale(
                    scale: sc,
                    child: Transform(
                      alignment: Alignment.center,
                      transform: Matrix4.identity()
                        ..setEntry(3, 2, 0.0018)
                        ..rotateX(angle),
                      child: Transform(
                        alignment: Alignment.center,
                        transform: Matrix4.identity()..rotateX(front ? 0 : math.pi),
                        child: _coinFace(size, front ? 'H' : 'T'),
                      ),
                    ),
                  ),
                ),
              ]);
            },
          ),
        ),
        _tx('TOSS IN THE AIR…', base * 0.035, color: Colors.white70, ls: 6),
      ]),
    );
  }

  Widget _coinFace(double size, String face) => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const RadialGradient(
            colors: [Color(0xFFFFF59D), Color(0xFFFFC107), Color(0xFFFF8F00)],
          ),
          border: Border.all(color: const Color(0xFFFFE082), width: size * 0.06),
          boxShadow: [BoxShadow(color: _gold.withAlpha(140), blurRadius: size * 0.25)],
        ),
        child: Text(
          face,
          style: TextStyle(
              fontSize: size * 0.5,
              fontWeight: FontWeight.w900,
              color: const Color(0xFF8D6E00),
              decoration: TextDecoration.none),
        ),
      );

  Widget _pick(BoxConstraints box) {
    final base = math.min(box.maxWidth, box.maxHeight * 1.7);
    final wide = box.maxWidth / box.maxHeight > 1.2;
    final photo = wide
        ? math.min(box.maxHeight * 0.4, box.maxWidth * 0.22)
        : math.min(box.maxWidth * 0.36, box.maxHeight * 0.18);
    final t = _in.value;
    final pop = _ease(t, 0.15, 0.55, Curves.elasticOut);
    final txt = _ease(t, 0.3, 0.6, Curves.easeOutCubic);

    Widget choice(int i, TeamCard c) => InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: () {
            _winner = i;
            _go(_Ph.winner);
          },
          child: Container(
            padding: EdgeInsets.all(base * 0.02),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              color: Colors.white.withAlpha(16),
              border: Border.all(color: c.color.withAlpha(180), width: 2),
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              _teamTile(c, photo, pop, txt),
              SizedBox(height: base * 0.012),
              _tx('${c.team.toUpperCase()} WON', base * 0.026, color: _gold, ls: 3, w: FontWeight.w900),
            ]),
          ),
        );

    return Center(
      child: _NoScroll(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          _head(base, 'TOSS RESULT'),
          SizedBox(height: base * 0.015),
          Opacity(
            opacity: _ease(t, 0.1, 0.4, Curves.easeOut),
            child: _tx('Who won the toss?', base * 0.034, color: Colors.white70, ls: 2),
          ),
          SizedBox(height: base * 0.03),
          wide
              ? Row(mainAxisSize: MainAxisSize.min, children: [
                  choice(0, widget.a),
                  SizedBox(width: base * 0.04),
                  choice(1, widget.b),
                ])
              : Column(mainAxisSize: MainAxisSize.min, children: [
                  choice(0, widget.a),
                  SizedBox(height: base * 0.03),
                  choice(1, widget.b),
                ]),
          SizedBox(height: base * 0.02),
          TextButton.icon(
            onPressed: _start,
            icon: const Icon(Icons.replay, color: Colors.white70),
            label: const Text('Flip again', style: TextStyle(color: Colors.white70)),
          ),
        ]),
      ),
    );
  }

  Widget _winnerView(BoxConstraints box) {
    final base = math.min(box.maxWidth, box.maxHeight * 1.7);
    final photo = math.min(box.maxHeight * 0.38, box.maxWidth * 0.5);
    final t = _in.value;
    final pop = _ease(t, 0.05, 0.4, Curves.elasticOut);
    final txt = _ease(t, 0.3, 0.55, Curves.easeOutCubic);
    final slam = _ease(t, 0.35, 0.5, Curves.easeOutBack).clamp(0.0, 1.0);
    final ask = _ease(t, 0.6, 0.85, Curves.easeOutCubic);
    final c = _w;

    return Center(
      child: _NoScroll(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          _head(base, 'TOSS WINNER'),
          SizedBox(height: base * 0.015),
          _teamTile(c, photo, pop, txt),
          SizedBox(height: base * 0.01),
          Opacity(
            opacity: slam,
            child: Transform.scale(
              scale: 1 + (1 - slam) * 2.2,
              child: _tx('WON THE TOSS', base * 0.05, color: _gold, w: FontWeight.w900, ls: 6),
            ),
          ),
          SizedBox(height: base * 0.025),
          Opacity(
            opacity: ask,
            child: Transform.translate(
              offset: Offset(0, (1 - ask) * 24),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                _tx('${c.team} elected to…', base * 0.03, color: Colors.white70, ls: 2),
                SizedBox(height: base * 0.015),
                Wrap(alignment: WrapAlignment.center, spacing: base * 0.025, runSpacing: base * 0.015, children: [
                  _bigButton('BATTING', Icons.sports_cricket, () {
                    _bat = true;
                    _go(_Ph.done);
                  }, base),
                  _bigButton('FIELDING', Icons.sports_baseball, () {
                    _bat = false;
                    _go(_Ph.done);
                  }, base, bg: const Color(0xFF1565C0), fg: Colors.white),
                ]),
              ]),
            ),
          ),
          TextButton(
            onPressed: () => _go(_Ph.pick),
            child: const Text('Change toss winner', style: TextStyle(color: Colors.white54)),
          ),
        ]),
      ),
    );
  }

  Widget _doneView(BoxConstraints box) {
    final base = math.min(box.maxWidth, box.maxHeight * 1.7);
    final photo = math.min(box.maxHeight * 0.26, box.maxWidth * 0.34);
    final t = _in.value;
    final pop = _ease(t, 0.02, 0.35, Curves.elasticOut);
    final txt = _ease(t, 0.2, 0.45, Curves.easeOutCubic);
    final typeT = _ease(t, 0.35, 0.85, Curves.linear);
    final btn = _ease(t, 0.8, 1.0, Curves.easeOutBack).clamp(0.0, 1.0);
    final s = _sentence;
    final n = (s.length * typeT).round().clamp(0, s.length);
    final bat = _bat == true;

    return Center(
      child: _NoScroll(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: box.maxWidth * 0.06),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            _head(base, 'TOSS'),
            SizedBox(height: base * 0.015),
            _teamTile(_w, photo, pop, txt),
            SizedBox(height: base * 0.03),
            ScaleTransition(
              scale: Tween<double>(begin: 0.92, end: 1.08).animate(_pulse),
              child: Icon(bat ? Icons.sports_cricket : Icons.sports_baseball,
                  color: _gold, size: base * 0.08),
            ),
            SizedBox(height: base * 0.015),
            _tx(s.substring(0, n), base * 0.04, w: FontWeight.w800, align: TextAlign.center),
            SizedBox(height: base * 0.03),
            Opacity(
              opacity: btn,
              child: Wrap(
                alignment: WrapAlignment.center,
                spacing: base * 0.025,
                runSpacing: base * 0.015,
                children: [
                  _bigButton('CONFIRM', Icons.check_circle,
                      () => Navigator.of(context).pop(TossResult(_winner!, bat)), base),
                  _bigButton('CHANGE DECISION', Icons.undo, () => _go(_Ph.winner), base,
                      bg: const Color(0xFF1565C0), fg: Colors.white),
                ],
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
