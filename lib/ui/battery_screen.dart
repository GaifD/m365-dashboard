import 'package:flutter/material.dart';

import '../ble/scooter.dart';
import '../data/models.dart';
import '../logic/brain.dart';
import '../theme.dart';
import 'trips_screen.dart' show fmtDate;
import 'widgets.dart';

class BatteryScreen extends StatelessWidget {
  const BatteryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = ScooterService.instance;
    final b = s.brain;
    return AnimatedBuilder(
      animation: Listenable.merge([s, b]),
      builder: (context, _) {
        final hasData = s.voltage > 0;
        final spread = s.cellSpread;
        final pct = s.batteryPct;
        final rawDiff = (pct - s.bmsPct).abs() >= 3 && s.bmsPct > 0;
        return SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            children: [
              Row(
                children: [
                  const Expanded(
                      child: Text('Батарея', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700))),
                  Text('BMS ${s.bmsFw ?? '—'} · ${s.capacityMah} мАч',
                      style: const TextStyle(fontSize: 12, color: C.muted)),
                ],
              ),
              const SizedBox(height: 12),
              if (!hasData)
                const Banner2(
                  text: 'Данных пока нет — подключись к самокату.',
                  color: C.accent,
                  icon: Icons.info_outline,
                )
              else ...[
                Card2(
                  child: Row(
                    children: [
                      SizedBox(
                        width: 104,
                        height: 104,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            SizedBox(
                              width: 92,
                              height: 92,
                              child: CircularProgressIndicator(
                                value: pct / 100,
                                strokeWidth: 9,
                                strokeCap: StrokeCap.round,
                                backgroundColor: C.track,
                                color: pct <= 15 ? C.red : C.accent,
                              ),
                            ),
                            Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text('$pct%', style: numStyle(26, weight: FontWeight.w700)),
                                const Text('заряд', style: TextStyle(fontSize: 11, color: C.muted)),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${b.remainingWh?.toStringAsFixed(0) ?? '—'} Вт·ч', style: numStyle(22)),
                            const SizedBox(height: 4),
                            Text(
                              rawDiff
                                  ? 'BMS сейчас: ${s.bmsPct}% — просадка под нагрузкой'
                                  : '${s.remainingMah} мАч по BMS',
                              style: const TextStyle(fontSize: 13, color: C.muted),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Циклов: ${s.cycles ?? '—'} · зарядок: ${s.chargeCount ?? '—'}',
                              style: const TextStyle(fontSize: 13, color: C.muted),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Card2(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Expanded(
                              child: Text('Ячейки', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700))),
                          const Text('разбаланс ', style: TextStyle(fontSize: 12, color: C.muted)),
                          Text('${spread.toStringAsFixed(3)} В',
                              style: numStyle(14, color: spread >= 0.05 ? C.amber : C.text)),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _CellBars(cells: s.cells),
                      const SizedBox(height: 10),
                      Text(_cellVerdict(s.cells, spread),
                          style: const TextStyle(fontSize: 12, color: C.textSoft, height: 1.4)),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                        child: StatTile(
                            label: 'Напряжение', value: s.voltage.toStringAsFixed(2), unit: 'В', size: 20)),
                    const SizedBox(width: 10),
                    Expanded(
                        child: StatTile(
                            label: 'Ток',
                            value: s.current.toStringAsFixed(1),
                            unit: 'А · ${s.power.toStringAsFixed(0)} Вт',
                            size: 20)),
                    const SizedBox(width: 10),
                    Expanded(
                        child: StatTile(
                            label: 'Температура',
                            value: '${s.temp1}°',
                            unit: 'BMS · ${s.temp2}°',
                            size: 20)),
                  ],
                ),
              ],
              const SizedBox(height: 10),
              _CapacityCard(b: b),
              const SectionTitle('Зарядки'),
              _ChargesCard(b: b, onTariff: () => editTariff(context)),
            ],
          ),
        );
      },
    );
  }

  static String _cellVerdict(List<double> cells, double spread) {
    if (cells.length < 2) return 'Жду данные по ячейкам…';
    var minI = 0;
    for (var i = 1; i < cells.length; i++) {
      if (cells[i] < cells[minI]) minI = i;
    }
    if (spread < 0.03) return 'Ячейки сбалансированы.';
    if (spread < 0.05) {
      return 'Ячейка ${minI + 1} ниже остальных на ${spread.toStringAsFixed(2)} В — в пределах нормы.';
    }
    if (spread < 0.10) {
      return 'Ячейка ${minI + 1} отстаёт на ${spread.toStringAsFixed(2)} В. Стоит зарядить до 100% и '
          'оставить на зарядке пару часов для балансировки.';
    }
    return 'Сильный разбаланс: ячейка ${minI + 1} отстаёт на ${spread.toStringAsFixed(2)} В. '
        'Батарею стоит проверить.';
  }
}

