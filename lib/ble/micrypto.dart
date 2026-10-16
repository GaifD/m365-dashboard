// Криптография Xiaomi MiAuth (BLE): ECDH P-256, HKDF-SHA256, HMAC-SHA256, AES-CCM (тег 4 байта).
// Алгоритм портирован с MiAuth (Daljeet Nandha, AGPL-3.0): https://github.com/dnandha/miauth
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

class MiKeys {
  final Uint8List devKey;
  final Uint8List appKey;
  final Uint8List devIv;
  final Uint8List appIv;
  MiKeys(this.devKey, this.appKey, this.devIv, this.appIv);
}

class MiCrypto {
  static final ECDomainParameters _curve = ECCurve_secp256r1();

  static SecureRandom _rng() {
    final r = Random.secure();
    final seed = Uint8List.fromList(List<int>.generate(32, (_) => r.nextInt(256)));
    return FortunaRandom()..seed(KeyParameter(seed));
  }

  static Uint8List randomBytes(int n) {
    final r = Random.secure();
    return Uint8List.fromList(List<int>.generate(n, (_) => r.nextInt(256)));
  }

  // ---- EC ----
  static AsymmetricKeyPair<ECPublicKey, ECPrivateKey> generateKeyPair() {
    final gen = ECKeyGenerator()..init(ParametersWithRandom(ECKeyGeneratorParameters(_curve), _rng()));
    final p = gen.generateKeyPair();
    return AsymmetricKeyPair<ECPublicKey, ECPrivateKey>(p.publicKey as ECPublicKey, p.privateKey as ECPrivateKey);
  }

  static ECPrivateKey privateFromValue(BigInt d) => ECPrivateKey(d, _curve);

  static ECPublicKey publicFromPrivate(ECPrivateKey k) => ECPublicKey((_curve.G * k.d)!, _curve);

  /// Публичный ключ как 64 байта x||y (без префикса 04).
  static Uint8List publicBytes(ECPublicKey k) => Uint8List.fromList(k.Q!.getEncoded(false).sublist(1));

  static ECPublicKey publicFromBytes(List<int> xy) =>
      ECPublicKey(_curve.curve.decodePoint([4, ...xy])!, _curve);

  /// Общий секрет ECDH — координата X, 32 байта.
  static Uint8List ecdh(ECPrivateKey priv, ECPublicKey pub) {
    final p = (pub.Q! * priv.d)!;
    return _bigToBytes(p.x!.toBigInteger()!, 32);
  }

  static Uint8List _bigToBytes(BigInt v, int len) {
    final out = Uint8List(len);
    var x = v;
    for (var i = len - 1; i >= 0; i--) {
      out[i] = (x & BigInt.from(0xff)).toInt();
      x = x >> 8;
    }
    return out;
  }

  // ---- HMAC / HKDF ----
  static Uint8List hmacSha256(List<int> key, List<int> data) {
    final h = HMac(SHA256Digest(), 64)..init(KeyParameter(Uint8List.fromList(key)));
    return h.process(Uint8List.fromList(data));
  }

  static Uint8List hkdf(List<int> ikm, List<int>? salt, List<int> info, int length) {
    final prk = hmacSha256(salt == null || salt.isEmpty ? Uint8List(32) : salt, ikm);
    final out = <int>[];
    var t = <int>[];
    var i = 1;
    while (out.length < length) {
      t = hmacSha256(prk, [...t, ...info, i]);
      out.addAll(t);
      i++;
    }
    return Uint8List.fromList(out.sublist(0, length));
  }

  static final List<int> _setupInfo = 'mible-setup-info'.codeUnits;
  static final List<int> _loginInfo = 'mible-login-info'.codeUnits;

  static Uint8List deriveKey(List<int> sharedKey, [List<int>? salt]) =>
      hkdf(sharedKey, salt, salt == null ? _setupInfo : _loginInfo, 64);

  // ---- AES-CCM ----
  static Uint8List _aes(Uint8List key, Uint8List block) {
    final e = AESEngine()..init(true, KeyParameter(key));
    final out = Uint8List(16);
    e.processBlock(block, 0, out, 0);
    return out;
  }

  static Uint8List _cbcMac(Uint8List key, Uint8List nonce, List<int> data, List<int> aad, int tagLen) {
    final l = 15 - nonce.length;
    final b0 = Uint8List(16);
    b0[0] = (aad.isNotEmpty ? 0x40 : 0) | (((tagLen - 2) ~/ 2) << 3) | (l - 1);
    b0.setRange(1, 1 + nonce.length, nonce);
    var len = data.length;
    for (var i = 15; i > 15 - l; i--) {
      b0[i] = len & 0xff;
      len >>= 8;
    }
    final blocks = <int>[...b0];
    if (aad.isNotEmpty) {
      final a = <int>[(aad.length >> 8) & 0xff, aad.length & 0xff, ...aad];
      while (a.length % 16 != 0) {
        a.add(0);
      }
      blocks.addAll(a);
    }
    final d = <int>[...data];
    while (d.length % 16 != 0) {
      d.add(0);
    }
    blocks.addAll(d);
    var x = Uint8List(16);
    for (var off = 0; off < blocks.length; off += 16) {
      final blk = Uint8List(16);
      for (var j = 0; j < 16; j++) {
        blk[j] = x[j] ^ blocks[off + j];
      }
      x = _aes(key, blk);
    }
    return x.sublist(0, tagLen);
  }

