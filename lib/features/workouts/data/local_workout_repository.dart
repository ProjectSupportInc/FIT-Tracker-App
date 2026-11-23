// Persists workout history in the app's private directory. The schedule is still
// a local starter plan; sign-in/backend integration is a separate feature.
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../domain/workout_models.dart';
import '../domain/workout_journal.dart';
import 'demo_workout_repository.dart';
import 'workout_repository.dart';

/// Real completion storage; tests inject a temporary directory and fixed clock.
class LocalWorkoutRepository extends WorkoutRepository {
  LocalWorkoutRepository({
    Future<Directory> Function()? directory,
    DateTime Function()? now,
  })  : _directory = directory ?? getApplicationSupportDirectory,
        _now = now ?? DateTime.now;

  final Future<Directory> Function() _directory;
  final DateTime Function() _now;
  Future<void>? _loading;
  File? _file;
  final Map<String, WorkoutPlan> _plans = {};
  final Map<String, ExerciseResult> _results = {};
  final Map<String, ExerciseResult> _attempts = {};
  WorkoutJournal _journal = const WorkoutJournal();
  Future<void> _writes = Future.value();
  Future<T> _mutate<T>(Future<T> Function() operation) {
    final next = _writes.then((_) => operation());
    _writes = next.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return next;
  }

  /// Load once; a failed read can be retried without replacing the stored file.
  Future<void> _ensureLoaded() async {
    try {
      await (_loading ??= _load());
    } catch (_) {
      _loading = null;
      rethrow;
    }
  }

  Future<void> _load() async {
    final directory = await _directory();
    await directory.create(recursive: true);
    _file = File('${directory.path}/workouts-v1.json');
    final plans = <String, WorkoutPlan>{};
    final results = <String, ExerciseResult>{};
    final attempts = <String, ExerciseResult>{};
    var journal = const WorkoutJournal();
    if (await _file!.exists()) {
      final data =
          jsonDecode(await _file!.readAsString()) as Map<String, dynamic>;
      if (data['version'] != 1 && data['version'] != 2) {
        throw const FormatException('Unsupported workout history version.');
      }
      for (final value in data['plans'] as List<dynamic>) {
        final plan = _readPlan(value as Map<String, dynamic>);
        plans[plan.id] = plan;
      }
      for (final value in data['results'] as List<dynamic>) {
        final item = value as Map<String, dynamic>;
        final result = ExerciseResult.fromJson(item);
        if (result.repetitions < 0 || !plans.containsKey(result.workoutId)) {
          throw const FormatException('Invalid saved workout result.');
        }
        attempts[result.recordId] = result;
        if (result.completed &&
            (results[result.key] == null ||
                !result.completedAt
                    .isBefore(results[result.key]!.completedAt))) {
          results[result.key] = result;
        }
      }
      if (data["journal"] != null) {
        journal =
            WorkoutJournal.fromJson(data["journal"] as Map<String, dynamic>);
      }
    }
    _attempts
      ..clear()
      ..addAll(attempts);
    _journal = journal;
    _plans
      ..clear()
      ..addAll(plans);
    _results
      ..clear()
      ..addAll(results);
  }

