// Модели данных, которые приложение хранит между запусками.

double _d(dynamic v, [double def = 0]) => v is num ? v.toDouble() : def;
double? _dn(dynamic v) => v is num ? v.toDouble() : null;
int? _in(dynamic v) => v is num ? v.toInt() : null;
DateTime _t(dynamic v) => DateTime.fromMillisecondsSinceEpoch(v is num ? v.toInt() : 0);

/// Состояние батареи в момент времени.
class Snapshot {
  final DateTime t;
  final double pct; // честный заряд (как в покое)
  final double bmsPct; // что показывала BMS
  final int mah;
  final double odo; // км
  final int? chargeCount;
  final double cumWh; // накопленный счётчик энергии приложения
  final double cumAh;
  final bool rested;

  const Snapshot({
    required this.t,
    required this.pct,
    required this.bmsPct,
    required this.mah,
    required this.odo,
    required this.chargeCount,
    required this.cumWh,
    required this.cumAh,
    required this.rested,
  });

  Map<String, dynamic> toJson() => {
        't': t.millisecondsSinceEpoch,
        'pct': pct,
        'bmsPct': bmsPct,
        'mah': mah,
        'odo': odo,
        'cc': chargeCount,
        'cumWh': cumWh,
        'cumAh': cumAh,
        'rested': rested,
      };

  static Snapshot? fromJson(dynamic j) {
    if (j is! Map) return null;
    return Snapshot(
      t: _t(j['t']),
      pct: _d(j['pct']),
      bmsPct: _d(j['bmsPct']),
      mah: _in(j['mah']) ?? 0,
      odo: _d(j['odo']),
      chargeCount: _in(j['cc']),
      cumWh: _d(j['cumWh']),
      cumAh: _d(j['cumAh']),
      rested: j['rested'] == true,
    );
  }
}

class TripRecord {
  final String id;
  final DateTime start;
  final DateTime end;
  final double km;
  final int movingSec;
  final double maxSpeed;
  final double? wh; // потрачено (нетто), null — неизвестно
  final double regenWh;
  final double? ah;
  final double? pctStart;
  final double? pctEnd;
  final double? minCell;
  final Map<String, int> modeSec; // код режима → секунды в движении
  final double odoStart;
  final double odoEnd;
  final double gapKm; // км, проеханные без связи внутри поездки
  final bool unrecorded; // поездка без приложения (по одометру)
  final bool whApprox;
  final bool hasSamples;
  final int ver; // 2+ — режим записан из регистра 0x75 (раньше режим был неверный)
  final int? smooth; // плавность 0..100
  final int? hardStarts; // резких стартов
  final double? hardWh; // энергия на резких разгонах

  const TripRecord({
    required this.id,
    required this.start,
    required this.end,
    required this.km,
    required this.movingSec,
    required this.maxSpeed,
    required this.wh,
    required this.regenWh,
    required this.ah,
    required this.pctStart,
    required this.pctEnd,
    required this.minCell,
    required this.modeSec,
    required this.odoStart,
    required this.odoEnd,
    required this.gapKm,
    required this.unrecorded,
    required this.whApprox,
    required this.hasSamples,
    this.ver = 1,
    this.smooth,
    this.hardStarts,
    this.hardWh,
  });

  bool get modeOk => ver >= 2;

  double get effKm => km - gapKm;

  double? get avgWhKm {
    final w = wh;
    if (w == null || effKm < 0.2) return null;
    return w / effKm;
  }

  double? get avgSpeed => movingSec > 0 ? km / (movingSec / 3600.0) : null;

  /// Входит ли поездка в средний расход, прогноз и замер ёмкости.
  bool get countsForStats => !unrecorded && wh != null && effKm >= 1.0;

  Map<String, dynamic> toJson() => {
        'id': id,
        'start': start.millisecondsSinceEpoch,
        'end': end.millisecondsSinceEpoch,
        'km': km,
        'mov': movingSec,
        'vmax': maxSpeed,
        'wh': wh,
        'regen': regenWh,
        'ah': ah,
        'p0': pctStart,
        'p1': pctEnd,
        'cmin': minCell,
        'modes': modeSec,
        'o0': odoStart,
        'o1': odoEnd,
        'gap': gapKm,
        'unrec': unrecorded,
        'approx': whApprox,
        'samples': hasSamples,
        'ver': ver,
        'smooth': smooth,
        'hard': hardStarts,
        'hardWh': hardWh,
      };

