import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:magicpaste/services/protocol.dart';

void main() {
  group('Protocol.buildHeader', () {
    test('produces exactly 32 bytes', () {
      final hdr = Protocol.buildHeader(Protocol.msgPing, 0);
      expect(hdr.length, equals(Protocol.headerSize));
    });

    test('magic number is correct', () {
      final hdr = Protocol.buildHeader(Protocol.msgPing, 0);
      final b = ByteData.sublistView(hdr);
      expect(b.getUint32(0, Endian.big), equals(Protocol.magic));
    });

    test('message type is encoded correctly', () {
      final hdr = Protocol.buildHeader(Protocol.msgImage, 0);
      final b = ByteData.sublistView(hdr);
      expect(b.getUint32(4, Endian.big), equals(Protocol.msgImage));
    });

    test('payload length is encoded correctly', () {
      final hdr = Protocol.buildHeader(Protocol.msgPing, 1234);
      final b = ByteData.sublistView(hdr);
      expect(b.getUint32(8, Endian.big), equals(1234));
    });

    test('token is embedded in bytes 16-31', () {
      final token = Uint8List.fromList(List.generate(16, (i) => i + 1));
      final hdr = Protocol.buildHeader(Protocol.msgPing, 0, token);
      expect(hdr.sublist(16, 32), equals(token));
    });

    test('no token produces zero bytes 16-31', () {
      final hdr = Protocol.buildHeader(Protocol.msgPing, 0);
      expect(hdr.sublist(16, 32), equals(Uint8List(16)));
    });
  });

  group('Protocol.parseHeader', () {
    test('round-trip with msgImage', () {
      final hdr = Protocol.buildHeader(Protocol.msgImage, 512);
      final (msgType, payloadLen) = Protocol.parseHeader(hdr);
      expect(msgType, equals(Protocol.msgImage));
      expect(payloadLen, equals(512));
    });

    test('throws on bad magic', () {
      final bad = Uint8List(32);
      expect(() => Protocol.parseHeader(bad), throwsFormatException);
    });

    test('throws when data too short', () {
      expect(() => Protocol.parseHeader(Uint8List(10)), throwsFormatException);
    });
  });

  group('Protocol.buildImageMessage', () {
    test('total length = header + 12 + raw', () {
      final raw = Uint8List(200);
      final msg = Protocol.buildImageMessage(Protocol.imgPng, 100, 50, raw);
      expect(msg.length, equals(Protocol.headerSize + 12 + 200));
    });

    test('header inside message parses correctly', () {
      final raw = Uint8List(100);
      final msg = Protocol.buildImageMessage(Protocol.imgJpeg, 1920, 1080, raw);
      final (msgType, payloadLen) =
          Protocol.parseHeader(msg.sublist(0, Protocol.headerSize));
      expect(msgType, equals(Protocol.msgImage));
      expect(payloadLen, equals(12 + 100));
    });

    test('image format encoded at payload offset 0', () {
      final raw = Uint8List(10);
      final msg = Protocol.buildImageMessage(Protocol.imgJpeg, 1, 1, raw);
      final b = ByteData.sublistView(msg, Protocol.headerSize);
      expect(b.getUint32(0, Endian.big), equals(Protocol.imgJpeg));
    });

    test('width and height encoded correctly', () {
      final raw = Uint8List(10);
      final msg =
          Protocol.buildImageMessage(Protocol.imgPng, 800, 600, raw);
      final b = ByteData.sublistView(msg, Protocol.headerSize);
      expect(b.getUint32(4, Endian.big), equals(800));
      expect(b.getUint32(8, Endian.big), equals(600));
    });

    test('raw bytes appended after 12-byte prefix', () {
      final raw = Uint8List.fromList([1, 2, 3, 4, 5]);
      final msg =
          Protocol.buildImageMessage(Protocol.imgPng, 1, 1, raw);
      final appended = msg.sublist(Protocol.headerSize + 12);
      expect(appended, equals(raw));
    });
  });

  group('Protocol.normToken', () {
    test('16-byte token is unchanged', () {
      final t = Uint8List.fromList(List.generate(16, (i) => i));
      expect(Protocol.normToken(t), equals(t));
    });

    test('short token is zero-padded', () {
      final t = Uint8List.fromList([1, 2]);
      final result = Protocol.normToken(t);
      expect(result.length, equals(16));
      expect(result[0], equals(1));
      expect(result[1], equals(2));
      expect(result.sublist(2), equals(Uint8List(14)));
    });

    test('long token is truncated', () {
      final t = Uint8List.fromList(List.generate(32, (i) => i));
      final result = Protocol.normToken(t);
      expect(result.length, equals(16));
      expect(result, equals(t.sublist(0, 16)));
    });

    test('null token returns zeros', () {
      expect(Protocol.normToken(null), equals(Uint8List(16)));
    });
  });

  group('Protocol.tokenFromHex', () {
    test('valid hex string decoded correctly', () {
      final result = Protocol.tokenFromHex('0102030405060708090a0b0c0d0e0f10');
      expect(result[0], equals(0x01));
      expect(result[1], equals(0x02));
      expect(result[15], equals(0x10));
    });

    test('null returns zeros', () {
      expect(Protocol.tokenFromHex(null), equals(Uint8List(16)));
    });

    test('empty string returns zeros', () {
      expect(Protocol.tokenFromHex(''), equals(Uint8List(16)));
    });
  });

  group('Protocol.buildSimpleMessage', () {
    test('PING has no payload beyond header', () {
      final msg = Protocol.buildSimpleMessage(Protocol.msgPing);
      expect(msg.length, equals(Protocol.headerSize));
    });

    test('PAIR_REQUEST carries payload', () {
      final payload = Uint8List.fromList('MyPhone'.codeUnits);
      final msg =
          Protocol.buildSimpleMessage(Protocol.msgPairRequest, payload);
      expect(msg.length, equals(Protocol.headerSize + payload.length));
      expect(msg.sublist(Protocol.headerSize), equals(payload));
    });
  });
}
