import 'package:flutter/material.dart';
import 'app_state.dart';
import 'models.dart';

/// Match rules + lineups (starting XI, bench, captain) for a football match.
class FootballSetupScreen extends StatefulWidget {
  final FootballMatch match;
  final VoidCallback onChanged;
  const FootballSetupScreen({super.key, required this.match, required this.onChanged});
  @override
  State<FootballSetupScreen> createState() => _FootballSetupScreenState();
}

class _FootballSetupScreenState extends State<FootballSetupScreen> {
  FootballMatch get m => widget.match;

  late final TextEditingController _half = TextEditingController(text: '${m.halfMinutes}');
  late final TextEditingController _et = TextEditingController(text: '${m.etMinutes}');
  late final TextEditingController _subs = TextEditingController(text: '${m.maxSubs}');
  late final TextEditingController _league = TextEditingController(
      text: m.league.isNotEmpty ? m.league : AppState.I.leagueName);
  late bool _knockout = m.knockout;
  late final List<List<String>> _squad = [List.of(m.playersA), List.of(m.playersB)];
  late final List<Map<String, int>> _st = [_initStatus(0), _initStatus(1)];
  late final List<String> _cap = [_initCap(0), _initCap(1)];

  Map<String, int> _initStatus(int t) {
    final squad = t == 0 ? m.playersA : m.playersB;
    final res = <String, int>{};
    if (m.hasLineup(t)) {
      for (final p in squad) {
        res[p] = m.starters(t).contains(p) ? 1 : (m.bench(t).contains(p) ? 2 : 0);
      }
    } else {
      for (var i = 0; i < squad.length; i++) {
        res[squad[i]] = i < 11 ? 1 : 2;
      }
    }
    return res;
  }

  String _initCap(int t) {
    final c = t == 0 ? m.captainA : m.captainB;
    if (c.isNotEmpty) return c;
    return AppState.I.captains[m.teamAt(t)] ?? '';
  }

  int _n(int t, int s) => _st[t].values.where((v) => v == s).length;

