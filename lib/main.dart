import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'config.dart';
import 'playback/audio_handler.dart';
import 'playback/silence.dart';
import 'services/catalog_repository.dart';
import 'services/downloads.dart';
import 'services/settings.dart';
import 'ui/common.dart';
import 'ui/home_screen.dart';
import 'updates/app_version.dart';
import 'updates/update_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final support = await getApplicationSupportDirectory();
  final temp = await getTemporaryDirectory();
  final prefs = await SharedPreferences.getInstance();
  final silence = await silenceFile(support);

  // Spoken-word audio: pauses (instead of ducking) when another app speaks.
  final audioSession = await AudioSession.instance;
  await audioSession.configure(const AudioSessionConfiguration.speech());

  final handler = await AudioService.init(
    builder: () => MeditationHandler(silence),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.oleksandrshabaldas.tranquillo.playback',
      androidNotificationChannelName: 'Meditation playback',
      androidNotificationIcon: 'drawable/ic_stat_tranquillo',
    ),
  );

  final settings = Settings(prefs);
  final repo = CatalogRepository(baseUrl: contentBaseUrl, cacheFile: File(p.join(support.path, 'catalog.json')));
  final downloads = Downloads(
    dir: Directory(p.join(support.path, 'downloads')),
    cacheDir: Directory(p.join(temp.path, 'streamed')),
    repo: repo,
    prefs: prefs,
  );
  await repo.loadCached();
  await downloads.init();
  unawaited(repo.refresh());

  final packageInfo = await PackageInfo.fromPlatform();
  final updates = UpdateService(
    current: AppVersion.tryParse(packageInfo.version) ?? const AppVersion([0]),
    prefs: prefs,
    tempDir: temp,
  );
  unawaited(updates.cleanUp());

  runApp(MultiProvider(
    providers: [
      Provider<MeditationHandler>.value(value: handler),
      ChangeNotifierProvider.value(value: settings),
      ChangeNotifierProvider.value(value: repo),
      ChangeNotifierProvider.value(value: downloads),
      ChangeNotifierProvider.value(value: updates),
    ],
    child: const TranquilloApp(),
  ));
}

class TranquilloApp extends StatelessWidget {
  const TranquilloApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Tranquillo',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      home: const HomeScreen(),
    );
  }
}
