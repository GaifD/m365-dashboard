// Кривая напряжения ячейки (используется как запасной вариант оценки заряда).

class EnergyMath {
  // Типичная кривая напряжения покоя (OCV) ячейки NMC 18650: заряд % → вольты.
  static const List<double> _soc = [0, 5, 10, 20, 30, 40, 50, 60, 70, 80, 90, 100];
  static const List<double> _ocv = [3.00, 3.30, 3.45, 3.57, 3.64, 3.70, 3.75, 3.82, 3.90, 3.98, 4.07, 4.18];

  static const int cells = 10;

  static double ocvAt(double soc) {
    final s = soc.clamp(0.0, 100.0);
    for (var i = 1; i < _soc.length; i++) {
      if (s <= _soc[i]) {
        final t = (s - _soc[i - 1]) / (_soc[i] - _soc[i - 1]);
        return _ocv[i - 1] + t * (_ocv[i] - _ocv[i - 1]);
      }
    }
    return _ocv.last;
  }

  /// Заряд % по напряжению ячейки в покое.
  static double socFromCellVoltage(double v) {
    if (v <= _ocv.first) return 0;
    if (v >= _ocv.last) return 100;
    for (var i = 1; i < _ocv.length; i++) {
      if (v <= _ocv[i]) {
        final t = (v - _ocv[i - 1]) / (_ocv[i] - _ocv[i - 1]);
        return _soc[i - 1] + t * (_soc[i] - _soc[i - 1]);
      }
    }
    return 100;
  }

  /// Среднее напряжение батареи на отрезке от 0 до soc — по нему считаем остаток Вт·ч,
  /// а не по номинальным 36 В (иначе к концу разряда цифра «проваливается»).
  static double meanPackVoltage(double soc) {
    final s = soc.clamp(0.0, 100.0);
    if (s < 1) return _ocv.first * cells;
    final n = s.ceil();
    var sum = 0.0;
    for (var i = 0; i < n; i++) {
      sum += ocvAt((i + 0.5) * s / n);
    }
    return sum / n * cells;
  }

  static double remainingWh(int remainingMah, double socPct) =>
      remainingMah / 1000.0 * meanPackVoltage(socPct);
}
