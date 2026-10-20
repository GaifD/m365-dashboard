// «Мозг» приложения: учёт энергии, честный заряд, автоматические поездки,
// замер реальной ёмкости, учёт зарядок и пробега без записи.
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/models.dart';
import '../data/store.dart';

class _Slice {
  final double wh;
  final double km;
  final DateTime t;
  _Slice(this.wh, this.km, this.t);
}

class ActiveTrip {
  final DateTime start;
  DateTime lastMove;
  final double odoStart;
  double odoEnd;
  double kmBySpeed = 0;
  double wh = 0;
  double regen = 0;
  double ah = 0;
  double maxSpeed = 0;
  int movingSec = 0;
  final double? pctStart;
  double? minCell;
  final Map<String, int> modeSec = {};
  double gapKm = 0;
  final List<List<num>> samples = [];
  DateTime? suspendedAt;

  ActiveTrip(this.start, this.odoStart, this.pctStart)
      : lastMove = start,
        odoEnd = odoStart;

  double get km => (odoStart > 0 && odoEnd >= odoStart) ? odoEnd - odoStart : kmBySpeed;

  double? get avgWhKm {
    final e = km - gapKm;
    return e >= 0.2 ? wh / e : null;
  }

  double get avgSpeed => movingSec > 0 ? km / (movingSec / 3600.0) : 0;
}

class LiveCharge {
  final DateTime start;
  final double pctFrom;
  final int mahFrom;
  double wh = 0;
  double ah = 0;
  bool approx = false; // был кусок без связи, досчитан по току × время
  DateTime? suspendedAt; // связь пропала, запись ждёт продолжения
  LiveCharge(this.start, this.pctFrom, this.mahFrom);

  Map<String, dynamic> toJson() => {
        'start': start.millisecondsSinceEpoch,
        'p0': pctFrom,
        'mah0': mahFrom,
        'wh': wh,
        'ah': ah,
        'approx': approx,
        'susp': suspendedAt?.millisecondsSinceEpoch,
      };

  static LiveCharge? fromJson(dynamic j) {
    if (j is! Map || j['start'] is! num) return null;
    final lc = LiveCharge(
      DateTime.fromMillisecondsSinceEpoch((j['start'] as num).toInt()),
      (j['p0'] as num?)?.toDouble() ?? 0,
      (j['mah0'] as num?)?.toInt() ?? 0,
    );
    lc.wh = (j['wh'] as num?)?.toDouble() ?? 0;
    lc.ah = (j['ah'] as num?)?.toDouble() ?? 0;
    lc.approx = j['approx'] == true;
    final su = j['susp'];
    lc.suspendedAt = su is num ? DateTime.fromMillisecondsSinceEpoch(su.toInt()) : DateTime.now();
    return lc;
  }
}

double _r(double v, int digits) {
  final m = math.pow(10, digits);
  return (v * m).roundToDouble() / m;
}

double _median(List<double> v) {
  final s = [...v]..sort();
  final n = s.length;
  if (n == 0) return double.nan;
  return n.isOdd ? s[n ~/ 2] : (s[n ~/ 2 - 1] + s[n ~/ 2]) / 2;
}

class Brain extends ChangeNotifier {
  static const Duration restAfter = Duration(minutes: 15);
  static const Duration tripEndIdle = Duration(minutes: 3);
  static const Duration resumeWindow = Duration(minutes: 10);

  Store? _store;
  String? key;
  int factoryMah = 12800;
  double get factoryWh => factoryMah / 1000.0 * 36.0 * 1.03;

  // ---- выученное ----
  double? _whPerPctLearned;
  double? _kLearned;
  double get whPerPct => _whPerPctLearned ?? factoryWh / 100.0;
  double get kBms => _kLearned ?? 1.0;
  List<CapacitySample> capacity = [];

  // ---- история ----
  List<TripRecord> trips = [];
  List<ChargeRecord> charges = [];

  // ---- учёт ----
  double cumWh = 0;
  double cumAh = 0;
  double _attachWh = 0;
  double _attachAh = 0;
  Snapshot? lastSeen; // последнее известное состояние (для сравнения при подключении)
  Snapshot? socAnchor; // последнее состояние покоя — от него считается честный заряд
  Snapshot? capAnchor; // начало текущего замера ёмкости
  bool dirtyCap = false; // с начала замера было что-то неучтённое
  bool socValid = false;

