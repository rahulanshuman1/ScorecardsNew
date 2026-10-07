import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show FontFeature;
import 'package:flutter/material.dart';
import 'app_state.dart';
import 'fullscreen.dart';
import 'models.dart';

class _OverRow {
  final int index;
  final List<Ball> balls = [];
  int runs = 0, wk = 0;
  _OverRow(this.index);
}

/// Broadcast-style full-screen scoreboard for TV / projector use.
/// Scoring controls sit in a collapsible strip at the bottom (keyboard shortcuts too).
class CricketTvBoard extends StatelessWidget {
  final CricketMatch m;
  final bool showControls, canScore;
  final void Function(int runs) onRuns;
  final void Function(String type) onExtra; // tap: wd / nb direct, b / lb dialog
  final void Function(String type) onExtraLong; // long-press: choose runs
  final VoidCallback onWicket, onUndo, onTimeout, onEndInnings, onToggleControls, onExit;
  final bool showCard; // full scorecard view instead of live view
  final int cardInnings; // 0 or 1
  final void Function(int innings) onCardInnings;
  final VoidCallback onToggleCard, onRetire;
  final VoidCallback onLeague, onEditLeague, onTeams, onToss, onTossResult, onFullScreen;

  const CricketTvBoard({
    super.key,
    required this.m,
    required this.showControls,
    required this.canScore,
    required this.onRuns,
    required this.onExtra,
    required this.onExtraLong,
    required this.onWicket,
    required this.onUndo,
    required this.onTimeout,
    required this.onEndInnings,
    required this.onToggleControls,
    required this.onExit,
    required this.showCard,
    required this.cardInnings,
    required this.onCardInnings,
    required this.onToggleCard,
    required this.onRetire,
    required this.onLeague,
    required this.onEditLeague,
    required this.onTeams,
    required this.onToss,
    required this.onTossResult,
    required this.onFullScreen,
  });

  static const _gold = Color(0xFFFFC107);

  AppState get _s => AppState.I;
  double get _ts => _s.fontScale.clamp(0.8, 1.4).toDouble();
  Color get _tc => _s.textColor == null ? Colors.white : Color(_s.textColor!);
  FontWeight get _heavy => _s.bold ? FontWeight.w900 : FontWeight.w800;
  FontWeight get _mid => _s.bold ? FontWeight.w800 : FontWeight.w600;
  Color get _accent => Color(_s.accent);

  Text _t(String s, double size,
          {Color? color, FontWeight? w, double ls = 0, TextAlign? align}) =>
      Text(
        s,
        textAlign: align,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: size * _ts,
          color: color ?? _tc,
          fontWeight: w ?? _mid,
          letterSpacing: ls,
          decoration: TextDecoration.none,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      );

