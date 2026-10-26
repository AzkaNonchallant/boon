enum ActivityKind { fileSent, fileReceived, clipboard, connection, info }

class ActivityEvent {
  ActivityEvent({
    required this.id,
    required this.kind,
    required this.title,
    required this.subtitle,
    required this.time,
  });

  final String id;
  final ActivityKind kind;
  final String title;
  final String subtitle;
  final DateTime time;
}
