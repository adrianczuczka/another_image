import 'dart:async';

import 'package:another_image/src/api/image_api.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Matcher throwsFailure(ImageApiFailure failure, {int? statusCode}) => throwsA(
  isA<ImageApiException>()
      .having((e) => e.failure, 'failure', failure)
      .having((e) => e.statusCode, 'statusCode', statusCode),
);

void main() {
  group('ImageApi.fetchRandomImageUrl', () {
    test('returns the URL with sizing params merged in', () async {
      final api = ImageApi(
        client: MockClient((request) async {
          expect(request.method, 'GET');
          expect(request.url, ImageApi.defaultEndpoint);
          return http.Response(
            '{"url": "https://images.unsplash.com/photo-123"}',
            200,
          );
        }),
      );

      final url = Uri.parse(await api.fetchRandomImageUrl());

      expect(url.host, 'images.unsplash.com');
      expect(url.path, '/photo-123');
      expect(url.queryParameters, ImageApi.imageParams);
    });

    test(
      'preserves existing query params; sizing params win on conflict',
      () async {
        final api = ImageApi(
          client: MockClient(
            (_) async => http.Response(
              '{"url": "https://images.unsplash.com/photo-123?sig=abc&w=32"}',
              200,
            ),
          ),
        );

        final url = Uri.parse(await api.fetchRandomImageUrl());

        expect(url.queryParameters['sig'], 'abc');
        expect(url.queryParameters['w'], ImageApi.imageParams['w']);
      },
    );

    test('leaves non-Unsplash URLs untouched', () async {
      final api = ImageApi(
        client: MockClient(
          (_) async =>
              http.Response('{"url": "https://example.com/photo.jpg"}', 200),
        ),
      );

      expect(await api.fetchRandomImageUrl(), 'https://example.com/photo.jpg');
    });

    test('reports a non-200 response as a server error with its status', () {
      final api = ImageApi(
        client: MockClient((_) async => http.Response('oops', 503)),
      );

      expect(
        api.fetchRandomImageUrl,
        throwsFailure(ImageApiFailure.serverError, statusCode: 503),
      );
    });

    test('reports a non-JSON body as malformed', () {
      final api = ImageApi(
        client: MockClient((_) async => http.Response('not json', 200)),
      );

      expect(api.fetchRandomImageUrl, throwsFailure(ImageApiFailure.malformed));
    });

    test('reports a body missing the url field as malformed', () {
      final api = ImageApi(
        client: MockClient((_) async => http.Response('{"other": 1}', 200)),
      );

      expect(api.fetchRandomImageUrl, throwsFailure(ImageApiFailure.malformed));
    });

    test('reports a non-string url as malformed', () {
      final api = ImageApi(
        client: MockClient((_) async => http.Response('{"url": 42}', 200)),
      );

      expect(api.fetchRandomImageUrl, throwsFailure(ImageApiFailure.malformed));
    });

    test('reports an unparseable url as malformed', () {
      final api = ImageApi(
        client: MockClient(
          (_) async => http.Response('{"url": "http://[bad"}', 200),
        ),
      );

      expect(api.fetchRandomImageUrl, throwsFailure(ImageApiFailure.malformed));
    });

    test('reports a stalled request as unreachable after the timeout', () {
      fakeAsync((fake) {
        final api = ImageApi(
          // A request that never completes.
          client: MockClient((_) => Completer<http.Response>().future),
        );
        Object? caught;
        api.fetchRandomImageUrl().then<void>(
          (_) {},
          onError: (Object e) => caught = e,
        );

        fake.elapse(ImageApi.timeout + const Duration(milliseconds: 1));

        expect(
          caught,
          isA<ImageApiException>().having(
            (e) => e.failure,
            'failure',
            ImageApiFailure.unreachable,
          ),
        );
      });
    });

    test('reports network errors as unreachable', () {
      final api = ImageApi(
        client: MockClient((_) async => throw http.ClientException('boom')),
      );

      expect(
        api.fetchRandomImageUrl,
        throwsFailure(ImageApiFailure.unreachable),
      );
    });

    test('reports an empty or relative url as malformed', () async {
      for (final body in ['{"url": ""}', '{"url": "not a url"}']) {
        final api = ImageApi(
          client: MockClient((_) async => http.Response(body, 200)),
        );
        await expectLater(
          api.fetchRandomImageUrl,
          throwsFailure(ImageApiFailure.malformed),
        );
      }
    });

    test('dispose leaves an injected client usable by other owners', () async {
      final client = MockClient(
        (_) async =>
            http.Response('{"url": "https://images.unsplash.com/p"}', 200),
      );
      final first = ImageApi(client: client);
      final second = ImageApi(client: client);

      first.dispose();

      await expectLater(second.fetchRandomImageUrl(), completes);
    });
  });
}