  Widget _card(double u, Widget child, {EdgeInsets? pad}) => Container(
        padding: pad ?? EdgeInsets.all(20 * u),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22 * u),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Colors.white.withAlpha(26), Colors.white.withAlpha(8)],
          ),
          border: Border.all(color: Colors.white.withAlpha(46), width: 1.2),
          boxShadow: [
            BoxShadow(color: Colors.black.withAlpha(90), blurRadius: 24 * u, offset: Offset(0, 8 * u)),
          ],
        ),
        child: child,
      );

  Widget _initials(String s, double size) => Container(
        color: const Color(0xFF3949AB),
        alignment: Alignment.center,
        child: Text(s,
            style: TextStyle(
                fontSize: size * 0.4,
                color: Colors.white,
                fontWeight: FontWeight.w800,
                decoration: TextDecoration.none)),
      );

  Widget _avatar(String team, String name, double size) {
    final p = AppState.I.photoFor(team, name);
    final parts = name.trim().split(RegExp(r'\s+')).where((e) => e.isNotEmpty).toList();
    final ini = parts.isEmpty ? '?' : parts.take(2).map((e) => e[0].toUpperCase()).join();
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: _gold, width: math.max(2, size * 0.04)),
      ),
      child: ClipOval(
        child: p != null
            ? Image.file(File(p),
                fit: BoxFit.cover,
                width: size,
                height: size,
                errorBuilder: (_, __, ___) => _initials(ini, size))
            : _initials(ini, size),
      ),
    );
  }

  Widget _bubble(Ball b, double size) {
    Color bg;
    var txt = b.label;
    if (b.wicket) {
      bg = const Color(0xFFE53935);
    } else if (b.extra != null) {
      bg = const Color(0xFFFB8C00);
    } else if (b.runs == 6) {
      bg = const Color(0xFF8E24AA);
    } else if (b.runs == 4) {
      bg = const Color(0xFF1E88E5);
    } else if (b.runs == 0) {
      bg = Colors.white.withAlpha(36);
      txt = '•';
    } else {
      bg = Colors.white.withAlpha(70);
    }
    return Container(
      constraints: BoxConstraints(minWidth: size),
      height: size,
      padding: EdgeInsets.symmetric(horizontal: size * 0.25),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(size / 2)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(txt,
              style: TextStyle(
                  fontSize: size * 0.46,
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  decoration: TextDecoration.none)),
        ],
      ),
    );
  }

  // ------------------------------------------------------------ data helpers

  BatStat? _bat(Innings i, String? n) {
    if (n == null) return null;
    for (final b in i.batting) {
      if (b.name == n) return b;
    }
    return null;
  }

  List<_OverRow> _overs(Innings inn) {
    final rows = <_OverRow>[];
    var legal = 0;
    _OverRow? cur;
    for (final b in inn.balls) {
      final idx = legal ~/ 6;
      if (cur == null || cur.index != idx) {
        cur = _OverRow(idx);
        rows.add(cur);
      }
      cur.balls.add(b);
      cur.runs += b.total;
      if (b.wicket) cur.wk++;
      if (b.legal) legal++;
    }
    return rows;
  }

  ({int runs, int balls}) _partnership(Innings inn) {
    var start = 0;
    for (var k = 0; k < inn.balls.length; k++) {
      if (inn.balls[k].wicket) start = k + 1;
    }
    var runs = 0, legal = 0;
    for (var k = start; k < inn.balls.length; k++) {
      runs += inn.balls[k].total;
      if (inn.balls[k].legal) legal++;
    }
    return (runs: runs, balls: legal);
  }

  String _lastWicket(Innings inn) {
    for (var k = inn.balls.length - 1; k >= 0; k--) {
      final b = inn.balls[k];
      if (b.wicket) {
        final name = b.out ?? 'Batter';
        final s = _bat(inn, name);
        return '$name ${s?.runs ?? 0} (${s?.balls ?? 0})  ${b.wkType ?? ''}'.trim();
      }
    }
    return '—';
  }

  // -------------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    return MediaQuery.withNoTextScaling(
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF050B1F), Color(0xFF0A1740), Color(0xFF050B1F)],
          ),
        ),
        child: Column(children: [
          Expanded(
            child: Stack(children: [
              LayoutBuilder(builder: (context, box) {
                final wide = box.maxWidth / box.maxHeight > 1.25;
                if (wide) {
                  final u = math.min(box.maxWidth / 1280, box.maxHeight / 720);
                  return showCard ? _cardWide(u) : _wide(u);
                }
                final un = box.maxWidth / 720;
                return showCard ? _cardNarrow(un) : _narrow(un);
              }),
              if (!showControls)
                Positioned(
                  right: 8,
                  bottom: 8,
                  child: Opacity(
                    opacity: 0.45,
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      IconButton(
                        tooltip: FullScreen.I.on ? 'Exit full screen (F)' : 'Full screen (F)',
                        color: Colors.white,
                        icon: Icon(FullScreen.I.on ? Icons.fullscreen_exit : Icons.fullscreen),
                        onPressed: onFullScreen,
                      ),
                      IconButton(
                        tooltip: 'Show controls (H)',
                        color: Colors.white,
                        icon: const Icon(Icons.keyboard_arrow_up),
                        onPressed: onToggleControls,
                      ),
                    ]),
                  ),
                ),
            ]),
          ),
          if (showControls) _controls(),
        ]),
      ),
    );
  }

  Widget _wide(double u) => Padding(
        padding: EdgeInsets.all(22 * u),
        child: Column(children: [
          _header(u),
          SizedBox(height: 14 * u),
          Expanded(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Expanded(flex: 5, child: _scoreCard(u)),
              SizedBox(width: 16 * u),
              Expanded(
                flex: 5,
                child: Column(children: [
                  _battersCard(u),
                  SizedBox(height: 14 * u),
                  _bowlerCard(u),
                  SizedBox(height: 14 * u),
                  Expanded(child: _barsCard(u)),
                ]),
              ),
            ]),
          ),
          SizedBox(height: 14 * u),
          _footer(u),
        ]),
      );

  Widget _narrow(double u) => ListView(
        padding: EdgeInsets.all(16 * u),
        children: [
          _header(u),
          SizedBox(height: 12 * u),
          SizedBox(height: 360 * u, child: _scoreCard(u)),
          SizedBox(height: 12 * u),
          _battersCard(u),
          SizedBox(height: 12 * u),
          _bowlerCard(u),
          SizedBox(height: 12 * u),
          SizedBox(height: 220 * u, child: _barsCard(u)),
          SizedBox(height: 12 * u),
          _footer(u),
        ],
      );

  // ------------------------------------------------------------------- header

  Widget _header(double u) => Row(children: [
        _LiveBadge(u: u),
        SizedBox(width: 16 * u),
        Expanded(flex: 3, child: _t('${m.teamA}  vs  ${m.teamB}', 30 * u, w: _heavy, ls: 1)),
        Expanded(
          flex: 2,
          child: Align(
            alignment: Alignment.centerRight,
            child: _t(
              m.league.trim().isEmpty
                  ? '${m.overs}-OVER MATCH'
                  : '${m.league.toUpperCase()}  •  ${m.overs}-OVER MATCH',
              18 * u,
              color: Colors.white70,
              ls: 3 * u,
            ),
          ),
        ),
      ]);

  // --------------------------------------------------------------- score card

  Widget _stat(String label, String value, double u, {Color? color}) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _t(label, 15 * u, color: Colors.white60, ls: 3 * u, w: FontWeight.w700),
          SizedBox(height: 2 * u),
          _t(value, 34 * u, w: _heavy, color: color),
        ],
      );

  Widget _scoreCard(double u) {
    final i = m.now;
    final chase = m.current == 1 && !m.finished;
    final need = m.target - i.runs;
    final balls = m.overs * 6 - i.legalBalls;
    final rrr = balls > 0 ? need * 6 / balls : 0.0;
    final proj = i.legalBalls == 0 ? 0 : (i.runs * (m.overs * 6) / i.legalBalls).round();
    final over = i.currentOver;

    Widget status;
    if (m.finished) {
      status = Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.emoji_events, color: _gold, size: 40 * u),
        SizedBox(width: 12 * u),
        Flexible(child: _t(m.result.toUpperCase(), 30 * u, w: _heavy, color: _gold)),
      ]);
    } else if (chase) {
      status = Column(children: [
        _t('${m.battingTeam.toUpperCase()} NEED $need RUNS FROM $balls BALLS', 26 * u,
            w: _heavy, color: _gold),
        SizedBox(height: 8 * u),
        ClipRRect(
          borderRadius: BorderRadius.circular(8 * u),
          child: LinearProgressIndicator(
            minHeight: 12 * u,
            value: (i.runs / m.target).clamp(0.0, 1.0),
            backgroundColor: Colors.white.withAlpha(36),
            valueColor: AlwaysStoppedAnimation(_accent),
          ),
        ),
      ]);
    } else if (m.inningsOver) {
      status = _t('INNINGS COMPLETE', 26 * u, w: _heavy, color: _gold, ls: 3 * u);
    } else if (m.preMatch && m.tossDecided) {
      status = _t(m.tossLine.toUpperCase(), 20 * u, w: _heavy, color: _gold, ls: 1 * u);
    } else {
      status = _t('${m.bowlingTeam.toUpperCase()} BOWLING', 22 * u,
          color: Colors.white70, ls: 3 * u, w: FontWeight.w700);
    }

    return _card(
      u,
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Container(
            width: 8 * u,
            height: 46 * u,
            decoration: BoxDecoration(color: _accent, borderRadius: BorderRadius.circular(4 * u)),
          ),
          SizedBox(width: 14 * u),
          Expanded(child: _t(m.battingTeam.toUpperCase(), 40 * u, w: _heavy, ls: 2 * u)),
          Container(
            padding: EdgeInsets.symmetric(horizontal: 14 * u, vertical: 6 * u),
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(30),
              borderRadius: BorderRadius.circular(20 * u),
            ),
            child: _t('INNINGS ${m.current + 1}', 16 * u, ls: 2 * u, w: FontWeight.w700),
          ),
        ]),
        Expanded(
          child: Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: _t('${i.runs}/${i.wickets}', 230 * u, w: FontWeight.w900),
            ),
          ),
        ),
        Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
          _stat('OVERS', '${i.overs} / ${m.overs}', u),
          _stat('RUN RATE', i.runRate.toStringAsFixed(2), u),
          chase || m.current == 1
              ? _stat('TARGET', '${m.target}', u, color: _gold)
              : _stat('PROJECTED', i.legalBalls == 0 ? '—' : '$proj', u, color: _gold),
          if (chase) _stat('REQ. RATE', rrr.toStringAsFixed(2), u, color: _gold),
        ]),
        SizedBox(height: 14 * u),
        status,
        SizedBox(height: 14 * u),
        SizedBox(
          height: 48 * u,
          child: Row(children: [
            _t('THIS OVER', 15 * u, color: Colors.white60, ls: 3 * u, w: FontWeight.w700),
            SizedBox(width: 16 * u),
            Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  for (final b in over)
                    Padding(
                      padding: EdgeInsets.only(right: 8 * u),
                      child: _bubble(b, 44 * u),
                    ),
                ]),
              ),
            ),
          ]),
        ),
      ]),
    );
  }

  // ------------------------------------------------------------ players cards

  Widget _col(String v, double size, double width, {Color? color, FontWeight? w}) =>
      SizedBox(width: width, child: Align(alignment: Alignment.centerRight, child: _t(v, size, color: color, w: w)));

  Widget _cardTitle(String title, List<MapEntry<String, double>> cols, double u) => Padding(
        padding: EdgeInsets.only(bottom: 6 * u),
        child: Row(children: [
          Container(width: 5 * u, height: 18 * u, color: _accent),
          SizedBox(width: 10 * u),
          Expanded(child: _t(title, 15 * u, color: Colors.white60, ls: 3 * u, w: FontWeight.w700)),
          for (final c in cols)
            _col(c.key, 14 * u, c.value * u, color: Colors.white54, w: FontWeight.w700),
        ]),
      );

  Widget _battersCard(double u) {
    final i = m.now;
    Widget row(String? name, bool strike) {
      if (name == null) return SizedBox(height: 66 * u);
      final s = _bat(i, name);
      return Padding(
        padding: EdgeInsets.symmetric(vertical: 6 * u),
        child: Row(children: [
          SizedBox(
            width: 26 * u,
            child: strike ? Icon(Icons.arrow_right, color: _gold, size: 34 * u) : null,
          ),
          _avatar(m.battingTeam, name, 54 * u),
          SizedBox(width: 14 * u),
          Expanded(child: _t(name, 26 * u, w: strike ? _heavy : _mid)),
          _col('${s?.runs ?? 0}', 34 * u, 64 * u, color: strike ? _gold : null, w: _heavy),
          _col('${s?.balls ?? 0}', 22 * u, 52 * u, color: Colors.white70),
          _col('${s?.fours ?? 0}', 22 * u, 40 * u, color: Colors.white70),
          _col('${s?.sixes ?? 0}', 22 * u, 40 * u, color: Colors.white70),
          _col((s?.sr ?? 0).toStringAsFixed(1), 22 * u, 66 * u, color: Colors.white70),
        ]),
      );
    }

    return _card(
      u,
      Column(children: [
        _cardTitle('BATTING', const [
          MapEntry('R', 64), MapEntry('B', 52), MapEntry('4s', 40), MapEntry('6s', 40), MapEntry('SR', 66),
        ], u),
        row(i.striker, true),
        row(i.nonStriker, false),
      ]),
    );
  }

  Widget _bowlerCard(double u) {
    final i = m.now;
    BowlStat? bw;
    for (final b in i.bowling) {
      if (b.name == i.bowler) bw = b;
    }
    return _card(
      u,
      Column(children: [
        _cardTitle('BOWLING', const [
          MapEntry('O', 64), MapEntry('R', 52), MapEntry('W', 52), MapEntry('ECON', 78),
        ], u),
        if (i.bowler == null)
          SizedBox(height: 66 * u, child: Center(child: _t('—', 26 * u, color: Colors.white54)))
        else
          Padding(
            padding: EdgeInsets.symmetric(vertical: 6 * u),
            child: Row(children: [
              SizedBox(width: 26 * u),
              _avatar(m.bowlingTeam, i.bowler!, 54 * u),
              SizedBox(width: 14 * u),
              Expanded(child: _t(i.bowler!, 26 * u, w: _heavy)),
              _col(bw?.overs ?? '0.0', 26 * u, 64 * u, w: _heavy),
              _col('${bw?.runs ?? 0}', 22 * u, 52 * u, color: Colors.white70),
              _col('${bw?.wkts ?? 0}', 26 * u, 52 * u, color: _gold, w: _heavy),
              _col((bw?.econ ?? 0).toStringAsFixed(2), 22 * u, 78 * u, color: Colors.white70),
            ]),
          ),
        Divider(color: Colors.white.withAlpha(30), height: 18 * u),
        Row(children: [
          _t('LAST WICKET', 13 * u, color: Colors.white54, ls: 3 * u, w: FontWeight.w700),
          SizedBox(width: 14 * u),
          Expanded(child: _t(_lastWicket(i), 18 * u, color: Colors.white70)),
        ]),
      ]),
    );
  }

  Widget _barsCard(double u) {
    final i = m.now;
    final rows = _overs(i);
    final curIdx = i.legalBalls ~/ 6;
    return _card(
      u,
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _cardTitle('RUNS PER OVER', const [], u),
        Expanded(
          child: CustomPaint(
            painter: _OverBars(rows, m.overs, _accent, curIdx, u, _ts),
            child: const SizedBox.expand(),
          ),
        ),
      ]),
      pad: EdgeInsets.fromLTRB(20 * u, 16 * u, 20 * u, 10 * u),
    );
  }

  // ------------------------------------------------------------------- footer

  Widget _mini(String label, String value, double u) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _t(label, 13 * u, color: Colors.white60, ls: 2.5 * u, w: FontWeight.w700),
          SizedBox(height: 2 * u),
          _t(value, 28 * u, w: _heavy),
        ],
      );

  Widget _footer(double u) {
    final i = m.now;
    var fours = 0, sixes = 0;
    for (final b in i.batting) {
      fours += b.fours;
      sixes += b.sixes;
    }
    final p = _partnership(i);
    return _card(
      u,
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        _mini('EXTRAS', '${i.extras}', u),
        _mini('FOURS', '$fours', u),
        _mini('SIXES', '$sixes', u),
        _mini('PARTNERSHIP', '${p.runs} (${p.balls})', u),
        _mini('STRATEGIC T/O', '${i.timeouts.length}', u),
      ]),
      pad: EdgeInsets.symmetric(horizontal: 28 * u, vertical: 12 * u),
    );
  }

  // ---------------------------------------------------------- full scorecard

  int _cardIdx() {
    final k = cardInnings.clamp(0, 1).toInt();
    if (k == 1 && m.current == 0 && m.innings[1].balls.isEmpty) return 0;
    return k;
  }

  List<String> _fow(Innings inn) {
    final out = <String>[];
    var total = 0, wk = 0, legal = 0;
    for (final b in inn.balls) {
      total += b.total;
      if (b.legal) legal++;
      if (b.wicket) {
        wk++;
        out.add('$wk-$total (${b.out ?? 'Batter'}, ${legal ~/ 6}.${legal % 6} ov)');
      }
    }
    return out;
  }

  Widget _innChip(String label, bool sel, bool enabled, VoidCallback onTap, double u) => Padding(
        padding: EdgeInsets.only(left: 10 * u),
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(20 * u),
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: 18 * u, vertical: 8 * u),
            decoration: BoxDecoration(
              color: sel ? _accent : Colors.white.withAlpha(enabled ? 30 : 12),
              borderRadius: BorderRadius.circular(20 * u),
            ),
            child: _t(label, 17 * u,
                w: _heavy, ls: 2 * u, color: enabled ? null : Colors.white38),
          ),
        ),
      );

  Widget _cardHeader(double u) {
    final has2 = !(m.current == 0 && m.innings[1].balls.isEmpty);
    final k = _cardIdx();
    return Row(children: [
      _LiveBadge(u: u),
      SizedBox(width: 16 * u),
      Expanded(child: _t('FULL SCORECARD  •  ${m.teamA} vs ${m.teamB}', 28 * u, w: _heavy, ls: 1)),
      _innChip('INNINGS 1', k == 0, true, () => onCardInnings(0), u),
      _innChip('INNINGS 2', k == 1, has2, () => onCardInnings(1), u),
    ]);
  }

  Widget _cardSummary(double u) {
    final k = _cardIdx();
    final i = m.innings[k];
    final team = m.inningsTeam(k);
    return _card(
      u,
      Row(children: [
        Container(
          width: 8 * u,
          height: 56 * u,
          decoration: BoxDecoration(color: _accent, borderRadius: BorderRadius.circular(4 * u)),
        ),
        SizedBox(width: 14 * u),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            _t(team.toUpperCase(), 34 * u, w: _heavy, ls: 2 * u),
            _t(m.finished ? m.result.toUpperCase() : 'INNINGS ${k + 1}', 16 * u,
                color: m.finished ? _gold : Colors.white70, ls: 3 * u, w: FontWeight.w700),
          ]),
        ),
        _t('${i.runs}/${i.wickets}', 74 * u, w: FontWeight.w900, color: _gold),
        SizedBox(width: 26 * u),
        _stat('OVERS', i.overs, u),
        SizedBox(width: 26 * u),
        _stat('RUN RATE', i.runRate.toStringAsFixed(2), u),
        SizedBox(width: 26 * u),
        _stat('EXTRAS', '${i.extras}', u),
      ]),
      pad: EdgeInsets.symmetric(horizontal: 24 * u, vertical: 14 * u),
    );
  }

  Widget _battingSheet(Innings i, String team) {
    const wR = 70.0, wB = 60.0, w4 = 52.0, w6 = 52.0, wSR = 92.0;
    final stats = i.batting;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Expanded(child: _t('BATTING', 18, color: Colors.white54, ls: 3, w: FontWeight.w700)),
        _col('R', 18, wR, color: Colors.white54, w: FontWeight.w700),
        _col('B', 18, wB, color: Colors.white54, w: FontWeight.w700),
        _col('4s', 18, w4, color: Colors.white54, w: FontWeight.w700),
        _col('6s', 18, w6, color: Colors.white54, w: FontWeight.w700),
        _col('SR', 18, wSR, color: Colors.white54, w: FontWeight.w700),
      ]),
      const Divider(color: Colors.white24, height: 16),
      if (stats.isEmpty) _t('Yet to bat', 22, color: Colors.white54),
      for (final s in stats)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(children: [
            _avatar(team, s.name, 44),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _t('${s.name}${s.out ? '' : ' *'}', 26, w: _heavy),
                _t(s.how ?? 'not out', 16, color: s.how == null ? _gold : Colors.white60),
              ]),
            ),
            _col('${s.runs}', 28, wR, w: _heavy, color: s.how == null ? _gold : null),
            _col('${s.balls}', 22, wB, color: Colors.white70),
            _col('${s.fours}', 22, w4, color: Colors.white70),
            _col('${s.sixes}', 22, w6, color: Colors.white70),
            _col(s.sr.toStringAsFixed(1), 22, wSR, color: Colors.white70),
          ]),
        ),
    ]);
  }

  Widget _bowlingSheet(Innings i, String bowlTeam) {
    const wO = 64.0, wR = 56.0, wW = 50.0, wE = 84.0;
    final fow = _fow(i);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Expanded(child: _t('BOWLING', 18, color: Colors.white54, ls: 3, w: FontWeight.w700)),
        _col('O', 18, wO, color: Colors.white54, w: FontWeight.w700),
        _col('R', 18, wR, color: Colors.white54, w: FontWeight.w700),
        _col('W', 18, wW, color: Colors.white54, w: FontWeight.w700),
        _col('ECON', 18, wE, color: Colors.white54, w: FontWeight.w700),
      ]),
      const Divider(color: Colors.white24, height: 16),
      if (i.bowling.isEmpty) _t('No bowling yet', 22, color: Colors.white54),
      for (final b in i.bowling)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(children: [
            _avatar(bowlTeam, b.name, 40),
            const SizedBox(width: 12),
            Expanded(child: _t(b.name, 24, w: _heavy)),
            _col(b.overs, 24, wO, w: _heavy),
            _col('${b.runs}', 22, wR, color: Colors.white70),
            _col('${b.wkts}', 24, wW, color: _gold, w: _heavy),
            _col(b.econ.toStringAsFixed(2), 22, wE, color: Colors.white70),
          ]),
        ),
      const Divider(color: Colors.white24, height: 24),
      Row(children: [
        Expanded(child: _t('EXTRAS', 18, color: Colors.white54, ls: 3, w: FontWeight.w700)),
        _t('${i.extras}', 24, w: _heavy),
      ]),
      const SizedBox(height: 6),
      Row(children: [
        Expanded(child: _t('TOTAL', 18, color: Colors.white54, ls: 3, w: FontWeight.w700)),
        _t('${i.runs}/${i.wickets}  (${i.overs} ov)', 24, w: _heavy, color: _gold),
      ]),
      if (fow.isNotEmpty) ...[
        const Divider(color: Colors.white24, height: 24),
        _t('FALL OF WICKETS', 16, color: Colors.white54, ls: 3, w: FontWeight.w700),
        const SizedBox(height: 6),
        for (final f in fow)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: _t(f, 18, color: Colors.white70),
          ),
      ],
      for (final t in i.timeouts)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: _t('Strategic timeout at ${t.overLabel} ov', 16, color: Colors.white54),
        ),
    ]);
  }

  Widget _cardWide(double u) {
    final k = _cardIdx();
    final i = m.innings[k];
    final team = m.inningsTeam(k);
    final bowlTeam = m.inningsTeam(1 - k);
    return Padding(
      padding: EdgeInsets.all(22 * u),
      child: Column(children: [
        _cardHeader(u),
        SizedBox(height: 14 * u),
        _cardSummary(u),
        SizedBox(height: 14 * u),
        Expanded(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(
              flex: 6,
              child: _card(
                u,
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.topLeft,
                  child: SizedBox(width: 760, child: _battingSheet(i, team)),
                ),
              ),
            ),
            SizedBox(width: 16 * u),
            Expanded(
              flex: 4,
              child: _card(
                u,
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.topLeft,
                  child: SizedBox(width: 560, child: _bowlingSheet(i, bowlTeam)),
                ),
              ),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _cardNarrow(double u) {
    final k = _cardIdx();
    final i = m.innings[k];
    final team = m.inningsTeam(k);
    final bowlTeam = m.inningsTeam(1 - k);
    return ListView(
      padding: EdgeInsets.all(16 * u),
      children: [
        _cardHeader(u),
        SizedBox(height: 12 * u),
        _cardSummary(u),
        SizedBox(height: 12 * u),
        _card(u, FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.topLeft, child: SizedBox(width: 760, child: _battingSheet(i, team)))),
        SizedBox(height: 12 * u),
        _card(u, FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.topLeft, child: SizedBox(width: 560, child: _bowlingSheet(i, bowlTeam)))),
      ],
    );
  }

  // ----------------------------------------------------------------- controls

  Widget _controls() {
    return LayoutBuilder(builder: (context, box) {
      final cu = (box.maxWidth / 1280).clamp(0.8, 1.3).toDouble();
      Widget b(String label, VoidCallback? f, {Color? bg, VoidCallback? long, double? w}) =>
          FilledButton(
            style: FilledButton.styleFrom(
              minimumSize: Size(w ?? 62 * cu, 50 * cu),
              backgroundColor: bg,
              foregroundColor: bg == null ? null : Colors.white,
              padding: EdgeInsets.symmetric(horizontal: 14 * cu),
            ),
            onPressed: f,
            onLongPress: long,
            child: Text(label, style: TextStyle(fontSize: 18 * cu, fontWeight: FontWeight.w800)),
          );
      final on = canScore;
      return Container(
        width: double.infinity,
        padding: EdgeInsets.fromLTRB(16 * cu, 10 * cu, 16 * cu, 8 * cu),
        decoration: BoxDecoration(
          color: Colors.black.withAlpha(150),
          border: Border(top: BorderSide(color: Colors.white.withAlpha(40))),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Wrap(alignment: WrapAlignment.center, spacing: 8 * cu, runSpacing: 8 * cu, children: [
            for (final r in [0, 1, 2, 3, 4, 6])
              b('$r', on ? () => onRuns(r) : null,
                  bg: r == 4
                      ? const Color(0xFF1E88E5)
                      : r == 6
                          ? const Color(0xFF8E24AA)
                          : null),
            b('Wd', on ? () => onExtra('wd') : null,
                bg: const Color(0xFFFB8C00), long: on ? () => onExtraLong('wd') : null),
            b('Nb', on ? () => onExtra('nb') : null,
                bg: const Color(0xFFFB8C00), long: on ? () => onExtraLong('nb') : null),
            b('Bye', on ? () => onExtra('b') : null, bg: const Color(0xFFFB8C00)),
            b('LB', on ? () => onExtra('lb') : null, bg: const Color(0xFFFB8C00)),
            b('W', on ? onWicket : null, bg: const Color(0xFFE53935)),
            b('Undo', onUndo, bg: const Color(0xFF546E7A), w: 84 * cu),
          ]),
          SizedBox(height: 8 * cu),
          Wrap(alignment: WrapAlignment.center, spacing: 8 * cu, runSpacing: 6 * cu, children: [
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: showCard ? _gold : const Color(0xFF1565C0),
                foregroundColor: showCard ? Colors.black : Colors.white,
                padding: EdgeInsets.symmetric(horizontal: 18 * cu, vertical: 14 * cu),
                textStyle: const TextStyle(fontWeight: FontWeight.w800),
              ),
              onPressed: onToggleCard,
              icon: Icon(showCard ? Icons.sports_cricket : Icons.view_list),
              label: Text(showCard ? 'Live view (S)' : 'Full scorecard (S)'),
            ),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(foregroundColor: Colors.white),
              onPressed: (on && m.now.striker != null && m.now.nonStriker != null) ? onRetire : null,
              icon: const Icon(Icons.healing),
              label: const Text('Retired hurt (R)'),
            ),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(foregroundColor: Colors.white),
              onPressed: onLeague,
              icon: const Icon(Icons.emoji_events),
              label: const Text('League'),
            ),
            IconButton(
              tooltip: 'Edit league name',
              color: Colors.white,
              onPressed: onEditLeague,
              icon: const Icon(Icons.edit),
            ),
            if (m.preMatch)
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(foregroundColor: Colors.white),
                onPressed: onTeams,
                icon: const Icon(Icons.groups),
                label: const Text('Show teams'),
              ),
            if (m.preMatch)
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: _gold,
                  foregroundColor: Colors.black,
                  textStyle: const TextStyle(fontWeight: FontWeight.w800),
                ),
                onPressed: onToss,
                icon: const Icon(Icons.monetization_on),
                label: Text(m.tossDecided ? 'Edit toss' : 'Toss'),
              ),
            if (m.tossDecided)
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(foregroundColor: Colors.white),
                onPressed: onTossResult,
                icon: const Icon(Icons.campaign),
                label: const Text('Toss result'),
              ),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(foregroundColor: Colors.white),
              onPressed: on ? onTimeout : null,
              icon: const Icon(Icons.timer),
              label: const Text('Strategic timeout'),
            ),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(foregroundColor: Colors.white),
              onPressed: m.finished ? null : onEndInnings,
              icon: const Icon(Icons.flag),
              label: Text(m.current == 0 ? 'End innings' : 'End match'),
            ),
            OutlinedButton(
              style: OutlinedButton.styleFrom(foregroundColor: Colors.white),
              onPressed: () => AppState.I.setFontScale(AppState.I.fontScale - 0.1),
              child: const Text('A−'),
            ),
            OutlinedButton(
              style: OutlinedButton.styleFrom(foregroundColor: Colors.white),
              onPressed: () => AppState.I.setFontScale(AppState.I.fontScale + 0.1),
              child: const Text('A+'),
            ),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(foregroundColor: Colors.white),
              onPressed: onToggleControls,
              icon: const Icon(Icons.visibility_off),
              label: const Text('Hide controls'),
            ),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: FullScreen.I.on ? _gold : const Color(0xFF00897B),
                foregroundColor: FullScreen.I.on ? Colors.black : Colors.white,
                textStyle: const TextStyle(fontWeight: FontWeight.w800),
              ),
              onPressed: onFullScreen,
              icon: Icon(FullScreen.I.on ? Icons.fullscreen_exit : Icons.fullscreen),
              label: Text(FullScreen.I.on ? 'Exit full screen (F)' : 'Full screen (F)'),
            ),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(foregroundColor: Colors.white),
              onPressed: onExit,
              icon: const Icon(Icons.close),
              label: const Text('Exit TV mode'),
            ),
          ]),
          SizedBox(height: 6 * cu),
          Text(
            'Keys: 0-6 runs  •  D wide  •  N no ball  •  B bye  •  L leg bye  •  W wicket  •  R retired hurt  •  U undo  •  S scorecard  •  ←/→ innings  •  F full screen  •  H hide  •  Esc exit',
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 12 * cu, color: Colors.white54, decoration: TextDecoration.none),
          ),
        ]),
      );
    });
  }
}

