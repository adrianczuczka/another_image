import 'package:another_image/src/api/image_api.dart';
import 'package:another_image/src/state/random_image_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Returns queued results in order; a queued [ImageApiException] is thrown.
class FakeImageApi extends ImageApi {
  FakeImageApi(this.results)
      : super(client: MockClient((_) async => http.Response('', 500)));

  final List<Object> results;
  int calls = 0;

  @override
  Future<String> fetchRandomImageUrl() async {
    final result = results[calls++];
    if (result is ImageApiException) throw result;
    return result as String;
  }
}

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
    final controller =
        RandomImageController(FakeImageApi([ImageApiException('down')]));

    await controller.fetch();

    expect((controller.state as RandomImageError).message, 'down');
  });

  test('re-rolls when the API returns the current URL again', () async {
    final api = FakeImageApi(['url-a', 'url-a', 'url-b']);
    final controller = RandomImageController(api);

    await controller.fetch();
    await controller.fetch();

    expect((controller.state as RandomImageLoaded).url, 'url-b');
    expect(api.calls, 3);
  });

  test('gives up re-rolling after the retry cap and keeps the duplicate',
      () async {
    final api = FakeImageApi(['url-a', 'url-a', 'url-a', 'url-a', 'url-a']);
    final controller = RandomImageController(api);

    await controller.fetch();
    await controller.fetch();

    // Second fetch: 1 initial attempt + maxDuplicateRetries re-rolls.
    expect(api.calls, 2 + RandomImageController.maxDuplicateRetries);
    expect((controller.state as RandomImageLoaded).url, 'url-a');
  });

  test('recovers from error on the next fetch', () async {
    final controller = RandomImageController(
      FakeImageApi([ImageApiException('down'), 'url-a']),
    );

    await controller.fetch();
    expect(controller.state, isA<RandomImageError>());

    await controller.fetch();
    expect((controller.state as RandomImageLoaded).url, 'url-a');
  });
}
