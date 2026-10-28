import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../ble/scooter.dart';
import '../theme.dart';
import 'widgets.dart';

class RideScreen extends StatelessWidget {
  final VoidCallback onOpenScooter;
  const RideScreen({super.key, required this.onOpenScooter});

  @override
  Widget build(BuildContext context) {
    final s = ScooterService.instance;
    final b = s.brain;
    return AnimatedBuilder(
      animation: Listenable.merge([s, b]),
      builder: (context, _) {
        final connected = s.link == LinkState.connected;
        final trip = b.trip;
        final inst = b.instantWhKm;
        final range = b.usableRangeKm;
        final remWh = b.remainingWh;
        final warns = s.dataFlowing ? b.warnings : const <String>[];
        final wi = b.cells.weakIndex;
        return SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            children: [
              _Header(s: s, onTap: onOpenScooter),
              if (!connected) ...[
                const SizedBox(height: 8),
                Banner2(
                  text: s.statusText ?? 'Самокат не подключён. Открой вкладку «Самокат», чтобы найти его.',
                  color: C.accent,
                  icon: Icons.bluetooth_searching,
                ),
              ],
              if (connected && !s.dataFlowing) ...[
                const SizedBox(height: 8),
                Banner2(
                  text: s.authStatus ?? 'Подготовка связи…',
                  color: s.auth == AuthState.failed ? C.red : C.accent,
                  icon: Icons.lock_outline,
                ),
                if (s.auth == AuthState.needRegister || s.auth == AuthState.failed) ...[
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: onOpenScooter,
                    icon: const Icon(Icons.link),
                    label: const Text('Привязать самокат'),
                  ),
                ],
              ],
              if (s.dataFlowing && s.noReply) ...[
                const SizedBox(height: 8),
                const Banner2(
                  text: 'Самокат подключён, но не отвечает. Скопируй журнал (Самокат → Журнал пакетов) и пришли мне.',
                ),
              ],
              if (connected && !s.batteryOptimizationOff) ...[
                const SizedBox(height: 8),
                InkWell(
                  onTap: s.requestBatteryOptimizationOff,
                  borderRadius: BorderRadius.circular(14),
                  child: const Banner2(
                    text: 'Разреши приложению работать в фоне без ограничений, иначе телефон может '
                        'прерывать запись в кармане. Нажми здесь.',
                    icon: Icons.battery_alert,
                  ),
                ),
              ],
              for (final w in warns.take(2)) ...[
                const SizedBox(height: 8),
                Banner2(text: w, color: C.amber),
              ],
              const SizedBox(height: 6),
              Center(
                child: SizedBox(
                  width: 300,
                  height: 300,
                  child: CustomPaint(
                    painter: _GaugePainter(speed: s.speed, power: s.power),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(s.speed.abs().toStringAsFixed(0),
                              style: numStyle(104, weight: FontWeight.w700).copyWith(height: 0.95, letterSpacing: -2)),
                          const Text('КМ/Ч', style: TextStyle(fontSize: 14, color: C.muted, letterSpacing: 1)),
                          const SizedBox(height: 14),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.baseline,
                            textBaseline: TextBaseline.alphabetic,
                            children: [
                              Text('${s.power >= 0 ? '+' : '−'}${s.power.abs().toStringAsFixed(0)}',
                                  style: numStyle(20, color: s.power < 0 ? C.amber : C.text)),
                              const SizedBox(width: 4),
                              const Text('Вт', style: TextStyle(fontSize: 13, color: C.muted)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 1.55,
                children: [
                  StatTile(label: 'Расход сейчас', value: fmt(inst), unit: 'Вт·ч/км'),
                  StatTile(
                      label: 'Средний за поездку', value: fmt(trip?.avgWhKm), unit: 'Вт·ч/км', valueColor: C.accent),
                  StatTile(
                    label: 'Остаток энергии',
                    value: remWh == null ? '—' : remWh.toStringAsFixed(0),
                    unit: 'Вт·ч из ~${(b.whPerPct * 100).toStringAsFixed(0)}${b.capacity.isEmpty ? ' (завод.)' : ''}',
                  ),
                  StatTile(
                    label: 'Запас хода',
                    value: range == null ? '—' : '~${range.toStringAsFixed(0)}',
                    unit: b.weakLimits && wi != null
                        ? 'км · до просадки ячейки ${wi + 1}'
                        : 'км при ${b.rangeWhKm.toStringAsFixed(1)} Вт·ч/км',
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (trip != null)
                Card2(
                  padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
                  child: Row(
                    children: [
                      Expanded(child: MiniStat(label: 'Пробег', value: '${trip.km.toStringAsFixed(1)} км')),
                      Expanded(child: MiniStat(label: 'Время', value: _dur(trip.movingSec))),
                      Expanded(child: MiniStat(label: 'Потрачено', value: '${trip.wh.toStringAsFixed(0)} Вт·ч')),
                      Expanded(
                          child: MiniStat(label: 'Рекуп.', value: '+${trip.regen.toStringAsFixed(1)}', color: C.amber)),
                      IconButton(
                        tooltip: 'Завершить поездку',
                        onPressed: () => _confirmFinish(context),
                        icon: const Icon(Icons.flag_outlined, color: C.muted),
                      ),
                    ],
                  ),
                )
              else
                Card2(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                  child: Row(
                    children: [
                      const Icon(Icons.play_circle_outline, color: C.muted, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          b.liveCharge != null
                              ? 'Идёт зарядка: +${b.liveCharge!.wh.toStringAsFixed(0)} Вт·ч в батарею'
                              : 'Поездка начнётся сама, как только поедешь',
                          style: const TextStyle(fontSize: 13, color: C.textSoft),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  static String _dur(int sec) {
    final m = sec ~/ 60;
    final s = sec % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  void _confirmFinish(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: C.surface,
        title: const Text('Завершить поездку?'),
        content: const Text('Обычно поездка завершается сама через 3 минуты стоянки. '
            'Следующая начнётся автоматически, когда поедешь.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
          TextButton(
            onPressed: () {
              ScooterService.instance.brain.finishTripNow();
              Navigator.pop(ctx);
            },
            child: const Text('Завершить'),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final ScooterService s;
  final VoidCallback onTap;
  const _Header({required this.s, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final connected = s.link == LinkState.connected;
    final status = switch (s.link) {
      LinkState.connected => !s.dataFlowing
          ? 'подключено · нужна авторизация'
          : s.noReply
              ? 'подключено · нет ответа'
              : (s.auth == AuthState.ready ? 'подключено · шифрование' : 'подключено · BLE'),
      LinkState.connecting => 'подключаюсь…',
      LinkState.scanning => 'поиск…',
      LinkState.idle => 'не подключено',
    };
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        child: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(shape: BoxShape.circle, color: connected ? C.accent : C.faint),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(s.deviceName ?? 'M365 Pro', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                  Text(status, style: const TextStyle(fontSize: 12, color: C.muted)),
                ],
              ),
            ),
            if (connected) ...[
              if (s.mode >= 0) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(99),
                    border: Border.all(color: s.mode == 2 ? C.amber : C.accent),
                  ),
                  child: Text(ScooterService.modeShort(s.mode),
                      style: TextStyle(
                          fontSize: 11, fontWeight: FontWeight.w700, color: s.mode == 2 ? C.amber : C.accent)),
                ),
                const SizedBox(width: 12),
              ],
              const Icon(Icons.thermostat, size: 16, color: C.textSoft),
              Text('${s.temp1}°', style: const TextStyle(fontSize: 13, color: C.textSoft)),
              const SizedBox(width: 14),
              _BatteryIcon(pct: s.batteryPct),
              const SizedBox(width: 6),
              Text('${s.batteryPct}%', style: numStyle(15)),
            ],
          ],
        ),
      ),
    );
  }
}

class _BatteryIcon extends StatelessWidget {
  final int pct;
  const _BatteryIcon({required this.pct});

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 22,
        height: 12,
        child: CustomPaint(painter: _BatteryPainter(pct)),
      );
}

class _BatteryPainter extends CustomPainter {
  final int pct;
  _BatteryPainter(this.pct);

  @override
  void paint(Canvas canvas, Size size) {
    final outline = Paint()
      ..color = C.muted
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawRRect(RRect.fromLTRBR(0.75, 0.75, 18.75, 11.25, const Radius.circular(2.5)), outline);
    canvas.drawRRect(RRect.fromLTRBR(19.6, 4, 21.6, 8, const Radius.circular(1)), Paint()..color = C.muted);
    final w = 14.5 * (pct.clamp(0, 100) / 100);
    final color = pct <= 15 ? C.red : C.accent;
    canvas.drawRRect(RRect.fromLTRBR(2.5, 2.5, 2.5 + w, 9.5, const Radius.circular(1)), Paint()..color = color);
  }

  @override
  bool shouldRepaint(_BatteryPainter old) => old.pct != pct;
}

class _GaugePainter extends CustomPainter {
  final double speed;
  final double power;
  static const double maxSpeed = 35;
  static const double maxPower = 700;
  static const double sweep = math.pi * 1.5; // 270°
  static const double start = math.pi * 0.75; // 135°

  _GaugePainter({required this.speed, required this.power});

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    Paint arc(Color color, double w) => Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = w
      ..strokeCap = StrokeCap.round;

    final outer = Rect.fromCircle(center: c, radius: 130);
    final inner = Rect.fromCircle(center: c, radius: 110);
    canvas.drawArc(outer, start, sweep, false, arc(C.track, 14));
    final sf = (speed.abs() / maxSpeed).clamp(0.0, 1.0);
    if (sf > 0.002) canvas.drawArc(outer, start, sweep * sf, false, arc(C.accent, 14));

    canvas.drawArc(inner, start, sweep, false, arc(const Color(0xFF151E24), 6));
    final pf = (power.abs() / maxPower).clamp(0.0, 1.0);
    if (pf > 0.002) {
      canvas.drawArc(inner, start, sweep * pf, false,
          arc(power < 0 ? C.amber : C.text.withValues(alpha: 0.85), 6));
    }

    final tp = TextPainter(textDirection: TextDirection.ltr);
    void label(String t, Offset at) {
      tp.text = TextSpan(text: t, style: const TextStyle(fontSize: 12, color: C.faint));
      tp.layout();
      tp.paint(canvas, at - Offset(tp.width / 2, tp.height / 2));
    }

    label('0', c + Offset(math.cos(start) * 130, math.sin(start) * 130) + const Offset(-6, 22));
    label('${maxSpeed.toInt()}',
        c + Offset(math.cos(start + sweep) * 130, math.sin(start + sweep) * 130) + const Offset(6, 22));
  }

  @override
  bool shouldRepaint(_GaugePainter old) => old.speed != speed || old.power != power;
}
