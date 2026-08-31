import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

import '../api/image_api.dart';
import '../state/random_image_controller.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.controller,
    required this.onImageShown,
    this.cacheManager,
  });

  final RandomImageController controller;

  /// Called with each image as it renders, with a clone of the rendered
  /// frame; the receiver takes ownership of the clone. Drives the theme,
  /// which must follow what is on screen rather than what was fetched.
  final void Function(String url, ui.Image image) onImageShown;

  /// Backs the image widget; null uses the shared disk cache. Injectable so
  /// tests can serve or fail images deterministically.
  final BaseCacheManager? cacheManager;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  ImageStream? _pendingImage;
  ImageStreamListener? _pendingImageListener;
  String? _lastShownUrl;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onStateChanged);
    // Catch up with an image that loaded before this screen mounted –
    // deferred, because the announcement path reads inherited widgets,
    // which initState must not do synchronously.
    scheduleMicrotask(() {
      if (mounted) _onStateChanged();
    });
  }

  @override
  void didUpdateWidget(HomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onStateChanged);
      widget.controller.addListener(_onStateChanged);
      _onStateChanged();
    }
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

  /// Watches the current image for its first decoded frame, then announces
  /// it to screen readers and hands the frame to [HomeScreen.onImageShown]
  /// for theming – reacting to the render rather than the URL, since the
  /// download takes a moment and a few URLs are dead. The error panel is a
  /// live region and announces itself.
  ///
  /// Resolving the same provider as the image widget shares its cache entry,
  /// so this costs no extra download or decode.
  void _announceWhenShown(String url) {
    final stream = CachedNetworkImageProvider(
      url,
      cacheManager: widget.cacheManager,
    ).resolve(ImageConfiguration.empty);
    late final ImageStreamListener listener;
    listener = ImageStreamListener((ImageInfo info, _) {
      widget.onImageShown(url, info.image.clone());
      info.dispose();
      _stopWaitingForImage();
      if (!mounted) return;
      SemanticsService.sendAnnouncement(
        View.of(context),
        // The duplicate re-roll can keep the same URL; don't claim novelty.
        url == _lastShownUrl ? 'Same image shown again' : 'New image loaded',
        Directionality.of(context),
      );
      _lastShownUrl = url;
    }, onError: (_, _) => _stopWaitingForImage());
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
        final frame = _ImageFrame(
          child: _ImageContent(
            state: widget.controller.state,
            cacheManager: widget.cacheManager,
            onRetry: widget.controller.fetch,
            onImageFailed: widget.controller.imageFailed,
          ),
        );
        final button = _AnotherButton(onPressed: widget.controller.fetch);
        // Stacking the button under the frame in landscape leaves the
        // frame only what's left of the height, so put them side by side.
        final sideBySide =
            MediaQuery.orientationOf(context) == Orientation.landscape;
        final colorScheme = Theme.of(context).colorScheme;
        // The bar icons sit over the gradient's corners, so contrast against
        // those corner colors – which the seeded scheme picks, not the
        // theme's overall brightness (the high-contrast variants shift the
        // container tones).
        final topBrightness = ThemeData.estimateBrightnessForColor(
          colorScheme.primaryContainer,
        );
        final bottomBrightness = ThemeData.estimateBrightnessForColor(
          colorScheme.tertiaryContainer,
        );
        return AnnotatedRegion<SystemUiOverlayStyle>(
          // There's no AppBar to do this: keep the system bars transparent so
          // the gradient runs edge to edge, with icons that contrast with
          // the gradient corner behind them.
          value: SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: topBrightness == Brightness.light
                ? Brightness.dark
                : Brightness.light,
            statusBarBrightness: topBrightness,
            systemNavigationBarColor: Colors.transparent,
            systemNavigationBarIconBrightness:
                bottomBrightness == Brightness.light
                ? Brightness.dark
                : Brightness.light,
            systemNavigationBarContrastEnforced: false,
          ),
          child: Scaffold(
            backgroundColor: colorScheme.primaryContainer,
            body: SizedBox.expand(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  // All three stops come from the image-seeded scheme, so
                  // the wash follows each photo; the theme lerp in main.dart
                  // animates it between images. Same recipe in both themes –
                  // the tokens carry the light/dark tone shift.
                  gradient: LinearGradient(
                    begin: AlignmentDirectional.topStart,
                    end: AlignmentDirectional.bottomEnd,
                    stops: const [0, 0.45, 1],
                    colors: [
                      colorScheme.primaryContainer,
                      colorScheme.secondaryContainer,
                      colorScheme.tertiaryContainer,
                    ],
                  ),
                ),
                child: SafeArea(
                  child: sideBySide
                      ? Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Flexible(child: frame),
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
                                  padding: const EdgeInsets.all(24),
                                  child: frame,
                                ),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.only(bottom: 24),
                              child: button,
                            ),
                          ],
                        ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The image's frame: fills as much of the available space as its aspect
/// bounds allow. Portrait stretches from square up to 4:5 (w:h); landscape
/// is a fixed 4:3. The caps – 560×700 and 720×540 – are those aspects at
/// tablet size. The aspect is fixed per orientation, never per photo, so
/// the frame can't jump between images and the loading and error states
/// keep the same geometry.
class _ImageFrame extends StatelessWidget {
  const _ImageFrame({required this.child});

