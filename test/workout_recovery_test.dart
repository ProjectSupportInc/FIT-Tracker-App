import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:repform_app/core/utils/date_labels.dart';
import 'package:repform_app/features/tracker/domain/tracker_status.dart';
import 'package:repform_app/features/workouts/data/local_workout_repository.dart';
import 'package:repform_app/features/workouts/domain/workout_journal.dart';
import 'package:repform_app/features/workouts/domain/workout_models.dart';
import 'package:repform_app/features/workouts/presentation/workout_view_model.dart';

import 'workout_view_model_test.dart' show TestTracker;

class _Tracker extends TestTracker {
  int pauseCalls = 0;
  bool loseStartReply = false;
  @override
  Future<void> pauseCounting() async {
    pauseCalls++;
    await super.pauseCounting();
  }

  @override
  Future<void> startCounting({int? sessionId}) async {
    await super.startCounting(sessionId: sessionId);
    if (loseStartReply) {
      emitStatus(null);
      throw StateError('Reply lost');
    }
  }
}

class _Repository extends LocalWorkoutRepository {
  _Repository(Directory directory) : super(directory: () async => directory);
  bool failCommit = false;
  @override
  Future<void> commitResult(
      ExerciseResult result, WorkoutJournal journal) async {
    if (failCommit) throw StateError('Disk temporarily unavailable');
    await super.commitResult(result, journal);
  }
}

