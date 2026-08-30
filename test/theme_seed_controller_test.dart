import 'dart:async';
import 'dart:ui';

import 'package:another_image/src/state/random_image_controller.dart';
import 'package:another_image/src/state/theme_seed_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_image_api.dart';

const red = Color(0xFFFF0000);
const green = Color(0xFF00FF00);
const blue = Color(0xFF0000FF);

void main() {
  test('starts with the fallback and follows each loaded image', () async {
    final images = RandomImageController(FakeImageApi(['url-a', 'url-b']));
    final seeds = ThemeSeedController(
      images,
      (url) async => url == 'url-a' ? red : green,
    );
    var notified = 0;
    seeds.addListener(() => notified++);

    expect(seeds.seed, ThemeSeedController.defaultFallback);

    await images.fetch();
    await pumpEventQueue();
    expect(seeds.seed, red);

    await images.fetch();
    await pumpEventQueue();
    expect(seeds.seed, green);
    expect(notified, 2);
  });

  test('ignores an extraction that finishes after a newer one', () async {
    final images = RandomImageController(FakeImageApi(['url-a', 'url-b']));
    final pending = <String, Completer<Color>>{};
    final seeds = ThemeSeedController(
      images,
      (url) => (pending[url] = Completer<Color>()).future,
    );

    await images.fetch(); // url-a: extraction stays pending.
    await images.fetch(); // url-b: also pending.
    pending['url-b']!.complete(blue);
    await pumpEventQueue();
    expect(seeds.seed, blue);

    pending['url-a']!.complete(red); // The slow, stale one.
    await pumpEventQueue();

    expect(seeds.seed, blue);
  });

  test('keeps the previous seed when extraction fails', () async {
    final images = RandomImageController(FakeImageApi(['url-a', 'url-b']));
    final seeds = ThemeSeedController(
      images,
      (url) async => url == 'url-a' ? green : throw StateError('undecodable'),
    );
    var notified = 0;
    seeds.addListener(() => notified++);

    await images.fetch();
    await pumpEventQueue();
    await images.fetch();
    await pumpEventQueue();

    expect(seeds.seed, green);
    expect(notified, 1);
  });

  test('stops following images after dispose', () async {
    final images = RandomImageController(FakeImageApi(['url-a']));
    var extractions = 0;
    final seeds = ThemeSeedController(images, (_) async {
      extractions++;
      return red;
    });

    seeds.dispose();
    await images.fetch();
    await pumpEventQueue();

    expect(extractions, 0);
  });
}
