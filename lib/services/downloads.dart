import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/catalog.dart';
import 'catalog_repository.dart';

/// Progress of a "download group" or "download everything" run.
class BulkDownload {
  BulkDownload(this.label, this.total);

  final String label;
  final int total;
  int done = 0;
  int failed = 0;
  bool cancelled = false;
}

/// Keeps audio files on the device.
///
/// Files are named after the content hash of the audio, so a replaced
/// recording is a new file: when the catalog shows that a downloaded voice
/// changed, the new version is fetched and the old file deleted.
///
/// Sessions that aren't downloaded are fetched into a temporary folder right
/// before playing ("streaming"). Recordings hold only the spoken parts, so
/// they're small and download in a few seconds; playing from a local file
/// keeps the cuts exact and a bad connection can't interrupt a meditation.
class Downloads extends ChangeNotifier {
  Downloads({
    required this.dir,
    required this.cacheDir,
    required this.repo,
    required this.prefs,
    http.Client? client,
  }) : _client = client ?? http.Client();

  final Directory dir;
  final Directory cacheDir;
  final CatalogRepository repo;
  final SharedPreferences prefs;
  final http.Client _client;

  static const _prefsKey = 'downloads';

  /// Downloaded voices: voice key -> hash of the downloaded version.
  final Map<String, String> _tracked = {};
  final Set<String> _files = {};
  final Map<String, double> _progress = {};
  bool _updatingOutdated = false;

  /// The running bulk download, if any.
  BulkDownload? bulk;
  int bytesUsed = 0;

  Future<void> init() async {
    await dir.create(recursive: true);
    await cacheDir.create(recursive: true);
    try {
      final saved = prefs.getString(_prefsKey);
      if (saved != null) _tracked.addAll((jsonDecode(saved) as Map).cast<String, String>());
    } catch (_) {
      // Unreadable list: files are still found below, just not tracked.
    }
    await for (final entry in dir.list()) {
      if (entry is! File) continue;
      if (entry.path.endsWith('.part')) {
        await entry.delete();
      } else {
        _files.add(p.basename(entry.path));
      }
    }
    _tracked.removeWhere((key, hash) => !_files.any((f) => f.startsWith(hash)));
    await _cleanCache();
    await _updateBytes();
    repo.addListener(_onCatalogChanged);
    _onCatalogChanged();
  }

  String _fileName(Voice v) => '${v.hash}${p.extension(v.file).toLowerCase()}';
  File _keptFile(Voice v) => File(p.join(dir.path, _fileName(v)));
  File _cacheFile(Voice v) => File(p.join(cacheDir.path, _fileName(v)));

  bool isDownloaded(Voice v) => _tracked[v.key] == v.hash && _files.contains(_fileName(v));
  bool isDownloading(Voice v) => _progress.containsKey(v.key);
  double? progressOf(Voice v) => _progress[v.key];
  int downloadedCount(Iterable<Voice> voices) => voices.where(isDownloaded).length;

  /// The file to play [voice] from: the downloaded copy if there is one,
  /// otherwise a temporary copy that is fetched now.
  Future<File> audioFor(Voice voice, {void Function(double progress)? onProgress}) async {
    final kept = _keptFile(voice);
    if (_files.contains(_fileName(voice)) && await kept.exists()) return kept;
    final cached = _cacheFile(voice);
    if (!await cached.exists()) await _fetch(voice, cached, onProgress);
    return cached;
  }

  /// Keeps [voice] on the device for offline listening.
  Future<void> download(Voice voice) async {
    if (isDownloaded(voice) || isDownloading(voice)) return;
    _progress[voice.key] = 0;
    notifyListeners();
    try {
      final target = _keptFile(voice);
      final cached = _cacheFile(voice);
      if (_files.contains(_fileName(voice)) && await target.exists()) {
        // Same audio is already here (another session uses identical audio).
      } else if (await cached.exists()) {
        await _move(cached, target);
      } else {
        await _fetch(voice, target, (x) {
          _progress[voice.key] = x;
          notifyListeners();
        });
      }
      _files.add(_fileName(voice));
      _tracked[voice.key] = voice.hash;
      await _save();
    } finally {
      _progress.remove(voice.key);
      await _updateBytes();
      notifyListeners();
    }
  }

  Future<void> remove(Voice voice) async {
    final hash = _tracked.remove(voice.key);
    if (hash != null) await _deleteIfUnused(hash);
    await _save();
    await _updateBytes();
    notifyListeners();
  }

