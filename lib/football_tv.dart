import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show FontFeature;
import 'package:flutter/material.dart';
import 'app_state.dart';
import 'fullscreen.dart';
import 'intro_screen.dart' show TeamCard;
import 'models.dart';

class FootballTvActions {
  final void Function(int team) goal, penalty, yellow, red, sub;
  final VoidCallback primary,
      alt,
      toggleClock,
      addedTime,
      undo,
      varCheck,
      league,
      editLeague,
      teams,
      winner,
      fullScreen,
      exit,
      toggleControls;
  const FootballTvActions({
    required this.goal,
    required this.penalty,
    required this.yellow,
    required this.red,
    required this.sub,
    required this.primary,
    required this.alt,
    required this.toggleClock,
    required this.addedTime,
    required this.undo,
    required this.varCheck,
    required this.league,
    required this.editLeague,
    required this.teams,
    required this.winner,
    required this.fullScreen,
    required this.exit,
    required this.toggleControls,
  });
}

/// Broadcast-style football scoreboard for TV / projector use.
/// Scoring controls sit in a collapsible strip at the bottom (keyboard shortcuts too).
class FootballTvBoard extends StatelessWidget {
  final FootballMatch m;
  final TeamCard cardA, cardB;
  final bool showControls, running;
  final FootballTvActions act;

  const FootballTvBoard({
    super.key,
    required this.m,
    required this.cardA,
    required this.cardB,
    required this.showControls,
    required this.running,
    required this.act,
  });

  static const _gold = Color(0xFFFFC107);
  static const _yellow = Color(0xFFFFD600);
  static const _red = Color(0xFFE53935);

  AppState get _s => AppState.I;
  double get _ts => _s.fontScale.clamp(0.8, 1.4).toDouble();
  Color get _tc => _s.textColor == null ? Colors.white : Color(_s.textColor!);
  FontWeight get _heavy => _s.bold ? FontWeight.w900 : FontWeight.w800;
  FontWeight get _mid => _s.bold ? FontWeight.w800 : FontWeight.w600;
  TeamCard _card(int t) => t == 0 ? cardA : cardB;

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

