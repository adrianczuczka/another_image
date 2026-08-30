import 'dart:convert';

import 'package:http/http.dart' as http;

/// Why a request to the image API failed. The UI decides what to tell the
/// user; this layer only classifies.
enum ImageApiFailure {
  /// No usable response: offline, DNS, TLS, or the request timed out.
  unreachable,

  /// A response with a status other than 200.
  serverError,

  /// A 200 whose body wasn't the expected `{"url": "..."}`.
  malformed,
}

/// Thrown when the image API returns an unusable response.
class ImageApiException implements Exception {
  ImageApiException(this.failure, {this.statusCode});

  final ImageApiFailure failure;

  /// The HTTP status, for [ImageApiFailure.serverError].
  final int? statusCode;

  @override
  String toString() =>
      'ImageApiException($failure${statusCode == null ? '' : ', HTTP $statusCode'})';
}

/// Client for the random image API.
class ImageApi {
  ImageApi({http.Client? client, Uri? endpoint})
    : _client = client ?? http.Client(),
      _endpoint = endpoint ?? defaultEndpoint;

  /// `/image/` with the trailing slash: the bare `/image` path answers with a
  /// 307 redirect to it.
  static final Uri defaultEndpoint = Uri.parse(
    'https://november7-730026606190.europe-west1.run.app/image/',
  );

  static const Duration timeout = Duration(seconds: 10);

  /// The only host the sizing parameters apply to; other URLs pass through.
  static const String unsplashHost = 'images.unsplash.com';

  /// Resize parameters merged into returned Unsplash URLs (existing
  /// parameters are preserved; these win on conflict). The API hands out
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
      response = await _client.get(_endpoint).timeout(timeout);
    } on Exception {
      // ClientException, SocketException, TimeoutException, and friends.
      throw ImageApiException(ImageApiFailure.unreachable);
    }
    if (response.statusCode != 200) {
      throw ImageApiException(
        ImageApiFailure.serverError,
        statusCode: response.statusCode,
      );
    }
    final Object? body;
    try {
      body = jsonDecode(response.body);
    } on FormatException {
      throw ImageApiException(ImageApiFailure.malformed);
    }
    final url = body is Map<String, Object?> ? body['url'] : null;
    if (url is! String) throw ImageApiException(ImageApiFailure.malformed);
    try {
      final uri = Uri.parse(url);
      if (uri.host != unsplashHost) return uri.toString();
      return uri
          .replace(queryParameters: {...uri.queryParameters, ...imageParams})
          .toString();
    } on FormatException {
      throw ImageApiException(ImageApiFailure.malformed);
    } on ArgumentError {
      // Uri.queryParameters rejects malformed percent-encoding this way.
      throw ImageApiException(ImageApiFailure.malformed);
    }
  }

  void dispose() => _client.close();
}
