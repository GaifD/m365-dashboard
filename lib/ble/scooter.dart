import 'dart:async';
import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../logic/energy.dart';
import 'protocol.dart';

enum LinkState { idle, scanning, connecting, connected }

class LogLine {
  final DateTime t;
  final String dir; // TX, RX, ** (событие)
  final String text;
  LogLine(this.dir, this.text) : t = DateTime.now();

  @override
  String toString() {
    final ts = '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:'
        '${t.second.toString().padLeft(2, '0')}.${(t.millisecond ~/ 10).toString().padLeft(2, '0')}';
    return '$ts $dir $text';
  }
}

class ScooterService extends ChangeNotifier {
  ScooterService._();
  static final ScooterService instance = ScooterService._();

  static final Guid _uartService = Guid('6e400001-b5a3-f393-e0a9-e50e24dcca9e');
  static final Guid _txUuid = Guid('6e400002-b5a3-f393-e0a9-e50e24dcca9e');
  static final Guid _rxUuid = Guid('6e400003-b5a3-f393-e0a9-e50e24dcca9e');

  static const int factoryMahDefault = 12800; // M365 Pro, родная батарея

  // ---- состояние связи ----
  LinkState link = LinkState.idle;
  String? deviceName;
  String? statusText;
  List<ScanResult> scanResults = [];
  bool noReply = false; // подключились, но самокат молчит — возможно, нужна авторизация

  // ---- контроллер ----
  double speed = 0; // км/ч
  int escBattery = 0;
  int errorCode = 0;
  int warningCode = 0;
  int mode = 0;
  double totalKm = 0;
  double frameTemp = 0;
  String? escFw;
  int? kers; // 0 слабая, 1 средняя, 2 сильная
  bool? cruise;
  bool? tailLight;

  // ---- BMS ----
  double voltage = 0;
  double current = 0; // А, + разряд, − заряд/рекуперация (после автоопределения знака)
  int remainingMah = 0;
  int bmsPct = 0;
  int temp1 = 0;
  int temp2 = 0;
  List<double> cells = [];
  String? bmsFw;
  int? factoryMah;
  int? cycles;
  int? chargeCount;
  DateTime? lastRx;

  // ---- расчёты ----
  final TripTracker trip = TripTracker();
  double savedAvgWhKm = 13.0; // средний расход прошлых поездок, для прогноза в начале
  int _currentSign = 1;
  int _signVotes = 0;

  double get power => voltage * current;
  int get batteryPct => bmsPct > 0 ? bmsPct : escBattery;
  double get remainingWh => EnergyMath.remainingWh(remainingMah, batteryPct.toDouble());
  int get capacityMah => factoryMah ?? factoryMahDefault;
  double get factoryWh => capacityMah / 1000.0 * 36.0 * 1.03; // ~474 Вт·ч для 12 800 мАч

  double get rangeWhKm {
    final a = trip.avgWhKm;
    if (a != null && trip.km >= 1.0 && a > 3) return a;
    return savedAvgWhKm;
  }

  double? get rangeKm => remainingMah > 0 ? remainingWh / rangeWhKm : null;

  double get cellSpread {
    final v = cells.where((c) => c > 1).toList();
    if (v.length < 2) return 0;
    v.sort();
    return v.last - v.first;
  }

  // ---- журнал ----
  final List<LogLine> log = [];
  static const int _logMax = 800;
  void _log(String dir, String text) {
    log.add(LogLine(dir, text));
    if (log.length > _logMax) log.removeRange(0, log.length - _logMax);
  }

  void clearLog() {
    log.clear();
    notifyListeners();
  }

  // ---- BLE ----
  BluetoothDevice? _device;
  BluetoothCharacteristic? _tx;
  StreamSubscription<List<ScanResult>>? _scanSub;
  StreamSubscription<BluetoothConnectionState>? _connSub;
  StreamSubscription<List<int>>? _rxSub;
  Timer? _poll;
  int _pollStep = 0;
  final List<Uint8List> _oneShot = [];
  final FrameParser _parser = FrameParser();
  bool _userDisconnect = false;

