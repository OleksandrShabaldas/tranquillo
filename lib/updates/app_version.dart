import 'dart:math' as math;

/// A version number like 1.4.2, as used in pubspec.yaml and in release tags
/// ("v1.4.2").
class AppVersion implements Comparable<AppVersion> {
  const AppVersion(this.parts);

  final List<int> parts;

  /// Reads "1.4.2", "v1.4.2", "1.4.2+7" or "1.4.2-beta" (the part after + or -
  /// is ignored). Returns null when there is no version number.
  static AppVersion? tryParse(String text) {
    final match = RegExp(r'\d+(?:\.\d+)*').firstMatch(text);
    if (match == null) return null;
    return AppVersion(match.group(0)!.split('.').map(int.parse).toList());
  }

  @override
  int compareTo(AppVersion other) {
    for (var i = 0; i < math.max(parts.length, other.parts.length); i++) {
      final a = i < parts.length ? parts[i] : 0;
      final b = i < other.parts.length ? other.parts[i] : 0;
      if (a != b) return a.compareTo(b);
    }
    return 0;
  }

  bool operator >(AppVersion other) => compareTo(other) > 0;

  @override
  bool operator ==(Object other) => other is AppVersion && compareTo(other) == 0;

  @override
  int get hashCode => Object.hashAll(parts.reversed.skipWhile((p) => p == 0));

  @override
  String toString() => parts.join('.');
}
