import 'package:flutter_test/flutter_test.dart';
import 'package:tranquillo/models/catalog.dart';
import 'package:tranquillo/playback/timeline.dart';

void main() {
  const parts = [
    Part(start: 0, end: 5, pause: 10),
    Part(start: 8, end: 14, pause: 150),
    Part(start: 17, end: 20),
  ];

  Duration s(num seconds) => Duration(milliseconds: (seconds * 1000).round());

  test('lays out speech and pauses in order', () {
    final t = Timeline.build(parts, 1);
    expect(t.segments.map((x) => x.isPause), [false, true, false, true, false]);
    expect(t.segments.map((x) => x.length), [s(5), s(10), s(6), s(150), s(3)]);
    expect(t.total, s(5 + 10 + 6 + 150 + 3));
    expect(t.spokenParts, 3);
  });

  test('scales pauses but never the speech', () {
    final t = Timeline.build(parts, 0.5);
    expect(t.total, s(5 + 5 + 6 + 75 + 3));
    expect(Timeline.build(parts, 3).total, s(5 + 30 + 6 + 450 + 3));
  });

  test('splits long pauses into even chunks no longer than the silent file', () {
    final t = Timeline.build(parts, 1, maxSilence: s(60));
    final chunks = t.items.where((i) => i.isPause && i.segment == 3).map((i) => i.length).toList();
    expect(chunks, [s(50), s(50), s(50)]);
    expect(t.items.where((i) => i.isPause && i.segment == 1).single.length, s(10));
  });

  test('speech items point at the right place in the recording', () {
    final t = Timeline.build(parts, 1);
    final speech = t.items.where((i) => !i.isPause).toList();
    expect(speech.map((i) => i.fileStart), [s(0), s(8), s(17)]);
    expect(speech.map((i) => i.offset), [s(0), s(15), s(171)]);
  });

  test('maps positions between the session and the player items', () {
    final t = Timeline.build(parts, 1, maxSilence: s(60));
    for (final position in [s(0), s(4.2), s(5), s(12), s(15), s(20.5), s(100), s(170.9), s(172)]) {
      final loc = t.locate(position);
      expect(t.positionOf(loc.index, loc.offset), position, reason: '$position');
    }
    expect(t.locate(s(-3)).index, 0);
    expect(t.locate(t.total + s(10)).index, t.items.length - 1);
  });

  test('knows whether a position is in a pause and finds the next spoken part', () {
    final t = Timeline.build(parts, 1);
    expect(t.segmentAt(s(3))!.isPause, isFalse);
    expect(t.segmentAt(s(7))!.isPause, isTrue);
    expect(t.segmentAt(s(7))!.part, 0);
    final next = t.nextSpeechItem(s(7))!;
    expect(t.items[next].fileStart, s(8));
    expect(t.nextSpeechItem(s(172)), isNull);
  });

  test('a trailing pause adds silence at the end', () {
    final t = Timeline.build(const [Part(start: 0, end: 4, pause: 20)], 1);
    expect(t.segments.last.isPause, isTrue);
    expect(t.total, s(24));
  });

  test('pause length options', () {
    expect(PauseLength.byName('long'), PauseLength.long);
    expect(PauseLength.byName('nonsense'), PauseLength.normal);
    expect(PauseLength.byName(null), PauseLength.normal);
  });
}
