import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/catalog.dart';
import '../services/downloads.dart';
import '../services/settings.dart';
import 'common.dart';

class GroupScreen extends StatelessWidget {
  const GroupScreen({super.key, required this.group});

  final Group group;

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<Settings>();
    final downloads = context.watch<Downloads>();
    final voices = settings.voicesToDownload(group.sessions);
    final downloaded = downloads.downloadedCount(voices);
    final color = groupColor(group);

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar.large(
            title: Text(group.name),
            actions: [
              if (downloads.bulk?.label == group.name)
                const Padding(
                  padding: EdgeInsets.all(14),
                  child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                )
              else
                PopupMenuButton<String>(
                  tooltip: 'Downloads',
                  icon: Icon(downloaded == voices.length ? Icons.download_done : Icons.download_outlined),
                  itemBuilder: (_) => [
                    if (downloaded < voices.length)
                      PopupMenuItem(
                        value: 'download',
                        child: Text('Download group (${formatMegabytes(voices.where((v) => !downloads.isDownloaded(v)).fold(0, (a, v) => a + v.size))})'),
                      ),
                    if (downloaded > 0) const PopupMenuItem(value: 'remove', child: Text('Remove downloads')),
                  ],
                  onSelected: (action) async {
                    if (action == 'remove') {
                      await downloads.removeMany(group.sessions.expand((s) => s.voices));
                      return;
                    }
                    final run = await downloads.downloadMany(group.name, voices);
                    if (run != null && run.failed > 0 && context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text("${run.failed} download${run.failed == 1 ? '' : 's'} failed. Check your connection.")),
                      );
                    }
                  },
                ),
            ],
          ),
          if (group.description.isNotEmpty || group.tags.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (group.description.isNotEmpty) Text(group.description, style: Theme.of(context).textTheme.bodyLarge),
                    if (group.tags.isNotEmpty) ...[const SizedBox(height: 12), TagChips(group.tags, color: color)],
                  ],
                ),
              ),
            ),
          SliverList.list(children: [
            for (final s in group.sessions) SessionTile(session: s, group: group),
            SizedBox(height: 24 + MediaQuery.paddingOf(context).bottom),
          ]),
        ],
      ),
      bottomNavigationBar: const MiniPlayer(),
    );
  }
}
