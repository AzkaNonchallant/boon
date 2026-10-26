/// Device identity & types shared by desktop and (future) mobile builds.
enum DeviceType { desktop, phone, tablet, unknown }

enum DeviceStatus { online, offline, pairing, unknown }

class DeviceCapabilities {
  const DeviceCapabilities({
    this.clipboard = false,
    this.fileTransfer = false,
    this.notifications = false,
    this.mediaControl = false,
  });

  final bool clipboard;
  final bool fileTransfer;
  final bool notifications;
  final bool mediaControl;

  factory DeviceCapabilities.fromList(List<dynamic> list) => DeviceCapabilities(
        clipboard: list.contains('clipboard'),
        fileTransfer: list.contains('file_transfer'),
        notifications: list.contains('notifications'),
        mediaControl: list.contains('media_control'),
      );

  List<String> toList() => [
        if (clipboard) 'clipboard',
        if (fileTransfer) 'file_transfer',
        if (notifications) 'notifications',
        if (mediaControl) 'media_control',
      ];
}

class BoonDevice {
  BoonDevice({
    required this.id,
    required this.name,
    required this.type,
    this.platform = '',
    this.status = DeviceStatus.unknown,
    this.address,
    this.port,
    this.caps = const DeviceCapabilities(),
    this.battery,
    this.charging = false,
    this.lastSeen,
  });

  String id;
  String name;
  DeviceType type;
  final String platform;
  DeviceStatus status;
  final String? address;
  final int? port;
  DeviceCapabilities caps;
  int? battery;
  bool charging;
  DateTime? lastSeen;

  BoonDevice copyWith({
    String? name,
    DeviceStatus? status,
    int? battery,
    bool? charging,
    DateTime? lastSeen,
    String? address,
    int? port,
    DeviceCapabilities? caps,
  }) =>
      BoonDevice(
        id: id,
        name: name ?? this.name,
        type: type,
        platform: platform,
        status: status ?? this.status,
        address: address ?? this.address,
        port: port ?? this.port,
        caps: caps ?? this.caps,
        battery: battery ?? this.battery,
        charging: charging ?? this.charging,
        lastSeen: lastSeen ?? this.lastSeen,
      );

  static DeviceType typeFrom(String s) {
    switch (s) {
      case 'desktop':
        return DeviceType.desktop;
      case 'phone':
        return DeviceType.phone;
      case 'tablet':
        return DeviceType.tablet;
      default:
        return DeviceType.unknown;
    }
  }

  factory BoonDevice.fromJson(Map<String, dynamic> json) => BoonDevice(
        id: json['id'] as String,
        name: (json['name'] ?? 'Unknown') as String,
        type: typeFrom((json['type'] ?? 'unknown') as String),
        platform: (json['platform'] ?? '') as String,
        status: DeviceStatus.unknown,
        address: json['address'] as String?,
        port: json['port'] as int?,
        caps: DeviceCapabilities.fromList(json['caps'] ?? const []),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'type': type.name,
        'platform': platform,
        'caps': caps.toList(),
      };
}
