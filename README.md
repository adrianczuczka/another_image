# Another Image

A single-screen Flutter app that fetches a random image from an API and shows it as a centered square. The app theme is derived from the current image, so the background and button colors shift with every photo.

## Demo

- [iOS – iPhone 17 simulator](demo/ios.mp4)
- [Android – Pixel 8 emulator, Android 16](demo/android.mp4)

Both clips show a cold start, several taps of "Another" in light mode, a switch to dark mode, and more taps. The Android clip also shows the error panel for one of the API's dead image URLs.

## Features

- Centered square image with rounded corners, cropped server-side to match the display. In landscape the button moves beside the square instead of below it.
- Dynamic theming: after each image loads, a Material 3 seed color is extracted from it (the same quantize-and-score pipeline as `ColorScheme.fromImageProvider`, run once at thumbnail size for both the light and dark schemes), and the background animates to the new palette.
- "Another" button that fetches a fresh image, with a determinate download progress indicator.
- Error handling for both API failures and broken image URLs, each with an inline retry and a 10-second request timeout.
- System light and dark mode – both schemes are seeded from the same image.
- Accessibility: semantic labels on the image, button, and loading states; a screen-reader announcement when a new image loads and a live-region error panel; animations are disabled when the system reduce-motion setting is on; the error panel scrolls instead of overflowing at large font scales.

## Architecture

```
lib/
  main.dart                              – app root, theme extraction and wiring
  src/api/image_api.dart                 – HTTP client for GET /image
  src/state/random_image_controller.dart – ChangeNotifier with loading/loaded/error states
  src/theme/seed_color.dart              – seed color extraction from a decoded image
  src/ui/home_screen.dart                – the single screen
```

The controller and API client are plain classes with injected dependencies, covered by unit tests. The widget layer listens to the controller with `ListenableBuilder`.

## API notes

Things the implementation accounts for, found by probing the endpoint:

- `GET /image` answers with a 307 redirect to `/image/`, so the client calls the trailing-slash path directly.
- The API serves a small rotating pool of URLs and often returns the same URL twice in a row. The controller re-rolls up to two times when it receives the URL that's already on screen, so tapping "Another" doesn't look like a no-op.
- Three of the ~20 URLs in the pool are dead Unsplash links (HTTP 404), so roughly one draw in seven hits a broken image – presumably by design. The image widget falls back to an error panel with a retry action, and theme extraction failures are non-fatal. Fetch errors and image-load errors are distinct states with distinct copy.
- The API returns bare Unsplash URLs that resolve to multi-MB originals. The client merges imgix parameters (`w=1200&h=1200&fit=crop&q=80&fm=jpg`) into the URL – preserving any parameters already present – to download a phone-sized square crop instead.

Images are cached on disk by `cached_network_image`; theme extraction reads from the same cache, so each image is downloaded once.

## Run

```sh
flutter pub get
flutter run
```

## Test

```sh
flutter test
```

Covers API response parsing and error mapping, the controller state machine including the duplicate re-roll, and widget-level fetch and error-retry flows.
