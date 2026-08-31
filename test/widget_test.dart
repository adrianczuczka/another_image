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
  testWidgets('fetches on startup and again when refresh is tapped', (
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

    await tester.tap(find.byIcon(Icons.shuffle));
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

      await tester.tap(find.byIcon(Icons.shuffle));
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

  testWidgets('fills the screen with the image in portrait', (tester) async {
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

    final image = tester.getRect(find.byType(CachedNetworkImage));
    expect(image, const Rect.fromLTWH(0, 0, 800, 1600));

    final refresh = tester.getRect(find.byIcon(Icons.shuffle));
    expect(refresh.center.dx, greaterThan(800 * 0.8)); // Top-right corner.
    expect(refresh.center.dy, lessThan(100));
  });

  testWidgets('fills a phone screen edge to edge', (
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

    final image = tester.getRect(find.byType(CachedNetworkImage));
    expect(image, const Rect.fromLTWH(0, 0, 390, 844));
    expect(find.byIcon(Icons.shuffle), findsOneWidget);
  });

  testWidgets('fills the screen with the image in landscape', (
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

    final image = tester.getRect(find.byType(CachedNetworkImage));
    expect(image, const Rect.fromLTWH(0, 0, 1600, 800));

    final refresh = tester.getRect(find.byIcon(Icons.shuffle));
    expect(refresh.center.dx, greaterThan(1600 * 0.8)); // Top-right corner.
    expect(refresh.center.dy, lessThan(100));
  });

  testWidgets('goes back to the previous image without refetching', (
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
    expect(find.byIcon(Icons.undo), findsNothing); // Nothing to go back to.

    await tester.tap(find.byIcon(Icons.shuffle));
    await tester.pump();
    await tester.pump();
    expect(find.byIcon(Icons.undo), findsOneWidget);
    // Let the back button finish fading in before tapping it.
    await tester.pump(const Duration(milliseconds: 250));

    await tester.tap(find.byIcon(Icons.undo));
    await tester.pump(); // Rebuild with the restored image; b starts exiting.
    // Advance past the 250 ms cross-fade: the outgoing image is dropped in
    // the same frame its exit animation completes.
    await tester.pump(const Duration(milliseconds: 300));

    final image = tester.widget<CachedNetworkImage>(
      find.byType(CachedNetworkImage),
    );
    expect(image.imageUrl, 'https://example.com/a');
    expect(api.calls, 2); // Going back never fetches.
    expect(find.byIcon(Icons.undo), findsNothing); // History exhausted.
  });
}
