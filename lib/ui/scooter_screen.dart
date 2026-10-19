import 'package:flutter/material.dart';

import '../ble/scooter.dart';
import '../theme.dart';
import 'battery_screen.dart' show editTariff;
import 'log_screen.dart';
import 'widgets.dart';

class ScooterScreen extends StatelessWidget {
  const ScooterScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = ScooterService.instance;
    return AnimatedBuilder(
      animation: Listenable.merge([s, s.brain]),
      builder: (context, _) {
        final connected = s.link == LinkState.connected;
        final busy = s.link == LinkState.connecting || s.link == LinkState.scanning;
        return SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            children: [
              const Text('Самокат', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              Card2(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(s.deviceName ?? 'Xiaomi M365 Pro',
                                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                              const SizedBox(height: 2),
                              Text(
                                connected ? 'Пробег ${s.totalKm.toStringAsFixed(1)} км' : (s.statusText ?? 'Не подключён'),
                                style: const TextStyle(fontSize: 12, color: C.muted),
                              ),
                            ],
                          ),
                        ),
                        if (connected)
                          OutlinedButton(onPressed: s.disconnect, child: const Text('Отключить'))
                        else
                          FilledButton(
                            onPressed: busy ? null : s.startScan,
                            child: Text(s.link == LinkState.scanning
                                ? 'Ищу…'
                                : s.link == LinkState.connecting
                                    ? 'Подключаюсь…'
                                    : 'Найти'),
                          ),
                      ],
                    ),
                    if (connected) ...[
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(child: _Ver('DRV', s.escFw)),
                          const SizedBox(width: 8),
                          const Expanded(child: _Ver('BLE', '0122')),
                          const SizedBox(width: 8),
                          Expanded(child: _Ver('BMS', s.bmsFw)),
                        ],
                      ),
                      if (s.errorCode != 0 || s.warningCode != 0) ...[
                        const SizedBox(height: 10),
                        Banner2(
                          text: 'Код ошибки ${s.errorCode}, предупреждение ${s.warningCode}',
                          color: C.red,
                        ),
                      ],
                    ],
                  ],
                ),
              ),
              if (connected && s.auth != AuthState.plain) ...[
                const SectionTitle('Привязка'),
                _AuthCard(s: s),
              ],
              if (!connected && s.scanResults.isNotEmpty) ...[
                const SectionTitle('Найдено'),
                Card2(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                  child: Column(
                    children: [
                      for (final r in s.scanResults)
                        ListTile(
                          leading: Icon(
                            ScooterService.isScooter(r) ? Icons.electric_scooter : Icons.bluetooth,
                            color: ScooterService.isScooter(r) ? C.accent : C.muted,
                          ),
                          title: Text(ScooterService.nameOf(r)),
                          subtitle: Text('${r.device.remoteId.str} · ${r.rssi} dBm',
                              style: const TextStyle(fontSize: 12, color: C.muted)),
                          onTap: busy && s.link != LinkState.scanning
                              ? null
                              : () => s.connect(r.device, name: ScooterService.nameOf(r)),
                        ),
                    ],
                  ),
                ),
              ],
              const SectionTitle('Управление'),
              Card2(
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Рекуперация', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: SizedBox(
                        width: double.infinity,
                        child: SegmentedButton<int>(
                          segments: const [
                            ButtonSegment(value: 0, label: Text('Слабая')),
                            ButtonSegment(value: 1, label: Text('Средняя')),
                            ButtonSegment(value: 2, label: Text('Сильная')),
                          ],
                          selected: (s.kers != null && s.kers! >= 0 && s.kers! <= 2) ? <int>{s.kers!} : <int>{},
                          emptySelectionAllowed: true,
                          showSelectedIcon: false,
                          onSelectionChanged: s.dataFlowing
                              ? (v) {
                                  if (v.isNotEmpty) s.setKers(v.first);
                                }
                              : null,
                          style: SegmentedButton.styleFrom(
                            selectedBackgroundColor: C.accent,
                            selectedForegroundColor: C.bg,
                            foregroundColor: C.muted,
                            side: const BorderSide(color: C.line),
                          ),
                        ),
                      ),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Круиз-контроль', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                      value: s.cruise ?? false,
                      onChanged: s.dataFlowing ? s.setCruise : null,
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Задний фонарь всегда',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                      value: s.tailLight ?? false,
                      onChanged: s.dataFlowing ? s.setTailLight : null,
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Блокировка', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                      trailing: Wrap(
                        spacing: 6,
                        children: [
                          OutlinedButton.icon(
                            onPressed: s.dataFlowing ? s.lock : null,
                            icon: const Icon(Icons.lock_outline, size: 18),
                            label: const Text('Закрыть'),
                          ),
                          OutlinedButton.icon(
                            onPressed: s.dataFlowing ? s.unlock : null,
                            icon: const Icon(Icons.lock_open, size: 18),
                            label: const Text('Открыть'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SectionTitle('Приложение'),
              Card2(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                child: Column(
                  children: [
                    ListTile(
                      title: const Text('Работа в фоне', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                      subtitle: Text(
                        s.batteryOptimizationOff
                            ? 'Без ограничений — запись в кармане не прерывается'
                            : 'Телефон ограничивает приложение. Нажми, чтобы снять. На Samsung также: '
                                'Настройки → Приложения → M365 Dashboard → Батарея → Не ограничено',
                        style: const TextStyle(fontSize: 12, color: C.muted, height: 1.35),
                      ),
                      trailing: Icon(
                        s.batteryOptimizationOff ? Icons.check : Icons.battery_alert,
                        color: s.batteryOptimizationOff ? C.accent : C.amber,
                      ),
                      onTap: s.batteryOptimizationOff ? s.refreshBatteryOptimization : s.requestBatteryOptimizationOff,
                    ),
                    ListTile(
                      title: const Text('Фоновая служба', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                      subtitle: Text(
                        s.serviceRunning
                            ? 'Работает — значок в шторке, запись идёт при выключенном экране'
                            : connected
                                ? 'Не запущена${s.serviceError != null ? ': ${s.serviceError}' : ''}. Нажми, чтобы запустить'
                                : 'Запускается при подключении к самокату',
                        style: const TextStyle(fontSize: 12, color: C.muted, height: 1.35),
                      ),
                      trailing: Icon(
                        s.serviceRunning ? Icons.check : Icons.warning_amber_rounded,
                        color: s.serviceRunning ? C.accent : (connected ? C.amber : C.faint),
                      ),
                      onTap: connected ? s.startBackgroundService : s.refreshServiceStatus,
                    ),
                    SwitchListTile(
                      title: const Text('Экран не гаснет', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                      subtitle: const Text('Пока самокат подключён. Для крепления на руль; в кармане лучше выключить',
                          style: TextStyle(fontSize: 12, color: C.muted)),
                      value: s.keepScreenOn,
                      onChanged: s.setKeepScreenOn,
                    ),
                    const ListTile(
                      title: Text('Экран блокировки', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                      subtitle: Text(
                          'Пока самокат подключён, кнопка питания показывает спидометр без разблокировки '
                          '(если приложение было открыто, когда гас экран)',
                          style: TextStyle(fontSize: 12, color: C.muted, height: 1.35)),
                    ),
                    ListTile(
                      title: const Text('Тариф на электричество',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                      subtitle: Text(
                          s.brain.tariff == null ? 'Не задан' : '${s.brain.tariff} грн за кВт·ч',
                          style: const TextStyle(fontSize: 12, color: C.muted)),
                      trailing: const Icon(Icons.edit_outlined, color: C.faint, size: 20),
                      onTap: () => editTariff(context),
                    ),
                    if (connected)
                      ListTile(
                        title: const Text('Режим (код)', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                        subtitle: const Text('Для проверки: переключи режим на самокате и посмотри, как меняется код',
                            style: TextStyle(fontSize: 12, color: C.muted)),
                        trailing: Text('${s.mode}', style: numStyle(18)),
                      ),
                    const ListTile(
                      title: Text('Колёса', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                      subtitle: Text('8.5″ стандарт · коэффициент 1.00', style: TextStyle(fontSize: 12, color: C.muted)),
                    ),
                    ListTile(
                      title: const Text('Журнал пакетов', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                      subtitle: Text('${s.log.length} строк · для отладки',
                          style: const TextStyle(fontSize: 12, color: C.muted)),
                      trailing: const Icon(Icons.chevron_right, color: C.faint),
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LogScreen())),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              const Center(child: Text('M365 Dashboard v0.3.1', style: TextStyle(fontSize: 11, color: C.faint))),
            ],
          ),
        );
      },
    );
  }
}

class _AuthCard extends StatelessWidget {
  final ScooterService s;
  const _AuthCard({required this.s});

  @override
  Widget build(BuildContext context) {
    final busy = s.auth == AuthState.registering || s.auth == AuthState.loggingIn;
    final ready = s.auth == AuthState.ready;
    return Card2(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(ready ? Icons.lock : Icons.lock_open, color: ready ? C.accent : C.amber, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  ready ? 'Приложение привязано, канал зашифрован' : (s.authStatus ?? 'Нужна привязка'),
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, height: 1.35),
                ),
              ),
              if (busy) const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
            ],
          ),
          if (!ready && !busy) ...[
            const SizedBox(height: 10),
            const Text(
              'Самокат шифрует связь. Привязка нужна один раз:\n'
              '1. Нажми «Привязать».\n'
              '2. Самокат пискнет — сразу коротко нажми кнопку питания.\n'
              '3. Если не вышло, приложение само повторит, жми после следующего писка.\n\n'
              'm365 Dashboard после этого, скорее всего, придётся привязать заново.',
              style: TextStyle(fontSize: 12, color: C.textSoft, height: 1.45),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: s.register,
                icon: const Icon(Icons.link),
                label: const Text('Привязать'),
              ),
            ),
          ],
          if (ready) ...[
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(onPressed: s.forgetPairing, child: const Text('Сбросить привязку')),
            ),
          ],
        ],
      ),
    );
  }
}

class _Ver extends StatelessWidget {
  final String label;
  final String? value;
  const _Ver(this.label, this.value);

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(color: C.bg, borderRadius: BorderRadius.circular(10)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: 10, color: C.muted)),
            Text(value ?? '—', style: numStyle(14, weight: FontWeight.w500)),
          ],
        ),
      );
}
