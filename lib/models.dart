import 'dart:math';

String _p(Object v, int w) => v.toString().padLeft(w);

abstract class SportMatch {
  String id;
  String teamA;
  String teamB;
  DateTime date;
  SportMatch(this.id, this.teamA, this.teamB, this.date);
  String get sport;
  String get summary;
  Map<String, dynamic> toJson();

  static String newId() =>
      '${DateTime.now().microsecondsSinceEpoch}${Random().nextInt(999)}';

  static SportMatch fromJson(Map<String, dynamic> j) =>
      j['sport'] == 'cricket' ? CricketMatch.fromJson(j) : FootballMatch.fromJson(j);
}

// ---------------- CRICKET ----------------

class Ball {
  int runs; // off the bat, or wide/no-ball/bye/leg-bye runs
  String? extra; // 'wd', 'nb', 'b', 'lb' or null
  bool wicket;
  String? wkType; // bowled, caught, lbw, stumped, hit wicket, run out
  String? out; // dismissed batter
  // state BEFORE the ball (used for stats and undo)
  String? batter, nonStriker, bowler;

  Ball({
    this.runs = 0,
    this.extra,
    this.wicket = false,
    this.wkType,
    this.out,
    this.batter,
    this.nonStriker,
    this.bowler,
  });

  bool get legal => extra != 'wd' && extra != 'nb';
  bool get penalty => extra == 'wd' || extra == 'nb';
  int get total => runs + (penalty ? 1 : 0);
  int get batterRuns => (extra == null || extra == 'nb') ? runs : 0;
  bool get facedByBatter => extra != 'wd';
  int get bowlerRuns => (extra == 'b' || extra == 'lb') ? 0 : total;
  bool get bowlerWicket => wicket && wkType != 'run out';
  int get extraRuns {
    switch (extra) {
      case 'wd':
        return 1 + runs;
      case 'nb':
        return 1;
      case 'b':
      case 'lb':
        return runs;
    }
    return 0;
  }

  Map<String, dynamic> toJson() => {
        'r': runs, 'e': extra, 'w': wicket, 'wt': wkType, 'o': out,
        'b': batter, 'n': nonStriker, 'bw': bowler,
      };
  factory Ball.fromJson(Map<String, dynamic> j) => Ball(
        runs: j['r'], extra: j['e'], wicket: j['w'], wkType: j['wt'], out: j['o'],
        batter: j['b'], nonStriker: j['n'], bowler: j['bw'],
      );

  String get label {
    if (extra == 'wd') return runs > 0 ? 'Wd+$runs' : 'Wd';
    if (extra == 'nb') return runs > 0 ? 'Nb+$runs' : 'Nb';
    if (extra == 'b') return 'B$runs';
    if (extra == 'lb') return 'Lb$runs';
    if (wicket) return runs > 0 ? 'W+$runs' : 'W';
    return '$runs';
  }
}

class BatStat {
  final String name;
  int runs = 0, balls = 0, fours = 0, sixes = 0;
  String? how;
  BatStat(this.name);
  bool get out => how != null;
  double get sr => balls == 0 ? 0 : runs * 100 / balls;
}

class BowlStat {
  final String name;
  int balls = 0, runs = 0, wkts = 0;
  BowlStat(this.name);
  String get overs => '${balls ~/ 6}.${balls % 6}';
  double get econ => balls == 0 ? 0 : runs * 6 / balls;
}

/// A batter who retired hurt and was replaced at the crease.
class Retirement {
  final String name; // who retired
  final String replacement; // who came in
  final int atBall; // balls bowled in the innings when it happened
  final bool wasStriker;
  Retirement(this.name, this.replacement, this.atBall, this.wasStriker);

  Map<String, dynamic> toJson() => {'n': name, 'r': replacement, 'a': atBall, 's': wasStriker};
  factory Retirement.fromJson(Map<String, dynamic> j) =>
      Retirement(j['n'], j['r'], j['a'], j['s']);
}

/// A strategic timeout taken during an innings.
class TimeoutRec {
  final int atLegal; // legal balls bowled when it was taken
  final String by;
  final int seconds;
  TimeoutRec(this.atLegal, this.by, this.seconds);
  String get overLabel => '${atLegal ~/ 6}.${atLegal % 6}';

  Map<String, dynamic> toJson() => {'a': atLegal, 'b': by, 's': seconds};
  factory TimeoutRec.fromJson(Map<String, dynamic> j) => TimeoutRec(j['a'], j['b'], j['s']);
}

class Innings {
  List<Ball> balls;
  String? striker, nonStriker, bowler;
  List<Retirement> retired;
  List<TimeoutRec> timeouts;

  Innings({
    List<Ball>? balls,
    this.striker,
    this.nonStriker,
    this.bowler,
    List<Retirement>? retired,
    List<TimeoutRec>? timeouts,
  })  : balls = balls ?? [],
        retired = retired ?? [],
        timeouts = timeouts ?? [];

