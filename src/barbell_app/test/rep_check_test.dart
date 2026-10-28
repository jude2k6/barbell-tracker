import 'dart:io';

import 'package:barbell_app/ui/app_theme.dart';
import 'package:barbell_app/ui/app_widgets.dart';
import 'package:barbell_app/ui/charts/rep_check_chart.dart';
import 'package:barbell_app/ui/rep_check_page.dart';
import 'package:barbell_app/workout/rep_editing.dart';
import 'package:barbell_app/workout/session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 10 Hz trace, 0–4.9 s; reps 1–2 s and 3–4 s. The chart shows all of it
/// (shorter than the 10 s window), with the scrubber starting at 2.45 s.
SetRecord _set() => SetRecord(
      id: 's',
      startedAt: DateTime(2026, 10, 23, 9),
      endedAt: DateTime(2026, 10, 23, 9, 1),
      weight: 100,
      unit: WeightUnit.kg,
      reps: const [
        RepRecord(index: 1, startSec: 1, endSec: 2, meanVelocity: 0.5, peakVelocity: 1),
        RepRecord(index: 2, startSec: 3, endSec: 4, meanVelocity: 0.5, peakVelocity: 1),
      ],
      velocityTrace: [for (var i = 0; i < 50; i++) i / 10],
      traceHz: 10,
    );

