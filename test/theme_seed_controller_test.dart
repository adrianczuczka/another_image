import 'dart:async';
import 'dart:ui' as ui;

import 'package:another_image/src/state/theme_seed_controller.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

const red = Color(0xFFFF0000);
const green = Color(0xFF00FF00);
const blue = Color(0xFF0000FF);

/// A tiny rendered frame; each call returns a fresh image because the
/// controller takes ownership and disposes what it is given.
Future<ui.Image> frame() {
  final recorder = ui.PictureRecorder();
  ui.Canvas(
    recorder,
  ).drawRect(const ui.Rect.fromLTWH(0, 0, 2, 2), ui.Paint()..color = red);
  return recorder.endRecording().toImage(2, 2);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('starts with the fallback and follows each rendered image', () async {
    final queue = [red, green];
    final seeds = ThemeSeedController((_) async => queue.removeAt(0));
    var notified = 0;
    seeds.addListener(() => notified++);

    expect(seeds.seed, ThemeSeedController.defaultFallback);

    seeds.imageShown('url-a', await frame());
    await pumpEventQueue();
    expect(seeds.seed, red);

    seeds.imageShown('url-b', await frame());
    await pumpEventQueue();
    expect(seeds.seed, green);
    expect(notified, 2);
  });

  test('ignores an extraction that finishes after a newer one', () async {
    final pending = <Completer<Color>>[];
    final seeds = ThemeSeedController((_) {
      final completer = Completer<Color>();
      pending.add(completer);
      return completer.future;
    });

    seeds.imageShown('url-a', await frame());
    seeds.imageShown('url-b', await frame());
    pending[1].complete(blue);
    await pumpEventQueue();
    expect(seeds.seed, blue);

    pending[0].complete(red); // The slow, stale one.
    await pumpEventQueue();

    expect(seeds.seed, blue);
  });

  test('skips re-extraction when the same image renders again', () async {
    var extractions = 0;
    final seeds = ThemeSeedController((_) async {
      extractions++;
      return red;
    });

    seeds.imageShown('url-a', await frame());
    await pumpEventQueue();
    seeds.imageShown('url-a', await frame()); // The duplicate re-roll case.
    await pumpEventQueue();

    expect(extractions, 1);
    expect(seeds.seed, red);
  });

  test('retries a URL whose extraction failed when it renders again', () async {
    var calls = 0;
    final seeds = ThemeSeedController((_) async {
      if (++calls == 1) throw Exception('unreadable');
      return green;
    });

    seeds.imageShown('url-a', await frame());
    await pumpEventQueue();
    expect(seeds.seed, ThemeSeedController.defaultFallback);

    seeds.imageShown('url-a', await frame());
    await pumpEventQueue();

    expect(seeds.seed, green);
  });

  test('keeps the previous seed when extraction fails', () async {
    var calls = 0;
    final seeds = ThemeSeedController((_) async {
      if (++calls == 1) return green;
      throw Exception('unreadable');
    });

    seeds.imageShown('url-a', await frame());
    await pumpEventQueue();
    seeds.imageShown('url-b', await frame());
    await pumpEventQueue();

    expect(seeds.seed, green);
  });

  test('reports a programming error from extraction, keeps the seed', () async {
    final reported = <FlutterErrorDetails>[];
    final previousHandler = FlutterError.onError;
    FlutterError.onError = reported.add;
    addTearDown(() => FlutterError.onError = previousHandler);
    final seeds = ThemeSeedController((_) async => throw StateError('bug'));

    seeds.imageShown('url-a', await frame());
    await pumpEventQueue();

    expect(seeds.seed, ThemeSeedController.defaultFallback);
    expect(reported, hasLength(1));
  });

  test('does not notify for an identical seed from a new image', () async {
    final seeds = ThemeSeedController((_) async => red);
    var notified = 0;
    seeds.addListener(() => notified++);

    seeds.imageShown('url-a', await frame());
    await pumpEventQueue();
    seeds.imageShown('url-b', await frame());
    await pumpEventQueue();

    expect(seeds.seed, red);
    expect(notified, 1);
  });

  test('ignores frames after dispose', () async {
    var extractions = 0;
    final seeds = ThemeSeedController((_) async {
      extractions++;
      return red;
    });

    seeds.dispose();
    seeds.imageShown('url-a', await frame());
    await pumpEventQueue();

    expect(extractions, 0);
  });
}
