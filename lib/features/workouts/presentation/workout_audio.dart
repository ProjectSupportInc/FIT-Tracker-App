import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/widgets/fit_widgets.dart';
import '../../tracker/domain/tracker_status.dart';
import 'workout_view_model.dart';

enum WorkoutAudioMode { voice, tones, muted }

/// Announces device transitions once; ordinary heartbeats never replay a cue.
class WorkoutAudio extends ChangeNotifier {
  WorkoutAudio(this.workouts, {MethodChannel? channel})
      : _channel = channel ?? const MethodChannel('fittracker/workout_audio') {
    workouts.addListener(_update);
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'availability' && !_disposed) {
        voiceAvailable = call.arguments == true;
        notifyListeners();
      }
    });
    unawaited(_load());
  }
  final WorkoutViewModel workouts;
  final MethodChannel _channel;
  WorkoutAudioMode mode = WorkoutAudioMode.voice;
  bool speakReps = false;
  bool voiceAvailable = false;
  bool _foreground = true, _disposed = false, _active = false;
  bool _visible = false;
  bool _wasDisconnected = false;
  String? _session, _lastCue;
  TrackerState? _state;
  int _reps = 0, _calibration = 0;

  Future<dynamic> _invoke(String method, [Object? arguments]) async {
    try {
      return await _channel.invokeMethod<dynamic>(method, arguments);
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  Future<void> _load() async {
    final settings = await _invoke('getSettings');
    if (_disposed || settings is! Map) return;
    mode = WorkoutAudioMode.values.firstWhere((m) => m.name == settings['mode'],
        orElse: () => WorkoutAudioMode.voice);
    speakReps = settings['speakReps'] == true;
    voiceAvailable = settings['voiceAvailable'] == true;
    notifyListeners();
  }

  Future<void> setPreferences({WorkoutAudioMode? mode, bool? speakReps}) async {
    this.mode = mode ?? this.mode;
    this.speakReps = speakReps ?? this.speakReps;
    await _invoke('stop');
    await _invoke(
        'setSettings', {'mode': this.mode.name, 'speakReps': this.speakReps});
    if (!_disposed) notifyListeners();
  }

  Future<void> preview() =>
      _cue('Get ready. Hold your starting position.', 'ready');

  Future<void> _cue(String? text, String tone) async {
    if (!_foreground || mode == WorkoutAudioMode.muted) return;
    await _invoke('cue', {'text': text, 'tone': tone, 'mode': mode.name});
  }

  void setWorkoutVisible(bool value) {
    _visible = value;
    _update();
  }

  void setForeground(bool value) {
    _foreground = value;
    if (!value) unawaited(_invoke('stop'));
    _update();
  }

  void _update() {
    if (_disposed) return;
    final active = workouts.hasActiveSession && _foreground && _visible;
    if (active != _active) {
      _active = active;
      unawaited(_invoke('setActive', active));
    }
    final session = workouts.activeAttemptId;
    if (session != _session) {
      _session = session;
      _lastCue = null;
      _state = null;
      _reps = 0;
      _calibration = 0;
      _wasDisconnected = false;
    }
    if (!active) {
      unawaited(_invoke('stop'));
      return;
    }
    final status = workouts.trackerStatus;
    final key =
        '${workouts.isDisconnected}:${workouts.sessionInvalid}:${status?.state}:${status?.calibrationReps}:${workouts.liveReps}';
    if (key == _lastCue) return;
    _lastCue = key;
    if (workouts.sessionInvalid) {
      unawaited(_cue('Session interrupted. Check your tracker.', 'error'));
      return;
    }
    if (workouts.isDisconnected) {
      _wasDisconnected = true;
      unawaited(_cue('Connection lost. Rest the equipment.', 'error'));
      return;
    }
    if (status == null) return;
    String? text = _wasDisconnected ? 'Tracker reconnected.' : null;
    _wasDisconnected = false;
    var tone = 'ready';
    if (status.event == TrackerEvent.calibrationReset && _calibration > 0) {
      text = 'Calibration reset. Take your starting position.';
      tone = 'reset';
    } else if (status.state != _state) {
      text = switch (status.state) {
        TrackerState.waitPickup => 'Take your starting position.',
        TrackerState.settling => 'Hold this position.',
        TrackerState.calibrating =>
          'Begin three controlled reps. Pause briefly between reps.',
        TrackerState.running => workouts.liveReps == 3
            ? 'Ready. Three reps counted. Keep going.'
            : 'Continue your set.',
        TrackerState.paused => 'Workout paused.',
        TrackerState.finished => 'Set ended.',
        TrackerState.error => 'Tracker problem. Rest the equipment.',
        TrackerState.idle => null,
      };
      if (status.state == TrackerState.error) tone = 'error';
    }
    if (status.state == TrackerState.calibrating &&
        status.calibrationReps > _calibration) {
      text = switch (status.calibrationReps) {
        1 => 'One recorded. Repeat the same movement.',
        2 => 'Two recorded. Repeat once more.',
        _ => 'Three recorded.',
      };
    }
    final target = workouts.activeExercise!.targetReps;
    final counted =
        status.state == TrackerState.running && workouts.liveReps > _reps;
    if (counted && workouts.liveReps >= target && _reps < target) {
      text = 'Target reached. Finish when you are ready.';
    } else if (counted && _state == TrackerState.running) {
      text = speakReps ? '${workouts.liveReps}' : null;
      tone = 'rep';
    }
    _state = status.state;
    _calibration = status.calibrationReps;
    _reps = workouts.liveReps;
    if (text != null || counted) unawaited(_cue(text, tone));
  }

  @override
  void dispose() {
    _disposed = true;
    workouts.removeListener(_update);
    _channel.setMethodCallHandler(null);
    unawaited(_invoke('stop'));
    unawaited(_invoke('setActive', false));
    super.dispose();
  }
}

class WorkoutAudioSettings extends StatelessWidget {
  const WorkoutAudioSettings({super.key, required this.audio});
  final WorkoutAudio audio;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: audio,
      builder: (context, _) => FitCard(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Workout guidance',
                      style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 12),
                  DropdownButton<WorkoutAudioMode>(
                      value: audio.mode,
                      isExpanded: true,
                      onChanged: (mode) {
                        if (mode != null) audio.setPreferences(mode: mode);
                      },
                      items: const [
                        DropdownMenuItem(
                            value: WorkoutAudioMode.voice,
                            child: Text('Voice and tones')),
                        DropdownMenuItem(
                            value: WorkoutAudioMode.tones,
                            child: Text('Tones only')),
                        DropdownMenuItem(
                            value: WorkoutAudioMode.muted,
                            child: Text('Muted')),
                      ]),
                  SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Speak rep counts'),
                      value: audio.speakReps,
                      onChanged: audio.mode == WorkoutAudioMode.voice
                          ? (value) => audio.setPreferences(speakReps: value)
                          : null),
                  if (audio.mode == WorkoutAudioMode.voice &&
                      !audio.voiceAvailable)
                    const Text(
                        'An offline English voice is unavailable. Tones will play instead.'),
                  const Text(
                      'Use your phone’s media volume. Guidance also plays through connected headphones.'),
                  TextButton.icon(
                      onPressed: audio.mode == WorkoutAudioMode.muted
                          ? null
                          : audio.preview,
                      icon: const Icon(Icons.volume_up_outlined),
                      label: const Text('Test sound')),
                ]),
          ));
}

Future<void> showWorkoutHelp(BuildContext context, WorkoutAudio? audio) =>
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
          child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (audio != null) WorkoutAudioSettings(audio: audio),
          const SizedBox(height: 20),
          Text('Need to restart calibration?',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          const Text(
              'After a mistaken calibration rep, return the equipment to rest and leave it still for eight seconds. '
              'The tracker clears the calibration and waits for you to take your starting position again. '
              'Long rests also reset unfinished calibration. Your normal workout count is never cleared this way.'),
          const SizedBox(height: 12),
          const Text(
              'Keep the tracker on the moving weight or equipment. For bodyweight exercises, it must move with your body; '
              'check counting accuracy for that placement before relying on it.'),
        ]),
      )),
    );
