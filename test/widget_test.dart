import 'dart:ui' as ui;

import 'package:another_image/main.dart';
import 'package:another_image/src/api/image_api.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_cache_manager.dart';
import 'fake_image_api.dart';

Future<Color> stubSeedExtractor(ui.Image _) async => Colors.teal;

const imageFailedCopy = "This image couldn't be loaded";

void main() {
  testWidgets('fetches on startup and again when Another is tapped', (
    tester,
  ) async {
    final api = FakeImageApi([
      'https://example.com/a',
      'https://example.com/b',
    ]);
    await tester.pumpWidget(
      AnotherImageApp(
        api: api,
        seedExtractor: stubSeedExtractor,
        cacheManager: FakeCacheManager(),
      ),
    );
    await tester.pump();

    expect(api.calls, 1);
    expect(find.byType(CachedNetworkImage), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Another'));
    await tester.pump();
    await tester.pump();

    expect(api.calls, 2);
  });

  testWidgets('derives both themes from the image that rendered', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final cache = FakeCacheManager(
        imageFile: await solidImageFile(const Color(0xFF2196F3)),
      );
      final api = FakeImageApi(['https://img.test/ok']);
      await tester.pumpWidget(
        AnotherImageApp(
          api: api,
          seedExtractor: (_) async => Colors.teal,
          cacheManager: cache,
        ),
      );

      final expected = ColorScheme.fromSeed(seedColor: Colors.teal).primary;
      await settle(
        tester,
        () =>
            tester
                .widget<MaterialApp>(find.byType(MaterialApp))
                .theme!
                .colorScheme
                .primary ==
            expected,
      );
      final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(
        app.darkTheme!.colorScheme.primary,
        ColorScheme.fromSeed(
          seedColor: Colors.teal,
          brightness: Brightness.dark,
        ).primary,
      );
    });
  });

  testWidgets('shows an error panel with retry when the API fails', (
    tester,
  ) async {
    final api = FakeImageApi([
      ImageApiException(ImageApiFailure.unreachable),
      'https://example.com/a',
    ]);
    await tester.pumpWidget(
      AnotherImageApp(
        api: api,
        seedExtractor: stubSeedExtractor,
        cacheManager: FakeCacheManager(),
      ),
    );
    await tester.pump();

    expect(
      find.textContaining("Couldn't reach the image service"),
      findsOneWidget,
    );
    expect(find.byType(CachedNetworkImage), findsNothing);

    await tester.tap(find.widgetWithText(TextButton, 'Try again'));
    await tester.pump();
    await tester.pump();

    expect(api.calls, 2);
    expect(find.byType(CachedNetworkImage), findsOneWidget);
  });

  testWidgets('replaces a dead image silently, then shows the panel', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final cache = FakeCacheManager(
        imageFile: await solidImageFile(const Color(0xFF2196F3)),
      );
      final api = FakeImageApi([
        'https://img.test/dead-1', // Startup: dead, replaced silently...
        'https://img.test/ok-1', // ...by this one.
        'https://img.test/dead-2', // Tap: dead, replaced once...
        'https://img.test/dead-3', // ...but the replacement is dead too.
        'https://img.test/ok-2', // "Try another".
      ]);
      await tester.pumpWidget(
        AnotherImageApp(
          api: api,
          seedExtractor: stubSeedExtractor,
          cacheManager: cache,
        ),
      );

      await settle(tester, () => find.byType(RawImage).evaluate().isNotEmpty);
      expect(api.calls, 2);
      expect(find.text(imageFailedCopy), findsNothing);

      await tester.tap(find.widgetWithText(FilledButton, 'Another'));
      await settle(
        tester,
        () => find.text(imageFailedCopy).evaluate().isNotEmpty,
      );
      expect(api.calls, 4);

      await tester.tap(find.widgetWithText(TextButton, 'Try another'));
      await settle(tester, () => find.text(imageFailedCopy).evaluate().isEmpty);
      expect(api.calls, 5);
    });
  });

  testWidgets('stacks the button below the frame in portrait', (tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final api = FakeImageApi(['https://example.com/a']);
    await tester.pumpWidget(
      AnotherImageApp(
        api: api,
        seedExtractor: stubSeedExtractor,
        cacheManager: FakeCacheManager(),
      ),
    );
    await tester.pump();

    final frameFinder = find.byKey(const ValueKey('image-frame'));
    expect(frameFinder, findsOneWidget);
    final frame = tester.getRect(frameFinder);
    final button = tester.getRect(find.byType(FilledButton));

    expect(frame.width, 560); // Capped, not the full 800 - 48.
    expect(frame.height, 700); // Stretched to the 4:5 cap.
    expect(button.height, 64); // Tablet-sized to match.
    expect(button.top, greaterThan(frame.bottom));
    expect(button.center.dx, closeTo(frame.center.dx, 1));
  });

  testWidgets('fills the width on a phone with a regular-size button', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final api = FakeImageApi(['https://example.com/a']);
    await tester.pumpWidget(
      AnotherImageApp(
        api: api,
        seedExtractor: stubSeedExtractor,
        cacheManager: FakeCacheManager(),
      ),
    );
    await tester.pump();

    final frame = tester.getRect(find.byKey(const ValueKey('image-frame')));
    final button = tester.getRect(find.byType(FilledButton));

    expect(frame.width, 390 - 48);
    expect(frame.height, (390 - 48) * 5 / 4); // 4:5 fits the tall screen.
    expect(button.height, 52);
  });

  testWidgets('places the button beside the frame in landscape', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final api = FakeImageApi(['https://example.com/a']);
    await tester.pumpWidget(
      AnotherImageApp(
        api: api,
        seedExtractor: stubSeedExtractor,
        cacheManager: FakeCacheManager(),
      ),
    );
    await tester.pump();

    final frame = tester.getRect(find.byKey(const ValueKey('image-frame')));
    final button = tester.getRect(find.byType(FilledButton));

    expect(frame.height, 540); // Capped; would be 800 - 32 uncapped.
    expect(frame.width, 720); // 4:3 from the capped height.
    expect(button.height, 64);
    expect(button.left, greaterThan(frame.right));
    expect(button.center.dy, closeTo(frame.center.dy, 1));
  });
}