  /// Retire the striker (or non-striker) hurt and bring in [replacement].
  void retire(bool strikerOut, String replacement) {
    final name = strikerOut ? striker : nonStriker;
    if (name == null) return;
    retired.add(Retirement(name, replacement, balls.length, strikerOut));
    if (strikerOut) {
      striker = replacement;
    } else {
      nonStriker = replacement;
    }
  }

  bool _undoRetire() {
    if (retired.isEmpty || retired.last.atBall < balls.length) return false;
    final r = retired.removeLast();
    if (r.wasStriker) {
      striker = r.name;
    } else {
      nonStriker = r.name;
    }
    return true;
  }

  int get runs => balls.fold(0, (s, b) => s + b.total);
  int get wickets => balls.where((b) => b.wicket).length;
  int get legalBalls => balls.where((b) => b.legal).length;
  String get overs => '${legalBalls ~/ 6}.${legalBalls % 6}';
  double get runRate => legalBalls == 0 ? 0 : runs * 6 / legalBalls;
  int get extras => balls.fold(0, (s, b) => s + b.extraRuns);
  bool get needsPlayers => striker == null || nonStriker == null || bowler == null;

  List<Ball> get currentOver {
    int done = (legalBalls ~/ 6) * 6;
    if (legalBalls > 0 && legalBalls % 6 == 0 && balls.isNotEmpty && balls.last.legal) {
      done -= 6;
    }
    final out = <Ball>[];
    int seen = 0;
    for (final b in balls) {
      if (seen >= done) out.add(b);
      if (b.legal) seen++;
    }
    return out;
  }

  void _swap() {
    final t = striker;
    striker = nonStriker;
    nonStriker = t;
  }

  void add(Ball b) {
    b.batter = striker;
    b.nonStriker = nonStriker;
    b.bowler = bowler;
    if (b.wicket && b.out == null) b.out = striker;
    balls.add(b);
    if (b.wicket) {
      // runs completed before a run out: odd runs mean the batters crossed
      if (b.runs.isOdd) _swap();
      if (b.out == striker) {
        striker = null;
      } else {
        nonStriker = null;
      }
    } else if (b.runs.isOdd) {
      _swap();
    }
    if (b.legal && legalBalls % 6 == 0) {
      _swap();
      bowler = null;
    }
  }

  void undo() {
    if (_undoRetire()) return;
    if (balls.isEmpty) return;
    final b = balls.removeLast();
    striker = b.batter;
    nonStriker = b.nonStriker;
    bowler = b.bowler;
  }

  List<String> get bowlerNames {
    final s = <String>[];
    for (final b in balls) {
      if (b.bowler != null && !s.contains(b.bowler)) s.add(b.bowler!);
    }
    return s;
  }

  List<BatStat> get batting {
    final map = <String, BatStat>{};
    BatStat s(String n) => map.putIfAbsent(n, () => BatStat(n));
    final away = <String>{}; // retired hurt and not back at the crease
    var ri = 0;
    void applyRetirements(int upTo) {
      while (ri < retired.length && retired[ri].atBall <= upTo) {
        final r = retired[ri++];
        s(r.name);
        away.add(r.name);
      }
    }

    for (var bi = 0; bi < balls.length; bi++) {
      applyRetirements(bi);
      final b = balls[bi];
      away.remove(b.batter);
      away.remove(b.nonStriker);
      final st = s(b.batter ?? 'Unknown');
      if (b.nonStriker != null) s(b.nonStriker!);
      st.runs += b.batterRuns;
      if (b.facedByBatter) st.balls++;
      if (b.extra == null || b.extra == 'nb') {
        if (b.runs == 4) st.fours++;
        if (b.runs == 6) st.sixes++;
      }
      if (b.wicket) s(b.out ?? 'Unknown').how = b.wkType ?? 'out';
    }
    applyRetirements(balls.length);
    if (striker != null) {
      s(striker!);
      away.remove(striker);
    }
    if (nonStriker != null) {
      s(nonStriker!);
      away.remove(nonStriker);
    }
    for (final n in away) {
      final st = map[n];
      if (st != null && st.how == null) st.how = 'retired hurt';
    }
    return map.values.toList();
  }

  List<BowlStat> get bowling {
    final map = <String, BowlStat>{};
    for (final b in balls) {
      final st = map.putIfAbsent(b.bowler ?? 'Unknown', () => BowlStat(b.bowler ?? 'Unknown'));
      if (b.legal) st.balls++;
      st.runs += b.bowlerRuns;
      if (b.bowlerWicket) st.wkts++;
    }
    return map.values.toList();
  }

  Map<String, dynamic> toJson() => {
        'balls': balls.map((b) => b.toJson()).toList(),
        's': striker, 'n': nonStriker, 'bw': bowler,
        'ret': retired.map((r) => r.toJson()).toList(),
        'to': timeouts.map((t) => t.toJson()).toList(),
      };
  factory Innings.fromJson(Map<String, dynamic> j) => Innings(
        balls: (j['balls'] as List).map((b) => Ball.fromJson(Map<String, dynamic>.from(b))).toList(),
        striker: j['s'], nonStriker: j['n'], bowler: j['bw'],
        retired: ((j['ret'] ?? []) as List)
            .map((r) => Retirement.fromJson(Map<String, dynamic>.from(r)))
            .toList(),
        timeouts: ((j['to'] ?? []) as List)
            .map((t) => TimeoutRec.fromJson(Map<String, dynamic>.from(t)))
            .toList(),
      );
}

