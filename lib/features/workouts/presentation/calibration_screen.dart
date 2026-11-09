import 'package:flutter/material.dart';

import '../../../app/app_services.dart';
import '../../../app/fittracker_theme.dart';
import '../../../core/widgets/fit_widgets.dart';
import '../domain/workout_models.dart';

/// UX placeholder for collecting reference repetitions.
/// Actual calibration values must be produced and persisted by ESP32 firmware.
class CalibrationScreen extends StatefulWidget {
  const CalibrationScreen({super.key, required this.exercise});
  final ExercisePlan exercise;

  @override
  State<CalibrationScreen> createState() => _CalibrationScreenState();
}

class _CalibrationScreenState extends State<CalibrationScreen> {
  int _samples = 0;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Calibrate Movement')),
    body: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SectionHeading('Teach your movement.', subtitle: widget.exercise.name),
        const SizedBox(height: 20),
        const FitCard(child: Text('Perform three steady reference repetitions with the sensor attached securely.')),
        const Spacer(),
        Center(child: SizedBox(
          height: 220, width: 220,
          child: Stack(fit: StackFit.expand, children: [
            CircularProgressIndicator(value: _samples / 3, strokeWidth: 14,
              backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
              color: FitColors.lime, strokeCap: StrokeCap.round),
            Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('$_samples / 3', style: const TextStyle(fontSize: 54, fontWeight: FontWeight.w900)),
              const Text('reference reps'),
            ])),
          ]),
        )),
        const Spacer(),
        if (_samples < 3)
          AccentButton('Record reference rep',
            icon: Icons.add_rounded,
            onPressed: () => setState(() => _samples++))
        else
          AccentButton('Save calibration', icon: Icons.check,
            onPressed: () async {
              try {
                await AppServices.of(context).workouts.saveCalibration(widget.exercise);
                if (context.mounted) Navigator.pop(context);
              } catch (_) {
                if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Unable to save calibration. Please retry.')));
              }
            }),
        const SizedBox(height: 15),
      ]),
    ),
  );
}
