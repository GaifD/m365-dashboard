import 'package:flutter/material.dart';

import '../ble/scooter.dart';
import '../data/models.dart';
import '../logic/analytics.dart';
import '../theme.dart';
import 'trip_detail_screen.dart';
import 'widgets.dart';

String fmtDate(DateTime d) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(d.year, d.month, d.day);
  final hm = '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  if (day == today) return 'Сегодня, $hm';
  if (day == today.subtract(const Duration(days: 1))) return 'Вчера, $hm';
  const months = ['янв', 'фев', 'мар', 'апр', 'мая', 'июн', 'июл', 'авг', 'сен', 'окт', 'ноя', 'дек'];
  return '${d.day} ${months[d.month - 1]}, $hm';
}

String fmtDur(int sec) {
  final h = sec ~/ 3600;
  final m = (sec % 3600) ~/ 60;
  return h > 0 ? '$h ч $m мин' : '$m мин';
}

class TripsScreen extends StatelessWidget {
  const TripsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = ScooterService.instance;
    final b = s.brain;
    return AnimatedBuilder(
      animation: b,
      builder: (context, _) {
        final t = b.trip;
        final weekFrom = DateTime.now().subtract(const Duration(days: 7));
        final week = b.trips.where((r) => r.start.isAfter(weekFrom)).toList();
        final weekKm = week.fold<double>(0, (a, r) => a + r.km);
        final weekWh = week.where((r) => r.wh != null).fold<double>(0, (a, r) => a + r.wh!);
        return SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            children: [
              const Text('Поездки', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              if (t != null) ...[
                Card2(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(color: C.accent, shape: BoxShape.circle),
                          ),
                          const SizedBox(width: 8),
                          const Text('Идёт поездка', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(child: MiniStat(label: 'Пробег', value: '${t.km.toStringAsFixed(2)} км')),
                          Expanded(child: MiniStat(label: 'Средняя', value: '${t.avgSpeed.toStringAsFixed(1)} км/ч')),
                          Expanded(child: MiniStat(label: 'Макс.', value: '${t.maxSpeed.toStringAsFixed(1)} км/ч')),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(child: MiniStat(label: 'Потрачено', value: '${t.wh.toStringAsFixed(1)} Вт·ч')),
                          Expanded(
                              child: MiniStat(label: 'Расход', value: '${fmt(t.avgWhKm)} Вт·ч/км', color: C.accent)),
                          Expanded(
                              child: MiniStat(
                                  label: 'Рекуперация', value: '+${t.regen.toStringAsFixed(1)} Вт·ч', color: C.amber)),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
              ],
              Card2(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text('За 7 дней', style: TextStyle(fontSize: 14, color: C.textSoft)),
                    ),
                    Text(
                      '${weekKm.toStringAsFixed(1)} км · ${weekWh.toStringAsFixed(0)} Вт·ч · '
                      '${b.rangeWhKm.toStringAsFixed(1)} Вт·ч/км',
                      style: numStyle(14, weight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              _AnalyticsSection(tripsCount: b.trips.length),
              const SizedBox(height: 4),
              if (b.trips.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 24),
                  child: Center(
                    child: Text(
                      'Пока пусто. Поездки появятся здесь сами:\nначало и конец определяются по движению.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: C.muted, height: 1.4),
                    ),
                  ),
                ),
              for (final r in b.trips) _TripTile(r: r),
            ],
          ),
        );
      },
    );
  }
}

class _TripTile extends StatelessWidget {
  final TripRecord r;
  const _TripTile({required this.r});

  @override
  Widget build(BuildContext context) {
    final avg = r.avgWhKm;
    final meta = r.unrecorded
        ? '${r.km.toStringAsFixed(1)} км · без приложения'
        : '${r.km.toStringAsFixed(1)} км · ${fmtDur(r.movingSec)} · ${r.wh?.toStringAsFixed(0) ?? '—'} Вт·ч';
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Material(
        color: C.surface,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => TripDetailScreen(trip: r))),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
            child: Row(
              children: [
                if (r.unrecorded)
                  const Padding(
                    padding: EdgeInsets.only(right: 10),
                    child: Icon(Icons.history_toggle_off, color: C.muted, size: 20),
                  ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(fmtDate(r.start), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      Text(meta, style: const TextStyle(fontSize: 12, color: C.muted)),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      avg == null ? '—' : '${r.whApprox ? '≈' : ''}${avg.toStringAsFixed(1)}',
                      style: numStyle(18, color: r.unrecorded ? C.muted : C.accent),
                    ),
                    const Text('Вт·ч/км', style: TextStyle(fontSize: 11, color: C.muted)),
                  ],
                ),
                const Icon(Icons.chevron_right, color: C.faint),
              ],
            ),
          ),
        ),
      ),
    );
  }
}


class _AnalyticsSection extends StatefulWidget {
  final int tripsCount;
  const _AnalyticsSection({required this.tripsCount});

  @override
  State<_AnalyticsSection> createState() => _AnalyticsSectionState();
}

class _AnalyticsSectionState extends State<_AnalyticsSection> {
  SpeedTable? _table;
  final _km = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(_AnalyticsSection old) {
    super.didUpdateWidget(old);
    if (old.tripsCount != widget.tripsCount) _load();
  }

