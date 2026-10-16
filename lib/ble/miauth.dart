// Привязка (register) и вход (login) по протоколу Xiaomi MiAuth через сервис FE95.
// Логика обмена портирована с MiAuth (Daljeet Nandha, AGPL-3.0): https://github.com/dnandha/miauth
import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';

import 'micrypto.dart';
import 'protocol.dart' show toHex;

class MiAuthError implements Exception {
  final String message;
  final bool needsRegister;
  MiAuthError(this.message, {this.needsRegister = false});
  @override
  String toString() => message;
}

class MiCmd {
  static const getInfo = [0xa2, 0, 0, 0];
  static const setKey = [0x15, 0, 0, 0];
  static const login = [0x24, 0, 0, 0];
  static const auth = [0x13, 0, 0, 0];

  static const sendData = [0, 0, 0, 0x03, 0x04, 0];
  static const sendDid = [0, 0, 0, 0x00, 0x02, 0];
  static const sendKey = [0, 0, 0, 0x0b, 0x01, 0];
  static const sendInfo = [0, 0, 0, 0x0a, 0x02, 0];

  static const rcvRdy = [0, 0, 1, 1];
  static const rcvOk = [0, 0, 1, 0];

  static const registerOk = [0x11, 0, 0, 0];
  static const registerErr = [0x12, 0, 0, 0];
  static const loginOk = [0x21, 0, 0, 0];
  static const loginErr = [0x23, 0, 0, 0];
}