  Future<void> init() async {
    final p = await SharedPreferences.getInstance();
    savedAvgWhKm = p.getDouble('avgWhKm') ?? 13.0;
    final last = p.getString('lastDevice');
    final lastName = p.getString('lastDeviceName');
    if (last != null) {
      // Пробуем сразу подключиться к прошлому самокату.
      unawaited(connect(BluetoothDevice.fromId(last), name: lastName));
    }
  }

  Future<bool> _ensurePermissions() async {
    if (!Platform.isAndroid) return true;
    final res = await [Permission.bluetoothScan, Permission.bluetoothConnect].request();
    final ok = res.values.every((s) => s.isGranted || s.isLimited);
    if (!ok) {
      statusText = 'Нет разрешения на Bluetooth — разреши в настройках приложения';
      notifyListeners();
      return false;
    }
    final st = await FlutterBluePlus.adapterState
        .where((s) => s != BluetoothAdapterState.unknown)
        .first
        .timeout(const Duration(seconds: 3), onTimeout: () => BluetoothAdapterState.unknown);
    if (st != BluetoothAdapterState.on) {
      try {
        await FlutterBluePlus.turnOn();
      } catch (_) {
        statusText = 'Включи Bluetooth';
        notifyListeners();
        return false;
      }
    }
    return true;
  }