  ActiveTrip? trip;
  LiveCharge? liveCharge;
  PendingUnrecorded? pendingUnrecorded;

  // ---- настройки ----
  double? tariff; // грн за кВт·ч
  double fallbackWhKm = 13.0;

  // ---- телеметрия ----
  bool connected = false;
  DateTime? _connectedAt;
  bool _needConnectCheck = false;
  double speed = 0;
  double odo = 0;
  int mode = -1;
  double voltage = 0;
  double current = 0;
  double power = 0;
  int mah = 0;
  double bmsPct = 0;
  double? minCell;
  int? chargeCount;

  DateTime? _lastBmsT;
  double _lastPower = 0;
  double _lastCurrent = 0;
  DateTime? _lastEscT;
  final List<_Slice> _window = [];
  DateTime? _quietSince;
  bool _anchoredThisQuiet = false;
  DateTime? _chargeSince;
  DateTime? _chargeEndSince;
  Timer? _timer;
  int _tick = 0;

  Future<void> init() async {
    final p = await SharedPreferences.getInstance();
    tariff = p.getDouble('tariff');
    fallbackWhKm = p.getDouble('avgWhKm') ?? 13.0;
  }

  Future<void> setTariff(double? v) async {
    tariff = v;
    final p = await SharedPreferences.getInstance();
    if (v == null) {
      await p.remove('tariff');
    } else {
      await p.setDouble('tariff', v);
    }
    notifyListeners();
  }

  // ================= подключение =================

  Future<void> attach(String deviceId) async {
    final k = deviceId.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
    if (key != k) {
      key = k;
      _store = await Store.open(k);
      await _load();
    }
    connected = true;
    _connectedAt = DateTime.now();
    _needConnectCheck = true;
    _lastBmsT = null;
    _lastEscT = null;
    _window.clear();
    _quietSince = null;
    _anchoredThisQuiet = false;
    _attachWh = cumWh;
    _attachAh = cumAh;
    bmsPct = 0;
    odo = 0;
    chargeCount = null;
    _timer ??= Timer.periodic(const Duration(seconds: 1), (_) => _onTick());
    notifyListeners();
  }

  void detach() {
    if (!connected) return;
    connected = false;
    final lc = liveCharge;
    if (lc != null) lc.suspendedAt = DateTime.now();
    final t = trip;
    if (t != null) t.suspendedAt = DateTime.now();
    if (!_needConnectCheck) lastSeen = _snap(false);
    speed = 0;
    _window.clear();
    _saveState();
    _checkpoint();
    notifyListeners();
  }

  /// Знак тока оказался перевёрнут — исправляем то, что успели насчитать с подключения.
  void onSignFlip() {
    cumWh = _attachWh - (cumWh - _attachWh);
    cumAh = _attachAh - (cumAh - _attachAh);
    final t = trip;
    if (t != null) {
      t.wh = -t.wh;
      t.ah = -t.ah;
      t.regen = 0;
    }
    _window.clear();
  }

  // ================= данные с самоката =================

  void onEsc(double v, double odoKm, int m) {
    final now = DateTime.now();
    final last = _lastEscT;
    _lastEscT = now;
    speed = v < 0 ? 0 : v;
    mode = m;
    if (odoKm > 0) odo = odoKm;
    final t = trip;
    if (t != null && t.suspendedAt == null) {
      if (odoKm > 0 && odoKm > t.odoEnd) t.odoEnd = odoKm;
      if (last != null) {
        final dt = now.difference(last).inMilliseconds / 1000.0;
        if (dt > 0 && dt < 10) t.kmBySpeed += speed * dt / 3600.0;
      }
      if (speed > t.maxSpeed) t.maxSpeed = speed;
    }
  }

