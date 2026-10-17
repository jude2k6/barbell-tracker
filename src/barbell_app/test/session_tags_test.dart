import 'package:barbell_app/analysis/exercises.dart';
import 'package:barbell_app/workout/readiness.dart';
import 'package:barbell_app/workout/session.dart';
import 'package:barbell_app/workout/session_tags.dart';
import 'package:flutter_test/flutter_test.dart';

SetRecord _set(double v) => SetRecord(
      id: 'set$v',
      startedAt: DateTime.utc(2026, 10, 1),
      endedAt: DateTime.utc(2026, 10, 1),
      weight: 100,
      unit: WeightUnit.kg,
      setType: SetType.topSet,
      reps: [
        RepRecord(index: 1, startSec: 0, endSec: 1, meanVelocity: v, peakVelocity: v),
      ],
    );

Session _session(String id, int day, double v, List<String> tags) => Session(
      id: id,
      exerciseId: 'squat_low_bar',
      startedAt: DateTime.utc(2026, 10, day, 9),
      sets: [_set(v)],
      tags: tags,
    );

void main() {
  test('wire tags and lookups', () {
    expect(SessionDayType.primary.wireTag, 'Day:Primary');
    expect(SessionDayType.fromTags(['Block:Peak', 'Day:Tertiary']),
        SessionDayType.tertiary);
    expect(SessionDayType.fromTags(['Day:Heavy']), isNull);
    // extractSessionType matches a type name anywhere in any tag.
    expect(sessionTypeOf(['Block:Peak', 'Day:Secondary']), 'Secondary');
    expect(sessionTypeOf(['Block:Peak']), '');
    expect(hasSessionTypeTag(const []), isFalse);
  });

  test('withDayType replaces or removes the Day tag only', () {
    expect(withDayType(['Block:Peak', 'Day:Primary'], SessionDayType.secondary),
        ['Block:Peak', 'Day:Secondary']);
    expect(withDayType(['Day:Primary', 'Week:3'], null), ['Week:3']);
  });

  test('Session keeps its tags through JSON; untagged writes none', () {
    final s = _session('a', 1, 0.5, ['Day:Primary']);
    expect(Session.fromJson(s.toJson()).tags, ['Day:Primary']);
    expect(_session('b', 1, 0.5, const []).toJson().containsKey('tags'), isFalse);
  });

  test('readiness only uses sessions of the same type', () {
    final current = _session('now', 12, 0.6, ['Day:Primary']);
    final all = [
      current,
      _session('p', 10, 0.55, ['Day:Primary']),
      _session('s', 11, 0.40, ['Day:Secondary']),
      _session('u', 9, 0.30, const []),
    ];
    final r = buildReadiness(all, current: current, set: current.sets.single);
    expect(r.lastSessionSpeed, 0.55);
    expect(r.historicAverage, isNull);

    final untagged = _session('now2', 12, 0.6, const []);
    expect(
        buildReadiness([...all, untagged], current: untagged, set: untagged.sets.single)
            .lastSessionSpeed,
        0.30);
  });

  test('toggleTag keeps one tag per section (SessionTagRules)', () {
    expect(tagPrefix('Block:3'), 'Block');
    expect(tagPrefix('plain'), 'plain');
    expect(tagPrefix(':x'), ':x');
    var tags = ['Day:Primary'];
    tags = toggleTag(tags, 'Block:1');
    expect(tags, ['Day:Primary', 'Block:1']);
    tags = toggleTag(tags, 'Block:2');
    expect(tags, ['Day:Primary', 'Block:2']);
    tags = toggleTag(tags, 'Day:Tertiary');
    expect(tags, ['Block:2', 'Day:Tertiary']);
    tags = toggleTag(tags, 'Block:2');
    expect(tags, ['Day:Tertiary']);
  });

  test('editor sections and starting counts', () {
    expect(blockTags(editorPageSize).first, 'Block:1');
    expect(weekTags(12).last, 'Week:12');
    expect(dayTags, ['Day:Primary', 'Day:Secondary', 'Day:Tertiary', 'Day:Quaternary']);
    expect(externalTags, [for (var i = 1; i <= 5; i++) 'Externals:$i']);
    expect(initialEditorCount(const [], 'Block'), 6);
    expect(initialEditorCount(['Block:7', 'Week:2'], 'Block'), 12);
    expect(initialEditorCount(['Block:7', 'Week:2'], 'Week'), 6);
  });

  test('card pills: ordered and shortened (SessionTagFormatter)', () {
    expect(
        displayTags(['Externals:2', 'Block:1', '//hidden', 'Day:Primary', 'Other', 'Week:3']),
        ['Primary', 'W:3', 'B:1', 'E:2', 'Other']);
    expect(shortenTagText('Day'), 'D');
    expect(shortenTagText('External:1'), 'E:1');
  });

  test('readiness session label (generateSessionLabel)', () {
    expect(readinessSessionLabel(['Day:Primary', 'Week:3', 'Block:2']), 'Block:2 Week:3');
    expect(readinessSessionLabel(['Week:1']), 'Week:1');
    expect(readinessSessionLabel(['Day:Primary']), '');
    final current = _session('now', 12, 0.6, ['Day:Primary']);
    final r = buildReadiness([
      current,
      _session('a', 10, 0.5, ['Day:Primary', 'Block:1', 'Week:2']),
      _session('b', 11, 0.55, ['Day:Primary']),
    ], current: current, set: current.sets.single);
    expect(r.points.map((p) => p.sessionLabel), ['', 'Block:1 Week:2']);
  });
}
