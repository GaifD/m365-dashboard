import 'package:flutter/material.dart';

import '../ble/scooter.dart';
import '../theme.dart';
import 'widgets.dart';

class BatteryScreen extends StatelessWidget {
  const BatteryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = ScooterService.instance;
    return AnimatedBuilder(
      animation: s,
      builder: (context, _) {
        final hasData = s.voltage > 0;
        final spread = s.cellSpread;
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
                                value: s.batteryPct / 100,
                                strokeWidth: 9,
                                strokeCap: StrokeCap.round,
                                backgroundColor: C.track,
                                color: s.batteryPct <= 15 ? C.red : C.accent,
                              ),
                            ),
                            Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text('${s.batteryPct}%', style: numStyle(26, weight: FontWeight.w700)),
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
                            Text('${s.remainingWh.toStringAsFixed(0)} Вт·ч', style: numStyle(22)),
                            const SizedBox(height: 4),
                            Text('${s.remainingMah} мАч осталось',
                                style: const TextStyle(fontSize: 13, color: C.muted)),
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
                const SizedBox(height: 10),
                const Banner2(
                  text: 'Реальная ёмкость, износ и сопротивление батареи появятся в следующей версии — '
                      'для них нужна история нескольких поездок.',
                  color: C.accent,
                  icon: Icons.insights,
                ),
              ],
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
