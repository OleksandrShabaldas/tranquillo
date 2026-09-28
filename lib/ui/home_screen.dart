import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/catalog.dart';
import '../services/catalog_repository.dart';
import '../services/settings.dart';
import '../updates/update_service.dart';
import 'common.dart';
import 'group_screen.dart';
import 'settings_screen.dart';
import 'update_dialog.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String? _tag;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _offerUpdateIfAvailable());
  }

  /// Looks for a newer version on GitHub shortly after the app opens.
  Future<void> _offerUpdateIfAvailable() async {
    final updates = context.read<UpdateService>();
    await Future<void>.delayed(const Duration(seconds: 2));
    final release = await updates.checkIfDue();
    if (release != null && mounted) await offerUpdate(context, release);
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<CatalogRepository>();
    final catalog = repo.catalog;
    final tag = catalog != null && catalog.tags.contains(_tag) ? _tag : null;

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: repo.refresh,
        child: CustomScrollView(
          slivers: [
            SliverAppBar.large(
              title: const Text('Tranquillo'),
              actions: [
                IconButton(
                  tooltip: 'Settings',
                  icon: const Icon(Icons.settings_outlined),
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsScreen())),
                ),
              ],
            ),
            if (repo.error != null)
              SliverToBoxAdapter(child: _Banner(message: repo.error!, onRetry: repo.refresh, offline: catalog != null)),
            if (catalog == null || catalog.groups.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: repo.loading
                      ? const CircularProgressIndicator()
                      : const _EmptyState(),
                ),
              )
            else ...[
              if (catalog.tags.isNotEmpty)
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: 52,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      children: [
                        for (final t in catalog.tags)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: FilterChip(
                              label: Text(t),
                              selected: t == tag,
                              onSelected: (on) => setState(() => _tag = on ? t : null),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              if (tag == null)
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(16, 8, 16, 24 + MediaQuery.paddingOf(context).bottom),
                  sliver: SliverList.separated(
                    itemCount: catalog.groups.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 14),
                    itemBuilder: (context, i) => _GroupCard(group: catalog.groups[i]),
                  ),
                )
              else
                SliverList.list(children: [
                  for (final s in catalog.sessionsTagged(tag))
                    SessionTile(session: s, group: catalog.groupById(s.groupId), showGroup: true),
                  SizedBox(height: 24 + MediaQuery.paddingOf(context).bottom),
                ]),
            ],
          ],
        ),
      ),
      bottomNavigationBar: const MiniPlayer(),
    );
  }
}

class _GroupCard extends StatelessWidget {
  const _GroupCard({required this.group});

  final Group group;

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<Settings>();
    final color = groupColor(group);
    final fg = onColor(color);
    final text = Theme.of(context).textTheme;
    final lengths = [for (final s in group.sessions) settings.voiceFor(s).lengthWith(settings.pauseLength.scale)]..sort();
    final shortest = formatMinutes(lengths.first), longest = formatMinutes(lengths.last);
    final count = group.sessions.length;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => GroupScreen(group: group))),
        child: Ink(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [color, Color.lerp(color, Colors.black, 0.25)!],
            ),
          ),
          padding: const EdgeInsets.fromLTRB(22, 22, 22, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(group.name, style: text.headlineSmall?.copyWith(color: fg, fontWeight: FontWeight.w600)),
              if (group.description.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(group.description, maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: text.bodyMedium?.copyWith(color: fg.withValues(alpha: 0.9))),
              ],
              const SizedBox(height: 16),
              Text(
                '$count session${count == 1 ? '' : 's'} · ${shortest == longest ? shortest : '$shortest – $longest'}',
                style: text.labelLarge?.copyWith(color: fg.withValues(alpha: 0.85)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.message, required this.onRetry, required this.offline});

  final String message;
  final Future<void> Function() onRetry;
  final bool offline;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Material(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
          child: Row(
            children: [
              Icon(Icons.cloud_off_outlined, color: scheme.onErrorContainer),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  offline ? '$message Showing the last saved library.' : message,
                  style: TextStyle(color: scheme.onErrorContainer),
                ),
              ),
              TextButton(onPressed: onRetry, child: const Text('Retry')),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.spa_outlined, size: 48, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 16),
          Text('No meditations yet', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          const Text('Pull down to check again.', textAlign: TextAlign.center),
        ],
      ),
    );
  }
}