Future<void> editTariff(BuildContext context) async {
  final b = ScooterService.instance.brain;
  final ctl = TextEditingController(text: b.tariff?.toString() ?? '');
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: C.surface,
      title: const Text('Тариф на электричество'),
      content: TextField(
        controller: ctl,
        autofocus: true,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: const InputDecoration(suffixText: 'грн за кВт·ч', hintText: 'например, 4.32'),
      ),
      actions: [
        TextButton(
          onPressed: () {
            b.setTariff(null);
            Navigator.pop(ctx);
          },
          child: const Text('Убрать'),
        ),
        TextButton(
          onPressed: () {
            final v = double.tryParse(ctl.text.replaceAll(',', '.').trim());
            if (v != null && v > 0) b.setTariff(v);
            Navigator.pop(ctx);
          },
          child: const Text('Сохранить'),
        ),
      ],
    ),
  );
}

class _CapacityCard extends StatelessWidget {
  final Brain b;
  const _CapacityCard({required this.b});

  @override
  Widget build(BuildContext context) {
    final wh = b.capWh;
    final n = b.capacity.length;
    return Card2(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text('Реальная ёмкость', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              ),
              Text(n == 0 ? 'нет замеров' : 'уточняется · $n замер${n == 1 ? '' : n < 5 ? 'а' : 'ов'}',
                  style: const TextStyle(fontSize: 12, color: C.muted)),
            ],
          ),
          const SizedBox(height: 10),
          if (wh == null)
            const Text(
              'Замер появится сам, когда заряд за поездки упадёт хотя бы на 15%, '
              'а самокат потом постоит 15+ минут (или до следующего подключения). '
              'Зарядка между этими моментами сбрасывает замер.',
              style: TextStyle(fontSize: 12, color: C.textSoft, height: 1.45),
            )
          else ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text('~${wh.toStringAsFixed(0)} Вт·ч', style: numStyle(24, color: C.accent)),
                const SizedBox(width: 8),
                Text('${(wh / b.factoryWh * 100).toStringAsFixed(0)}% от заводской',
                    style: const TextStyle(fontSize: 13, color: C.muted)),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'По счётчику приложения: ~${(b.capAhApp! * 1000).toStringAsFixed(0)} мАч\n'
              'По счётчику BMS: ~${b.capMahBms!.toStringAsFixed(0)} мАч\n'
              'Заводская: ${b.factoryMah} мАч (~${b.factoryWh.toStringAsFixed(0)} Вт·ч)',
              style: const TextStyle(fontSize: 12, color: C.textSoft, height: 1.5),
            ),
          ],
        ],
      ),
    );
  }
}

class _ChargesCard extends StatelessWidget {
  final Brain b;
  final VoidCallback onTariff;
  const _ChargesCard({required this.b, required this.onTariff});

