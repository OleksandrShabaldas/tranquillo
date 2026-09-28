import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/catalog.dart';
import '../playback/audio_handler.dart';
import '../playback/timeline.dart';
import '../services/catalog_repository.dart';
import '../services/downloads.dart';
import '../services/settings.dart';
import 'common.dart';

class SessionScreen extends StatefulWidget {
  const SessionScreen({super.key, required this.session});

  final Session session;

  @override
  State<SessionScreen> createState() => _SessionScreenState();
}

class _SessionScreenState extends State<SessionScreen> {
  late Voice _voice;
  late PauseLength _pauseLength;

  /// Download progress while getting the session ready; null when idle.
  double? _preparing;

  @override
  void initState() {
    super.initState();
    final settings = context.read<Settings>();
    _voice = settings.voiceFor(widget.session);
    _pauseLength = settings.pauseLength;
  }

  Future<void> _begin() async {
    final handler = context.read<MeditationHandler>();
    final downloads = context.read<Downloads>();
    final group = context.read<CatalogRepository>().catalog?.groupById(widget.session.groupId);
    if (group == null) return;
    setState(() => _preparing = 0);
    try {
      final audio = await downloads.audioFor(_voice, onProgress: (x) {
        if (mounted) setState(() => _preparing = x);
      });
      await handler.load(session: widget.session, group: group, voice: _voice, pauseLength: _pauseLength, audio: audio);
      handler.play();
      if (mounted) openPlayer(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Couldn't start the session. Check your internet connection and try again.")),
        );
      }
    } finally {
      if (mounted) setState(() => _preparing = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final settings = context.read<Settings>();
    final group = context.watch<CatalogRepository>().catalog?.groupById(session.groupId);
    final downloads = context.watch<Downloads>();
    final color = groupColor(group);
    final fg = onColor(color);
    final text = Theme.of(context).textTheme;
    final length = _voice.lengthWith(_pauseLength.scale);

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: 220,
            backgroundColor: color,
            foregroundColor: fg,
            flexibleSpace: FlexibleSpaceBar(
              titlePadding: const EdgeInsetsDirectional.only(start: 56, end: 16, bottom: 16),
              title: Text(session.name, style: TextStyle(color: fg, fontWeight: FontWeight.w600)),
              background: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color.lerp(color, Colors.white, 0.12)!, Color.lerp(color, Colors.black, 0.2)!],
                  ),
                ),
                child: Align(
                  alignment: const Alignment(0.75, -0.1),
                  child: Icon(Icons.spa_outlined, size: 96, color: fg.withValues(alpha: 0.18)),
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: EdgeInsets.fromLTRB(20, 20, 20, 32 + MediaQuery.paddingOf(context).bottom),
            sliver: SliverList.list(children: [
              if (group != null) Text(group.name.toUpperCase(), style: text.labelMedium?.copyWith(letterSpacing: 1.2, color: color)),
              if (session.description.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(session.description, style: text.bodyLarge),
              ],
              if (session.tags.isNotEmpty) ...[const SizedBox(height: 14), TagChips(session.tags, color: color)],
              if (session.voices.length > 1) ...[
                const SizedBox(height: 28),
                Text('Voice', style: text.titleMedium),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final v in session.voices)
                      ChoiceChip(
                        label: Text(v.name),
                        showCheckmark: false,
                        avatar: downloads.isDownloaded(v) ? const Icon(Icons.download_done, size: 18) : null,
                        selected: v == _voice,
                        onSelected: (_) {
                          setState(() => _voice = v);
                          settings.preferredVoice = v.name;
                        },
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 28),
              Text('Pauses', style: text.titleMedium),
              const SizedBox(height: 4),
              Text('How long you rest in silence between the spoken parts.', style: text.bodySmall),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final p in PauseLength.values)
                    ChoiceChip(
                      label: Text('${p.label} · ${formatMinutes(_voice.lengthWith(p.scale))}'),
                      selected: p == _pauseLength,
                      onSelected: (_) {
                        setState(() => _pauseLength = p);
                        settings.pauseLength = p;
                      },
                    ),
                ],
              ),
              const SizedBox(height: 32),
              SizedBox(
                height: 56,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: color, foregroundColor: fg),
                  onPressed: _preparing == null ? _begin : null,
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: Text(_preparing == null ? 'Begin · ${formatMinutes(length)}' : 'Getting ready…'),
                ),
              ),
              if (_preparing != null) ...[
                const SizedBox(height: 10),
                LinearProgressIndicator(value: _preparing == 0 ? null : _preparing, color: color),
              ],
              const SizedBox(height: 12),
              _DownloadButton(voice: _voice),
            ]),
          ),
        ],
      ),
      bottomNavigationBar: const MiniPlayer(),
    );
  }
}

class _DownloadButton extends StatelessWidget {
  const _DownloadButton({required this.voice});

  final Voice voice;

  @override
  Widget build(BuildContext context) {
    final downloads = context.watch<Downloads>();
    if (downloads.isDownloading(voice)) {
      final progress = downloads.progressOf(voice);
      return OutlinedButton.icon(
        onPressed: null,
        icon: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2, value: progress == 0 ? null : progress),
        ),
        label: const Text('Downloading…'),
      );
    }
    if (downloads.isDownloaded(voice)) {
      return OutlinedButton.icon(
        onPressed: () => downloads.remove(voice),
        icon: const Icon(Icons.download_done),
        label: const Text('Downloaded · tap to remove'),
      );
    }
    return OutlinedButton.icon(
      onPressed: () async {
        try {
          await downloads.download(voice);
        } catch (_) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("Download failed. Check your internet connection.")),
            );
          }
        }
      },
      icon: const Icon(Icons.download_outlined),
      label: Text('Download for offline · ${formatMegabytes(voice.size)}'),
    );
  }
}
