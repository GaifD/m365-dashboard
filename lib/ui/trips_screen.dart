import 'package:flutter/material.dart';

import '../ble/scooter.dart';
import '../data/models.dart';
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
