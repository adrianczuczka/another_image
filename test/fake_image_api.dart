import 'dart:async';

import 'package:another_image/src/api/image_api.dart';

/// Returns queued results in order: a String resolves, an [Exception] is
/// thrown, and a [Completer] defers until the test completes it.
class FakeImageApi implements ImageApi {
  FakeImageApi(this.results);

  final List<Object> results;
  int calls = 0;

  @override
  Future<String> fetchRandomImageUrl() {
    final result = results[calls++];
    if (result is Completer<String>) return result.future;
    if (result is Exception) return Future.error(result);
    return Future.value(result as String);
  }

  @override
  void dispose() {}
}
