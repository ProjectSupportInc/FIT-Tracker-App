import 'package:flutter/material.dart';

import '../../../app/app_services.dart';
import '../../../app/fittracker_theme.dart';
import '../../../core/widgets/fit_widgets.dart';
import '../domain/workout_models.dart';
import 'exercise_complete_screen.dart';

class LiveExerciseScreen extends StatefulWidget {
  const LiveExerciseScreen({super.key, required this.workout, required this.exercise});
  final WorkoutPlan workout;
  final ExercisePlan exercise;

  @override
  State<LiveExerciseScreen> createState() => _LiveExerciseScreenState();
}

class _LiveExerciseScreenState extends State<LiveExerciseScreen> {
  bool _exiting = false;
  bool _busy = false;

  Future<bool> _confirmStop() async {
    final answer = await showDialog<bool>(context: context, builder: (dialogContext) => AlertDialog(
      title: const Text('Stop this exercise?'),
      content: const Text('Your exercise will remain incomplete. You can restart it later.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Keep training')),
        FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Stop exercise')),
      ],
    ));
    return answer ?? false;
  }

  Future<void> _stop() async {
    if (!await _confirmStop()) return;
    _exiting = true;
    if (!mounted) return;
    await AppServices.of(context).workouts.stopWithoutSaving();
    if (mounted) Navigator.pop(context);
  }

  Future<void> _finish() async {
    setState(() => _busy = true);
    try {
      final saved = await AppServices.of(context).workouts.finishExercise();
      if (!mounted) return;
      if (!saved) return;
      _exiting = true;
      Navigator.of(context).pushReplacement(MaterialPageRoute<void>(
        builder: (_) => ExerciseCompleteScreen(workout: widget.workout, exercise: widget.exercise)));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to save this exercise. Please try again.')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final vm = AppServices.of(context).workouts;
    return WillPopScope(
      onWillPop: () async {
        if (_exiting) return true;
        final confirmed = await _confirmStop();
        if (confirmed) await vm.stopWithoutSaving();
        return confirmed;
      },
      child: AnimatedBuilder(animation: vm, builder: (context, _) {
        final current = vm.liveReps;
        final target = widget.exercise.targetReps;
        final completed = current >= target;
        final extra = current > target ? current - target : 0;
        return Scaffold(
          appBar: AppBar(
            title: const Text('Live Repetitions'),
            leading: IconButton(onPressed: _stop, icon: const Icon(Icons.close)),
          ),
          body: Padding(
            padding: const EdgeInsets.fromLTRB(24, 22, 24, 25),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(widget.exercise.name, textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w900)),
              const SizedBox(height: 8),
              Center(child: FitBadge(vm.isPaused ? 'Paused' : completed ? 'Target reached · Keep going' : 'Counting reps',
                  highlight: completed, icon: vm.isPaused ? Icons.pause : Icons.bolt)),
              const Spacer(),
              Center(child: SizedBox(
                height: 250, width: 250,
                child: Stack(fit: StackFit.expand, children: [
                  CircularProgressIndicator(value: (current / target).clamp(0.0, 1.0),
                    color: FitColors.lime, backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                    strokeWidth: 17, strokeCap: StrokeCap.round),
                  Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text('$current', style: const TextStyle(fontSize: 86, fontWeight: FontWeight.w900, height: 1)),
                    const SizedBox(height: 5),
                    Text('of $target target reps'),
                    if (extra > 0) ...[
                      const SizedBox(height: 12),
                      FitBadge('+$extra extra reps', highlight: true),
                    ],
                  ])),
                ]),
              )),
              const Spacer(),
              if (vm.connectedDevice != null)
                Center(child: Text('Connected · ${vm.connectedDevice!.id}',
                    style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant))),
              const SizedBox(height: 18),
              OutlinedButton.icon(
                onPressed: _busy ? null : () => vm.togglePause(),
                icon: Icon(vm.isPaused ? Icons.play_arrow : Icons.pause),
                label: Text(vm.isPaused ? 'Resume counting' : 'Pause counting'),
              ),
              const SizedBox(height: 12),
              AccentButton('Finish Exercise',
                icon: Icons.check_circle_outline,
                onPressed: completed && !_busy ? _finish : null),
              const SizedBox(height: 12),
              TextButton(onPressed: _busy ? null : _stop, child: const Text('Stop without completing')),
            ]),
          ),
        );
      }),
    );
  }
}
