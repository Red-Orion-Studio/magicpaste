// Persisted log of recently-sent screenshots, shown on Home (recent row) and
// History (grid). Stored as JSON in SharedPreferences. Thumbnails are kept as
// small base64 JPEGs so the UI can render a preview without re-reading the
// original file.

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class SentItem {
  final String name;
  final int width;
  final int height;
  final bool ok;
  final int timestampMs;
  final String? thumbB64; // small jpeg preview, optional

  const SentItem({
    required this.name,
    required this.width,
    required this.height,
    required this.ok,
    required this.timestampMs,
    this.thumbB64,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'w': width,
        'h': height,
        'ok': ok,
        'ts': timestampMs,
        if (thumbB64 != null) 'thumb': thumbB64,
      };

  factory SentItem.fromJson(Map<String, dynamic> j) => SentItem(
        name: j['name'] as String? ?? 'screenshot',
        width: j['w'] as int? ?? 0,
        height: j['h'] as int? ?? 0,
        ok: j['ok'] as bool? ?? true,
        timestampMs: j['ts'] as int? ?? 0,
        thumbB64: j['thumb'] as String?,
      );

  DateTime get time => DateTime.fromMillisecondsSinceEpoch(timestampMs);
}

class SentHistory {
  static const _kKey = 'mp_sent_history';
  static const _max = 50;

  static Future<List<SentItem>> load() async {
    final prefs = await SharedPreferences.getInstance();
    // The native WorkManager scanner writes history directly to the prefs XML
    // while the app runs; reload() pulls those external changes into Dart's
    // in-memory cache so the UI sees background auto-sends without a restart.
    await prefs.reload();
    final raw = prefs.getString(_kKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .map((e) => SentItem.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Prepend a new item (newest first), capped at [_max].
  static Future<void> add(SentItem item) async {
    final prefs = await SharedPreferences.getInstance();
    final items = await load();
    items.insert(0, item);
    final trimmed = items.take(_max).toList();
    await prefs.setString(
      _kKey,
      jsonEncode(trimmed.map((e) => e.toJson()).toList()),
    );
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kKey);
  }
}
