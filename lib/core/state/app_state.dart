import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/companion/android_companion.dart';
import '../../services/companion/companion_bridge.dart';
import '../../services/companion/foreground_service.dart';
import '../../services/companion/android_files.dart';
import '../../services/transfer/transfer_service.dart' show TransferService;
import '../models/activity_event.dart';
import '../models/boon_device.dart';
import '../models/media_state.dart';
import '../models/phone_notification.dart';
import '../models/transfer_record.dart';
import '../networking/boon_link.dart';
import '../networking/link_service.dart';
import '../protocol/boon_message.dart';
import '../security/device_identity.dart';
import '../security/trusted_store.dart';
import '../../services/clipboard/clipboard_service.dart';
import '../../services/mock/mock_link_service.dart';

enum SyncDirection { both, phoneToDesktop, desktopToPhone }

enum SensitivePolicy { allow, discard }

/// Central application state: bridges the link services (real + demo),
/// clipboard sync, notifications, media, transfers and activity feed to
/// the UI. Mock (demo) data never mixes with real service output.
class AppState extends ChangeNotifier {
  DeviceIdentity? identity;
  LinkService? link;
  MockLinkService? mock;
  TransferService? transfer;
  final ClipboardService clipboard = ClipboardService();

  bool ready = false;

  /// Demo (Pixel 8 sample) data is off by default now that real connecting
  /// works end to end — mock must never sit on top of a live link. The
  /// toggle lives in Settings for UI-only evaluation (see SettingsPage).
  bool demoMode = false;

  // ---- Clipboard settings -------------------------------------------
  bool autoSync = true;
  SyncDirection syncDirection = SyncDirection.both;
  SensitivePolicy sensitivePolicy = SensitivePolicy.allow;
  DateTime? lastSync;

  // ---- Companion ----------------------------------------------------
  bool notificationsEnabled = true;
  bool privacyMode = false;
  bool autoSaveMediaToGallery = false;

  /// True on Android builds: this device can mirror notifications/media.
  final bool companionSupported = CompanionBridge.available;

  /// Whether Android Notification Access is granted on THIS device. The
  /// desktop reads the remote phone's value from its status broadcast
  /// (see [DeviceStatusData.notificationsReady]) — desktop itself has no
  /// listener, so this stays false there.
  bool notificationListenerActive = false;

  /// Android foreground service: raises process priority while backgrounded
  /// so the link, status broadcast and clipboard delivery keep working.
  /// Starts on app init; stops only when the user toggles it off — never
  /// on app lifecycle events. Default ON (Android requires the persistent
  /// notification anyway).
  bool keepLinkAlive = true;
  final Map<String, DeviceStatusData> statusByDevice = {};
  final List<PhoneNotification> phoneNotifications = [];
  final Map<String, String> notificationAppNames = {};
  final Map<String, bool> notificationAppEnabled = {};
  MediaState media = MediaState.empty;
  Uint8List? screenFrame;
  String? screenFramePeerId;
  String? screenViewerId;
  String? screenError;
  String? screenStage;
  bool _sentFirstScreenFrame = false;
  int screenFrameWidth = 0;
  int screenFrameHeight = 0;

  // ---- Activity -----------------------------------------------------
  final List<ActivityEvent> activities = [];

  /// Transfer destination override (null = primary device).
  String? selectedDeviceId;

  void selectDevice(String id) {
    selectedDeviceId = id;
    notifyListeners();
  }

  List<TransferRecord> get transfers => transfer?.history ?? const [];

  // ---- Pairing prompts surfaced to the shell ------------------------
  final Map<String, ({BoonDevice device, String code})> incomingPairings = {};
  final Map<String, ({String code, BoonDevice device})> outgoingCodes = {};
  List<BoonDevice> discovered = [];

  StreamSubscription? _pairSub;
  StreamSubscription? _appSub;
  StreamSubscription? _sessionSub;
  StreamSubscription? _clipSub;
  StreamSubscription? _discoverySub;
  StreamSubscription? _companionSub;
  Timer? _deviceStatusTimer;
  Timer? _screenFrameTimeout;
  bool _screenFrameSending = false;
  bool _loggedScreenFrameEvent = false;
  bool _loggedScreenFrameQueue = false;
  bool _loggedScreenFrameReceived = false;

  Map<String, PairedDevice> get trustedDevices => link?.trusted.all ?? {};

  /// The device the UI shows as primary companion (Pixel 8 card).
  /// Real devices always win over the demo peer — demo data never
  /// masks a live connection, it only fills the empty state.
  BoonDevice? get primaryDevice {
    final list = connectedDevices;
    if (list.isEmpty) return null;
    final real = list.where((d) => d.id != 'mock-pixel-8');
    if (real.isEmpty) {
      return list.first; // demo only
    }
    final realPhone = real.where((d) => d.type == DeviceType.phone);
    if (realPhone.isNotEmpty) return realPhone.first;
    return real.first;
  }

  List<BoonDevice> get connectedDevices =>
      statusByDevice.values.map((s) => s.device).toList();