class CricketMatch extends SportMatch {
  int overs;
  List<Innings> innings;
  int current; // 0 or 1
  bool finished;
  List<String> playersA, playersB;
  String league; // tournament / premier league name
  String captainA, captainB;
  int tossWinner; // -1 = toss not done, 0 = teamA, 1 = teamB
  String tossDecision; // '', 'bat' or 'field'
  int batFirst; // 0 = teamA bats first, 1 = teamB bats first

  CricketMatch({
    required String id,
    required String teamA,
    required String teamB,
    required this.overs,
    DateTime? date,
    List<Innings>? innings,
    this.current = 0,
    this.finished = false,
    List<String>? playersA,
    List<String>? playersB,
    this.league = '',
    this.captainA = '',
    this.captainB = '',
    this.tossWinner = -1,
    this.tossDecision = '',
    this.batFirst = 0,
  })  : innings = innings ?? [Innings(), Innings()],
        playersA = playersA ?? [],
        playersB = playersB ?? [],
        super(id, teamA, teamB, date ?? DateTime.now());

  @override
  String get sport => 'cricket';

  String teamAt(int idx) => idx == 0 ? teamA : teamB;

  /// Team batting in innings [k] (0 = first innings) - depends on the toss.
  String inningsTeam(int k) => teamAt(k == 0 ? batFirst : 1 - batFirst);
  String get battingTeam => inningsTeam(current);
  String get bowlingTeam => inningsTeam(1 - current);
  List<String> _squad(int idx) => idx == 0 ? playersA : playersB;
  List<String> get battingPlayers => _squad(current == 0 ? batFirst : 1 - batFirst);
  List<String> get bowlingPlayers => _squad(current == 0 ? 1 - batFirst : batFirst);

  /// True until the first ball (or retirement) of the match.
  bool get preMatch =>
      current == 0 && !finished && innings[0].balls.isEmpty && innings[0].retired.isEmpty;
  bool get tossDecided => tossWinner >= 0 && tossDecision.isNotEmpty;
  String get tossLine => tossDecided
      ? '${teamAt(tossWinner)} won the toss and elected to ${tossDecision == 'bat' ? 'bat' : 'field'}.'
      : '';

  void setToss(int winner, bool bat) {
    tossWinner = winner;
    tossDecision = bat ? 'bat' : 'field';
    batFirst = bat ? winner : 1 - winner;
    if (preMatch) {
      // openers / bowler must be picked again for the correct teams
      innings[0].striker = null;
      innings[0].nonStriker = null;
      innings[0].bowler = null;
    }
  }
  Innings get now => innings[current];
  int get target => innings[0].runs + 1;

  bool get inningsOver {
    if (now.wickets >= 10 || now.legalBalls >= overs * 6) return true;
    if (current == 1 && now.runs >= target) return true;
    return false;
  }

  void addBall(Ball b) {
    if (finished || inningsOver || now.needsPlayers) return;
    now.add(b);
    if (inningsOver && current == 1) finished = true;
  }

  void undo() {
    if (now.balls.isNotEmpty || now.retired.isNotEmpty) {
      now.undo();
      finished = false;
    } else if (current == 1) {
      current = 0;
      finished = false;
    }
  }

  void endInnings() {
    if (current == 0) {
      current = 1;
    } else {
      finished = true;
    }
  }

  String get result {
    if (!finished) return '';
    final a = innings[0].runs, b = innings[1].runs;
    if (b >= target) return '${inningsTeam(1)} won by ${10 - innings[1].wickets} wickets';
    if (b < a) return '${inningsTeam(0)} won by ${a - b} runs';
    return 'Match tied';
  }

  @override
  String get summary {
    final s =
        '${inningsTeam(0)} ${innings[0].runs}/${innings[0].wickets}  vs  ${inningsTeam(1)} ${innings[1].runs}/${innings[1].wickets}';
    return finished ? '$s • $result' : '$s • In progress';
  }

  /// Index (0 = teamA, 1 = teamB) of the winning team; -1 if not finished or tied.
  int get winnerIdx {
    if (!finished) return -1;
    final a = innings[0].runs, b = innings[1].runs;
    if (b >= target) return 1 - batFirst; // chasing team
    if (b < a) return batFirst; // team that batted first
    return -1;
  }

  /// "won by 6 runs" / "won by 4 wickets" ('' when there is no winner).
  String get winMargin {
    final a = innings[0].runs, b = innings[1].runs;
    if (b >= target) {
      final w = 10 - innings[1].wickets;
      return 'won by $w ${w == 1 ? 'wicket' : 'wickets'}';
    }
    if (b < a) {
      final r = a - b;
      return 'won by $r ${r == 1 ? 'run' : 'runs'}';
    }
    return '';
  }