  void _snack(String s) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));

  Future<void> _addPlayer(int t) async {
    final c = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Add player – ${m.teamAt(t)}'),
        content: TextField(
          controller: c,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Player name'),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('Add')),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    if (_squad[t].contains(name)) {
      _snack('$name is already in the squad');
      return;
    }
    setState(() {
      _squad[t].add(name);
      _st[t][name] = 2;
    });
  }

  void _auto(int t) {
    setState(() {
      for (var i = 0; i < _squad[t].length; i++) {
        _st[t][_squad[t][i]] = i < 11 ? 1 : 2;
      }
    });
  }

  void _save() {
    final half = int.tryParse(_half.text.trim());
    final et = int.tryParse(_et.text.trim());
    final subs = int.tryParse(_subs.text.trim());
    if (half == null || half < 5 || half > 60) {
      _snack('Half length must be between 5 and 60 minutes');
      return;
    }
    if (et == null || et < 1 || et > 30) {
      _snack('Extra time half must be between 1 and 30 minutes');
      return;
    }
    if (subs == null || subs < 1 || subs > 12) {
      _snack('Substitutes allowed must be between 1 and 12');
      return;
    }
    for (var t = 0; t < 2; t++) {
      final xi = _n(t, 1);
      if (xi > 11) {
        _snack('${m.teamAt(t)}: a team can start with at most 11 players');
        return;
      }
      if (xi > 0 && xi < 7) {
        _snack('${m.teamAt(t)}: at least 7 players are needed to start (11 recommended)');
        return;
      }
    }
    m.halfMinutes = half;
    m.etMinutes = et;
    m.maxSubs = subs;
    m.knockout = _knockout;
    m.league = _league.text.trim();
    if (m.league.isNotEmpty) AppState.I.setLeagueName(m.league);
    for (var t = 0; t < 2; t++) {
      final squad = _squad[t];
      final start = squad.where((p) => _st[t][p] == 1).toList();
      final bench = squad.where((p) => _st[t][p] == 2).toList();
      if (t == 0) {
        m.playersA = squad;
        m.startA = start;
        m.benchA = bench;
        m.captainA = _cap[0];
      } else {
        m.playersB = squad;
        m.startB = start;
        m.benchB = bench;
        m.captainB = _cap[1];
      }
      if (_cap[t].isNotEmpty) AppState.I.setCaptain(m.teamAt(t), _cap[t]);
    }
    widget.onChanged();
    Navigator.pop(context, true);
  }

  Widget _num(TextEditingController c, String label) => SizedBox(
        width: 180,
        child: TextField(
          controller: c,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
        ),
      );

  Widget _team(int t) {
    final squad = _squad[t];
    final color = t == 0 ? const Color(0xFF2979FF) : const Color(0xFFFF6D00);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          color: color,
          padding: const EdgeInsets.all(12),
          child: Text(m.teamAt(t),
              style: const TextStyle(
                  color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
        ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              'Starting XI ${_n(t, 1)}/11   •   Bench ${_n(t, 2)}   •   Captain: ${_cap[t].isEmpty ? 'not set' : _cap[t]}',
              style: const TextStyle(fontSize: 12),
            ),
            Wrap(spacing: 8, children: [
              TextButton.icon(
                onPressed: () => _auto(t),
                icon: const Icon(Icons.auto_fix_high),
                label: const Text('Auto: first 11 start'),
              ),
              TextButton.icon(
                onPressed: () => _addPlayer(t),
                icon: const Icon(Icons.person_add),
                label: const Text('Add player'),
              ),
            ]),
            if (squad.isEmpty)
              const Padding(
                padding: EdgeInsets.all(8),
                child: Text('No players yet. Import a roster (Teams screen) or add players here. '
                    'You can also play without a lineup and type player names during the match.'),
              ),
            for (final p in squad)
              Row(children: [
                IconButton(
                  tooltip: _cap[t] == p ? 'Captain (tap to remove)' : 'Make captain',
                  icon: Icon(_cap[t] == p ? Icons.star : Icons.star_border,
                      color: _cap[t] == p ? Colors.amber : null),
                  onPressed: () => setState(() => _cap[t] = _cap[t] == p ? '' : p),
                ),
                Expanded(child: Text(p, maxLines: 1, overflow: TextOverflow.ellipsis)),
                SegmentedButton<int>(
                  showSelectedIcon: false,
                  style: const ButtonStyle(visualDensity: VisualDensity.compact),
                  segments: const [
                    ButtonSegment(value: 1, label: Text('XI')),
                    ButtonSegment(value: 2, label: Text('Sub')),
                    ButtonSegment(value: 0, label: Text('Out')),
                  ],
                  selected: {_st[t][p] ?? 0},
                  onSelectionChanged: (v) => setState(() => _st[t][p] = v.first),
                ),
              ]),
          ]),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Match setup – rules & lineups')),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: FilledButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.check),
            label: const Text('Save and continue'),
          ),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: ListView(padding: const EdgeInsets.all(16), children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('MATCH RULES',
                      style: TextStyle(fontSize: 12, letterSpacing: 3, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _league,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'League / tournament name (optional)',
                      prefixIcon: Icon(Icons.emoji_events),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(spacing: 12, runSpacing: 12, children: [
                    _num(_half, 'Half length (minutes)'),
                    _num(_et, 'Extra-time half (minutes)'),
                    _num(_subs, 'Substitutes allowed'),
                  ]),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Knockout match'),
                    subtitle: const Text('If drawn after full time: extra time, then penalty shootout'),
                    value: _knockout,
                    onChanged: (v) => setState(() => _knockout = v),
                  ),
                  const Text(
                    'Rules applied: second yellow = red card, sent-off players cannot be replaced, '
                    'substituted players cannot return, one extra substitution in extra time, '
                    'a team with fewer than 7 players cannot continue.',
                    style: TextStyle(fontSize: 12),
                  ),
                ]),
              ),
            ),
            const SizedBox(height: 8),
            _team(0),
            const SizedBox(height: 8),
            _team(1),
          ]),
        ),
      ),
    );
  }
}
