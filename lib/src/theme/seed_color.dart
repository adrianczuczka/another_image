import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:material_color_utilities/material_color_utilities.dart';

/// Extracts a Material 3 seed color from [provider].
///
/// Runs the same quantize-and-score pipeline as
/// [ColorScheme.fromImageProvider], but returns the seed itself so that the
/// light and dark schemes can both be derived from a single image decode
/// instead of one decode per brightness. Pass a provider that decodes at
/// thumbnail size; quantization doesn't need more than ~112px.
Future<Color> seedColorFromImageProvider(ImageProvider provider) async {
  final ui.Image image = await _resolveImage(provider);
  try {
    final byteData = await image.toByteData();
    if (byteData == null) {
      throw StateError('Could not read image bytes');
    }
    final bytes = byteData.buffer.asUint8List();
    final pixels = <int>[
      for (var i = 0; i + 3 < bytes.length; i += 4)
        // Raw RGBA bytes to the ARGB ints the quantizer expects.
        (bytes[i + 3] << 24) | (bytes[i] << 16) | (bytes[i + 1] << 8) | bytes[i + 2],
    ];
    final quantized = await QuantizerCelebi().quantize(pixels, 128);
    final ranked = Score.score(quantized.colorToCount);
    return Color(ranked.first);
  } finally {
    image.dispose();
  }
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
