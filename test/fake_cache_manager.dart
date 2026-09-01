import 'dart:async';
import 'dart:io' as io;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file/file.dart';
import 'package:file/local.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_test/flutter_test.dart';

/// Stands in for the disk cache so widget tests never touch the network or
/// platform channels.
///
/// Without an [imageFile], every load stays pending forever, which keeps the
/// image widget in its progress state. With one, URLs containing "dead" fail
/// the way a 404 does, URLs in [pendingUrls] stall forever, and every other
/// URL is served the file. Loading an actual file needs real async, so tests
/// using it run inside [WidgetTester.runAsync].
class FakeCacheManager implements BaseCacheManager {
  FakeCacheManager({this.imageFile, this.pendingUrls = const {}});

  final File? imageFile;

  /// URLs whose loads never complete, as if the download stalled.
  final Set<String> pendingUrls;

  @override
  Stream<FileResponse> getFileStream(
    String url, {
    String? key,
    Map<String, String>? headers,
    bool withProgress = false,
  }) {
    final file = imageFile;
    if (file == null || pendingUrls.contains(url)) {
      return StreamController<FileResponse>().stream;
    }
    if (url.contains('dead')) {
      return Stream.error(Exception('HTTP 404 for $url'));
    }
    return Stream.value(
      FileInfo(
        file,
        FileSource.Online,
        DateTime.now().add(const Duration(days: 1)),
        url,
      ),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

/// A [size]×[size] PNG filled with [color].
Future<Uint8List> solidPng(ui.Color color, {int size = 8}) async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawRect(
    ui.Rect.fromLTWH(0, 0, size.toDouble(), size.toDouble()),
    ui.Paint()..color = color,
  );
  final image = await recorder.endRecording().toImage(size, size);
  try {
    return (await image.toByteData(
      format: ui.ImageByteFormat.png,
    ))!.buffer.asUint8List();
  } finally {
    image.dispose();
  }
}

/// [solidPng] written to a temp file.
Future<File> solidImageFile(ui.Color color, {int size = 8}) async {
  final bytes = await solidPng(color, size: size);
  final dir = await io.Directory.systemTemp.createTemp('another_image_test');
  final path = '${dir.path}/image.png';
  await io.File(path).writeAsBytes(bytes);
  return const LocalFileSystem().file(path);
}

/// Pumps frames while real time passes until [done] holds. For use inside
/// [WidgetTester.runAsync], where image decoding completes asynchronously.
Future<void> settle(WidgetTester tester, bool Function() done) async {
  for (var i = 0; i < 500 && !done(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(done(), isTrue, reason: 'Condition not met within 10 s');
}