  /// Plain ASCII scorecard (used for PDF export and copy).
  String get scorecardText {
    final sb = StringBuffer();
    if (league.isNotEmpty) sb.writeln(league);
    sb.writeln('$teamA vs $teamB  ($overs overs)');
    sb.writeln(date.toString().substring(0, 16));
    if (tossDecided) sb.writeln(tossLine);
    for (int k = 0; k < 2; k++) {
      final i = innings[k];
      if (k == 1 && current == 0 && i.balls.isEmpty) continue;
      sb.writeln();
      sb.writeln('${inningsTeam(k)}  ${i.runs}/${i.wickets}  (${i.overs} ov)');
      sb.writeln('-' * 52);
      sb.writeln('${'Batter'.padRight(16)}${_p('R', 5)}${_p('B', 5)}${_p('4s', 5)}${_p('6s', 5)}${_p('SR', 7)}');
      for (final b in i.batting) {
        final nm = (b.name + (b.out ? '' : '*')).padRight(16);
        sb.writeln('$nm${_p(b.runs, 5)}${_p(b.balls, 5)}${_p(b.fours, 5)}${_p(b.sixes, 5)}${_p(b.sr.toStringAsFixed(1), 7)}  ${b.how ?? ''}');
      }
      sb.writeln('Extras: ${i.extras}   Total: ${i.runs}/${i.wickets} (${i.overs} ov)');
      for (final t in i.timeouts) {
        sb.writeln('Strategic timeout at ${t.overLabel} ov (${t.by})');
      }
      sb.writeln();
      sb.writeln('${'Bowler'.padRight(16)}${_p('O', 6)}${_p('R', 5)}${_p('W', 4)}${_p('Econ', 7)}');
      for (final b in i.bowling) {
        sb.writeln('${b.name.padRight(16)}${_p(b.overs, 6)}${_p(b.runs, 5)}${_p(b.wkts, 4)}${_p(b.econ.toStringAsFixed(2), 7)}');
      }
    }
    if (finished) {
      sb.writeln();
      sb.writeln('Result: $result');
    }
    return sb.toString();
  }

  @override
  Map<String, dynamic> toJson() => {
        'sport': 'cricket',
        'id': id,
        'teamA': teamA,
        'teamB': teamB,
        'date': date.toIso8601String(),
        'overs': overs,
        'current': current,
        'finished': finished,
        'pA': playersA,
        'pB': playersB,
        'lg': league,
        'capA': captainA,
        'capB': captainB,
        'tw': tossWinner,
        'td': tossDecision,
        'bf': batFirst,
        'innings': innings.map((i) => i.toJson()).toList(),
      };

  factory CricketMatch.fromJson(Map<String, dynamic> j) => CricketMatch(
        id: j['id'],
        teamA: j['teamA'],
        teamB: j['teamB'],
        date: DateTime.parse(j['date']),
        overs: j['overs'],
        current: j['current'],
        finished: j['finished'],
        playersA: List<String>.from(j['pA'] ?? const []),
        playersB: List<String>.from(j['pB'] ?? const []),
        league: (j['lg'] ?? '') as String,
        captainA: (j['capA'] ?? '') as String,
        captainB: (j['capB'] ?? '') as String,
        tossWinner: (j['tw'] ?? -1) as int,
        tossDecision: (j['td'] ?? '') as String,
        batFirst: (j['bf'] ?? 0) as int,
        innings: (j['innings'] as List)
            .map((i) => Innings.fromJson(Map<String, dynamic>.from(i)))
            .toList(),
      );
}

// ---------------- FOOTBALL ----------------

/// One kick of a penalty shootout.
class PenKick {
  int team;
  String player;
  bool scored;
  String? detail;
  PenKick(this.team, this.player, this.scored, [this.detail]);

  Map<String, dynamic> toJson() => {'t': team, 'p': player, 's': scored, 'd': detail};
  factory PenKick.fromJson(Map<String, dynamic> j) =>
      PenKick(j['t'], (j['p'] ?? '') as String, j['s'], j['d']);
}

/// goal, owngoal, yellow, yellow2 (second yellow = sent off), red, sub (player = out,
/// other = in), pen_miss, var, injury, shot, sot, corner, foul, offside
class FootballEvent {
  String type;
  int team;
  String player;
  String? other; // assist / player coming on
  String? detail;
  int seconds; // match clock when it happened
  int period; // clock phase: 1 = 1st half, 3 = 2nd half, 5 / 7 = extra time
  bool cancelled; // goal disallowed by VAR
  FootballEvent(this.type, this.team, this.player, this.seconds, this.period,
      {this.other, this.detail, this.cancelled = false});

  Map<String, dynamic> toJson() => {
        't': type, 'team': team, 'p': player, 'o': other, 'd': detail,
        's': seconds, 'pe': period, 'c': cancelled,
      };

  factory FootballEvent.fromJson(Map<String, dynamic> j) {
    // older saved matches only had 'm' (minute)
    final int secs = (j['s'] ?? (((j['m'] ?? 1) as int) - 1) * 60) as int;
    return FootballEvent(j['t'], j['team'], (j['p'] ?? '') as String, secs,
        (j['pe'] ?? 1) as int,
        other: j['o'], detail: j['d'], cancelled: (j['c'] ?? false) as bool);
  }
}

