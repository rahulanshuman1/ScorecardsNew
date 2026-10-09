import 'dart:async';
import 'dart:io';
import 'dart:ui' show FontFeature;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'app_state.dart';
import 'events_anim.dart';
import 'export_xlsx.dart';
import 'football_setup.dart';
import 'football_tv.dart';
import 'fullscreen.dart';
import 'intro_screen.dart';
import 'milestone_anim.dart';
import 'models.dart';
import 'settings_screen.dart';

class FootballScreen extends StatefulWidget {
  final FootballMatch match;
  final VoidCallback onChanged;
  const FootballScreen({super.key, required this.match, required this.onChanged});
  @override
  State<FootballScreen> createState() => _FootballScreenState();
}

class _FootballScreenState extends State<FootballScreen> {
  FootballMatch get m => widget.match;

  static const _colA = Color(0xFF2979FF);
  static const _colB = Color(0xFFFF6D00);
  static const _gold = Color(0xFFFFC107);

  Timer? _timer;
  bool running = false;
  int _poss = -1; // ball possession: -1 none, 0 team A, 1 team B
  bool _showAll = false;
  bool _tv = false;
  bool _tvControls = true;
  final _tvFocus = FocusNode();
  final _fx = GlobalKey<EventOverlayState>();

  @override
  void initState() {
    super.initState();
    FullScreen.I.addListener(_fsChanged);
  }

