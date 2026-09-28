import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import '../models/catalog.dart';
import 'silence.dart';
import 'timeline.dart';

/// What is loaded in the player right now.
class NowPlaying {
  const NowPlaying({
    required this.session,
    required this.group,
    required this.voice,
    required this.pauseLength,
    required this.timeline,
  });

  final Session session;
  final Group group;
  final Voice voice;
  final PauseLength pauseLength;
  final Timeline timeline;
}

/// Plays a session as one continuous track: clips of the recording with clips
/// of a silent file in between. Talks to the lock screen and notification
/// through audio_service, which also keeps playback going in the background.
class MeditationHandler extends BaseAudioHandler with SeekHandler {
  /// [silence] is the file pauses are cut from (see silence.dart).
  MeditationHandler(this.silence) {
    _player.playbackEventStream.listen(_broadcast, onError: _onError);
    _player.playingStream.listen((_) => _broadcast());
    _player.processingStateStream.listen((state) {
      if (state == ProcessingState.completed) _onCompleted();
    });
  }

  final File silence;
  final _player = AudioPlayer();

  /// The loaded session, or null when nothing is loaded.
  final nowPlaying = ValueNotifier<NowPlaying?>(null);

  /// True once the session has played to the end.
  final completed = ValueNotifier<bool>(false);

  /// Last playback error, shown by the player screen.
  final error = ValueNotifier<String?>(null);

  Timeline? get timeline => nowPlaying.value?.timeline;
  bool get isPlaying => _player.playing;
  Stream<bool> get playingStream => _player.playingStream;

  /// Position within the whole session (pauses included).
  Duration get position {
    final t = timeline;
    if (t == null) return Duration.zero;
    if (completed.value) return t.total;
    return t.positionOf(_player.currentIndex, _player.position);
  }

  Future<void> load({
    required Session session,
    required Group group,
    required Voice voice,
    required PauseLength pauseLength,
    required File audio,
  }) async {
    final timeline = Timeline.build(voice.parts, pauseLength.scale, maxSilence: silenceLength);
    completed.value = false;
    error.value = null;
    nowPlaying.value = NowPlaying(
      session: session,
      group: group,
      voice: voice,
      pauseLength: pauseLength,
      timeline: timeline,
    );
    mediaItem.add(MediaItem(
      id: voice.key,
      title: session.name,
      artist: voice.name,
      album: group.name,
      duration: timeline.total,
    ));
    try {
      await _player.setAudioSources([
        for (final item in timeline.items)
          ClippingAudioSource(
            // Every clip needs its own child source instance.
            child: AudioSource.file(item.isPause ? silence.path : audio.path),
            start: item.fileStart,
            end: item.fileStart + item.length,
            duration: item.length,
          ),
      ]);
    } catch (e) {
      nowPlaying.value = null;
      mediaItem.add(null);
      rethrow;
    }
    _broadcast();
  }

  /// Starts or resumes playback. Don't await this: just_audio's play()
  /// only completes when playback pauses or stops.
  @override
  Future<void> play() async {
    if (completed.value) {
      completed.value = false;
      await _player.seek(Duration.zero, index: 0);
    }
    return _player.play();
  }

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> stop() async {
    await _player.stop();
    nowPlaying.value = null;
    completed.value = false;
    mediaItem.add(null);
    await super.stop();
  }

  @override
  Future<void> seek(Duration position) async {
    final t = timeline;
    if (t == null) return;
    completed.value = false;
    final target = t.locate(position);
    await _player.seek(target.offset, index: target.index);
  }

  /// Jumps from the middle of a pause to the next spoken part.
  Future<void> skipPause() async {
    final next = timeline?.nextSpeechItem(position);
    if (next != null) await _player.seek(Duration.zero, index: next);
  }

  /// Swiping the app away from recent apps ends the session.
  @override
  Future<void> onTaskRemoved() => stop();

  Future<void> _onCompleted() async {
    if (completed.value) return;
    completed.value = true;
    await _player.pause();
    _broadcast();
  }

  void _onError(Object e, StackTrace stackTrace) {
    error.value = e is PlayerException ? (e.message ?? 'Playback failed') : '$e';
    playbackState.add(playbackState.value.copyWith(
      processingState: AudioProcessingState.error,
      errorMessage: error.value,
    ));
  }

  void _broadcast([PlaybackEvent? _]) {
    final playing = _player.playing;
    final pos = position;
    playbackState.add(playbackState.value.copyWith(
      controls: [playing ? MediaControl.pause : MediaControl.play, MediaControl.stop],
      systemActions: const {MediaAction.seek, MediaAction.seekForward, MediaAction.seekBackward},
      androidCompactActionIndices: const [0, 1],
      processingState: completed.value
          ? AudioProcessingState.completed
          : const {
              ProcessingState.idle: AudioProcessingState.idle,
              ProcessingState.loading: AudioProcessingState.loading,
              ProcessingState.buffering: AudioProcessingState.buffering,
              ProcessingState.ready: AudioProcessingState.ready,
              ProcessingState.completed: AudioProcessingState.completed,
            }[_player.processingState]!,
      playing: playing,
      updatePosition: pos,
      bufferedPosition: pos,
      speed: _player.speed,
      queueIndex: 0,
    ));
  }
}