class FootballMatch extends SportMatch {
  List<FootballEvent> events;
  int seconds; // match clock
  /// 0 pre-match, 1 first half, 2 half time, 3 second half, 4 full time,
  /// 5 extra time 1st half, 6 extra time break, 7 extra time 2nd half,
  /// 8 end of extra time, 9 penalty shootout, 10 finished
  int phase;
  int halfMinutes, etMinutes, maxSubs;
  bool knockout; // draw -> extra time -> penalties
  Map<int, int> added; // announced added time per clock phase (minutes)
  List<String> playersA, playersB; // squads
  List<String> startA, startB, benchA, benchB;
  List<PenKick> shootout;
  int shootFirst; // team that takes the first shootout kick
  int possA, possB; // possession seconds
  String? potm; // player of the match
  String league;
  String captainA, captainB;

  FootballMatch({
    required String id,
    required String teamA,
    required String teamB,
    DateTime? date,
    List<FootballEvent>? events,
    this.seconds = 0,
    this.phase = 0,
    this.halfMinutes = 45,
    this.etMinutes = 15,
    this.maxSubs = 5,
    this.knockout = false,
    Map<int, int>? added,
    List<String>? playersA,
    List<String>? playersB,
    List<String>? startA,
    List<String>? startB,
    List<String>? benchA,
    List<String>? benchB,
    List<PenKick>? shootout,
    this.shootFirst = 0,
    this.possA = 0,
    this.possB = 0,
    this.potm,
    this.league = '',
    this.captainA = '',
    this.captainB = '',
  })  : events = events ?? [],
        added = added ?? {},
        playersA = playersA ?? [],
        playersB = playersB ?? [],
        startA = startA ?? [],
        startB = startB ?? [],
        benchA = benchA ?? [],
        benchB = benchB ?? [],
        shootout = shootout ?? [],
        super(id, teamA, teamB, date ?? DateTime.now());

  @override
  String get sport => 'football';

  // ------------------------------------------------------------- clock / phase

  bool get finished => phase == 10;
  bool get preMatch => phase == 0;
  bool get clockPhase => phase == 1 || phase == 3 || phase == 5 || phase == 7;

  /// The clock phase an event belongs to (breaks use the period just played).
  int get activePeriod {
    const map = {0: 1, 1: 1, 2: 1, 3: 3, 4: 3, 5: 5, 6: 5, 7: 7, 8: 7, 9: 7, 10: 7};
    return map[phase] ?? 1;
  }

  int periodEndMin(int p) {
    switch (p) {
      case 1:
        return halfMinutes;
      case 3:
        return 2 * halfMinutes;
      case 5:
        return 2 * halfMinutes + etMinutes;
      default:
        return 2 * halfMinutes + 2 * etMinutes;
    }
  }

  String get phaseLabel => const [
        'Pre-match', '1st half', 'Half time', '2nd half', 'Full time',
        'Extra time – 1st half', 'Extra time – half time', 'Extra time – 2nd half',
        'End of extra time', 'Penalty shootout', 'Finished',
      ][phase];

  int addedFor(int p) => added[p] ?? 0;

  /// Seconds played beyond the scheduled end of the current half (stoppage time).
  int get stoppageSecs => clockPhase ? max(0, seconds - periodEndMin(phase) * 60) : 0;

  String labelAt(int secs, int period) {
    final minute = secs ~/ 60 + 1;
    final end = periodEndMin(period);
    return minute > end ? '$end+${minute - end}' : '$minute';
  }

  String labelFor(FootballEvent e) => labelAt(e.seconds, e.period);

  /// Moves to the next phase (kick-off, half time, second half ...).
  void advance() {
    switch (phase) {
      case 0:
        phase = 1;
        seconds = 0;
        break;
      case 1:
        phase = 2;
        break;
      case 2:
        phase = 3;
        seconds = halfMinutes * 60;
        break;
      case 3:
        phase = 4;
        break;
      case 4:
        phase = 5;
        seconds = 2 * halfMinutes * 60;
        break;
      case 5:
        phase = 6;
        break;
      case 6:
        phase = 7;
        seconds = (2 * halfMinutes + etMinutes) * 60;
        break;
      case 7:
        phase = 8;
        break;
      case 8:
        phase = 9;
        break;
      case 9:
        phase = 10;
        break;
    }
  }

  // ---------------------------------------------------------------- squads

  String teamAt(int t) => t == 0 ? teamA : teamB;
  List<String> squad(int t) => t == 0 ? playersA : playersB;
  List<String> starters(int t) => t == 0 ? startA : startB;
  List<String> bench(int t) => t == 0 ? benchA : benchB;
  bool hasLineup(int t) => starters(t).isNotEmpty;

  Iterable<FootballEvent> _ev(String type, int t) =>
      events.where((e) => e.type == type && e.team == t);