  Widget _panel(double u, Widget child, {EdgeInsets? pad}) => Container(
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

  Widget _avatar(TeamCard c, double size) {
    final p = c.photo;
    final src = c.captain.isNotEmpty ? c.captain : c.team;
    final parts = src.trim().split(RegExp(r'\s+')).where((e) => e.isNotEmpty).toList();
    final ini = parts.isEmpty ? '?' : parts.take(2).map((e) => e[0].toUpperCase()).join();
    Widget fallback() => Container(
          color: c.color.withAlpha(170),
          alignment: Alignment.center,
          child: Text(ini,
              style: TextStyle(
                  fontSize: size * 0.4,
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  decoration: TextDecoration.none)),
        );
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: c.color, width: math.max(3, size * 0.05)),
      ),
      child: ClipOval(
        child: p != null
            ? Image.file(File(p),
                fit: BoxFit.cover,
                alignment: Alignment.topCenter,
                width: size,
                height: size,
                cacheWidth: math.max(128, (size * 2).round()),
                errorBuilder: (_, __, ___) => fallback())
            : fallback(),
      ),
    );
  }

  Widget _pill(String s, double u, Color bg, {Color fg = Colors.white}) => Container(
        padding: EdgeInsets.symmetric(horizontal: 14 * u, vertical: 5 * u),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20 * u)),
        child: _t(s, 15 * u, color: fg, ls: 2 * u, w: FontWeight.w800),
      );

  Widget _cardSquare(Color c, double u) => Container(
        width: 14 * u,
        height: 19 * u,
        decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(2 * u)),
      );

  // -------------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    return MediaQuery.withNoTextScaling(
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF04120C), Color(0xFF0A2A1A), Color(0xFF04120C)],
          ),
        ),
        child: Column(children: [
          Expanded(
            child: Stack(children: [
              LayoutBuilder(builder: (context, box) {
                final wide = box.maxWidth / box.maxHeight > 1.25;
                if (wide) {
                  return _wide(math.min(box.maxWidth / 1280, box.maxHeight / 720));
                }
                return _narrow(box.maxWidth / 720);
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
                        onPressed: act.fullScreen,
                      ),
                      IconButton(
                        tooltip: 'Show controls (H)',
                        color: Colors.white,
                        icon: const Icon(Icons.keyboard_arrow_up),
                        onPressed: act.toggleControls,
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
              Expanded(flex: 7, child: _scoreCard(u)),
              SizedBox(width: 16 * u),
              Expanded(
                flex: 4,
                child: Column(children: [
                  if (m.shootout.isNotEmpty)
                    _shootCard(u)
                  else
                    Expanded(flex: 5, child: _statsCard(u)),
                  SizedBox(height: 14 * u),
                  Expanded(flex: 4, child: _timelineCard(u)),
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
          SizedBox(height: 520 * u, child: _scoreCard(u)),
          SizedBox(height: 12 * u),
          if (m.shootout.isNotEmpty) _shootCard(u) else SizedBox(height: 330 * u, child: _statsCard(u)),
          SizedBox(height: 12 * u),
          SizedBox(height: 300 * u, child: _timelineCard(u)),
          SizedBox(height: 12 * u),
          _footer(u),
        ],
      );

  Widget _header(double u) => Row(children: [
        _FbLiveBadge(u: u),
        SizedBox(width: 16 * u),
        Expanded(flex: 3, child: _t('${m.teamA}  vs  ${m.teamB}', 30 * u, w: _heavy, ls: 1)),
        Expanded(
          flex: 2,
          child: Align(
            alignment: Alignment.centerRight,
            child: _t(
              m.league.trim().isEmpty ? 'FOOTBALL' : '${m.league.toUpperCase()}  •  FOOTBALL',
              18 * u,
              color: Colors.white70,
              ls: 3 * u,
            ),
          ),
        ),
      ]);

  // --------------------------------------------------------------- score card

  Widget _teamSide(int t, double u) {
    final c = _card(t);
    final sc = m.scorers(t);
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: SizedBox(
        width: 230 * u,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          _avatar(c, 96 * u),
          SizedBox(height: 8 * u),
          _t(c.team.toUpperCase(), 30 * u, w: _heavy, ls: 1 * u, align: TextAlign.center),
          SizedBox(height: 4 * u),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            _cardSquare(_yellow, u),
            SizedBox(width: 6 * u),
            _t('${m.yellowCards(t)}', 20 * u, w: _heavy),
            SizedBox(width: 16 * u),
            _cardSquare(_red, u),
            SizedBox(width: 6 * u),
            _t('${m.redCards(t)}', 20 * u, w: _heavy),
          ]),
          SizedBox(height: 8 * u),
          for (final line in sc.take(5))
            _t('⚽ $line', 15 * u, color: Colors.white70, align: TextAlign.center),
          if (sc.length > 5) _t('+${sc.length - 5} more', 14 * u, color: Colors.white54),
        ]),
      ),
    );
  }

  Widget _scoreCard(double u) {
    final secs = m.seconds;
    final mm = (secs ~/ 60).toString().padLeft(2, '0');
    final ss = (secs % 60).toString().padLeft(2, '0');
    final over = m.stoppageSecs;
    final added = m.clockPhase ? m.addedFor(m.phase) : 0;
    final live = m.clockPhase && running;

    Widget status = const SizedBox.shrink();
    if (m.finished) {
      status = Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.emoji_events, color: _gold, size: 36 * u),
        SizedBox(width: 10 * u),
        Flexible(child: _t(m.result.toUpperCase(), 26 * u, w: _heavy, color: _gold)),
      ]);
    } else if (m.shootout.isNotEmpty) {
      status = _t('PENALTIES  ${m.shootScore(0)} - ${m.shootScore(1)}', 26 * u,
          w: _heavy, color: _gold);
    }

    return _panel(
      u,
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          _pill(m.phaseLabel.toUpperCase(), u, live ? const Color(0xFF2E7D32) : Colors.white24),
          if (m.clockPhase && !running) ...[
            SizedBox(width: 10 * u),
            _pill('PAUSED', u, const Color(0xFFEF6C00)),
          ],
          if (added > 0) ...[
            SizedBox(width: 10 * u),
            _pill('ADDED TIME +$added', u, const Color(0xFFD50000)),
          ],
        ]),
        SizedBox(height: 4 * u),
        if (m.phase >= 1 && m.phase <= 8)
          Center(child: FittedBox(fit: BoxFit.scaleDown, child: _t('$mm:$ss', 70 * u, w: FontWeight.w900))),
        if (over > 0)
          Center(
            child: _t('STOPPAGE TIME  +${over ~/ 60}:${(over % 60).toString().padLeft(2, '0')}',
                16 * u, color: Colors.redAccent, ls: 2 * u, w: FontWeight.w700),
          ),
        Expanded(
          child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            Expanded(flex: 3, child: _teamSide(0, u)),
            Expanded(
              flex: 4,
              child: Center(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: _t('${m.score(0)} - ${m.score(1)}', 170 * u, w: FontWeight.w900),
                ),
              ),
            ),
            Expanded(flex: 3, child: _teamSide(1, u)),
          ]),
        ),
        status,
        if (m.possA + m.possB > 0) ...[
          SizedBox(height: 10 * u),
          Row(children: [
            _t('${m.possession(0)}%', 20 * u, w: _heavy),
            SizedBox(width: 12 * u),
            Expanded(child: _bar(m.possession(0), m.possession(1), u, 10)),
            SizedBox(width: 12 * u),
            _t('${m.possession(1)}%', 20 * u, w: _heavy),
          ]),
          _t('POSSESSION', 12 * u, color: Colors.white54, ls: 3 * u, align: TextAlign.center),
        ],
      ]),
    );
  }

  Widget _bar(int a, int b, double u, double h) {
    if (a + b == 0) {
      return Container(
        height: h * u,
        decoration: BoxDecoration(
            color: Colors.white.withAlpha(30), borderRadius: BorderRadius.circular(h * u)),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(h * u),
      child: SizedBox(
        height: h * u,
        child: Row(children: [
          Expanded(flex: a * 1000 + 1, child: Container(color: cardA.color)),
          SizedBox(width: 2 * u),
          Expanded(flex: b * 1000 + 1, child: Container(color: cardB.color)),
        ]),
      ),
    );
  }

  // ------------------------------------------------------------- right column

  Widget _cmp(String label, int a, int b, double u) => Padding(
        padding: EdgeInsets.symmetric(vertical: 6 * u),
        child: Column(children: [
          Row(children: [
            SizedBox(width: 60 * u, child: _t('$a', 26 * u, w: _heavy)),
            Expanded(
              child: _t(label, 15 * u,
                  color: Colors.white70, ls: 3 * u, w: FontWeight.w700, align: TextAlign.center),
            ),
            SizedBox(
                width: 60 * u,
                child: Align(alignment: Alignment.centerRight, child: _t('$b', 26 * u, w: _heavy))),
          ]),
          SizedBox(height: 4 * u),
          _bar(a, b, u, 8),
        ]),
      );

  Widget _title(String s, double u) => Padding(
        padding: EdgeInsets.only(bottom: 6 * u),
        child: Row(children: [
          Container(width: 5 * u, height: 18 * u, color: _gold),
          SizedBox(width: 10 * u),
          _t(s, 15 * u, color: Colors.white60, ls: 3 * u, w: FontWeight.w700),
        ]),
      );

  Widget _statsCard(double u) => _panel(
        u,
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _title('MATCH STATS', u),
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.topCenter,
              child: SizedBox(
                width: 520,
                child: Column(children: [
                  _cmp('SHOTS', m.shots(0), m.shots(1), 1),
                  _cmp('ON TARGET', m.count('sot', 0), m.count('sot', 1), 1),
                  _cmp('CORNERS', m.count('corner', 0), m.count('corner', 1), 1),
                  _cmp('FOULS', m.count('foul', 0), m.count('foul', 1), 1),
                  _cmp('OFFSIDES', m.count('offside', 0), m.count('offside', 1), 1),
                  _cmp('YELLOW CARDS', m.yellowCards(0), m.yellowCards(1), 1),
                  _cmp('RED CARDS', m.redCards(0), m.redCards(1), 1),
                ]),
              ),
            ),
          ),
        ]),
      );

  Widget _timelineCard(double u) {
    const key = ['goal', 'owngoal', 'yellow', 'yellow2', 'red', 'sub', 'pen_miss', 'var', 'injury'];
    final list = m.events.where((e) => key.contains(e.type)).toList().reversed.take(8).toList();
    return _panel(
      u,
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _title('MATCH EVENTS', u),
        Expanded(
          child: list.isEmpty
              ? Center(child: _t('No events yet', 18 * u, color: Colors.white38))
              : FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.topLeft,
                  child: SizedBox(
                    width: 520,
                    child: Column(children: [
                      for (final e in list)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(children: [
                            Container(
                              width: 6,
                              height: 30,
                              decoration: BoxDecoration(
                                  color: _card(e.team).color, borderRadius: BorderRadius.circular(3)),
                            ),
                            const SizedBox(width: 10),
                            SizedBox(width: 74, child: _t("${m.labelFor(e)}'", 22, w: _heavy, color: _gold)),
                            Expanded(child: _t(m.describe(e), 22, w: _mid)),
                          ]),
                        ),
                    ]),
                  ),
                ),
        ),
      ]),
    );
  }

  Widget _shootCard(double u) {
    Widget row(int t) => Padding(
          padding: EdgeInsets.symmetric(vertical: 6 * u),
          child: Row(children: [
            SizedBox(width: 130 * u, child: _t(_card(t).team.toUpperCase(), 18 * u, w: _heavy)),
            Expanded(
              child: Wrap(spacing: 8 * u, runSpacing: 6 * u, children: [
                for (final k in m.shootout.where((k) => k.team == t))
                  Icon(k.scored ? Icons.check_circle : Icons.cancel,
                      color: k.scored ? const Color(0xFF43A047) : _red, size: 30 * u),
              ]),
            ),
            _t('${m.shootScore(t)}', 30 * u, w: _heavy, color: _gold),
          ]),
        );
    return _panel(
      u,
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _title('PENALTY SHOOTOUT', u),
        row(0),
        row(1),
        SizedBox(height: 4 * u),
        _t(
          m.shootDecided
              ? '${m.teamAt(m.shootWinner).toUpperCase()} WIN ON PENALTIES'
              : 'NEXT KICK: ${m.teamAt(m.nextShooter).toUpperCase()}',
          16 * u,
          color: _gold,
          w: _heavy,
          ls: 2 * u,
        ),
      ]),
    );
  }

  // ------------------------------------------------------------------- footer

  Widget _mini(String label, String value, double u) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _t(label, 13 * u, color: Colors.white60, ls: 2.5 * u, w: FontWeight.w700),
          SizedBox(height: 2 * u),
          _t(value, 26 * u, w: _heavy),
        ],
      );

  Widget _footer(double u) => _panel(
        u,
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          _mini('ON PITCH', '${m.onPitchCount(0)} v ${m.onPitchCount(1)}', u),
          _mini('SUBS USED', '${m.subsUsed(0)}/${m.subsAllowed}  •  ${m.subsUsed(1)}/${m.subsAllowed}', u),
          _mini('SHOTS (ON TARGET)',
              '${m.shots(0)} (${m.count('sot', 0)})  -  ${m.shots(1)} (${m.count('sot', 1)})', u),
          _mini('CORNERS', '${m.count('corner', 0)} - ${m.count('corner', 1)}', u),
          _mini('FOULS', '${m.count('foul', 0)} - ${m.count('foul', 1)}', u),
        ]),
        pad: EdgeInsets.symmetric(horizontal: 28 * u, vertical: 12 * u),
      );

  // ----------------------------------------------------------------- controls

  Widget _controls() {
    return LayoutBuilder(builder: (context, box) {
      final cu = (box.maxWidth / 1280).clamp(0.8, 1.3).toDouble();
      final en = m.phase >= 1 && m.phase <= 8;
      final clock = m.clockPhase;

      Widget b(String label, VoidCallback? f, {Color? bg, Color fg = Colors.white}) => FilledButton(
            style: FilledButton.styleFrom(
              minimumSize: Size(56 * cu, 46 * cu),
              backgroundColor: bg,
              foregroundColor: fg,
              padding: EdgeInsets.symmetric(horizontal: 12 * cu),
            ),
            onPressed: f,
            child: Text(label, style: TextStyle(fontSize: 16 * cu, fontWeight: FontWeight.w800)),
          );

      Widget group(int t) {
        final c = _card(t).color;
        return Container(
          padding: EdgeInsets.all(8 * cu),
          decoration: BoxDecoration(
            border: Border.all(color: c.withAlpha(190), width: 2),
            borderRadius: BorderRadius.circular(14 * cu),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(_card(t).team.toUpperCase(),
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 13 * cu,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 2,
                    decoration: TextDecoration.none)),
            SizedBox(height: 6 * cu),
            Wrap(spacing: 6 * cu, runSpacing: 6 * cu, alignment: WrapAlignment.center, children: [
              b('⚽ Goal', en && clock ? () => act.goal(t) : null, bg: c),
              b('🎯 Pen', en && clock ? () => act.penalty(t) : null, bg: c),
              b('🟨', en ? () => act.yellow(t) : null, bg: const Color(0xFFF9A825), fg: Colors.black),
              b('🟥', en ? () => act.red(t) : null, bg: const Color(0xFFC62828)),
              b('🔁 Sub', en ? () => act.sub(t) : null, bg: const Color(0xFF455A64)),
            ]),
          ]),
        );
      }

      OutlinedButton o(String label, IconData icon, VoidCallback? f) => OutlinedButton.icon(
            style: OutlinedButton.styleFrom(foregroundColor: Colors.white),
            onPressed: f,
            icon: Icon(icon),
            label: Text(label),
          );

      return Container(
        width: double.infinity,
        padding: EdgeInsets.fromLTRB(16 * cu, 10 * cu, 16 * cu, 8 * cu),
        decoration: BoxDecoration(
          color: Colors.black.withAlpha(150),
          border: Border(top: BorderSide(color: Colors.white.withAlpha(40))),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 14 * cu,
            runSpacing: 8 * cu,
            children: [
              group(0),
              Column(mainAxisSize: MainAxisSize.min, children: [
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: _gold,
                    foregroundColor: Colors.black,
                    padding: EdgeInsets.symmetric(horizontal: 22 * cu, vertical: 14 * cu),
                    textStyle: TextStyle(fontSize: 17 * cu, fontWeight: FontWeight.w900),
                  ),
                  onPressed: m.phase == 10 ? null : act.primary,
                  icon: const Icon(Icons.skip_next),
                  label: Text(m.phase == 10 ? 'Match finished' : m.primaryLabel),
                ),
                if (m.altLabel != null) ...[
                  SizedBox(height: 6 * cu),
                  o(m.altLabel!, Icons.sports_score, act.alt),
                ],
                SizedBox(height: 6 * cu),
                Wrap(spacing: 6 * cu, runSpacing: 6 * cu, alignment: WrapAlignment.center, children: [
                  if (clock)
                    o(running ? 'Pause' : 'Resume', running ? Icons.pause : Icons.play_arrow,
                        act.toggleClock),
                  if (clock) o('Added time', Icons.more_time, act.addedTime),
                  o('Undo', Icons.undo, act.undo),
                  if (en) o('VAR', Icons.tv, act.varCheck),
                ]),
              ]),
              group(1),
            ],
          ),
          SizedBox(height: 8 * cu),
          Wrap(alignment: WrapAlignment.center, spacing: 8 * cu, runSpacing: 6 * cu, children: [
            o('League', Icons.emoji_events, act.league),
            IconButton(
              tooltip: 'Edit league name',
              color: Colors.white,
              onPressed: act.editLeague,
              icon: const Icon(Icons.edit),
            ),
            o('Show teams', Icons.groups, act.teams),
            if (m.finished && m.winnerIdx >= 0)
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: _gold,
                  foregroundColor: Colors.black,
                  textStyle: const TextStyle(fontWeight: FontWeight.w800),
                ),
                onPressed: act.winner,
                icon: const Icon(Icons.emoji_events),
                label: const Text('Show winner'),
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
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: FullScreen.I.on ? _gold : const Color(0xFF00897B),
                foregroundColor: FullScreen.I.on ? Colors.black : Colors.white,
                textStyle: const TextStyle(fontWeight: FontWeight.w800),
              ),
              onPressed: act.fullScreen,
              icon: Icon(FullScreen.I.on ? Icons.fullscreen_exit : Icons.fullscreen),
              label: Text(FullScreen.I.on ? 'Exit full screen (F)' : 'Full screen (F)'),
            ),
            o('Hide controls', Icons.visibility_off, act.toggleControls),
            o('Exit TV mode', Icons.close, act.exit),
          ]),
          SizedBox(height: 6 * cu),
          Text(
            'Keys: 1/2 goal A/B  •  3/4 yellow  •  5/6 red  •  7/8 substitution  •  Space clock  •  N next step  •  V VAR  •  U undo  •  L league  •  F full screen  •  H hide  •  Esc exit',
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 12 * cu, color: Colors.white54, decoration: TextDecoration.none),
          ),
        ]),
      );
    });
  }
}

class _FbLiveBadge extends StatefulWidget {
  final double u;
  const _FbLiveBadge({required this.u});
  @override
  State<_FbLiveBadge> createState() => _FbLiveBadgeState();
}

class _FbLiveBadgeState extends State<_FbLiveBadge> with SingleTickerProviderStateMixin {
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
