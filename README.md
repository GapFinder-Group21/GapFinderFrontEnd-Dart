# gapfinderfrontend_dart

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## Server address

The app reads the address of the server from `API_BASE_URL` (see `lib/core/network/api_config.dart`). It is the only place where the address is written. Without it the app uses our public server (`https://54-226-15-64.sslip.io`), so a normal build already works. Use `--dart-define` only to point to another backend:

```bash
# Debug build for the demo by USB (public server)
flutter run

# Release APK (public server)
flutter build apk --release

# Another backend, for example a local backend from the Android emulator
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8080
```

## Time zone

The free gap reminders are scheduled in Bogotá time (`America/Bogota`, see `lib/services/gap_reminder_service.dart`). The phone must use Bogotá time (UTC-5) for the reminders to ring at the right hour.
