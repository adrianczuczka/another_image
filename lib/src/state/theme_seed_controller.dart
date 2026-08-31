import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// Extracts a seed color from a rendered frame, used to derive the app's
/// light and dark themes. Injectable so tests can avoid real quantization.
typedef SeedExtractor = Future<Color> Function(ui.Image image);

/// The theme seed: the color extracted from the most recently rendered
/// image, or [fallback] until the first extraction succeeds.
///
/// Fed by the UI reporting each image as it actually renders, so the theme
/// derives from what is on screen by construction: there is no second image
/// resolution to race, no separate timeout policy to desync, and nothing to
/// clean up when a download stalls or dies – extraction simply never
/// starts.
class ThemeSeedController extends ChangeNotifier {
  ThemeSeedController(this._extract, {Color fallback = defaultFallback})
    : _seed = fallback;

  /// Indigo, shown before the first image and if none ever renders.
  static const Color defaultFallback = Color(0xFF5C6BC0);

  final SeedExtractor _extract;

  Color _seed;
  Color get seed => _seed;

  /// The URL whose seed the current [seed] came from.
  String? _lastSeedUrl;

  int _extractionSeq = 0;
  bool _disposed = false;

  /// Reports that the image at [url] has rendered. Takes ownership of
  /// [image] – a clone of the rendered frame – and disposes it.
  ///
  /// A repeat report for the URL the current seed came from is skipped: the
  /// duplicate re-roll can legitimately re-show the same image, and
  /// re-extracting an identical seed would rebuild the themes for nothing.
  /// A URL whose extraction failed is retried when it renders again.
  void imageShown(String url, ui.Image image) {
    if (_disposed || url == _lastSeedUrl) {
      image.dispose();
      return;
    }
    _updateSeed(url, image);
  }

  Future<void> _updateSeed(String url, ui.Image image) async {
    // Extractions can finish out of order; only the latest may win.
    final seq = ++_extractionSeq;
    final Color seed;
    try {
      seed = await _extract(image);
    } on Exception {
      // Expected: an unreadable frame surfaces as an Exception. The picture
      // itself is already on screen; keep the previous seed.
      return;
    } catch (error, stack) {
      // Anything else is a bug, not a load failure: report it and keep the
      // current theme.
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'another_image',
          context: ErrorDescription('while extracting a theme seed'),
        ),
      );
      return;
    } finally {
      image.dispose();
    }
    if (_disposed || seq != _extractionSeq) return;
    _lastSeedUrl = url;
    if (seed == _seed) return;
    _seed = seed;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
