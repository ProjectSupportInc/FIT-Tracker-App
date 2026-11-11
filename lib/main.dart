// Starts the app: Flutter calls main(), which installs FitTrackerApp as the root widget.
// Read docs/BEGINNER_GUIDE.md for the app flow and Dart syntax explanations.
// Entry point: launched by Flutter (also imported by tests where applicable).

import 'package:flutter/material.dart';

import 'app/fittracker_app.dart';

/// Application entry point called by the Flutter runtime; initializes bindings and runs the root widget.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const FitTrackerApp());
}