  Future<void> _load() async {
    final t = await ScooterService.instance.brain.speedTable();
    if (mounted) setState(() => _table = t);
  }

  @override
  void dispose() {
    _km.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final b = ScooterService.instance.brain;
    final t = _table;
    return Column(
      children: [
        _rangeCard(b, t),
        const SizedBox(height: 10),
        if (t != null) _speedCard(t),
      ],
    );
  }

  Widget _rangeCard(dynamic b, SpeedTable? t) {
    final km = double.tryParse(_km.text.replaceAll(',', '.'));
    final usable = b.usableWh as double?;
    final whKm = b.rangeWhKm as double;
    String? title;
    String? hint;
    var ok = true;
    if (km != null && km > 0 && usable != null) {
      final reserve = usable * 0.92; // небольшой запас на ошибку оценки
      final need = km * whKm;
      if (need <= reserve) {
        final spare = reserve / whKm - km;
        title = 'Хватит, запас ~${spare.toStringAsFixed(0)} км';
        hint = 'При твоём обычном расходе ${whKm.toStringAsFixed(1)} Вт·ч/км.';
      } else {
        ok = false;
        final idx = t?.maxSpeedFor(km, reserve);
        title = 'На обычном темпе не хватит';
        if (idx == null) {
          hint = 'Нужно ~${need.toStringAsFixed(0)} Вт·ч, доступно ~${reserve.toStringAsFixed(0)}.';
        } else if (idx < 0) {
          hint = 'Не хватит даже на малой скорости: нужно ~${need.toStringAsFixed(0)} Вт·ч, доступно ~${reserve.toStringAsFixed(0)}.';
        } else {
          final top = SpeedTable.edges[idx + 1];
          hint = top >= 100
              ? 'Хватит, если ехать в своём режиме без резких разгонов.'
              : 'Держи не больше ${top.toStringAsFixed(0)} км/ч — тогда хватит.';
          title = 'Хватит, если сбавить';
          ok = true;
        }
      }
    }
    return Card2(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Хватит ли доехать?', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 110,
                child: TextField(
                  controller: _km,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (_) => setState(() {}),
                  style: numStyle(22),
                  decoration: const InputDecoration(
                    hintText: '0',
                    suffixText: 'км',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: title == null
                    ? const Padding(
                        padding: EdgeInsets.only(top: 6),
                        child: Text('Введи, сколько ехать. Учитывается заряд, слабая ячейка и твой расход.',
                            style: TextStyle(fontSize: 12, color: C.muted, height: 1.4)),
                      )
                    : Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: (ok ? C.accent : C.amber).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(title,
                                style: TextStyle(
                                    fontSize: 14, fontWeight: FontWeight.w700, color: ok ? C.accent : C.amber)),
                            if (hint != null) ...[
                              const SizedBox(height: 3),
                              Text(hint, style: const TextStyle(fontSize: 12, color: C.textSoft, height: 1.35)),
                            ],
                          ],
                        ),
                      ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _speedCard(SpeedTable t) {
    final best = t.bestBin;
    const modes = [('all', 'Все'), ('1', 'ЭКО'), ('0', 'D'), ('2', 'S')];
    final hasModes = t.tripsWithMode > 0;
    String cell(String k, int i) {
      final v = t.cells[k]![i].whKm;
      return v == null ? '—' : v.toStringAsFixed(1);
    }

    return Card2(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text('Расход по скоростям', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              ),
              Text('Вт·ч/км · ${t.trips} поездок', style: const TextStyle(fontSize: 12, color: C.muted)),
            ],
          ),
          const SizedBox(height: 10),
          Table(
            columnWidths: const {0: FlexColumnWidth(1.3)},
            children: [
              TableRow(children: [
                const Text('км/ч', style: TextStyle(fontSize: 11, color: C.muted)),
                for (final m in modes)
                  if (m.$1 == 'all' || hasModes)
                    Text(m.$2,
                        textAlign: TextAlign.right,
                        style: const TextStyle(fontSize: 11, color: C.muted, fontWeight: FontWeight.w600)),
              ]),
              for (var i = 0; i < SpeedTable.labels.length; i++)
                TableRow(children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Text(SpeedTable.labels[i],
                        style: TextStyle(fontSize: 13, color: i == best ? C.accent : C.textSoft)),
                  ),
                  for (final m in modes)
                    if (m.$1 == 'all' || hasModes)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Text(cell(m.$1, i),
                            textAlign: TextAlign.right,
                            style: numStyle(14,
                                weight: FontWeight.w500,
                                color: m.$1 == 'all' && i == best ? C.accent : C.text)),
                      ),
                ]),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            best == null
                ? 'Нужно больше поездок, чтобы посчитать.'
                : 'Экономнее всего — ${SpeedTable.labels[best]} км/ч.'
                    '${hasModes ? '' : ' Разбивка по режимам появится после поездок на этой версии.'}',
            style: const TextStyle(fontSize: 12, color: C.textSoft, height: 1.4),
          ),
        ],
      ),
    );
  }
}
