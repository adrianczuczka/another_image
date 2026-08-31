import 'dart:async';
import 'dart:ui' as ui;

import 'package:another_image/src/theme/seed_color.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_cache_manager.dart';

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

/// A [size]×[size] image whose left [leftFraction] is [left] and the rest
/// is [right].
Future<MemoryImage> splitImage(
  Color left,
  Color right, {
  double leftFraction = 0.75,
  int size = 8,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  final split = size * leftFraction;
  canvas.drawRect(
    ui.Rect.fromLTWH(0, 0, split, size.toDouble()),
    ui.Paint()..color = left,
  );
  canvas.drawRect(
    ui.Rect.fromLTWH(split, 0, size - split, size.toDouble()),
    ui.Paint()..color = right,
  );
  final image = await recorder.endRecording().toImage(size, size);
  try {
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    return MemoryImage(bytes!.buffer.asUint8List());
  } finally {
    image.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('returns the color of a solid image', () async {
    const red = Color(0xFFD32F2F);

    final seed = await seedColorFromImageProvider(
      MemoryImage(await solidPng(red)),
    );

    expect(seed, closeToColor(red));
  });

  test('prefers the dominant chromatic color', () async {
    const blue = Color(0xFF1E88E5);
    const orange = Color(0xFFFB8C00);

    final seed = await seedColorFromImageProvider(
      await splitImage(blue, orange),
    );

    expect(seed, closeToColor(blue));
  });

  test('fails when the provider cannot load', () async {
    final provider = MemoryImage(Uint8List.fromList([1, 2, 3]));

    await expectLater(seedColorFromImageProvider(provider), throwsA(anything));
  });

  test('gives up on a provider that never delivers', () {
    fakeAsync((fake) {
      Object? caught;
      seedColorFromImageProvider(
        _NeverLoadsImage(),
      ).then<void>((_) {}, onError: (Object e) => caught = e);

      fake.elapse(const Duration(seconds: 11));

      expect(caught, isA<TimeoutException>());
    });
  });
}

class _NeverLoadsImage extends ImageProvider<_NeverLoadsImage> {
  @override
  Future<_NeverLoadsImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(
    _NeverLoadsImage key,
    ImageDecoderCallback decode,
  ) => OneFrameImageStreamCompleter(Completer<ImageInfo>().future);
}
