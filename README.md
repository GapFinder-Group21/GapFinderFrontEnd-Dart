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

The app reads the address of the server from `API_BASE_URL` (see `lib/core/network/api_config.dart`). It is the only place where the address is written. Without it the app uses a placeholder that never answers, so always pass the real address:

```bash
# Debug build for the demo by USB
flutter run --dart-define=API_BASE_URL=https://<domain>

# Release APK
flutter build apk --release --dart-define=API_BASE_URL=https://<domain>
```

## Time zone

The free gap reminders are scheduled in Bogotá time (`America/Bogota`, see `lib/services/gap_reminder_service.dart`). The phone must use Bogotá time (UTC-5) for the reminders to ring at the right hour.
