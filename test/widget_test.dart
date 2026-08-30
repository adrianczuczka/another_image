import 'package:another_image/main.dart';
import 'package:another_image/src/api/image_api.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_cache_manager.dart';
import 'fake_image_api.dart';

Future<Color> stubSeedExtractor(String url) async => Colors.teal;

const imageFailedCopy = "This image couldn't be loaded";

void main() {
  testWidgets('fetches on startup and again when Another is tapped',
      (tester) async {
    final api = FakeImageApi(['https://example.com/a', 'https://example.com/b']);
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

  testWidgets('derives both themes from the extracted seed', (tester) async {
    final api = FakeImageApi(['https://example.com/a']);
    await tester.pumpWidget(
      AnotherImageApp(
        api: api,
        seedExtractor: (_) async => Colors.teal,
        cacheManager: FakeCacheManager(),
      ),
    );
    await tester.pump(); // The fetch completes.
    await tester.pump(); // The extraction completes.
    await tester.pump(); // The themes rebuild.

    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(
      app.theme!.colorScheme.primary,
      ColorScheme.fromSeed(seedColor: Colors.teal).primary,
    );
    expect(
      app.darkTheme!.colorScheme.primary,
      ColorScheme.fromSeed(seedColor: Colors.teal, brightness: Brightness.dark)
          .primary,
    );
  });

  testWidgets('shows an error panel with retry when the API fails',
      (tester) async {
    final api = FakeImageApi(
      [ImageApiException(ImageApiFailure.unreachable), 'https://example.com/a'],
    );
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

  testWidgets('replaces a dead image silently, then shows the panel',
      (tester) async {
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

  testWidgets('stacks the button below the square in portrait',
      (tester) async {
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

    expect(find.byType(AspectRatio), findsOneWidget);
    final square = tester.getRect(find.byType(AspectRatio));
    final button = tester.getRect(find.byType(FilledButton));

    expect(square.width, 560); // Capped, not the full 800 - 64.
    expect(button.height, 64); // Tablet-sized to match.
    expect(button.top, greaterThan(square.bottom));
    expect(button.center.dx, closeTo(square.center.dx, 1));
  });

  testWidgets('fills the width on a phone with a regular-size button',
      (tester) async {
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

    final square = tester.getRect(find.byType(AspectRatio));
    final button = tester.getRect(find.byType(FilledButton));

    expect(square.width, 390 - 64);
    expect(button.height, 52);
  });

  testWidgets('places the button beside the square in landscape',
      (tester) async {
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

    final square = tester.getRect(find.byType(AspectRatio));
    final button = tester.getRect(find.byType(FilledButton));

    expect(square.height, 560); // Capped; would be 800 - 32 uncapped.
    expect(button.height, 64);
    expect(button.left, greaterThan(square.right));
    expect(button.center.dy, closeTo(square.center.dy, 1));
  });
}
