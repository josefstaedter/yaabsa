import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wear_plus/wear_plus.dart';
import 'package:yaabsa/api/library/request/library_items_request.dart';
import 'package:yaabsa/api/library/request/library_sort.dart';
import 'package:yaabsa/api/library_items/library_item.dart';
import 'package:yaabsa/models/internal_download.dart';
import 'package:yaabsa/provider/common/library_provider.dart';
import 'package:yaabsa/provider/common/stored_downloads_provider.dart';
import 'package:yaabsa/provider/core/user_providers.dart';
import 'package:yaabsa/screens/wear/components/wear_ambient_view.dart';
import 'package:yaabsa/screens/wear/components/wear_scroll_view.dart';
import 'package:yaabsa/screens/wear/components/wear_swipe_to_dismiss.dart';
import 'package:yaabsa/util/globals.dart' show downloadHandler;

/// The item the user picked to play: library item id and optional episode id.
typedef WearPick = ({String itemId, String? episodeId});

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
    final downloads = _playableDownloads(ref);
    final libraries = ref.watch(userLibrariesProvider);
    final bookLibraries = (libraries.value ?? const []).where((l) => l.mediaType == 'book').toList(growable: false);

    return _WearPage(
      child: WearScrollView(
        children: [
          const _Header('Library'),
          if (downloads.isNotEmpty)
            _WearTile(
              icon: Icons.file_download_done,
              title: 'Downloaded',
              subtitle: '${downloads.length}',
              onTap: () => _open(context, const _WearDownloadsScreen()),
            ),
          for (final library in bookLibraries)
            _WearTile(
              icon: Icons.library_books,
              title: library.name,
              onTap: () => _open(context, _WearLibraryItemsScreen(libraryId: library.id, name: library.name)),
            ),
          if (libraries.isLoading && bookLibraries.isEmpty)
            const _Spinner()
          else if (bookLibraries.isEmpty && downloads.isEmpty)
            const _Message('No libraries available.\nCheck your connection.'),
        ],
      ),
    );
  }
}

List<InternalDownload> _playableDownloads(WidgetRef ref) =>
    (ref.watch(storedDownloadsProvider).value ?? const <InternalDownload>[])
        .where((d) => d.item != null && !d.isPodcast && d.numberOfDownloadedTracks > 0)
        .toList(growable: false);

class _WearDownloadsScreen extends ConsumerWidget {
  const _WearDownloadsScreen();

