import 'dart:async';
import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../logic/brain.dart';
import '../platform/system.dart';
import 'miauth.dart';
import 'micrypto.dart';
import 'protocol.dart';

enum LinkState { idle, scanning, connecting, connected }

/// Состояние шифрования/авторизации.
enum AuthState { unknown, plain, loggingIn, ready, needRegister, registering, failed }

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

class _Need {
  final Uint8List req;
  int tries = 0;
  _Need(this.req);
}

class ScooterService extends ChangeNotifier {
  ScooterService._() {
    _parser.decryptor = (frame) {
      final k = _keys;
      if (k == null) return null;
      return MiCrypto.decryptUart(k.devKey, k.devIv, frame);
    };
    _parser.onError = (e) => _log('**', e);
  }
  static final ScooterService instance = ScooterService._();

  static const String _uartService = '6e400001-b5a3-f393-e0a9-e50e24dcca9e';
  static const String _txUuid = '6e400002-b5a3-f393-e0a9-e50e24dcca9e';
  static const String _rxUuid = '6e400003-b5a3-f393-e0a9-e50e24dcca9e';
  static const String _authService = '0000fe95-0000-1000-8000-00805f9b34fb';
  static const String _upnpUuid = '00000010-0000-1000-8000-00805f9b34fb';
  static const String _avdtpUuid = '00000019-0000-1000-8000-00805f9b34fb';

  static const int factoryMahDefault = 12800; // M365 Pro, родная батарея

  final Brain brain = Brain();

  // ---- состояние связи ----
  LinkState link = LinkState.idle;
  AuthState auth = AuthState.unknown;
  String? authStatus;
  String? deviceName;
  String? statusText;
  List<ScanResult> scanResults = [];
  bool noReply = false;

  // ---- настройки приложения ----
  bool keepScreenOn = false;
  bool batteryOptimizationOff = true;

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

  int _currentSign = 1;
  int _signVotes = 0;

  double get power => voltage * current;

  /// Заряд для показа: честный («как в покое»), если известен.
  int get batteryPct {
    final h = brain.honestPct;
    if (h != null) return h.round();
    return bmsPct > 0 ? bmsPct : escBattery;
  }

  int get capacityMah => factoryMah ?? factoryMahDefault;
  double get factoryWh => capacityMah / 1000.0 * 36.0 * 1.03; // ~474 Вт·ч для 12 800 мАч

  double get cellSpread {
    final v = cells.where((c) => c > 1).toList();
    if (v.length < 2) return 0;
    v.sort();
    return v.last - v.first;
  }

  bool get dataFlowing => link == LinkState.connected && (auth == AuthState.plain || auth == AuthState.ready);

  // ---- журнал ----
  final List<LogLine> log = [];
  static const int _logMax = 1200;
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
  BluetoothCharacteristic? _upnp;
  BluetoothCharacteristic? _avdtp;
  final List<StreamSubscription> _subs = [];
  StreamSubscription<List<ScanResult>>? _scanSub;
  StreamSubscription<BluetoothConnectionState>? _connSub;
  final FrameParser _parser = FrameParser();
  bool _userDisconnect = false;
  bool _quietReconnect = false;
  bool _wasConnected = false;
  DateTime? _disconnectedAt;
  Timer? _notifTimer;
  MiAuth? _miAuth;
  MiKeys? _keys;
  int _uartIt = 0;
  int _pollGen = 0;
  int _pollStep = 0;
  final Map<String, _Need> _needs = {};
  int _needCursor = 0;
  DateTime _lastChargeCountReq = DateTime.fromMillisecondsSinceEpoch(0);
  Completer<void>? _pending;

  Future<void> init() async {
    final p = await SharedPreferences.getInstance();
    keepScreenOn = p.getBool('keepScreenOn') ?? false;
    await brain.init();
    await refreshBatteryOptimization();
    final last = p.getString('lastDevice');
    final lastName = p.getString('lastDeviceName');
    if (last != null) {
      unawaited(connect(BluetoothDevice.fromId(last), name: lastName));
    }
  }

