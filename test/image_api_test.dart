import 'package:another_image/src/api/image_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('ImageApi.fetchRandomImageUrl', () {
    test('returns the URL with sizing params appended', () async {
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

    test('throws on a non-200 response', () {
      final api = ImageApi(
        client: MockClient((_) async => http.Response('oops', 500)),
      );

      expect(api.fetchRandomImageUrl, throwsA(isA<ImageApiException>()));
    });

    test('throws on a malformed body', () {
      final api = ImageApi(
        client: MockClient((_) async => http.Response('not json', 200)),
      );

      expect(api.fetchRandomImageUrl, throwsA(isA<ImageApiException>()));
    });

    test('throws on a body missing the url field', () {
      final api = ImageApi(
        client: MockClient((_) async => http.Response('{"other": 1}', 200)),
      );

      expect(api.fetchRandomImageUrl, throwsA(isA<ImageApiException>()));
    });

    test('wraps network errors', () {
      final api = ImageApi(
        client: MockClient((_) async => throw http.ClientException('boom')),
      );

      expect(api.fetchRandomImageUrl, throwsA(isA<ImageApiException>()));
    });
  });
}
