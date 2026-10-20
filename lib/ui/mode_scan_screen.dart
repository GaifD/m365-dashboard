import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../ble/scooter.dart';
import '../theme.dart';
import 'widgets.dart';

/// Поиск регистра, в котором самокат хранит режим (ЭКО / драйв / спорт).
/// Приложение по кругу читает регистры контроллера и показывает те, что меняются.
class ModeScanScreen extends StatelessWidget {
  const ModeScanScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = ScooterService.instance;
    return Scaffold(
      appBar: AppBar(title: const Text('Поиск кода режима')),
      body: AnimatedBuilder(
        animation: s,
        builder: (context, _) {
          // Режим меняется редко и принимает мало значений — отсекаем «шумные» регистры
          // (время, температура, напряжение), у которых много разных значений.
          final rows = s.scanChanges.entries
              .where((e) => e.value.toSet().length <= 4)
              .toList()
            ..sort((a, b) => a.key.compareTo(b.key));
          final noisy = s.scanChanges.length - rows.length;
          final text = rows
              .map((e) => '0x${e.key.toRadixString(16).padLeft(2, '0')}: ${e.value.join(' → ')}')
              .join('\n');
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Banner2(
                text: '1. Нажми «Начать».\n'
                    '2. Подожди 20 секунд, ничего не трогая.\n'
                    '3. Переключай режимы по кругу ЭКО → драйв → спорт → ЭКО, '
                    'на каждом ждать 15 секунд.\n'
                    '4. Нажми «Скопировать» и пришли результат.',
                color: C.accent,
                icon: Icons.info_outline,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: s.dataFlowing ? (s.modeScan ? s.stopModeScan : s.startModeScan) : null,
                      icon: Icon(s.modeScan ? Icons.stop : Icons.play_arrow),
                      label: Text(s.modeScan ? 'Стоп' : 'Начать'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  OutlinedButton.icon(
                    onPressed: rows.isEmpty
                        ? null
                        : () async {
                            await Clipboard.setData(ClipboardData(text: 'Регистры, которые менялись:\n$text'));
                            if (context.mounted) {
                              ScaffoldMessenger.of(context)
                                  .showSnackBar(const SnackBar(content: Text('Скопировано — вставь в чат')));
                            }
                          },
                    icon: const Icon(Icons.copy, size: 18),
                    label: const Text('Скопировать'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (s.modeScan && rows.isEmpty)
                const Text('Читаю регистры… Пока ничего не менялось.', style: TextStyle(color: C.muted)),
              for (final e in rows)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Card2(
                    padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 56,
                          child: Text('0x${e.key.toRadixString(16).padLeft(2, '0')}', style: numStyle(15)),
                        ),
                        Expanded(
                          child: Text(e.value.join(' → '),
                              style: const TextStyle(fontSize: 13, color: C.textSoft, height: 1.35)),
                        ),
                      ],
                    ),
                  ),
                ),
              if (noisy > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text('Скрыто «шумных» регистров: $noisy (время, напряжение и т. п.)',
                      style: const TextStyle(fontSize: 12, color: C.faint)),
                ),
            ],
          );
        },
      ),
    );
  }
}
