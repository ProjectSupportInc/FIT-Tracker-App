# repform_app

FitTracker is a Flutter fitness app with an ESP32 BLE workout flow, sensor-driven calibration, live reps, and locally persisted results. Sign-in and workout prescriptions remain demo/local features.

See [BLE workout setup](docs/BLE_WORKOUT_SETUP.md) for the FreeRTOS firmware flow and recovery behavior. The deferred firmware task-coordination fixes are applied. [The review record](docs/FREERTOS_FIRMWARE_REVIEW.md) explains their resolution.

Start with the [beginner’s guide](docs/BEGINNER_GUIDE.md) for the file map, class/function call relationships, Dart syntax, and an explanation of the live exercise screen. Application source files in `lib/` also contain inline teaching comments.

The earlier pair reported working by the user is committed and tagged in both repositories as `tested-integration-2026-11-21`: mobile `6c3ca04`, firmware `6eabe43`. The current changes add repeat history, durable session recovery, clearer illustrated guidance, hands-free calibration reset and optional offline voice/tones. **Deploy the new app and firmware together: they use protocol version 2.**

Validation: Flutter analysis, 80 app tests, a debug APK build, ESP-IDF build, and firmware host regressions. The new pair has not been flashed or physically tested. The setup guide includes the remaining equipment/radio trials.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