  Set<String> sentOff(int t) => events
      .where((e) => e.team == t && (e.type == 'red' || e.type == 'yellow2'))
      .map((e) => e.player)
      .toSet();
  Set<String> subbedOff(int t) => _ev('sub', t).map((e) => e.player).toSet();
  Set<String> subbedOn(int t) =>
      _ev('sub', t).map((e) => e.other ?? '').where((s) => s.isNotEmpty).toSet();

  /// Players currently on the pitch (starters + substitutes - subbed off - sent off).
  List<String> onPitch(int t) {
    final red = sentOff(t);
    if (!hasLineup(t)) return squad(t).where((p) => !red.contains(p)).toList();
    final gone = {...red, ...subbedOff(t)};
    return [...starters(t), ...subbedOn(t)].where((p) => !gone.contains(p)).toList();
  }

  List<String> benchAvailable(int t) {
    final used = subbedOn(t);
    final red = sentOff(t);
    return bench(t).where((p) => !used.contains(p) && !red.contains(p)).toList();
  }

  int onPitchCount(int t) => hasLineup(t) ? onPitch(t).length : 11 - sentOff(t).length;

  int subsUsed(int t) => _ev('sub', t).length;
  int get subsAllowed => maxSubs + (phase >= 5 ? 1 : 0); // +1 in extra time

  int yellowsOf(int t, String p) =>
      events.where((e) => e.type == 'yellow' && e.team == t && e.player == p).length;
  int goalsBy(int t, String p) => events
      .where((e) => e.type == 'goal' && !e.cancelled && e.team == t && e.player == p)
      .length;

  // ---------------------------------------------------------------- numbers

  int score(int team) => events
      .where((e) =>
          !e.cancelled &&
          ((e.type == 'goal' && e.team == team) || (e.type == 'owngoal' && e.team != team)))
      .length;

  int count(String type, int t) =>
      events.where((e) => e.type == type && e.team == t && !e.cancelled).length;
  int yellowCards(int t) => count('yellow', t) + count('yellow2', t);
  int redCards(int t) => count('red', t) + count('yellow2', t);
  int shots(int t) => count('shot', t) + count('sot', t);
  int possession(int t) {
    final tot = possA + possB;
    if (tot == 0) return 0;
    return ((t == 0 ? possA : possB) * 100 / tot).round();
  }

  // -------------------------------------------------------- penalty shootout

  int shootScore(int t) => shootout.where((k) => k.team == t && k.scored).length;
  int kicks(int t) => shootout.where((k) => k.team == t).length;
  int get nextShooter => shootout.length % 2 == 0 ? shootFirst : 1 - shootFirst;

  /// Best of five, then sudden death; ends as soon as one side cannot be caught.
  bool get shootDecided {
    if (shootout.isEmpty) return false;
    final ka = kicks(0), kb = kicks(1), sa = shootScore(0), sb = shootScore(1);
    if (ka >= 5 && kb >= 5) return ka == kb && sa != sb;
    final remA = ka < 5 ? 5 - ka : 0;
    final remB = kb < 5 ? 5 - kb : 0;
    return sa > sb + remB || sb > sa + remA;
  }

  int get shootWinner => shootDecided ? (shootScore(0) > shootScore(1) ? 0 : 1) : -1;

  /// Players who may take the next kick: on the pitch and not yet used this round.
  List<String> shootEligible(int t) {
    final pool = onPitch(t);
    if (pool.isEmpty) return [];
    final counts = {
      for (final p in pool) p: shootout.where((k) => k.team == t && k.player == p).length,
    };
    final low = counts.values.reduce(min);
    return pool.where((p) => counts[p] == low).toList();
  }

  // ----------------------------------------------------------------- result

  bool get drawn => score(0) == score(1);

  /// Label of the main "next step" button for the current phase.
  String get primaryLabel {
    switch (phase) {
      case 0:
        return 'Kick off';
      case 1:
        return 'End 1st half';
      case 2:
        return 'Start 2nd half';
      case 3:
        return 'End 2nd half';
      case 4:
        return knockout && drawn ? 'Start extra time' : 'Finish match';
      case 5:
        return 'End extra-time 1st half';
      case 6:
        return 'Start extra-time 2nd half';
      case 7:
        return 'End extra time';
      case 8:
        return knockout && drawn ? 'Go to penalties' : 'Finish match';
      case 9:
        return 'Finish match';
      default:
        return 'Finished';
    }
  }

  /// Second choice at full time of a drawn knockout match (straight to penalties).
  String? get altLabel => (phase == 4 && knockout && drawn) ? 'Go to penalties' : null;

  /// "Name 23'" lines for the goals that count for team [t] (own goals credited too).
  List<String> scorers(int t) {
    final out = <String>[];
    for (final e in events) {
      if (e.cancelled) continue;
      if (e.type == 'goal' && e.team == t) {
        final who = e.player.isEmpty ? teamAt(t) : e.player;
        out.add("$who${e.detail == 'penalty' ? ' (pen)' : ''} ${labelFor(e)}'");
      } else if (e.type == 'owngoal' && e.team != t) {
        out.add("${e.player} (OG) ${labelFor(e)}'");
      }
    }
    return out;
  }

