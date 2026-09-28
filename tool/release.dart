// Publishes a new version of Tranquillo as a GitHub release.
//
//   dart run tool/release.dart 1.0.1 "What's new in this version"
//
// It sets the version in pubspec.yaml (the build number goes up by one),
// builds the APK signed with your release key (android/key.properties),
// commits and tags the version, pushes, and creates the GitHub release with
// the APK attached. Installed apps offer the update the next time they check.
import 'dart:io';

Future<void> main(List<String> args) async {
  if (args.length != 2 || !RegExp(r'^\d+\.\d+\.\d+$').hasMatch(args[0])) {
    fail('Usage: dart run tool/release.dart <version, e.g. 1.0.1> "<what\'s new>"');
  }
  final version = args[0];
  final notes = args[1];
  Directory.current = File.fromUri(Platform.script).parent.parent;

  if (!File('android/key.properties').existsSync()) {
    fail("android/key.properties is missing, so the APK can't be signed with your release key (see README).");
  }
  if ((await run('git', ['status', '--porcelain'], quiet: true)).trim().isNotEmpty) {
    fail('There are uncommitted changes. Commit them first.');
  }

  final pubspec = File('pubspec.yaml');
  final text = pubspec.readAsStringSync();
  final current = RegExp(r'^version:\s*(\d+\.\d+\.\d+)\+(\d+)', multiLine: true).firstMatch(text);
  if (current == null) fail('pubspec.yaml has no "version: x.y.z+n" line.');
  if (_compare(version, current.group(1)!) < 0) {
    fail('$version is older than the current version ${current.group(1)}.');
  }
  final build = int.parse(current.group(2)!) + 1;
  pubspec.writeAsStringSync(text.replaceFirst(current.group(0)!, 'version: $version+$build'));

  await run('flutter', ['build', 'apk', '--release']);
  final apk = 'build/app/outputs/flutter-apk/tranquillo-$version.apk';
  File('build/app/outputs/flutter-apk/app-release.apk').copySync(apk);

  await run('git', ['commit', '--quiet', '-am', 'Release $version']);
  await run('git', ['tag', 'v$version']);
  await run('git', ['push', '--quiet', 'origin', 'HEAD', 'v$version']);

  final notesFile = File('${Directory.systemTemp.path}/tranquillo-release-notes.md')..writeAsStringSync(notes);
  await run('gh', ['release', 'create', 'v$version', apk, '--title', 'Tranquillo $version', '--notes-file', notesFile.path]);
  notesFile.deleteSync();
  stdout.writeln('\nReleased Tranquillo $version.');
}

Never fail(String message) {
  stderr.writeln(message);
  exit(1);
}

/// Runs a command, showing its output (or returning it when [quiet]).
/// Stops the release if the command fails.
Future<String> run(String executable, List<String> args, {bool quiet = false}) async {
  if (!quiet) stdout.writeln('\n> $executable ${args.join(' ')}');
  // flutter is a .bat file on Windows, which needs a shell. Other commands
  // run directly so that arguments like release notes aren't reinterpreted.
  final process = await Process.start(
    executable,
    args,
    runInShell: Platform.isWindows && executable == 'flutter',
    mode: quiet ? ProcessStartMode.normal : ProcessStartMode.inheritStdio,
  );
  var output = '';
  if (quiet) {
    final collected = process.stdout.transform(systemEncoding.decoder).join();
    await process.stderr.drain<void>();
    output = await collected;
  }
  final code = await process.exitCode;
  if (code != 0) fail('"$executable ${args.first}" failed (exit code $code).');
  return output;
}

int _compare(String a, String b) {
  final x = a.split('.').map(int.parse).toList(), y = b.split('.').map(int.parse).toList();
  for (var i = 0; i < 3; i++) {
    if (x[i] != y[i]) return x[i].compareTo(y[i]);
  }
  return 0;
}
