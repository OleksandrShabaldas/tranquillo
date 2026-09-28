import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../playback/audio_handler.dart';
import 'common.dart';

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key});

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> with SingleTickerProviderStateMixin {
  late final MeditationHandler _handler = context.read<MeditationHandler>();
  late final AnimationController _breath =
      AnimationController(vsync: this, duration: const Duration(seconds: 5))..repeat(reverse: true);
  Timer? _ticker;
  Duration _position = Duration.zero;

  /// Slider value (0..1) while the listener is dragging it.
  double? _dragValue;

  @override
  void initState() {
    super.initState();
    _position = _handler.position;
    _ticker = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (mounted && _dragValue == null) setState(() => _position = _handler.position);
    });
    _handler.nowPlaying.addListener(_onSessionChanged);
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _breath.dispose();
    _handler.nowPlaying.removeListener(_onSessionChanged);
    super.dispose();
  }

  void _onSessionChanged() {
    if (_handler.nowPlaying.value == null && mounted) Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final np = _handler.nowPlaying.value;
    if (np == null) return const Scaffold();
    final timeline = np.timeline;
    final color = groupColor(np.group);
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final shown = _dragValue != null ? timeline.total * _dragValue! : _position;
    final segment = timeline.segmentAt(shown);
    final inPause = segment?.isPause ?? false;
    final totalMs = timeline.total.inMilliseconds;

    return Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color.lerp(scheme.surface, color, 0.35)!, scheme.surface],
          ),
        ),
        child: SafeArea(
          child: ValueListenableBuilder<bool>(
            valueListenable: _handler.completed,
            builder: (context, done, _) => Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
                  child: Row(
                    children: [
                      IconButton(
                        tooltip: 'Minimize',
                        icon: const Icon(Icons.keyboard_arrow_down),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                      Expanded(
                        child: Text(np.group.name.toUpperCase(),
                            textAlign: TextAlign.center, style: text.labelMedium?.copyWith(letterSpacing: 1.2)),
                      ),
                      TextButton(onPressed: _handler.stop, child: const Text('End')),
                    ],
                  ),
                ),
                Expanded(
                  child: Center(
                    child: done
                        ? _Completed(onDone: _handler.stop)
                        : _BreathingCircle(
                            animation: _breath,
                            color: color,
                            breathing: inPause,
                            label: inPause ? 'Pause' : 'Listen',
                            detail: inPause
                                ? formatClock(segment!.end - shown)
                                : 'Part ${(segment?.part ?? 0) + 1} of ${timeline.spokenParts}',
                          ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    children: [
                      Text(np.session.name, textAlign: TextAlign.center, style: text.headlineSmall),
                      const SizedBox(height: 4),
                      Text('${np.voice.name} · ${np.pauseLength.label.toLowerCase()} pauses',
                          style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Slider(
                    value: totalMs == 0 ? 0 : (shown.inMilliseconds / totalMs).clamp(0.0, 1.0),
                    activeColor: color,
                    onChangeStart: (v) => setState(() => _dragValue = v),
                    onChanged: (v) => setState(() => _dragValue = v),
                    onChangeEnd: (v) async {
                      await _handler.seek(timeline.total * v);
                      if (mounted) {
                        setState(() {
                          _dragValue = null;
                          _position = timeline.total * v;
                        });
                      }
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 36),
                  child: Row(
                    children: [
                      Text(formatClock(shown), style: text.bodySmall),
                      const Spacer(),
                      Text('-${formatClock(timeline.total - shown)}', style: text.bodySmall),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      iconSize: 32,
                      tooltip: 'Back 10 seconds',
                      icon: const Icon(Icons.replay_10),
                      onPressed: () {
                        final back = _position - const Duration(seconds: 10);
                        _handler.seek(back < Duration.zero ? Duration.zero : back);
                      },
                    ),
                    const SizedBox(width: 24),
                    StreamBuilder<bool>(
                      stream: _handler.playingStream,
                      initialData: _handler.isPlaying,
                      builder: (context, snap) {
                        final playing = snap.data ?? false;
                        return IconButton.filled(
                          iconSize: 44,
                          tooltip: done ? 'Play again' : (playing ? 'Pause' : 'Play'),
                          style: IconButton.styleFrom(
                            backgroundColor: color,
                            foregroundColor: onColor(color),
                            minimumSize: const Size(84, 84),
                          ),
                          icon: Icon(done ? Icons.replay : (playing ? Icons.pause : Icons.play_arrow)),
                          onPressed: () => playing ? _handler.pause() : _handler.play(),
                        );
                      },
                    ),
                    const SizedBox(width: 24),
                    IconButton(
                      iconSize: 32,
                      tooltip: 'Skip this pause',
                      icon: const Icon(Icons.skip_next),
                      onPressed: inPause && !done ? _handler.skipPause : null,
                    ),
                  ],
                ),
                const SizedBox(height: 36),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A softly glowing circle that breathes slowly during pauses.
class _BreathingCircle extends StatelessWidget {
  const _BreathingCircle({
    required this.animation,
    required this.color,
    required this.breathing,
    required this.label,
    required this.detail,
  });

  final Animation<double> animation;
  final Color color;
  final bool breathing;
  final String label;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = [240.0, constraints.maxWidth * 0.7, constraints.maxHeight * 0.85].reduce((a, b) => a < b ? a : b);
        return TweenAnimationBuilder<double>(
          tween: Tween(end: breathing ? 1 : 0.15),
          duration: const Duration(milliseconds: 1200),
          builder: (context, depth, child) => AnimatedBuilder(
            animation: animation,
            builder: (context, child) {
              final t = Curves.easeInOut.transform(animation.value);
              return Transform.scale(scale: 1 - 0.16 * depth * (1 - t), child: child);
            },
            child: child,
          ),
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(colors: [color.withValues(alpha: 0.55), color.withValues(alpha: 0.12)]),
              boxShadow: [BoxShadow(color: color.withValues(alpha: 0.3), blurRadius: 60, spreadRadius: 4)],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(label, style: text.titleLarge),
                const SizedBox(height: 4),
                Text(detail, style: text.bodyLarge?.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Completed extends StatelessWidget {
  const _Completed({required this.onDone});

  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.spa_outlined, size: 56, color: Theme.of(context).colorScheme.primary),
        const SizedBox(height: 16),
        Text('Session complete', style: text.headlineSmall),
        const SizedBox(height: 6),
        Text('Take a moment before you move on.', style: text.bodyMedium),
        const SizedBox(height: 20),
        FilledButton.tonal(onPressed: onDone, child: const Text('Done')),
      ],
    );
  }
}
