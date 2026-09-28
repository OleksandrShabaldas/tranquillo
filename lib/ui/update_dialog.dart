import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../updates/update_service.dart';

/// Asks GitHub for a newer version and reports the result. Used by the
/// "Check for updates" button in Settings.
Future<void> checkForUpdatesNow(BuildContext context) async {
  final updates = context.read<UpdateService>();
  final messenger = ScaffoldMessenger.of(context);
  try {
    final release = await updates.check();
    if (!context.mounted) return;
    if (release == null) {
      messenger.showSnackBar(SnackBar(content: Text("You have the latest version (${updates.current}).")));
    } else {
      await offerUpdate(context, release);
    }
  } catch (_) {
    messenger.showSnackBar(const SnackBar(content: Text("Couldn't check for updates. Check your internet connection.")));
  }
}

/// Shows what's new in [release] and, if the listener agrees, downloads and
/// installs it.
Future<void> offerUpdate(BuildContext context, AppRelease release) async {
  final updates = context.read<UpdateService>();
  final text = Theme.of(context).textTheme;
  final accepted = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      icon: const Icon(Icons.system_update_outlined),
      title: const Text('Update available'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Tranquillo ${release.version} is ready. You have ${updates.current}.'),
            if (release.notes.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text("What's new", style: text.titleSmall),
              const SizedBox(height: 4),
              Text(release.notes),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Later')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Update')),
      ],
    ),
  );
  if (accepted != true || !context.mounted) return;

  final navigator = Navigator.of(context, rootNavigator: true);
  final messenger = ScaffoldMessenger.of(context);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => PopScope(
      canPop: false,
      child: AlertDialog(
        title: const Text('Downloading update'),
        content: ListenableBuilder(
          listenable: updates,
          builder: (context, _) {
            final progress = updates.downloadProgress;
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                LinearProgressIndicator(value: progress == null || progress == 0 ? null : progress),
                const SizedBox(height: 12),
                Text(progress == null ? 'Starting…' : '${(progress * 100).round()} %'),
              ],
            );
          },
        ),
      ),
    ),
  );

  Object? failure;
  try {
    await updates.downloadAndInstall(release);
  } catch (e) {
    failure = e;
  }
  navigator.pop();
  if (failure != null) {
    messenger.showSnackBar(SnackBar(
      content: const Text("The update couldn't be downloaded."),
      action: SnackBarAction(label: 'Open in browser', onPressed: () => ApkInstaller.openUrl(release.page)),
    ));
  }
}
