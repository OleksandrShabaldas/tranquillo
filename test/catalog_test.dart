import 'dart:convert';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:tranquillo/models/catalog.dart';

// Same shape as the catalog.json written by tools/build-catalog.mjs.
const _json = '''
{
  "version": 1,
  "generated": "2026-09-28T15:25:16.387Z",
  "groups": [
    {
      "id": "Breathing Basics", "name": "Breathing Basics", "description": "Calm the mind.",
      "tags": ["breathing", "beginner"], "color": "#5E9C8F", "order": 1, "author": "extra fields are ignored",
      "sessions": [
        {
          "id": "Breathing Basics/01 Breathing Space", "name": "Breathing Space", "description": "Short.",
          "tags": ["breathing", "short"],
          "voices": [
            {"id": "david", "name": "David", "file": "Meditations/Breathing Basics/01 Breathing Space/david.mp3",
             "size": 557139, "hash": "49bd74ff06f83505",
             "parts": [{"start": 0.01, "end": 5.79, "pause": 10}, {"start": 9.63, "end": 14.75}]},
            {"id": "zira", "name": "Zira", "file": "Meditations/Breathing Basics/01 Breathing Space/zira.mp3",
             "size": 557557, "hash": "ecc1c3542fd95985",
             "parts": [{"start": 0, "end": 5.85, "pause": 10}, {"start": 9.65, "end": 14.76}]}
          ]
        }
      ]
    },
    {
      "id": "Sleep", "name": "Sleep", "description": "", "tags": ["sleep"],
      "sessions": [
        {"id": "Sleep/01 Letting Go", "name": "Letting Go", "tags": ["breathing"],
         "voices": [{"id": "david", "name": "David", "file": "Meditations/Sleep/01 Letting Go/david.mp3",
                     "size": 1, "hash": "aa", "parts": [{"start": 0, "end": 4, "pause": 60}]}]},
        {"id": "Sleep/02 Empty", "name": "No voices", "voices": []}
      ]
    },
    {"id": "Empty", "name": "Empty", "sessions": []}
  ]
}
''';

void main() {
  final catalog = Catalog.fromJson(jsonDecode(_json) as Map<String, dynamic>);

  test('reads groups, sessions and voices', () {
    expect(catalog.groups.map((g) => g.name), ['Breathing Basics', 'Sleep']);
    final session = catalog.sessionById('Breathing Basics/01 Breathing Space')!;
    expect(session.voices.map((v) => v.name), ['David', 'Zira']);
    expect(session.groupId, 'Breathing Basics');
    expect(catalog.groups.first.color, const Color(0xFF5E9C8F));
    expect(catalog.generated, DateTime.utc(2026, 9, 28, 15, 25, 16, 387));
  });

  test('drops sessions without voices and groups without sessions', () {
    expect(catalog.sessionById('Sleep/02 Empty'), isNull);
    expect(catalog.groupById('Empty'), isNull);
  });

  test('finds voices by key and computes lengths', () {
    final voice = catalog.voiceByKey('Breathing Basics/01 Breathing Space/zira')!;
    expect(voice.speech, const Duration(milliseconds: 5850 + 5110));
    expect(voice.normalPauses, const Duration(seconds: 10));
    expect(voice.lengthWith(2), const Duration(milliseconds: 10960 + 20000));
  });

  test('collects tags and voice names', () {
    expect(catalog.tags.first, 'breathing');
    expect(catalog.tags, containsAll(['beginner', 'short', 'sleep']));
    expect(catalog.voiceNames, ['David', 'Zira']);
    expect(catalog.sessionsTagged('sleep').map((s) => s.name), ['Letting Go']);
    expect(catalog.sessionsTagged('breathing').length, 2);
  });

  test('groups sessions into chapters', () {
    final c = Catalog.fromJson({
      'groups': [
        {
          'id': 'g',
          'chapters': [
            {'id': 'start', 'name': 'First Steps', 'description': 'Begin here.'},
            {'id': 'empty', 'name': 'No sessions'},
            {'name': 'No id'},
          ],
          'sessions': [
            for (final (id, chapter) in [('a', 'start'), ('b', 'start'), ('c', 'later'), ('d', null)])
              {
                'id': 'g/$id',
                'chapter': chapter,
                'voices': [
                  {'id': 'v', 'parts': [{'start': 0, 'end': 1}]},
                ],
              },
          ],
        },
        {
          'id': 'plain',
          'sessions': [
            {'id': 'plain/x', 'voices': [{'id': 'v', 'parts': [{'start': 0, 'end': 1}]}]},
          ],
        },
      ],
    });
    final g = c.groupById('g')!;
    expect(g.chapters.map((ch) => ch.name), ['First Steps']);
    expect(g.chapters.single.description, 'Begin here.');
    expect(g.chapters.single.sessions.map((s) => s.id), ['g/a', 'g/b']);
    expect(g.unchaptered.map((s) => s.id), ['g/c', 'g/d']);
    expect(g.sessions.length, 4);
    final plain = c.groupById('plain')!;
    expect(plain.chapters, isEmpty);
    expect(plain.unchaptered.map((s) => s.id), ['plain/x']);
  });

  test('tolerates missing or malformed fields', () {
    final c = Catalog.fromJson({
      'groups': [
        {
          'id': 'g',
          'color': 'blue',
          'tags': 'not a list',
          'sessions': [
            {
              'id': 'g/s',
              'voices': [
                {'id': 'v', 'parts': [{'start': 1, 'end': 2}]},
              ],
            },
          ],
        },
      ],
    });
    expect(c.groups.single.color, isNull);
    expect(c.groups.single.tags, isEmpty);
    expect(c.sessions.single.voices.single.parts.single.pause, 0);
  });
}