  Future<void> setKeepScreenOn(bool on) async {
    keepScreenOn = on;
    final p = await SharedPreferences.getInstance();
    await p.setBool('keepScreenOn', on);
    try {
      if (on && link == LinkState.connected) {
        await WakelockPlus.enable();
      } else {
        await WakelockPlus.disable();
      }
    } catch (_) {}
    notifyListeners();
  }

  Future<void> refreshBatteryOptimization() async {
    if (!Platform.isAndroid) return;
    batteryOptimizationOff = await SystemBridge.isIgnoringBatteryOptimizations();
    notifyListeners();
  }

  Future<void> requestBatteryOptimizationOff() async {
    await SystemBridge.requestIgnoreBatteryOptimizations();
    await Future.delayed(const Duration(seconds: 1));
    await refreshBatteryOptimization();
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
    try {
      await Permission.notification.request();
    } catch (_) {}
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

  static String _u(Guid g) => g.str128.toLowerCase();

  /// Подключение и настройка характеристик. Без авторизации и опроса.
  Future<bool> _open(BluetoothDevice d) async {
    await _connSub?.cancel();
    _connSub = d.connectionState.listen((s) {
      if (s == BluetoothConnectionState.disconnected && link == LinkState.connected) {
        _onDisconnected();
      }
    });
    await d.connect(timeout: const Duration(seconds: 15), autoConnect: false);
    final services = await d.discoverServices();
    BluetoothCharacteristic? rx;
    _tx = null;
    _upnp = null;
    _avdtp = null;
    for (final s in services) {
      final su = _u(s.serviceUuid);
      _log('**', 'service ${s.serviceUuid.str}: ${s.characteristics.map((c) => c.characteristicUuid.str).join(', ')}');
      for (final c in s.characteristics) {
        final cu = _u(c.characteristicUuid);
        if (su == _uartService && cu == _txUuid) _tx = c;
        if (su == _uartService && cu == _rxUuid) rx = c;
        if (su == _authService && cu == _upnpUuid) _upnp = c;
        if (su == _authService && cu == _avdtpUuid) _avdtp = c;
      }
    }
    if (_tx == null || rx == null) throw StateError('UART-сервис не найден');

    for (final s in _subs) {
      await s.cancel();
    }
    _subs.clear();
    _parser.reset();

    await rx.setNotifyValue(true);
    final rxSub = rx.onValueReceived.listen(_onData);
    d.cancelWhenDisconnected(rxSub);
    _subs.add(rxSub);

    final upnp = _upnp;
    final avdtp = _avdtp;
    if (upnp != null && avdtp != null) {
      _miAuth = MiAuth(
        writeUpnp: (data) => _write(upnp, data),
        writeAvdtp: (data) => _write(avdtp, data),
        log: (m) => _log('**', m),
      );
      await upnp.setNotifyValue(true);
      await avdtp.setNotifyValue(true);
      final a = upnp.onValueReceived.listen((v) => _miAuth?.onNotify(v));
      final b = avdtp.onValueReceived.listen((v) => _miAuth?.onNotify(v));
      d.cancelWhenDisconnected(a);
      d.cancelWhenDisconnected(b);
      _subs..add(a)..add(b);
    } else {
      _miAuth = null;
    }
    return true;
  }

  Future<void> _write(BluetoothCharacteristic c, List<int> data) =>
      c.write(data, withoutResponse: c.properties.writeWithoutResponse);

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
    _keys = null;
    auth = AuthState.unknown;
    _log('**', 'connect ${d.remoteId.str} $deviceName');
    notifyListeners();
    try {
      await _open(d);
      final p = await SharedPreferences.getInstance();
      await p.setString('lastDevice', d.remoteId.str);
      await p.setString('lastDeviceName', deviceName ?? '');
      _currentSign = p.getInt('sign_${d.remoteId.str}') ?? 1;
      _signVotes = 0;

      link = LinkState.connected;
      _wasConnected = true;
      _disconnectedAt = null;
      statusText = null;
      await brain.attach(d.remoteId.str);
      await SystemBridge.startService('M365 · подключено', deviceName ?? 'Самокат');
      await SystemBridge.setShowWhenLocked(true);
      if (keepScreenOn) {
        try {
          await WakelockPlus.enable();
        } catch (_) {}
      }
      _startNotifTimer();
      _log('**', 'connected');
      notifyListeners();
      await _afterOpen();
    } catch (e) {
      _log('**', 'connect error: $e');
      statusText = 'Не удалось подключиться: $e';
      link = LinkState.idle;
      try {
        await d.disconnect();
      } catch (_) {}
      notifyListeners();
      _scheduleReconnect();
    }
  }

