import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/catalog.dart';

/// Loads the list of meditations (catalog.json) from the content site and
/// keeps a copy on the device so the app also works offline.
class CatalogRepository extends ChangeNotifier {
  CatalogRepository({required String baseUrl, required this.cacheFile, http.Client? client})
      : baseUri = Uri.parse(baseUrl.endsWith('/') ? baseUrl : '$baseUrl/'),
        _client = client ?? http.Client();

  final Uri baseUri;
  final File cacheFile;
  final http.Client _client;

  Catalog? catalog;
  bool loading = false;
  String? error;

  /// Reads the copy saved on the device, if there is one.
  Future<void> loadCached() async {
    try {
      if (await cacheFile.exists()) {
        catalog = Catalog.fromJson(jsonDecode(await cacheFile.readAsString()) as Map<String, dynamic>);
        notifyListeners();
      }
    } catch (_) {
      // A damaged cache is simply replaced by the next download.
    }
  }

  /// Downloads the latest catalog. On failure the previous one stays in use.
  Future<void> refresh() async {
    if (loading) return;
    loading = true;
    error = null;
    notifyListeners();
    try {
      final response = await _client.get(baseUri.resolve('catalog.json')).timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) {
        throw HttpException('The content site answered ${response.statusCode}');
      }
      final body = utf8.decode(response.bodyBytes);
      catalog = Catalog.fromJson(jsonDecode(body) as Map<String, dynamic>);
      await cacheFile.parent.create(recursive: true);
      await cacheFile.writeAsString(body);
    } on SocketException {
      error = "Can't reach the meditation library. Check your internet connection.";
    } on TimeoutException {
      error = 'The meditation library took too long to answer.';
    } catch (e) {
      error = "Couldn't load the meditation library ($e).";
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  /// Download link for a voice's audio. `file` is usually a path on the
  /// content site, but can also be a full link (for audio stored elsewhere).
  /// The hash makes the link change when the file is replaced, so caches
  /// never serve an old version.
  Uri audioUri(Voice voice) {
    final isFullLink = voice.file.startsWith('https://') || voice.file.startsWith('http://');
    final link = isFullLink ? Uri.parse(voice.file) : baseUri.resolveUri(Uri(path: voice.file));
    return link.replace(queryParameters: {...link.queryParameters, 'v': voice.hash});
  }
}
