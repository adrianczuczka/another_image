import 'dart:ui' show Color;

import 'package:flutter/foundation.dart';

import 'random_image_controller.dart';

/// Extracts a seed color from a loaded image, used to derive the app's
/// light and dark themes. Injectable so tests can avoid real image decoding.
typedef SeedExtractor = Future<Color> Function(String url);

/// The theme seed: the color extracted from the most recently loaded image,
/// or [fallback] until the first extraction succeeds.
class ThemeSeedController extends ChangeNotifier {
  ThemeSeedController(
    this._images,
    this._extract, {
    Color fallback = defaultFallback,
  }) : _seed = fallback {
    _images.addListener(_onImageChanged);
  }

  /// Indigo, shown before the first image and if none ever decodes.
  static const Color defaultFallback = Color(0xFF5C6BC0);

  final RandomImageController _images;
  final SeedExtractor _extract;

  Color _seed;
  Color get seed => _seed;

  int _extractionSeq = 0;
  bool _disposed = false;

  void _onImageChanged() {
    final state = _images.state;
    if (state is RandomImageLoaded) _updateSeed(state.url);
  }

  Future<void> _updateSeed(String url) async {
    // Extractions can finish out of order; only the latest may win.
    final seq = ++_extractionSeq;
    final Color seed;
    try {
      seed = await _extract(url);
    } catch (_) {
      // Decoding failures surface as Exceptions and Errors alike (a dead URL
      // in the API's pool is the common case). The image widget shows its
      // own error; keep the previous seed rather than adding a second one.
      return;
    }
    if (_disposed || seq != _extractionSeq) return;
    _seed = seed;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _images.removeListener(_onImageChanged);
    super.dispose();
  }
}
