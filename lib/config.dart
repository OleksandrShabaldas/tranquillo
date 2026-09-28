/// Address of the content site built from your meditations repo
/// (it serves catalog.json and the audio files).
///
/// For testing against a local copy:
///   flutter run --dart-define=CONTENT_URL=http://10.0.2.2:8765/_site/
/// (10.0.2.2 is how the Android emulator reaches your computer.)
const String contentBaseUrl = String.fromEnvironment(
  'CONTENT_URL',
  defaultValue: 'https://tranquillo-content.pages.dev/',
);

/// GitHub repository whose releases the Android app updates itself from.
const String releasesRepo = 'OleksandrShabaldas/tranquillo';

/// Where the app asks for the newest release. Can be pointed at a test file:
///   flutter run --dart-define=UPDATES_URL=http://10.0.2.2:8766/latest.json
const String latestReleaseUrl = String.fromEnvironment(
  'UPDATES_URL',
  defaultValue: 'https://api.github.com/repos/$releasesRepo/releases/latest',
);

const String releasesPageUrl = 'https://github.com/$releasesRepo/releases';