  /// Downloads several voices one after another. Returns the finished run
  /// (or null if another bulk download is already running).
  Future<BulkDownload?> downloadMany(String label, Iterable<Voice> voices) async {
    if (bulk != null) return null;
    final todo = voices.where((v) => !isDownloaded(v)).toList();
    final run = bulk = BulkDownload(label, todo.length);
    notifyListeners();
    for (final voice in todo) {
      if (run.cancelled) break;
      try {
        await download(voice);
      } catch (_) {
        run.failed++;
      }
      run.done++;
      notifyListeners();
    }
    bulk = null;
    notifyListeners();
    return run;
  }

  /// Stops the bulk download after the file currently downloading.
  void cancelBulk() {
    bulk?.cancelled = true;
    notifyListeners();
  }

  Future<void> removeMany(Iterable<Voice> voices) async {
    for (final voice in voices.toList()) {
      final hash = _tracked.remove(voice.key);
      if (hash != null) await _deleteIfUnused(hash);
    }
    await _save();
    await _updateBytes();
    notifyListeners();
  }

  Future<void> removeAll() async {
    _tracked.clear();
    await for (final entry in dir.list()) {
      if (entry is File) await entry.delete();
    }
    _files.clear();
    await _save();
    await _updateBytes();
    notifyListeners();
  }

  void _onCatalogChanged() {
    final catalog = repo.catalog;
    if (catalog == null || _updatingOutdated) return;
    final outdated = [
      for (final e in _tracked.entries)
        if (catalog.voiceByKey(e.key) case final voice? when voice.hash != e.value) voice,
    ];
    if (outdated.isNotEmpty) _replaceOutdated(outdated);
  }

  /// Swaps downloaded recordings that were replaced on the content site.
  Future<void> _replaceOutdated(List<Voice> voices) async {
    _updatingOutdated = true;
    try {
      for (final voice in voices) {
        final oldHash = _tracked.remove(voice.key);
        try {
          await download(voice);
          if (oldHash != null) await _deleteIfUnused(oldHash);
        } catch (_) {
          // Keep the old copy tracked; the next catalog refresh tries again.
          if (oldHash != null) _tracked[voice.key] = oldHash;
        }
      }
      await _save();
      await _updateBytes();
      notifyListeners();
    } finally {
      _updatingOutdated = false;
    }
  }

  Future<void> _deleteIfUnused(String hash) async {
    if (_tracked.values.contains(hash)) return;
    for (final name in _files.where((f) => f.startsWith(hash)).toList()) {
      final file = File(p.join(dir.path, name));
      if (await file.exists()) await file.delete();
      _files.remove(name);
    }
  }

  Future<void> _fetch(Voice voice, File target, void Function(double)? onProgress) async {
    final part = File('${target.path}.part');
    final response = await _client.send(http.Request('GET', repo.audioUri(voice))).timeout(const Duration(seconds: 30));
    if (response.statusCode != 200) {
      await response.stream.drain<void>();
      throw HttpException('Download failed (${response.statusCode})');
    }
    final total = response.contentLength ?? voice.size;
    final sink = part.openWrite();
    var received = 0;
    var reported = 0.0;
    try {
      await for (final chunk in response.stream.timeout(const Duration(seconds: 30))) {
        sink.add(chunk);
        received += chunk.length;
        if (onProgress != null && total > 0) {
          final fraction = (received / total).clamp(0.0, 1.0);
          if (fraction - reported >= 0.02 || fraction == 1) {
            reported = fraction;
            onProgress(fraction);
          }
        }
      }
      await sink.close();
    } catch (_) {
      await sink.close();
      if (await part.exists()) await part.delete();
      rethrow;
    }
    if (voice.size > 0 && received != voice.size) {
      await part.delete();
      throw const HttpException('The download was incomplete');
    }
    await part.rename(target.path);
  }

  Future<void> _move(File from, File to) async {
    try {
      await from.rename(to.path);
    } on FileSystemException {
      await from.copy(to.path);
      await from.delete();
    }
  }

  Future<void> _cleanCache() async {
    final cutoff = DateTime.now().subtract(const Duration(days: 7));
    try {
      await for (final entry in cacheDir.list()) {
        if (entry is File && (await entry.lastModified()).isBefore(cutoff)) await entry.delete();
      }
    } on FileSystemException {
      // Cache cleanup is best effort.
    }
  }

  Future<void> _updateBytes() async {
    var total = 0;
    await for (final entry in dir.list()) {
      if (entry is File) total += await entry.length();
    }
    bytesUsed = total;
  }

  Future<void> _save() => prefs.setString(_prefsKey, jsonEncode(_tracked));
}
