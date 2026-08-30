import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

import 'src/api/image_api.dart';
import 'src/state/random_image_controller.dart';
import 'src/state/theme_seed_controller.dart';
import 'src/theme/seed_color.dart';
import 'src/ui/home_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Draw behind the system bars on Android 14 and below too; Android 15+
  // enforces this and iOS always has. HomeScreen styles the bar icons.
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  runApp(const AnotherImageApp());
}

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

  /// Collaborators are injectable for tests; null means the real one.
  final ImageApi? api;
  final SeedExtractor? seedExtractor;

  /// Image cache for the screen; null uses the shared disk cache.
  final BaseCacheManager? cacheManager;

  @override
  State<AnotherImageApp> createState() => _AnotherImageAppState();
}

class _AnotherImageAppState extends State<AnotherImageApp>
    with WidgetsBindingObserver {
  // Read once; rebuilding AnotherImageApp with different arguments isn't
  // supported (only tests pass any).
  late final ImageApi _api = widget.api ?? ImageApi();
  late final RandomImageController _images = RandomImageController(_api);
  late final ThemeSeedController _themeSeed = ThemeSeedController(
    _images,
    widget.seedExtractor ?? _seedFromNetworkImage,
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _images.fetch();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _themeSeed.dispose();
    _images.dispose();
    if (widget.api == null) _api.dispose(); // Only what this widget created.
    super.dispose();
  }

  @override
  void didChangeAccessibilityFeatures() {
    // Re-read platformDispatcher.accessibilityFeatures in build, so
    // mid-session reduce-motion and contrast toggles take effect.
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final features =
        WidgetsBinding.instance.platformDispatcher.accessibilityFeatures;
    final reduceMotion = features.disableAnimations;
    // Both schemes derive from the same seed; the system "increase contrast"
    // setting switches them to their high-contrast variants.
    final contrastLevel = features.highContrast ? 1.0 : 0.0;
    return ListenableBuilder(
      listenable: _themeSeed,
      builder: (context, _) => MaterialApp(
        title: 'Another Image',
        debugShowCheckedModeBanner: false,
        themeMode: ThemeMode.system,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: _themeSeed.seed,
            contrastLevel: contrastLevel,
          ),
        ),
        darkTheme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: _themeSeed.seed,
            brightness: Brightness.dark,
            contrastLevel: contrastLevel,
          ),
        ),
        themeAnimationDuration:
            reduceMotion ? Duration.zero : const Duration(milliseconds: 600),
        home: HomeScreen(
          controller: _images,
          cacheManager: widget.cacheManager,
        ),
      ),
    );
  }
}
