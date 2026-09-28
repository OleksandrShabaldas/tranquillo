# Tranquillo

Guided meditations where you choose how long the pauses are.

Each meditation is recorded once and holds only the spoken parts. A small file per recording marks where each
part starts and ends. While playing, the app puts silence of the listener's chosen length (Short, Normal, Long,
Extra long) between the parts, so the pause length is a setting rather than part of the recording.

## Download

Android: install the APK from the [latest release](https://github.com/OleksandrShabaldas/tranquillo/releases/latest).
The app checks for new versions by itself and offers to install them.

## How it works

| Part | Where |
| --- | --- |
| Library of groups, sessions and voices: `catalog.json` from the content site, cached for offline use | `lib/services/catalog_repository.dart` |
| Playback: clips of the recording with clips of a silent WAV in between, played as one track in the background and on the lock screen (just_audio and audio_service) | `lib/playback/` |
| Downloads: files are named after their content hash, so replaced recordings update automatically | `lib/services/downloads.dart` |
| Updates: checks the latest GitHub release when the app starts (at most once a day) and from Settings, then downloads the APK and opens Android's installer | `lib/updates/`, `MainActivity.kt` |

The meditations live in a separate private repository. That repository is published to
`https://tranquillo-content.pages.dev/`, which is set in `lib/config.dart`.

## Development

```
flutter run
flutter test
```

To test against a local copy of the content, run `flutter run --dart-define=CONTENT_URL=http://10.0.2.2:8765/_site/`.
From the Android emulator, 10.0.2.2 is your computer.

## Publishing a new version

```
dart run tool/release.dart 1.0.1 "What's new in this version"
```

This one command:
1. Sets the version in `pubspec.yaml`.
2. Builds the signed APK.
3. Commits, tags and pushes.
4. Creates the GitHub release with the APK attached.

Installed apps offer the update the next time they check.

### Signing key

Releases are signed with a key that is **not** in this repository. `android/key.properties` points to it, and git
ignores that file:

```
storePassword=…
keyPassword=…
keyAlias=tranquillo
storeFile=C:/path/to/tranquillo-release.jks
```

Android only installs an update if it's signed with the same key as the installed app. Keep a backup of the
keystore and `key.properties`. Without them, you can't publish updates that existing installs will accept.