  @override
  Widget build(BuildContext context) {
    final tariff = b.tariff;
    final lc = b.liveCharge;
    final list = b.charges.take(6).toList();
    final kwh = b.monthWallKwh;
    final per100 = b.costPer100km;
    return Card2(
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (lc != null)
            Padding(
              padding: const EdgeInsets.only(right: 8, bottom: 10),
              child: Banner2(
                text: 'Идёт зарядка: +${lc.wh.toStringAsFixed(0)} Вт·ч, +${(lc.ah * 1000).toStringAsFixed(0)} мАч '
                    '(по BMS +${b.mah - lc.mahFrom} мАч)',
                color: C.accent,
                icon: Icons.bolt,
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Row(
              children: [
                Expanded(
                  child: MiniStat(label: 'Из розетки за 30 дней', value: '${kwh.toStringAsFixed(2)} кВт·ч'),
                ),
                Expanded(
                  child: MiniStat(
                    label: 'Стоимость 100 км',
                    value: per100 == null ? '—' : '${per100.toStringAsFixed(1)} грн',
                  ),
                ),
              ],
            ),
          ),
          if (list.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(0, 12, 8, 6),
              child: Text(
                'Зарядки появятся сами: приложение видит их при следующем подключении. '
                'Если телефон рядом во время зарядки — запишет точно.',
                style: TextStyle(fontSize: 12, color: C.textSoft, height: 1.45),
              ),
            ),
          for (final c in list) _ChargeTile(c: c, tariff: tariff),
          ListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: const Text('Тариф', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            subtitle: Text(tariff == null ? 'не задан — стоимость не считается' : '$tariff грн за кВт·ч',
                style: const TextStyle(fontSize: 12, color: C.muted)),
            trailing: const Icon(Icons.edit_outlined, color: C.faint, size: 20),
            onTap: onTariff,
          ),
        ],
      ),
    );
  }
}

class _ChargeTile extends StatelessWidget {
  final ChargeRecord c;
  final double? tariff;
  const _ChargeTile({required this.c, required this.tariff});

  @override
  Widget build(BuildContext context) {
    final wall = c.wallWh;
    final cost = (wall != null && tariff != null) ? wall / 1000 * tariff! : null;
    final approx = c.approx ? '≈' : '';
    final parts = <String>[
      '${c.pctFrom.toStringAsFixed(0)}% → ${c.pctTo.toStringAsFixed(0)}%',
      if (c.count > 1) '${c.count} зарядки',
      if (c.live) 'записана целиком',
    ];
    final details = c.live && c.ahApp != null && c.mahBms != null
        ? '\nприложение +${(c.ahApp! * 1000).toStringAsFixed(0)} мАч · BMS +${c.mahBms} мАч'
        : '';
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 10, 8, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.bolt, size: 18, color: c.live ? C.accent : C.muted),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(fmtDate(c.t), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                Text('${parts.join(' · ')}$details',
                    style: const TextStyle(fontSize: 11, color: C.muted, height: 1.35)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(c.batteryWh == null ? '—' : '$approx+${c.batteryWh!.toStringAsFixed(0)} Вт·ч', style: numStyle(14)),
              if (cost != null)
                Text('$approx${cost.toStringAsFixed(2)} грн', style: const TextStyle(fontSize: 11, color: C.muted)),
            ],
          ),
        ],
      ),
    );
  }
}

class _CellBars extends StatelessWidget {
  final List<double> cells;
  const _CellBars({required this.cells});

  @override
  Widget build(BuildContext context) {
    if (cells.isEmpty) return const SizedBox(height: 110);
    final mx = cells.reduce((a, b) => a > b ? a : b);
    final mn = cells.reduce((a, b) => a < b ? a : b);
    final lowIdx = cells.indexOf(mn);
    final flagLow = mx - mn >= 0.03;
    return SizedBox(
      height: 130,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < cells.length; i++)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      cells[i].toStringAsFixed(2).substring(1),
                      style: numStyle(10,
                          weight: FontWeight.w500, color: flagLow && i == lowIdx ? C.amber : C.muted),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      height: (20 + (cells[i] - 3.0) * 70).clamp(8, 100).toDouble(),
                      decoration: BoxDecoration(
                        color: flagLow && i == lowIdx ? C.amber : C.accent,
                        borderRadius: BorderRadius.circular(5),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text('${i + 1}', style: const TextStyle(fontSize: 10, color: C.faint)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