  void onBms(double u, double i, int mahNow, int pct) {
    final now = DateTime.now();
    voltage = u;
    current = i;
    power = u * i;
    mah = mahNow;
    bmsPct = pct.toDouble();
    final last = _lastBmsT;
    _lastBmsT = now;
    if (last != null) {
      final dt = now.difference(last).inMilliseconds / 1000.0;
      if (dt > 0 && dt <= 10) {
        final p = (power + _lastPower) / 2;
        final ia = (i + _lastCurrent) / 2;
        final dWh = p * dt / 3600.0;
        final dAh = ia * dt / 3600.0;
        cumWh += dWh;
        cumAh += dAh;
        final t = trip;
        if (t != null && t.suspendedAt == null && !(speed < 0.5 && dWh < 0)) {
          t.wh += dWh;
          t.ah += dAh;
          if (dWh < 0) t.regen += -dWh;
        }
        final lc = liveCharge;
        if (lc != null && lc.suspendedAt == null) {
          lc.wh += -dWh;
          lc.ah += -dAh;
        }
        _window.add(_Slice(dWh, speed * dt / 3600.0, now));
        var wKm = _window.fold<double>(0, (a, s) => a + s.km);
        while (_window.length > 2 &&
            (wKm - _window.first.km >= 0.15 || now.difference(_window.first.t) > const Duration(seconds: 30))) {
          wKm -= _window.first.km;
          _window.removeAt(0);
        }
      } else if (dt > 10) {
        // Пропуск в учёте энергии: замер ёмкости и честный заряд до следующего покоя не точны.
        dirtyCap = true;
        final t = trip;
        if (t != null && t.suspendedAt == null) t.gapKm += speed * dt / 3600.0;
      }
    }
    _lastPower = power;
    _lastCurrent = i;
    _detectRestAndCharge(now);
  }

  void onFactoryMah(int v) {
    if (v > 1000) factoryMah = v;
  }

  // ================= производные =================

  /// Расход сейчас, сглаженный по ~150 м. На стоянке — null (прочерк).
  double? get instantWhKm {
    if (!connected || speed < 3) return null;
    final wKm = _window.fold<double>(0, (a, s) => a + s.km);
    if (wKm < 0.02) return null;
    return _window.fold<double>(0, (a, s) => a + s.wh) / wKm;
  }

  /// Заряд «как в покое»: от последнего состояния покоя минус то, что насчитано с тех пор.
  double? get honestPct {
    final a = socAnchor;
    if (a == null || !socValid) return bmsPct > 0 ? bmsPct : null;
    final mahPerPct = a.bmsPct > 5 ? a.mah / a.bmsPct : factoryMah / 100.0;
    final used = (cumAh - a.cumAh) * 1000.0 * kBms;
    return (a.bmsPct - used / mahPerPct).clamp(0.0, 100.0).toDouble();
  }

  bool get honestIsEstimated => socAnchor != null && socValid;

  double? get remainingWh {
    final p = honestPct;
    return p == null ? null : p * whPerPct;
  }

  /// Средний расход для прогноза: последние 5 записанных поездок от 1 км + текущая.
  double get rangeWhKm {
    var wh = 0.0;
    var km = 0.0;
    final t = trip;
    if (t != null && t.km - t.gapKm >= 1) {
      wh += t.wh;
      km += t.km - t.gapKm;
    }
    var n = 0;
    for (final r in trips) {
      if (!r.countsForStats) continue;
      wh += r.wh!;
      km += r.effKm;
      if (++n >= 5) break;
    }
    if (km < 1 || wh <= 0) return fallbackWhKm;
    return wh / km;
  }

  double? get rangeKm {
    final w = remainingWh;
    if (w == null) return null;
    return w / rangeWhKm;
  }

  // ---- ёмкость ----
  double? get capWh => capacity.isEmpty ? null : _median(capacity.map((c) => c.capWh).toList());
  double? get capMahBms => capacity.isEmpty ? null : _median(capacity.map((c) => c.capMahBms).toList());
  double? get capAhApp => capacity.isEmpty ? null : _median(capacity.map((c) => c.capAhApp).toList());

  // ---- зарядки ----
  double get monthWallKwh {
    final from = DateTime.now().subtract(const Duration(days: 30));
    return charges
            .where((c) => c.t.isAfter(from) && c.wallWh != null)
            .fold<double>(0, (a, c) => a + c.wallWh!) /
        1000.0;
  }