  static Uint8List _ctr(Uint8List key, Uint8List nonce, List<int> data, int startCounter) {
    final l = 15 - nonce.length;
    final out = Uint8List(data.length);
    var counter = startCounter;
    for (var off = 0; off < data.length; off += 16) {
      final a = Uint8List(16);
      a[0] = l - 1;
      a.setRange(1, 1 + nonce.length, nonce);
      var c = counter;
      for (var i = 15; i > 15 - l; i--) {
        a[i] = c & 0xff;
        c >>= 8;
      }
      final s = _aes(key, a);
      for (var j = 0; j < 16 && off + j < data.length; j++) {
        out[off + j] = data[off + j] ^ s[j];
      }
      counter++;
    }
    return out;
  }

  static Uint8List ccmEncrypt(List<int> key, List<int> nonce, List<int> plain,
      {List<int> aad = const [], int tagLen = 4}) {
    final k = Uint8List.fromList(key);
    final n = Uint8List.fromList(nonce);
    final tag = _cbcMac(k, n, plain, aad, tagLen);
    final ct = _ctr(k, n, plain, 1);
    final s0 = _ctr(k, n, tag, 0);
    return Uint8List.fromList([...ct, ...s0]);
  }

  /// Возвращает null, если тег не сошёлся.
  static Uint8List? ccmDecrypt(List<int> key, List<int> nonce, List<int> data,
      {List<int> aad = const [], int tagLen = 4}) {
    if (data.length < tagLen) return null;
    final k = Uint8List.fromList(key);
    final n = Uint8List.fromList(nonce);
    final ct = data.sublist(0, data.length - tagLen);
    final tagEnc = data.sublist(data.length - tagLen);
    final plain = _ctr(k, n, ct, 1);
    final tag = _ctr(k, n, tagEnc, 0);
    final expect = _cbcMac(k, n, plain, aad, tagLen);
    for (var i = 0; i < tagLen; i++) {
      if (tag[i] != expect[i]) return null;
    }
    return plain;
  }

  static Uint8List encryptDid(List<int> key, List<int> did) => ccmEncrypt(
        key,
        const [16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27],
        did,
        aad: 'devID'.codeUnits,
      );

  // ---- UART 55 AB ----
  static List<int> crc16(List<int> data) {
    var s = 0;
    for (final b in data) {
      s += b;
    }
    final n = (~s) & 0xFFFF;
    return [n & 0xff, (n >> 8) & 0xff];
  }

  /// [plainFrame] — кадр 55 AA L addr cmd arg payload (контрольная сумма, если есть, отбрасывается).
  static Uint8List encryptUart(List<int> appKey, List<int> appIv, List<int> plainFrame, int it,
      {List<int>? rand}) {
    final l = plainFrame[2];
    final body = plainFrame.sublist(3, 3 + 3 + (l - 2)); // addr cmd arg payload
    final data = [...body, ...(rand ?? randomBytes(4))];
    final itBytes = [it & 0xff, (it >> 8) & 0xff, (it >> 16) & 0xff, (it >> 24) & 0xff];
    final nonce = [...appIv, 0, 0, 0, 0, ...itBytes];
    final ct = ccmEncrypt(appKey, nonce, data);
    final inner = [l, itBytes[0], itBytes[1], ...ct];
    return Uint8List.fromList([0x55, 0xAB, ...inner, ...crc16(inner)]);
  }

  /// [frame] — полный кадр 55 AB ... crc. Возвращает расшифровку: addr cmd arg payload rand4.
  static Uint8List? decryptUart(List<int> devKey, List<int> devIv, List<int> frame) {
    if (frame.length < 9 || frame[0] != 0x55 || frame[1] != 0xAB) return null;
    final it = frame.sublist(3, 5);
    final ct = frame.sublist(5, frame.length - 2);
    final nonce = [...devIv, 0, 0, 0, 0, ...it, 0, 0];
    return ccmDecrypt(devKey, nonce, ct);
  }

  // ---- вычисления привязки и входа ----

  /// Привязка: возвращает (зашифрованный DID для отправки, токен 12 байт для хранения).
  static (Uint8List didCt, Uint8List token) calcDid(
      ECPrivateKey priv, List<int> remoteKey64, List<int> remoteInfo20) {
    final secret = ecdh(priv, publicFromBytes(remoteKey64));
    final derived = deriveKey(secret);
    final token = derived.sublist(0, 12);
    final a = derived.sublist(28, 44);
    return (encryptDid(a, remoteInfo20), token);
  }

  /// Вход: возвращает (наш ответ 32 байта, ожидаемый ответ самоката, ключи сессии).
  static (Uint8List info, Uint8List expectedRemote, MiKeys keys) calcLogin(
      List<int> token, List<int> randKey, List<int> remoteKey) {
    final salt = [...randKey, ...remoteKey];
    final saltInv = [...remoteKey, ...randKey];
    final d = deriveKey(token, salt);
    final keys = MiKeys(d.sublist(0, 16), d.sublist(16, 32), d.sublist(32, 36), d.sublist(36, 40));
    return (hmacSha256(keys.appKey, salt), hmacSha256(keys.devKey, saltInv), keys);
  }
}
