class MediaState {
  const MediaState({
    this.available = false,
    this.playing = false,
    this.title,
    this.artist,
    this.album,
    this.positionMs,
    this.durationMs,
  });

  final bool available;
  final bool playing;
  final String? title;
  final String? artist;
  final String? album;
  final int? positionMs;
  final int? durationMs;

  double get progress {
    final pos = positionMs ?? 0;
    final dur = durationMs ?? 0;
    if (dur <= 0) return 0;
    return (pos / dur).clamp(0.0, 1.0);
  }

  factory MediaState.fromJson(Map<String, dynamic> json) => MediaState(
        available: json['available'] == true,
        playing: json['playing'] == true,
        title: json['title'] as String?,
        artist: json['artist'] as String?,
        album: json['album'] as String?,
        positionMs: json['positionMs'] as int?,
        durationMs: json['durationMs'] as int?,
      );

  Map<String, dynamic> toJson() => {
        'available': available,
        'playing': playing,
        'title': title,
        'artist': artist,
        'album': album,
        'positionMs': positionMs,
        'durationMs': durationMs,
      };

  static const empty = MediaState();
}