  double? get costPer100km {
    final tr = tariff;
    if (tr == null) return null;
    return rangeWhKm / ChargeRecord.chargerEfficiency * 100.0 / 1000.0 * tr;
  }

  // ================= логика =================

  Snapshot _snap(bool rested) => Snapshot(
        t: DateTime.now(),
        pct: honestPct ?? bmsPct,
        bmsPct: bmsPct,
        mah: mah,
        odo: odo,
        chargeCount: chargeCount,
        cumWh: cumWh,
        cumAh: cumAh,
        rested: rested,
      );

  void _detectRestAndCharge(DateTime now) {
    final quiet = current.abs() < 0.3 && speed < 0.5;
    if (quiet && !_needConnectCheck) {
      _quietSince ??= now;
      if (!_anchoredThisQuiet && now.difference(_quietSince!) >= restAfter) {
        _anchoredThisQuiet = true;
        _takeAnchor(now);
      }
    } else {
      _quietSince = null;
      _anchoredThisQuiet = false;
    }

    final charging = speed < 0.5 && current < -0.5;
    if (charging) {
      _chargeEndSince = null;
      _chargeSince ??= now;
      if (liveCharge == null && now.difference(_chargeSince!) >= const Duration(seconds: 30)) {
        liveCharge = LiveCharge(_chargeSince!, honestPct ?? bmsPct, mah);
        _saveState();
        notifyListeners();
      }
    } else {
      _chargeSince = null;
      if (liveCharge != null) {
        _chargeEndSince ??= now;
        if (now.difference(_chargeEndSince!) >= const Duration(seconds: 120)) _finishLiveCharge();
      }
    }
  }

  void _finishLiveCharge() {
    final lc = liveCharge;
    if (lc == null) return;
    liveCharge = null;
    _chargeEndSince = null;
    if (lc.wh < 2) return;
    charges.insert(
      0,
      ChargeRecord(
        t: lc.start,
        prevT: null,
        live: true,
        pctFrom: lc.pctFrom,
        pctTo: honestPct ?? bmsPct,
        batteryWh: lc.wh,
        count: 1,
        approx: lc.approx,
        durationSec: DateTime.now().difference(lc.start).inSeconds,
        ahApp: lc.ah,
        mahBms: mah - lc.mahFrom,
      ),
    );
    if (lc.approx) dirtyCap = true;
    _saveCharges();
    _saveState();
    notifyListeners();
  }

  /// Состояние покоя: пересинхронизация честного заряда и, если можно, замер ёмкости.
  void _takeAnchor(DateTime now) {
    final rested = Snapshot(
      t: now,
      pct: bmsPct,
      bmsPct: bmsPct,
      mah: mah,
      odo: odo,
      chargeCount: chargeCount,
      cumWh: cumWh,
      cumAh: cumAh,
      rested: true,
    );
    socAnchor = rested;
    socValid = true;

    final c = capAnchor;
    if (c == null || dirtyCap) {
      capAnchor = rested;
      dirtyCap = false;
    } else {
      // Между двумя состояниями покоя: сколько процентов ушло/пришло и сколько энергии
      // насчитал счётчик приложения (поездки и зарядки, записанные целиком).
      final dPct = c.bmsPct - bmsPct; // > 0 — разряд, < 0 — зарядка
      final wh = cumWh - c.cumWh;
      final ah = cumAh - c.cumAh;
      final dMah = (c.mah - mah).toDouble();
      if (dPct.abs() >= 15 && wh * dPct > 0 && ah * dPct > 0) {
        capacity.add(CapacitySample(
          t: now,
          dPct: dPct,
          capWh: wh / dPct * 100.0,
          capAhApp: ah / dPct * 100.0,
          capMahBms: dMah / dPct * 100.0,
          k: dMah / (ah * 1000.0),
        ));
        if (capacity.length > 30) capacity.removeAt(0);
        _relearn();
        capAnchor = rested;
      }
    }
    lastSeen = _snap(true);
    _saveState();
    notifyListeners();
  }

  void _relearn() {
    if (capacity.isEmpty) return;
    final wh = _median(capacity.map((c) => c.capWh).toList());
    if (wh.isFinite && wh > 50) _whPerPctLearned = wh / 100.0;
    final k = _median(capacity.map((c) => c.k).toList());
    if (k.isFinite) _kLearned = k.clamp(0.7, 1.5).toDouble();
  }

