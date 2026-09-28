import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/catalog.dart';
import '../playback/audio_handler.dart';
import '../services/downloads.dart';
import '../services/settings.dart';
import 'player_screen.dart';
import 'session_screen.dart';

const _seed = Color(0xFF3F8A7C);

ThemeData buildTheme(Brightness brightness) {
  final scheme = ColorScheme.fromSeed(seedColor: _seed, brightness: brightness);
  return ThemeData(
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    appBarTheme: AppBarTheme(backgroundColor: scheme.surface, scrolledUnderElevation: 0),
    cardTheme: CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
    ),
    chipTheme: ChipThemeData(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
  );
}

const _fallbackColors = [
  Color(0xFF5E9C8F),
  Color(0xFF5B6C9E),
  Color(0xFF9C7A5E),
  Color(0xFF7E6B9E),
  Color(0xFF5E8A9C),
  Color(0xFF8F9C5E),
];

/// The group's own color, or a calm color picked from its name.
Color groupColor(Group? group) {
  if (group == null) return _seed;
  return group.color ?? _fallbackColors[group.id.codeUnits.fold(0, (a, b) => a + b) % _fallbackColors.length];
}

/// Readable text color on top of [background].
Color onColor(Color background) =>
    ThemeData.estimateBrightnessForColor(background) == Brightness.dark ? Colors.white : const Color(0xFF14201D);

String formatMinutes(Duration d) {
  final minutes = (d.inSeconds / 60).round();
  return minutes < 1 ? '< 1 min' : '$minutes min';
}

String formatClock(Duration d) {
  final s = d.inSeconds;
  return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
}

String formatMegabytes(int bytes) {
  final mb = bytes / (1024 * 1024);
  return mb < 10 ? '${mb.toStringAsFixed(1)} MB' : '${mb.round()} MB';
}

void openSession(BuildContext context, Session session) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => SessionScreen(session: session)));

void openPlayer(BuildContext context) =>
    Navigator.of(context).push(MaterialPageRoute(fullscreenDialog: true, builder: (_) => const PlayerScreen()));

class TagChips extends StatelessWidget {
  const TagChips(this.tags, {super.key, this.color});

  final List<String> tags;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    if (tags.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final tag in tags)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: (color ?? scheme.primary).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(tag, style: Theme.of(context).textTheme.labelMedium),
          ),
      ],
    );
  }
}

class SessionTile extends StatelessWidget {
  const SessionTile({super.key, required this.session, required this.group, this.showGroup = false});

  final Session session;
  final Group? group;
  final bool showGroup;

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<Settings>();
    final downloads = context.watch<Downloads>();
    final voice = settings.voiceFor(session);
    final color = groupColor(group);
    final details = [
      if (showGroup && group != null) group!.name,
      formatMinutes(voice.lengthWith(settings.pauseLength.scale)),
      if (session.voices.length > 1) '${session.voices.length} voices',
    ].join(' · ');
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      leading: CircleAvatar(
        backgroundColor: color.withValues(alpha: 0.18),
        child: Icon(Icons.self_improvement, color: color),
      ),
      title: Text(session.name),
      subtitle: Text(details),
      trailing: downloads.isDownloaded(voice)
          ? Icon(Icons.download_done, color: Theme.of(context).colorScheme.primary, semanticLabel: 'Downloaded')
          : const Icon(Icons.chevron_right),
      onTap: () => openSession(context, session),
    );
  }
}

/// Small bar at the bottom of the screens while a session is loaded.
class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    final handler = context.read<MeditationHandler>();
    return ValueListenableBuilder<NowPlaying?>(
      valueListenable: handler.nowPlaying,
      builder: (context, np, _) {
        if (np == null) return const SizedBox.shrink();
        final scheme = Theme.of(context).colorScheme;
        return Material(
          color: scheme.surfaceContainerHigh,
          child: SafeArea(
            top: false,
            child: InkWell(
              onTap: () => openPlayer(context),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 8, 8),
                child: Row(
                  children: [
                    Icon(Icons.self_improvement, color: groupColor(np.group)),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(np.session.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleSmall),
                          Text('${np.voice.name} · ${np.pauseLength.label.toLowerCase()} pauses',
                              style: Theme.of(context).textTheme.bodySmall),
                        ],
                      ),
                    ),
                    StreamBuilder<bool>(
                      stream: handler.playingStream,
                      initialData: handler.isPlaying,
                      builder: (context, snap) => IconButton(
                        tooltip: snap.data == true ? 'Pause' : 'Play',
                        icon: Icon(snap.data == true ? Icons.pause : Icons.play_arrow),
                        onPressed: () => snap.data == true ? handler.pause() : handler.play(),
                      ),
                    ),
                    IconButton(tooltip: 'End session', icon: const Icon(Icons.close), onPressed: handler.stop),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
