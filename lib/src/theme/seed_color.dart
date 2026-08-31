import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:material_color_utilities/material_color_utilities.dart';

/// Extracts a Material 3 seed color from a decoded [image] – the frame the
/// UI actually rendered, so the theme can never diverge from what is on
/// screen.
///
/// Runs the same quantize-and-score pipeline as
/// [ColorScheme.fromImageProvider], with three differences: it takes the
/// rendered frame instead of resolving an [ImageProvider] a second time; it
/// samples the pixels down to a thumbnail's worth and quantizes them in a
/// helper isolate, so a full-size frame can't jank the UI; and it quantizes
/// true ARGB values rather than raw byte words, which can pick a different
/// winner between closely scored colors (Lab-space clustering isn't
/// invariant under the red/blue swap – this ordering is the color-correct
/// one).
///
/// Does not take ownership of [image]; the caller disposes it.
Future<Color> seedColorFromImage(ui.Image image) async {
  final byteData = await image.toByteData();
  if (byteData == null) {
    // Environmental (engine teardown, memory pressure), not a bug: an
    // Exception, so callers treat it like any other extraction failure.
    throw Exception('Could not read image bytes');
  }
  final pixels = _sampleGrid(
    byteData.buffer.asUint8List(),
    image.width,
    image.height,
  );
  return Color(await Isolate.run(() => _scoreSeed(pixels)));
}

/// Sampling target: quantization needs no more than a ~112px thumbnail's
/// worth of pixels, however large the rendered frame is.
const int _sampleDimension = 112;

/// Picks an even 2D grid of at most [_sampleDimension]² pixels, packed as
/// ARGB ints. Grid-aware sampling rather than a flat stride over the buffer,
/// so the step can't alias with the image width and silently sample only a
/// few columns.
List<int> _sampleGrid(Uint8List rgba, int width, int height) {
  final colStep = (width / _sampleDimension).ceil();
  final rowStep = (height / _sampleDimension).ceil();
  final pixels = <int>[];
  for (var y = 0; y < height; y += rowStep) {
    final rowStart = y * width;
    for (var x = 0; x < width; x += colStep) {
      final i = (rowStart + x) * 4;
      pixels.add(
        (rgba[i + 3] << 24) |
            (rgba[i] << 16) |
            (rgba[i + 1] << 8) |
            rgba[i + 2],
      );
    }
  }
  return pixels;
}

/// Sampled ARGB pixels in, the top-scoring color out. Pure Dart, so it can
/// run in a helper isolate; only the small sampled list crosses the isolate
/// boundary, never the full frame.
Future<int> _scoreSeed(List<int> pixels) async {
  final quantized = await QuantizerCelebi().quantize(pixels, 128);
  return Score.score(quantized.colorToCount).first;
}
