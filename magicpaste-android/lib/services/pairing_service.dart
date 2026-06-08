// Stores the paired Windows PC address and discovers it via mDNS.

import 'dart:async';

import 'package:nsd/nsd.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'protocol.dart';

class PairedPc {
  final String host;
  final int port;
  final String? token; // hex auth secret presented on every message
  final String? name;  // PC display name (hostname), for nicer UI
  const PairedPc(this.host, this.port, [this.token, this.name]);
}

class PairingService {
  static const _kHost = 'paired_host';
  static const _kPort = 'paired_port';
  static const _kToken = 'paired_token';
  static const _kPcName = 'paired_pc_name';

  static Future<PairedPc?> getPaired() async {
    final prefs = await SharedPreferences.getInstance();
    final host = prefs.getString(_kHost);
    if (host == null || host.isEmpty) return null;
    final port = prefs.getInt(_kPort) ?? Protocol.defaultPort;
    final token = prefs.getString(_kToken);
    final name = prefs.getString(_kPcName);
    return PairedPc(host, port, token, name);
  }

  static Future<void> savePaired(String host, int port,
      [String? token, String? pcName]) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kHost, host);
    await prefs.setInt(_kPort, port);
    // The native background sender (ScreenshotScanner.kt) reads this key.
    if (token != null && token.isNotEmpty) {
      await prefs.setString(_kToken, token);
    }
    if (pcName != null && pcName.isNotEmpty) {
      await prefs.setString(_kPcName, pcName);
    } else {
      await prefs.remove(_kPcName);
    }
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kHost);
    await prefs.remove(_kPort);
    await prefs.remove(_kToken);
    await prefs.remove(_kPcName);
  }

  /// Parse "192.168.1.5", "192.168.1.5:49152" or "…:port?tk=<hex>" into
  /// host + port + optional token.
  static (String, int, String?) parseAddress(String input) {
    var trimmed = input.trim();
    String? token;
    final q = trimmed.indexOf('?');
    if (q >= 0) {
      final query = trimmed.substring(q + 1);
      trimmed = trimmed.substring(0, q);
      for (final part in query.split('&')) {
        if (part.startsWith('tk=')) token = part.substring(3);
      }
    }
    if (trimmed.contains(':')) {
      final parts = trimmed.split(':');
      final port = int.tryParse(parts[1]) ?? Protocol.defaultPort;
      return (parts[0], port, token);
    }
    return (trimmed, Protocol.defaultPort, token);
  }

  /// Discover MagicPaste PCs on the LAN via mDNS. Returns found addresses.
  /// Stops after [timeout] or when the first service resolves.
  static Future<List<PairedPc>> discover({
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final found = <PairedPc>[];
    Discovery? discovery;
    try {
      discovery = await startDiscovery(
        '${Protocol.serviceType}.',
        ipLookupType: IpLookupType.v4,
      );
      final completer = Completer<void>();
      discovery.addServiceListener((service, status) {
        if (status == ServiceStatus.found) {
          final addresses = service.addresses;
          final host = (addresses != null && addresses.isNotEmpty)
              ? addresses.first.address
              : null;
          if (host != null) {
            found.add(PairedPc(host, service.port ?? Protocol.defaultPort));
            if (!completer.isCompleted) completer.complete();
          }
        }
      });
      await completer.future.timeout(timeout, onTimeout: () {});
    } catch (_) {
      // mDNS not available / blocked — caller falls back to manual entry.
    } finally {
      if (discovery != null) {
        try {
          await stopDiscovery(discovery);
        } catch (_) {}
      }
    }
    return found;
  }
}
