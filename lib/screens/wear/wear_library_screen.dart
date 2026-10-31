import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yaabsa/api/library/request/library_items_request.dart';
import 'package:yaabsa/api/library/request/library_sort.dart';
import 'package:yaabsa/api/library_items/library_item.dart';
import 'package:yaabsa/models/internal_download.dart';
import 'package:yaabsa/provider/common/library_provider.dart';
import 'package:yaabsa/provider/common/stored_downloads_provider.dart';
import 'package:yaabsa/provider/core/user_providers.dart';

/// The item the user picked to play: library item id and optional episode id.
typedef WearPick = ({String itemId, String? episodeId});

const _roundInsets = EdgeInsets.fromLTRB(20, 28, 20, 36);

/// Entry point for starting playback of something new on the watch: lists the
/// downloaded items and the user's book libraries. Pops with a [WearPick].
class WearLibraryScreen extends ConsumerWidget {
  const WearLibraryScreen({super.key});

  Future<void> _open(BuildContext context, Widget screen) async {
    final pick = await Navigator.of(context).push<WearPick>(MaterialPageRoute(builder: (_) => screen));
    if (pick != null && context.mounted) Navigator.of(context).pop(pick);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final downloads = (ref.watch(storedDownloadsProvider).value ?? const <InternalDownload>[])
        .where((d) => d.item != null && !d.isPodcast && d.numberOfDownloadedTracks > 0)
        .toList(growable: false);
    final libraries = ref.watch(userLibrariesProvider);
    final bookLibraries = (libraries.value ?? const []).where((l) => l.mediaType == 'book').toList(growable: false);

    return Scaffold(
      body: ListView(
        padding: _roundInsets,
        children: [
          const _Header('Library'),
          if (downloads.isNotEmpty)
            _WearTile(
              icon: Icons.file_download_done,
              title: 'Downloaded',
              subtitle: '${downloads.length}',
              onTap: () => _open(context, _WearDownloadsScreen(downloads: downloads)),
            ),
          for (final library in bookLibraries)
            _WearTile(
              icon: Icons.library_books,
              title: library.name,
              onTap: () => _open(context, _WearLibraryItemsScreen(libraryId: library.id, name: library.name)),
            ),
          if (libraries.isLoading && bookLibraries.isEmpty)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else if (bookLibraries.isEmpty && downloads.isEmpty)
            const _Message('No libraries available.\nCheck your connection.'),
        ],
      ),
    );
  }
}

class _WearDownloadsScreen extends StatelessWidget {
  const _WearDownloadsScreen({required this.downloads});

  final List<InternalDownload> downloads;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ListView(
        padding: _roundInsets,
        children: [
          const _Header('Downloaded'),
          for (final download in downloads)
            _WearTile(
              title: download.item!.title,
              subtitle: download.item!.authorString,
              onTap: () => Navigator.of(context).pop<WearPick>((itemId: download.item!.id, episodeId: null)),
            ),
        ],
      ),
    );
  }
}

class _WearLibraryItemsScreen extends ConsumerStatefulWidget {
  const _WearLibraryItemsScreen({required this.libraryId, required this.name});

  final String libraryId;
  final String name;

  @override
  ConsumerState<_WearLibraryItemsScreen> createState() => _WearLibraryItemsScreenState();
}

class _WearLibraryItemsScreenState extends ConsumerState<_WearLibraryItemsScreen> {
  static const _pageSize = 20;

  final List<LibraryItem> _items = [];
  int _nextPage = 0;
  bool _hasMore = true, _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadMore();
  }

  Future<void> _loadMore() async {
    if (_loading || !_hasMore) return;
    final api = ref.read(absApiProvider);
    if (api == null) {
      setState(() => _error = 'Not connected');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = (await api.getLibraryApi().getLibraryItems(
        widget.libraryId,
        LibraryItemsRequest(
          limit: _pageSize,
          page: _nextPage,
          sort: defaultLibrarySortWireValue,
          desc: defaultLibrarySortDesc,
        ),
      )).data;
      if (!mounted) return;
      final results = data?.results ?? const <LibraryItem>[];
      setState(() {
        _items.addAll(results.where((i) => i.isMissing != true && i.isInvalid != true));
        _nextPage++;
        _hasMore = results.length == _pageSize && (data?.total == null || _nextPage * _pageSize < data!.total!);
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load library';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final showFooter = _loading || _error != null || _hasMore;
    return Scaffold(
      body: NotificationListener<ScrollNotification>(
        onNotification: (n) {
          if (n.metrics.extentAfter < 200) _loadMore();
          return false;
        },
        child: ListView.builder(
          padding: _roundInsets,
          itemCount: 1 + _items.length + (showFooter ? 1 : 0) + (_items.isEmpty && !showFooter ? 1 : 0),
          itemBuilder: (context, index) {
            if (index == 0) return _Header(widget.name);
            final i = index - 1;
            if (i < _items.length) {
              final item = _items[i];
              return _WearTile(
                title: item.title,
                subtitle: item.authorString,
                onTap: () => Navigator.of(context).pop<WearPick>((itemId: item.id, episodeId: null)),
              );
            }
            if (!showFooter) return const _Message('This library is empty.');
            if (_error != null) {
              return Column(
                children: [
                  _Message(_error!),
                  TextButton(
                    onPressed: _loadMore,
                    child: const Text('Retry', style: TextStyle(fontSize: 12)),
                  ),
                ],
              );
            }
            return const Padding(
              padding: EdgeInsets.all(12),
              child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
            );
          },
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      text,
      textAlign: TextAlign.center,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.primary),
    ),
  );
}

class _Message extends StatelessWidget {
  const _Message(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(12),
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.70)),
    ),
  );
}

class _WearTile extends StatelessWidget {
  const _WearTile({required this.title, required this.onTap, this.subtitle, this.icon});

  final String title;
  final String? subtitle;
  final IconData? icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final subtitle = this.subtitle;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Material(
        color: colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Row(
              children: [
                if (icon != null) ...[Icon(icon, size: 18, color: colorScheme.primary), const SizedBox(width: 10)],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: colorScheme.onSurface),
                      ),
                      if (subtitle != null && subtitle.isNotEmpty)
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 10, color: colorScheme.onSurface.withValues(alpha: 0.60)),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
