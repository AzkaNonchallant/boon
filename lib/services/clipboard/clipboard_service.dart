import 'dart:async';

import 'package:flutter/services.dart';

/// Polls the desktop clipboard for text changes.
///
/// Why polling: Flutter has no clipboard-change callback on Windows.
/// The poll deduplicates by content and ignores the value Boon itself
/// just applied, so a synchronized clipboard cannot bounce back and
/// forth (loop prevention).
///
/// Android note (Phase 2): Android 10+ restricts background clipboard
/// reads — this only works while the app has focus on Android, and a
/// real mobile implementation needs native work.
class ClipboardService {
  final _copies = StreamController<String>.broadcast();
  Stream<String> get localCopies => _copies.stream;

  String _lastHash = '';
  Timer? _timer;

  void start({Duration interval = const Duration(milliseconds: 1200)}) {
    _timer?.cancel();
    _timer = Timer.periodic(interval, (_) => _poll());
  }

  Future<void> _poll() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text == null || text.isEmpty) return;
    if (text == _lastHash) return;
    _lastHash = text;
    if (!_copies.isClosed) _copies.add(text);
  }

  /// Call right after Boon applied a remote clipboard value, so the
  /// poller does not treat it as a fresh local copy.
  void markApplied(String text) {
    _lastHash = text;
  }

  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    await _copies.close();
  }
}