  DeviceStatusData? get primaryStatus {
    final device = primaryDevice;
    if (device == null) return null;
    return statusByDevice[device.id];
  }

  bool get hasOnlinePeer =>
      (link != null && link!.hasLinkedPeer) || mock != null && ready;

  // ==================================================================
  // Lifecycle
  // ==================================================================

  Future<void> init() async {
    if (ready) return;
    identity = await DeviceIdentity.load();
    await _loadGalleryPreference();
    await _loadNotificationAppPreferences();
    // Android: hold the Wi-Fi multicast lock before the discovery socket
    // binds, otherwise the kernel drops multicast/broadcast packets.
    await AndroidCompanion.acquireMulticast();
    await AndroidCompanion.start();
    if (CompanionBridge.available) {
      notificationListenerActive = await CompanionBridge.isListening();
      await CompanionBridge.requestRebind();
      _companionSub = CompanionBridge.events.listen(_onCompanionEvent);
    }
    // Android: foreground service before link.start() so the sockets and
    // timers being created here survive backgrounding immediately.
    if (ForegroundService.available) {
      await _loadKeepLinkAlive();
      if (keepLinkAlive) {
        await ForegroundService.start();
        await ForegroundService.ensureNotificationPermission();
      }
    }
    link = LinkService(identity!);
    await link!.start();

    _pairSub = link!.pairingEvents.listen(_onPairingEvent);
    _appSub = link!.appData.listen(
      (m) => unawaited(_onAppMessage(m.peerId, m.type, m.payload)),
    );
    _sessionSub = link!.sessionsChanged.listen((_) {
      notifyListeners();
      // A peer just (re)connected: refresh its snapshot instead of waiting
      // for the next 30s status tick / media change.
      unawaited(_broadcastSelfStatus());
      if (CompanionBridge.available) {
        if (media.available) {
          unawaited(
            link?.broadcastApp(BoonMessage.tMediaState, media.toJson()),
          );
        }
      }
    });
    _discoverySub = link!.discoveredPeers.listen((list) {
      discovered = list;
      notifyListeners();
    });

    transfer = TransferService(
      link: _TransferSendAdapter(this),
      getPeerName: (peerId) => statusByDevice[peerId]?.device.name ?? 'Device',
      onUpdated: notifyListeners,
      onIncomingCompleted: _onIncomingTransferCompleted,
    );
    await transfer!.loadHistory();

    await setDemoMode(demoMode);

    clipboard.start();
    _clipSub = clipboard.localCopies.listen(
      (text) => unawaited(_onLocalClipboard(text)),
    );

    _deviceStatusTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      unawaited(_broadcastSelfStatus());
    });

    ready = true;
    notifyListeners();
  }

  Future<void> setDemoMode(bool on) async {
    demoMode = on;
    if (on && mock == null) {
      final m = MockLinkService();
      mock = m;
      m.appData.listen(
        (msg) =>
            unawaited(_onAppMessage('mock-pixel-8', msg.type, msg.payload)),
      );
      m.sessionsChanged.listen((_) => notifyListeners());
      await m.start();
      notifyListeners();
    } else if (!on) {
      await mock?.stop();
      mock = null;
      statusByDevice.remove('mock-pixel-8');
      media = MediaState.empty;
      notifyListeners();
    }
  }

  /// Publishes this device's own status to every paired peer. Battery and
  /// charging come from the real ACTION_BATTERY_CHANGED broadcast on
  /// Android; on desktop those fields are simply omitted.
  Future<void> _broadcastSelfStatus() async {
    final battery = await AndroidCompanion.readBattery();
    final payload = <String, dynamic>{
      'platform': identity!.type,
      'name': identity!.name,
      if (battery != null) 'battery': battery.level,
      if (battery != null) 'charging': battery.charging,
      // Tells the desktop whether Phone Buddy can actually receive
      // notifications/media from this phone right now.
      if (companionSupported)
        'notificationListener': notificationListenerActive,
      if (companionSupported)
        'screenControl': await CompanionBridge.isAccessibilityEnabled(),
    };
    await link?.broadcastStatus(payload);
  }

  /// Re-checks Android Notification Access (granted/revoked outside the app)
  /// and re-announces capabilities when it changed.
  Future<void> refreshCompanionStatus() async {
    if (!CompanionBridge.available) return;
    final wasActive = notificationListenerActive;
    notificationListenerActive = await CompanionBridge.isListening();
    await CompanionBridge.requestRebind();
    if (wasActive != notificationListenerActive) {
      addActivity(
        ActivityKind.info,
        'Companion access',
        notificationListenerActive
            ? 'Notification and media access granted'
            : 'Notification access was turned off',
      );
      await _broadcastSelfStatus();
      notifyListeners();
    }
  }

  /// Opens the Android Notification Access screen (phone side only).
  Future<void> openNotificationListenerSettings() =>
      CompanionBridge.openListenerSettings();

  /// Asks a paired phone to open its Notification Access screen — used by
  /// the desktop when the phone reports that mirroring is not enabled.
  Future<void> requestNotificationAccess(String peerId) async {
    await link?.sendToPeer(peerId, BoonMessage.tCompanionAction, {
      'action': 'open_notification_settings',
    });
    addActivity(
      ActivityKind.info,
      'Request sent',
      'Check the phone to grant notification access',
    );
    notifyListeners();
  }

  // ------------------------------------------------------------------
  // Native companion events (Android only)
  // ------------------------------------------------------------------

  void _onCompanionEvent(Map<String, dynamic> event) {
    switch (event['kind']) {
      case 'listener':
        final connected = event['connected'] == true;
        if (connected == notificationListenerActive) return;
        notificationListenerActive = connected;
        unawaited(_broadcastSelfStatus());
        notifyListeners();

      case 'notification':
        final appId = event['appId'] as String? ?? 'app';
        notificationAppNames[appId] = event['appName'] as String? ?? appId;
        notificationAppEnabled.putIfAbsent(appId, () => true);
        unawaited(_persistNotificationAppPreferences());
        notifyListeners();
        unawaited(_mirrorNotification(event));

      case 'media':
        unawaited(_mirrorMedia(event));

      case 'screen_frame':
        if (!_loggedScreenFrameEvent) {
          _loggedScreenFrameEvent = true;
          debugPrint(
            'Phone Buddy: native frame event received (${(event['data'] as String?)?.length ?? 0} chars; viewer=${screenViewerId != null})',
          );
        }
        screenError = null;
        unawaited(_mirrorScreenFrame(event));

      case 'screen_started':
        _sendScreenStatus('screen_share_started');

      case 'screen_error':
        _sendScreenStatus('screen_share_error', {
          'message':
              event['message'] as String? ??
              'Android could not start screen capture.',
        });

      case 'screen_stopped':
        final viewer = screenViewerId;
        screenViewerId = null;
        if (viewer != null) {
          unawaited(
            link?.sendToPeer(viewer, BoonMessage.tCompanionAction, {
              'action': 'screen_share_stopped',
            }),
          );
        }
        notifyListeners();
    }
  }

  Future<void> _mirrorNotification(Map<String, dynamic> event) async {
    // The desktop also gates on this; checking here avoids sending when the
    // user paused mirroring so the phone radio stays quiet.
    if (!notificationsEnabled) return;
    final appId = event['appId'] as String? ?? 'app';
    if (notificationAppEnabled[appId] == false) return;
    final timeMs =
        (event['time'] as num?)?.toInt() ??
        DateTime.now().millisecondsSinceEpoch;
    await link?.broadcastApp(BoonMessage.tNotification, {
      'appId': appId,
      'appName': event['appName'] as String? ?? 'App',
      'title': event['title'] as String? ?? '',
      'body': event['body'] as String? ?? '',
      'time': DateTime.fromMillisecondsSinceEpoch(timeMs).toIso8601String(),
    });
  }

  Future<void> _mirrorMedia(Map<String, dynamic> event) async {
    final next = MediaState(
      available: event['available'] == true,
      playing: event['playing'] == true,
      title: event['title'] as String?,
      artist: event['artist'] as String?,
      album: event['album'] as String?,
      positionMs: (event['positionMs'] as num?)?.toInt(),
      durationMs: (event['durationMs'] as num?)?.toInt(),
    );
    media = next;
    await link?.broadcastApp(BoonMessage.tMediaState, next.toJson());
    notifyListeners();
  }

  Future<void> _mirrorScreenFrame(Map<String, dynamic> event) async {
    final viewer = screenViewerId;
    final data = event['data'] as String?;
    if (viewer == null || data == null || data.isEmpty || _screenFrameSending) {
      return;
    }
    _screenFrameSending = true;
    try {
      await link?.sendToPeer(viewer, BoonMessage.tScreenFrame, {
        'data': data,
        'width': event['width'],
        'height': event['height'],
      });
      if (!_loggedScreenFrameQueue) {
        debugPrint('Phone Buddy: screen frame queued to paired peer');
        _loggedScreenFrameQueue = true;
      }
      if (!_sentFirstScreenFrame) {
        _sentFirstScreenFrame = true;
        _sendScreenStatus('screen_first_frame_sent');
      }
    } finally {
      _screenFrameSending = false;
    }
  }

  void _sendScreenStatus(
    String action, [
    Map<String, dynamic> extra = const {},
  ]) {
    final viewer = screenViewerId;
    if (viewer == null) return;
    unawaited(
      link?.sendToPeer(viewer, BoonMessage.tCompanionAction, {
        'action': action,
        ...extra,
      }),
    );
  }

  /// Public wrapper used by the phone shell: sends an immediate self-status
  /// broadcast when the app resumes (so the desktop sees fresh Last Seen /
  /// battery before the next 30s tick). Avoids protected warnings.
  Future<void> pushSelfStatus() => _broadcastSelfStatus();

  @override
  void dispose() {
    _pairSub?.cancel();
    _appSub?.cancel();
    _sessionSub?.cancel();
    _clipSub?.cancel();
    _discoverySub?.cancel();
    _companionSub?.cancel();
    _deviceStatusTimer?.cancel();
    _screenFrameTimeout?.cancel();
    unawaited(AndroidCompanion.releaseMulticast());
    unawaited(AndroidCompanion.stop());
    unawaited(clipboard.stop());
    unawaited(link?.stop());
    unawaited(mock?.stop());
    super.dispose();
  }

  // ==================================================================
  // Local clipboard -> peers
  // ==================================================================

  Future<void> _onLocalClipboard(String text) async {
    if (!autoSync || syncDirection == SyncDirection.phoneToDesktop) return;
    if (!hasOnlinePeer) return;
    lastSync = DateTime.now();
    await mock?.sendClipboardText(text);
    await link?.sendClipboardText(text);
    final sensitive = sensitivePolicy == SensitivePolicy.discard;
    addActivity(
      ActivityKind.clipboard,
      sensitive ? 'Clipboard synced' : 'Copied From Desktop',
      sensitive
          ? '${text.length} chars • kept out of content history'
          : '${text.length} chars shared',
    );
    notifyListeners();
  }

  /// Reads the local clipboard and pushes it to peers. Used by the desktop
  /// Phone Buddy and, with [quiet], by the phone shell on resume — Android
  /// blocks background clipboard reads, so the moment the app regains focus
  /// is the honest "sync now" moment. [quiet] suppresses the "nothing to
  /// sync" activity entry so resume doesn't spam the feed.
  Future<void> syncNow({bool quiet = false}) async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text == null || text.isEmpty) {
      if (!quiet) {
        addActivity(
          ActivityKind.info,
          'Nothing to sync',
          'Desktop clipboard is empty',
        );
        notifyListeners();
      }
      return;
    }
    await _onLocalClipboard(text);
    // The resume/manual push covers the poller's pending change too —
    // mark it applied so the next poll tick can't re-send the same text.
    clipboard.markApplied(text);
  }

  // ==================================================================
  // Incoming secure messages
  // ==================================================================

  Future<void> _onAppMessage(
    String peerId,
    String type,
    Map<String, dynamic> payload,
  ) async {
    switch (type) {
      case BoonMessage.tClipboardText:
        if (syncDirection == SyncDirection.desktopToPhone) return;
        final text = payload['text'] as String? ?? '';
        if (text.isEmpty) return;
        await Clipboard.setData(ClipboardData(text: text));
        clipboard.markApplied(text);
        lastSync = DateTime.now();
        final sensitive = sensitivePolicy == SensitivePolicy.discard;
        addActivity(
          ActivityKind.clipboard,
          sensitive ? 'Clipboard received' : 'Copied From Phone',
          sensitive
              ? 'content not stored'
              : '${text.length} chars • paste with Ctrl+V',
        );
        notifyListeners();

      case BoonMessage.tDeviceStatus:
        final existing = statusByDevice[peerId];
        final device =
            existing?.device ??
            BoonDevice(
              id: peerId,
              name: payload['name'] as String? ?? 'Device',
              type: peerId == 'mock-pixel-8'
                  ? DeviceType.phone
                  : DeviceType.unknown,
              status: DeviceStatus.online,
            );
        device.status = DeviceStatus.online;
        final battery = payload['battery'];
        if (battery is int) device.battery = battery;
        device.charging = payload['charging'] == true;
        device.lastSeen = DateTime.now();
        statusByDevice[peerId] = DeviceStatusData(
          device: device,
          online: true,
          notificationsReady: payload['notificationListener'] == true,
          screenControl: payload['screenControl'] == true,
        );
        notifyListeners();

      case BoonMessage.tMediaState:
        media = MediaState.fromJson(payload);
        notifyListeners();

      case BoonMessage.tMediaAction:
        // Desktop pressed play/pause/next: drive the real session here.
        final action = payload['action'] as String? ?? '';
        if (action.isEmpty || !CompanionBridge.available) return;
        final applied = await CompanionBridge.applyMediaAction(action);
        if (!applied) {
          addActivity(
            ActivityKind.info,
            'Media control',
            'No active media session on this phone',
          );
          notifyListeners();
        }

      case BoonMessage.tCompanionAction:
        final action = payload['action'] as String? ?? '';
        if (action == 'open_notification_settings' &&
            CompanionBridge.available) {
          await CompanionBridge.openListenerSettings();
          addActivity(
            ActivityKind.info,
            'Notification access',
            'Enable Boon to mirror notifications',
          );
          notifyListeners();
        } else if (action == 'set_notifications_enabled' &&
            CompanionBridge.available) {
          notificationsEnabled = payload['enabled'] == true;
          notifyListeners();
        } else if (action == 'start_screen_share' &&
            CompanionBridge.available) {
          screenViewerId = peerId;
          _loggedScreenFrameEvent = false;
          _loggedScreenFrameQueue = false;
          unawaited(CompanionBridge.requestScreenShare());
        } else if (action == 'stop_screen_share' && CompanionBridge.available) {
          screenViewerId = null;
          unawaited(CompanionBridge.stopScreenShare());
        } else if (action == 'screen_tap' && CompanionBridge.available) {
          unawaited(
            CompanionBridge.tapScreen(
              (payload['x'] as num?)?.toDouble() ?? -1,
              (payload['y'] as num?)?.toDouble() ?? -1,
            ),
          );
        } else if (action == 'open_accessibility_settings' &&
            CompanionBridge.available) {
          unawaited(CompanionBridge.openAccessibilitySettings());
        } else if (action == 'screen_share_stopped') {
          screenFrame = null;
          screenFramePeerId = null;
          screenFrameWidth = 0;
          screenFrameHeight = 0;
          notifyListeners();
        } else if (action == 'screen_share_started') {
          screenError = null;
          screenStage = 'Capture started; waiting for first frame…';
          notifyListeners();
        } else if (action == 'screen_first_frame_sent') {
          screenStage = 'Phone is sending the screen…';
          notifyListeners();
        } else if (action == 'screen_share_error') {
          screenError =
              payload['message'] as String? ?? 'Screen capture failed.';
          notifyListeners();
        }

      case BoonMessage.tScreenFrame:
        if (peerId != screenFramePeerId) return;
        try {
          final data = payload['data'] as String?;
          if (data == null || data.isEmpty) return;
          if (!_loggedScreenFrameReceived) {
            _loggedScreenFrameReceived = true;
            debugPrint(
              'Phone Buddy: desktop received screen frame (${data.length} chars)',
            );
          }
          screenFrame = base64Decode(data);
          _screenFrameTimeout?.cancel();
          screenError = null;
          screenStage = null;
          screenFramePeerId = peerId;
          screenFrameWidth = (payload['width'] as num?)?.toInt() ?? 0;
          screenFrameHeight = (payload['height'] as num?)?.toInt() ?? 0;
          notifyListeners();
        } catch (_) {
          // Ignore malformed screen frames from the authenticated peer.
        }

      case BoonMessage.tNotification:
        if (!notificationsEnabled) return;
        final appId = payload['appId'] as String? ?? 'app';
        final appName = payload['appName'] as String? ?? 'App';
        notificationAppNames.putIfAbsent(appId, () => appName);
        notificationAppEnabled.putIfAbsent(appId, () => true);
        unawaited(_persistNotificationAppPreferences());
        if (notificationAppEnabled[appId] == false) return;
        final time =
            DateTime.tryParse(payload['time'] as String? ?? '') ??
            DateTime.now();
        phoneNotifications.insert(
          0,
          PhoneNotification(
            id: '$peerId:${phoneNotifications.length}:$time',
            appId: appId,
            appName: appName,
            title: payload['title'] as String? ?? '',
            body: privacyMode ? null : payload['body'] as String?,
            time: time,
          ),
        );
        if (phoneNotifications.length > 12) phoneNotifications.removeLast();
        notifyListeners();

      case BoonMessage.tSendText:
        final text = payload['text'] as String? ?? '';
        addActivity(
          ActivityKind.clipboard,
          'Text received',
          'Saved to clipboard • ${text.length} chars',
        );
        await Clipboard.setData(ClipboardData(text: text));
        notifyListeners();

      case BoonMessage.tSendLink:
        final url = payload['url'] as String? ?? '';
        addActivity(ActivityKind.info, 'Link received', url);
        await Clipboard.setData(ClipboardData(text: url));
        notifyListeners();

      case BoonMessage.tTransferRequest:
      case BoonMessage.tTransferAccept:
      case BoonMessage.tTransferChunk:
      case BoonMessage.tTransferEnd:
      case BoonMessage.tTransferCancel:
      case BoonMessage.tTransferComplete:
        unawaited(transfer?.handle(peerId, type, payload));

      case BoonMessage.tTransferReject:
        unawaited(transfer?.handle(peerId, type, payload));
    }
  }

  // ==================================================================
  // Pairing events
  // ==================================================================

  void _onPairingEvent(PairingEvent event) {
    switch (event.stage) {
      case PairingEvent.incoming:
        incomingPairings[event.peerId] = (
          device: BoonDevice(
            id: event.peerId,
            name: event.peerName,
            type: DeviceType.unknown,
          ),
          code: event.verificationCode ?? '',
        );
      case PairingEvent.code:
        outgoingCodes[event.peerId] = (
          code: event.verificationCode ?? '',
          device: BoonDevice(
            id: event.peerId,
            name: event.peerName,
            type: DeviceType.unknown,
          ),
        );
      case PairingEvent.complete:
        incomingPairings.remove(event.peerId);
        outgoingCodes.remove(event.peerId);
        addActivity(
          ActivityKind.connection,
          'Device paired',
          '${event.peerName} is now trusted',
        );
      case PairingEvent.rejected:
        incomingPairings.remove(event.peerId);
        outgoingCodes.remove(event.peerId);
      case PairingEvent.outgoingWaiting:
        break;
      case PairingEvent.failed:
        outgoingCodes.remove(event.peerId);
        addActivity(
          ActivityKind.info,
          'Pairing failed',
          'Could not reach ${event.peerName}',
        );
    }
    notifyListeners();
  }

  // ==================================================================
  // Settings setters (public so pages never touch notifyListeners)
  // ==================================================================

  void setAutoSync(bool v) {
    autoSync = v;
    notifyListeners();
  }

  void setSyncDirection(SyncDirection d) {
    syncDirection = d;
    notifyListeners();
  }

  void setSensitivePolicy(SensitivePolicy p) {
    sensitivePolicy = p;
    notifyListeners();
  }

  void setNotificationsEnabled(bool v) {
    notificationsEnabled = v;
    notifyListeners();
    if (!CompanionBridge.available) {
      final device = primaryDevice;
      if (device != null) {
        unawaited(
          link?.sendToPeer(device.id, BoonMessage.tCompanionAction, {
            'action': 'set_notifications_enabled',
            'enabled': v,
          }),
        );
      }
    }
  }

  void setNotificationAppEnabled(String appId, bool enabled) {
    notificationAppEnabled[appId] = enabled;
    unawaited(_persistNotificationAppPreferences());
    notifyListeners();
  }

  Future<void> _loadNotificationAppPreferences() async {
    try {
      final dir = await DeviceIdentity.supportDir();
      final file = File(
        '${dir.path}${Platform.pathSeparator}notification-apps.json',
      );
      if (!await file.exists()) return;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return;
      for (final entry in decoded.entries) {
        if (entry.key is String && entry.value is Map) {
          final value = (entry.value as Map).cast<String, dynamic>();
          final appId = entry.key as String;
          notificationAppNames[appId] = value['name'] as String? ?? appId;
          notificationAppEnabled[appId] = value['enabled'] != false;
        }
      }
    } catch (_) {}
  }

  Future<void> _persistNotificationAppPreferences() async {
    try {
      final dir = await DeviceIdentity.supportDir();
      final file = File(
        '${dir.path}${Platform.pathSeparator}notification-apps.json',
      );
      final payload = <String, dynamic>{
        for (final appId in notificationAppNames.keys)
          appId: {
            'name': notificationAppNames[appId],
            'enabled': notificationAppEnabled[appId] != false,
          },
      };
      await file.writeAsString(jsonEncode(payload));
    } catch (_) {}
  }

  void setPrivacyMode(bool v) {
    privacyMode = v;
    notifyListeners();
  }

  void setAutoSaveMediaToGallery(bool v) {
    autoSaveMediaToGallery = v;
    notifyListeners();
    unawaited(_persistGalleryPreference(v));
  }

  Future<void> _loadGalleryPreference() async {
    try {
      final dir = await DeviceIdentity.supportDir();
      final file = File(
        '${dir.path}${Platform.pathSeparator}gallery-autosave.txt',
      );
      if (await file.exists()) {
        autoSaveMediaToGallery = (await file.readAsString()).trim() == 'on';
      }
    } catch (_) {}
  }

  Future<void> _persistGalleryPreference(bool enabled) async {
    try {
      final dir = await DeviceIdentity.supportDir();
      final file = File(
        '${dir.path}${Platform.pathSeparator}gallery-autosave.txt',
      );
      await file.writeAsString(enabled ? 'on' : 'off');
    } catch (_) {}
  }

  void setKeepLinkAlive(bool v) {
    keepLinkAlive = v;
    notifyListeners();
    unawaited(_applyKeepLinkAlive(v));
  }

  Future<void> _applyKeepLinkAlive(bool on) async {
    if (on) {
      await ForegroundService.start();
      await ForegroundService.ensureNotificationPermission();
    } else {
      await ForegroundService.stop();
    }
    await _persistKeepLinkAlive(on);
  }

  /// Stores the toggle in the app-support dir so a fresh launch restores the
  /// user's choice before the service decision is made. Best effort only.
  Future<void> _loadKeepLinkAlive() async {
    try {
      final dir = await DeviceIdentity.supportDir();
      final file = File('${dir.path}${Platform.pathSeparator}keepalive.txt');
      if (await file.exists()) {
        keepLinkAlive = (await file.readAsString()).trim() != 'off';
      }
    } catch (_) {
      // Ignore — keep-link-alive defaults to ON.
    }
  }

  Future<void> _persistKeepLinkAlive(bool on) async {
    try {
      final dir = await DeviceIdentity.supportDir();
      final file = File('${dir.path}${Platform.pathSeparator}keepalive.txt');
      await file.writeAsString(on ? 'on' : 'off');
    } catch (_) {
      // Ignore — the toggle still applies for this session.
    }
  }

  // ==================================================================
  // Actions from the UI
  // ==================================================================

  Future<void> sendLink(String peerId, String url) async {
    if (peerId == 'mock-pixel-8') {
      await mock?.sendToPeer(peerId, BoonMessage.tSendLink, {'url': url});
    } else {
      await link?.sendToPeer(peerId, BoonMessage.tSendLink, {'url': url});
    }
    addActivity(ActivityKind.info, 'Link sent', url);
    notifyListeners();
  }

  Future<void> sendText(String peerId, String text) async {
    if (peerId == 'mock-pixel-8') {
      await mock?.sendToPeer(peerId, BoonMessage.tSendText, {'text': text});
    } else {
      await link?.sendToPeer(peerId, BoonMessage.tSendText, {'text': text});
    }
    addActivity(
      ActivityKind.clipboard,
      'Text sent',
      '${text.length} chars • ${_nameOf(peerId)}',
    );
    notifyListeners();
  }

  String _nameOf(String peerId) =>
      statusByDevice[peerId]?.device.name ?? 'device';

  Future<void> sendMediaAction(String action) async {
    final device = primaryDevice;
    if (device == null) return;
    if (device.id == 'mock-pixel-8') {
      await mock?.sendToPeer(device.id, BoonMessage.tMediaAction, {
        'action': action,
      });
      media = MediaState(
        available: true,
        playing: action == 'play'
            ? true
            : action == 'pause'
            ? false
            : media.playing,
        title: media.title,
        artist: media.artist,
        positionMs: media.positionMs,
        durationMs: media.durationMs,
      );
    } else {
      await link?.sendToPeer(device.id, BoonMessage.tMediaAction, {
        'action': action,
      });
    }
    notifyListeners();
  }

  Future<void> requestScreenShare(String peerId) async {
    _screenFrameTimeout?.cancel();
    screenFrame = null;
    screenError = null;
    screenStage = 'Waiting for the phone…';
    _sentFirstScreenFrame = false;
    _loggedScreenFrameReceived = false;
    screenFramePeerId = peerId;
    screenFrameWidth = 0;
    screenFrameHeight = 0;
    await link?.sendToPeer(peerId, BoonMessage.tCompanionAction, {
      'action': 'start_screen_share',
    });
    _screenFrameTimeout = Timer(const Duration(seconds: 15), () {
      if (screenFrame == null &&
          screenFramePeerId == peerId &&
          screenError == null) {
        screenError = 'No screen frames received. Keep Boon open on the phone and try again.';
        screenStage = null;
        notifyListeners();
      }
    });
    notifyListeners();
  }

  Future<void> stopScreenShare(String peerId) async {
    _screenFrameTimeout?.cancel();
    await link?.sendToPeer(peerId, BoonMessage.tCompanionAction, {
      'action': 'stop_screen_share',
    });
    screenFrame = null;
    screenError = null;
    screenStage = null;
    _sentFirstScreenFrame = false;
    screenFramePeerId = null;
    screenFrameWidth = 0;
    screenFrameHeight = 0;
    notifyListeners();
  }

  Future<void> sendScreenTap(String peerId, double x, double y) async {
    if (statusByDevice[peerId]?.screenControl != true) return;
    await link?.sendToPeer(peerId, BoonMessage.tCompanionAction, {
      'action': 'screen_tap',
      'x': x.clamp(0.0, 1.0),
      'y': y.clamp(0.0, 1.0),
    });
  }

  Future<void> pairAt(String address, int? port) async {
    await link?.pairWith(address, port);
  }

  Future<void> confirmIncomingPairing(String peerId) async {
    await link?.acceptIncomingPairing(peerId);
  }

  void rejectIncomingPairing(String peerId) {
    link?.rejectIncomingPairing(peerId);
    incomingPairings.remove(peerId);
    notifyListeners();
  }

  Future<void> confirmOutgoingPairing(String peerId) async {
    await link?.confirmOutgoingPairing(peerId);
    outgoingCodes.remove(peerId);
    notifyListeners();
  }

  void forgetDevice(String peerId) {
    link?.forgetDevice(peerId);
    statusByDevice.remove(peerId);
    notifyListeners();
  }

  // ---- Transfers ----------------------------------------------------

  Future<void> _onIncomingTransferCompleted(TransferRecord record) async {
    if (autoSaveMediaToGallery && _isGalleryMedia(record.fileName)) {
      await saveTransferToGallery(record.id, automatic: true);
    }
  }

  Future<bool> saveTransferToGallery(
    String transferId, {
    bool automatic = false,
  }) async {
    final record = transfer?.find(transferId);
    if (record == null ||
        record.status != TransferStatus.completed ||
        !AndroidFiles.available ||
        !_isGalleryMedia(record.fileName)) {
      if (!automatic) {
        addActivity(
          ActivityKind.info,
          'Gallery save unavailable',
          'Only completed photos and videos can be saved to Gallery.',
        );
        notifyListeners();
      }
      return false;
    }
    final localPath = record.path ?? record.file?.path;
    if (localPath == null) return false;

    final saved = await AndroidFiles.saveToGallery(
      path: localPath,
      name: record.fileName,
      mimeType: _galleryMimeType(record.fileName),
    );
    if (saved) {
      transfer?.markGallerySaved(transferId);
      addActivity(
        ActivityKind.fileReceived,
        'Saved to Gallery',
        record.fileName,
      );
    } else if (!automatic) {
      addActivity(ActivityKind.info, 'Gallery save failed', record.fileName);
    }
    notifyListeners();
    return saved;
  }

  Future<bool> openTransfer(String transferId) async {
    final record = transfer?.find(transferId);
    final localPath = record?.path ?? record?.file?.path;
    if (record == null || localPath == null) return false;
    if (AndroidFiles.available) {
      return AndroidFiles.openFile(
        path: localPath,
        mimeType: _mimeTypeForName(record.fileName),
      );
    }
    try {
      if (Platform.isWindows) {
        await Process.start('explorer.exe', [localPath]);
      } else if (Platform.isMacOS) {
        await Process.start('open', [localPath]);
      } else if (Platform.isLinux) {
        await Process.start('xdg-open', [localPath]);
      } else {
        return false;
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> offerFile(String path) async {
    final peerId = selectedDeviceId ?? primaryDevice?.id;
    if (peerId == null) {
      addActivity(
        ActivityKind.info,
        'No destination',
        'Connect a device first.',
      );
      notifyListeners();
      return;
    }
    if (peerId == 'mock-pixel-8') {
      addActivity(
        ActivityKind.info,
        'Demo transfer unavailable',
        'Disable Demo Mode and connect a real device to send files.',
      );
      notifyListeners();
      return;
    }
    unawaited(transfer?.offer(peerId, path));
  }

  void cancelTransfer(String id) => unawaited(transfer?.cancel(id));

  /// Public UI refresh for companion services (avoids protected warnings).
  void requestUiUpdate() => notifyListeners();

  void addActivity(ActivityKind kind, String title, String subtitle) {
    activities.insert(
      0,
      ActivityEvent(
        id: '${DateTime.now().microsecondsSinceEpoch}',
        kind: kind,
        title: title,
        subtitle: subtitle,
        time: DateTime.now(),
      ),
    );
    if (activities.length > 30) activities.removeLast();
  }
}

bool _isGalleryMedia(String name) {
  final lower = name.toLowerCase();
  return lower.endsWith('.jpg') ||
      lower.endsWith('.jpeg') ||
      lower.endsWith('.png') ||
      lower.endsWith('.webp') ||
      lower.endsWith('.heic') ||
      lower.endsWith('.gif') ||
      lower.endsWith('.mp4') ||
      lower.endsWith('.mov') ||
      lower.endsWith('.mkv') ||
      lower.endsWith('.webm');
}

String _galleryMimeType(String name) {
  final lower = name.toLowerCase();
  if (lower.endsWith('.mp4')) return 'video/mp4';
  if (lower.endsWith('.mov')) return 'video/quicktime';
  if (lower.endsWith('.mkv')) return 'video/x-matroska';
  if (lower.endsWith('.webm')) return 'video/webm';
  if (lower.endsWith('.png')) return 'image/png';
  if (lower.endsWith('.webp')) return 'image/webp';
  if (lower.endsWith('.gif')) return 'image/gif';
  if (lower.endsWith('.heic')) return 'image/heic';
  return 'image/jpeg';
}

String _mimeTypeForName(String name) =>
    _galleryMediaMime(name) ?? 'application/octet-stream';

String? _galleryMediaMime(String name) {
  if (!_isGalleryMedia(name)) return null;
  return _galleryMimeType(name);
}

class DeviceStatusData {
  DeviceStatusData({
    required this.device,
    required this.online,
    this.notificationsReady = false,
    this.screenControl = false,
  });

  final BoonDevice device;
  bool online;

  /// Remote phone granted notification/media access (from its status
  /// broadcast). Always false for desktop peers, which have no listener.
  final bool notificationsReady;

  /// Android Accessibility control service is currently connected.
  final bool screenControl;
}

/// Routes `BoonLink.sendToPeer` calls (used by TransferService) to the
/// matching backend: the real LAN link, or the demo peer in demo mode.
class _TransferSendAdapter implements BoonLink {
  _TransferSendAdapter(this._state);

  final AppState _state;

  BoonLink? _route(String peerId) {
    if (peerId == 'mock-pixel-8') return _state.mock;
    return _state.link;
  }

  @override
  Future<void> sendToPeer(
    String peerId,
    String type,
    Map<String, dynamic> payload,
  ) async {
    final target = _route(peerId);
    if (target == null) {
      _state.addActivity(
        ActivityKind.fileSent,
        'Transfer failed',
        'No reachable link to the destination device.',
      );
      _state.requestUiUpdate();
      return;
    }
    await target.sendToPeer(peerId, type, payload);
  }

  // Unused by the transfer engine; present for interface completeness.
  @override
  Stream<SecureAppMessage> get appData =>
      _state.link?.appData ?? _state.mock!.appData;
  @override
  Stream<void> get sessionsChanged =>
      _state.link?.sessionsChanged ?? _state.mock!.sessionsChanged;
  @override
  bool get hasLinkedPeer => _state.hasOnlinePeer;
  @override
  Future<void> start() async {}
  @override
  Future<void> stop() => Future.value();
  @override
  Future<void> sendClipboardText(String text) =>
      _state.link?.sendClipboardText(text) ?? Future.value();
}
