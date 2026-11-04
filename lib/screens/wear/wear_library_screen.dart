import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wear_plus/wear_plus.dart';
import 'package:yaabsa/api/library/library.dart';
import 'package:yaabsa/api/library/request/library_filter.dart';
import 'package:yaabsa/api/library/request/library_items_request.dart';
import 'package:yaabsa/api/library/request/library_sort.dart';
import 'package:yaabsa/api/library_items/library_item.dart';
import 'package:yaabsa/api/library/search_series.dart';
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

/// Pushes a nested browser screen and passes its [WearPick] on up the stack,
/// so a pick at any depth ends up at the player.
Future<void> _openAndForward(BuildContext context, Widget screen) async {
  final pick = await Navigator.of(context).push<WearPick>(MaterialPageRoute(builder: (_) => screen));
  if (pick != null && context.mounted) Navigator.of(context).pop(pick);
}

void _pickBook(BuildContext context, String itemId) =>
    Navigator.of(context).pop<WearPick>((itemId: itemId, episodeId: null));

/// Visible book count of a series. Only counts books the server actually
/// returned for this user, never the server's total (`numBooks`), which also
/// includes books hidden by permissions such as explicit content.
String _bookCount(int? count) => count == null ? 'Series' : (count == 1 ? '1 book' : '$count books');

/// Entry point for starting playback of something new on the watch: lists the
/// downloaded items and the user's book libraries. Pops with a [WearPick].
class WearLibraryScreen extends ConsumerStatefulWidget {
  const WearLibraryScreen({super.key});

  @override
  ConsumerState<WearLibraryScreen> createState() => _WearLibraryScreenState();
}

class _WearLibraryScreenState extends ConsumerState<WearLibraryScreen> {
  @override
  void initState() {
    super.initState();
    // The library list is kept alive for the whole app run (the selected
    // library depends on it), so it would otherwise only be fetched once.
    // Refetch on every open so granted or revoked library access shows up.
    ref.invalidate(userLibrariesProvider);
  }

  Future<void> _open(BuildContext context, Widget screen) => _openAndForward(context, screen);

