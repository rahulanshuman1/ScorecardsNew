import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'models.dart';
import 'xlsx_writer.dart';

XCell _h(String s) => XCell(s, bold: true);

List<XSheet> cricketSheets(CricketMatch m) {
  final sheets = <XSheet>[];
  String score(Innings i) => '${i.runs}/${i.wickets} (${i.overs} ov)';

  sheets.add(XSheet('Summary', [
    [_h('Match'), XCell('${m.teamA} vs ${m.teamB}')],
    [_h('Date'), XCell(m.date.toString().substring(0, 16))],
    [_h('League'), XCell(m.league.isEmpty ? '-' : m.league)],
    [_h('Toss'), XCell(m.tossDecided ? m.tossLine : '-')],
    [_h('Overs per innings'), XCell(m.overs)],
    [_h(m.inningsTeam(0)), XCell(score(m.innings[0]))],
    [_h(m.inningsTeam(1)), XCell(score(m.innings[1]))],
    [_h('Result'), XCell(m.finished ? m.result : 'In progress')],
  ]));

  for (var k = 0; k < 2; k++) {
    final i = m.innings[k];
    if (k == 1 && m.current == 0 && i.balls.isEmpty) continue;
    final team = m.inningsTeam(k);
    sheets.add(XSheet('Innings ${k + 1} - $team', [
      [_h('$team  ${i.runs}/${i.wickets}  (${i.overs} ov)')],
      [],
      [_h('Batter'), _h('How out'), _h('Runs'), _h('Balls'), _h('4s'), _h('6s'), _h('SR')],
      for (final b in i.batting)
        [
          XCell(b.name),
          XCell(b.how ?? 'not out'),
          XCell(b.runs),
          XCell(b.balls),
          XCell(b.fours),
          XCell(b.sixes),
          XCell(double.parse(b.sr.toStringAsFixed(1))),
        ],
      [XCell('Extras'), XCell(''), XCell(i.extras)],
      [_h('Total'), XCell(''), _h('${i.runs}'), XCell('${i.wickets} wkts, ${i.overs} ov')],
      [],
      [_h('Bowler'), _h('Overs'), _h('Runs'), _h('Wickets'), _h('Econ')],
      for (final b in i.bowling)
        [
          XCell(b.name),
          XCell(b.overs),
          XCell(b.runs),
          XCell(b.wkts),
          XCell(double.parse(b.econ.toStringAsFixed(2))),
        ],
    ]));
  }

  final bb = <List<XCell>>[
    [_h('Innings'), _h('Over'), _h('Ball'), _h('Bowler'), _h('Striker'), _h('Non-striker'),
     _h('Event'), _h('Runs'), _h('Score')],
  ];
  for (var k = 0; k < 2; k++) {
    var legal = 0, total = 0, wk = 0;
    for (final b in m.innings[k].balls) {
      total += b.total;
      if (b.wicket) wk++;
      final event = b.wicket
          ? 'Wicket (${b.wkType ?? 'out'}) ${b.out ?? ''}'.trim()
          : (b.extra != null ? b.label : '${b.runs}');
      bb.add([
        XCell(k + 1),
        XCell(legal ~/ 6 + 1),
        XCell(legal % 6 + 1),
        XCell(b.bowler ?? ''),
        XCell(b.batter ?? ''),
        XCell(b.nonStriker ?? ''),
        XCell(event),
        XCell(b.total),
        XCell('$total/$wk'),
      ]);
      if (b.legal) legal++;
    }
  }
  sheets.add(XSheet('Ball by ball', bb));
  return sheets;
}

