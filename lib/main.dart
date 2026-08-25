import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'src/api/image_api.dart';
import 'src/state/random_image_controller.dart';
import 'src/ui/home_screen.dart';

void main() {
  runApp(const AnotherImageApp());
}

/// Builds a [ColorScheme] from a loaded image, used to tint the app
/// background. Injectable so tests can avoid real image decoding.
typedef SchemeExtractor = Future<ColorScheme> Function(
  String url,
  Brightness brightness,
);

Future<ColorScheme> _schemeFromNetworkImage(
  String url,
  Brightness brightness,
) {
  // Shares the disk cache with the CachedNetworkImage widget showing the
  // same URL, so this costs a decode, not a second download.
  return ColorScheme.fromImageProvider(
    provider: CachedNetworkImageProvider(url),
    brightness: brightness,
  );
}

class AnotherImageApp extends StatefulWidget {
  const AnotherImageApp({super.key, this.api, this.schemeExtractor});

  final ImageApi? api;
  final SchemeExtractor? schemeExtractor;

  @override
  State<AnotherImageApp> createState() => _AnotherImageAppState();
}

class _AnotherImageAppState extends State<AnotherImageApp>
    with WidgetsBindingObserver {
  static const _fallbackSeed = Color(0xFF5C6BC0);

  late final ImageApi _api = widget.api ?? ImageApi();
  late final RandomImageController _controller = RandomImageController(_api);
  late final SchemeExtractor _extractScheme =
      widget.schemeExtractor ?? _schemeFromNetworkImage;

  ColorScheme? _lightScheme;
  ColorScheme? _darkScheme;
  int _extractionSeq = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller.addListener(_onStateChanged);
    _controller.fetch();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.removeListener(_onStateChanged);
    _controller.dispose();
    _api.dispose();
    super.dispose();
  }

  @override
  void didChangeAccessibilityFeatures() {
    // Re-read platformDispatcher.accessibilityFeatures in build, so a
    // mid-session reduce-motion toggle takes effect.
    setState(() {});
  }

  void _onStateChanged() {
    final state = _controller.state;
    if (state is RandomImageLoaded) {
      _updateSchemes(state.url);
    }
  }

  Future<void> _updateSchemes(String url) async {
    final seq = ++_extractionSeq;
    try {
      final light = await _extractScheme(url, Brightness.light);
      final dark = await _extractScheme(url, Brightness.dark);
      if (!mounted || seq != _extractionSeq) return;
      setState(() {
        _lightScheme = light;
        _darkScheme = dark;
      });
    } catch (_) {
      // The image couldn't be decoded (e.g. a dead URL in the API's pool).
      // Keep the previous background rather than surfacing a second error.
    }
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = WidgetsBinding
        .instance.platformDispatcher.accessibilityFeatures.disableAnimations;
    return MaterialApp(
      title: 'Another Image',
      themeMode: ThemeMode.system,
      theme: ThemeData(
        colorScheme:
            _lightScheme ?? ColorScheme.fromSeed(seedColor: _fallbackSeed),
      ),
      darkTheme: ThemeData(
        colorScheme: _darkScheme ??
            ColorScheme.fromSeed(
              seedColor: _fallbackSeed,
              brightness: Brightness.dark,
            ),
      ),
      themeAnimationDuration:
          reduceMotion ? Duration.zero : const Duration(milliseconds: 600),
      home: HomeScreen(controller: _controller),
    );
  }
}
