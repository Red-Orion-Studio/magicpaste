// MagicPaste wire protocol (Dart side).
//
// Mirrors magicpaste-windows/protocol.py. See SPEC.md section 5.
//
// Header (32 bytes, big-endian):
//   0-3   magic 0x534E4150 ("SNAP")
//   4-7   message type (uint32)
//   8-11  payload length (uint32)
//   12-15 reserved (0)
//   16-31 auth token (16 bytes; zeros when none). The PC rejects any
//         non-pairing message whose token doesn't match the paired secret.

import 'dart:typed_data';

class Protocol {
  static const int magic = 0x534E4150;
  static const int headerSize = 32;
  static const int tokenSize = 16;

  // Message types
  static const int msgImage = 0x01;
  static const int msgPing = 0x02;
  static const int msgPong = 0x03;
  static const int msgPairRequest = 0x04;
  static const int msgPairAccept = 0x05;
  static const int msgImageAck = 0x06; // reply to IMAGE: payload 1=copied, 0=dropped
  static const int msgPairReject = 0x07; // pairing refused (PC locked)

  // Image formats
  static const int imgPng = 0x01;
  static const int imgJpeg = 0x02;

  static const int defaultPort = 49152;
  static const String serviceType = '_magicpaste._tcp';

  /// Normalise a token to exactly [tokenSize] bytes (zero-padded / truncated).
  static Uint8List normToken(Uint8List? token) {
    final out = Uint8List(tokenSize);
    if (token != null) {
      final n = token.length < tokenSize ? token.length : tokenSize;
      out.setRange(0, n, token);
    }
    return out;
  }

  /// Parse a hex token string ("a1b2…") into [tokenSize] bytes, or zeros.
  static Uint8List tokenFromHex(String? hex) {
    if (hex == null || hex.isEmpty) return Uint8List(tokenSize);
    final clean = hex.trim();
    final out = Uint8List(tokenSize);
    for (var i = 0; i + 1 < clean.length && i ~/ 2 < tokenSize; i += 2) {
      out[i ~/ 2] = int.tryParse(clean.substring(i, i + 2), radix: 16) ?? 0;
    }
    return out;
  }

  /// Build a 32-byte header carrying an optional 16-byte auth token.
  static Uint8List buildHeader(int msgType, int payloadLen, [Uint8List? token]) {
    final b = ByteData(headerSize);
    b.setUint32(0, magic, Endian.big);
    b.setUint32(4, msgType, Endian.big);
    b.setUint32(8, payloadLen, Endian.big);
    b.setUint32(12, 0, Endian.big);
    final out = b.buffer.asUint8List();
    out.setRange(16, 32, normToken(token));
    return out;
  }

  /// Build a full IMAGE message (header + 12-byte prefix + raw bytes).
  static Uint8List buildImageMessage(
    int imageFormat,
    int width,
    int height,
    Uint8List raw, [
    Uint8List? token,
  ]) {
    final prefix = ByteData(12);
    prefix.setUint32(0, imageFormat, Endian.big);
    prefix.setUint32(4, width, Endian.big);
    prefix.setUint32(8, height, Endian.big);

    final payloadLen = 12 + raw.length;
    final header = buildHeader(msgImage, payloadLen, token);

    final out = BytesBuilder();
    out.add(header);
    out.add(prefix.buffer.asUint8List());
    out.add(raw);
    return out.toBytes();
  }

  /// Build a small/empty-payload message (PING, PAIR_REQUEST, ...).
  static Uint8List buildSimpleMessage(int msgType,
      [Uint8List? payload, Uint8List? token]) {
    final p = payload ?? Uint8List(0);
    final header = buildHeader(msgType, p.length, token);
    final out = BytesBuilder();
    out.add(header);
    out.add(p);
    return out.toBytes();
  }

  /// Parse a 16-byte header. Returns (msgType, payloadLen) or throws.
  static (int, int) parseHeader(Uint8List data) {
    if (data.length < headerSize) {
      throw const FormatException('header too short');
    }
    final b = ByteData.sublistView(data, 0, headerSize);
    final m = b.getUint32(0, Endian.big);
    if (m != magic) {
      throw FormatException('bad magic: 0x${m.toRadixString(16)}');
    }
    final msgType = b.getUint32(4, Endian.big);
    final payloadLen = b.getUint32(8, Endian.big);
    return (msgType, payloadLen);
  }
}
