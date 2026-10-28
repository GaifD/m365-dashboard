// Аналитика по записанным поездкам: расход по скоростям и режимам, плавность.
//
// Строка сэмпла поездки: [t, скорость, мощность, напряжение, мин.ячейка, режим, Вт·ч, км]

class BinCell {
  double wh = 0;
  double km = 0;
  double? get whKm => km >= 1.0 ? wh / km : null;
}

class SpeedTable {
  /// Границы диапазонов скорости, км/ч.
  static const List<double> edges = [3, 10, 15, 20, 25, 100];
  static const List<String> labels = ['до 10', '10–15', '15–20', '20–25', '25+'];

  /// Ключ: 'all' или код режима '0' драйв, '1' эко, '2' спорт.
  final Map<String, List<BinCell>> cells = {
    for (final k in ['all', '1', '0', '2']) k: List.generate(labels.length, (_) => BinCell()),
  };
  int trips = 0;
  int tripsWithMode = 0;

  static int? binOf(double v) {
    for (var i = 0; i < labels.length; i++) {
      if (v >= edges[i] && v < edges[i + 1]) return i;
    }
    return null;
  }

  void addTrip(List<List<num>> s, {required bool modeOk}) {
    if (s.length < 2) return;
    trips++;
    if (modeOk) tripsWithMode++;
    for (var i = 1; i < s.length; i++) {
      final dKm = s[i][7].toDouble() - s[i - 1][7].toDouble();
      final dWh = s[i][6].toDouble() - s[i - 1][6].toDouble();
      if (dKm <= 0 || dKm > 0.05) continue;
      final v = (s[i][1].toDouble() + s[i - 1][1].toDouble()) / 2;
      final b = binOf(v);
      if (b == null) continue;
      cells['all']![b]
        ..wh += dWh
        ..km += dKm;
      if (modeOk) {
        final m = s[i][5].toInt();
        final list = cells['$m'];
        if (list != null) {
          list[b]
            ..wh += dWh
            ..km += dKm;
        }
      }
    }
  }

  /// Самый экономный диапазон по всем поездкам.
  int? get bestBin {
    int? best;
    for (var i = 0; i < labels.length; i++) {
      final v = cells['all']![i].whKm;
      if (v == null) continue;
      if (best == null || v < cells['all']![best].whKm!) best = i;
    }
    return best;
  }

  /// Максимальная скорость (верхняя граница диапазона), при которой хватит [availWh] на [km].
  /// null — данных нет; -1 — не хватит ни на какой скорости.
  int? maxSpeedFor(double km, double availWh) {
    int? ans;
    var any = false;
    for (var i = 0; i < labels.length; i++) {
      final v = cells['all']![i].whKm;
      if (v == null) continue;
      any = true;
      if (v * km <= availWh) ans = i;
    }
    if (!any) return null;
    return ans ?? -1;
  }
}

class Smoothness {
  final int score;
  final int hardStarts;
  final double hardWh;
  Smoothness(this.score, this.hardStarts, this.hardWh);

  static const double hardPowerW = 450;

  static Smoothness? of(List<List<num>> s) {
    if (s.length < 30) return null;
    var pos = 0.0;
    var hard = 0.0;
    var starts = 0;
    var cooldown = 0;
    for (var i = 1; i < s.length; i++) {
      final dWh = s[i][6].toDouble() - s[i - 1][6].toDouble();
      final p = s[i][2].toDouble();
      if (dWh > 0) {
        pos += dWh;
        if (p > hardPowerW) hard += dWh;
      }
      if (cooldown > 0) {
        cooldown--;
        continue;
      }
      // резкий старт: с места (<8 км/ч) +10 км/ч за 4 секунды
      if (s[i][1] < 8 && i + 4 < s.length && s[i + 4][1] - s[i][1] >= 10) {
        starts++;
        cooldown = 8;
      }
    }
    if (pos <= 1) return null;
    final score = (100 * (1 - hard / pos)).round().clamp(0, 100);
    return Smoothness(score, starts, hard);
  }
}