bool _eq(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

bool _startsWith(List<int> a, List<int> p) => a.length >= p.length && _eq(a.sublist(0, p.length), p);

typedef BleWrite = Future<void> Function(List<int> data);

class MiAuth {
  final BleWrite writeUpnp;
  final BleWrite writeAvdtp;
  final void Function(String) log;
  final Duration stepTimeout;

  MiAuth({
    required this.writeUpnp,
    required this.writeAvdtp,
    required this.log,
    this.stepTimeout = const Duration(seconds: 6),
  });

  final Queue<Uint8List> _inbox = Queue();
  Completer<void>? _waiter;

  /// Сюда передаются все уведомления с характеристик UPNP и AVDTP.
  void onNotify(List<int> data) {
    if (data.isEmpty) return;
    log('AUTH RX ${toHex(data)}');
    _inbox.add(Uint8List.fromList(data));
    final w = _waiter;
    if (w != null && !w.isCompleted) w.complete();
  }

  Future<Uint8List> _next() async {
    final deadline = DateTime.now().add(stepTimeout);
    while (_inbox.isEmpty) {
      final left = deadline.difference(DateTime.now());
      if (left <= Duration.zero) throw TimeoutException('MiAuth: самокат не отвечает');
      _waiter = Completer<void>();
      await _waiter!.future.timeout(left, onTimeout: () {});
    }
    final m = _inbox.removeFirst();
    if (m.length == 4 && m[0] >= 0xe0 && m[0] <= 0xe3 && m[1] == 0 && m[2] == 0 && m[3] == 0) {
      throw MiAuthError('Самокат отклонил авторизацию (код ${toHex(m)})', needsRegister: true);
    }
    return m;
  }

  Future<void> _upnp(List<int> d) {
    log('AUTH TX upnp ${toHex(d)}');
    return writeUpnp(d);
  }

  Future<void> _avdtp(List<int> d) {
    log('AUTH TX avdtp ${toHex(d)}');
    return writeAvdtp(d);
  }

  /// Принять посылку: заголовок 00 00 00 XX NN 00 → RCV_RDY → NN кадров → RCV_OK.
  Future<Uint8List> _receiveParcel() async {
    while (true) {
      final h = await _next();
      // «Официальный» короткий вариант: 00 00 02 0d <данные>
      if (h.length > 4 && h[0] == 0 && h[1] == 0 && h[2] == 2) {
        await _avdtp(const [0, 0, 3, 0]);
        return h.sublist(4);
      }
      if (h.length >= 6 && h[0] == 0 && h[1] == 0 && h[2] == 0) {
        final count = h[4] | (h[5] << 8);
        await _avdtp(MiCmd.rcvRdy);
        final out = <int>[];
        var got = 0;
        while (got < count) {
          final f = await _next();
          final idx = f[0] | (f.length > 1 ? f[1] << 8 : 0);
          if (idx == 0) continue; // служебное сообщение посреди посылки — пропускаем
          out.addAll(f.sublist(2));
          got = idx;
        }
        await _avdtp(MiCmd.rcvOk);
        return Uint8List.fromList(out);
      }
      log('AUTH: пропускаю ${toHex(h)}');
    }
  }

  /// Отправить посылку: заголовок → ждём RCV_RDY → кадры по 18 байт → ждём RCV_OK.
  Future<void> _sendParcel(List<int> header, List<int> data) async {
    await _avdtp(header);
    while (true) {
      final r = await _next();
      if (_eq(r, MiCmd.rcvRdy)) break;
      if (_startsWith(r, const [0, 0, 1, 5])) throw MiAuthError('Самокат: ошибка приёма (${toHex(r)})');
      log('AUTH: жду RCV_RDY, пришло ${toHex(r)}');
    }
    for (var i = 0; i < data.length; i += 18) {
      final end = (i + 18 < data.length) ? i + 18 : data.length;
      await _avdtp([i ~/ 18 + 1, 0, ...data.sublist(i, end)]);
    }
    while (true) {
      final r = await _next();
      if (_eq(r, MiCmd.rcvOk)) return;
      if (_startsWith(r, const [0, 0, 1, 5])) throw MiAuthError('Самокат: ошибка приёма (${toHex(r)})');
      log('AUTH: жду RCV_OK, пришло ${toHex(r)}');
    }
  }

  /// Привязка. Требует нажатия кнопки питания. Возвращает токен (12 байт).
  Future<Uint8List> register() async {
    _inbox.clear();
    final kp = MiCrypto.generateKeyPair();
    await _upnp(MiCmd.getInfo);
    final info = await _receiveParcel();
    if (info.length < 24) {
      throw MiAuthError('Самокат не отдал идентификатор (${info.length} байт). '
          'Его нужно хотя бы раз привязать в Mi Home.');
    }
    final remoteInfo = info.sublist(4, 24);
    await _upnp(MiCmd.setKey);
    await _sendParcel(MiCmd.sendData, MiCrypto.publicBytes(kp.publicKey));
    final remoteKey = await _receiveParcel();
    if (remoteKey.length < 64) throw MiAuthError('Неверная длина ключа самоката: ${remoteKey.length}');
    final (didCt, token) = MiCrypto.calcDid(kp.privateKey, remoteKey.sublist(0, 64), remoteInfo);
    await _sendParcel(MiCmd.sendDid, didCt);
    await _upnp(MiCmd.auth);
    while (true) {
      final r = await _next();
      if (_eq(r, MiCmd.registerOk)) return token;
      if (_eq(r, MiCmd.registerErr)) throw MiAuthError('Самокат отклонил привязку');
      log('AUTH: жду подтверждения, пришло ${toHex(r)}');
    }
  }

  /// Вход по сохранённому токену. Возвращает ключи сессии.
  Future<MiKeys> login(List<int> token) async {
    _inbox.clear();
    final randKey = MiCrypto.randomBytes(16);
    await _upnp(MiCmd.login);
    await _sendParcel(MiCmd.sendKey, randKey);
    final remoteKey = await _receiveParcel();
    final remoteInfo = await _receiveParcel();
    final (info, expected, keys) = MiCrypto.calcLogin(token, randKey, remoteKey.sublist(0, 16));
    if (!_eq(remoteInfo.sublist(0, expected.length), expected)) {
      throw MiAuthError('Токен не подошёл — нужна повторная привязка', needsRegister: true);
    }
    await _sendParcel(MiCmd.sendInfo, info);
    while (true) {
      final r = await _next();
      if (_eq(r, MiCmd.loginOk)) return keys;
      if (_eq(r, MiCmd.loginErr)) throw MiAuthError('Вход отклонён — нужна повторная привязка', needsRegister: true);
      log('AUTH: жду подтверждения входа, пришло ${toHex(r)}');
    }
  }
}