  /// Сравнение с прошлым подключением: зарядки, пробег без записи, покой.
  void _connectCheck() {
    _needConnectCheck = false;
    final now = DateTime.now();
    final prev = lastSeen;
    final chargingNow = current < -0.3 && speed < 0.5;
    final rested = (prev == null || now.difference(prev.t) >= restAfter) && current.abs() < 0.3;
    final odoDelta = (prev != null && prev.odo > 0 && odo > 0) ? odo - prev.odo : 0.0;

    // Зарядка, записанная до обрыва связи.
    final lc = liveCharge;
    var liveCovered = false;
    if (lc != null && lc.suspendedAt != null) {
      liveCovered = true;
      final gapH = now.difference(lc.suspendedAt!).inSeconds / 3600.0;
      if (chargingNow) {
        // Зарядка ещё идёт — продолжаем ту же запись, пропуск досчитываем по току × время.
        final gapAh = current.abs() * gapH;
        lc.ah += gapAh;
        lc.wh += gapAh * voltage;
        if (gapH > 0.01) lc.approx = true;
        lc.suspendedAt = null;
        lastSeen = _snap(false);
        _saveState();
        notifyListeners();
        return;
      }
      // Зарядка закончилась, пока связи не было: досчитываем по разнице процентов.
      final rise = bmsPct - (lc.pctFrom + lc.ah * 1000.0 * kBms / (lc.mahFrom > 0 && lc.pctFrom > 5 ? lc.mahFrom / lc.pctFrom : factoryMah / 100.0));
      if (rise > 0 && gapH > 0.01) {
        lc.wh += rise * whPerPct;
        lc.approx = true;
      }
      lc.suspendedAt = null;
      _finishLiveCharge();
    }

    // Продолжение прерванной поездки.
    final t = trip;
    if (t != null && t.suspendedAt != null) {
      if (now.difference(t.suspendedAt!) <= resumeWindow) {
        t.suspendedAt = null;
        if (odoDelta > 0.05) t.gapKm += odoDelta;
        lastSeen = _snap(false);
        _saveState();
        notifyListeners();
        return;
      }
      _finishTrip();
    }

    var charged = false;
    if (prev != null) {
      final cc = chargeCount;
      final pcc = prev.chargeCount;
      final dCount = (cc != null && pcc != null) ? cc - pcc : 0;
      final rise = bmsPct - prev.pct;
      if (!liveCovered && !chargingNow && (dCount > 0 || (rise >= 5 && mah - prev.mah > 500))) {
        charged = true;
        charges.insert(
          0,
          ChargeRecord(
            t: now,
            prevT: prev.t,
            live: false,
            pctFrom: prev.pct,
            pctTo: bmsPct,
            batteryWh: rise > 0 ? rise * whPerPct : null,
            count: dCount > 0 ? dCount : 1,
            approx: odoDelta > 0.2 || !rested,
            durationSec: null,
            ahApp: null,
            mahBms: null,
          ),
        );
        dirtyCap = true;
        _saveCharges();
      }
      if (odoDelta > 0.2) {
        final drop = prev.pct - bmsPct;
        pendingUnrecorded = PendingUnrecorded(
          km: odoDelta,
          from: prev.t,
          to: now,
          wh: (!charged && drop > 0) ? drop * whPerPct : null,
          odoStart: prev.odo,
          odoEnd: odo,
          pctFrom: prev.pct,
          pctTo: bmsPct,
        );
        dirtyCap = true;
      }
      if ((charged || odoDelta > 0.2) && !rested) socValid = false;
    }
    if (chargingNow && liveCharge == null) {
      liveCharge = LiveCharge(now, honestPct ?? bmsPct, mah);
      if (prev != null && bmsPct > prev.pct + 1) liveCharge!.approx = true;
    }
    if (rested) {
      _takeAnchor(now);
    } else {
      lastSeen = _snap(false);
      _saveState();
    }
    notifyListeners();
  }

