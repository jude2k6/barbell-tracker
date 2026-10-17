/// Exercise catalogue from the reference app (`domain/model/ExerciseCatalog`).
///
/// [rawValue] is the exact string the reference pipeline switches on, e.g.
/// the four "Deadlift (…)" strings select the deadlift constants.
library;

enum ExerciseFamily { squat, bench, deadlift }

class Exercise {
  const Exercise(this.id, this.rawValue, this.shortTitle, this.family);
  final String id;
  final String rawValue;
  final String shortTitle;
  final ExerciseFamily family;

  bool get isDeadlift => family == ExerciseFamily.deadlift;

  static Exercise byId(String id) => all.firstWhere((e) => e.id == id);

  static const all = <Exercise>[
    Exercise('squat_high_bar', 'Squat (high bar)', 'High Bar', ExerciseFamily.squat),
    Exercise('squat_low_bar', 'Squat (low bar)', 'Low Bar', ExerciseFamily.squat),
    Exercise('squat_front', 'Squat (front)', 'Front', ExerciseFamily.squat),
    Exercise('squat_safety_bar', 'Squat (SSB)', 'SSB', ExerciseFamily.squat),
    Exercise('bench_competition', 'Bench press (competition)', 'Competition', ExerciseFamily.bench),
    Exercise('bench_touch_and_go', 'Bench press (touch and go)', 'Touch And Go', ExerciseFamily.bench),
    Exercise('bench_feet_up', 'Bench press (feet up)', 'Feet Up', ExerciseFamily.bench),
    Exercise('bench_spoto', 'Bench press (spoto)', 'Spoto', ExerciseFamily.bench),
    Exercise('bench_larsen', 'Bench press (larson)', 'Larsen', ExerciseFamily.bench),
    Exercise('deadlift_conventional', 'Deadlift (conventional)', 'Conventional', ExerciseFamily.deadlift),
    Exercise('deadlift_sumo', 'Deadlift (sumo)', 'Sumo', ExerciseFamily.deadlift),
    Exercise('deadlift_trap_bar', 'Deadlift (trap bar)', 'Trap Bar', ExerciseFamily.deadlift),
    Exercise('deadlift_stiff_legged', 'Deadlift (stiff legged)', 'Stiff Legged', ExerciseFamily.deadlift),
  ];
}

/// Set-type tags from the reference app (`domain/model/SetTypeTag`).
enum SetType {
  warmUp('warmup', 'Warm up', 'WU'),
  lastWarmUp('last_warmup', 'Last Warmup', 'LWU'),
  topSet('top_set', 'Top set', 'TS'),
  backoff('backoff', 'Backoff', 'BO');

  const SetType(this.key, this.displayName, this.shortName);
  final String key;
  final String displayName;
  final String shortName;
}
