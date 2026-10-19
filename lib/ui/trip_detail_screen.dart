import 'package:flutter/material.dart';

import '../ble/scooter.dart';
import '../data/models.dart';
import '../theme.dart';
import 'chart.dart';
import 'trips_screen.dart' show fmtDate;
import 'widgets.dart';

class TripDetailScreen extends StatefulWidget {
  final TripRecord trip;
  const TripDetailScreen({super.key, required this.trip});

  @override
  State<TripDetailScreen> createState() => _TripDetailScreenState();
}

enum _Series { speed, power, consumption, voltage }

class _TripDetailScreenState extends State<TripDetailScreen> {
  List<List<num>>? _samples;
  _Series _series = _Series.speed;

  @override
  void initState() {
    super.initState();
    ScooterService.instance.brain.loadSamples(widget.trip).then((v) {
      if (mounted) setState(() => _samples = v);
    });
  }

  List<double?> _values() {
    final s = _samples ?? const [];
    switch (_series) {
      case _Series.speed:
        return [for (final r in s) r[1].toDouble()];
      case _Series.power:
        return [for (final r in s) r[2].toDouble()];
      case _Series.voltage:
        return [for (final r in s) r[3].toDouble() > 0 ? r[3].toDouble() : null];
      case _Series.consumption:
        // Скользящий расход по последним ~200 м.
        final out = <double?>[];
        var j = 0;
        for (var i = 0; i < s.length; i++) {
          final km = s[i][7].toDouble();
          final wh = s[i][6].toDouble();
          while (j < i && km - s[j + 1][7].toDouble() >= 0.2) {
            j++;
          }
          final dKm = km - s[j][7].toDouble();
          out.add(dKm >= 0.2 ? (wh - s[j][6].toDouble()) / dKm : null);
        }
        return out;
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.trip;
    final totalSec = (_samples != null && _samples!.isNotEmpty) ? _samples!.last[0].toInt() : 0;
    final unit = switch (_series) {
      _Series.speed => 'км/ч',
      _Series.power => 'Вт',
      _Series.consumption => 'Вт·ч/км',
      _Series.voltage => 'В',
    };
    return Scaffold(
      appBar: AppBar(
        title: Text(fmtDate(r.start)),
        actions: [
          IconButton(
            tooltip: 'Удалить поездку',
            icon: const Icon(Icons.delete_outline),
            onPressed: () => _confirmDelete(context),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          if (r.unrecorded)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Banner2(
                text: 'Поездка без приложения: найдена по одометру между ${fmtDate(r.start)} и ${fmtDate(r.end)}. '
                    'Километры точные, энергия примерная. В расход и прогнозы не входит.',
                color: C.muted,
                icon: Icons.history_toggle_off,
              ),
            ),
          GridView.count(
            crossAxisCount: 4,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 0.95,
            children: [
              _Tile('Пробег', r.km.toStringAsFixed(2), 'км'),
              _Tile('В движении', r.unrecorded ? '—' : '${r.movingSec ~/ 60}', 'мин'),
              _Tile('Средняя', fmt(r.avgSpeed), 'км/ч'),
              _Tile('Макс.', r.unrecorded ? '—' : r.maxSpeed.toStringAsFixed(1), 'км/ч'),
              _Tile('Потрачено', r.wh == null ? '—' : '${r.whApprox ? '≈' : ''}${r.wh!.toStringAsFixed(0)}', 'Вт·ч'),
              _Tile('Расход', r.avgWhKm == null ? '—' : '${r.whApprox ? '≈' : ''}${r.avgWhKm!.toStringAsFixed(1)}',
                  'Вт·ч/км',
                  color: C.accent),
              _Tile('Рекуп.', r.unrecorded ? '—' : '+${r.regenWh.toStringAsFixed(1)}', 'Вт·ч', color: C.amber),
              _Tile('Мин. ячейка', r.minCell == null ? '—' : r.minCell!.toStringAsFixed(2), 'В'),
            ],
          ),
          const SizedBox(height: 10),
          Card2(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Row(
              children: [
                const Expanded(child: Text('Заряд', style: TextStyle(fontSize: 14, color: C.textSoft))),
                Text(
                  '${r.pctStart?.toStringAsFixed(0) ?? '—'}% → ${r.pctEnd?.toStringAsFixed(0) ?? '—'}%',
                  style: numStyle(16),
                ),
              ],
            ),
          ),
          if (r.gapKm > 0.05) ...[
            const SizedBox(height: 10),
            Banner2(
              text: 'Внутри поездки ${r.gapKm.toStringAsFixed(1)} км прошли без связи — '
                  'расход посчитан по остальным ${r.effKm.toStringAsFixed(1)} км.',
            ),
          ],
          if (r.hasSamples) ...[
            const SizedBox(height: 10),
            Card2(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      _chip('Скорость', _Series.speed),
                      _chip('Мощность', _Series.power),
                      _chip('Расход', _Series.consumption),
                      _chip('Напряжение', _Series.voltage),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (_samples == null)
                    const SizedBox(height: 170, child: Center(child: CircularProgressIndicator(strokeWidth: 2)))
                  else
                    LineChart(
                      values: _values(),
                      unit: unit,
                      totalSec: totalSec,
                      color: _series == _Series.power ? C.text : C.accent,
                    ),
                  if (_series == _Series.power)
                    const Padding(
                      padding: EdgeInsets.only(top: 6),
                      child: Text('Янтарным — рекуперация', style: TextStyle(fontSize: 11, color: C.muted)),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _chip(String label, _Series v) {
    final on = _series == v;
    return ChoiceChip(
      label: Text(label),
      selected: on,
      showCheckmark: false,
      onSelected: (_) => setState(() => _series = v),
      selectedColor: C.accent,
      backgroundColor: C.bg,
      labelStyle: TextStyle(color: on ? C.bg : C.textSoft, fontWeight: FontWeight.w600, fontSize: 12),
      side: BorderSide(color: on ? C.accent : C.line),
    );
  }

  void _confirmDelete(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: C.surface,
        title: const Text('Удалить поездку?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await ScooterService.instance.brain.deleteTrip(widget.trip);
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  final String label;
  final String value;
  final String unit;
  final Color color;
  const _Tile(this.label, this.value, this.unit, {this.color = C.text});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: C.surface, borderRadius: BorderRadius.circular(14)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(fontSize: 10, color: C.muted), maxLines: 1),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(value, style: numStyle(17, color: color)),
            ),
            Text(unit, style: const TextStyle(fontSize: 10, color: C.muted), maxLines: 1),
          ],
        ),
      );
}