  void resolveUnrecorded(bool add) {
    final p = pendingUnrecorded;
    pendingUnrecorded = null;
    if (p != null && add) {
      trips.add(TripRecord(
        id: 'u${p.to.millisecondsSinceEpoch}',
        start: p.from,
        end: p.to,
        km: p.km,
        movingSec: 0,
        maxSpeed: 0,
        wh: p.wh,
        regenWh: 0,
        ah: null,
        pctStart: p.pctFrom,
        pctEnd: p.pctTo,
        minCell: null,
        modeSec: const {},
        odoStart: p.odoStart,
        odoEnd: p.odoEnd,
        gapKm: 0,
        unrecorded: true,
        whApprox: true,
        hasSamples: false,
      ));
      trips.sort((a, b) => b.start.compareTo(a.start));
      _saveTrips();
    }
    notifyListeners();
  }

  void _onTick() {
    final now = DateTime.now();
    _tick++;
    if (connected &&
        _needConnectCheck &&
        bmsPct > 0 &&
        odo > 0 &&
        (chargeCount != null || now.difference(_connectedAt!) > const Duration(seconds: 8))) {
      _connectCheck();
    }

    final lcs = liveCharge;
    if (lcs != null && lcs.suspendedAt != null && now.difference(lcs.suspendedAt!) > const Duration(hours: 12)) {
      lcs.approx = true;
      lcs.suspendedAt = null;
      _finishLiveCharge();
    }
    final t = trip;
    if (t != null && t.suspendedAt != null) {
      if (now.difference(t.suspendedAt!) > resumeWindow) _finishTrip();
    } else if (connected && !_needConnectCheck) {
      if (t == null) {
        if (speed >= 3 && liveCharge == null) {
          trip = ActiveTrip(now, odo, honestPct);
          notifyListeners();
        }
      } else {
        t.samples.add([
          now.difference(t.start).inSeconds,
          _r(speed, 1),
          _r(power, 0),
          _r(voltage, 2),
          _r(minCell ?? 0, 3),
          mode,
          _r(t.wh, 2),
          _r(t.km, 3),
        ]);
        if (speed > 1) {
          t.movingSec++;
          t.lastMove = now;
          final k = '$mode';
          t.modeSec[k] = (t.modeSec[k] ?? 0) + 1;
          final mc = minCell;
          if (mc != null && mc > 1 && (t.minCell == null || mc < t.minCell!)) t.minCell = mc;
        }
        if (speed < 1 && now.difference(t.lastMove) >= tripEndIdle) {
          _finishTrip();
        } else if (_tick % 30 == 0) {
          _checkpoint();
        }
      }
    }
    if (connected && !_needConnectCheck && _tick % 30 == 0) {
      lastSeen = _snap(false);
      _saveState();
    }
  }

  TripRecord _recordFrom(ActiveTrip t, {required DateTime end}) => TripRecord(
        id: '${t.start.millisecondsSinceEpoch}',
        start: t.start,
        end: end,
        km: t.km,
        movingSec: t.movingSec,
        maxSpeed: t.maxSpeed,
        wh: t.wh,
        regenWh: t.regen,
        ah: t.ah,
        pctStart: t.pctStart,
        pctEnd: honestPct,
        minCell: t.minCell,
        modeSec: Map.of(t.modeSec),
        odoStart: t.odoStart,
        odoEnd: t.odoEnd,
        gapKm: t.gapKm,
        unrecorded: false,
        whApprox: false,
        hasSamples: true,
      );

  /// Завершить текущую поездку сейчас (кнопка).
  void finishTripNow() => _finishTrip();

  void _finishTrip() {
    final t = trip;
    if (t == null) return;
    trip = null;
    final s = _store;
    if (t.km < 0.1) {
      s?.delete('active_trip.json');
      notifyListeners();
      return;
    }
    final rec = _recordFrom(t, end: t.lastMove);
    trips.insert(0, rec);
    if (s != null) {
      s.writeJson('trips/${rec.id}.json', t.samples);
      s.delete('active_trip.json');
    }
    _saveTrips();
    _saveFallback();
    notifyListeners();
  }

  Future<void> _saveFallback() async {
    final a = rangeWhKm;
    if (a > 3 && a < 60) {
      fallbackWhKm = a;
      final p = await SharedPreferences.getInstance();
      await p.setDouble('avgWhKm', a);
    }
  }