  Future<void> startScan() async {
    if (link == LinkState.connected || link == LinkState.connecting) return;
    if (!await _ensurePermissions()) return;
    scanResults = [];
    link = LinkState.scanning;
    statusText = 'Ищу самокат…';
    notifyListeners();
    await _scanSub?.cancel();
    _scanSub = FlutterBluePlus.scanResults.listen((list) {
      final named = list.where((r) => _nameOf(r).isNotEmpty).toList()
        ..sort((a, b) {
          final sa = _isScooter(a) ? 0 : 1;
          final sb = _isScooter(b) ? 0 : 1;
          if (sa != sb) return sa - sb;
          return b.rssi - a.rssi;
        });
      scanResults = named;
      notifyListeners();
    });
    try {
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 10));
      await FlutterBluePlus.isScanning.where((s) => s == false).first;
    } catch (e) {
      statusText = 'Ошибка поиска: $e';
    }
    if (link == LinkState.scanning) {
      link = LinkState.idle;
      statusText = scanResults.isEmpty ? 'Ничего не найдено. Самокат включён?' : null;
      notifyListeners();
    }
  }

  static String _nameOf(ScanResult r) =>
      r.advertisementData.advName.isNotEmpty ? r.advertisementData.advName : r.device.platformName;

  static bool _isScooter(ScanResult r) => _nameOf(r).toLowerCase().contains('scooter');

  static String nameOf(ScanResult r) => _nameOf(r);
  static bool isScooter(ScanResult r) => _isScooter(r);

  Future<void> connect(BluetoothDevice d, {String? name}) async {
    if (link == LinkState.connected || link == LinkState.connecting) return;
    if (!await _ensurePermissions()) return;
    try {
      await FlutterBluePlus.stopScan();
    } catch (_) {}
    _userDisconnect = false;
    _device = d;
    deviceName = name ?? (d.platformName.isNotEmpty ? d.platformName : d.remoteId.str);
    link = LinkState.connecting;
    statusText = 'Подключаюсь к $deviceName…';
    noReply = false;
    _log('**', 'connect ${d.remoteId.str} $deviceName');
    notifyListeners();
    try {
      await _connSub?.cancel();
      _connSub = d.connectionState.listen((s) {
        if (s == BluetoothConnectionState.disconnected && link == LinkState.connected) {
          _onDisconnected();
        }
      });
      await d.connect(timeout: const Duration(seconds: 15), autoConnect: false);
      final services = await d.discoverServices();
      BluetoothCharacteristic? tx;
      BluetoothCharacteristic? rx;
      for (final s in services) {
        _log('**', 'service ${s.serviceUuid.str}');
        if (s.serviceUuid != _uartService) continue;
        for (final c in s.characteristics) {
          if (c.characteristicUuid == _txUuid) tx = c;
          if (c.characteristicUuid == _rxUuid) rx = c;
        }
      }
      if (tx == null || rx == null) {
        throw StateError('UART-сервис не найден');
      }
      _tx = tx;
      await rx.setNotifyValue(true);
      await _rxSub?.cancel();
      _rxSub = rx.onValueReceived.listen(_onData);
      d.cancelWhenDisconnected(_rxSub!);

      final p = await SharedPreferences.getInstance();
      await p.setString('lastDevice', d.remoteId.str);
      await p.setString('lastDeviceName', deviceName ?? '');

      link = LinkState.connected;
      statusText = null;
      _parser.reset();
      trip.pause();
      _queueOneShots();
      _startPolling();
      try {
        await WakelockPlus.enable();
      } catch (_) {}
      _log('**', 'connected');
      notifyListeners();
    } catch (e) {
      _log('**', 'connect error: $e');
      statusText = 'Не удалось подключиться: $e';
      link = LinkState.idle;
      try {
        await d.disconnect();
      } catch (_) {}
      notifyListeners();
    }
  }

  Future<void> disconnect() async {
    _userDisconnect = true;
    _stopPolling();
    try {
      await _device?.disconnect();
    } catch (_) {}
    await _onDisconnected();
  }

  Future<void> _onDisconnected() async {
    _stopPolling();
    _log('**', 'disconnected');
    link = LinkState.idle;
    speed = 0;
    trip.pause();
    try {
      await WakelockPlus.disable();
    } catch (_) {}
    await _saveAvg();
    notifyListeners();
    if (!_userDisconnect && _device != null) {
      // Связь потерялась сама — пробуем вернуться.
      final d = _device!;
      Future.delayed(const Duration(seconds: 2), () {
        if (link == LinkState.idle && !_userDisconnect) connect(d, name: deviceName);
      });
    }
  }

  Future<void> _saveAvg() async {
    final a = trip.avgWhKm;
    if (a != null && trip.km >= 1.0 && a > 3 && a < 60) {
      savedAvgWhKm = savedAvgWhKm * 0.6 + a * 0.4;
      final p = await SharedPreferences.getInstance();
      await p.setDouble('avgWhKm', savedAvgWhKm);
    }
  }

  void newTrip() {
    _saveAvg();
    trip.reset();
    notifyListeners();
  }

  // ---- опрос ----
  void _queueOneShots() {
    _oneShot
      ..clear()
      ..addAll([
        readRequest(Addr.esc, 0x1A, 2), // прошивка контроллера
        readRequest(Addr.bms, 0x17, 2), // прошивка BMS
        readRequest(Addr.bms, 0x18, 2), // заводская ёмкость, мАч
        readRequest(Addr.bms, 0x1B, 4), // циклы, количество зарядок
        readRequest(Addr.esc, 0x7B, 6), // рекуперация, круиз, фонарь
      ]);
  }

  void _startPolling() {
    _stopPolling();
    _pollStep = 0;
    final connectedAt = DateTime.now();
    _poll = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (link != LinkState.connected) return;
      Uint8List req;
      if (_oneShot.isNotEmpty && _pollStep % 4 == 3) {
        req = _oneShot.removeAt(0);
      } else {
        switch (_pollStep % 4) {
          case 0:
          case 2:
            req = readRequest(Addr.esc, 0xB0, 0x20);
            break;
          case 1:
            req = readRequest(Addr.bms, 0x31, 0x0A);
            break;
          default:
            req = readRequest(Addr.bms, 0x40, 0x14);
        }
      }
      _pollStep++;
      _send(req);
      final silentFor = DateTime.now().difference(lastRx ?? connectedAt);
      final nr = silentFor > const Duration(seconds: 5);
      if (nr != noReply) {
        noReply = nr;
        if (nr) _log('**', 'нет ответов 5 с — возможно, нужна авторизация (шифрованный протокол)');
        notifyListeners();
      }
    });
  }

  void _stopPolling() {
    _poll?.cancel();
    _poll = null;
  }

  Future<void> _send(Uint8List bytes) async {
    final tx = _tx;
    if (tx == null) return;
    _log('TX', toHex(bytes));
    try {
      await tx.write(bytes, withoutResponse: tx.properties.writeWithoutResponse);
    } catch (e) {
      _log('**', 'write error: $e');
    }
  }

  // ---- управление ----
  Future<void> setKers(int level) async {
    await _send(writeRequest(Addr.esc, 0x7B, level));
    kers = level;
    _oneShot.add(readRequest(Addr.esc, 0x7B, 6));
    notifyListeners();
  }

  Future<void> setCruise(bool on) async {
    await _send(writeRequest(Addr.esc, 0x7C, on ? 1 : 0));
    cruise = on;
    _oneShot.add(readRequest(Addr.esc, 0x7B, 6));
    notifyListeners();
  }

  Future<void> setTailLight(bool on) async {
    await _send(writeRequest(Addr.esc, 0x7D, on ? 2 : 0));
    tailLight = on;
    _oneShot.add(readRequest(Addr.esc, 0x7B, 6));
    notifyListeners();
  }

  Future<void> lock() => _send(writeRequest(Addr.esc, 0x70, 1));
  Future<void> unlock() => _send(writeRequest(Addr.esc, 0x71, 1));

  // ---- разбор ответов ----
  void _onData(List<int> chunk) {
    _log('RX', toHex(chunk));
    final frames = _parser.feed(chunk);
    if (frames.isEmpty) return;
    lastRx = DateTime.now();
    for (final f in frames) {
      try {
        if (f.addr == Addr.escReply) {
          _handleEsc(f);
        } else if (f.addr == Addr.bmsReply) {
          _handleBms(f);
        }
      } catch (e) {
        _log('**', 'parse error arg=${f.arg.toRadixString(16)}: $e');
      }
    }
    notifyListeners();
  }

  void _handleEsc(NbFrame f) {
    final d = f.data;
    switch (f.arg) {
      case 0xB0:
        if (d.length < 24) return;
        errorCode = u16(d, 0);
        warningCode = u16(d, 2);
        mode = u16(d, 6);
        escBattery = u16(d, 8);
        speed = s16(d, 10) / 1000.0;
        totalKm = (u16(d, 14) | (u16(d, 16) << 16)) / 1000.0;
        frameTemp = s16(d, 22) / 10.0;
        break;
      case 0x1A:
        if (d.length >= 2) escFw = fwString(u16(d, 0));
        break;
      case 0x7B:
        if (d.length >= 2) kers = u16(d, 0);
        if (d.length >= 4) cruise = u16(d, 2) != 0;
        if (d.length >= 6) tailLight = u16(d, 4) != 0;
        break;
    }
  }

  void _handleBms(NbFrame f) {
    final d = f.data;
    switch (f.arg) {
      case 0x31:
        if (d.length < 10) return;
        remainingMah = u16(d, 0);
        bmsPct = u16(d, 2);
        final rawCurrent = s16(d, 4) / 100.0;
        voltage = u16(d, 6) / 100.0;
        temp1 = d[8] - 20;
        temp2 = d[9] - 20;
        _detectSign(rawCurrent);
        current = rawCurrent * _currentSign;
        trip.update(DateTime.now(), power, speed);
        break;
      case 0x40:
        final n = (d.length ~/ 2).clamp(0, 10);
        cells = [for (var i = 0; i < n; i++) u16(d, i * 2) / 1000.0].where((v) => v > 1).toList();
        break;
      case 0x17:
        if (d.length >= 2) bmsFw = fwString(u16(d, 0));
        break;
      case 0x18:
        if (d.length >= 2) {
          final v = u16(d, 0);
          if (v > 1000) factoryMah = v;
        }
        break;
      case 0x1B:
        if (d.length >= 2) cycles = u16(d, 0);
        if (d.length >= 4) chargeCount = u16(d, 2);
        break;
    }
  }

  /// На ходу ток в основном тянет из батареи. Если при движении он почти всегда
  /// отрицательный — значит у этой BMS знак обратный, переворачиваем.
  void _detectSign(double raw) {
    if (speed < 8 || raw.abs() < 1.5) return;
    _signVotes += raw * _currentSign > 0 ? 1 : -1;
    _signVotes = _signVotes.clamp(-30, 30);
    if (_signVotes <= -20) {
      _currentSign = -_currentSign;
      _signVotes = 0;
      _log('**', 'знак тока перевёрнут');
    }
  }
}
