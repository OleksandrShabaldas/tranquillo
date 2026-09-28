import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tranquillo/updates/app_version.dart';
import 'package:tranquillo/updates/update_service.dart';

Map<String, dynamic> _release(String tag, {List<Map<String, dynamic>>? assets}) => {
      'tag_name': tag,
      'html_url': 'https://github.com/OleksandrShabaldas/tranquillo/releases/tag/$tag',
      'body': 'Longer pauses\n- Bug fixes',
      'assets': assets ??
          [
            {'name': 'notes.txt', 'browser_download_url': 'https://example.com/notes.txt', 'size': 10},
            {'name': 'tranquillo-1.2.0.apk', 'browser_download_url': 'https://example.com/t.apk', 'size': 21000000},
          ],
    };

void main() {
  group('AppVersion', () {
    AppVersion v(String s) => AppVersion.tryParse(s)!;

    test('reads tags, pubspec versions and suffixes', () {
      expect(v('v1.2.3').toString(), '1.2.3');
      expect(v('1.2.3+7').toString(), '1.2.3');
      expect(v('v2.0.0-beta').toString(), '2.0.0');
      expect(AppVersion.tryParse('latest'), isNull);
    });

    test('compares number by number', () {
      expect(v('1.10.0') > v('1.9.9'), isTrue);
      expect(v('1.0.1') > v('1.0.0'), isTrue);
      expect(v('1.0.0') > v('1.0.0'), isFalse);
      expect(v('1.0') == v('1.0.0'), isTrue);
      expect(v('0.9.9') > v('1.0.0'), isFalse);
    });
  });

  group('AppRelease.fromGitHub', () {
    test('picks the APK and the notes', () {
      final r = AppRelease.fromGitHub(_release('v1.2.0'))!;
      expect(r.version.toString(), '1.2.0');
      expect(r.apk.toString(), 'https://example.com/t.apk');
      expect(r.apkSize, 21000000);
      expect(r.notes, startsWith('Longer pauses'));
    });

    test('handles releases without an APK or a version', () {
      expect(AppRelease.fromGitHub(_release('v1.2.0', assets: []))!.apk, isNull);
      expect(AppRelease.fromGitHub(_release('nightly')), isNull);
    });
  });

  group('UpdateService.check', () {
    Future<UpdateService> service(http.Response Function() respond, {String current = '1.1.0'}) async {
      SharedPreferences.setMockInitialValues({});
      return UpdateService(
        current: AppVersion.tryParse(current)!,
        prefs: await SharedPreferences.getInstance(),
        tempDir: Directory.systemTemp,
        client: MockClient((_) async => respond()),
      );
    }

    test('offers a newer release', () async {
      final s = await service(() => http.Response(jsonEncode(_release('v1.2.0')), 200));
      expect((await s.check())?.version.toString(), '1.2.0');
    });

    test('ignores the same or an older release', () async {
      final same = await service(() => http.Response(jsonEncode(_release('v1.2.0')), 200), current: '1.2.0');
      expect(await same.check(), isNull);
      final newer = await service(() => http.Response(jsonEncode(_release('v1.2.0')), 200), current: '1.3.0');
      expect(await newer.check(), isNull);
    });

    test('no releases yet is not an error', () async {
      final s = await service(() => http.Response('{"message": "Not Found"}', 404));
      expect(await s.check(), isNull);
    });

    test('other failures throw, but the automatic check stays quiet', () async {
      final s = await service(() => http.Response('rate limited', 403));
      await expectLater(s.check(), throwsA(isA<HttpException>()));
      expect(s.checking, isFalse);
    });

    Future<(UpdateService, int Function())> counting(http.Response Function() respond, {bool android = true}) async {
      var calls = 0;
      SharedPreferences.setMockInitialValues({});
      final s = UpdateService(
        current: AppVersion.tryParse('1.0.0')!,
        prefs: await SharedPreferences.getInstance(),
        tempDir: Directory.systemTemp,
        supported: android,
        client: MockClient((_) async {
          calls++;
          return respond();
        }),
      );
      return (s, () => calls);
    }

    test('the automatic check runs at most once per interval', () async {
      final (s, calls) = await counting(() => http.Response(jsonEncode(_release('v1.2.0')), 200));
      expect((await s.checkIfDue())?.version.toString(), '1.2.0');
      expect(await s.checkIfDue(), isNull);
      expect(calls(), 1);
    });

    test('the automatic check retries after a failure and stays quiet', () async {
      final (s, calls) = await counting(() => http.Response('offline', 503));
      expect(await s.checkIfDue(), isNull);
      expect(await s.checkIfDue(), isNull);
      expect(calls(), 2);
    });

    test('no automatic checks where updates are not supported', () async {
      final (s, calls) = await counting(() => http.Response(jsonEncode(_release('v1.2.0')), 200), android: false);
      expect(await s.checkIfDue(), isNull);
      expect(calls(), 0);
    });
  });
}
