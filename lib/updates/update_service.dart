import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';
import 'app_version.dart';

/// A published version of the app (a GitHub release).
class AppRelease {
  const AppRelease({
    required this.version,
    required this.notes,
    required this.page,
    required this.apk,
    required this.apkSize,
  });

  final AppVersion version;

  /// The release description, shown as "What's new".
  final String notes;
  final Uri page;

  /// Download link of the APK attached to the release, if any.
  final Uri? apk;
  final int apkSize;

  /// Reads a release from GitHub's API (`/repos/{owner}/{repo}/releases/latest`).
  static AppRelease? fromGitHub(Map<String, dynamic> json) {
    final version = AppVersion.tryParse(json['tag_name'] as String? ?? '');
    if (version == null) return null;
    Map<String, dynamic>? apk;
    for (final asset in (json['assets'] as List? ?? const []).whereType<Map<String, dynamic>>()) {
      if ((asset['name'] as String? ?? '').toLowerCase().endsWith('.apk')) {
        apk = asset;
        break;
      }
    }
    return AppRelease(
      version: version,
      notes: (json['body'] as String? ?? '').trim(),
      page: Uri.tryParse(json['html_url'] as String? ?? '') ?? Uri.parse(releasesPageUrl),
      apk: apk == null ? null : Uri.tryParse(apk['browser_download_url'] as String? ?? ''),
      apkSize: (apk?['size'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Hands a downloaded APK to Android's installer (see MainActivity.kt).
class ApkInstaller {
  static const _channel = MethodChannel('tranquillo/installer');

  static Future<void> install(String path) => _channel.invokeMethod<void>('install', {'path': path});

  static Future<void> openUrl(Uri url) => _channel.invokeMethod<void>('openUrl', {'url': url.toString()});
}

/// Checks GitHub for a newer release of the app and installs it.
///
/// Only on Android: the app is distributed there as an APK attached to each
/// GitHub release. iPhones get updates through the App Store instead.
class UpdateService extends ChangeNotifier {
  UpdateService({
    required this.current,
    required this.prefs,
    required this.tempDir,
    http.Client? client,
    bool? supported,
  })  : _client = client ?? http.Client(),
        supported = supported ?? Platform.isAndroid;

  final AppVersion current;
  final SharedPreferences prefs;
  final Directory tempDir;
  final http.Client _client;

  /// Whether this device can install updates from GitHub (Android only).
  final bool supported;

  static const _lastCheckKey = 'updates.lastCheck';

  /// How often the app checks by itself when it starts.
  static const autoCheckInterval = Duration(hours: 20);

  bool checking = false;

  /// Download progress (0..1) while an update downloads, otherwise null.
  double? downloadProgress;

  Directory get _updatesDir => Directory(p.join(tempDir.path, 'updates'));

  /// Asks GitHub for the latest release. Returns it when it's newer than the
  /// installed app, otherwise null. Throws when GitHub can't be reached.
  Future<AppRelease?> check() async {
    checking = true;
    notifyListeners();
    try {
      final response = await _client.get(
        Uri.parse(latestReleaseUrl),
        headers: const {'Accept': 'application/vnd.github+json'},
      ).timeout(const Duration(seconds: 15));
      // 404 means nothing has been released yet.
      if (response.statusCode != 200 && response.statusCode != 404) {
        throw HttpException('GitHub answered ${response.statusCode}');
      }
      await prefs.setInt(_lastCheckKey, DateTime.now().millisecondsSinceEpoch);
      if (response.statusCode == 404) return null;
      final release = AppRelease.fromGitHub(jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>);
      return release != null && release.version > current ? release : null;
    } finally {
      checking = false;
      notifyListeners();
    }
  }

  /// The check made when the app starts: at most once per [autoCheckInterval],
  /// and silent when there's no connection.
  Future<AppRelease?> checkIfDue() async {
    if (!supported) return null;
    final last = prefs.getInt(_lastCheckKey);
    if (last != null && DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(last)) < autoCheckInterval) {
      return null;
    }
    try {
      return await check();
    } catch (_) {
      return null;
    }
  }

  /// Downloads the release's APK and opens Android's install screen.
  Future<void> downloadAndInstall(AppRelease release) async {
    final url = release.apk;
    if (url == null) throw StateError('This release has no APK attached');
    await cleanUp();
    await _updatesDir.create(recursive: true);
    final file = File(p.join(_updatesDir.path, 'tranquillo-${release.version}.apk'));
    downloadProgress = 0;
    notifyListeners();
    try {
      final response = await _client.send(http.Request('GET', url)).timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) {
        await response.stream.drain<void>();
        throw HttpException('Download failed (${response.statusCode})');
      }
      final total = response.contentLength ?? release.apkSize;
      final sink = file.openWrite();
      var received = 0;
      try {
        await for (final chunk in response.stream.timeout(const Duration(seconds: 30))) {
          sink.add(chunk);
          received += chunk.length;
          final progress = total > 0 ? (received / total).clamp(0.0, 1.0) : null;
          if (progress != null && progress - (downloadProgress ?? 0) >= 0.01) {
            downloadProgress = progress;
            notifyListeners();
          }
        }
      } finally {
        await sink.close();
      }
      if (release.apkSize > 0 && received != release.apkSize) {
        throw const HttpException('The download was incomplete');
      }
      await ApkInstaller.install(file.path);
    } finally {
      downloadProgress = null;
      notifyListeners();
    }
  }

  /// Deletes downloaded update files (they're no longer needed once installed).
  Future<void> cleanUp() async {
    try {
      if (await _updatesDir.exists()) await _updatesDir.delete(recursive: true);
    } on FileSystemException {
      // Best effort; the OS clears the cache folder eventually.
    }
  }
}
