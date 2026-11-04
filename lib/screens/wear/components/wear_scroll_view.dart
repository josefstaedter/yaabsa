import 'package:material_ui/material_ui.dart';
import 'package:wear_plus/wear_plus.dart';

class WearScrollView extends StatefulWidget {
  const WearScrollView({required this.children, super.key}) : itemCount = 0, itemBuilder = null;

  /// Lazily built list for long or paged content. Items start at the top
  /// instead of being centered like [children].
  const WearScrollView.builder({required this.itemCount, required this.itemBuilder, super.key}) : children = const [];

  final List<Widget> children;
  final int itemCount;
  final IndexedWidgetBuilder? itemBuilder;

  @override
  State<WearScrollView> createState() => _WearScrollViewState();
}

class _WearScrollViewState extends State<WearScrollView> {
  final _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return WatchShape(
      builder: (context, shape, child) {
        return SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final padding = shape == WearShape.round
                  ? EdgeInsets.symmetric(
                      horizontal: constraints.maxWidth * 0.14,
                      vertical: constraints.maxHeight * 0.12,
                    )
                  : const EdgeInsets.all(12);

              final itemBuilder = widget.itemBuilder;
              final scrollView = itemBuilder != null
                  ? ListView.builder(
                      controller: _controller,
                      padding: padding,
                      itemCount: widget.itemCount,
                      itemBuilder: itemBuilder,
                    )
                  : SingleChildScrollView(
                      controller: _controller,
                      padding: padding,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(minHeight: constraints.maxHeight - padding.vertical),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: widget.children,
                        ),
                      ),
                    );

              if (shape == WearShape.round) {
                return ScrollConfiguration(
                  behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
                  child: RawScrollbar(
                    controller: _controller,
                    interactive: false,
                    thickness: 3,
                    radius: const Radius.circular(3),
                    minThumbLength: 16,
                    mainAxisMargin: constraints.maxHeight * 0.25,
                    crossAxisMargin: constraints.maxWidth * 0.07,
                    thumbColor: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.70),
                    child: scrollView,
                  ),
                );
              }

              return Scrollbar(controller: _controller, child: scrollView);
            },
          ),
        );
      },
    );
  }
}