  static TripRecord? fromJson(dynamic j) {
    if (j is! Map) return null;
    final m = <String, int>{};
    final raw = j['modes'];
    if (raw is Map) {
      raw.forEach((k, v) {
        if (v is num) m['$k'] = v.toInt();
      });
    }
    return TripRecord(
      id: '${j['id']}',
      start: _t(j['start']),
      end: _t(j['end']),
      km: _d(j['km']),
      movingSec: _in(j['mov']) ?? 0,
      maxSpeed: _d(j['vmax']),
      wh: _dn(j['wh']),
      regenWh: _d(j['regen']),
      ah: _dn(j['ah']),
      pctStart: _dn(j['p0']),
      pctEnd: _dn(j['p1']),
      minCell: _dn(j['cmin']),
      modeSec: m,
      odoStart: _d(j['o0']),
      odoEnd: _d(j['o1']),
      gapKm: _d(j['gap']),
      unrecorded: j['unrec'] == true,
      whApprox: j['approx'] == true,
      hasSamples: j['samples'] == true,
      ver: _in(j['ver']) ?? 1,
      smooth: _in(j['smooth']),
      hardStarts: _in(j['hard']),
      hardWh: _dn(j['hardWh']),
    );
  }
}

class ChargeRecord {
  static const double chargerEfficiency = 0.87;

  final DateTime t; // когда обнаружена / начата
  final DateTime? prevT; // для зарядок между подключениями: последнее подключение до неё
  final bool live; // записана при подключённом телефоне
  final double pctFrom;
  final double pctTo;
  final double? batteryWh; // вошло в батарею
  final int count;
  final bool approx;
  final int? durationSec;
  final double? ahApp; // по счётчику приложения (только live)
  final int? mahBms; // по счётчику BMS (только live)

  const ChargeRecord({
    required this.t,
    required this.prevT,
    required this.live,
    required this.pctFrom,
    required this.pctTo,
    required this.batteryWh,
    required this.count,
    required this.approx,
    required this.durationSec,
    required this.ahApp,
    required this.mahBms,
  });

  double? get wallWh => batteryWh == null ? null : batteryWh! / chargerEfficiency;

  Map<String, dynamic> toJson() => {
        't': t.millisecondsSinceEpoch,
        'prev': prevT?.millisecondsSinceEpoch,
        'live': live,
        'p0': pctFrom,
        'p1': pctTo,
        'wh': batteryWh,
        'n': count,
        'approx': approx,
        'dur': durationSec,
        'ah': ahApp,
        'mah': mahBms,
      };

  static ChargeRecord? fromJson(dynamic j) {
    if (j is! Map) return null;
    return ChargeRecord(
      t: _t(j['t']),
      prevT: j['prev'] is num ? _t(j['prev']) : null,
      live: j['live'] == true,
      pctFrom: _d(j['p0']),
      pctTo: _d(j['p1']),
      batteryWh: _dn(j['wh']),
      count: _in(j['n']) ?? 1,
      approx: j['approx'] == true,
      durationSec: _in(j['dur']),
      ahApp: _dn(j['ah']),
      mahBms: _in(j['mah']),
    );
  }
}

/// Один замер реальной ёмкости между двумя состояниями покоя.
class CapacitySample {
  final DateTime t;
  final double dPct;
  final double capWh; // по счётчику приложения
  final double capAhApp;
  final double capMahBms; // по счётчику BMS
  final double k; // мАч BMS / мАч приложения

  const CapacitySample({
    required this.t,
    required this.dPct,
    required this.capWh,
    required this.capAhApp,
    required this.capMahBms,
    required this.k,
  });

  Map<String, dynamic> toJson() => {
        't': t.millisecondsSinceEpoch,
        'dp': dPct,
        'wh': capWh,
        'ah': capAhApp,
        'mah': capMahBms,
        'k': k,
      };

  static CapacitySample? fromJson(dynamic j) {
    if (j is! Map) return null;
    return CapacitySample(
      t: _t(j['t']),
      dPct: _d(j['dp']),
      capWh: _d(j['wh']),
      capAhApp: _d(j['ah']),
      capMahBms: _d(j['mah']),
      k: _d(j['k'], 1),
    );
  }
}

/// Пробег, найденный по одометру, который приложение не записывало.
class PendingUnrecorded {
  final double km;
  final DateTime from;
  final DateTime to;
  final double? wh;
  final double odoStart;
  final double odoEnd;
  final double pctFrom;
  final double pctTo;

  const PendingUnrecorded({
    required this.km,
    required this.from,
    required this.to,
    required this.wh,
    required this.odoStart,
    required this.odoEnd,
    required this.pctFrom,
    required this.pctTo,
  });
}
