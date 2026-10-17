import 'package:flutter/material.dart';

import '../analysis/set_analysis.dart';
import '../workout/session.dart';

/// Tabular (fixed-width) digits so columns of numbers line up.
const tabularFigures = [FontFeature.tabularFigures()];

extension TabularStyle on TextStyle? {
  TextStyle? get tabular => this?.copyWith(fontFeatures: tabularFigures);
}

/// Velocity in m/s with two decimals, or an en dash.
String fmtVelocity(double? v) => v == null ? '–' : v.toStringAsFixed(2);

String fmtPct(double? v) => v == null ? '–' : '${v.toStringAsFixed(0)} %';

/// Range of motion in centimetres.
String fmtRomCm(double? metres) =>
    metres == null ? '–' : (metres * 100).toStringAsFixed(0);

/// A number without a trailing `.0`.
String fmtNumber(double v) =>
    v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

String fmtWeight(double w, WeightUnit unit) => '${fmtNumber(w)} ${unit.name}';

String fmtRpe(double? rpe) => rpe == null ? '–' : fmtNumber(rpe);

const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String _two(int n) => n.toString().padLeft(2, '0');

/// "Mon 12 Oct 2026"
String fmtDate(DateTime t) =>
    '${_weekdays[t.weekday - 1]} ${t.day} ${_months[t.month - 1]} ${t.year}';

/// "Oct"
String fmtMonth(DateTime t) => _months[t.month - 1];

/// "12 Oct"
String fmtDayMonth(DateTime t) => '${t.day} ${fmtMonth(t)}';

/// "12 Oct 26"
String fmtShortDate(DateTime t) =>
    '${fmtDayMonth(t)} ${_two(t.year % 100)}';

/// "14:05"
String fmtTime(DateTime t) => '${_two(t.hour)}:${_two(t.minute)}';

/// "1:05.3" style elapsed time.
String fmtElapsed(Duration d) {
  final tenths = (d.inMilliseconds % 1000) ~/ 100;
  return '${d.inMinutes}:${_two(d.inSeconds % 60)}.$tenths';
}

/// Which analysis pipeline produced a set's numbers.
String pipelineLabel(PipelineKind p) => switch (p) {
      PipelineKind.squatBenchNative => 'Squat/bench pipeline',
      PipelineKind.deadliftTcn => 'Deadlift TCN model',
      PipelineKind.deadliftFallback => 'Deadlift threshold fallback',
    };
