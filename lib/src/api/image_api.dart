import 'dart:convert';

import 'package:http/http.dart' as http;

/// Thrown when the image API returns an unusable response.
class ImageApiException implements Exception {
  ImageApiException(this.message);

  final String message;

  @override
  String toString() => 'ImageApiException: $message';
}

/// Client for the random image API.
class ImageApi {
  ImageApi({http.Client? client, Uri? endpoint})
      : _client = client ?? http.Client(),
        _endpoint = endpoint ?? defaultEndpoint;

  /// `/image/` with the trailing slash: the bare `/image` path answers with a
  /// 307 redirect to it.
  static final Uri defaultEndpoint =
      Uri.parse('https://november7-730026606190.europe-west1.run.app/image/');

  /// Resize parameters appended to returned Unsplash URLs. The API hands out
  /// bare URLs that resolve to multi-MB originals; Unsplash's imgix params
  /// let us request a phone-sized square crop instead, matching the square
  /// display exactly.
  static const Map<String, String> imageParams = {
    'w': '1200',
    'h': '1200',
    'fit': 'crop',
    'q': '80',
    'fm': 'jpg',
  };

  final http.Client _client;
  final Uri _endpoint;

  /// Fetches a random image URL, sized for on-device display.
  Future<String> fetchRandomImageUrl() async {
    final http.Response response;
    try {
      response = await _client.get(_endpoint);
    } catch (e) {
      throw ImageApiException('Network error: $e');
    }
    if (response.statusCode != 200) {
      throw ImageApiException('Server responded with ${response.statusCode}');
    }
    final String url;
    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      url = body['url'] as String;
    } catch (_) {
      throw ImageApiException('Unexpected response body');
    }
    return Uri.parse(url)
        .replace(queryParameters: imageParams)
        .toString();
  }

  void dispose() => _client.close();
}