  /// Решаем, как говорить с самокатом: открыто, по токену или нужна привязка.
  Future<void> _afterOpen() async {
    final d = _device;
    if (d == null) return;
    if (_miAuth == null) {
      auth = AuthState.plain;
      _startPolling();
      return;
    }
    final p = await SharedPreferences.getInstance();
    final tokenHex = p.getString('token_${d.remoteId.str}');
    if (tokenHex != null) {
      final ok = await _login(_fromHex(tokenHex));
      if (ok) return;
    }
    if (tokenHex == null && await _probePlain()) {
      auth = AuthState.plain;
      _log('**', 'самокат отвечает без шифрования');
      _startPolling();
      return;
    }
    if (auth != AuthState.failed) {
      auth = AuthState.needRegister;
      authStatus = 'Нужна привязка к самокату (один раз)';
    }
    notifyListeners();
  }

  Future<bool> _probePlain() async {
    final before = lastRx;
    for (var i = 0; i < 2; i++) {
      await _sendRaw(readRequest(Addr.esc, 0xB0, 0x20));
      await Future.delayed(const Duration(milliseconds: 700));
      if (lastRx != before) return true;
    }
    return false;
  }

  Future<bool> _login(Uint8List token) async {
    final a = _miAuth;
    if (a == null) return false;
    auth = AuthState.loggingIn;
    authStatus = 'Вход…';
    notifyListeners();
    try {
      _keys = await a.login(token);
      _uartIt = 0;
      auth = AuthState.ready;
      authStatus = null;
      _log('**', 'вход выполнен, канал зашифрован');
      notifyListeners();
      _startPolling();
      return true;
    } on MiAuthError catch (e) {
      _log('**', 'login error: $e');
      auth = e.needsRegister ? AuthState.needRegister : AuthState.failed;
      authStatus = e.message;
    } on TimeoutException catch (e) {
      _log('**', 'login timeout: $e');
      auth = AuthState.needRegister;
      authStatus = 'Самокат не принял вход — нужна привязка';
    } catch (e) {
      _log('**', 'login error: $e');
      auth = AuthState.failed;
      authStatus = 'Ошибка входа: $e';
    }
    notifyListeners();
    return false;
  }

  /// Привязка: самокат пищит и ждёт короткого нажатия кнопки питания.
  Future<void> register() async {
    final d = _device;
    if (d == null || link != LinkState.connected || _miAuth == null) return;
    _stopPolling();
    auth = AuthState.registering;
    for (var attempt = 1; attempt <= 4; attempt++) {
      authStatus = attempt == 1
          ? 'Привязка… Когда самокат пискнет — коротко нажми кнопку питания'
          : 'Попытка $attempt из 4. Самокат пискнет — сразу коротко нажми кнопку питания';
      notifyListeners();
      try {
        final token = await _miAuth!.register();
        final p = await SharedPreferences.getInstance();
        await p.setString('token_${d.remoteId.str}', _toHex(token));
        _log('**', 'привязка успешна');
        authStatus = 'Привязано! Вхожу…';
        notifyListeners();
        await _quietReopen(d);
        await _login(token);
        return;
      } on TimeoutException {
        _log('**', 'привязка: нет ответа (попытка $attempt) — ждём кнопку и переподключаемся');
        authStatus = 'Нажми кнопку питания на самокате сейчас…';
        notifyListeners();
        await _quietReopen(d, pause: const Duration(seconds: 5));
      } on MiAuthError catch (e) {
        _log('**', 'register error: $e');
        auth = AuthState.failed;
        authStatus = e.message;
        notifyListeners();
        return;
      } catch (e) {
        _log('**', 'register error: $e');
        await _quietReopen(d, pause: const Duration(seconds: 3));
      }
    }
    auth = AuthState.needRegister;
    authStatus = 'Не получилось привязать. Попробуй ещё раз и нажми кнопку сразу после писка.';
    notifyListeners();
  }

