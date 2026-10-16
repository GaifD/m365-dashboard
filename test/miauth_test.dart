// Проверка криптографии MiAuth на тестовых векторах из https://github.com/dnandha/miauth
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:m365_dashboard/ble/micrypto.dart';
import 'package:m365_dashboard/ble/protocol.dart';

Uint8List h(String s) {
  final c = s.replaceAll(' ', '');
  return Uint8List.fromList([for (var i = 0; i < c.length; i += 2) int.parse(c.substring(i, i + 2), radix: 16)]);
}

String hx(List<int> b) => b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

void main() {
  test('pub key from private value', () {
    final priv = MiCrypto.privateFromValue(
        BigInt.parse('38598657185418289442228743809972412250162588503372669841026540598582897367118'));
    final pub = MiCrypto.publicBytes(MiCrypto.publicFromPrivate(priv));
    expect(hx(pub),
        'b5dca0aec31a8932d0f53cbcbcf0cfdd833c355cada1025cc076e013439ddec2b4017b546a11d79a758db9d015a2ed8926cf82179b593679187d623b5e430fca');
  });

  test('ecdh symmetric', () {
    final a = MiCrypto.generateKeyPair();
    final b = MiCrypto.generateKeyPair();
    expect(hx(MiCrypto.ecdh(a.privateKey, b.publicKey)), hx(MiCrypto.ecdh(b.privateKey, a.publicKey)));
  });

  test('derive key', () {
    final secret = h('5a3d987d45f6484aff82ffde1e9105b7f6cc79fa7467f12c5855ad9e3f1d8f2f');
    expect(hx(MiCrypto.deriveKey(secret, [1, 2, 3, 4])),
        '40ccc0ee058c3a1d37c08e6f72bc2c57c0a406aaa801a0b1b72f22c8c3ec930d3f151e2eb38a2303d8625a18084daa15667496dcfbc53ba3074ce35d6c90d987');
    expect(hx(MiCrypto.deriveKey(secret)),
        '104ec0eda032b6d213c245359e585d3bfd4b7c5d683c99f49fd86aaf0de0f6b0bfafb897e3b3727aaa8f8ad6b21a737c1d85c3aae340969f268d2d95ca8848c1');
  });

  test('hmac', () {
    expect(hx(MiCrypto.hmacSha256(h('E2B274F08128A62A9575288BED169B3E'), [1, 2, 3, 4])),
        '235d7f910974acb594d76a1652a856ce4f269e3060d7c8512e94b2da345d3083');
  });

  test('encrypt did', () {
    expect(hx(MiCrypto.encryptDid(h('4FEB7165982BF1C6183A51B8CADD0EEC'), [1, 2, 3, 4])), 'aeebd70f8c2bdf8c');
  });

  test('encrypt uart', () {
    final ct = MiCrypto.encryptUart(h('9951fb8edf3921d61d15d56b45d38a46'), h('642b0a93'), h('55aa032001100e'), 0,
        rand: [1, 2, 3, 4]);
    expect(hx(ct), '55ab03000003dbfd07465635dcbd3b2d7acefa');
  });

  test('decrypt uart', () {
    final pt = MiCrypto.decryptUart(h('887ed6ae8ea3189546a55f0d0a6216ce'), h('659b7362'),
        h('55ab1001004c4e49c65c208435f7e050e56904adb8fe6e2eb1297cf9e0afbaf2'));
    expect(hx(pt!), '23011032353730302f3030303031333337cd65c322');
  });

  test('parser decrypts 55AB split into chunks', () {
    final p = FrameParser()
      ..decryptor = (f) => MiCrypto.decryptUart(h('887ed6ae8ea3189546a55f0d0a6216ce'), h('659b7362'), f);
    final frame = h('55ab1001004c4e49c65c208435f7e050e56904adb8fe6e2eb1297cf9e0afbaf2');
    expect(p.feed(frame.sublist(0, 20)), isEmpty);
    final out = p.feed(frame.sublist(20));
    expect(out.length, 1);
    expect(out[0].addr, 0x23);
    expect(out[0].arg, 0x10);
    expect(String.fromCharCodes(out[0].data), '25700/00001337');
  });

  test('register vector', () {
    final priv = MiCrypto.privateFromValue(
        BigInt.parse('48461508383982493215332654270464913273532832436436077476553357014100094140803'));
    final remoteInfo = h('0100000000626c742e342e31386e35383236366b67673030');
    final remoteKey = h(
        '2afe2a8c1c56e5e70721665cd20d017273111ecaeceb1e4d641e7b7a122a9c3041e5cbc962eefbdb155ffd95847a0d8762803291fc2866c5672ceee0e77d77fc');
    final secret = MiCrypto.ecdh(priv, MiCrypto.publicFromBytes(remoteKey));
    expect(hx(secret), 'fac3a6fd591dcea21f9f4fefe297804f49291527ae818b285f4a75a6fab72af8');
    final (didCt, token) = MiCrypto.calcDid(priv, remoteKey, remoteInfo.sublist(4));
    expect(hx(didCt), '646735cc7a96373aabbd93afa089bb6cd2d080302101007a');
    expect(hx(token), '0cf5615003810d89c233a12a');
  });

  test('login vector', () {
    final (info, expected, keys) = MiCrypto.calcLogin(
        h('0cf5615003810d89c233a12a'), h('a8699783c1f03c7b73a046cdb613a9bf'), h('90fdec0ece05016d7f116b50fca4b4bf'));
    expect(hx(expected), '471467ea7ed6064f8dd72f416c079dcb3bb78e3c94a51e97b98ef7623a7798e5');
    expect(hx(info), 'bbb99b6a6f1ae419e3b13db93514f3e12a1843033f276392eea99068affca753');
    expect(hx(keys.devKey), '3c2fdae69f8746663a7d91029724b072');
    expect(hx(keys.appKey), '12a4122dbe3cf60f3bdcb37139c34611');
    expect(hx(keys.devIv), 'cd016050');
    expect(hx(keys.appIv), 'c87de6f1');
  });

  test('plain frame checksum', () {
    expect(hx(readRequest(0x20, 0xB0, 0x20)), '55aa032001b0200bff');
  });
}
