import 'dart:async';
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

  /// Last URL whose first frame actually rendered – de-dups screen-reader
  /// announcements.
  String? _shownUrl;

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
    if (state is RandomImageLoaded) {
      _announceWhenShown(state.url, fromHistory: state.fromHistory);
    }
  }

  /// Watches the current image for its first decoded frame, then announces
  /// it to screen readers and hands the frame to [HomeScreen.onImageShown]
  /// for theming – reacting to the render rather than the URL, since the
  /// download takes a moment and a few URLs are dead. The error panel is a
  /// live region and announces itself.
  ///
  /// Resolving the same provider as the image widget shares its cache entry,
  /// so this costs no extra download or decode.
  void _announceWhenShown(String url, {required bool fromHistory}) {
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
      // The duplicate re-roll can keep the same URL; don't claim novelty.
      final isRepeat = url == _shownUrl;
      _shownUrl = url;
      SemanticsService.sendAnnouncement(
        View.of(context),
        fromHistory
            ? 'Previous image shown'
            : isRepeat
            ? 'Same image shown again'
            : 'New image loaded',
        Directionality.of(context),
      );
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
        final colorScheme = Theme.of(context).colorScheme;
        final reduceMotion = MediaQuery.disableAnimationsOf(context);
        return AnnotatedRegion<SystemUiOverlayStyle>(
          // The photo runs edge to edge behind both bars; the scrims keep
          // the bar icons legible over arbitrary pixels, so the icons are
          // always light – no per-theme switching.
          value: const SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: Brightness.light,
            statusBarBrightness: Brightness.dark,
            systemNavigationBarColor: Colors.transparent,
            systemNavigationBarIconBrightness: Brightness.light,
            systemNavigationBarContrastEnforced: false,
          ),
          child: Scaffold(
            backgroundColor: colorScheme.primaryContainer,
            body: Stack(
              fit: StackFit.expand,
              children: [
                // The image-seeded scheme gradient: the backdrop while
                // loading and on error; the theme lerp in main.dart
                // animates it between images.
                DecoratedBox(
                  decoration: BoxDecoration(
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
                ),
                _ImageContent(
                  state: widget.controller.state,
                  cacheManager: widget.cacheManager,
                  onRetry: widget.controller.fetch,
                  onImageFailed: widget.controller.imageFailed,
                ),
                const _EdgeScrims(),
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Appears once there is a previous image to restore
                        // and fades away at the start of history – its
                        // absence is the only depth indicator this needs.
                        AnimatedSwitcher(
                          duration: reduceMotion
                              ? Duration.zero
                              : const Duration(milliseconds: 200),
                          child: widget.controller.canGoBack
                              ? IconButton(
                                  onPressed: widget.controller.goBack,
                                  icon: const Icon(Icons.undo),
                                  color: Colors.white,
                                  iconSize: 28,
                                  tooltip: 'Show the previous image',
                                )
                              : const SizedBox.shrink(),
                        ),
                        const Spacer(),
                        IconButton(
                          // Always live: the controller ignores re-entrant
                          // calls, and disabling would flash the icon grey on
                          // each tap.
                          onPressed: widget.controller.fetch,
                          icon: const Icon(Icons.shuffle),
                          color: Colors.white,
                          iconSize: 28,
                          tooltip: 'Load another random image',
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Darkened gradients over the top and bottom edges: the status bar icons
/// and the refresh action sit on the top one, the gesture handle on the
/// bottom one, so all stay legible over arbitrary photo pixels. Always
/// painted – also over the loading and error backdrop – so the bar icons
/// never have to switch brightness. Purely decorative: ignores pointers.
class _EdgeScrims extends StatelessWidget {
  const _EdgeScrims();

  @override
  Widget build(BuildContext context) {
    final insets = MediaQuery.paddingOf(context);
    return IgnorePointer(
      child: Column(
        children: [
          Container(
            height: insets.top + 88,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.black54, Colors.transparent],
              ),
            ),
          ),
          const Spacer(),
          Container(
            height: insets.bottom + 12,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [Colors.black38, Colors.transparent],
              ),
            ),
          ),
        ],
      ),
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

  /// Reports a failed image load. Returns true when the screen should keep
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
      // take its natural aspect ratio; expand children to fill the screen.
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
        RandomImageLoaded(:final url) => CachedNetworkImage(
          // The key drives the AnimatedSwitcher transition between URLs.
          key: ValueKey(url),
          imageUrl: url,
          cacheManager: cacheManager,
          fadeInDuration: fadeDuration,
          fadeOutDuration: fadeDuration,
          // Only the loaded picture is an image to assistive tech; the
          // progress and failure states describe themselves.
          imageBuilder: (context, imageProvider) => Stack(
            fit: StackFit.expand,
            children: [
              // The letterbox filler: the same photo cover-cropped and
              // blurred, so the bars around the contained photo are its own
              // colors – no download or decode beyond the sharp copy's.
              // Decorative only; the sharp copy below carries the semantics.
              ImageFiltered(
                imageFilter: ui.ImageFilter.blur(
                  sigmaX: 32,
                  sigmaY: 32,
                  tileMode: ui.TileMode.clamp,
                ),
                child: Image(
                  image: imageProvider,
                  fit: BoxFit.cover,
                  excludeFromSemantics: true,
                ),
              ),
              // The photo itself, whole – contain never crops.
              Image(
                image: imageProvider,
                fit: BoxFit.contain,
                semanticLabel: 'Random photo from Unsplash',
              ),
            ],
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
        // Scrolls rather than overflows when space is tight (landscape,
        // large font scales); the action button stays outside the scroll
        // area so it's always visible.
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
