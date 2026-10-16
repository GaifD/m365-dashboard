// Расчёты энергии: остаток Вт·ч по кривой напряжения ячеек, учёт поездки, Вт·ч/км.

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

class _Slice {
  final double wh;
  final double km;
  final DateTime t;
  _Slice(this.wh, this.km, this.t);
}

/// Учёт текущей поездки.
class TripTracker {
  DateTime started = DateTime.now();
  DateTime? _last;
  double km = 0;
  double whNet = 0; // потрачено минус рекуперация
  double whRegen = 0;
  double maxSpeed = 0;
  Duration moving = Duration.zero;

  final List<_Slice> _window = [];
  static const double _windowKm = 0.15;
  static const Duration _windowAge = Duration(seconds: 30);

  void reset() {
    started = DateTime.now();
    _last = null;
    km = 0;
    whNet = 0;
    whRegen = 0;
    maxSpeed = 0;
    moving = Duration.zero;
    _window.clear();
  }

  void pause() => _last = null;

  void update(DateTime t, double powerW, double speedKmh) {
    final last = _last;
    _last = t;
    if (last == null) return;
    final dtMs = t.difference(last).inMilliseconds;
    if (dtMs <= 0 || dtMs > 3000) return; // разрыв связи — не интегрируем
    final dt = dtMs / 1000.0;
    final v = speedKmh < 0 ? 0.0 : speedKmh;
    final dWh = powerW * dt / 3600.0;
    final dKm = v * dt / 3600.0;
    km += dKm;
    whNet += dWh;
    if (dWh < 0) whRegen += -dWh;
    if (v > maxSpeed) maxSpeed = v;
    if (v > 1) moving += Duration(milliseconds: dtMs);

    _window.add(_Slice(dWh, dKm, t));
    var wKm = _window.fold<double>(0, (a, s) => a + s.km);
    while (_window.length > 2 &&
        (wKm - _window.first.km >= _windowKm || t.difference(_window.first.t) > _windowAge)) {
      wKm -= _window.first.km;
      _window.removeAt(0);
    }
  }

  /// Мгновенный расход, сглаженный по последним ~150 м / 30 с.
  double? get instantWhKm {
    final wKm = _window.fold<double>(0, (a, s) => a + s.km);
    if (wKm < 0.02) return null;
    final wWh = _window.fold<double>(0, (a, s) => a + s.wh);
    return wWh / wKm;
  }

  double? get avgWhKm => km >= 0.2 ? whNet / km : null;

  double get avgSpeed => moving.inSeconds > 0 ? km / (moving.inSeconds / 3600.0) : 0;
}