void main() {
  final commits = <List<RepMarker>>[];
  setUp(commits.clear);

  Future<SetRecord?> commit(List<RepMarker> markers) async {
    commits.add(markers);
    return applyRepMarkers(_set(), markers);
  }

  Future<void> open(WidgetTester tester, {File? video}) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: appTheme(),
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) =>
                    RepCheckPage(set: _set(), onCommit: commit, video: video))),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  String times(WidgetTester tester, int i) =>
      tester.widget<Text>(find.byKey(ValueKey('repTimes-$i'))).data!;

  /// Drags across the chart so that it ends at [sec].
  Future<void> scrubTo(WidgetTester tester, double sec) async {
    final r = tester.getRect(find.byKey(const Key('repCheckChart')));
    final x = r.left + sec / 4.9 * r.width;
    await tester.dragFrom(Offset(x - 40, r.center.dy), const Offset(40, 0));
    await tester.pump();
  }

  testWidgets('no sliders; R#s/R#e bubbles sit under each marker',
      (tester) async {
    await open(tester);
    expect(find.byType(Slider), findsNothing);
    expect(find.byType(RangeSlider), findsNothing);
    for (final label in ['R1s', 'R1e', 'R2s', 'R2e']) {
      expect(find.text(label), findsOneWidget);
    }
    final chart = tester.getRect(find.byKey(const Key('repCheckChart')));
    final r1e = tester.getCenter(find.byKey(const ValueKey('marker-end-0')));
    expect(r1e.dx, closeTo(chart.left + 2 / 4.9 * chart.width, 0.5));
    expect(times(tester, 0), '1.00s – 2.00s');
  });

  testWidgets('dragging a bubble moves its marker, clamped by its neighbours; '
      'Save commits', (tester) async {
    await open(tester);
    final save = find.byKey(const Key('saveMarkers'));
    expect(tester.widget<AppSmallButton>(save).onPressed, isNull);

    // R1e can't pass R2s.
    await tester.drag(
        find.byKey(const ValueKey('marker-end-0')), const Offset(400, 0));
    await tester.pump();
    expect(times(tester, 0), '1.00s – 3.00s');
    // R2s can't pass R1e (now 3.0) nor come within 0.1 s of R2e.
    await tester.drag(
        find.byKey(const ValueKey('marker-start-1')), const Offset(400, 0));
    await tester.pump();
    expect(times(tester, 1), '3.90s – 4.00s');
    // A smaller move follows the finger: 152 px of 744 px ≈ 1 s.
    await tester.drag(
        find.byKey(const ValueKey('marker-start-1')), const Offset(-152, 0));
    await tester.pump();
    final start = double.parse(times(tester, 1).split('s').first);
    expect(start, closeTo(3.0, 0.15));

    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(commits, hasLength(1));
    expect(commits.single.first, const RepMarker(1, 3));
    expect(commits.single.last.startSec, start);
  });

  testWidgets('dragging the chart scrubs; Add Rep sets start, end, then adds',
      (tester) async {
    await open(tester);
    await tester.tap(find.byKey(const Key('addRep')));
    await tester.pump();
    // Adding: the bubbles don't drag.
    await tester.drag(
        find.byKey(const ValueKey('marker-end-0')), const Offset(100, 0));
    await tester.pump();

    final action = find.byKey(const Key('addRepAction'));
    expect(find.descendant(of: action, matching: find.text('Set start time')),
        findsOneWidget);
    await tester.tap(action); // at the initial 2.45 s
    await tester.pump();
    expect(find.text('2.45s'), findsWidgets);

    // An end inside Rep 2 is refused.
    await scrubTo(tester, 3.5);
    await tester.tap(action);
    await tester.pumpAndSettle();
    expect(find.text('End time cannot be inside Rep 2'), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    await scrubTo(tester, 2.8);
    await tester.tap(action);
    await tester.pump();
    expect(find.descendant(of: action, matching: find.text('Add Rep')),
        findsOneWidget);
    await tester.tap(action);
    await tester.pumpAndSettle();
    expect(commits, hasLength(1));
    final added = commits.single.last;
    expect(added.startSec, 2.45);
    expect(added.endSec, closeTo(2.8, 0.02));
    expect(commits.single.take(2), const [RepMarker(1, 2), RepMarker(3, 4)]);
    // Back to the rep list, three reps now.
    expect(find.byKey(const ValueKey('repTimes-2')), findsOneWidget);
  });

  testWidgets('unsaved changes: Save, Discard, Cancel; Cancel stays',
      (tester) async {
    await open(tester);
    await tester.drag(
        find.byKey(const ValueKey('marker-end-0')), const Offset(60, 0));
    await tester.pump();

    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    final dialog = find.byType(AlertDialog);
    expect(find.descendant(of: dialog, matching: find.text('Unsaved Changes')),
        findsOneWidget);
    final buttons = tester
        .widgetList<TextButton>(
            find.descendant(of: dialog, matching: find.byType(TextButton)))
        .map((b) => (b.child as Text).data)
        .toList();
    expect(buttons, ['Save', 'Discard', 'Cancel']);

    await tester.tap(find.byKey(const Key('unsavedCancel')));
    await tester.pumpAndSettle();
    expect(dialog, findsNothing);
    expect(find.byType(RepCheckPage), findsOneWidget);
    expect(
        tester.widget<AppSmallButton>(find.byKey(const Key('saveMarkers'))).onPressed,
        isNotNull);

    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('unsavedDiscard')));
    await tester.pumpAndSettle();
    expect(find.byType(RepCheckPage), findsNothing);
    expect(commits, isEmpty);

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.drag(
        find.byKey(const ValueKey('marker-end-0')), const Offset(400, 0));
    await tester.pump();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('unsavedSave')));
    await tester.pumpAndSettle();
    expect(find.byType(RepCheckPage), findsNothing);
    expect(commits.single.first, const RepMarker(1, 3));
  });

  testWidgets('with a video: shown above a shorter chart, time follows the '
      'scrubber', (tester) async {
    await open(tester, video: File('${Directory.systemTemp.path}/none.mp4'));
    expect(find.byType(RepCheckVideo), findsOneWidget);
    expect(tester.getSize(find.byType(RepCheckVideo)).height, 220);
    expect(tester.getSize(find.byType(RepCheckChart)).height, 200);
    Text badge() => tester.widget(find.byKey(const Key('repCheckVideoTime')));
    expect(badge().data, '2.45s');
    await scrubTo(tester, 1.5);
    expect(double.parse(badge().data!.replaceAll('s', '')), closeTo(1.5, 0.02));
  });

  testWidgets('without a video: no player, taller chart', (tester) async {
    await open(tester);
    expect(find.byType(RepCheckVideo), findsNothing);
    expect(tester.getSize(find.byType(RepCheckChart)).height, 280);
  });
}