  @override
  Future<List<WorkoutPlan>> fetchWorkouts() => _mutate(() async {
        await _ensureLoaded();
        // Date-based IDs prevent yesterday's completion from unlocking today's plan.
        // Previously stored plans stay in history when a new day's schedule is added.
        final now = _now();
        final samples = await DemoWorkoutRepository(today: now).fetchWorkouts();
        final nextPlans = Map<String, WorkoutPlan>.of(_plans);
        for (final sample in samples) {
          final date = sample.scheduledAt;
          final dateKey =
              '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
          // Stable workout title identifies the template independent of relative day.
          final id =
              '$dateKey:${sample.title.toLowerCase().replaceAll(' ', '-')}';
          nextPlans.putIfAbsent(
              id,
              () => WorkoutPlan(
                    id: id,
                    title: sample.title,
                    description: sample.description,
                    scheduledAt: date,
                    exercises: sample.exercises,
                  ));
        }
        await _write(nextPlans);
        _plans
          ..clear()
          ..addAll(nextPlans);
        return List.unmodifiable(_plans.values.toList()
          ..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt)));
      });

  @override
  Future<Map<String, ExerciseResult>> fetchResults() async {
    await _ensureLoaded();
    // Deliberately do not import the demo repository's fabricated completion.
    return Map.unmodifiable(_results);
  }

  @override
  Future<List<ExerciseResult>> fetchHistory() async {
    await _ensureLoaded();
    await _writes;
    return List.unmodifiable(_attempts.values);
  }

  @override
  Future<WorkoutJournal> readJournal() async {
    await _ensureLoaded();
    await _writes;
    return _journal;
  }

  @override
  Future<void> writeJournal(WorkoutJournal value) => _mutate(() async {
        await _ensureLoaded();
        await _write(_plans, journal: value);
        _journal = value;
      });

  @override
  Future<void> saveResult(ExerciseResult result) => _commit(result, null);

  @override
  Future<void> commitResult(ExerciseResult result, WorkoutJournal journal) =>
      _commit(result, journal);

  Future<void> _commit(ExerciseResult result, WorkoutJournal? journal) =>
      _mutate(() async {
        await _ensureLoaded();
        final plan = _plans[result.workoutId];
        if (plan == null ||
            result.repetitions < 0 ||
            result.repetitions > 65535 ||
            !plan.exercises.any((e) =>
                e.id == result.exerciseId &&
                (!result.completed || result.repetitions >= e.targetReps))) {
          throw StateError(
              'The exercise result is not valid for the stored plan.');
        }
        final existing = _attempts[result.recordId];
        if (existing != null &&
            jsonEncode(existing.toJson()) != jsonEncode(result.toJson())) {
          throw StateError(
              'This attempt already has a different saved result.');
        }
        final attempts = Map<String, ExerciseResult>.of(_attempts)
          ..[result.recordId] = result;
        final next = Map<String, ExerciseResult>.of(_results);
        if (result.completed &&
            (next[result.key] == null ||
                !result.completedAt.isBefore(next[result.key]!.completedAt))) {
          next[result.key] = result;
        }
        await _write(_plans, attempts: attempts, journal: journal);
        _attempts
          ..clear()
          ..addAll(attempts);
        _results
          ..clear()
          ..addAll(next);
        if (journal != null) _journal = journal;
      });

  /// Replace the file only after a complete, flushed JSON write succeeds.
  Future<void> _write(Map<String, WorkoutPlan> plans,
      {Map<String, ExerciseResult>? attempts, WorkoutJournal? journal}) async {
    final data = <String, Object>{
      'version': 2,
      'journal': (journal ?? _journal).toJson(),
      'plans': plans.values
          .map((p) => {
                'id': p.id,
                'title': p.title,
                'description': p.description,
                'scheduledAt': p.scheduledAt.toIso8601String(),
                'exercises': p.exercises
                    .map((e) => {
                          'id': e.id,
                          'name': e.name,
                          'kind': e.kind,
                          'targetReps': e.targetReps,
                          'coachTip': e.coachTip,
                        })
                    .toList(),
              })
          .toList(),
      'results': (attempts ?? _attempts).values.map((r) => r.toJson()).toList(),
    };
    final temporary = File('${_file!.path}.tmp');
    await temporary.writeAsString(jsonEncode(data), flush: true);
    await temporary.rename(_file!.path);
  }

  WorkoutPlan _readPlan(Map<String, dynamic> value) {
    final exercises = (value['exercises'] as List<dynamic>).map((raw) {
      final e = raw as Map<String, dynamic>;
      final target = e['targetReps'] as int;
      if (target <= 0) {
        throw const FormatException('Exercise targets must be positive.');
      }
      return ExercisePlan(
          id: e['id'] as String,
          name: e['name'] as String,
          kind: e['kind'] as String,
          targetReps: target,
          coachTip: e['coachTip'] as String);
    }).toList();
    if (exercises.isEmpty) {
      throw const FormatException('Workout contains no exercises.');
    }
    return WorkoutPlan(
        id: value['id'] as String,
        title: value['title'] as String,
        description: value['description'] as String,
        scheduledAt: DateTime.parse(value['scheduledAt'] as String),
        exercises: exercises);
  }
}
