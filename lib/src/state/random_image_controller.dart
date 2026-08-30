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
  const RandomImageLoaded(this.url);

  final String url;
}

class RandomImageError extends RandomImageState {
  const RandomImageError(this.message);

  final String message;
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
    return _fetch();
  }

  /// Reports that the image at [url] could not be loaded.
  ///
  /// A few of the API's URLs are dead, so the first failure after each
  /// [fetch] is answered by fetching a replacement instead of bothering the
  /// user. Returns true when the caller should keep showing a loading state
  /// – a replacement is on its way, or the failure belongs to an image that
  /// is no longer current – and false when the failure should be shown.
  /// Idempotent and safe to call during build: the replacement fetch is
  /// scheduled, not started synchronously.
  bool imageFailed(String url) {
    if (url != _currentUrl || url == _replacingUrl || _fetching) return true;
    if (!_replacementAvailable) return false;
    _replacementAvailable = false;
    _replacingUrl = url;
    scheduleMicrotask(_fetch);
    return true;
  }

  Future<void> _fetch() async {
    if (_fetching) return;
    _fetching = true;
    _state = const RandomImageLoading();
    _notify();
    try {
      var url = await _api.fetchRandomImageUrl();
      for (var attempt = 0;
          url == _currentUrl && attempt < maxDuplicateRetries;
          attempt++) {
        try {
          url = await _api.fetchRandomImageUrl();
        } on ImageApiException {
          break; // The duplicate in hand is still displayable.
        }
      }
      _currentUrl = url;
      _state = RandomImageLoaded(url);
    } on ImageApiException catch (e) {
      _state = RandomImageError(e.message);
    } catch (_) {
      _state = const RandomImageError('Something went wrong. Try again.');
    }
    _replacingUrl = null;
    _fetching = false;
    _notify();
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
