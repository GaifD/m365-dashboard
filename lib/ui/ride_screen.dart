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
    return AnimatedBuilder(
      animation: s,
      builder: (context, _) {
        final connected = s.link == LinkState.connected;
        final trip = s.trip;
        final inst = trip.instantWhKm;
        final avg = trip.avgWhKm;
        final range = s.rangeKm;
        final remWh = s.remainingWh;
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
              if (connected && s.noReply) ...[
                const SizedBox(height: 8),
                const Banner2(
                  text: 'Самокат подключён, но не отвечает. Возможно, нужна авторизация. '
                      'Скопируй журнал (Самокат → Журнал пакетов) и пришли мне.',
                ),
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
                  StatTile(label: 'Средний за поездку', value: fmt(avg), unit: 'Вт·ч/км', valueColor: C.accent),
                  StatTile(
                    label: 'Остаток энергии',
                    value: s.remainingMah > 0 ? remWh.toStringAsFixed(0) : '—',
                    unit: 'Вт·ч из ~${s.factoryWh.toStringAsFixed(0)}',
                  ),
                  StatTile(
                    label: 'Запас хода',
                    value: range == null ? '—' : '~${range.toStringAsFixed(0)}',
                    unit: 'км при ${s.rangeWhKm.toStringAsFixed(1)} Вт·ч/км',
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Card2(
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
                child: Row(
                  children: [
                    Expanded(child: MiniStat(label: 'Пробег', value: '${trip.km.toStringAsFixed(1)} км')),
                    Expanded(child: MiniStat(label: 'Время', value: _dur(trip.moving))),
                    Expanded(child: MiniStat(label: 'Потрачено', value: '${trip.whNet.toStringAsFixed(0)} Вт·ч')),
                    Expanded(
                        child: MiniStat(
                            label: 'Рекуп.', value: '+${trip.whRegen.toStringAsFixed(1)}', color: C.amber)),
                    IconButton(
                      tooltip: 'Новая поездка',
                      onPressed: () => _confirmNewTrip(context),
                      icon: const Icon(Icons.restart_alt, color: C.muted),
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

  static String _dur(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  void _confirmNewTrip(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: C.surface,
        title: const Text('Начать новую поездку?'),
        content: const Text('Счётчики пробега, расхода и рекуперации обнулятся.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
          TextButton(
            onPressed: () {
              ScooterService.instance.newTrip();
              Navigator.pop(ctx);
            },
            child: const Text('Начать'),
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
      LinkState.connected => s.noReply ? 'подключено · нет ответа' : 'подключено · BLE',
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
