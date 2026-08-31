import 'dart:async';

import 'package:another_image/src/api/image_api.dart';
import 'package:another_image/src/state/random_image_controller.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_image_api.dart';

void main() {
  test('emits loading then loaded on success', () async {
    final controller = RandomImageController(FakeImageApi(['url-a']));
    final states = <RandomImageState>[];
    controller.addListener(() => states.add(controller.state));

    await controller.fetch();

    expect(states, hasLength(2));
    expect(states.first, isA<RandomImageLoading>());
    expect((states.last as RandomImageLoaded).url, 'url-a');
  });

  test('emits error state when the API fails', () async {
    final controller = RandomImageController(
      FakeImageApi([ImageApiException(ImageApiFailure.unreachable)]),
    );

    await controller.fetch();

    expect(
      (controller.state as RandomImageError).cause,
      ImageApiFailure.unreachable,
    );
  });

  test('reports unexpected exceptions and shows a causeless error', () async {
    final reported = <FlutterErrorDetails>[];
    final previousHandler = FlutterError.onError;
    FlutterError.onError = reported.add;
    addTearDown(() => FlutterError.onError = previousHandler);
    final controller = RandomImageController(
      FakeImageApi([const FormatException('bad uri')]),
    );

    await controller.fetch();

    expect((controller.state as RandomImageError).cause, isNull);
    expect(reported, hasLength(1));
    expect(reported.single.exception, isA<FormatException>());
  });

  test('re-rolls when the API returns the current URL again', () async {
    final api = FakeImageApi(['url-a', 'url-a', 'url-b']);
    final controller = RandomImageController(api);

    await controller.fetch();
    await controller.fetch();

    expect((controller.state as RandomImageLoaded).url, 'url-b');
    expect(api.calls, 3);
  });

  test(
    'gives up re-rolling after the retry cap and keeps the duplicate',
    () async {
      final api = FakeImageApi(['url-a', 'url-a', 'url-a', 'url-a', 'url-a']);
      final controller = RandomImageController(api);

      await controller.fetch();
      await controller.fetch();

      // Second fetch: 1 initial attempt + maxDuplicateRetries re-rolls.
      expect(api.calls, 2 + RandomImageController.maxDuplicateRetries);
      expect((controller.state as RandomImageLoaded).url, 'url-a');
    },
  );

  test('keeps the duplicate when a re-roll fails', () async {
    final api = FakeImageApi([
      'url-a',
      'url-a',
      ImageApiException(ImageApiFailure.unreachable),
    ]);
    final controller = RandomImageController(api);

    await controller.fetch();
    await controller.fetch();

    expect(api.calls, 3);
    expect((controller.state as RandomImageLoaded).url, 'url-a');
  });

  test('recovers from error on the next fetch', () async {
    final controller = RandomImageController(
      FakeImageApi([ImageApiException(ImageApiFailure.unreachable), 'url-a']),
    );

    await controller.fetch();
    expect(controller.state, isA<RandomImageError>());

    await controller.fetch();
    expect((controller.state as RandomImageLoaded).url, 'url-a');
  });

  test('ignores fetch calls while one is in flight', () async {
    final completer = Completer<String>();
    final api = FakeImageApi([completer]);
    final controller = RandomImageController(api);

    final first = controller.fetch();
    await controller.fetch(); // Re-entrant: must not consume a result.
    completer.complete('url-a');
    await first;

    expect(api.calls, 1);
    expect((controller.state as RandomImageLoaded).url, 'url-a');
  });

  test('does not notify after dispose', () async {
    final completer = Completer<String>();
    final controller = RandomImageController(FakeImageApi([completer]));
    var notified = false;
    controller.addListener(() => notified = true);

    final pending = controller.fetch();
    notified = false;
    controller.dispose();
    completer.complete('url-a');

    // Completes without throwing "used after being disposed".
    await pending;
    expect(notified, isFalse);
  });

  group('imageFailed', () {
    test(
      'fetches a replacement for the first dead image after a fetch',
      () async {
        final api = FakeImageApi(['url-a', 'url-b']);
        final controller = RandomImageController(api);
        await controller.fetch();

        expect(controller.imageFailed('url-a'), isTrue);
        expect(controller.state, isA<RandomImageLoaded>()); // Not yet started.
        await pumpEventQueue();

        expect(api.calls, 2);
        expect((controller.state as RandomImageLoaded).url, 'url-b');
      },
    );

    test('is idempotent while the replacement is pending', () async {
      final api = FakeImageApi(['url-a', 'url-b']);
      final controller = RandomImageController(api);
      await controller.fetch();

      expect(controller.imageFailed('url-a'), isTrue);
      expect(controller.imageFailed('url-a'), isTrue);
      await pumpEventQueue();

      expect(api.calls, 2);
    });

    test('gives up after one replacement per fetch', () async {
      final api = FakeImageApi(['url-a', 'url-b']);
      final controller = RandomImageController(api);
      await controller.fetch();
      controller.imageFailed('url-a');
      await pumpEventQueue();

      expect(controller.imageFailed('url-b'), isFalse);
      await pumpEventQueue();
      expect(api.calls, 2);
    });

    test('gives up when the replacement is the same dead URL', () async {
      final api = FakeImageApi(['url-a', 'url-a', 'url-a', 'url-a']);
      final controller = RandomImageController(api);
      await controller.fetch();
      controller.imageFailed('url-a');
      await pumpEventQueue();

      expect((controller.state as RandomImageLoaded).url, 'url-a');
      expect(controller.imageFailed('url-a'), isFalse);
    });

    test('a new fetch grants a fresh replacement', () async {
      final api = FakeImageApi(['url-a', 'url-b', 'url-c', 'url-d']);
      final controller = RandomImageController(api);
      await controller.fetch();
      controller.imageFailed('url-a');
      await pumpEventQueue();
      expect(controller.imageFailed('url-b'), isFalse);

      await controller.fetch();
      expect((controller.state as RandomImageLoaded).url, 'url-c');
      expect(controller.imageFailed('url-c'), isTrue);
      await pumpEventQueue();

      expect(api.calls, 4);
      expect((controller.state as RandomImageLoaded).url, 'url-d');
    });

    test(
      'treats a failure for a stale URL as handled without fetching',
      () async {
        final api = FakeImageApi(['url-a']);
        final controller = RandomImageController(api);
        await controller.fetch();

        expect(controller.imageFailed('url-old'), isTrue);
        await pumpEventQueue();
        expect(api.calls, 1);
      },
    );

    test('ignores a late failure once the state has moved on', () async {
      final api = FakeImageApi([
        'url-a',
        ImageApiException(ImageApiFailure.unreachable),
      ]);
      final controller = RandomImageController(api);
      await controller.fetch(); // Loaded(url-a).
      await controller.fetch(); // The next tap failed: RandomImageError.

      // url-a's download fails while its widget is fading out.
      expect(controller.imageFailed('url-a'), isTrue);
      await pumpEventQueue();

      expect(api.calls, 2); // No unrequested refetch.
      expect(controller.state, isA<RandomImageError>()); // The panel stays.
    });
  });

  group('goBack', () {
    test('restores the previous image without a fetch', () async {
      final api = FakeImageApi(['url-a', 'url-b']);
      final controller = RandomImageController(api);
      await controller.fetch();
      expect(controller.canGoBack, isFalse);
      await controller.fetch();
      expect(controller.canGoBack, isTrue);

      controller.goBack();

      final state = controller.state as RandomImageLoaded;
      expect(state.url, 'url-a');
      expect(state.fromHistory, isTrue);
      expect(api.calls, 2); // No network for going back.
      expect(controller.canGoBack, isFalse);
    });

    test('walks further back on repeated calls', () async {
      final api = FakeImageApi(['url-a', 'url-b', 'url-c']);
      final controller = RandomImageController(api);
      await controller.fetch();
      await controller.fetch();
      await controller.fetch();

      controller.goBack();
      expect((controller.state as RandomImageLoaded).url, 'url-b');
      controller.goBack();
      expect((controller.state as RandomImageLoaded).url, 'url-a');
      expect(controller.canGoBack, isFalse);
    });

    test('a fetch after going back can be undone too', () async {
      final api = FakeImageApi(['url-a', 'url-b', 'url-c']);
      final controller = RandomImageController(api);
      await controller.fetch();
      await controller.fetch();
      controller.goBack(); // Showing url-a again, history empty.

      await controller.fetch(); // url-c, history [url-a].
      controller.goBack();

      expect((controller.state as RandomImageLoaded).url, 'url-a');
    });

    test('is ignored while a fetch is in flight', () async {
      final completer = Completer<String>();
      final api = FakeImageApi(['url-a', completer]);
      final controller = RandomImageController(api);
      await controller.fetch();
      final second = controller.fetch(); // In flight; history [url-a].

      controller.goBack();
      expect(controller.state, isA<RandomImageLoading>());

      completer.complete('url-b');
      await second;
      expect((controller.state as RandomImageLoaded).url, 'url-b');
      expect(controller.canGoBack, isTrue); // History untouched.
    });

    test('caps the history', () async {
      final urls = [
        for (var i = 0; i <= RandomImageController.maxHistoryLength + 5; i++)
          'url-$i',
      ];
      final controller = RandomImageController(FakeImageApi(urls));
      for (var i = 0; i < urls.length; i++) {
        await controller.fetch();
      }

      var steps = 0;
      while (controller.canGoBack) {
        controller.goBack();
        steps++;
      }
      expect(steps, RandomImageController.maxHistoryLength);
    });

    test('steps further back when a restored image fails', () async {
      final api = FakeImageApi(['url-a', 'url-b', 'url-c']);
      final controller = RandomImageController(api);
      await controller.fetch();
      await controller.fetch();
      await controller.fetch(); // Showing url-c, history [url-a, url-b].
      controller.goBack(); // url-b, history [url-a].

      expect(controller.imageFailed('url-b'), isTrue);
      await pumpEventQueue();

      final state = controller.state as RandomImageLoaded;
      expect(state.url, 'url-a');
      expect(state.fromHistory, isTrue);
      expect(api.calls, 3); // Stepping back never fetches.
    });

    test('falls back to a fresh fetch when history runs out', () async {
      final api = FakeImageApi(['url-a', 'url-b', 'url-c']);
      final controller = RandomImageController(api);
      await controller.fetch();
      await controller.fetch(); // url-b, history [url-a].
      controller.goBack(); // url-a, history empty.

      expect(controller.imageFailed('url-a'), isTrue);
      await pumpEventQueue();

      expect((controller.state as RandomImageLoaded).url, 'url-c');
      expect(api.calls, 3);
    });
  });
}
