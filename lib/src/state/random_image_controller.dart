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

  Future<void> fetch() async {
    _state = const RandomImageLoading();
    notifyListeners();
    try {
      var url = await _api.fetchRandomImageUrl();
      for (var attempt = 0;
          url == _currentUrl && attempt < maxDuplicateRetries;
          attempt++) {
        url = await _api.fetchRandomImageUrl();
      }
      _currentUrl = url;
      _state = RandomImageLoaded(url);
    } on ImageApiException catch (e) {
      _state = RandomImageError(e.message);
    }
    notifyListeners();
  }
}
