import 'package:flutter/material.dart';

import '../ble/scooter.dart';
import '../theme.dart';
import 'widgets.dart';

class TripsScreen extends StatelessWidget {
  const TripsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = ScooterService.instance;
    return AnimatedBuilder(
      animation: s,
      builder: (context, _) {
        final t = s.trip;
        return SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            children: [
              const Text('Поездки', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              Card2(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Текущая поездка', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
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
                        Expanded(child: MiniStat(label: 'Потрачено', value: '${t.whNet.toStringAsFixed(1)} Вт·ч')),
                        Expanded(
                            child: MiniStat(label: 'Расход', value: '${fmt(t.avgWhKm)} Вт·ч/км', color: C.accent)),
                        Expanded(
                            child: MiniStat(
                                label: 'Рекуперация', value: '+${t.whRegen.toStringAsFixed(1)} Вт·ч', color: C.amber)),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Card2(
                child: Row(
                  children: [
                    const Expanded(
                      child: Text('Средний расход для прогноза',
                          style: TextStyle(fontSize: 14, color: C.textSoft)),
                    ),
                    Text('${s.savedAvgWhKm.toStringAsFixed(1)} Вт·ч/км', style: numStyle(16)),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              const Banner2(
                text: 'История поездок, графики, расход по скоростям и «хватит ли доехать» — в следующей версии.',
                color: C.accent,
                icon: Icons.timeline,
              ),
            ],
          ),
        );
      },
    );
  }
}
