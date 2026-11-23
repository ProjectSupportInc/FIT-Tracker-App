import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../tracker/domain/tracker_status.dart';
import 'exercise_illustration.dart';

/// Visual feedback for the current device state. Animation never advances a
/// stage, fills a calibration checkpoint, or changes the reported rep count.
class WorkoutStageView extends StatefulWidget {
  const WorkoutStageView({
    super.key,
    required this.status,
    required this.repetitions,
    required this.target,
    this.disconnected = false,
    this.readyToSave = false,
    this.animate = true,
    this.exerciseKind = "curl",
    this.interrupted = false,
  });

  final TrackerStatus? status;
  final int repetitions;
  final int target;
  final bool disconnected;
  final bool readyToSave;
  final bool animate;
  final String exerciseKind;
  final bool interrupted;

  @override
  State<WorkoutStageView> createState() => _WorkoutStageViewState();
}

enum _Phase {
  pickup,
  hold,
  calibration,
  counting,
  paused,
  disconnected,
  error,
  finished,
  waiting
}

class _WorkoutStageViewState extends State<WorkoutStageView>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _motion;
  bool _reduceMotion = false;
  bool _foreground = true;
  _Phase? _animatedPhase;

  _Phase get _phase {
    if (widget.interrupted) return _Phase.error;
    if (widget.readyToSave) return _Phase.finished;
    if (widget.disconnected) return _Phase.disconnected;
    return switch (widget.status?.state) {
      TrackerState.waitPickup => _Phase.pickup,
      TrackerState.settling => _Phase.hold,
      TrackerState.calibrating => _Phase.calibration,
      TrackerState.running => _Phase.counting,
      TrackerState.paused => _Phase.paused,
      TrackerState.error => _Phase.error,
      TrackerState.finished => _Phase.finished,
      _ => _Phase.waiting,
    };
  }

  @override
  void initState() {
    super.initState();
    _motion = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1800));
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    _syncMotion();
  }

  @override
  void didUpdateWidget(covariant WorkoutStageView oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncMotion();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _syncMotion();
  }

  void _syncMotion() {
    final phase = _phase;
    final preparing = phase == _Phase.pickup ||
        phase == _Phase.hold ||
        phase == _Phase.calibration;
    if (preparing &&
        widget.animate &&
        !_reduceMotion &&
        _foreground &&
        TickerMode.valuesOf(context).enabled) {
      if (!_motion.isAnimating || _animatedPhase != phase) {
        _motion.duration =
            Duration(milliseconds: phase == _Phase.hold ? 2400 : 1800);
        _motion.repeat();
        _animatedPhase = phase;
      }
    } else {
      _motion.stop();
      _motion.value = 0;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final phase = _phase;
    final learned = (widget.status?.calibrationReps ?? 0).clamp(0, 3);
    final targetReached = widget.repetitions >= widget.target;
    final justLearned = phase == _Phase.counting && widget.repetitions == 3;
    final title = switch (phase) {
      _Phase.pickup => 'Take your starting position',
      _Phase.hold => 'Hold this position',
      _Phase.calibration =>
        learned == 0 ? 'Begin three controlled reps' : 'Rep $learned recorded',
      _Phase.counting => targetReached
          ? 'Target reached'
          : justLearned
              ? 'Ready. Keep going.'
              : 'Keep it going',
      _Phase.paused => 'Workout paused',
      _Phase.disconnected => 'Connection lost',
      _Phase.error =>
        widget.interrupted ? 'Session interrupted' : 'Check your tracker',
      _Phase.finished => targetReached ? 'Set complete' : 'Session ended',
      _Phase.waiting => 'Waiting for your tracker',
    };
    final instruction = switch (phase) {
      _Phase.pickup => widget.exerciseKind.contains('push')
          ? 'Get into your push-up position.'
          : widget.exerciseKind.contains('squat')
              ? 'Stand ready for your first squat.'
              : 'Take the weight or handles and get ready.',
      _Phase.hold => widget.exerciseKind.contains('push')
          ? 'Keep your body still until the start cue.'
          : 'Keep the weight steady until the start cue.',
      _Phase.calibration => learned == 3
          ? 'Calibration complete. Your first three reps count.'
          : learned == 0
              ? 'Return to the start and pause briefly after each rep.'
              : learned == 1
                  ? 'Repeat the same movement.'
                  : 'Repeat once more.',
      _Phase.counting => targetReached
          ? 'Finish when you’re ready, or keep going.'
          : justLearned
              ? 'Your first three reps count. Keep going.'
              : '${widget.target - widget.repetitions} more to your goal.',
      _Phase.paused => 'Take a breath. Resume when you’re ready.',
      _Phase.disconnected => 'Showing your last confirmed count.',
      _Phase.error => widget.interrupted
          ? 'Your last confirmed reps are available to keep.'
          : 'Rest the equipment and check the tracker.',
      _Phase.finished => widget.readyToSave
          ? 'Save your result to finish.'
          : 'Your tracker has stopped counting.',
      _Phase.waiting => 'Your workout will appear here when it’s ready.',
    };
    final preparing = phase == _Phase.pickup ||
        phase == _Phase.hold ||
        phase == _Phase.calibration;
    final duration =
        _reduceMotion ? Duration.zero : const Duration(milliseconds: 300);
    final announcement = preparing
        ? '$title. $instruction${phase == _Phase.calibration ? ' $learned of 3 calibration reps recorded.' : ''}'
        : '$title. ${widget.repetitions} repetitions, goal ${widget.target}. $instruction';

    return Semantics(
      container: true,
      liveRegion: true,
      label: announcement,
      child: ExcludeSemantics(
          child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AnimatedSwitcher(
            duration: duration,
            child: Column(key: ValueKey('$phase-$title'), children: [
              Text(title,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineMedium?.copyWith(
                      fontSize: 30,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.7)),
              const SizedBox(height: 10),
              Text(instruction,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyLarge?.copyWith(
                      fontSize: 18, color: theme.colorScheme.onSurfaceVariant)),
            ]),
          ),
          const SizedBox(height: 28),
          if (preparing) _movementCue(phase) else _repCounter(phase, duration),
          if (phase == _Phase.calibration) ...[
            const SizedBox(height: 24),
            _calibrationCheckpoints(learned, duration),
            const SizedBox(height: 12),
            Text('$learned of 3 reps recorded',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium),
          ],
          const SizedBox(height: 12),
        ],
      )),
    );
  }

  /// A floating weight cues pickup/reps; a stationary hand with a breathing halo
  /// cues stillness. Neither animation estimates sensor progress or a countdown.
  Widget _movementCue(_Phase phase) {
    final color = Theme.of(context).colorScheme.primary;
    return Center(
        child: RepaintBoundary(
            child: SizedBox.square(
      dimension: 230,
      child: AnimatedBuilder(
          animation: _motion,
          builder: (context, _) {
            final wave = (1 - math.cos(_motion.value * 2 * math.pi)) / 2;
            final hold = phase == _Phase.hold;
            return Stack(alignment: Alignment.center, children: [
              Transform.scale(
                scale: hold ? 1 + wave * 0.06 : 1,
                child: Container(
                    width: 204,
                    height: 204,
                    decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: color.withValues(
                            alpha: 0.06 + (hold ? wave * 0.04 : 0)),
                        border: Border.all(
                            color: color.withValues(alpha: 0.2), width: 2))),
              ),
              if (!hold)
                Positioned(
                    bottom: 35,
                    child: Transform.scale(
                        scaleX: 1 - wave * 0.15,
                        child: Container(
                            width: 86,
                            height: 10,
                            decoration: BoxDecoration(
                                color: color.withValues(alpha: 0.13),
                                borderRadius: BorderRadius.circular(50))))),
              Transform.translate(
                key: const ValueKey('movement-cue'),
                offset: Offset(0, hold ? 0 : -8 - wave * 18),
                child: hold
                    ? Icon(Icons.pan_tool_outlined, size: 78, color: color)
                    : ExerciseIllustration(
                        kind: widget.exerciseKind, motion: wave, color: color),
              ),
              if (!hold)
                Positioned(
                    right: 24,
                    top: 65,
                    child: Icon(Icons.unfold_more_rounded,
                        size: 32, color: color.withValues(alpha: 0.6))),
            ]);
          }),
    )));
  }

  Widget _calibrationCheckpoints(int completed, Duration duration) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var rep = 1; rep <= 3; rep++)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 9),
            child: TweenAnimationBuilder<double>(
              key: ValueKey('calibration-$rep-${rep <= completed}'),
              tween: Tween(begin: rep <= completed ? 0.82 : 1, end: 1),
              duration: duration,
              curve: Curves.easeOutBack,
              builder: (_, scale, child) =>
                  Transform.scale(scale: scale, child: child),
              child: SizedBox.square(
                  dimension: 54,
                  child: Stack(
                    clipBehavior: Clip.none,
                    alignment: Alignment.center,
                    children: [
                      Container(
                          decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: rep <= completed
                                  ? colors.primary
                                  : colors.surfaceContainerHighest,
                              border: Border.all(
                                  color: rep == completed + 1
                                      ? colors.primary
                                      : colors.outlineVariant,
                                  width: rep == completed + 1 ? 2 : 1))),
                      Text('$rep',
                          style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                              color: rep <= completed
                                  ? colors.onPrimary
                                  : colors.onSurface)),
                      if (rep <= completed)
                        Positioned(
                            right: -3,
                            top: -3,
                            child: DecoratedBox(
                                decoration: BoxDecoration(
                                    color: colors.surface,
                                    shape: BoxShape.circle),
                                child: Icon(Icons.check_circle_rounded,
                                    color: colors.primary, size: 20))),
                    ],
                  )),
            ),
          ),
      ],
    );
  }

  Widget _repCounter(_Phase phase, Duration duration) {
    final colors = Theme.of(context).colorScheme;
    final active = phase == _Phase.counting;
    final fraction = widget.target > 0
        ? (widget.repetitions / widget.target).clamp(0.0, 1.0)
        : 0.0;
    final extra = widget.repetitions - widget.target;
    return Column(children: [
      SizedBox.square(
        dimension: 260,
        child: Stack(alignment: Alignment.center, children: [
          Positioned.fill(
              child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: fraction),
            duration: duration,
            builder: (_, progress, __) => CircularProgressIndicator(
                value: progress,
                strokeWidth: 13,
                strokeCap: StrokeCap.round,
                color: active || widget.readyToSave
                    ? colors.primary
                    : colors.outline,
                backgroundColor: colors.surfaceContainerHighest),
          )),
          Padding(
            padding: const EdgeInsets.all(34),
            child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (phase == _Phase.paused ||
                        phase == _Phase.disconnected ||
                        phase == _Phase.error)
                      Icon(
                          phase == _Phase.paused
                              ? Icons.pause_rounded
                              : phase == _Phase.error
                                  ? Icons.sensors_off
                                  : Icons.bluetooth_disabled,
                          color: colors.onSurfaceVariant,
                          size: 28),
                    AnimatedSwitcher(
                      duration: active ? duration : Duration.zero,
                      transitionBuilder: (child, animation) => FadeTransition(
                          opacity: animation,
                          child: ScaleTransition(
                              scale: Tween(begin: 0.8, end: 1.0).animate(
                                  CurvedAnimation(
                                      parent: animation,
                                      curve: Curves.easeOutBack)),
                              child: child)),
                      child: Text('${widget.repetitions}',
                          key: ValueKey('rep-${widget.repetitions}'),
                          style: const TextStyle(
                              fontSize: 88,
                              height: 1.1,
                              fontWeight: FontWeight.w900)),
                    ),
                    const SizedBox(height: 4),
                    Text('of ${widget.target} reps',
                        style: TextStyle(
                            fontSize: 18, color: colors.onSurfaceVariant)),
                  ],
                )),
          ),
        ]),
      ),
      if (extra > 0) ...[
        const SizedBox(height: 18),
        Text('+$extra extra ${extra == 1 ? 'rep' : 'reps'}',
            style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w700,
                color: colors.primary)),
      ],
    ]);
  }
}