  @override
  void dispose() {
    FullScreen.I.removeListener(_fsChanged);
    _timer?.cancel();
    _tvFocus.dispose();
    if (!FullScreen.I.on) SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _fsChanged() {
    if (mounted) setState(() {});
  }

  void _save() => widget.onChanged();

  void _do(VoidCallback f) {
    setState(f);
    _save();
  }

  void _snack(String s) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));

  // ------------------------------------------------------------------ clock

  void _syncTimer() {
    _timer?.cancel();
    _timer = null;
    if (running && m.clockPhase) {
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() {
          m.seconds++;
          if (_poss == 0) {
            m.possA++;
          } else if (_poss == 1) {
            m.possB++;
          }
        });
        if (m.seconds % 15 == 0) _save();
      });
    }
  }

  void _toggleClock() {
    if (!m.clockPhase) return;
    setState(() => running = !running);
    _syncTimer();
    _save();
  }

  // ------------------------------------------------------------ match phases

  void _afterPhase(int before) {
    if (m.phase == before) return;
    running = m.clockPhase;
    _syncTimer();
    const kinds = {
      1: EventKind.kickoff,
      2: EventKind.halfTime,
      4: EventKind.fullTime,
      6: EventKind.halfTime,
      8: EventKind.fullTime,
    };
    final k = kinds[m.phase];
    if (k != null) _fx.currentState?.show([k]);
  }

  /// Rules check before the match may start.
  Future<bool> _kickoffCheck() async {
    final h0 = m.hasLineup(0), h1 = m.hasLineup(1);
    for (var t = 0; t < 2; t++) {
      if (m.hasLineup(t) && m.starters(t).length < 7) {
        _snack('${m.teamAt(t)} needs at least 7 starting players (11 recommended)');
        return false;
      }
    }
    if (h0 != h1) {
      _snack('Set the line-up for both teams (or for neither) before kick-off');
      return false;
    }
    if (!h0 && !h1) {
      final go = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Start without line-ups?'),
          content: const Text(
              'No starting XI is set. Substitution and sent-off rules will use the player names you type. '
              'Set the line-ups first for full rule checking.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Set line-ups')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Start anyway')),
          ],
        ),
      );
      if (go != true) {
        if (mounted) await _setup();
        return false;
      }
    }
    return true;
  }

  Future<void> _advance() async {
    if (m.phase == 0 && !await _kickoffCheck()) return;
    final before = m.phase;
    _do(m.advance);
    _afterPhase(before);
  }

  void _toShootout() {
    final before = m.phase;
    _do(() => m.phase = 9);
    _afterPhase(before);
  }

  Future<void> _finish() async {
    final before = m.phase;
    _do(() => m.phase = 10);
    _afterPhase(before);
    _fx.currentState?.show([EventKind.fullTime]);
    await Future<void>.delayed(const Duration(milliseconds: 1800));
    if (!mounted) return;
    await _announceWinner();
    if (mounted && m.potm == null) _potm();
  }

  Future<void> _primary() async {
    switch (m.phase) {
      case 4:
        if (m.knockout && m.drawn) {
          await _advance();
        } else {
          await _finish();
        }
        break;
      case 8:
        if (m.knockout && m.drawn) {
          _toShootout();
        } else {
          await _finish();
        }
        break;
      case 9:
        if (m.shootDecided) {
          await _finish();
        } else {
          _snack('The shootout is not decided yet');
        }
        break;
      case 10:
        break;
      default:
        await _advance();
    }
  }

  Future<void> _setup() async {
    if (!m.preMatch) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => FootballSetupScreen(match: m, onChanged: _save)),
    );
    if (mounted) setState(() {});
  }

  // ---------------------------------------------------------------- dialogs

  Future<String?> _pick(String title, List<String> options, {bool optional = false}) {
    final c = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) {
        void submit(String v) {
          if (v.trim().isNotEmpty) Navigator.pop(ctx, v.trim());
        }

        final typing = options.isEmpty; // free text only when no line-up is set
        return AlertDialog(
          title: Text(title),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (options.isNotEmpty)
                Wrap(spacing: 6, runSpacing: 6, children: [
                  for (final o in options)
                    ActionChip(label: Text(o), onPressed: () => Navigator.pop(ctx, o)),
                ]),
              if (typing)
                TextField(
                  controller: c,
                  autofocus: true,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Player name'),
                  onSubmitted: submit,
                ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            if (optional) TextButton(onPressed: () => Navigator.pop(ctx, ''), child: const Text('Skip')),
            if (typing) FilledButton(onPressed: () => submit(c.text), child: const Text('OK')),
          ],
        );
      },
    );
  }

  Future<int?> _choose(String title, List<String> labels) => showDialog<int>(
        context: context,
        builder: (ctx) => SimpleDialog(
          title: Text(title),
          children: [
            for (var i = 0; i < labels.length; i++)
              SimpleDialogOption(onPressed: () => Navigator.pop(ctx, i), child: Text(labels[i])),
          ],
        ),
      );

  FootballEvent _newEv(String type, int team, String player, {String? other, String? detail}) =>
      FootballEvent(type, team, player, m.seconds, m.activePeriod, other: other, detail: detail);

  void _addEv(FootballEvent e) => _do(() => m.events.add(e));

  // ------------------------------------------------------------------ goals

  Future<void> _goal(int t, {bool own = false}) async {
    if (!m.clockPhase) {
      _snack('Goals can only be recorded while the clock is running');
      return;
    }
    final pool = m.onPitch(t);
    final scorer =
        await _pick(own ? 'Own goal by – ${m.teamAt(t)}' : 'Goal scorer – ${m.teamAt(t)}', pool);
    if (scorer == null) return;
    String? assist;
    if (!own) {
      final a = await _pick('Assist (optional)', pool.where((p) => p != scorer).toList(),
          optional: true);
      if (a == null) return;
      if (a.isNotEmpty) assist = a;
    }
    final e = _newEv(own ? 'owngoal' : 'goal', t, scorer, other: assist);
    _addEv(e);
    _celebrate(e);
  }

  Future<void> _penalty(int t) async {
    if (!m.clockPhase) {
      _snack('Penalties can only be recorded while the clock is running');
      return;
    }
    final taker = await _pick('Penalty taker – ${m.teamAt(t)}', m.onPitch(t));
    if (taker == null) return;
    final idx = await _choose('Penalty result',
        const ['Scored', 'Saved by the goalkeeper', 'Missed (off target)', 'Hit the post / bar']);
    if (idx == null) return;
    if (idx == 0) {
      final e = _newEv('goal', t, taker, detail: 'penalty');
      _addEv(e);
      _celebrate(e, before: const [EventKind.penalty]);
    } else {
      _addEv(_newEv('pen_miss', t, taker, detail: const ['', 'saved', 'missed', 'hit the woodwork'][idx]));
      _fx.currentState?.show([EventKind.penalty, idx == 1 ? EventKind.saved : EventKind.missed]);
    }
  }

  void _celebrate(FootballEvent e, {List<EventKind> before = const []}) {
    final own = e.type == 'owngoal';
    final tname = m.teamAt(e.team);
    final goals = own ? 0 : m.goalsBy(e.team, e.player);
    var title = own ? 'OWN GOAL' : (e.detail == 'penalty' ? 'PENALTY GOAL!' : 'GOAL!');
    if (goals == 3) title = 'HAT-TRICK!';
    if (goals >= 4) title = '$goals GOALS!';
    final assist = (e.other == null || e.other!.isEmpty) ? '-' : e.other!;
    final info = MilestoneInfo(
      name: e.player.isEmpty ? tname : e.player,
      team: tname,
      titleText: title,
      bigText: '${m.score(0)} - ${m.score(1)}',
      smallText: "${m.labelFor(e)}'",
      photoPath: e.player.isEmpty ? null : AppState.I.photoFor(tname, e.player),
      stats: [
        MapEntry('MINUTE', "${m.labelFor(e)}'"),
        MapEntry('ASSIST', assist),
        MapEntry('GOALS', '$goals'),
      ],
    );
    _fx.currentState?.show(before, milestone: info);
  }

  // ------------------------------------------------- discipline / changes

  Future<void> _card(int t, {required bool red}) async {
    final player = await _pick(red ? 'Red card – ${m.teamAt(t)}' : 'Yellow card – ${m.teamAt(t)}',
        m.onPitch(t));
    if (player == null) return;
    if (red) {
      _addEv(_newEv('red', t, player));
      _fx.currentState?.show([EventKind.red]);
    } else if (m.yellowsOf(t, player) >= 1) {
      _addEv(_newEv('yellow2', t, player));
      _snack('Second yellow – $player is sent off');
      _fx.currentState?.show([EventKind.yellow, EventKind.red]);
    } else {
      _addEv(_newEv('yellow', t, player));
      _fx.currentState?.show([EventKind.yellow]);
    }
    if (m.hasLineup(t) && m.onPitchCount(t) < 7 && mounted) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Match must be abandoned'),
          content: Text('${m.teamAt(t)} has fewer than 7 players on the pitch.'),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
        ),
      );
    }
  }

  Future<void> _sub(int t) async {
    if (m.subsUsed(t) >= m.subsAllowed) {
      _snack('${m.teamAt(t)} has used all ${m.subsAllowed} substitutions');
      return;
    }
    final out = await _pick('Player OFF – ${m.teamAt(t)}', m.onPitch(t));
    if (out == null) return;
    final bench = m.benchAvailable(t);
    if (m.hasLineup(t) && bench.isEmpty) {
      _snack('No substitutes left on the bench');
      return;
    }
    final inn = await _pick('Player ON – ${m.teamAt(t)}', bench);
    if (inn == null) return;
    _addEv(_newEv('sub', t, out, other: inn));
    _fx.currentState?.show([EventKind.sub]);
  }

  Future<void> _injury(int t) async {
    final p = await _pick('Injured player – ${m.teamAt(t)}', m.onPitch(t));
    if (p == null) return;
    _addEv(_newEv('injury', t, p));
  }

  void _quick(String type, int t) => _addEv(_newEv(type, t, ''));

  Future<void> _varCheck() async {
    final i = await _choose('VAR review', const [
      'Goal disallowed (cancel the last goal)',
      'Goal confirmed – stands',
      'Penalty awarded by VAR',
      'Red card by VAR',
      'No change',
    ]);
    if (i == null) return;
    if (i == 0) {
      final goals = m.events.where((e) => (e.type == 'goal' || e.type == 'owngoal') && !e.cancelled);
      if (goals.isEmpty) {
        _snack('No goal to cancel');
        return;
      }
      final g = goals.last;
      _do(() {
        g.cancelled = true;
        m.events.add(_newEv('var', g.team, '', detail: 'Goal disallowed – ${g.player}'));
      });
      _fx.currentState?.show([EventKind.varCheck]);
    } else if (i == 1) {
      _addEv(_newEv('var', 0, '', detail: 'Goal confirmed'));
      _fx.currentState?.show([EventKind.varCheck]);
    } else if (i == 2 || i == 3) {
      final t = await _choose('Which team?', [m.teamA, m.teamB]);
      if (t == null) return;
      _fx.currentState?.show([EventKind.varCheck]);
      if (i == 2) {
        await _penalty(t);
      } else {
        await _card(t, red: true);
      }
    } else {
      _addEv(_newEv('var', 0, '', detail: 'Review – no change'));
    }
  }

  Future<void> _addedTime() async {
    if (!m.clockPhase) return;
    final i = await _choose('Added time (minutes)', [for (var k = 1; k <= 10; k++) '+$k']);
    if (i == null) return;
    _do(() => m.added[m.phase] = i + 1);
  }

  void _undo() {
    if (m.finished || m.preMatch) return;
    _do(() {
      if (m.phase == 9 && m.shootout.isNotEmpty) {
        m.shootout.removeLast();
      } else if (m.events.isNotEmpty) {
        m.events.removeLast();
      }
    });
  }

  // -------------------------------------------------------------- shootout

  Future<void> _shootKick() async {
    if (m.shootDecided) return;
    final t = m.nextShooter;
    final eligible = m.shootEligible(t);
    final taker = await _pick('Penalty kick – ${m.teamAt(t)}', eligible);
    if (taker == null) return;
    final idx = await _choose('Result', const ['Scored', 'Saved', 'Missed']);
    if (idx == null) return;
    _do(() => m.shootout.add(PenKick(t, taker, idx == 0, idx == 0 ? null : (idx == 1 ? 'saved' : 'missed'))));
    _fx.currentState?.show([idx == 0 ? EventKind.goal : (idx == 1 ? EventKind.saved : EventKind.missed)]);
  }

  Future<void> _potm() async {
    final all = <String>[
      ...m.starters(0), ...m.bench(0), ...m.starters(1), ...m.bench(1),
    ];
    final p = await _pick('Player of the match', all.isEmpty ? [...m.playersA, ...m.playersB] : all,
        optional: true);
    if (p == null) return;
    _do(() => m.potm = p.isEmpty ? null : p);
  }

  // ------------------------------------------------- league / teams / winner

  String _capName(int t) {
    final c = t == 0 ? m.captainA : m.captainB;
    if (c.isNotEmpty) return c;
    return AppState.I.captains[m.teamAt(t)] ?? '';
  }

  TeamCard _teamCard(int t) {
    final team = m.teamAt(t);
    final cap = _capName(t);
    return TeamCard(team, cap, cap.isEmpty ? null : AppState.I.photoFor(team, cap),
        t == 0 ? _colA : _colB);
  }

  Future<void> _editLeague() async {
    final c = TextEditingController(text: m.league);
    String? err;
    final res = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('Premier League / tournament name'),
          content: TextField(
            controller: c,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(labelText: 'League name', errorText: err),
            onSubmitted: (v) {
              if (v.trim().isEmpty) {
                setD(() => err = 'Enter a league name');
              } else {
                Navigator.pop(ctx, v.trim());
              }
            },
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            if (m.league.isNotEmpty)
              TextButton(onPressed: () => Navigator.pop(ctx, ''), child: const Text('Remove')),
            FilledButton(
              onPressed: () {
                if (c.text.trim().isEmpty) {
                  setD(() => err = 'Enter a league name');
                } else {
                  Navigator.pop(ctx, c.text.trim());
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (res == null) return;
    _do(() => m.league = res);
    AppState.I.setLeagueName(res);
  }

  Future<void> _showLeague() async {
    if (m.league.trim().isEmpty) {
      await _editLeague();
      if (m.league.trim().isEmpty || !mounted) return;
    }
    await showIntro(context,
        kind: IntroKind.league, league: m.league, subtitle: '${m.teamA} vs ${m.teamB}');
  }

  Future<String?> _pickCaptain(int t) async {
    final name = await _pick('Captain – ${m.teamAt(t)}', m.squad(t));
    if (name == null || name.isEmpty) return null;
    _do(() {
      if (t == 0) {
        m.captainA = name;
      } else {
        m.captainB = name;
      }
    });
    AppState.I.setCaptain(m.teamAt(t), name);
    return name;
  }

  Future<bool> _needCaptain(int t) async {
    if (_capName(t).isNotEmpty) return true;
    final n = await _pickCaptain(t);
    return n != null && n.isNotEmpty;
  }

  Future<void> _showTeam(int t) async {
    if (!await _needCaptain(t) || !mounted) return;
    await showIntro(context,
        kind: IntroKind.team, a: _teamCard(t), league: m.league.isEmpty ? null : m.league);
  }

  Future<void> _showBoth() async {
    if (!await _needCaptain(0) || !mounted) return;
    if (!await _needCaptain(1) || !mounted) return;
    await showIntro(context,
        kind: IntroKind.versus,
        a: _teamCard(0),
        b: _teamCard(1),
        league: m.league.isEmpty ? null : m.league);
  }

  Future<void> _announceWinner() async {
    if (!mounted || !m.finished) return;
    final w = m.winnerIdx;
    if (w < 0) return; // drawn - nothing to announce
    final pens = m.shootout.isNotEmpty
        ? '   •   pens ${m.shootScore(0)} - ${m.shootScore(1)}'
        : '';
    await showIntro(
      context,
      kind: IntroKind.winner,
      a: _teamCard(w),
      league: m.league.isEmpty ? null : m.league,
      decision: '${m.teamAt(w)} ${m.winText}'.toUpperCase(),
      line: '${m.teamA} ${m.score(0)} - ${m.score(1)} ${m.teamB}$pens',
    );
  }

  // ---------------------------------------------------------------- export

  Future<void> _pdf() async {
    final doc = pw.Document();
    final font = pw.Font.courier();
    doc.addPage(pw.MultiPage(
      build: (_) => [pw.Text(m.reportText, style: pw.TextStyle(font: font, fontSize: 9))],
    ));
    final bytes = await doc.save();
    await Printing.layoutPdf(onLayout: (_) async => bytes, name: '${m.teamA}_vs_${m.teamB}');
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: m.reportText));
    if (mounted) _snack('Match report copied');
  }

  // --------------------------------------------------------------- TV mode

  void _enterTv() {
    setState(() {
      _tv = true;
      _tvControls = true;
    });
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _tvFocus.requestFocus();
  }

  void _exitTv() {
    setState(() => _tv = false);
    if (!FullScreen.I.on) SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    final k = e.logicalKey;
    final en = m.phase >= 1 && m.phase <= 8;
    if (k == LogicalKeyboardKey.digit1) {
      if (en) _goal(0);
    } else if (k == LogicalKeyboardKey.digit2) {
      if (en) _goal(1);
    } else if (k == LogicalKeyboardKey.digit3) {
      if (en) _card(0, red: false);
    } else if (k == LogicalKeyboardKey.digit4) {
      if (en) _card(1, red: false);
    } else if (k == LogicalKeyboardKey.digit5) {
      if (en) _card(0, red: true);
    } else if (k == LogicalKeyboardKey.digit6) {
      if (en) _card(1, red: true);
    } else if (k == LogicalKeyboardKey.digit7) {
      if (en) _sub(0);
    } else if (k == LogicalKeyboardKey.digit8) {
      if (en) _sub(1);
    } else if (k == LogicalKeyboardKey.space) {
      _toggleClock();
    } else if (k == LogicalKeyboardKey.keyN) {
      _primary();
    } else if (k == LogicalKeyboardKey.keyV) {
      if (en) _varCheck();
    } else if (k == LogicalKeyboardKey.keyU || k == LogicalKeyboardKey.backspace) {
      _undo();
    } else if (k == LogicalKeyboardKey.keyL) {
      _showLeague();
    } else if (k == LogicalKeyboardKey.keyH) {
      setState(() => _tvControls = !_tvControls);
    } else if (k == LogicalKeyboardKey.f11 || k == LogicalKeyboardKey.keyF) {
      FullScreen.I.toggle();
    } else if (k == LogicalKeyboardKey.escape) {
      _exitTv();
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  Widget _tvBody() {
    return Focus(
      focusNode: _tvFocus,
      autofocus: true,
      onKeyEvent: _onKey,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: _tvFocus.requestFocus,
        child: FootballTvBoard(
          m: m,
          cardA: _teamCard(0),
          cardB: _teamCard(1),
          showControls: _tvControls,
          running: running,
          act: FootballTvActions(
            goal: (t) => _goal(t),
            penalty: (t) => _penalty(t),
            yellow: (t) => _card(t, red: false),
            red: (t) => _card(t, red: true),
            sub: (t) => _sub(t),
            primary: _primary,
            alt: _toShootout,
            toggleClock: _toggleClock,
            addedTime: _addedTime,
            undo: _undo,
            varCheck: _varCheck,
            league: _showLeague,
            editLeague: _editLeague,
            teams: _showBoth,
            winner: _announceWinner,
            fullScreen: FullScreen.I.toggle,
            exit: _exitTv,
            toggleControls: () => setState(() => _tvControls = !_tvControls),
          ),
        ),
      ),
    );
  }

  // ======================================================================= UI

  List<Widget> _barActions() => [
        ...displayActions(context),
        IconButton(tooltip: 'TV scoreboard', icon: const Icon(Icons.tv), onPressed: _enterTv),
        PopupMenuButton<String>(
          onSelected: (v) {
            switch (v) {
              case 'winner':
                _announceWinner();
                break;
              case 'league':
                _showLeague();
                break;
              case 'editleague':
                _editLeague();
                break;
              case 'teams':
                _showBoth();
                break;
              case 'setup':
                _setup();
                break;
              case 'potm':
                _potm();
                break;
              case 'all':
                setState(() => _showAll = !_showAll);
                break;
              case 'xlsx':
                exportMatch(context, m);
                break;
              case 'pdf':
                _pdf();
                break;
              case 'copy':
                _copy();
                break;
            }
          },
          itemBuilder: (_) => [
            if (m.finished && m.winnerIdx >= 0)
              const PopupMenuItem(value: 'winner', child: Text('Show winner')),
            const PopupMenuItem(value: 'league', child: Text('Show league name')),
            const PopupMenuItem(value: 'editleague', child: Text('Edit league name')),
            if (m.preMatch) ...[
              const PopupMenuItem(value: 'teams', child: Text('Show both teams')),
              const PopupMenuItem(value: 'setup', child: Text('Match setup & line-ups')),
            ],
            if (m.finished) const PopupMenuItem(value: 'potm', child: Text('Player of the match')),
            PopupMenuItem(
              value: 'all',
              child: Text(_showAll ? 'Hide stat events in timeline' : 'Show all events in timeline'),
            ),
            const PopupMenuItem(value: 'xlsx', child: Text('Export Excel (.xlsx)')),
            const PopupMenuItem(value: 'pdf', child: Text('Export PDF / Print')),
            const PopupMenuItem(value: 'copy', child: Text('Copy match report')),
          ],
        ),
      ];

  Widget _floatBar() => Theme(
        data: Theme.of(context).copyWith(
          iconButtonTheme: IconButtonThemeData(
            style: IconButton.styleFrom(foregroundColor: Colors.white),
          ),
        ),
        child: Material(
          color: Colors.black.withAlpha(150),
          borderRadius: BorderRadius.circular(28),
          child: IconTheme(
            data: const IconThemeData(color: Colors.white),
            child: Row(mainAxisSize: MainAxisSize.min, children: _barActions()),
          ),
        ),
      );

  Widget _fsFrame(Widget child) {
    final showBar = !_tv && FullScreen.I.on;
    return Focus(
      autofocus: !_tv,
      onKeyEvent: (n, e) {
        if (_tv || e is! KeyDownEvent) return KeyEventResult.ignored;
        if (e.logicalKey == LogicalKeyboardKey.f11 ||
            (FullScreen.I.on && e.logicalKey == LogicalKeyboardKey.escape)) {
          FullScreen.I.toggle();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Stack(children: [
        Positioned.fill(child: child),
        if (showBar) Positioned(top: 6, right: 6, child: SafeArea(child: _floatBar())),
      ]),
    );
  }

  Widget _card2(Widget child, {EdgeInsets pad = const EdgeInsets.all(16), Color? border}) =>
      Container(
        width: double.infinity,
        padding: pad,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: border ?? Theme.of(context).colorScheme.outlineVariant),
        ),
        child: child,
      );

  Widget _title(String s, {IconData? icon}) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(children: [
          if (icon != null) ...[Icon(icon, size: 18), const SizedBox(width: 8)],
          Text(s.toUpperCase(),
              style: const TextStyle(fontSize: 12, letterSpacing: 3, fontWeight: FontWeight.w800)),
        ]),
      );

  // ---------------------------------------------------------------- pre-match

  Widget _preMatchCard() {
    Widget teamCol(int t) {
      final c = _teamCard(t);
      final n = m.hasLineup(t) ? '${m.starters(t).length} starters • ${m.bench(t).length} subs' : 'No line-up yet';
      return Expanded(
        child: Column(children: [
          CircleAvatar(
            radius: 32,
            backgroundColor: c.color.withAlpha(60),
            backgroundImage: c.photo != null ? FileImage(File(c.photo!)) : null,
            child: c.photo == null
                ? Text(c.captain.isEmpty ? '?' : c.captain.substring(0, 1).toUpperCase())
                : null,
          ),
          const SizedBox(height: 6),
          Text(c.team,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          Text(c.captain.isEmpty ? 'Captain: not set' : 'Captain: ${c.captain}',
              maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
          Text(n, style: const TextStyle(fontSize: 12)),
          TextButton(
            onPressed: () => _pickCaptain(t),
            child: Text(c.captain.isEmpty ? 'Set captain' : 'Change captain'),
          ),
          FilledButton.tonalIcon(
            onPressed: () => _showTeam(t),
            icon: const Icon(Icons.groups),
            label: const Text('Show team'),
          ),
        ]),
      );
    }

    return _card2(
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _title('Pre-match', icon: Icons.sports_soccer),
        Row(children: [
          const Icon(Icons.emoji_events),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              m.league.isEmpty ? 'No league name set' : m.league,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          IconButton(
            tooltip: 'Edit league name',
            icon: const Icon(Icons.edit),
            onPressed: _editLeague,
          ),
          FilledButton.tonal(onPressed: _showLeague, child: const Text('Show league')),
        ]),
        const Divider(height: 24),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [teamCol(0), teamCol(1)]),
        const SizedBox(height: 6),
        Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 8, children: [
          OutlinedButton.icon(
            onPressed: _showBoth,
            icon: const Icon(Icons.compare_arrows),
            label: const Text('Show both teams'),
          ),
          OutlinedButton.icon(
            onPressed: _setup,
            icon: const Icon(Icons.format_list_numbered),
            label: const Text('Rules & line-ups'),
          ),
        ]),
        const SizedBox(height: 8),
        Text(
          '${m.halfMinutes}-minute halves  •  ${m.maxSubs} substitutions'
          '${m.knockout ? '  •  knockout (extra time + penalties)' : ''}',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 12),
        ),
      ]),
    );
  }

  // --------------------------------------------------------------- scoreboard

  Widget _teamHead(int t) {
    final col = t == 0 ? _colA : _colB;
    return Expanded(
      child: Column(children: [
        Container(height: 4, width: 44, decoration: BoxDecoration(color: col, borderRadius: BorderRadius.circular(2))),
        const SizedBox(height: 8),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(m.teamAt(t).toUpperCase(),
              style: const TextStyle(
                  color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: 1.5)),
        ),
        const SizedBox(height: 6),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          _cardSq(const Color(0xFFFFD600)),
          const SizedBox(width: 4),
          Text('${m.yellowCards(t)}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
          const SizedBox(width: 12),
          _cardSq(const Color(0xFFE53935)),
          const SizedBox(width: 4),
          Text('${m.redCards(t)}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 6),
        for (final s in m.scorers(t).take(4))
          Text('⚽ $s',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white70, fontSize: 12)),
      ]),
    );
  }

  Widget _cardSq(Color c) => Container(
        width: 11,
        height: 15,
        decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(2)),
      );

  Widget _scoreboard() {
    final secs = m.seconds;
    final mm = (secs ~/ 60).toString().padLeft(2, '0');
    final ss = (secs % 60).toString().padLeft(2, '0');
    final over = m.stoppageSecs;
    final added = m.addedFor(m.clockPhase ? m.phase : m.activePeriod);
    final hasPoss = m.possA + m.possB > 0;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF04120C), Color(0xFF0B3A24)],
        ),
        boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 16, offset: Offset(0, 6))],
      ),
      child: Column(children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(color: Colors.white12, borderRadius: BorderRadius.circular(20)),
            child: Text(m.phaseLabel.toUpperCase(),
                style: const TextStyle(color: Colors.white, fontSize: 12, letterSpacing: 2, fontWeight: FontWeight.w700)),
          ),
          const Spacer(),
          if (m.league.isNotEmpty)
            Flexible(
              child: Text(m.league.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white54, fontSize: 12, letterSpacing: 2)),
            ),
        ]),
        const SizedBox(height: 6),
        if (m.phase >= 1 && m.phase <= 8)
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text('$mm:$ss',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 44,
                    fontWeight: FontWeight.w800,
                    fontFeatures: [FontFeature.tabularFigures()])),
          ),
        if (m.clockPhase && (over > 0 || added > 0))
          Text(
            over > 0
                ? 'Stoppage time +${over ~/ 60}:${(over % 60).toString().padLeft(2, '0')}   (announced +$added)'
                : 'Added time: +$added min',
            style: TextStyle(color: over > 0 ? const Color(0xFFFF8A80) : Colors.white70, fontSize: 12),
          ),
        const SizedBox(height: 10),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _teamHead(0),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text('${m.score(0)} - ${m.score(1)}',
                style: const TextStyle(color: Colors.white, fontSize: 60, fontWeight: FontWeight.w900)),
          ),
          _teamHead(1),
        ]),
        if (m.shootout.isNotEmpty)
          Text('Penalties ${m.shootScore(0)} - ${m.shootScore(1)}',
              style: const TextStyle(color: _gold, fontSize: 18, fontWeight: FontWeight.w800)),
        if (m.finished)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(m.result.toUpperCase(),
                textAlign: TextAlign.center,
                style: const TextStyle(color: _gold, fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: 1)),
          ),
        if (hasPoss) ...[
          const SizedBox(height: 10),
          Row(children: [
            Text('${m.possession(0)}%', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
            const SizedBox(width: 8),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  minHeight: 8,
                  value: m.possession(0) / 100,
                  backgroundColor: _colB,
                  valueColor: const AlwaysStoppedAnimation(_colA),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text('${m.possession(1)}%', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
          ]),
        ],
      ]),
    );
  }

  // ----------------------------------------------------------------- controls

  Widget _controls() {
    final primaryOn = m.phase != 10;
    return Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 8, children: [
      FilledButton.icon(
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
          textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
        ),
        onPressed: primaryOn ? _primary : null,
        icon: const Icon(Icons.skip_next),
        label: Text(m.phase == 10 ? 'Match finished' : m.primaryLabel),
      ),
      if (m.altLabel != null)
        FilledButton.tonalIcon(
          onPressed: _toShootout,
          icon: const Icon(Icons.sports_score),
          label: Text(m.altLabel!),
        ),
      if (m.clockPhase)
        OutlinedButton.icon(
          onPressed: _toggleClock,
          icon: Icon(running ? Icons.pause : Icons.play_arrow),
          label: Text(running ? 'Pause clock' : 'Start / resume clock'),
        ),
      if (m.clockPhase)
        OutlinedButton.icon(
          onPressed: _addedTime,
          icon: const Icon(Icons.more_time),
          label: const Text('Added time'),
        ),
      if (m.phase >= 1 && m.phase <= 8)
        OutlinedButton.icon(
          onPressed: _varCheck,
          icon: const Icon(Icons.tv),
          label: const Text('VAR'),
        ),
      OutlinedButton.icon(
        onPressed: (m.finished || m.preMatch) ? null : _undo,
        icon: const Icon(Icons.undo),
        label: const Text('Undo'),
      ),
      if (m.finished && m.winnerIdx >= 0)
        FilledButton.tonalIcon(
          onPressed: _announceWinner,
          icon: const Icon(Icons.emoji_events),
          label: const Text('Show winner'),
        ),
    ]);
  }

  Widget _possession() {
    if (!m.clockPhase) return const SizedBox.shrink();
    return _card2(
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _title('Ball possession', icon: Icons.sports_soccer),
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<int>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(value: 0, label: Text(m.teamA, maxLines: 1, overflow: TextOverflow.ellipsis)),
              const ButtonSegment(value: -1, label: Text('Neutral')),
              ButtonSegment(value: 1, label: Text(m.teamB, maxLines: 1, overflow: TextOverflow.ellipsis)),
            ],
            selected: {_poss},
            onSelectionChanged: (s) => setState(() => _poss = s.first),
          ),
        ),
      ]),
      pad: const EdgeInsets.all(12),
    );
  }

  // -------------------------------------------------------------- team panels

  Widget _teamPanel(int t) {
    final col = t == 0 ? _colA : _colB;
    final en = m.phase >= 1 && m.phase <= 8;
    final clock = m.clockPhase;
    Widget b(String label, IconData icon, VoidCallback? f, {Color? color}) =>
        FilledButton.tonalIcon(
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            backgroundColor: color,
          ),
          onPressed: f,
          icon: Icon(icon, size: 18),
          label: Text(label),
        );
    Widget group(String label, List<Widget> kids) => Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: const TextStyle(fontSize: 11, letterSpacing: 2, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 6, children: kids),
          ]),
        );
    final warn = m.hasLineup(t) && m.onPitchCount(t) < 7;
    return _card2(
      border: col.withAlpha(180),
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(width: 6, height: 28, decoration: BoxDecoration(color: col, borderRadius: BorderRadius.circular(3))),
          const SizedBox(width: 10),
          Expanded(
            child: Text(m.teamAt(t),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          ),
          Text('On pitch ${m.onPitchCount(t)}  •  Subs ${m.subsUsed(t)}/${m.subsAllowed}',
              style: TextStyle(fontSize: 12, color: warn ? Colors.red : null, fontWeight: FontWeight.w600)),
        ]),
        group('SCORING', [
          b('Goal', Icons.sports_soccer, en && clock ? () => _goal(t) : null),
          b('Penalty', Icons.gps_fixed, en && clock ? () => _penalty(t) : null),
          b('Own goal', Icons.replay, en && clock ? () => _goal(t, own: true) : null),
        ]),
        group('DISCIPLINE', [
          b('Yellow card', Icons.square, en ? () => _card(t, red: false) : null,
              color: const Color(0xFFFFE082)),
          b('Red card', Icons.square, en ? () => _card(t, red: true) : null,
              color: const Color(0xFFEF9A9A)),
        ]),
        group('CHANGES', [
          b('Substitution', Icons.swap_horiz, en ? () => _sub(t) : null),
          b('Injury', Icons.healing, en ? () => _injury(t) : null),
        ]),
        group('MATCH STATS', [
          b('Shot', Icons.my_location, en ? () => _quick('shot', t) : null),
          b('On target', Icons.adjust, en ? () => _quick('sot', t) : null),
          b('Corner', Icons.flag, en ? () => _quick('corner', t) : null),
          b('Foul', Icons.front_hand, en ? () => _quick('foul', t) : null),
          b('Offside', Icons.block, en ? () => _quick('offside', t) : null),
        ]),
      ]),
    );
  }

  Widget _teamPanels() => LayoutBuilder(
        builder: (context, box) => box.maxWidth > 760
            ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: _teamPanel(0)),
                const SizedBox(width: 12),
                Expanded(child: _teamPanel(1)),
              ])
            : Column(children: [_teamPanel(0), const SizedBox(height: 12), _teamPanel(1)]),
      );

  // ---------------------------------------------------------------- warnings

  Widget _warnings() {
    final msgs = <String>[];
    for (var t = 0; t < 2; t++) {
      if (m.hasLineup(t) && m.onPitchCount(t) < 7 && !m.preMatch) {
        msgs.add('${m.teamAt(t)} has fewer than 7 players – the match must be abandoned.');
      }
    }
    if (msgs.isEmpty) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.red.shade700, borderRadius: BorderRadius.circular(12)),
      child: Text(msgs.join('\n'),
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
    );
  }

  // --------------------------------------------------------------- shootout

  Widget _shootoutPanel() {
    if (m.phase != 9 && m.shootout.isEmpty) return const SizedBox.shrink();
    Widget dots(int t) => Wrap(spacing: 4, children: [
          for (final k in m.shootout.where((k) => k.team == t))
            Tooltip(
              message: k.player,
              child: Icon(k.scored ? Icons.check_circle : Icons.cancel,
                  color: k.scored ? Colors.green : Colors.red, size: 26),
            ),
        ]);
    return _card2(
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _title('Penalty shootout', icon: Icons.sports_score),
        Center(
          child: Text('${m.shootScore(0)}  -  ${m.shootScore(1)}',
              style: const TextStyle(fontSize: 40, fontWeight: FontWeight.w900)),
        ),
        if (m.shootout.isEmpty && m.phase == 9)
          Center(
            child: SegmentedButton<int>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(value: 0, label: Text('${m.teamA} kicks first')),
                ButtonSegment(value: 1, label: Text('${m.teamB} kicks first')),
              ],
              selected: {m.shootFirst},
              onSelectionChanged: (s) => _do(() => m.shootFirst = s.first),
            ),
          ),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(m.teamA, style: const TextStyle(fontWeight: FontWeight.w700)), dots(0)])),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(m.teamB, style: const TextStyle(fontWeight: FontWeight.w700)), dots(1)])),
        ]),
        const SizedBox(height: 10),
        if (m.phase == 9 && !m.shootDecided)
          Center(
            child: FilledButton.icon(
              onPressed: _shootKick,
              icon: const Icon(Icons.sports_soccer),
              label: Text('Next kick: ${m.teamAt(m.nextShooter)}'),
            ),
          ),
        if (m.shootDecided)
          Center(
            child: Text('${m.teamAt(m.shootWinner)} win the shootout',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          ),
      ]),
    );
  }

  // ------------------------------------------------------------------- stats

  Widget _statRow(String label, num a, num b, {String suffix = ''}) {
    final tot = (a + b) == 0 ? 1 : (a + b);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Column(children: [
        Row(children: [
          Text('$a$suffix', style: const TextStyle(fontWeight: FontWeight.w800)),
          Expanded(child: Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12))),
          Text('$b$suffix', style: const TextStyle(fontWeight: FontWeight.w800)),
        ]),
        const SizedBox(height: 3),
        Row(children: [
          Expanded(
            flex: (a * 100 / tot).round().clamp(0, 100).toInt() + 1,
            child: Container(height: 6, decoration: BoxDecoration(color: _colA, borderRadius: const BorderRadius.horizontal(left: Radius.circular(3)))),
          ),
          const SizedBox(width: 3),
          Expanded(
            flex: (b * 100 / tot).round().clamp(0, 100).toInt() + 1,
            child: Container(height: 6, decoration: BoxDecoration(color: _colB, borderRadius: const BorderRadius.horizontal(right: Radius.circular(3)))),
          ),
        ]),
      ]),
    );
  }

  Widget _statsCard() => _card2(
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _title('Match statistics', icon: Icons.bar_chart),
          Row(children: [
            Expanded(child: Text(m.teamA, style: const TextStyle(fontWeight: FontWeight.w800))),
            Text(m.teamB, style: const TextStyle(fontWeight: FontWeight.w800)),
          ]),
          _statRow('Goals', m.score(0), m.score(1)),
          _statRow('Shots', m.shots(0), m.shots(1)),
          _statRow('On target', m.count('sot', 0), m.count('sot', 1)),
          _statRow('Corners', m.count('corner', 0), m.count('corner', 1)),
          _statRow('Fouls', m.count('foul', 0), m.count('foul', 1)),
          _statRow('Offsides', m.count('offside', 0), m.count('offside', 1)),
          _statRow('Yellow cards', m.yellowCards(0), m.yellowCards(1)),
          _statRow('Red cards', m.redCards(0), m.redCards(1)),
          _statRow('Substitutions', m.subsUsed(0), m.subsUsed(1)),
          if (m.possA + m.possB > 0) _statRow('Possession', m.possession(0), m.possession(1), suffix: '%'),
        ]),
      );

  // ---------------------------------------------------------------- timeline

  Widget _timeline() {
    final list = m.events
        .where((e) => _showAll || FootballMatch.keyTypes.contains(e.type))
        .toList()
        .reversed
        .toList();
    return _card2(
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _title('Timeline', icon: Icons.timeline),
        if (list.isEmpty) const Padding(padding: EdgeInsets.all(8), child: Text('No events yet')),
        for (final e in list)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Container(
              width: 54,
              padding: const EdgeInsets.symmetric(vertical: 4),
              decoration: BoxDecoration(
                color: (e.team == 0 ? _colA : _colB).withAlpha(60),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text("${m.labelFor(e)}'",
                  textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w800)),
            ),
            title: Text(
              m.describe(e),
              style: TextStyle(decoration: e.cancelled ? TextDecoration.lineThrough : null),
            ),
            subtitle: Text(e.type == 'var' ? '' : m.teamAt(e.team)),
            trailing: PopupMenuButton<String>(
              onSelected: (v) {
                if (v == 'del') {
                  _do(() => m.events.remove(e));
                } else if (v == 'cancel') {
                  _do(() => e.cancelled = !e.cancelled);
                }
              },
              itemBuilder: (_) => [
                if (e.type == 'goal' || e.type == 'owngoal')
                  PopupMenuItem(
                    value: 'cancel',
                    child: Text(e.cancelled ? 'Restore goal' : 'Disallow goal (VAR)'),
                  ),
                const PopupMenuItem(value: 'del', child: Text('Delete event')),
              ],
            ),
          ),
      ]),
    );
  }

  // ----------------------------------------------------------------- lineups

  Widget _lineups() {
    if (!m.hasLineup(0) && !m.hasLineup(1)) return const SizedBox.shrink();
    Widget col(int t) => Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(m.teamAt(t), style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            for (final p in m.starters(t))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 1),
                child: Text('$p${m.badges(t, p)}',
                    style: TextStyle(
                      fontSize: 13,
                      decoration: (m.sentOff(t).contains(p) || m.subbedOff(t).contains(p))
                          ? TextDecoration.lineThrough
                          : null,
                    )),
              ),
            const SizedBox(height: 6),
            const Text('Substitutes', style: TextStyle(fontSize: 11, letterSpacing: 2)),
            for (final p in m.bench(t))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 1),
                child: Text('$p${m.badges(t, p)}', style: const TextStyle(fontSize: 13)),
              ),
          ]),
        );
    return _card2(
      Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: const Text('LINE-UPS',
              style: TextStyle(fontSize: 12, letterSpacing: 3, fontWeight: FontWeight.w800)),
          children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [col(0), col(1)]),
          ],
        ),
      ),
      pad: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    );
  }

  // ------------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: (_tv || FullScreen.I.on)
          ? null
          : AppBar(
              title: Text('${m.teamA} vs ${m.teamB}'),
              actions: _barActions(),
            ),
      body: _fsFrame(
        EventOverlay(
          key: _fx,
          child: _tv
              ? _tvBody()
              : Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: FullScreen.I.on ? 1100 : 900),
                    child: ListView(padding: const EdgeInsets.all(14), children: [
                      if (m.preMatch) ...[_preMatchCard(), const SizedBox(height: 12)],
                      _warnings(),
                      _scoreboard(),
                      const SizedBox(height: 12),
                      _controls(),
                      const SizedBox(height: 12),
                      _possession(),
                      if (m.clockPhase) const SizedBox(height: 12),
                      _teamPanels(),
                      const SizedBox(height: 12),
                      _shootoutPanel(),
                      if (m.phase == 9 || m.shootout.isNotEmpty) const SizedBox(height: 12),
                      if (!m.preMatch) ...[_statsCard(), const SizedBox(height: 12)],
                      _timeline(),
                      const SizedBox(height: 12),
                      _lineups(),
                      const SizedBox(height: 24),
                    ]),
                  ),
                ),
        ),
      ),
    );
  }
}
