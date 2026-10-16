import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../ble/scooter.dart';
import '../theme.dart';

class LogScreen extends StatelessWidget {
  const LogScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = ScooterService.instance;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Журнал пакетов'),
        actions: [
          IconButton(
            tooltip: 'Скопировать всё',
            icon: const Icon(Icons.copy),
            onPressed: () async {
              final text = s.log.map((l) => l.toString()).join('\n');
              await Clipboard.setData(ClipboardData(text: text));
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Скопировано ${s.log.length} строк — вставь в чат')),
                );
              }
            },
          ),
          IconButton(tooltip: 'Очистить', icon: const Icon(Icons.delete_outline), onPressed: s.clearLog),
        ],
      ),
      body: AnimatedBuilder(
        animation: s,
        builder: (context, _) {
          final lines = s.log.reversed.take(400).toList();
          if (lines.isEmpty) {
            return const Center(child: Text('Пусто', style: TextStyle(color: C.muted)));
          }
          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: lines.length,
            itemBuilder: (_, i) {
              final l = lines[i];
              final color = switch (l.dir) {
                'TX' => C.muted,
                'RX' => C.accent,
                _ => C.amber,
              };
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text(l.toString(),
                    style: TextStyle(fontFamily: 'monospace', fontSize: 11, color: color, height: 1.3)),
              );
            },
          );
        },
      ),
    );
  }
}
