import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

import '../state/random_image_controller.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.controller, this.cacheManager});

  final RandomImageController controller;

  /// Backs the image widget; null uses the shared disk cache. Injectable so
  /// tests can serve or fail images deterministically.
  final BaseCacheManager? cacheManager;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  ImageStream? _pendingImage;
  ImageStreamListener? _pendingImageListener;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onStateChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onStateChanged);
    _stopWaitingForImage();
    super.dispose();
  }

  void _onStateChanged() {
    _stopWaitingForImage();
    final state = widget.controller.state;
    if (state is RandomImageLoaded) _announceWhenShown(state.url);
  }

  /// Tells screen reader users about the new image once it has decoded – not
  /// when its URL arrives, since the download takes a moment and a few URLs
  /// are dead. The error panel is a live region and announces itself.
  ///
  /// Resolving the same provider as the image widget shares its cache entry,
  /// so this costs no extra download or decode.
  void _announceWhenShown(String url) {
    final stream = CachedNetworkImageProvider(
      url,
      cacheManager: widget.cacheManager,
    ).resolve(ImageConfiguration.empty);
    late final ImageStreamListener listener;
    listener = ImageStreamListener(
      (ImageInfo info, _) {
        info.dispose();
        _stopWaitingForImage();
        if (!mounted) return;
        SemanticsService.sendAnnouncement(
          View.of(context),
          'New image loaded',
          Directionality.of(context),
        );
      },
      onError: (_, _) => _stopWaitingForImage(),
    );
    _pendingImage = stream;
    _pendingImageListener = listener;
    stream.addListener(listener);
  }

  void _stopWaitingForImage() {
    final listener = _pendingImageListener;
    if (listener != null) _pendingImage?.removeListener(listener);
    _pendingImage = null;
    _pendingImageListener = null;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final square = _Square(
          child: _ImageSquare(
            state: widget.controller.state,
            cacheManager: widget.cacheManager,
            onRetry: widget.controller.fetch,
            onImageFailed: widget.controller.imageFailed,
          ),
        );
        final button = _AnotherButton(onPressed: widget.controller.fetch);
        // Stacking the button under the square in landscape leaves the
        // square only what's left of the height, so put them side by side.
        final sideBySide =
            MediaQuery.orientationOf(context) == Orientation.landscape;
        return Scaffold(
          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
          body: SafeArea(
            child: sideBySide
                ? Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Flexible(child: square),
                        const SizedBox(width: 32),
                        button,
                      ],
                    ),
                  )
                : Column(
                    children: [
                      Expanded(
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.all(32),
                            child: square,
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 32),
                        child: button,
                      ),
                    ],
                  ),
          ),
        );
      },
    );
  }
}

class _Square extends StatelessWidget {
  const _Square({required this.child});

  static const double maxSize = 560;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: maxSize, maxHeight: maxSize),
      child: AspectRatio(
        aspectRatio: 1,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(24),
          ),
          child: child,
        ),
      ),
    );
  }
}

class _AnotherButton extends StatelessWidget {
  const _AnotherButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      // Always live: the controller ignores re-entrant calls, and disabling
      // would flash the button grey on each tap.
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 52),
        padding: const EdgeInsets.symmetric(horizontal: 32),
        textStyle: Theme.of(context).textTheme.titleMedium,
      ),
      child: const Text(
        'Another',
        semanticsLabel: 'Load another random image',
      ),
    );
  }
}

class _ImageSquare extends StatelessWidget {
  const _ImageSquare({
    required this.state,
    required this.cacheManager,
    required this.onRetry,
    required this.onImageFailed,
  });

  final RandomImageState state;
  final BaseCacheManager? cacheManager;
  final VoidCallback onRetry;

  /// Reports a failed image load. Returns true when the square should keep
  /// showing a loading state because a replacement is on its way.
  final bool Function(String url) onImageFailed;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final fadeDuration =
        reduceMotion ? Duration.zero : const Duration(milliseconds: 400);
    return AnimatedSwitcher(
      duration: reduceMotion ? Duration.zero : const Duration(milliseconds: 250),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      // The default layout builder loosens constraints, letting the image
      // take its natural aspect ratio; expand children to keep the square.
      layoutBuilder: (currentChild, previousChildren) => Stack(
        fit: StackFit.expand,
        children: [...previousChildren, ?currentChild],
      ),
      child: switch (state) {
        RandomImageLoading() => const _Spinner(),
        RandomImageError(:final message) => _ErrorPanel(
            message: message,
            actionLabel: 'Try again',
            onAction: onRetry,
          ),
        RandomImageLoaded(:final url) => Semantics(
            key: ValueKey(url),
            image: true,
            label: 'Random photo from Unsplash',
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: CachedNetworkImage(
                imageUrl: url,
                cacheManager: cacheManager,
                fit: BoxFit.cover,
                fadeInDuration: fadeDuration,
                fadeOutDuration: fadeDuration,
                progressIndicatorBuilder: (context, _, progress) => Center(
                  child: CircularProgressIndicator(
                    value: progress.progress,
                    semanticsLabel: 'Downloading image',
                  ),
                ),
                errorWidget: (context, _, _) => onImageFailed(url)
                    ? const _Spinner()
                    : _ErrorPanel(
                        message: "This image couldn't be loaded",
                        // Retrying a dead URL is pointless; offer a fresh one.
                        actionLabel: 'Try another',
                        onAction: onRetry,
                      ),
              ),
            ),
          ),
      },
    );
  }
}

class _Spinner extends StatelessWidget {
  const _Spinner();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: CircularProgressIndicator(semanticsLabel: 'Loading a new image'),
    );
  }
}

class _ErrorPanel extends StatelessWidget {
  const _ErrorPanel({
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      liveRegion: true,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Scrolls rather than overflows the fixed square when space is
          // tight (landscape, large font scales); the action button stays
          // outside the scroll area so it's always visible.
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.broken_image_outlined,
                    size: 48,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyLarge,
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 12),
            child: TextButton(
              onPressed: onAction,
              child: Text(actionLabel),
            ),
          ),
        ],
      ),
    );
  }
}