  /// Team index (0 / 1) of the winner, -1 when drawn or not finished.
  int get winnerIdx {
    if (!finished) return -1;
    if (shootout.isNotEmpty && shootWinner >= 0) return shootWinner;
    final a = score(0), b = score(1);
    if (a > b) return 0;
    if (b > a) return 1;
    return -1;
  }

  /// "won 2-1" / "won 4-3 on penalties"
  String get winText {
    final w = winnerIdx;
    if (w < 0) return '';
    if (shootout.isNotEmpty && shootWinner >= 0) {
      return 'won ${shootScore(w)}-${shootScore(1 - w)} on penalties';
    }
    return 'won ${score(w)}-${score(1 - w)}';
  }

  String get result {
    if (!finished) return '';
    final a = score(0), b = score(1);
    final w = winnerIdx;
    if (w < 0) return 'Draw $a-$b';
    if (shootout.isNotEmpty && shootWinner >= 0) {
      return '${teamAt(w)} won ${shootScore(w)}-${shootScore(1 - w)} on penalties (after $a-$b)';
    }
    return '${teamAt(w)} won ${score(w)}-${score(1 - w)}';
  }

  @override
  String get summary {
    final pens = shootout.isNotEmpty ? ' (pens ${shootScore(0)}-${shootScore(1)})' : '';
    final s = '$teamA ${score(0)} - ${score(1)} $teamB$pens';
    return finished ? '$s • Full time' : '$s • In progress';
  }

  // ---------------------------------------------------------------- display

  static const typeNames = {
    'goal': 'Goal',
    'owngoal': 'Own goal',
    'yellow': 'Yellow card',
    'yellow2': 'Second yellow (sent off)',
    'red': 'Red card',
    'sub': 'Substitution',
    'pen_miss': 'Penalty missed',
    'var': 'VAR',
    'injury': 'Injury',
    'shot': 'Shot',
    'sot': 'Shot on target',
    'corner': 'Corner',
    'foul': 'Foul',
    'offside': 'Offside',
  };

  /// Key events shown in the timeline (stats-only events are left out).
  static const keyTypes = {
    'goal', 'owngoal', 'yellow', 'yellow2', 'red', 'sub', 'pen_miss', 'var', 'injury',
  };

  /// One-line description of an event ([plain] = no emoji, for reports).
  String describe(FootballEvent e, {bool plain = false}) {
    final other = (e.other ?? '').trim();
    String tag(String emoji, String word) => plain ? word : emoji;
    switch (e.type) {
      case 'goal':
        final pen = e.detail == 'penalty' ? ' (pen)' : '';
        final assist = other.isNotEmpty ? ' (assist $other)' : '';
        final dis = e.cancelled ? ' - disallowed' : '';
        return '${tag('⚽', 'Goal')} ${e.player}$pen$assist$dis';
      case 'owngoal':
        return '${tag('⚽', 'Goal')} ${e.player} (own goal)${e.cancelled ? ' - disallowed' : ''}';
      case 'yellow':
        return '${tag('🟨', 'Yellow card')} ${e.player}';
      case 'yellow2':
        return '${tag('🟨🟥', 'Second yellow / red')} ${e.player}';
      case 'red':
        return '${tag('🟥', 'Red card')} ${e.player}';
      case 'sub':
        return '${tag('🔁', 'Substitution')}  in: $other   out: ${e.player}';
      case 'pen_miss':
        return '${tag('❌', 'Penalty')} ${e.detail ?? 'missed'} - ${e.player}';
      case 'var':
        return '${tag('📺', 'VAR')} ${e.detail ?? ''}';
      case 'injury':
        return '${tag('🩹', 'Injury')} ${e.player}';
      default:
        return typeNames[e.type] ?? e.type;
    }
  }

  /// Small status marks next to a player in the line-up.
  String badges(int t, String p, {bool plain = false}) {
    final sb = StringBuffer();
    final g = goalsBy(t, p);
    if (g > 0) sb.write(plain ? ' G$g' : ' ⚽$g');
    if (yellowsOf(t, p) > 0) sb.write(plain ? ' Y' : ' 🟨');
    if (sentOff(t).contains(p)) sb.write(plain ? ' R' : ' 🟥');
    for (final e in _ev('sub', t)) {
      if (e.player == p) sb.write(plain ? ' off ${labelFor(e)}' : " ↓${labelFor(e)}'");
      if (e.other == p) sb.write(plain ? ' on ${labelFor(e)}' : " ↑${labelFor(e)}'");
    }
    return sb.toString();
  }

