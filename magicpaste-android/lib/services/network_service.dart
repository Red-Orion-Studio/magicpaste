// Handles the TCP connection to the Windows PC and sending images.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'protocol.dart';

enum PairStatus {
  ok, // paired — token + name returned
  refused, // PC reachable but locked (needs "Allow new device" on the PC)
  failed, // couldn't reach the PC / no valid reply
}

/// Result of a pairing handshake.
class PairResult {
  final PairStatus status;
  final String? token;
  final String? pcName;
  const PairResult(this.status, {this.token, this.pcName});
  bool get ok => status == PairStatus.ok;
}

class NetworkService {
  /// Send a single image to [host]:[port]. Opens a short-lived connection,
  /// sends the IMAGE message, then closes. Returns true on success.
  static Future<bool> sendImage({
    required String host,
    required int port,
    required Uint8List imageBytes,
    required int imageFormat,
    required int width,
    required int height,
    String? token,
    Duration timeout = const Duration(seconds: 8),
  }) async {
    Socket? socket;
    try {
      socket = await Socket.connect(host, port, timeout: timeout);
      final message = Protocol.buildImageMessage(
        imageFormat,
        width,
        height,
        imageBytes,
        Protocol.tokenFromHex(token),
      );
      socket.add(message);
      await socket.flush();
      // Wait for the PC's ACK: 1 = copied, 0 = dropped (paused/error). A
      // missing ACK is treated as delivered so we stay resilient.
      final completer = Completer<bool>();
      final buffer = BytesBuilder();
      socket.listen(
        (data) {
          buffer.add(data);
          final bytes = buffer.toBytes();
          if (bytes.length >= Protocol.headerSize && !completer.isCompleted) {
            try {
              final (msgType, payloadLen) = Protocol.parseHeader(bytes);
              if (msgType != Protocol.msgImageAck) {
                completer.complete(true);
                return;
              }
              if (bytes.length < Protocol.headerSize + payloadLen) return;
              final pl = bytes.sublist(
                  Protocol.headerSize, Protocol.headerSize + payloadLen);
              completer.complete(pl.isEmpty || pl[0] != 0);
            } catch (_) {
              completer.complete(true);
            }
          }
        },
        onError: (_) {
          if (!completer.isCompleted) completer.complete(true);
        },
        onDone: () {
          if (!completer.isCompleted) completer.complete(true);
        },
      );
      return await completer.future
          .timeout(const Duration(seconds: 5), onTimeout: () => true);
    } catch (_) {
      return false;
    } finally {
      try {
        await socket?.close();
      } catch (_) {}
      socket?.destroy();
    }
  }

  /// Send a PAIR_REQUEST and wait for the PC's reply.
  ///
  /// Returns a [PairResult] with status: ok (token + name), refused (PC
  /// reachable but locked — the user must open "Allow new device" on the PC),
  /// or failed (unreachable / no valid reply). If we already hold a token
  /// (paired via QR) we present it so the PC recognises us.
  static Future<PairResult> pair({
    required String host,
    required int port,
    required String deviceName,
    String? token,
    Duration timeout = const Duration(seconds: 8),
  }) async {
    Socket? socket;
    try {
      socket = await Socket.connect(host, port, timeout: timeout);
      final payload = Uint8List.fromList(deviceName.codeUnits);
      socket.add(Protocol.buildSimpleMessage(
          Protocol.msgPairRequest, payload, Protocol.tokenFromHex(token)));
      await socket.flush();

      final completer = Completer<PairResult>();
      final buffer = BytesBuilder();
      late StreamSubscription sub;
      sub = socket.listen(
        (data) {
          buffer.add(data);
          if (buffer.length >= Protocol.headerSize && !completer.isCompleted) {
            try {
              final bytes = buffer.toBytes();
              final (msgType, payloadLen) = Protocol.parseHeader(bytes);
              if (msgType == Protocol.msgPairReject) {
                completer.complete(const PairResult(PairStatus.refused));
                return;
              }
              if (msgType != Protocol.msgPairAccept) {
                completer.complete(const PairResult(PairStatus.failed));
                return;
              }
              // Wait for the full payload (JSON: token + PC name) first.
              if (bytes.length < Protocol.headerSize + payloadLen) return;
              final payload = bytes.sublist(
                  Protocol.headerSize, Protocol.headerSize + payloadLen);
              final text = utf8.decode(payload, allowMalformed: true).trim();
              String? tok;
              String? name;
              try {
                final m = jsonDecode(text) as Map<String, dynamic>;
                tok = (m['token'] as String?)?.trim();
                name = (m['name'] as String?)?.trim();
              } catch (_) {
                tok = text; // legacy: payload was the raw token hex
              }
              // Prefer the PC's token; fall back to the one we already had.
              completer.complete(PairResult(
                PairStatus.ok,
                token: (tok != null && tok.isNotEmpty) ? tok : token,
                pcName: (name != null && name.isNotEmpty) ? name : null,
              ));
            } catch (_) {
              completer.complete(const PairResult(PairStatus.failed));
            }
          }
        },
        onError: (_) {
          if (!completer.isCompleted) {
            completer.complete(const PairResult(PairStatus.failed));
          }
        },
        onDone: () {
          if (!completer.isCompleted) {
            completer.complete(const PairResult(PairStatus.failed));
          }
        },
      );

      final result = await completer.future.timeout(
        timeout,
        onTimeout: () => const PairResult(PairStatus.failed),
      );
      await sub.cancel();
      return result;
    } catch (_) {
      return const PairResult(PairStatus.failed);
    } finally {
      try {
        await socket?.close();
      } catch (_) {}
      socket?.destroy();
    }
  }

  /// Quick reachability check using a PING/PONG exchange.
  static Future<bool> ping({
    required String host,
    required int port,
    String? token,
    Duration timeout = const Duration(seconds: 4),
  }) async {
    Socket? socket;
    try {
      socket = await Socket.connect(host, port, timeout: timeout);
      socket.add(Protocol.buildSimpleMessage(
          Protocol.msgPing, null, Protocol.tokenFromHex(token)));
      await socket.flush();
      final completer = Completer<bool>();
      final buffer = BytesBuilder();
      socket.listen(
        (data) {
          buffer.add(data);
          if (buffer.length >= Protocol.headerSize && !completer.isCompleted) {
            try {
              final (msgType, _) = Protocol.parseHeader(buffer.toBytes());
              completer.complete(msgType == Protocol.msgPong);
            } catch (_) {
              completer.complete(false);
            }
          }
        },
        onError: (_) {
          if (!completer.isCompleted) completer.complete(false);
        },
        onDone: () {
          if (!completer.isCompleted) completer.complete(false);
        },
      );
      return await completer.future.timeout(timeout, onTimeout: () => false);
    } catch (_) {
      return false;
    } finally {
      socket?.destroy();
    }
  }
}