  Future<void> _delete(BuildContext context, WidgetRef ref, InternalDownload download) async {
    final colorScheme = Theme.of(context).colorScheme;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.all(24),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Delete download?',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: colorScheme.onSurface),
              ),
              const SizedBox(height: 4),
              Text(
                download.item!.title,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: colorScheme.onSurface.withValues(alpha: 0.70)),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  IconButton(
                    icon: const Icon(Icons.close),
                    tooltip: 'Cancel',
                    constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                    onPressed: () => Navigator.of(context).pop(false),
                  ),
                  IconButton.filled(
                    icon: const Icon(Icons.delete),
                    tooltip: 'Delete',
                    constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                    style: IconButton.styleFrom(
                      backgroundColor: colorScheme.error,
                      foregroundColor: colorScheme.onError,
                    ),
                    onPressed: () => Navigator.of(context).pop(true),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (confirmed != true) return;
    final user = ref.read(currentUserProvider).value;
    if (user == null) return;
    var failed = false;
    try {
      failed = (await downloadHandler.deleteDownloadedItem(download, userId: user.id)).failedFiles > 0;
    } catch (_) {
      failed = true;
    }
    if (failed && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not delete download')));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final downloads = _playableDownloads(ref);
    return _WearPage(
      child: WearScrollView(
        children: [
          const _Header('Downloaded'),
          for (final download in downloads)
            _WearTile(
              title: download.item!.title,
              subtitle: download.item!.authorString,
              onTap: () => Navigator.of(context).pop<WearPick>((itemId: download.item!.id, episodeId: null)),
              trailing: IconButton(
                icon: Icon(Icons.delete_outline, size: 22, color: Theme.of(context).colorScheme.error),
                tooltip: 'Delete download',
                onPressed: () => _delete(context, ref, download),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              ),
            ),
          if (downloads.isEmpty) const _Message('No downloads.'),
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

  final _searchController = TextEditingController();

  /// Non-null while showing results for a submitted query instead of the paged list.
  String? _query;
  List<LibraryItem> _results = const [];
  bool _searching = false;
  String? _searchError;

  @override
  void initState() {
    super.initState();
    _loadMore();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _search(String raw) async {
    final query = raw.trim();
    if (query.isEmpty) {
      _clearSearch();
      return;
    }
    final api = ref.read(absApiProvider);
    setState(() {
      _query = query;
      _results = const [];
      _searching = api != null;
      _searchError = api == null ? 'Not connected' : null;
    });
    if (api == null) return;
    try {
      final data = (await api.getLibraryApi().getSearchLibrary(widget.libraryId, query, limit: 25)).data;
      if (!mounted || _query != query) return;
      setState(() {
        _results = (data?.book ?? const [])
            .map((r) => r.libraryItem)
            .whereType<LibraryItem>()
            .where((i) => i.isMissing != true && i.isInvalid != true)
            .toList(growable: false);
        _searching = false;
      });
    } catch (_) {
      if (!mounted || _query != query) return;
      setState(() {
        _searchError = 'Search failed';
        _searching = false;
      });
    }
  }

  void _clearSearch() {
    _searchController.clear();
    FocusScope.of(context).unfocus();
    setState(() {
      _query = null;
      _results = const [];
      _searching = false;
      _searchError = null;
    });
  }

  Widget _searchField() {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: TextField(
        controller: _searchController,
        textInputAction: TextInputAction.search,
        onSubmitted: _search,
        style: TextStyle(fontSize: 14, color: colorScheme.onSurface),
        decoration: InputDecoration(
          hintText: 'Search',
          hintStyle: TextStyle(fontSize: 14, color: colorScheme.onSurface.withValues(alpha: 0.60)),
          prefixIcon: Icon(Icons.search, size: 20, color: colorScheme.onSurface.withValues(alpha: 0.70)),
          prefixIconConstraints: const BoxConstraints(minWidth: 40, minHeight: 48),
          suffixIcon: _query != null
              ? IconButton(
                  icon: Icon(Icons.close, size: 20, color: colorScheme.onSurface.withValues(alpha: 0.70)),
                  tooltip: 'Clear search',
                  onPressed: _clearSearch,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                )
              : null,
          constraints: const BoxConstraints(minHeight: 48),
          filled: true,
          fillColor: colorScheme.surfaceContainerHigh,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
        ),
      ),
    );
  }

  Widget _searchResults() {
    final children = <Widget>[_Header(widget.name), _searchField()];
    if (_searching) {
      children.add(const _Spinner());
    } else if (_searchError != null) {
      children.addAll([_Message(_searchError!), _RetryButton(onPressed: () => _search(_query!))]);
    } else if (_results.isEmpty) {
      children.add(const _Message('No matches.'));
    } else {
      for (final item in _results) {
        children.add(
          _WearTile(
            title: item.title,
            subtitle: item.authorString,
            onTap: () => Navigator.of(context).pop<WearPick>((itemId: item.id, episodeId: null)),
          ),
        );
      }
    }
    return WearScrollView.builder(itemCount: children.length, itemBuilder: (_, i) => children[i]);
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
    if (_query != null) return _WearPage(child: _searchResults());
    final showFooter = _loading || _error != null || _hasMore;
    return _WearPage(
      child: NotificationListener<ScrollNotification>(
        onNotification: (n) {
          if (n.metrics.extentAfter < 200) _loadMore();
          return false;
        },
        child: WearScrollView.builder(
          itemCount: 2 + _items.length + (showFooter ? 1 : 0) + (_items.isEmpty && !showFooter ? 1 : 0),
          itemBuilder: (context, index) {
            if (index == 0) return _Header(widget.name);
            if (index == 1) return _searchField();
            final i = index - 2;
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
                  _RetryButton(onPressed: _loadMore),
                ],
              );
            }
            return const _Spinner();
          },
        ),
      ),
    );
  }
}

/// Shared frame for the library screens: swipe right to go back, and the
/// burn-in safe ambient view while the watch is dimmed.
class _WearPage extends StatelessWidget {
  const _WearPage({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => WearSwipeToDismiss(
    child: AmbientMode(
      builder: (context, mode, _) => Scaffold(body: mode == WearMode.ambient ? const WearAmbientView() : child),
    ),
  );
}

class _Spinner extends StatelessWidget {
  const _Spinner();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.all(12),
    child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
  );
}

class _RetryButton extends StatelessWidget {
  const _RetryButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => TextButton(
    onPressed: onPressed,
    style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
    child: const Text('Retry', style: TextStyle(fontSize: 12)),
  );
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
      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.primary),
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
      style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.70)),
    ),
  );
}

class _WearTile extends StatelessWidget {
  const _WearTile({required this.title, required this.onTap, this.subtitle, this.icon, this.trailing});

  final String title;
  final String? subtitle;
  final IconData? icon;
  final Widget? trailing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final subtitle = this.subtitle;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Material(
        color: colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(24),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: EdgeInsetsDirectional.only(start: 14, end: trailing != null ? 4 : 14, top: 6, bottom: 6),
              child: Row(
                children: [
                  if (icon != null) ...[Icon(icon, size: 22, color: colorScheme.primary), const SizedBox(width: 10)],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: colorScheme.onSurface),
                        ),
                        if (subtitle != null && subtitle.isNotEmpty)
                          Text(
                            subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 12, color: colorScheme.onSurface.withValues(alpha: 0.70)),
                          ),
                      ],
                    ),
                  ),
                  if (trailing != null) ...[const SizedBox(width: 4), trailing!],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