List<XSheet> footballSheets(FootballMatch m) {
  const periods = ['', '1st half', '', '2nd half', '', 'Extra time 1', '', 'Extra time 2'];
  final sheets = <XSheet>[];

  sheets.add(XSheet('Summary', [
    [_h('League'), XCell(m.league.isEmpty ? '-' : m.league)],
    [_h('Match'), XCell('${m.teamA} vs ${m.teamB}')],
    [_h('Date'), XCell(m.date.toString().substring(0, 16))],
    [_h('Score'), XCell('${m.teamA} ${m.score(0)} - ${m.score(1)} ${m.teamB}')],
    if (m.shootout.isNotEmpty)
      [_h('Penalties'), XCell('${m.shootScore(0)} - ${m.shootScore(1)}')],
    [_h('Result'), XCell(m.finished ? m.result : m.phaseLabel)],
    [_h('Half length (min)'), XCell(m.halfMinutes)],
    [_h('Substitutions allowed'), XCell(m.maxSubs)],
    [_h('Knockout'), XCell(m.knockout ? 'Yes' : 'No')],
    [_h('Player of the match'), XCell(m.potm ?? '-')],
  ]));

  sheets.add(XSheet('Statistics', [
    [_h('Statistic'), _h(m.teamA), _h(m.teamB)],
    [XCell('Goals'), XCell(m.score(0)), XCell(m.score(1))],
    [XCell('Shots'), XCell(m.shots(0)), XCell(m.shots(1))],
    [XCell('Shots on target'), XCell(m.count('sot', 0)), XCell(m.count('sot', 1))],
    [XCell('Corners'), XCell(m.count('corner', 0)), XCell(m.count('corner', 1))],
    [XCell('Fouls'), XCell(m.count('foul', 0)), XCell(m.count('foul', 1))],
    [XCell('Offsides'), XCell(m.count('offside', 0)), XCell(m.count('offside', 1))],
    [XCell('Yellow cards'), XCell(m.yellowCards(0)), XCell(m.yellowCards(1))],
    [XCell('Red cards'), XCell(m.redCards(0)), XCell(m.redCards(1))],
    [XCell('Substitutions'), XCell(m.subsUsed(0)), XCell(m.subsUsed(1))],
    if (m.possA + m.possB > 0)
      [XCell('Possession %'), XCell(m.possession(0)), XCell(m.possession(1))],
  ]));

  final lineRows = <List<XCell>>[
    [_h('Team'), _h('Role'), _h('Player'), _h('Goals'), _h('Cards / changes')],
  ];
  for (var t = 0; t < 2; t++) {
    for (final p in m.starters(t)) {
      lineRows.add([XCell(m.teamAt(t)), XCell('Starter'), XCell(p), XCell(m.goalsBy(t, p)),
          XCell(m.badges(t, p, plain: true).trim())]);
    }
    for (final p in m.bench(t)) {
      lineRows.add([XCell(m.teamAt(t)), XCell('Substitute'), XCell(p), XCell(m.goalsBy(t, p)),
          XCell(m.badges(t, p, plain: true).trim())]);
    }
  }
  sheets.add(XSheet('Line-ups', lineRows));

  sheets.add(XSheet('Events', [
    [_h('Minute'), _h('Period'), _h('Team'), _h('Event'), _h('Player'), _h('Assist / player on'), _h('Notes')],
    for (final e in m.events)
      [
        XCell("${m.labelFor(e)}'"),
        XCell(periods[e.period.clamp(0, 7).toInt()]),
        XCell(e.type == 'var' ? '-' : m.teamAt(e.team)),
        XCell(FootballMatch.typeNames[e.type] ?? e.type),
        XCell(e.player),
        XCell(e.other ?? ''),
        XCell(e.cancelled ? 'Disallowed' : (e.detail ?? '')),
      ],
  ]));

  if (m.shootout.isNotEmpty) {
    sheets.add(XSheet('Shootout', [
      [_h('#'), _h('Team'), _h('Player'), _h('Result')],
      for (var i = 0; i < m.shootout.length; i++)
        [
          XCell(i + 1),
          XCell(m.teamAt(m.shootout[i].team)),
          XCell(m.shootout[i].player),
          XCell(m.shootout[i].scored ? 'Scored' : (m.shootout[i].detail ?? 'Missed')),
        ],
    ]));
  }
  return sheets;
}

Future<void> exportMatch(BuildContext context, SportMatch m) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    final sheets = m is CricketMatch ? cricketSheets(m) : footballSheets(m as FootballMatch);
    final bytes = Uint8List.fromList(buildXlsx(sheets));
    final base = '${m.teamA}_vs_${m.teamB}'.replaceAll(RegExp(r'[^A-Za-z0-9_\-]+'), '_');
    var path = await FilePicker.platform.saveFile(
      dialogTitle: 'Save scorecard',
      fileName: '$base.xlsx',
      type: FileType.custom,
      allowedExtensions: ['xlsx'],
      bytes: bytes,
    );
    if (path == null) return;
    if (!Platform.isAndroid && !Platform.isIOS) {
      if (!path.toLowerCase().endsWith('.xlsx')) path = '$path.xlsx';
      await File(path).writeAsBytes(bytes);
    }
    messenger.showSnackBar(const SnackBar(content: Text('Scorecard saved as Excel file')));
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('Export failed: $e')));
  }
}
