import 'dart:async';
import 'dart:math';

import '../../core/networking/boon_link.dart';
import '../../core/networking/link_service.dart';
import '../../core/protocol/boon_message.dart';

/// Demo peer that pretends to be a connected Pixel 8 so the UI can be
/// shown/evaluated without a real phone. Strictly separated from the
/// real [LinkService]; enabled via Demo mode in Settings.
class MockLinkService implements BoonLink {
  final _appData = StreamController<SecureAppMessage>.broadcast();
  final _sessionsChanged = StreamController<void>.broadcast();

  Timer? _heartbeat;
  Timer? _mediaProgress;
  final _rng = Random();

  @override
  Stream<SecureAppMessage> get appData => _appData.stream;

  @override
  Stream<void> get sessionsChanged => _sessionsChanged.stream;

  @override
  bool get hasLinkedPeer => true;

  int _positionMs = 64000;
  static const _durationMs = 214000;

  @override
  Future<void> start() async {
    await Future<void>.delayed(const Duration(milliseconds: 900));
    // Initial device status (78%, charging — matches the reference).
    _emit(BoonMessage.tDeviceStatus, {
      'name': 'Pixel 8',
      'type': 'phone',
      'battery': 78,
      'charging': true,
      'platform': 'android',
    });
    _emit(BoonMessage.tMediaState, {
      'available': true,
      'playing': true,
      'title': 'Panasea',
      'artist': 'Rumah Sakit',
      'positionMs': _positionMs,
      'durationMs': _durationMs,
    });
    // A few historical notifications, like the reference screen.
    final now = DateTime.now();
    _emitNotification(
      'WhatsApp',
      'New message from Aldi',
      'Halo, kabar len?',
      now.subtract(const Duration(minutes: 3)),
    );
    _emitNotification(
      'Instagram',
      'New followers',
      '3 new followers this week',
      now.subtract(const Duration(hours: 5)),
    );
    _emitNotification(
      'Telegram',
      'Saved Messages',
      'Link saved from phone',
      now.subtract(const Duration(hours: 26)),
    );

    _heartbeat = Timer.periodic(const Duration(seconds: 20), (_) {
      _emit(BoonMessage.tDeviceStatus, {
        'name': 'Pixel 8',
        'type': 'phone',
        'battery': (75 + _rng.nextInt(20)),
        'charging': true,
        'platform': 'android',
      });
    });

    _mediaProgress = Timer.periodic(const Duration(milliseconds: 500), (_) {
      _positionMs = (_positionMs + 500) % _durationMs;
      _emit(BoonMessage.tMediaState, {
        'available': true,
        'playing': true,
        'title': 'Panasea',
        'artist': 'Rumah Sakit',
        'positionMs': _positionMs,
        'durationMs': _durationMs,
      });
    });
    _sessionsChanged.add(null);

    // Occasionally deliver an incoming clipboard sample.
    Timer(const Duration(seconds: 15), () {
      if (!_appData.isClosed) {
        _emit(BoonMessage.tClipboardText, {
          'text': 'https://flutter.dev — copied on Pixel 8',
        });
      }
    });
  }

  void _emitNotification(String app, String title, String body, DateTime time) {
    _appData.add(
      SecureAppMessage('mock-pixel-8', BoonMessage.tNotification, {
        'appId': app.toLowerCase(),
        'appName': app,
        'title': title,
        'body': body,
        'time': time.toIso8601String(),
      }),
    );
  }

  void _emit(String type, Map<String, dynamic> payload) {
    if (_appData.isClosed) return;
    _appData.add(SecureAppMessage('mock-pixel-8', type, payload));
  }

  @override
  Future<void> sendClipboardText(String text) async {
    // Demo: echo a transformed clipboard value so sync can be observed.
    await Future<void>.delayed(const Duration(milliseconds: 700));
    _emit(BoonMessage.tClipboardText, {'text': text});
  }

  @override
  Future<void> sendToPeer(
    String peerId,
    String type,
    Map<String, dynamic> payload,
  ) async {
    if (type == BoonMessage.tMediaAction) {
      final action = payload['action'] as String?;
      _positionMs = switch (action) {
        'next' => (_positionMs + 15000) % _durationMs,
        'prev' => (_positionMs - 15000 + _durationMs) % _durationMs,
        _ => _positionMs,
      };
    }
    if (type == BoonMessage.tSendText || type == BoonMessage.tSendLink) {
      await Future<void>.delayed(const Duration(milliseconds: 400));
      final preview = (payload['url'] ?? payload['text'] ?? '') as String;
      _emitNotification(
        'Boon',
        type == BoonMessage.tSendLink ? 'Link di terima' : 'Text di terima',
        preview.length > 48 ? '${preview.substring(0, 48)}…' : preview,
        DateTime.now(),
      );
    }
  }

  @override
  Future<void> stop() async {
    _heartbeat?.cancel();
    _mediaProgress?.cancel();
    await _appData.close();
    await _sessionsChanged.close();
  }
}
