import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../state/random_image_controller.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.controller});

  final RandomImageController controller;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final state = controller.state;
        return Scaffold(
          backgroundColor: colorScheme.primaryContainer,
          body: SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: AspectRatio(
                        aspectRatio: 1,
                        child: _ImageSquare(state: state, onRetry: controller.fetch),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 32),
                  child: FilledButton(
                    onPressed:
                        state is RandomImageLoading ? null : controller.fetch,
                    child: const Text(
                      'Another',
                      semanticsLabel: 'Load another random image',
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ImageSquare extends StatelessWidget {
  const _ImageSquare({required this.state, required this.onRetry});

  final RandomImageState state;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final fadeDuration =
        reduceMotion ? Duration.zero : const Duration(milliseconds: 400);
    return AnimatedSwitcher(
      duration: reduceMotion ? Duration.zero : const Duration(milliseconds: 250),
      // The default layout builder loosens constraints, letting the image
      // take its natural aspect ratio; expand children to keep the square.
      layoutBuilder: (currentChild, previousChildren) => Stack(
        fit: StackFit.expand,
        children: [...previousChildren, ?currentChild],
      ),
      child: switch (state) {
        RandomImageLoading() => const Center(
            child: CircularProgressIndicator(
              semanticsLabel: 'Loading a new image',
            ),
          ),
        RandomImageError(:final message) =>
          _ErrorPanel(message: message, onRetry: onRetry),
        RandomImageLoaded(:final url) => Semantics(
            image: true,
            label: 'Random photo from Unsplash',
            child: ClipRRect(
              key: ValueKey(url),
              borderRadius: BorderRadius.circular(24),
              child: CachedNetworkImage(
                imageUrl: url,
                fit: BoxFit.cover,
                fadeInDuration: fadeDuration,
                fadeOutDuration: fadeDuration,
                progressIndicatorBuilder: (context, _, progress) => Center(
                  child: CircularProgressIndicator(
                    value: progress.progress,
                    semanticsLabel: 'Downloading image',
                  ),
                ),
                errorWidget: (context, _, error) => _ErrorPanel(
                  message: "This image couldn't be loaded",
                  onRetry: onRetry,
                ),
              ),
            ),
          ),
      },
    );
  }
}

class _ErrorPanel extends StatelessWidget {
  const _ErrorPanel({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(24),
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.broken_image_outlined,
            size: 48,
            color: colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 16),
          Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          TextButton(onPressed: onRetry, child: const Text('Try again')),
        ],
      ),
    );
  }
}