class _LiveBadge extends StatefulWidget {
  final double u;
  const _LiveBadge({required this.u});
  @override
  State<_LiveBadge> createState() => _LiveBadgeState();
}

class _LiveBadgeState extends State<_LiveBadge> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
        ..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final u = widget.u;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 16 * u, vertical: 8 * u),
      decoration: BoxDecoration(
        color: const Color(0xFFD50000),
        borderRadius: BorderRadius.circular(8 * u),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        FadeTransition(
          opacity: Tween<double>(begin: 0.25, end: 1).animate(_c),
          child: Container(
            width: 12 * u,
            height: 12 * u,
            decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
          ),
        ),
        SizedBox(width: 10 * u),
        Text(
          'LIVE',
          style: TextStyle(
            fontSize: 22 * u,
            color: Colors.white,
            fontWeight: FontWeight.w900,
            letterSpacing: 3 * u,
            decoration: TextDecoration.none,
          ),
        ),
      ]),
    );
  }
}

class _OverBars extends CustomPainter {
  final List<_OverRow> rows;
  final int slots, curIdx;
  final Color color;
  final double u, ts;
  _OverBars(this.rows, this.slots, this.color, this.curIdx, this.u, this.ts);

  void _text(Canvas c, String s, Offset center, double size, Color col, {bool bold = false}) {
    final tp = TextPainter(
      text: TextSpan(
        text: s,
        style: TextStyle(
            fontSize: size, color: col, fontWeight: bold ? FontWeight.w800 : FontWeight.w600),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(c, center - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (slots <= 0 || size.width <= 0 || size.height <= 0) return;
    var maxRuns = 12;
    for (final r in rows) {
      if (r.runs > maxRuns) maxRuns = r.runs;
    }
    final labelH = 22 * u;
    final topPad = 22 * u;
    final slotW = size.width / slots;
    final barW = slotW * 0.62;
    final chartH = size.height - labelH - topPad;
    final every = slots <= 20 ? 1 : 5;
    canvas.drawLine(
      Offset(0, topPad + chartH),
      Offset(size.width, topPad + chartH),
      Paint()
        ..color = Colors.white.withAlpha(50)
        ..strokeWidth = 1.2,
    );
    for (var s = 0; s < slots; s++) {
      final cx = slotW * s + slotW / 2;
      if ((s + 1) % every == 0 || s == 0) {
        _text(canvas, '${s + 1}', Offset(cx, size.height - labelH / 2), 12 * u, Colors.white54);
      }
    }
    for (final r in rows) {
      if (r.index >= slots) continue;
      final cx = slotW * r.index + slotW / 2;
      final h = chartH * r.runs / maxRuns;
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(cx - barW / 2, topPad + chartH - h, barW, math.max(h, 2)),
        Radius.circular(3 * u),
      );
      canvas.drawRRect(
        rect,
        Paint()..color = r.index == curIdx ? color.withAlpha(140) : color,
      );
      if (slots <= 25 && r.runs > 0) {
        _text(canvas, '${r.runs}', Offset(cx, topPad + chartH - h - 10 * u), 12 * u, Colors.white,
            bold: true);
      }
      for (var w = 0; w < r.wk; w++) {
        canvas.drawCircle(
          Offset(cx, topPad + chartH - h - (slots <= 25 ? 24 : 10) * u - w * 11 * u),
          4.5 * u,
          Paint()..color = const Color(0xFFE53935),
        );
      }
    }
  }

  @override
  bool shouldRepaint(_OverBars old) => true;
}
