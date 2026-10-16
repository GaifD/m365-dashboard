import 'package:flutter/material.dart';

import '../theme.dart';

class Card2 extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  const Card2({super.key, required this.child, this.padding = const EdgeInsets.all(16)});

  @override
  Widget build(BuildContext context) => Container(
        padding: padding,
        decoration: BoxDecoration(color: C.surface, borderRadius: BorderRadius.circular(18)),
        child: child,
      );
}

class StatTile extends StatelessWidget {
  final String label;
  final String value;
  final String unit;
  final Color valueColor;
  final double size;
  const StatTile({
    super.key,
    required this.label,
    required this.value,
    required this.unit,
    this.valueColor = C.text,
    this.size = 30,
  });

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: BoxDecoration(color: C.surface, borderRadius: BorderRadius.circular(16)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: 12, color: C.muted)),
            const SizedBox(height: 4),
            Text(value, style: numStyle(size, color: valueColor)),
            const SizedBox(height: 2),
            Text(unit, style: const TextStyle(fontSize: 12, color: C.muted), maxLines: 1, overflow: TextOverflow.ellipsis),
          ],
        ),
      );
}

class MiniStat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const MiniStat({super.key, required this.label, required this.value, this.color = C.text});

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 11, color: C.muted)),
          const SizedBox(height: 2),
          Text(value, style: numStyle(16, color: color)),
        ],
      );
}

class SectionTitle extends StatelessWidget {
  final String text;
  const SectionTitle(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
        child: Text(text.toUpperCase(),
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: C.muted, letterSpacing: 0.8)),
      );
}

class Banner2 extends StatelessWidget {
  final String text;
  final Color color;
  final IconData icon;
  const Banner2({super.key, required this.text, this.color = C.amber, this.icon = Icons.warning_amber_rounded});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 10),
            Expanded(child: Text(text, style: const TextStyle(fontSize: 13, color: C.text, height: 1.35))),
          ],
        ),
      );
}

String fmt(double? v, [int digits = 1]) => v == null || v.isNaN || v.isInfinite ? '—' : v.toStringAsFixed(digits);
