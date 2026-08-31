import 'dart:ui' as ui;

import 'package:another_image/src/theme/seed_color.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

/// Matches a color whose channels are each within [tolerance]/255 of
/// [expected]; the quantizer round-trips through Lab, which can move a
/// channel by one.
Matcher closeToColor(Color expected, {int tolerance = 2}) => predicate<Color>(
  (c) =>
      ((c.r - expected.r) * 255).abs() <= tolerance &&
      ((c.g - expected.g) * 255).abs() <= tolerance &&
      ((c.b - expected.b) * 255).abs() <= tolerance,
  'within $tolerance/255 of #${expected.toARGB32().toRadixString(16)}',
);

/// A [width]×[height] frame whose left [leftFraction] is [left] and the
/// rest is [right].
Future<ui.Image> renderSplit(
  Color left,
  Color right, {
  double leftFraction = 0.75,
  int width = 8,
  int height = 8,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  final split = width * leftFraction;
  canvas.drawRect(
    ui.Rect.fromLTWH(0, 0, split, height.toDouble()),
    ui.Paint()..color = left,
  );
  canvas.drawRect(
    ui.Rect.fromLTWH(split, 0, width - split, height.toDouble()),
    ui.Paint()..color = right,
  );
  return recorder.endRecording().toImage(width, height);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('returns the color of a solid frame', () async {
    const red = Color(0xFFD32F2F);
    final image = await renderSplit(red, red);

    final seed = await seedColorFromImage(image);

    expect(seed, closeToColor(red));
    image.dispose(); // The caller keeps ownership.
  });

  test('prefers the dominant chromatic color', () async {
    const blue = Color(0xFF1E88E5);
    const orange = Color(0xFFFB8C00);
    final image = await renderSplit(blue, orange);

    final seed = await seedColorFromImage(image);

    expect(seed, closeToColor(blue));
    image.dispose();
  });

  test(
    'samples a full-size frame down without losing the dominant color',
    () async {
      const blue = Color(0xFF1E88E5);
      const orange = Color(0xFFFB8C00);
      final image = await renderSplit(blue, orange, width: 1024, height: 1024);

      final seed = await seedColorFromImage(image);

      expect(seed, closeToColor(blue));
      image.dispose();
    },
  );

  test('is not fooled by colors aligned to a flat sampling stride', () async {
    // A flat stride over a 1024px-wide buffer is 64 pixels and would sample
    // only columns 0, 64, 128, ... – exactly the 1px stripes painted here.
    // The 2D grid sampler must still see the blue in between.
    const blue = Color(0xFF1E88E5);
    const orange = Color(0xFFFB8C00);
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawRect(
      const ui.Rect.fromLTWH(0, 0, 1024, 1024),
      ui.Paint()..color = blue,
    );
    for (var x = 0; x < 1024; x += 64) {
      canvas.drawRect(
        ui.Rect.fromLTWH(x.toDouble(), 0, 1, 1024),
        ui.Paint()..color = orange,
      );
    }
    final image = await recorder.endRecording().toImage(1024, 1024);

    final seed = await seedColorFromImage(image);

    expect(seed, closeToColor(blue));
    image.dispose();
  });
}
