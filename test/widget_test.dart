import 'package:another_image/main.dart';
import 'package:another_image/src/api/image_api.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_image_api.dart';

Future<ColorScheme> stubSchemeExtractor(String url, Brightness brightness) async {
  return ColorScheme.fromSeed(seedColor: Colors.teal, brightness: brightness);
}

void main() {
  testWidgets('fetches on startup and again when Another is tapped',
      (tester) async {
    final api = FakeImageApi(['https://example.com/a', 'https://example.com/b']);
    await tester.pumpWidget(
      AnotherImageApp(api: api, schemeExtractor: stubSchemeExtractor),
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
      AnotherImageApp(api: api, schemeExtractor: stubSchemeExtractor),
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
}
