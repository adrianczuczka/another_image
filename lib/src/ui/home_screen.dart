import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../state/random_image_controller.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.controller});

  final RandomImageController controller;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_announceState);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_announceState);
    super.dispose();
  }

  void _announceState() {
    // The error panel is a live region and announces itself; loaded images
    // need an explicit announcement for screen reader users.
    if (mounted && widget.controller.state is RandomImageLoaded) {
      SemanticsService.sendAnnouncement(
        View.of(context),
        'New image loaded',
        TextDirection.ltr,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final square = _Square(
          child: _ImageSquare(
            state: widget.controller.state,
            onRetry: widget.controller.fetch,
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

/// The image area: always square, capped on large screens so it doesn't
/// dwarf the button, with a persistent surface so its footprint is stable
/// across loading, image, and error states.
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
  const _ImageSquare({required this.state, required this.onRetry});

  final RandomImageState state;
  final VoidCallback onRetry;

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
        RandomImageLoading() => const Center(
            child: CircularProgressIndicator(
              semanticsLabel: 'Loading a new image',
            ),
          ),
        RandomImageError(:final message) =>
          _ErrorPanel(message: message, onRetry: onRetry),
        RandomImageLoaded(:final url) => Semantics(
            key: ValueKey(url),
            image: true,
            label: 'Random photo from Unsplash',
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: CachedNetworkImage(
                imageUrl: url,
                fit: BoxFit.cover,
                fadeInDuration: fadeDuration,
                fadeOutDuration: fadeDuration,
                progressIndicatorBuilder: (context, _, progress) => Center(
                  child: CircularProgressIndicator(
                    value: progress.progress,
                    semanticsLabel: 'Downloading image',
                  ),
                ),
                errorWidget: (context, _, error) => _ErrorPanel(
                  message: "This image couldn't be loaded",
                  onRetry: onRetry,
                ),
              ),
            ),
          ),
      },
    );
  }
}

class _ErrorPanel extends StatelessWidget {
  const _ErrorPanel({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      liveRegion: true,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Scrolls rather than overflows the fixed square when space is
          // tight (landscape, large font scales); the retry button stays
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
              onPressed: onRetry,
              child: const Text('Try again'),
            ),
          ),
        ],
      ),
    );
  }
}
