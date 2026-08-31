import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:material_color_utilities/material_color_utilities.dart';

/// Extracts a Material 3 seed color from [provider].
///
/// Runs the same quantize-and-score pipeline as
/// [ColorScheme.fromImageProvider], with three differences: it returns the
/// seed itself, so the light and dark schemes can both be derived from a
/// single image decode instead of one per brightness; it quantizes in a
/// helper isolate so the work can't drop frames while the image fades in;
/// and it quantizes true ARGB values rather than raw byte words, which can
/// pick a different winner between closely scored colors (Lab-space
/// clustering isn't invariant under the red/blue swap – this ordering is
/// the color-correct one). Pass a provider that decodes at thumbnail size;
/// oversized inputs are sampled down before quantization.
Future<Color> seedColorFromImageProvider(ImageProvider provider) async {
  final ui.Image image = await _resolveImage(provider);
  final Uint8List rgba;
  try {
    final byteData = await image.toByteData();
    if (byteData == null) {
      throw StateError('Could not read image bytes');
    }
    rgba = byteData.buffer.asUint8List();
  } finally {
    image.dispose();
  }
  return Color(await Isolate.run(() => _scoreSeed(rgba)));
}

/// Sampling cap: quantization needs no more than a ~128px thumbnail's worth
/// of pixels. The provider is asked for a thumbnail, but the cache package
/// silently skips resizing for image formats it can't re-encode, so the
/// input size can't be trusted.
const int _maxSeedPixels = 128 * 128;

/// Raw RGBA bytes in, the top-scoring ARGB color out. Pure Dart, so it can
/// run in a helper isolate.
Future<int> _scoreSeed(Uint8List rgba) async {
  final totalPixels = rgba.length ~/ 4;
  final sampleEvery = (totalPixels / _maxSeedPixels).ceil();
  final stride = 4 * (sampleEvery < 1 ? 1 : sampleEvery);
  final pixels = <int>[
    for (var i = 0; i + 3 < rgba.length; i += stride)
      (rgba[i + 3] << 24) | (rgba[i] << 16) | (rgba[i + 1] << 8) | rgba[i + 2],
  ];
  final quantized = await QuantizerCelebi().quantize(pixels, 128);
  return Score.score(quantized.colorToCount).first;
}

/// How long the image may take to arrive before extraction gives up – the
/// same defence [ColorScheme.fromImageProvider] applies, so a stalled
/// download can't strand the extraction (and a slot in the shared cache
/// manager) forever.
const Duration _loadTimeout = Duration(seconds: 10);

Future<ui.Image> _resolveImage(ImageProvider provider) {
  final completer = Completer<ui.Image>();
  final stream = provider.resolve(ImageConfiguration.empty);
  late final ImageStreamListener listener;
  listener = ImageStreamListener(
    (ImageInfo info, _) {
      stream.removeListener(listener);
      if (!completer.isCompleted) completer.complete(info.image.clone());
      info.dispose();
    },
    onError: (Object error, StackTrace? stackTrace) {
      stream.removeListener(listener);
      if (!completer.isCompleted) {
        completer.completeError(error, stackTrace ?? StackTrace.current);
      }
    },
  );
  stream.addListener(listener);
  return completer.future.timeout(
    _loadTimeout,
    onTimeout: () {
      // Removing the listener means a late arrival can't leak a cloned image.
      stream.removeListener(listener);
      throw TimeoutException('Image did not arrive within $_loadTimeout');
    },
  );
}
