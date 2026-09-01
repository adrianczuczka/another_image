import 'dart:async';

import 'package:flutter/foundation.dart';

import '../api/image_api.dart';

sealed class RandomImageState {
  const RandomImageState();
}

class RandomImageLoading extends RandomImageState {
  const RandomImageLoading();
}

class RandomImageLoaded extends RandomImageState {
  const RandomImageLoaded(this.url, {this.fromHistory = false});

  final String url;

  /// True when this image was restored by [RandomImageController.goBack]
  /// rather than freshly fetched – the UI announces it differently.
  final bool fromHistory;
}

class RandomImageError extends RandomImageState {
  const RandomImageError(this.cause, {this.statusCode});

  /// What went wrong, or null for an unexpected (non-API) failure.
  final ImageApiFailure? cause;

  /// The HTTP status, for [ImageApiFailure.serverError].
  final int? statusCode;
}

/// Owns the fetch lifecycle for the single screen.
class RandomImageController extends ChangeNotifier {
  RandomImageController(this._api);

  /// The API serves a small rotating pool of URLs, so back-to-back duplicates
  /// are common; without a re-roll, tapping "Another" often looks like a
  /// no-op.
  static const int maxDuplicateRetries = 2;

  final ImageApi _api;

  RandomImageState _state = const RandomImageLoading();
  RandomImageState get state => _state;

  /// True from a fetch's start until its result lands. While an image is
  /// already on screen the fetch doesn't disturb [state], so this is the
  /// only signal that work is in progress – the UI shows it on the shuffle
  /// button.
  bool get isFetching => _fetching;

  /// Upper bound on remembered URLs – about principle rather than memory;
  /// nobody steps back a hundred times.
  static const int maxHistoryLength = 100;

  /// Previously shown URLs, oldest first. Session-only by design.
  final List<String> _history = [];

  /// Whether [goBack] has a previous image to restore.
  bool get canGoBack => _history.isNotEmpty;

  String? _currentUrl;
  bool _fetching = false;
  bool _disposed = false;

  /// Whether the next image-load failure may be answered by silently
  /// fetching a replacement. Granted once per user-initiated [fetch].
  bool _replacementAvailable = false;

  /// The URL whose failed load has a replacement fetch pending or in flight.
  String? _replacingUrl;

  /// Fetches a new image URL on the user's behalf.
  Future<void> fetch() {
    _replacementAvailable = true;
    _replacingUrl = null;
    final state = _state;
    // Remember what's being shuffled away so [goBack] can restore it. Only
    // user-initiated fetches push, and only once per in-flight fetch – the
    // photo stays up during a fetch, so a re-entrant tap sees the same
    // Loaded state again. A dead image's replacement fetch must not
    // enshrine the broken URL in history.
    if (!_fetching && state is RandomImageLoaded) _pushHistory(state.url);
    return _fetch();
  }

  /// Restores the most recently shuffled-away image. No network involved:
  /// the URL is normally still in the image cache. Ignored while a fetch is
  /// in flight, like a re-entrant [fetch].
  void goBack() {
    if (_fetching || _history.isEmpty) return;
    // A back tap is as user-initiated as a fetch, so it refreshes the same
    // one-replacement grant; [imageFailed] steps further back while more
    // history remains, and the grant covers the final fallback.
    _replacementAvailable = true;
    _replacingUrl = null;
    final url = _history.removeLast();
    _currentUrl = url;
    _state = RandomImageLoaded(url, fromHistory: true);
    _notify();
  }

  void _pushHistory(String url) {
    if (_history.length == maxHistoryLength) _history.removeAt(0);
    _history.add(url);
  }

  /// The deferred half of [imageFailed]'s history path.
  void _goBackFurther() {
    _replacingUrl = null;
    if (_disposed || _fetching || _history.isEmpty) return;
    final url = _history.removeLast();
    _currentUrl = url;
    _state = RandomImageLoaded(url, fromHistory: true);
    _notify();
  }

  /// Reports that the image at [url] could not be loaded.
  ///
  /// A few of the API's URLs are dead, so the first failure after each
  /// [fetch] is answered by fetching a replacement instead of bothering the
  /// user. Returns true when the caller should keep its current display
  /// – a replacement is on its way, or the failure belongs to an image that
  /// is no longer current – and false when the failure should be shown.
  /// Idempotent and safe to call during build: the replacement fetch is
  /// scheduled, not started synchronously.
  bool imageFailed(String url) {
    // While a fetch is in flight a new state is already on its way; the
    // kept Loaded state still names the outgoing image, so without this
    // guard its failure could consume the grant or start a second fetch.
    if (_fetching) return true;
    final state = _state;
    // Only the image currently on screen may react. A late failure from a
    // widget on its way out – the state has already moved to an error or a
    // new image – must neither consume the grant nor touch the state.
    if (state is! RandomImageLoaded || state.url != url) return true;
    // Covers the window between consuming the grant and the scheduled
    // microtask starting the fetch.
    if (url == _replacingUrl) return true;
    // A restored image that fails (cache evicted and the URL since dead)
    // steps further back instead of fetching a random stranger – the user
    // asked for a specific previous photo, not a new one.
    if (state.fromHistory && _history.isNotEmpty) {
      _replacingUrl = url;
      scheduleMicrotask(_goBackFurther);
      return true;
    }
    if (!_replacementAvailable) return false;
    _replacementAvailable = false;
    _replacingUrl = url;
    scheduleMicrotask(_fetch);
    return true;
  }

  Future<void> _fetch() async {
    if (_fetching || _disposed) return;
    _fetching = true;
    // Keep the current photo on screen while the next one is fetched: a
    // full-screen spinner between photos flashes on fast networks and
    // blanks the screen on slow ones. Only cold start and error recovery,
    // where there is no photo worth keeping, show the loading state.
    if (_state is! RandomImageLoaded) _state = const RandomImageLoading();
    _notify();
    try {
      var url = await _api.fetchRandomImageUrl();
      for (
        var attempt = 0;
        url == _currentUrl && attempt < maxDuplicateRetries;
        attempt++
      ) {
        try {
          url = await _api.fetchRandomImageUrl();
        } on ImageApiException {
          break; // The duplicate in hand is still displayable.
        }
      }
      _currentUrl = url;
      _state = RandomImageLoaded(url);
    } on ImageApiException catch (e) {
      _state = RandomImageError(e.failure, statusCode: e.statusCode);
    } catch (error, stack) {
      // Not an API problem but a bug: set the state first (a throwing
      // FlutterError.onError must not leave stale UI), then report it where
      // developers and crash reporters see it.
      _state = const RandomImageError(null);
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'another_image',
          context: ErrorDescription('while fetching a random image'),
        ),
      );
    } finally {
      // Runs even if error reporting itself throws: a wedged _fetching flag
      // would disable the app for good.
      _replacingUrl = null;
      _fetching = false;
      _notify();
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