  /// Plain ASCII match report (copy / PDF).
  String get reportText {
    final sb = StringBuffer();
    if (league.isNotEmpty) sb.writeln(league);
    sb.writeln('$teamA vs $teamB');
    sb.writeln(date.toString().substring(0, 16));
    sb.writeln('$teamA ${score(0)} - ${score(1)} $teamB');
    if (shootout.isNotEmpty) sb.writeln('Penalties: ${shootScore(0)} - ${shootScore(1)}');
    sb.writeln(finished ? result : phaseLabel);
    if (potm != null && potm!.isNotEmpty) sb.writeln('Player of the match: $potm');
    sb.writeln();
    sb.writeln('EVENTS');
    for (final e in events.where((e) => keyTypes.contains(e.type))) {
      sb.writeln("${labelFor(e).padLeft(6)}'  [${teamAt(e.team)}]  ${describe(e, plain: true)}");
    }
    sb.writeln();
    sb.writeln('STATS${' ' * 22}${teamA.padRight(10).substring(0, 10)}  ${teamB.padRight(10).substring(0, 10)}');
    void row(String label, Object a, Object b) =>
        sb.writeln('${label.padRight(27)}${a.toString().padRight(12)}${b.toString()}');
    row('Goals', score(0), score(1));
    row('Shots', shots(0), shots(1));
    row('On target', count('sot', 0), count('sot', 1));
    row('Corners', count('corner', 0), count('corner', 1));
    row('Fouls', count('foul', 0), count('foul', 1));
    row('Offsides', count('offside', 0), count('offside', 1));
    row('Yellow cards', yellowCards(0), yellowCards(1));
    row('Red cards', redCards(0), redCards(1));
    row('Substitutions', subsUsed(0), subsUsed(1));
    if (possA + possB > 0) row('Possession %', possession(0), possession(1));
    for (var t = 0; t < 2; t++) {
      if (!hasLineup(t)) continue;
      sb.writeln();
      sb.writeln('${teamAt(t).toUpperCase()} LINE-UP');
      for (final p in starters(t)) {
        sb.writeln('  $p${badges(t, p, plain: true)}');
      }
      sb.writeln('  Substitutes:');
      for (final p in bench(t)) {
        sb.writeln('  $p${badges(t, p, plain: true)}');
      }
    }
    if (shootout.isNotEmpty) {
      sb.writeln();
      sb.writeln('PENALTY SHOOTOUT');
      for (var i = 0; i < shootout.length; i++) {
        final k = shootout[i];
        sb.writeln('  ${i + 1}. ${teamAt(k.team)} - ${k.player}: ${k.scored ? 'scored' : 'missed'}');
      }
    }
    return sb.toString();
  }

  // ------------------------------------------------------------------- json

  @override
  Map<String, dynamic> toJson() => {
        'sport': 'football',
        'id': id,
        'teamA': teamA,
        'teamB': teamB,
        'date': date.toIso8601String(),
        'seconds': seconds,
        'phase': phase,
        'half': halfMinutes,
        'et': etMinutes,
        'subs': maxSubs,
        'ko': knockout,
        'added': added.map((k, v) => MapEntry('$k', v)),
        'pA': playersA,
        'pB': playersB,
        'sA': startA,
        'sB': startB,
        'bA': benchA,
        'bB': benchB,
        'shoot': shootout.map((k) => k.toJson()).toList(),
        'sf': shootFirst,
        'possA': possA,
        'possB': possB,
        'potm': potm,
        'lg': league,
        'capA': captainA,
        'capB': captainB,
        'events': events.map((e) => e.toJson()).toList(),
      };

  factory FootballMatch.fromJson(Map<String, dynamic> j) {
    final events = ((j['events'] ?? []) as List)
        .map((e) => FootballEvent.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    int phase;
    if (j['phase'] != null) {
      phase = j['phase'] as int;
    } else {
      // match saved by an older version
      final fin = j['finished'] == true;
      final per = ((j['period'] ?? 1) as int).clamp(1, 4).toInt();
      final secs = (j['seconds'] ?? 0) as int;
      phase = fin ? 10 : ((secs == 0 && events.isEmpty) ? 0 : const [0, 1, 3, 5, 7][per]);
    }
    List<String> ls(String k) => List<String>.from(j[k] ?? const []);
    return FootballMatch(
      id: j['id'],
      teamA: j['teamA'],
      teamB: j['teamB'],
      date: DateTime.parse(j['date']),
      events: events,
      seconds: (j['seconds'] ?? 0) as int,
      phase: phase,
      halfMinutes: (j['half'] ?? 45) as int,
      etMinutes: (j['et'] ?? 15) as int,
      maxSubs: (j['subs'] ?? 5) as int,
      knockout: (j['ko'] ?? false) as bool,
      added: ((j['added'] ?? {}) as Map)
          .map((k, v) => MapEntry(int.parse(k.toString()), v as int)),
      playersA: ls('pA'),
      playersB: ls('pB'),
      startA: ls('sA'),
      startB: ls('sB'),
      benchA: ls('bA'),
      benchB: ls('bB'),
      shootout: ((j['shoot'] ?? []) as List)
          .map((k) => PenKick.fromJson(Map<String, dynamic>.from(k)))
          .toList(),
      shootFirst: (j['sf'] ?? 0) as int,
      possA: (j['possA'] ?? 0) as int,
      possB: (j['possB'] ?? 0) as int,
      potm: j['potm'] as String?,
      league: (j['lg'] ?? '') as String,
      captainA: (j['capA'] ?? '') as String,
      captainB: (j['capB'] ?? '') as String,
    );
  }
}
