import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/catalog.dart';
import '../playback/timeline.dart';
import '../services/catalog_repository.dart';
import '../services/downloads.dart';
import '../services/settings.dart';
import '../updates/update_service.dart';
import 'common.dart';
import 'update_dialog.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  Future<void> _downloadMany(BuildContext context, String label, List<Voice> voices) async {
    final run = await context.read<Downloads>().downloadMany(label, voices);
    if (run != null && run.failed > 0 && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("${run.failed} download${run.failed == 1 ? '' : 's'} failed. Check your connection and try again.")),
      );
    }
  }

  Future<void> _confirmRemoveAll(BuildContext context) async {
    final downloads = context.read<Downloads>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove all downloads?'),
        content: const Text('Sessions stay in the app. They will be streamed again when you play them.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Remove')),
        ],
      ),
    );
    if (ok == true) await downloads.removeAll();
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<Settings>();
    final downloads = context.watch<Downloads>();
    final repo = context.watch<CatalogRepository>();
    final updates = context.watch<UpdateService>();
    final catalog = repo.catalog;
    final text = Theme.of(context).textTheme;
    final voices = catalog == null ? <Voice>[] : settings.voicesToDownload(catalog.sessions);
    final downloadedCount = downloads.downloadedCount(voices);
    final remaining = voices.where((v) => !downloads.isDownloaded(v)).fold(0, (sum, v) => sum + v.size);
    final bulk = downloads.bulk;
    final voiceNames = catalog?.voiceNames ?? const <String>[];

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: EdgeInsets.only(bottom: 32 + MediaQuery.paddingOf(context).bottom),
        children: [
          const _Header('Pauses'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Normal is the length each meditation was written with. Short halves every pause, Long doubles it.',
                    style: text.bodyMedium),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final p in PauseLength.values)
                      ChoiceChip(
                        label: Text(p.label),
                        selected: p == settings.pauseLength,
                        onSelected: (_) => settings.pauseLength = p,
                      ),
                  ],
                ),
              ],
            ),
          ),
          const _Header('Voice'),
          ListTile(
            title: const Text('Preferred voice'),
            subtitle: const Text('Picked automatically when a session has it'),
            trailing: DropdownButton<String?>(
              value: voiceNames.contains(settings.preferredVoice) ? settings.preferredVoice : null,
              underline: const SizedBox.shrink(),
              items: [
                const DropdownMenuItem<String?>(value: null, child: Text('Any')),
                for (final name in voiceNames) DropdownMenuItem<String?>(value: name, child: Text(name)),
              ],
              onChanged: (v) => settings.preferredVoice = v,
            ),
          ),
          const _Header('Downloads'),
          SwitchListTile(
            title: const Text('Download every voice'),
            subtitle: const Text('When off, only your preferred voice of each session is downloaded'),
            value: settings.downloadAllVoices,
            onChanged: (v) => settings.downloadAllVoices = v,
          ),
          if (bulk != null)
            ListTile(
              title: Text('Downloading ${bulk.label}… ${bulk.done} of ${bulk.total}'),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: LinearProgressIndicator(value: bulk.total == 0 ? null : bulk.done / bulk.total),
              ),
              trailing: TextButton(onPressed: bulk.cancelled ? null : downloads.cancelBulk, child: const Text('Cancel')),
            ),
          ListTile(
            leading: const Icon(Icons.download_for_offline_outlined),
            title: const Text('Download everything'),
            subtitle: Text(voices.isEmpty
                ? 'Nothing to download yet'
                : downloadedCount == voices.length
                    ? 'Everything is downloaded'
                    : '$downloadedCount of ${voices.length} downloaded · ${formatMegabytes(remaining)} to go'),
            enabled: bulk == null && downloadedCount < voices.length,
            onTap: () => _downloadMany(context, 'everything', voices),
          ),
          if (catalog != null)
            for (final group in catalog.groups)
              _GroupDownloads(group: group, onDownload: (v) => _downloadMany(context, group.name, v)),
          ListTile(
            leading: const Icon(Icons.delete_outline),
            title: const Text('Remove all downloads'),
            subtitle: Text('Using ${formatMegabytes(downloads.bytesUsed)}'),
            enabled: downloads.bytesUsed > 0 && bulk == null,
            onTap: () => _confirmRemoveAll(context),
          ),
          const _Header('Library'),
          ListTile(
            leading: const Icon(Icons.refresh),
            title: const Text('Check for new meditations'),
            subtitle: Text(repo.error ??
                (catalog?.generated != null ? 'Library updated ${_formatDate(catalog!.generated!)}' : 'Not loaded yet')),
            trailing: repo.loading
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : null,
            onTap: repo.loading ? null : repo.refresh,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            child: Text('Content source: ${repo.baseUri}',
                style: text.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ),
          if (updates.supported) ...[
            const _Header('App'),
            ListTile(
              leading: const Icon(Icons.system_update_outlined),
              title: const Text('Check for updates'),
              subtitle: Text('Version ${updates.current}'),
              trailing: updates.checking || updates.downloadProgress != null
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : null,
              onTap: updates.checking || updates.downloadProgress != null ? null : () => checkForUpdatesNow(context),
            ),
          ],
        ],
      ),
    );
  }
}

class _GroupDownloads extends StatelessWidget {
  const _GroupDownloads({required this.group, required this.onDownload});

  final Group group;
  final void Function(List<Voice> voices) onDownload;

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<Settings>();
    final downloads = context.watch<Downloads>();
    final voices = settings.voicesToDownload(group.sessions);
    final done = downloads.downloadedCount(voices);
    final busy = downloads.bulk != null;
    return ListTile(
      contentPadding: const EdgeInsetsDirectional.only(start: 72, end: 12),
      title: Text(group.name),
      subtitle: Text('$done of ${voices.length} downloaded'),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (done < voices.length)
            IconButton(
              tooltip: 'Download ${group.name}',
              icon: const Icon(Icons.download_outlined),
              onPressed: busy ? null : () => onDownload(voices),
            ),
          if (done > 0)
            IconButton(
              tooltip: 'Remove ${group.name} downloads',
              icon: const Icon(Icons.delete_outline),
              onPressed: busy ? null : () => downloads.removeMany(group.sessions.expand((s) => s.voices)),
            ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.title);

  final String title;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
        child: Text(title,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(color: Theme.of(context).colorScheme.primary)),
      );
}

String _formatDate(DateTime d) {
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  final local = d.toLocal();
  final time = '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  return '${local.day} ${months[local.month - 1]} ${local.year}, $time';
}
