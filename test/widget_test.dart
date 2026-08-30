import 'package:another_image/main.dart';
import 'package:another_image/src/api/image_api.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_image_api.dart';

Future<Color> stubSeedExtractor(String url) async => Colors.teal;

void main() {
  testWidgets('fetches on startup and again when Another is tapped',
      (tester) async {
    final api = FakeImageApi(['https://example.com/a', 'https://example.com/b']);
    await tester.pumpWidget(
      AnotherImageApp(api: api, seedExtractor: stubSeedExtractor),
    );
    await tester.pump();

    expect(api.calls, 1);
    expect(find.byType(CachedNetworkImage), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Another'));
    await tester.pump();
    await tester.pump();

    expect(api.calls, 2);
  });

  testWidgets('shows an error panel with retry when the API fails',
      (tester) async {
    final api = FakeImageApi(
      [ImageApiException('down'), 'https://example.com/a'],
    );
    await tester.pumpWidget(
      AnotherImageApp(api: api, seedExtractor: stubSeedExtractor),
    );
    await tester.pump();

    expect(find.text('down'), findsOneWidget);
    expect(find.byType(CachedNetworkImage), findsNothing);

    await tester.tap(find.widgetWithText(TextButton, 'Try again'));
    await tester.pump();
    await tester.pump();

    expect(api.calls, 2);
    expect(find.byType(CachedNetworkImage), findsOneWidget);
  });

  testWidgets('stacks the button below the square in portrait',
      (tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final api = FakeImageApi(['https://example.com/a']);
    await tester.pumpWidget(
      AnotherImageApp(api: api, seedExtractor: stubSeedExtractor),
    );
    await tester.pump();

    expect(find.byType(AspectRatio), findsOneWidget);
    final square = tester.getRect(find.byType(AspectRatio));
    final button = tester.getRect(find.byType(FilledButton));

    expect(square.width, 560); // Capped, not the full 800 - 64.
    expect(button.top, greaterThan(square.bottom));
    expect(button.center.dx, closeTo(square.center.dx, 1));
  });

  testWidgets('places the button beside the square in landscape',
      (tester) async {
    tester.view.physicalSize = const Size(1600, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final api = FakeImageApi(['https://example.com/a']);
    await tester.pumpWidget(
      AnotherImageApp(api: api, seedExtractor: stubSeedExtractor),
    );
    await tester.pump();

    final square = tester.getRect(find.byType(AspectRatio));
    final button = tester.getRect(find.byType(FilledButton));

    expect(square.height, 560); // Capped; would be 800 - 32 uncapped.
    expect(button.left, greaterThan(square.right));
    expect(button.center.dy, closeTo(square.center.dy, 1));
  });
}
