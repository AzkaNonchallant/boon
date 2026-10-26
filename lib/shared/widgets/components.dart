import 'package:flutter/material.dart';

import '../../app/theme.dart';
import 'neu.dart';

/// Blue-gradient circular icon used on feature cards,
/// e.g. clipboard / upload / dumbbell icons in the reference.
class AppIconCircle extends StatelessWidget {
  const AppIconCircle({
    super.key,
    required this.icon,
    this.size = 54,
    this.iconSize = 26,
  });

  final IconData icon;
  final double size;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            BoonColors.accent,
            BoonColors.accentDeep,
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: BoonColors.shadowDark,
            offset: const Offset(4, 5),
            blurRadius: 10,
          ),
        ],
      ),
      child: Center(
        child: Container(
          width: size * 0.74,
          height: size * 0.74,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              colors: [Color(0xFFA5C6E0), BoonColors.accentDeep],
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.18),
                offset: const Offset(0, 2),
                blurRadius: 5,
              ),
            ],
          ),
          child: Icon(icon, size: iconSize, color: Colors.white),
        ),
      ),
    );
  }
}

/// Rounded phone silhouette shown on the device cards.
class PhoneSilhouette extends StatelessWidget {
  const PhoneSilhouette({super.key, this.width = 74, this.height = 132});

  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: const Color(0xFFAFC0D2),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: BoonColors.shadowDark,
            offset: const Offset(5, 6),
            blurRadius: 12,
          ),
          BoxShadow(
            color: Colors.white,
            offset: const Offset(-5, -6),
            blurRadius: 12,
          ),
        ],
      ),
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          width: width * 0.16,
          height: width * 0.16,
          decoration: BoxDecoration(
            color: BoonColors.panelTop,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: BoonColors.shadowDark,
                offset: const Offset(1, 1),
                blurRadius: 3,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ConnectionStatus extends StatelessWidget {
  const ConnectionStatus({
    super.key,
    required this.connected,
    this.label,
    this.compact = false,
  });

  final bool connected;
  final String? label;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: compact ? 8 : 10,
          height: compact ? 8 : 10,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: connected ? BoonColors.online : BoonColors.textFaint,
            boxShadow: connected
                ? [
                    BoxShadow(
                      color: BoonColors.online.withValues(alpha: 0.55),
                      blurRadius: 6,
                      spreadRadius: 1,
                    ),
                  ]
                : null,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label ?? (connected ? 'Connected' : 'Offline'),
          style: TextStyle(
            fontSize: compact ? 10.5 : 12.5,
            fontWeight: FontWeight.w600,
            color: connected ? BoonColors.online : BoonColors.textFaint,
          ),
        ),
      ],
    );
  }
}

/// Media player card shared by the dashboard and Phone Buddy.
class MediaPlayerCard extends StatelessWidget {
  const MediaPlayerCard({
    super.key,
    this.title = 'Panasea',
    this.artist = 'Rumah Sakit',
    this.playing = true,
    this.position = 0.35,
    this.available = true,
    required this.onPlayPause,
    required this.onPrev,
    required this.onNext,
  });

  final String title;
  final String artist;
  final bool playing;
  final double position;
  final bool available;

  final VoidCallback onPlayPause;
  final VoidCallback onPrev;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return NeuCard(
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      child: Opacity(
        opacity: available ? 1 : 0.55,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: BoonColors.panelTop,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: BoonShadows.raised(
                      blur: 8,
                      darkOffset: const Offset(3, 3),
                      lightOffset: const Offset(-3, -3),
                    ),
                  ),
                  child: const Icon(Icons.music_note, size: 22, color: BoonColors.navy),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: BoonTypography.cardTitle.copyWith(fontSize: 16),
                      ),
                      Text(
                        artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: BoonTypography.subtitle,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _ProgressTrack(position: position)),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _MediaKey(icon: Icons.fast_rewind, onTap: available ? onPrev : null),
                Material(
                  color: Colors.transparent,
                  child: Ink(
                    width: 40,
                    height: 40,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: BoonColors.panelBase,
                    ),
                    child: InkWell(
                      onTap: available ? onPlayPause : null,
                      customBorder: const CircleBorder(),
                      child: Center(
                        child: Icon(
                          playing ? Icons.pause : Icons.play_arrow,
                          size: 20,
                          color: BoonColors.navy,
                        ),
                      ),
                    ),
                  ),
                ),
                _MediaKey(icon: Icons.fast_forward, onTap: available ? onNext : null),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ProgressTrack extends StatelessWidget {
  const _ProgressTrack({required this.position});

  final double position;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final w = constraints.maxWidth;
      return Stack(
        alignment: Alignment.centerLeft,
        children: [
          Container(
            height: 4,
            decoration: BoxDecoration(
              color: BoonColors.panelBottom,
              borderRadius: BorderRadius.circular(2),
              boxShadow: [
                BoxShadow(
                  color: Colors.white,
                  offset: const Offset(0, -1),
                  blurRadius: 2,
                ),
              ],
            ),
          ),
          Container(
            width: w * position.clamp(0.0, 1.0),
            height: 4,
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [BoonColors.accentSoft, BoonColors.accent]),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Positioned(
            left: (w * position.clamp(0.05, 0.95)) - 7,
            child: Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                color: BoonColors.panelTop,
                shape: BoxShape.circle,
                boxShadow: BoonShadows.raised(
                  blur: 5,
                  darkOffset: const Offset(2, 2),
                  lightOffset: const Offset(-2, -2),
                ),
              ),
            ),
          ),
        ],
      );
    });
  }
}

class _MediaKey extends StatelessWidget {
  const _MediaKey({required this.icon, this.onTap});

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Ink(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: BoonColors.panelBase,
          shape: BoxShape.circle,
        ),
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: Icon(icon, size: 16, color: BoonColors.iconNeutral),
        ),
      ),
    );
  }
}
