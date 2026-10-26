/// A notification mirrored from a connected phone.
/// Content is only carried when privacy mode allows it.
class PhoneNotification {
  PhoneNotification({
    required this.id,
    required this.appId,
    required this.appName,
    required this.title,
    this.body,
    required this.time,
  });

  final String id;
  final String appId;
  final String appName;
  final String title;
  final String? body;
  final DateTime time;
}