void main() {
  late Directory directory;
  late _Repository repository;
  late _Tracker tracker;
  late WorkoutViewModel vm;
  late WorkoutPlan plan;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('fittracker-recovery-');
    repository = _Repository(directory);
    tracker = _Tracker();
    vm = WorkoutViewModel(repository: repository, tracker: tracker);
    await vm.load();
    plan = vm.workouts.firstWhere((w) =>
        isSameDate(w.scheduledAt, DateTime.now()) &&
        w.title == 'Upper Body Focus');
  });
  tearDown(() async {
    vm.dispose();
    await Future<void>.delayed(Duration.zero);
    await directory.delete(recursive: true);
  });

  Future<void> start([ExercisePlan? exercise]) async {
    if (vm.connectedDevice == null) {
      await vm.connect((await tracker.scan()).first);
    }
    await vm.prepareExercise(exercise ?? plan.exercises.first);
    await vm.startExercise(plan, exercise ?? plan.exercises.first);
  }

  Future<void> complete(ExercisePlan exercise, {int extra = 0}) async {
    await start(exercise);
    tracker.completeCalibration();
    tracker.emitReps(exercise.targetReps + extra);
    expect(await vm.finishExercise(), isTrue);
  }

  Future<ActiveExercise> record() async {
    await Future<void>.delayed(Duration.zero);
    return (await repository.readJournal()).active!;
  }

  Future<void> reopen({TrackerStatus? status}) async {
    final saved = await record();
    vm.dispose();
    tracker = _Tracker()
      ..bootId = saved.bootId
      ..sessionId = saved.sessionId
      ..restoredOnConnect = status;
    repository = _Repository(directory);
    vm = WorkoutViewModel(repository: repository, tracker: tracker);
    await vm.load();
  }

  test('Repeating an exercise preserves both attempts and other completions',
      () async {
    final exercise = plan.exercises.first;
    await complete(exercise);
    final original = vm.resultFor(plan, exercise)!;
    await vm.beginRepeat(plan, exercise: exercise);
    expect(vm.exerciseComplete(plan, exercise), isTrue);
    await complete(exercise, extra: 2);
    expect(vm.historyFor(plan, exercise), hasLength(2));
    expect(vm.historyFor(plan, exercise).map((r) => r.recordId),
        contains(original.recordId));
    expect(vm.lastFinishNextExercise, isNull);
    expect(vm.lastFinishWasRepeat, isTrue);
    final fresh = _Repository(directory);
    expect(await fresh.fetchHistory(), hasLength(2));
    expect((await fresh.fetchResults())[original.key]!.repetitions,
        exercise.targetReps + 2);
    expect((await fresh.readJournal()).active, isNull);
  });

  test(
      'Whole-workout repeat has independent progress and keeps daily completion',
      () async {
    for (final exercise in plan.exercises) {
      await complete(exercise);
    }
    expect(vm.workoutComplete(plan), isTrue);
    await vm.beginRepeat(plan);
    final run = vm.repeat!.id;
    for (var i = 0; i < plan.exercises.length; i++) {
      expect(vm.repeat!.index, i);
      expect(vm.workoutComplete(plan), isTrue);
      await complete(plan.exercises[i], extra: 1);
    }
    expect(vm.repeat, isNull);
    expect(vm.historyFor(plan), hasLength(plan.exercises.length * 2));
    expect(vm.historyFor(plan).where((r) => r.runId == run),
        hasLength(plan.exercises.length));
  });

  test('App recreation restores identity and requires explicit resume',
      () async {
    await start();
    tracker.completeCalibration();
    tracker.emitReps(6);
    final saved = await record();
    await reopen(
        status: TrackerStatus(
            state: TrackerState.running,
            repetitions: 8,
            calibrationReps: 3,
            bootId: saved.bootId,
            sessionId: saved.sessionId));
    expect(vm.hasActiveSession, isTrue);
    expect(vm.liveReps, 6);
    expect(vm.isDisconnected, isTrue);
    await vm.reconnectActiveExercise();
    expect(vm.liveReps, 8);
    expect(vm.isPaused, isTrue);
    expect(tracker.startCalls, 0);
    expect(tracker.resetCalls, 0);
    await vm.togglePause();
    expect(tracker.resumeCalls, 1);
  });

  for (final rebooted in [true, false]) {
    test(
        '${rebooted ? 'Rebooted' : 'Replaced'} device cannot donate counts to the old attempt',
        () async {
      await start();
      tracker.completeCalibration();
      tracker.emitReps(6);
      final saved = await record();
      tracker.emitStatus(null);
      tracker.restoredOnConnect = TrackerStatus(
          state: TrackerState.running,
          repetitions: 42,
          bootId: saved.bootId + (rebooted ? 1 : 0),
          sessionId: saved.sessionId + (rebooted ? 0 : 1));
      await expectLater(vm.reconnectActiveExercise(), throwsStateError);
      expect(vm.liveReps, 6);
      expect(vm.sessionInvalid, isTrue);
      expect(tracker.pauseCalls, 0);
      expect(tracker.resetCalls, 0);
      await vm.keepInterruptedResult();
      final history = await repository.fetchHistory();
      expect(history.single.repetitions, 6);
      expect(history.single.completed, isFalse);
      expect(await repository.fetchResults(), isEmpty);
      expect((await repository.readJournal()).active, isNull);
    });
  }

  test(
      'Lost START reply preserves the durable attempt and never blindly resets',
      () async {
    tracker.loseStartReply = true;
    await expectLater(start(), throwsStateError);
    final saved = await record();
    expect(vm.hasActiveSession, isTrue);
    expect(tracker.resetCalls, 0);
    tracker.restoredOnConnect = TrackerStatus(
        state: TrackerState.waitPickup,
        bootId: saved.bootId,
        sessionId: saved.sessionId);
    await vm.reconnectActiveExercise();
    expect(vm.isPaused, isTrue);
    expect(tracker.startCalls, 1);
  });

  test('Storage failure before START prevents an unjournaled device session',
      () async {
    await Directory('${directory.path}/workouts-v1.json.tmp').create();
    await expectLater(start(), throwsA(isA<FileSystemException>()));
    expect(tracker.startCalls, 0);
    expect(vm.hasActiveSession, isFalse);
  });

  test('Automatic reconnection retains a running set without another START',
      () async {
    await start();
    tracker.completeCalibration();
    tracker.emitReps(5);
    tracker.restoredOnConnect = TrackerStatus(
        state: TrackerState.running,
        repetitions: 6,
        calibrationReps: 3,
        bootId: tracker.bootId,
        sessionId: tracker.sessionId);
    tracker.emitStatus(null);
    await Future<void>.delayed(const Duration(milliseconds: 1250));
    expect(vm.isDisconnected, isFalse);
    expect(vm.liveReps, 6);
    expect(vm.isPaused, isFalse);
    expect(tracker.pauseCalls, 0);
    expect(tracker.startCalls, 1);
  });

  test('A failed stop journal write retains the attempt for a retry', () async {
    await start();
    await record();
    final blocked = Directory('${directory.path}/workouts-v1.json.tmp');
    await blocked.create();
    await expectLater(
        vm.stopWithoutSaving(), throwsA(isA<FileSystemException>()));
    expect(vm.hasActiveSession, isTrue);
    expect((await repository.readJournal()).active, isNotNull);
    await blocked.delete();
    await vm.stopWithoutSaving();
    expect(vm.hasActiveSession, isFalse);
    expect((await repository.readJournal()).active, isNull);
  });

  test('Repeat progress survives reopening and a failed cancel', () async {
    for (final exercise in plan.exercises) {
      await complete(exercise);
    }
    await vm.beginRepeat(plan);
    await complete(plan.exercises.first);
    final fresh = _Repository(directory);
    final journal = await fresh.readJournal();
    expect(journal.repeat!.index, 1);
    expect(journal.repeat!.id, vm.repeat!.id);
    final blocked = Directory('${directory.path}/workouts-v1.json.tmp');
    await blocked.create();
    await expectLater(vm.cancelRepeat(), throwsA(isA<FileSystemException>()));
    expect(vm.repeat!.index, 1);
    await blocked.delete();
    await vm.cancelRepeat();
    expect(vm.repeat, isNull);
    expect(vm.workoutComplete(plan), isTrue);
  });

  test('Confirmed final result survives a failed save and another app process',
      () async {
    await start();
    tracker.completeCalibration();
    tracker.emitReps(plan.exercises.first.targetReps + 1);
    repository.failCommit = true;
    await expectLater(vm.finishExercise(), throwsStateError);
    final saved = await record();
    expect(saved.finalResult, isNotNull);
    await reopen();
    expect(vm.hasPendingResult, isTrue);
    expect(vm.canFinish, isTrue);
    expect(await vm.finishExercise(), isTrue);
    expect(tracker.startCalls, 0);
    expect(tracker.stopCalls, 0);
    expect(await repository.fetchHistory(), hasLength(1));
    expect((await repository.readJournal()).active, isNull);
  });

  test('Version 1 completion migrates into history without deleting the result',
      () async {
    await complete(plan.exercises.first);
    final file = File('${directory.path}/workouts-v1.json');
    final old = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    old['version'] = 1;
    old.remove('journal');
    for (final result in old['results'] as List) {
      (result as Map)
        ..remove('attemptId')
        ..remove('runId')
        ..remove('completed');
    }
    await file.writeAsString(jsonEncode(old));
    final migrated = _Repository(directory);
    await migrated.fetchWorkouts();
    expect(await migrated.fetchHistory(), hasLength(1));
    expect((await migrated.fetchResults()).values.single.completed, isTrue);
    expect(jsonDecode(await file.readAsString())['version'], 2);
  });

  test(
      'A repeat is limited to today and cancelling it preserves earlier results',
      () async {
    await complete(plan.exercises.first);
    final yesterday = WorkoutPlan(
        id: plan.id,
        title: plan.title,
        description: plan.description,
        scheduledAt: DateTime.now().subtract(const Duration(days: 1)),
        exercises: plan.exercises);
    await expectLater(vm.beginRepeat(yesterday), throwsStateError);
    await vm.beginRepeat(plan, exercise: plan.exercises.first);
    await vm.cancelRepeat();
    expect(vm.repeat, isNull);
    expect(vm.exerciseComplete(plan, plan.exercises.first), isTrue);
    expect(await repository.fetchHistory(), hasLength(1));
  });
}
