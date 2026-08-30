import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:material_color_utilities/material_color_utilities.dart';

/// Extracts a Material 3 seed color from [provider].
///
/// Runs the same quantize-and-score pipeline as
/// [ColorScheme.fromImageProvider], with two differences: it returns the seed
/// itself, so the light and dark schemes can both be derived from a single
/// image decode instead of one per brightness, and it quantizes in a helper
/// isolate so the work can't drop frames while the image fades in. Pass a
/// provider that decodes at thumbnail size; quantization doesn't need more
/// than ~112px.
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

/// Raw RGBA bytes in, the top-scoring ARGB color out. Pure Dart, so it can
/// run in a helper isolate.
Future<int> _scoreSeed(Uint8List rgba) async {
  final pixels = <int>[
    for (var i = 0; i + 3 < rgba.length; i += 4)
      (rgba[i + 3] << 24) | (rgba[i] << 16) | (rgba[i + 1] << 8) | rgba[i + 2],
  ];
  final quantized = await QuantizerCelebi().quantize(pixels, 128);
  return Score.score(quantized.colorToCount).first;
}

Future<ui.Image> _resolveImage(ImageProvider provider) {
  final completer = Completer<ui.Image>();
  final stream = provider.resolve(ImageConfiguration.empty);
  late final ImageStreamListener listener;
  listener = ImageStreamListener(
    (ImageInfo info, _) {
      stream.removeListener(listener);
      completer.complete(info.image.clone());
      info.dispose();
    },
    onError: (Object error, StackTrace? stackTrace) {
      stream.removeListener(listener);
      completer.completeError(error, stackTrace ?? StackTrace.current);
    },
  );
  stream.addListener(listener);
  return completer.future;
}
