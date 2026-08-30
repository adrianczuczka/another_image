import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

import 'src/api/image_api.dart';
import 'src/state/random_image_controller.dart';
import 'src/theme/seed_color.dart';
import 'src/ui/home_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Draw behind the system bars on Android 14 and below too; Android 15+
  // enforces this and iOS always has. HomeScreen styles the bar icons.
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  runApp(const AnotherImageApp());
}

/// Extracts a seed color from a loaded image, used to derive the app's
/// light and dark themes. Injectable so tests can avoid real image decoding.
typedef SeedExtractor = Future<Color> Function(String url);

Future<Color> _seedFromNetworkImage(String url) {
  // Shares the disk cache with the CachedNetworkImage widget showing the
  // same URL, so this costs one thumbnail decode, not a second download.
  return seedColorFromImageProvider(
    CachedNetworkImageProvider(url, maxWidth: 112, maxHeight: 112),
  );
}

class AnotherImageApp extends StatefulWidget {
  const AnotherImageApp({
    super.key,
    this.api,
    this.seedExtractor,
    this.cacheManager,
  });

  final ImageApi? api;
  final SeedExtractor? seedExtractor;

  /// Image cache for the screen; null uses the shared disk cache.
  final BaseCacheManager? cacheManager;

  @override
  State<AnotherImageApp> createState() => _AnotherImageAppState();
}

class _AnotherImageAppState extends State<AnotherImageApp>
    with WidgetsBindingObserver {
  static const _fallbackSeed = Color(0xFF5C6BC0);

  late final ImageApi _api = widget.api ?? ImageApi();
  late final RandomImageController _controller = RandomImageController(_api);
  late final SeedExtractor _extractSeed =
      widget.seedExtractor ?? _seedFromNetworkImage;

  Color _seed = _fallbackSeed;
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
    // Re-read platformDispatcher.accessibilityFeatures in build, so
    // mid-session reduce-motion and contrast toggles take effect.
    setState(() {});
  }

  void _onStateChanged() {
    final state = _controller.state;
    if (state is RandomImageLoaded) {
      _updateSeed(state.url);
    }
  }

  Future<void> _updateSeed(String url) async {
    final seq = ++_extractionSeq;
    try {
      final seed = await _extractSeed(url);
      if (!mounted || seq != _extractionSeq) return;
      setState(() => _seed = seed);
    } catch (_) {
      // The image couldn't be decoded (e.g. a dead URL in the API's pool).
      // Keep the previous background rather than surfacing a second error.
    }
  }

  @override
  Widget build(BuildContext context) {
    final features =
        WidgetsBinding.instance.platformDispatcher.accessibilityFeatures;
    final reduceMotion = features.disableAnimations;
    // Both schemes derive from the same seed; the system "increase contrast"
    // setting switches them to their high-contrast variants.
    final contrastLevel = features.highContrast ? 1.0 : 0.0;
    return MaterialApp(
      title: 'Another Image',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.system,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: _seed,
          contrastLevel: contrastLevel,
        ),
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: _seed,
          brightness: Brightness.dark,
          contrastLevel: contrastLevel,
        ),
      ),
      themeAnimationDuration: reduceMotion
          ? Duration.zero
          : const Duration(milliseconds: 600),
      home: HomeScreen(
        controller: _controller,
        cacheManager: widget.cacheManager,
      ),
    );
  }
}
