import 'dart:math' as math;

import '../models/catalog.dart';

/// How long pauses are, relative to the lengths written in the script.
enum PauseLength {
  short('Short', 0.5),
  normal('Normal', 1),
  long('Long', 2),
  extraLong('Extra long', 3);

  const PauseLength(this.label, this.scale);

  final String label;
  final double scale;

  static PauseLength byName(String? name) =>
      values.firstWhere((p) => p.name == name, orElse: () => PauseLength.normal);
}

/// A continuous stretch of the session: either a spoken part or a pause.
class Segment {
  const Segment({required this.isPause, required this.part, required this.offset, required this.length});

  final bool isPause;

  /// Index of the spoken part (for a pause: the part it follows).
  final int part;

  /// Where the segment starts within the whole session.
  final Duration offset;
  final Duration length;

  Duration get end => offset + length;
}

/// One entry of the player's playlist. Long pauses are split into several
/// items because each one is a clip of a fixed-length silent file.
class PlayerItem {
  const PlayerItem({
    required this.segment,
    required this.isPause,
    required this.fileStart,
    required this.length,
    required this.offset,
  });

  final int segment;
  final bool isPause;

  /// For spoken parts: where the clip starts in the audio file.
  final Duration fileStart;
  final Duration length;

  /// Where the item starts within the whole session.
  final Duration offset;
}

/// The whole session laid out in time: spoken parts from the recording with
/// silence of the chosen length between them.
class Timeline {
  Timeline._(this.segments, this.items, this.total);

  final List<Segment> segments;
  final List<PlayerItem> items;
  final Duration total;

  factory Timeline.build(List<Part> parts, double pauseScale, {Duration maxSilence = const Duration(seconds: 60)}) {
    final segments = <Segment>[];
    final items = <PlayerItem>[];
    var offset = Duration.zero;

    for (var i = 0; i < parts.length; i++) {
      final part = parts[i];
      final speech = _ms(part.end - part.start);
      if (speech > Duration.zero) {
        items.add(PlayerItem(
          segment: segments.length,
          isPause: false,
          fileStart: _ms(part.start),
          length: speech,
          offset: offset,
        ));
        segments.add(Segment(isPause: false, part: i, offset: offset, length: speech));
        offset += speech;
      }

      final pause = _ms(part.pause * pauseScale);
      if (pause > Duration.zero) {
        // Split evenly so there is never a tiny leftover clip.
        final chunks = math.max(1, (pause.inMilliseconds / maxSilence.inMilliseconds).ceil());
        var itemOffset = offset;
        for (var c = 0; c < chunks; c++) {
          final start = pause * c ~/ chunks;
          final end = pause * (c + 1) ~/ chunks;
          items.add(PlayerItem(
            segment: segments.length,
            isPause: true,
            fileStart: Duration.zero,
            length: end - start,
            offset: itemOffset,
          ));
          itemOffset += end - start;
        }
        segments.add(Segment(isPause: true, part: i, offset: offset, length: pause));
        offset += pause;
      }
    }
    return Timeline._(segments, items, offset);
  }

  /// Position within the session, given the player's item index and its
  /// position inside that item.
  Duration positionOf(int? itemIndex, Duration inItem) {
    if (items.isEmpty || itemIndex == null) return Duration.zero;
    final item = items[itemIndex.clamp(0, items.length - 1)];
    final within = inItem < Duration.zero ? Duration.zero : (inItem > item.length ? item.length : inItem);
    return item.offset + within;
  }

  /// The player item and offset inside it for a session [position].
  ({int index, Duration offset}) locate(Duration position) {
    if (items.isEmpty) return (index: 0, offset: Duration.zero);
    if (position <= Duration.zero) return (index: 0, offset: Duration.zero);
    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      if (position < item.offset + item.length) return (index: i, offset: position - item.offset);
    }
    return (index: items.length - 1, offset: items.last.length);
  }

  Segment? segmentAt(Duration position) {
    for (final s in segments) {
      if (position < s.end) return s;
    }
    return segments.isEmpty ? null : segments.last;
  }

  /// Index of the first item of the next spoken part after [position], if any.
  int? nextSpeechItem(Duration position) {
    for (var i = 0; i < items.length; i++) {
      if (!items[i].isPause && items[i].offset > position) return i;
    }
    return null;
  }

  int get spokenParts => segments.where((s) => !s.isPause).length;
}

Duration _ms(double seconds) => Duration(milliseconds: (seconds * 1000).round());
