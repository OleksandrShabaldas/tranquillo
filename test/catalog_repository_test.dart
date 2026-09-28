import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tranquillo/models/catalog.dart';
import 'package:tranquillo/services/catalog_repository.dart';

void main() {
  final repo = CatalogRepository(baseUrl: 'https://tranquillo-content.pages.dev', cacheFile: File('unused.json'));

  Voice voice(String file) =>
      Voice(id: 'anna', name: 'Anna', file: file, size: 1, hash: 'abc123', parts: const [], sessionId: 's');

  test('audio paths resolve against the content site, with spaces encoded', () {
    expect(
      repo.audioUri(voice('Meditations/Sleep/01 Wind Down/anna.mp3')).toString(),
      'https://tranquillo-content.pages.dev/Meditations/Sleep/01%20Wind%20Down/anna.mp3?v=abc123',
    );
  });

  test('full links are used as they are', () {
    expect(
      repo.audioUri(voice('https://audio.example.com/sleep/anna.mp3')).toString(),
      'https://audio.example.com/sleep/anna.mp3?v=abc123',
    );
  });
}
