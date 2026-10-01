import 'dart:ui' show Color;

/// One spoken part of a recording, and the pause that follows it.
class Part {
  const Part({required this.start, required this.end, this.pause = 0});

  /// Where the part starts and ends in the audio file, in seconds.
  final double start;
  final double end;

  /// Normal length of the silence after this part, in seconds (0 = none).
  final double pause;

  factory Part.fromJson(Map<String, dynamic> json) => Part(
        start: _toDouble(json['start']),
        end: _toDouble(json['end']),
        pause: _toDouble(json['pause']),
      );
}

/// One recording of a session in a particular voice.
class Voice {
  Voice({
    required this.id,
    required this.name,
    required this.file,
    required this.size,
    required this.hash,
    required this.parts,
    required this.sessionId,
  });

  final String id;
  final String name;

  /// Path of the audio file relative to the content site, e.g.
  /// `Meditations/Sleep/01 Wind Down/anna.mp3`.
  final String file;
  final int size;

  /// Short content hash. Changes whenever the audio file is replaced.
  final String hash;
  final List<Part> parts;
  final String sessionId;

  /// Identifies this voice across catalog updates.
  String get key => '$sessionId/$id';

  late final Duration speech = _seconds(parts.fold<double>(0, (sum, p) => sum + (p.end - p.start)));
  late final Duration normalPauses = _seconds(parts.fold<double>(0, (sum, p) => sum + p.pause));

  /// Total session length when pauses are scaled by [pauseScale].
  Duration lengthWith(double pauseScale) => speech + normalPauses * pauseScale;

  factory Voice.fromJson(Map<String, dynamic> json, String sessionId) => Voice(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        file: json['file'] as String? ?? '',
        size: (json['size'] as num?)?.toInt() ?? 0,
        hash: json['hash'] as String? ?? '',
        parts: _list(json['parts']).map(Part.fromJson).toList(),
        sessionId: sessionId,
      );
}

class Session {
  Session({
    required this.id,
    required this.name,
    required this.description,
    required this.tags,
    required this.voices,
    required this.groupId,
    this.chapterId,
  });

  final String id;
  final String name;
  final String description;
  final List<String> tags;
  final List<Voice> voices;
  final String groupId;

  /// Id of the chapter the session is in, when its group has chapters.
  final String? chapterId;

  factory Session.fromJson(Map<String, dynamic> json, String groupId) {
    final id = json['id'] as String? ?? '';
    return Session(
      id: id,
      name: json['name'] as String? ?? '',
      description: json['description'] as String? ?? '',
      tags: _strings(json['tags']),
      voices: _list(json['voices']).map((v) => Voice.fromJson(v, id)).where((v) => v.parts.isNotEmpty).toList(),
      groupId: groupId,
      chapterId: json['chapter'] as String?,
    );
  }
}

/// A smaller group of sessions inside a group, e.g. "First Steps".
class Chapter {
  Chapter({required this.id, required this.name, required this.description, required this.sessions});

  final String id;
  final String name;
  final String description;
  final List<Session> sessions;
}

class Group {
  Group({
    required this.id,
    required this.name,
    required this.description,
    required this.tags,
    required this.color,
    required this.sessions,
    this.chapters = const [],
  });

  final String id;
  final String name;
  final String description;
  final List<String> tags;
  final Color? color;

  /// All sessions in the order they're shown, chapter after chapter when the group has chapters.
  final List<Session> sessions;

  /// The group's chapters that have sessions, in order. Empty when the group isn't split into chapters.
  final List<Chapter> chapters;

  /// Sessions that aren't in one of [chapters] (all of them when the group has no chapters).
  late final List<Session> unchaptered = [
    for (final s in sessions)
      if (!chapters.any((c) => c.id == s.chapterId)) s,
  ];

  factory Group.fromJson(Map<String, dynamic> json) {
    final id = json['id'] as String? ?? '';
    final sessions = _list(json['sessions']).map((s) => Session.fromJson(s, id)).where((s) => s.voices.isNotEmpty).toList();
    return Group(
      id: id,
      name: json['name'] as String? ?? '',
      description: json['description'] as String? ?? '',
      tags: _strings(json['tags']),
      color: _color(json['color']),
      sessions: sessions,
      chapters: [
        for (final c in _list(json['chapters']))
          if (c['id'] is String)
            Chapter(
              id: c['id'] as String,
              name: c['name'] as String? ?? '',
              description: c['description'] as String? ?? '',
              sessions: sessions.where((s) => s.chapterId == c['id']).toList(),
            ),
      ].where((c) => c.sessions.isNotEmpty).toList(),
    );
  }
}

class Catalog {
  Catalog({required this.groups, this.generated});

  final List<Group> groups;
  final DateTime? generated;

  factory Catalog.fromJson(Map<String, dynamic> json) => Catalog(
        groups: _list(json['groups']).map(Group.fromJson).where((g) => g.sessions.isNotEmpty).toList(),
        generated: DateTime.tryParse(json['generated'] as String? ?? ''),
      );

  late final Map<String, Group> _groupsById = {for (final g in groups) g.id: g};
  late final Map<String, Session> _sessionsById = {
    for (final g in groups)
      for (final s in g.sessions) s.id: s,
  };
  late final Map<String, Voice> _voicesByKey = {
    for (final s in _sessionsById.values)
      for (final v in s.voices) v.key: v,
  };

  Group? groupById(String id) => _groupsById[id];
  Session? sessionById(String id) => _sessionsById[id];
  Voice? voiceByKey(String key) => _voicesByKey[key];
  Iterable<Session> get sessions => _sessionsById.values;
  Iterable<Voice> get voices => _voicesByKey.values;

  /// Every tag used by a group or session, most common first.
  late final List<String> tags = () {
    final counts = <String, int>{};
    for (final g in groups) {
      for (final t in {...g.tags, for (final s in g.sessions) ...s.tags}) {
        counts[t] = (counts[t] ?? 0) + 1;
      }
    }
    return counts.keys.toList()..sort((a, b) => counts[b]!.compareTo(counts[a]!));
  }();

  /// Distinct voice names, in the order they first appear.
  late final List<String> voiceNames = {for (final v in voices) v.name}.toList();

  /// Sessions tagged with [tag], directly or through their group.
  List<Session> sessionsTagged(String tag) => [
        for (final g in groups)
          for (final s in g.sessions)
            if (s.tags.contains(tag) || g.tags.contains(tag)) s,
      ];
}

Duration _seconds(double s) => Duration(milliseconds: (s * 1000).round());

double _toDouble(Object? v) => v is num ? v.toDouble() : 0;

List<Map<String, dynamic>> _list(Object? v) => v is List ? v.whereType<Map<String, dynamic>>().toList() : const [];

List<String> _strings(Object? v) => v is List ? v.whereType<String>().toList() : const [];

Color? _color(Object? v) {
  if (v is! String) return null;
  final hex = v.replaceFirst('#', '');
  final value = int.tryParse(hex, radix: 16);
  if (hex.length != 6 || value == null) return null;
  return Color(0xFF000000 | value);
}
