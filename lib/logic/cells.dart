// Слабая ячейка: какая, насколько отстаёт в покое, какое у неё сопротивление
// и при каком заряде она начнёт упираться в порог отключения.
import 'dart:math' as math;

import 'energy.dart';

double _median(List<double> v) {
  if (v.isEmpty) return double.nan;
  final s = [...v]..sort();
  final n = s.length;
  return n.isOdd ? s[n ~/ 2] : (s[n ~/ 2 - 1] + s[n ~/ 2]) / 2;
}

class WeakCellTracker {
  static const double cutoffV = 3.0; // ниже этого под нагрузкой — риск отключения
  static const double warnV = 3.15;

  List<int> minCounts = [];
  int observations = 0;
  double? restGap; // насколько слабая ячейка ниже средней остальных в покое, В
  final List<double> rWeak = []; // сопротивление слабой ячейки, Ом (ΔV/ΔI)
  final List<double> rOthers = []; // среднее сопротивление остальных
  final List<int> currentHist = List<int>.filled(41, 0); // ток в движении, по 1 А

  // для ΔV/ΔI
  double? _prevI;
  double? _prevWeak;
  double? _prevOthers;
  int? _prevIdx;
  DateTime? _prevT;

  /// Индекс слабой ячейки (0-based), если уверенно определена.
  int? get weakIndex {
    if (minCounts.isEmpty || observations < 40) return null;
    var best = 0;
    for (var i = 1; i < minCounts.length; i++) {
      if (minCounts[i] > minCounts[best]) best = i;
    }
    return minCounts[best] >= observations * 0.6 ? best : null;
  }

  double? get rWeakOhm => rWeak.length >= 8 ? _median(rWeak) : null;
  double? get rOthersOhm => rOthers.length >= 8 ? _median(rOthers) : null;

  /// Типичный «сильный» ток в езде — 90-й перцентиль.
  double? get peakCurrent {
    final total = currentHist.fold<int>(0, (a, b) => a + b);
    if (total < 60) return null;
    var acc = 0;
    for (var i = 0; i < currentHist.length; i++) {
      acc += currentHist[i];
      if (acc >= total * 0.9) return i.toDouble() + 0.5;
    }
    return currentHist.length.toDouble();
  }

  void update(List<double> cells, double current, double speed, {required bool atRest}) {
    if (cells.length < 2) return;
    if (minCounts.length != cells.length) {
      minCounts = List<int>.filled(cells.length, 0);
      observations = 0;
    }
    var mi = 0;
    for (var i = 1; i < cells.length; i++) {
      if (cells[i] < cells[mi]) mi = i;
    }
    final spread = cells.reduce(math.max) - cells[mi];
    if (spread >= 0.01) {
      minCounts[mi]++;
      observations++;
      if (observations > 5000) {
        // старые наблюдения постепенно забываются
        for (var i = 0; i < minCounts.length; i++) {
          minCounts[i] = (minCounts[i] * 0.8).round();
        }
        observations = minCounts.fold<int>(0, (a, b) => a + b);
      }
    }
    if (speed > 3 && current > 0) {
      final b = current.round().clamp(0, currentHist.length - 1);
      currentHist[b]++;
    }

    final w = weakIndex ?? mi;
    final weakV = cells[w];
    final others = [for (var i = 0; i < cells.length; i++) if (i != w) cells[i]];
    final othersAvg = others.reduce((a, b) => a + b) / others.length;

    if (atRest) {
      final g = othersAvg - weakV;
      restGap = restGap == null ? g : restGap! * 0.9 + g * 0.1;
    }

    final now = DateTime.now();
    final pi = _prevI;
    final pt = _prevT;
    if (pi != null && pt != null && _prevIdx == w && now.difference(pt).inMilliseconds < 3000) {
      final dI = current - pi;
      if (dI.abs() > 4) {
        final rw = -(weakV - _prevWeak!) / dI;
        final ro = -(othersAvg - _prevOthers!) / dI;
        if (rw > 0 && rw < 0.3) {
          rWeak.add(rw);
          if (rWeak.length > 200) rWeak.removeAt(0);
        }
        if (ro > 0 && ro < 0.3) {
          rOthers.add(ro);
          if (rOthers.length > 200) rOthers.removeAt(0);
        }
      }
    }
    _prevI = current;
    _prevWeak = weakV;
    _prevOthers = othersAvg;
    _prevIdx = w;
    _prevT = now;
  }

  /// Ниже какого заряда (в %) слабая ячейка на сильном токе проседает до порога.
  double? cutoffPct() {
    final r = rWeakOhm;
    final ip = peakCurrent;
    if (r == null || ip == null || weakIndex == null) return null;
    final gap = restGap ?? 0;
    for (var s = 0.0; s <= 100; s += 0.5) {
      final v = EnergyMath.ocvAt(s) - gap - ip * r;
      if (v >= cutoffV) return s;
    }
    return 100;
  }

  Map<String, dynamic> toJson() => {
        'min': minCounts,
        'obs': observations,
        'gap': restGap,
        'rw': rWeak,
        'ro': rOthers,
        'ih': currentHist,
      };

  void loadJson(dynamic j) {
    if (j is! Map) return;
    final m = j['min'];
    if (m is List) minCounts = [for (final v in m) v is num ? v.toInt() : 0];
    observations = (j['obs'] as num?)?.toInt() ?? 0;
    restGap = (j['gap'] as num?)?.toDouble();
    final rw = j['rw'];
    if (rw is List) rWeak..clear()..addAll([for (final v in rw) if (v is num) v.toDouble()]);
    final ro = j['ro'];
    if (ro is List) rOthers..clear()..addAll([for (final v in ro) if (v is num) v.toDouble()]);
    final ih = j['ih'];
    if (ih is List) {
      for (var i = 0; i < ih.length && i < currentHist.length; i++) {
        final v = ih[i];
        currentHist[i] = v is num ? v.toInt() : 0;
      }
    }
  }
}