  void _checkpoint() {
    final t = trip;
    final s = _store;
    if (t == null || s == null) return;
    s.writeJson('active_trip.json', {
      'trip': _recordFrom(t, end: t.lastMove).toJson(),
      'samples': t.samples,
    });
  }

  Future<List<List<num>>> loadSamples(TripRecord r) async {
    final s = _store;
    if (s == null || !r.hasSamples) return [];
    final raw = await s.readJson('trips/${r.id}.json');
    if (raw is! List) return [];
    return [
      for (final row in raw)
        if (row is List) [for (final v in row) v is num ? v : 0]
    ];
  }

  Future<void> deleteCharge(ChargeRecord c) async {
    charges.remove(c);
    await _saveCharges();
    notifyListeners();
  }

  Future<void> deleteTrip(TripRecord r) async {
    trips.removeWhere((x) => x.id == r.id);
    final s = _store;
    if (s != null) await s.delete('trips/${r.id}.json');
    _saveTrips();
    notifyListeners();
  }

  // ================= хранение =================

  Future<void> _load() async {
    final s = _store!;
    final st = await s.readJson('state.json');
    if (st is Map) {
      cumWh = st['cumWh'] is num ? (st['cumWh'] as num).toDouble() : 0;
      cumAh = st['cumAh'] is num ? (st['cumAh'] as num).toDouble() : 0;
      dirtyCap = st['dirtyCap'] == true;
      socValid = st['socValid'] == true;
      lastSeen = Snapshot.fromJson(st['lastSeen']);
      socAnchor = Snapshot.fromJson(st['socAnchor']);
      capAnchor = Snapshot.fromJson(st['capAnchor']);
      final cap = st['capacity'];
      capacity = cap is List ? cap.map(CapacitySample.fromJson).whereType<CapacitySample>().toList() : [];
      if (st['factoryMah'] is num) factoryMah = (st['factoryMah'] as num).toInt();
      liveCharge = LiveCharge.fromJson(st['liveCharge']);
      _relearn();
    } else {
      cumWh = 0;
      cumAh = 0;
      dirtyCap = false;
      socValid = false;
      lastSeen = null;
      socAnchor = null;
      capAnchor = null;
      capacity = [];
    }
    final tr = await s.readJson('trips.json');
    trips = tr is List ? tr.map(TripRecord.fromJson).whereType<TripRecord>().toList() : [];
    final ch = await s.readJson('charges.json');
    charges = ch is List ? ch.map(ChargeRecord.fromJson).whereType<ChargeRecord>().toList() : [];

    // Поездка, оставшаяся с прошлого запуска (приложение закрыли посреди поездки).
    final cp = await s.readJson('active_trip.json');
    if (cp is Map) {
      final rec = TripRecord.fromJson(cp['trip']);
      if (rec != null && rec.km >= 0.1 && !trips.any((x) => x.id == rec.id)) {
        trips.insert(0, rec);
        await s.writeJson('trips/${rec.id}.json', cp['samples'] is List ? cp['samples'] : []);
        await _saveTrips();
      }
      await s.delete('active_trip.json');
    }
    trips.sort((a, b) => b.start.compareTo(a.start));
  }

  Future<void> _saveState() async {
    final s = _store;
    if (s == null) return;
    await s.writeJson('state.json', {
      'cumWh': cumWh,
      'cumAh': cumAh,
      'dirtyCap': dirtyCap,
      'socValid': socValid,
      'lastSeen': lastSeen?.toJson(),
      'socAnchor': socAnchor?.toJson(),
      'capAnchor': capAnchor?.toJson(),
      'capacity': capacity.map((c) => c.toJson()).toList(),
      'factoryMah': factoryMah,
      'liveCharge': liveCharge?.toJson(),
    });
  }

  Future<void> _saveTrips() async {
    final s = _store;
    if (s == null) return;
    await s.writeJson('trips.json', trips.map((t) => t.toJson()).toList());
  }

  Future<void> _saveCharges() async {
    final s = _store;
    if (s == null) return;
    if (charges.length > 200) charges = charges.sublist(0, 200);
    await s.writeJson('charges.json', charges.map((c) => c.toJson()).toList());
  }
}
