// Протокол Xiaomi/Ninebot M365 поверх BLE UART (кадры 55 AA).
//
// Кадр: 55 AA | L | addr | cmd | arg | payload (L-2 байт) | ck_lo ck_hi
// L = длина payload + 2. Контрольная сумма = (сумма байт от L до конца payload) XOR 0xFFFF.
import 'dart:typed_data';

class Addr {
  static const esc = 0x20; // телефон → контроллер
  static const bms = 0x22; // телефон → BMS
  static const escReply = 0x23; // контроллер → телефон
  static const bmsReply = 0x25; // BMS → телефон
}

class Cmd {
  static const read = 0x01;
  static const write = 0x03;
}

class NbFrame {
  final int addr;
  final int cmd;
  final int arg;
  final Uint8List data;
  NbFrame(this.addr, this.cmd, this.arg, this.data);
}

int _checksum(List<int> bytes) {
  var s = 0;
  for (final b in bytes) {
    s += b;
  }
  return (s ^ 0xFFFF) & 0xFFFF;
}

Uint8List buildFrame(int addr, int cmd, int arg, List<int> payload) {
  final body = <int>[payload.length + 2, addr, cmd, arg, ...payload];
  final ck = _checksum(body);
  return Uint8List.fromList([0x55, 0xAA, ...body, ck & 0xFF, (ck >> 8) & 0xFF]);
}

Uint8List readRequest(int addr, int reg, int len) =>
    buildFrame(addr, Cmd.read, reg, [len]);

Uint8List writeRequest(int addr, int reg, int value) =>
    buildFrame(addr, Cmd.write, reg, [value & 0xFF, (value >> 8) & 0xFF]);

/// Расшифровщик кадров 55 AB: получает весь кадр, возвращает addr cmd arg payload (+4 случайных байта) или null.
typedef FrameDecryptor = Uint8List? Function(List<int> frame);

/// Собирает кадры из кусков уведомлений (BLE режет данные по 20 байт).
/// Понимает открытые кадры 55 AA и зашифрованные 55 AB (если задан [decryptor]).
class FrameParser {
  final List<int> _buf = [];
  FrameDecryptor? decryptor;
  void Function(String)? onError;

  List<NbFrame> feed(List<int> chunk) {
    _buf.addAll(chunk);
    final out = <NbFrame>[];
    while (true) {
      var start = -1;
      for (var i = 0; i + 1 < _buf.length; i++) {
        if (_buf[i] == 0x55 && (_buf[i + 1] == 0xAA || _buf[i + 1] == 0xAB)) {
          start = i;
          break;
        }
      }
      if (start < 0) {
        final keepTail = _buf.isNotEmpty && _buf.last == 0x55;
        _buf.clear();
        if (keepTail) _buf.add(0x55);
        break;
      }
      if (start > 0) _buf.removeRange(0, start);
      if (_buf.length < 3) break;
      if (_buf[1] == 0xAB) {
        // 55 AB | L | it(2) | шифротекст (L+9 байт: addr cmd arg payload rand4 tag4) | crc(2)
        final l = _buf[2];
        final total = l + 16;
        if (_buf.length < total) break;
        final frame = _buf.sublist(0, total);
        final inner = frame.sublist(2, total - 2);
        var s = 0;
        for (final b in inner) {
          s += b;
        }
        final ck = (~s) & 0xFFFF;
        final got = frame[total - 2] | (frame[total - 1] << 8);
        final dec = (ck == got && decryptor != null) ? decryptor!(frame) : null;
        if (dec != null && dec.length >= 3 + (l - 2)) {
          out.add(NbFrame(dec[0], dec[1], dec[2], Uint8List.fromList(dec.sublist(3, 3 + (l - 2)))));
          _buf.removeRange(0, total);
        } else {
          onError?.call(ck != got ? 'crc 55AB не сошёлся' : 'не удалось расшифровать 55AB');
          _buf.removeRange(0, 2);
        }
        continue;
      }
      final l = _buf[2];
      if (l < 2) {
        _buf.removeRange(0, 2);
        continue;
      }
      final total = l + 6;
      if (_buf.length < total) break;
      final body = _buf.sublist(2, total - 2);
      final ck = _buf[total - 2] | (_buf[total - 1] << 8);
      if (_checksum(body) == ck) {
        out.add(NbFrame(body[1], body[2], body[3], Uint8List.fromList(body.sublist(4))));
        _buf.removeRange(0, total);
      } else {
        _buf.removeRange(0, 2);
      }
    }
    return out;
  }

  void reset() => _buf.clear();
}

int u16(List<int> d, int o) => d[o] | (d[o + 1] << 8);

int s16(List<int> d, int o) {
  final v = u16(d, o);
  return v >= 0x8000 ? v - 0x10000 : v;
}

String toHex(List<int> b) =>
    b.map((x) => x.toRadixString(16).padLeft(2, '0')).join(' ').toUpperCase();

String fwString(int v) => v.toRadixString(16).padLeft(4, '0').toUpperCase();