  @override
  Widget build(BuildContext context) {
    final downloads = _playableDownloads(ref);
    final libraries = ref.watch(userLibrariesProvider);
    // While refetching, hide the previous list: it may still contain a
    // library the user can no longer open. On a failed fetch the provider
    // falls back to its cached list, so offline use still works.
    final bookLibraries = libraries.isLoading
        ? const <Library>[]
        : (libraries.value ?? const []).where((l) => l.mediaType == 'book').toList(growable: false);

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
          if (libraries.isLoading)
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
              onTap: () => _pickBook(context, download.item!.id),
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

/// Paged book list of a library (series collapsed into one entry each), or,
/// with [seriesId], the books of that series in reading order.
class _WearLibraryItemsScreen extends ConsumerStatefulWidget {
  const _WearLibraryItemsScreen({required this.libraryId, required this.name, this.seriesId});

  final String libraryId;
  final String name;
  final String? seriesId;

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
  List<SearchSeries> _seriesResults = const [];
  bool _searching = false;
  String? _searchError;

  bool get _isSeries => widget.seriesId != null;

  /// Header, plus the search field outside of a series.
  int get _leadingRows => _isSeries ? 1 : 2;

  void _openSeries(String seriesId, String name) =>
      _openAndForward(context, _WearLibraryItemsScreen(libraryId: widget.libraryId, name: name, seriesId: seriesId));

  Widget _seriesTile(String seriesId, String name, int? visibleBooks) => _WearTile(
    icon: Icons.collections_bookmark,
    title: name,
    subtitle: _bookCount(visibleBooks),
    chevron: true,
    onTap: () => _openSeries(seriesId, name),
  );

  /// The position of [item] in the series being shown, e.g. "2" or "1.5".
  String? _sequenceOf(LibraryItem item) {
    final series = item.media?.bookMedia?.metadata.series;
    final match = series?.where((s) => s.id == widget.seriesId).firstOrNull;
    final sequence = (match?.sequence ?? item.seriesPosition)?.trim();
    return sequence == null || sequence.isEmpty ? null : sequence;
  }

  Widget _itemTile(LibraryItem item) {
    final collapsed = item.collapsedSeries;
    if (collapsed != null) return _seriesTile(collapsed.id, item.title, collapsed.libraryItemIds?.length);
    final sequence = _isSeries ? _sequenceOf(item) : null;
    return _WearTile(
      subtitlePrefix: sequence == null ? null : '#$sequence',
      title: item.title,
      subtitle: item.authorString,
      onTap: () => _pickBook(context, item.id),
    );
  }

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
      _seriesResults = const [];
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
        // A series whose books are all hidden from this user is left out.
        _seriesResults = (data?.series ?? const []).where((r) => r.books.isNotEmpty).toList(growable: false);
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
      _seriesResults = const [];
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
    } else if (_results.isEmpty && _seriesResults.isEmpty) {
      children.add(const _Message('No matches.'));
    } else {
      // Series first: a matching series name is the more specific hit.
      for (final result in _seriesResults) {
        children.add(_seriesTile(result.series.id, result.series.name, result.books.length));
      }
      children.addAll(_results.map(_itemTile));
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
        _isSeries
            ? LibraryItemsRequest(
                limit: _pageSize,
                page: _nextPage,
                sort: 'sequence',
                desc: 0,
                filter: LibraryFilter.grouped(LibraryFilterGroup.series, widget.seriesId!).queryValue,
                collapseseries: 0,
              )
            : LibraryItemsRequest(
                limit: _pageSize,
                page: _nextPage,
                sort: defaultLibrarySortWireValue,
                desc: defaultLibrarySortDesc,
                collapseseries: 1,
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
        _error = _isSeries ? 'Could not load series' : 'Could not load library';
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
          itemCount: _leadingRows + _items.length + (showFooter ? 1 : 0) + (_items.isEmpty && !showFooter ? 1 : 0),
          itemBuilder: (context, index) {
            if (index == 0) return _Header(widget.name);
            if (index < _leadingRows) return _searchField();
            final i = index - _leadingRows;
            if (i < _items.length) return _itemTile(_items[i]);
            if (!showFooter) return _Message(_isSeries ? 'This series is empty.' : 'This library is empty.');
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
  const _WearTile({
    required this.title,
    required this.onTap,
    this.subtitle,
    this.icon,
    this.subtitlePrefix,
    this.trailing,
    this.chevron = false,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;

  /// Highlighted text in front of the subtitle, e.g. the "#2" position in a
  /// series. Kept off the title line so long titles keep the full width.
  final String? subtitlePrefix;
  final Widget? trailing;

  /// Marks tiles that open another list instead of playing.
  final bool chevron;
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
              padding: EdgeInsetsDirectional.only(
                start: 14,
                end: trailing != null ? 4 : (chevron ? 8 : 14),
                top: 6,
                bottom: 6,
              ),
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
                        if ((subtitle != null && subtitle.isNotEmpty) || subtitlePrefix != null)
                          Text.rich(
                            TextSpan(
                              children: [
                                if (subtitlePrefix != null)
                                  TextSpan(
                                    text: subtitle != null && subtitle.isNotEmpty
                                        ? '$subtitlePrefix · '
                                        : subtitlePrefix,
                                    style: TextStyle(fontWeight: FontWeight.w600, color: colorScheme.primary),
                                  ),
                                if (subtitle != null) TextSpan(text: subtitle),
                              ],
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 12, color: colorScheme.onSurface.withValues(alpha: 0.70)),
                          ),
                      ],
                    ),
                  ),
                  if (trailing != null) ...[
                    const SizedBox(width: 4),
                    trailing!,
                  ] else if (chevron) ...[
                    const SizedBox(width: 4),
                    Icon(Icons.chevron_right, size: 22, color: colorScheme.onSurface.withValues(alpha: 0.60)),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
