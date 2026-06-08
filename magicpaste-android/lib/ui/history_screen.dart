import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../services/l10n.dart';
import '../services/sent_history.dart';
import 'theme.dart';

class HistoryScreen extends StatefulWidget {
  final ValueChanged<int> onNavigate;
  const HistoryScreen({super.key, required this.onNavigate});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<SentItem> _items = [];
  bool _loaded = false;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _load();
    // Kept alive inside an IndexedStack, so poll to pick up background sends.
    _poll = Timer.periodic(const Duration(seconds: 5), (_) => _load());
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  String _sig = '';

  Future<void> _load() async {
    final items = await SentHistory.load();
    if (!mounted) return;
    // Only rebuild when the list actually changed, so the periodic poll
    // doesn't re-instantiate Image.memory widgets and cause flicker.
    final sig = items.map((e) => '${e.timestampMs}:${e.ok}').join(',');
    if (sig == _sig && _loaded) return;
    setState(() {
      _items = items;
      _loaded = true;
      _sig = sig;
    });
  }

  Future<void> _clear() async {
    await SentHistory.clear();
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(L10n.t('history_title'),
                      style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                          color: MP.textPrimary,
                          letterSpacing: -0.5)),
                  const SizedBox(height: 2),
                  Text(L10n.t('screenshots_sent', {'n': '${_items.length}'}),
                      style: const TextStyle(fontSize: 12, color: MP.textMuted)),
                ],
              ),
              if (_items.isNotEmpty)
                TextButton.icon(
                  onPressed: _clear,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    backgroundColor: MP.glass,
                    foregroundColor: MP.textSec,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                      side: const BorderSide(color: MP.glassBorder),
                    ),
                  ),
                  icon: const Icon(Icons.delete_outline, size: 14),
                  label: Text(L10n.t('clear'), style: const TextStyle(fontSize: 12)),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: !_loaded
                ? const SizedBox.shrink()
                : _items.isEmpty
                    ? const _EmptyHistory()
                    : GridView.builder(
                        padding: const EdgeInsets.only(bottom: 16),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          mainAxisSpacing: 10,
                          crossAxisSpacing: 10,
                          childAspectRatio: 0.78,
                        ),
                        itemCount: _items.length,
                        itemBuilder: (_, i) => _HistoryCard(item: _items[i]),
                      ),
          ),
        ],
      ),
    );
  }
}

class _EmptyHistory extends StatelessWidget {
  const _EmptyHistory();
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: MP.glass,
              border: Border.all(color: MP.glassBorder),
            ),
            child: const Icon(Icons.photo_library_outlined, size: 32, color: MP.textMuted),
          ),
          const SizedBox(height: 16),
          Text(L10n.t('no_ss_yet'),
              style: const TextStyle(fontSize: 15, color: MP.textSec, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Text(L10n.t('take_ss_to_send'),
              style: const TextStyle(fontSize: 12, color: MP.textMuted)),
        ],
      ),
    );
  }
}

class _HistoryCard extends StatelessWidget {
  final SentItem item;
  const _HistoryCard({required this.item});

  String _fmt(DateTime t) {
    final now = DateTime.now();
    final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final m = t.minute.toString().padLeft(2, '0');
    final ap = t.hour < 12 ? 'AM' : 'PM';
    final hm = '$h:$m $ap';
    final sameDay = t.year == now.year && t.month == now.month && t.day == now.day;
    final yest = now.subtract(const Duration(days: 1));
    final isYest = t.year == yest.year && t.month == yest.month && t.day == yest.day;
    if (sameDay) return '${L10n.t('today')} $hm';
    if (isYest) return '${L10n.t('yesterday')} $hm';
    final months = L10n.t('months_abbr').split(',');
    return '${months[t.month - 1]} ${t.day} $hm';
  }

  @override
  Widget build(BuildContext context) {
    Uint8List? thumb;
    if (item.thumbB64 != null) {
      try {
        thumb = base64Decode(item.thumbB64!);
      } catch (_) {}
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        color: MP.glass,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: MP.glassBorder),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Container(
                    color: const Color(0xFF2A2730),
                    child: thumb != null
                        ? Image.memory(thumb, fit: BoxFit.cover, gaplessPlayback: true)
                        : const Icon(Icons.image_outlined, color: MP.textMuted),
                  ),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: item.ok ? const Color(0xE022C55E) : const Color(0xE0EF4444),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(L10n.t(item.ok ? 'sent_badge' : 'failed_badge'),
                          style: const TextStyle(
                              fontSize: 9, fontWeight: FontWeight.w700, color: Colors.white, letterSpacing: 0.6)),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Text(_fmt(item.time),
                  style: const TextStyle(fontSize: 11, color: MP.textSec)),
            ),
          ],
        ),
      ),
    );
  }
}
