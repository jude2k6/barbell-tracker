import 'package:barbell_app/analysis/exercises.dart';
import 'package:barbell_app/analysis/set_analysis.dart';
import 'package:barbell_app/workout/session.dart';
import 'package:barbell_app/workout/set_log.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('set completed block follows Stance and omits missing fields', () {
    final t = DateTime.utc(2026, 10, 17, 10, 0, 0);
    final set = SetRecord(
      id: 'rec1',
      startedAt: t,
      endedAt: t.add(const Duration(seconds: 12)),
      weight: 100,
      unit: WeightUnit.kg,
      setType: SetType.topSet,
      sampleCount: 2400,
      measuredHz: 199.987,
      pipeline: PipelineKind.squatBenchNative,
      rawCsvFile: 'recordings/rec1.csv',
    );
    final lines = setCompletedLines(set,
        exercise: Exercise.all.first,
        sessionId: 's1',
        sensorName: 'WT901',
        loggedAt: t);
    expect(lines.first, '========== SET COMPLETED BEGIN ==========');
    expect(lines.last, '========== SET COMPLETED END ==========');
    expect(lines, containsAll([
      'recordingId=rec1',
      'sessionGroupId=s1',
      'setType=top_set',
      'setDurationMs=12000',
      'meanFrequencyHz=199.99',
      'repMeanVelocitiesMps=[]',
      'datFileName=rec1.csv',
      'videoLocalIdentifier=N/A',
    ]));
    expect(lines.any((l) => l.startsWith('imuDataLossPct')), isFalse);
  });
}