  Future<void> _quietReopen(BluetoothDevice d, {Duration pause = const Duration(seconds: 1)}) async {
    _quietReconnect = true;
    try {
      try {
        await d.disconnect();
      } catch (_) {}
      await Future.delayed(pause);
      await _open(d);
    } catch (e) {
      _log('**', 'reopen error: $e');
    } finally {
      _quietReconnect = false;
    }
  }

  Future<void> forgetPairing() async {
    final d = _device;
    if (d == null) return;
    final p = await SharedPreferences.getInstance();
    await p.remove('token_${d.remoteId.str}');
    _keys = null;
    _stopPolling();
    auth = _miAuth == null ? AuthState.plain : AuthState.needRegister;
    authStatus = 'Привязка сброшена';
    notifyListeners();
  }

  Future<void> disconnect() async {
    _userDisconnect = true;
    _stopPolling();
    try {
      await _device?.disconnect();
    } catch (_) {}
    await _onDisconnected();
    await SystemBridge.stopService();
  }

  Future<void> _onDisconnected() async {
    if (_quietReconnect) return;
    if (link == LinkState.idle && _disconnectedAt != null) return;
    _stopPolling();
    _notifTimer?.cancel();
    _log('**', 'disconnected');
    link = LinkState.idle;
    _keys = null;
    speed = 0;
    _disconnectedAt = DateTime.now();
    brain.detach();
    await SystemBridge.setShowWhenLocked(false);
    try {
      await WakelockPlus.disable();
    } catch (_) {}
    notifyListeners();
    if (!_userDisconnect) {
      await SystemBridge.updateService('M365 · связь потеряна', 'Переподключаюсь…');
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    final d = _device;
    if (d == null || _userDisconnect || !_wasConnected) return;
    final since = _disconnectedAt ?? DateTime.now();
    final away = DateTime.now().difference(since);
    if (away > const Duration(minutes: 10)) {
      // Долго нет связи — отпускаем фоновую службу, но иногда пробуем снова.
      SystemBridge.stopService();
    }
    final delay = away < const Duration(minutes: 1) ? const Duration(seconds: 3) : const Duration(seconds: 30);
    Future.delayed(delay, () {
      if (link == LinkState.idle && !_userDisconnect) connect(d, name: deviceName);
    });
  }

  void _startNotifTimer() {
    _notifTimer?.cancel();
    _notifTimer = Timer.periodic(const Duration(seconds: 2), (_) => _updateNotification());
  }

  void _updateNotification() {
    if (link != LinkState.connected) return;
    final b = brain;
    final title = dataFlowing ? '${speed.toStringAsFixed(0)} км/ч · $batteryPct%' : 'M365 · ${authStatus ?? 'подключено'}';
    final parts = <String>[];
    final t = b.trip;
    if (t != null) {
      parts.add('${t.km.toStringAsFixed(1)} км');
      final a = t.avgWhKm;
      if (a != null) parts.add('${a.toStringAsFixed(1)} Вт·ч/км');
    }
    final r = b.rangeKm;
    if (r != null) parts.add('запас ~${r.toStringAsFixed(0)} км');
    SystemBridge.updateService(title, parts.isEmpty ? (deviceName ?? 'Подключено') : parts.join(' · '));
  }

  // ---- опрос: строго запрос → ответ ----

  static String _needKey(int addr, int arg) => '$addr:$arg';

  void _need(int addr, int arg, int len) {
    _needs[_needKey(addr, arg)] = _Need(readRequest(addr, arg, len));
  }

  void _satisfied(int replyAddr, int arg) {
    final addr = replyAddr == Addr.escReply ? Addr.esc : Addr.bms;
    _needs.remove(_needKey(addr, arg));
  }

  Uint8List? _nextNeed() {
    if (_needs.isEmpty) return null;
    final keys = _needs.keys.toList();
    final k = keys[_needCursor % keys.length];
    _needCursor++;
    final n = _needs[k]!;
    n.tries++;
    if (n.tries > 8) _needs.remove(k);
    return n.req;
  }

  void _startPolling() {
    _stopPolling();
    _needs.clear();
    _need(Addr.esc, 0x1A, 2); // прошивка контроллера
    _need(Addr.bms, 0x17, 2); // прошивка BMS
    _need(Addr.bms, 0x18, 2); // заводская ёмкость, мАч
    _need(Addr.bms, 0x1B, 4); // циклы, количество зарядок
    _need(Addr.esc, 0x7B, 6); // рекуперация, круиз, фонарь
    _lastChargeCountReq = DateTime.now();
    _pollStep = 0;
    final gen = ++_pollGen;
    unawaited(_pollLoop(gen));
  }

  void _stopPolling() {
    _pollGen++;
  }

  Future<void> _pollLoop(int gen) async {
    final startedAt = DateTime.now();
    while (gen == _pollGen && link == LinkState.connected) {
      if (DateTime.now().difference(_lastChargeCountReq) > const Duration(seconds: 60)) {
        _lastChargeCountReq = DateTime.now();
        _need(Addr.bms, 0x1B, 4);
      }
      Uint8List req;
      // Ток BMS — каждый второй запрос (~2 раза в секунду), остальное — контроллер, ячейки, разовые.
      switch (_pollStep % 6) {
        case 1:
        case 3:
        case 5:
          req = readRequest(Addr.bms, 0x31, 0x0A);
          break;
        case 4:
          final n = (_pollStep ~/ 6).isEven ? _nextNeed() : null;
          req = n ?? readRequest(Addr.bms, 0x40, 0x14);
          break;
        default:
          req = readRequest(Addr.esc, 0xB0, 0x20);
      }
      _pollStep++;
      _pending = Completer<void>();
      await _send(req);
      await _pending!.future.timeout(const Duration(milliseconds: 500), onTimeout: () {});
      await Future.delayed(const Duration(milliseconds: 30));

      final silentFor = DateTime.now().difference(lastRx ?? startedAt);
      final nr = silentFor > const Duration(seconds: 5);
      if (nr != noReply) {
        noReply = nr;
        if (nr) _log('**', 'нет ответов 5 с');
        notifyListeners();
      }
    }
  }

  /// Отправка команды 55 AA: шифруем, если вошли по MiAuth.
  Future<void> _send(Uint8List plainFrame) async {
    final k = _keys;
    if (k != null) {
      final enc = MiCrypto.encryptUart(k.appKey, k.appIv, plainFrame, _uartIt);
      _uartIt++;
      _log('TX', '${toHex(plainFrame)}  ⇒  ${toHex(enc)}');
      await _sendRaw(enc, logIt: false);
    } else {
      await _sendRaw(plainFrame);
    }
  }

  Future<void> _sendRaw(Uint8List bytes, {bool logIt = true}) async {
    final tx = _tx;
    if (tx == null) return;
    if (logIt) _log('TX', toHex(bytes));
    try {
      for (var i = 0; i < bytes.length; i += 20) {
        final end = i + 20 < bytes.length ? i + 20 : bytes.length;
        await _write(tx, bytes.sublist(i, end));
      }
    } catch (e) {
      _log('**', 'write error: $e');
    }
  }

  // ---- управление ----
  Future<void> setKers(int level) async {
    await _send(writeRequest(Addr.esc, 0x7B, level));
    kers = level;
    _need(Addr.esc, 0x7B, 6);
    notifyListeners();
  }

  Future<void> setCruise(bool on) async {
    await _send(writeRequest(Addr.esc, 0x7C, on ? 1 : 0));
    cruise = on;
    _need(Addr.esc, 0x7B, 6);
    notifyListeners();
  }

  Future<void> setTailLight(bool on) async {
    await _send(writeRequest(Addr.esc, 0x7D, on ? 2 : 0));
    tailLight = on;
    _need(Addr.esc, 0x7B, 6);
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
      if (_keys != null) {
        _log('**', '⇐ ${f.addr.toRadixString(16)} ${f.cmd.toRadixString(16)} ${f.arg.toRadixString(16)} ${toHex(f.data)}');
      }
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
    final p = _pending;
    if (p != null && !p.isCompleted) p.complete();
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
        brain.onEsc(speed, totalKm, mode);
        break;
      case 0x1A:
        if (d.length >= 2) {
          escFw = fwString(u16(d, 0));
          _satisfied(f.addr, f.arg);
        }
        break;
      case 0x7B:
        if (d.length >= 2) kers = u16(d, 0);
        if (d.length >= 4) cruise = u16(d, 2) != 0;
        if (d.length >= 6) tailLight = u16(d, 4) != 0;
        _satisfied(f.addr, f.arg);
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
        brain.onBms(voltage, current, remainingMah, bmsPct);
        break;
      case 0x40:
        final n = (d.length ~/ 2).clamp(0, 10);
        cells = [for (var i = 0; i < n; i++) u16(d, i * 2) / 1000.0].where((v) => v > 1).toList();
        if (cells.isNotEmpty) brain.minCell = cells.reduce((a, b) => a < b ? a : b);
        break;
      case 0x17:
        if (d.length >= 2) {
          bmsFw = fwString(u16(d, 0));
          _satisfied(f.addr, f.arg);
        }
        break;
      case 0x18:
        if (d.length >= 2) {
          final v = u16(d, 0);
          if (v > 1000) {
            factoryMah = v;
            brain.onFactoryMah(v);
          }
          _satisfied(f.addr, f.arg);
        }
        break;
      case 0x1B:
        if (d.length >= 2) cycles = u16(d, 0);
        if (d.length >= 4) {
          chargeCount = u16(d, 2);
          brain.chargeCount = chargeCount;
        }
        _satisfied(f.addr, f.arg);
        break;
    }
  }

  /// На ходу ток в основном тянет из батареи. Если при движении он почти всегда
  /// отрицательный — у этой BMS знак обратный, переворачиваем и запоминаем.
  void _detectSign(double raw) {
    if (speed < 8 || raw.abs() < 1.5) return;
    _signVotes += raw * _currentSign > 0 ? 1 : -1;
    _signVotes = _signVotes.clamp(-30, 30);
    if (_signVotes <= -20) {
      _currentSign = -_currentSign;
      _signVotes = 0;
      _log('**', 'знак тока перевёрнут');
      brain.onSignFlip();
      _saveSign();
    } else if (_signVotes >= 20) {
      _saveSign();
    }
  }

  bool _signSaved = false;
  Future<void> _saveSign() async {
    if (_signSaved) return;
    final d = _device;
    if (d == null) return;
    _signSaved = true;
    final p = await SharedPreferences.getInstance();
    await p.setInt('sign_${d.remoteId.str}', _currentSign);
  }

  static String _toHex(List<int> b) => b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  static Uint8List _fromHex(String s) =>
      Uint8List.fromList([for (var i = 0; i + 1 < s.length; i += 2) int.parse(s.substring(i, i + 2), radix: 16)]);
}