  static const double maxPortraitWidth = 560;
  static const double maxPortraitHeight = 700;
  static const double maxLandscapeHeight = 540;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final landscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = landscape
            ? _landscapeSize(constraints)
            : _portraitSize(constraints);
        return SizedBox.fromSize(
          // The frame's size is computed rather than declared through a
          // layout widget; the key gives widget tests something to measure.
          key: const ValueKey('image-frame'),
          size: size,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest.withValues(
                alpha: 0.35,
              ),
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(
                  color: colorScheme.shadow.withValues(
                    alpha: dark ? 0.45 : 0.25,
                  ),
                  blurRadius: 32,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: child,
          ),
        );
      },
    );
  }

  /// As wide as fits, then as tall as the space allows between square and
  /// 4:5 – tight heights (split screen, landscape-ish windows) trade height
  /// away before width.
  static Size _portraitSize(BoxConstraints constraints) {
    var width = math.min(constraints.maxWidth, maxPortraitWidth);
    final height = math.min(
      math.min(constraints.maxHeight, maxPortraitHeight),
      width * 5 / 4,
    );
    if (height < width) width = height; // Never wider than square.
    return Size(width, height);
  }

  /// Fixed 4:3, sized from the height and shrunk when the row is narrow.
  static Size _landscapeSize(BoxConstraints constraints) {
    var height = math.min(constraints.maxHeight, maxLandscapeHeight);
    var width = height * 4 / 3;
    if (width > constraints.maxWidth) {
      width = constraints.maxWidth;
      height = width * 3 / 4;
    }
    return Size(width, height);
  }
}

class _AnotherButton extends StatelessWidget {
  const _AnotherButton({required this.onPressed});

  /// Shortest side from which the button grows to match the larger frame.
  static const double tabletBreakpoint = 600;

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final large = MediaQuery.sizeOf(context).shortestSide >= tabletBreakpoint;
    final textTheme = Theme.of(context).textTheme;
    return FilledButton(
      // Always live: the controller ignores re-entrant calls, and disabling
      // would flash the button grey on each tap.
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        minimumSize: Size(0, large ? 64 : 52),
        padding: EdgeInsets.symmetric(horizontal: large ? 48 : 32),
        textStyle: large ? textTheme.titleLarge : textTheme.titleMedium,
      ),
      child: const Text('Another', semanticsLabel: 'Load another random image'),
    );
  }
}

class _ImageContent extends StatelessWidget {
  const _ImageContent({
    required this.state,
    required this.cacheManager,
    required this.onRetry,
    required this.onImageFailed,
  });

  final RandomImageState state;
  final BaseCacheManager? cacheManager;
  final VoidCallback onRetry;

  /// Reports a failed image load. Returns true when the frame should keep
  /// showing a loading state because a replacement is on its way.
  final bool Function(String url) onImageFailed;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final fadeDuration = reduceMotion
        ? Duration.zero
        : const Duration(milliseconds: 400);
    return AnimatedSwitcher(
      duration: reduceMotion
          ? Duration.zero
          : const Duration(milliseconds: 250),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      // The default layout builder loosens constraints, letting the image
      // take its natural aspect ratio; expand children to fill the frame.
      layoutBuilder: (currentChild, previousChildren) => Stack(
        fit: StackFit.expand,
        children: [...previousChildren, ?currentChild],
      ),
      child: switch (state) {
        RandomImageLoading() => const _Spinner(),
        RandomImageError(:final cause, :final statusCode) => _ErrorPanel(
          message: _fetchErrorCopy(cause, statusCode),
          actionLabel: 'Try again',
          onAction: onRetry,
        ),
        RandomImageLoaded(:final url) => ClipRRect(
          // The key drives the AnimatedSwitcher transition between URLs.
          key: ValueKey(url),
          borderRadius: BorderRadius.circular(28),
          child: CachedNetworkImage(
            imageUrl: url,
            cacheManager: cacheManager,
            fit: BoxFit.cover,
            fadeInDuration: fadeDuration,
            fadeOutDuration: fadeDuration,
            // Only the loaded picture is an image to assistive tech; the
            // progress and failure states describe themselves.
            imageBuilder: (context, imageProvider) => Image(
              image: imageProvider,
              fit: BoxFit.cover,
              semanticLabel: 'Random photo from Unsplash',
            ),
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
      },
    );
  }
}

/// User copy for a failed fetch; the API layer only reports the cause.
String _fetchErrorCopy(
  ImageApiFailure? cause,
  int? statusCode,
) => switch (cause) {
  ImageApiFailure.unreachable =>
    "Couldn't reach the image service. Check your connection and try again.",
  ImageApiFailure.serverError =>
    'The image service had a problem (HTTP $statusCode). Try again.',
  ImageApiFailure.malformed =>
    'The image service sent an unexpected response. Try again.',
  null => 'Something went wrong. Try again.',
};

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
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Scrolls rather than overflows the fixed frame when space is
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
                // The live region sits on the text that owns the label, so
                // assistive tech announces the message when the panel
                // appears or its copy changes.
                Semantics(
                  liveRegion: true,
                  child: Text(
                    message,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyLarge,
                  ),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 12),
          child: TextButton(onPressed: onAction, child: Text(actionLabel)),
        ),
      ],
    );
  }
}
