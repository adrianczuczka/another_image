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

  /// Last URL whose first frame actually rendered – the photo currently on
  /// screen, or null when a spinner or panel shows instead. While the
  /// controller's URL differs from this, the old photo is held on screen
  /// and the new one decodes off screen ([_watchImage] swaps them). Also
  /// de-dups screen-reader announcements.
  String? _shownUrl;

  /// URL that failed to load with no replacement left; the screen shows
  /// the failure panel while the controller still reports it.
  String? _failedUrl;

  /// The state already reacted to. A notify can report the same object
  /// (fetch bookkeeping around a kept state); re-watching the image then
  /// would re-announce it to screen readers and drop a pending watch.
  RandomImageState? _lastState;

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
    final state = widget.controller.state;
    if (identical(state, _lastState)) return;
    _lastState = state;
    _stopWaitingForImage();
    if (state is RandomImageLoaded) {
      if (_failedUrl != null && _failedUrl != state.url) {
        // The failure belonged to an earlier URL; this one starts clean.
        setState(() => _failedUrl = null);
      }
      _watchImage(state.url, fromHistory: state.fromHistory);
    } else if (_shownUrl != null || _failedUrl != null) {
      // The spinner or error panel replaces the photo, so the next load
      // has nothing on screen to hold on to.
      setState(() {
        _shownUrl = null;
        _failedUrl = null;
      });
    }
  }

  /// Watches [url] for its first decoded frame – the moment it can actually
  /// paint. Until then the previous photo stays on screen; on the frame the
  /// display swaps to [url], the frame seeds the theme via
  /// [HomeScreen.onImageShown], and screen readers hear about the change.
  /// A load failure goes to [RandomImageController.imageFailed], which
  /// either fetches a silent replacement or declines, moving the screen to
  /// the failure panel – a live region that announces itself.
  ///
  /// Resolving the same provider as the image widget shares its cache entry,
  /// so this costs no extra download or decode.
  void _watchImage(String url, {required bool fromHistory}) {
    final stream = CachedNetworkImageProvider(
      url,
      cacheManager: widget.cacheManager,
    ).resolve(ImageConfiguration.empty);
    late final ImageStreamListener listener;
    listener = ImageStreamListener(
      (ImageInfo info, _) {
        widget.onImageShown(url, info.image.clone());
        info.dispose();
        _stopWaitingForImage();
        if (!mounted) return;
        // The duplicate re-roll can keep the same URL; don't claim novelty.
        final isRepeat = url == _shownUrl;
        setState(() => _shownUrl = url); // Releases any held previous photo.
        SemanticsService.sendAnnouncement(
          View.of(context),
          fromHistory
              ? 'Previous image shown'
              : isRepeat
              ? 'Same image shown again'
              : 'New image loaded',
          Directionality.of(context),
        );
      },
      onError: (_, _) {
        _stopWaitingForImage();
        if (!mounted) return;
        // True means a replacement is coming (or the failure is stale) and a
        // new state will arrive; false means this URL is the end of the line.
        if (!widget.controller.imageFailed(url)) {
          setState(() {
            _failedUrl = url;
            _shownUrl = null;
          });
        }
      },
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
        final state = widget.controller.state;
        // While a fresh URL decodes off screen, keep the rendered photo up;
        // the crossfade to the new one runs only once it can paint.
        final holdingPhoto =
            state is RandomImageLoaded &&
            _shownUrl != null &&
            state.url != _shownUrl &&
            state.url != _failedUrl;
        // With the photo staying up, the shuffle button is the only place
        // fetch-and-decode progress can show.
        final busy =
            state is RandomImageLoaded &&
            (widget.controller.isFetching || holdingPhoto);
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
                  state: holdingPhoto ? RandomImageLoaded(_shownUrl!) : state,
                  failedUrl: _failedUrl,
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
                          transitionBuilder: _unkeyedFade,
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
                          icon: _ShuffleIcon(busy: busy),
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

/// An unkeyed fade for [AnimatedSwitcher.transitionBuilder]. The default
/// builder keys each fade by the child's key, so two in-flight children
/// with equal keys – both null, or the same child re-entering within one
/// fade – collide with "Duplicate keys found". Unkeyed, the switcher falls
/// back to its unique per-entry key.
Widget _unkeyedFade(Widget child, Animation<double> animation) =>
    FadeTransition(opacity: animation, child: child);

class _ImageContent extends StatelessWidget {
  const _ImageContent({
    required this.state,
    required this.failedUrl,
    required this.cacheManager,
    required this.onRetry,
    required this.onImageFailed,
  });

  final RandomImageState state;

  /// URL whose load failed with no replacement left – rendered as the
  /// failure panel instead of yet another load attempt.
  final String? failedUrl;

  final BaseCacheManager? cacheManager;
  final VoidCallback onRetry;

  /// Reports a failed image load. Returns true when the screen should keep
  /// its current display because a replacement is on its way.
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
      transitionBuilder: _unkeyedFade,
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
        // A URL that failed for good while the previous photo was still up;
        // the errorWidget below covers the same failure when the dead image
        // itself was the one being displayed.
        RandomImageLoaded(:final url) when url == failedUrl => _ErrorPanel(
          message: "This image couldn't be loaded",
          actionLabel: 'Try another',
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

/// The shuffle glyph, swapping to a small spinner once [busy] has lasted
/// past a short delay. Fast loads finish with the photo crossfade as their
/// only feedback; slow ones show that the tap is being worked on. The
/// full-screen spinner can't serve here – the photo deliberately stays up
/// while the next one loads.
class _ShuffleIcon extends StatefulWidget {
  const _ShuffleIcon({required this.busy});

  /// Whether a new image is being fetched or decoded right now.
  final bool busy;

  @override
  State<_ShuffleIcon> createState() => _ShuffleIconState();
}

class _ShuffleIconState extends State<_ShuffleIcon> {
  /// How long a load must run before the spinner appears; anything faster
  /// stays chrome-free.
  static const Duration revealDelay = Duration(milliseconds: 400);

  Timer? _revealTimer;
  bool _showSpinner = false;

  @override
  void initState() {
    super.initState();
    if (widget.busy) _armTimer();
  }

  @override
  void didUpdateWidget(_ShuffleIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.busy == oldWidget.busy) return;
    _revealTimer?.cancel();
    _revealTimer = null;
    if (widget.busy) {
      _armTimer();
    } else if (_showSpinner) {
      setState(() => _showSpinner = false);
    }
  }

  void _armTimer() {
    _revealTimer = Timer(revealDelay, () {
      setState(() => _showSpinner = true);
    });
  }

  @override
  void dispose() {
    _revealTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return AnimatedSwitcher(
      duration: reduceMotion
          ? Duration.zero
          : const Duration(milliseconds: 150),
      transitionBuilder: _unkeyedFade,
      child: _showSpinner
          ? const SizedBox.square(
              dimension: 24,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                color: Colors.white,
                semanticsLabel: 'Loading a new image',
              ),
            )
          : const Icon(Icons.shuffle),
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
