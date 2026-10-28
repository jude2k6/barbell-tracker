import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../workout/rep_editing.dart';
import '../app_theme.dart';
import '../app_widgets.dart';

/// Rep start markers and the pending new rep's start (Stance's 0xFF34C759).
const repStartColor = AppColors.connected;

/// Rep end markers and the pending new rep's end (Stance's 0xFFE85252).
const repEndColor = AppColors.error;

/// The scrubber (Stance's `SCRUBBER_BLUE`).
const scrubberColor = Color(0xFF0A84FF);

/// `%.2fs`, as Stance's Rep Check labels times.
String fmtRepCheckSec(double s) => '${s.toStringAsFixed(2)}s';

/// Stance's `RepCheckChart`: the trace between [windowStart] and
/// [windowEnd] in a card, each rep shaded and numbered with dashed start
/// (green) and end (red) lines, the saved positions as gray ghosts, the
/// pending new rep's start and end, and the blue scrubber. Dragging across
/// the chart scrubs: [onScrub] gets the time under the finger.
class RepCheckChart extends StatelessWidget {
  const RepCheckChart({
    super.key,
    required this.velocity,
    required this.hz,
    required this.markers,
    required this.original,
    required this.windowStart,
    required this.windowEnd,
    required this.scrubSec,
    required this.onScrub,
    this.adding = false,
    this.addStart,
    this.addEnd,
    this.height = 280,
  });

  final List<double> velocity;
  final double hz;
  final List<RepMarker> markers;

  /// The markers as saved, drawn as gray ghosts behind [markers].
  final List<RepMarker> original;
  final double windowStart, windowEnd, scrubSec;
  final ValueChanged<double> onScrub;

  /// Adding a rep: the markers are drawn gray.
  final bool adding;
  final double? addStart, addEnd;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: appCard(),
      padding: const EdgeInsets.all(12),
      child: LayoutBuilder(builder: (context, box) {
        double timeAt(Offset p) =>
            windowStart +
            p.dx / box.maxWidth * math.max(windowEnd - windowStart, 1e-6);
        return GestureDetector(
          key: const Key('repCheckChart'),
          behavior: HitTestBehavior.opaque,
          dragStartBehavior: DragStartBehavior.down,
          onPanStart: (d) => onScrub(timeAt(d.localPosition)),
          onPanUpdate: (d) => onScrub(timeAt(d.localPosition)),
          child: CustomPaint(
            size: Size.infinite,
            painter: RepCheckChartPainter(
              velocity: velocity,
              hz: hz,
              markers: markers,
              original: original,
              windowStart: windowStart,
              windowEnd: windowEnd,
              scrubSec: scrubSec,
              adding: adding,
              addStart: addStart,
              addEnd: addEnd,
              labelStyle: Theme.of(context).textTheme.labelSmall!.copyWith(
                  color: AppColors.subtitleGray,
                  fontSize: 11,
                  fontWeight: FontWeight.w500),
            ),
          ),
        );
      }),
    );
  }
}

class RepCheckChartPainter extends CustomPainter {
  RepCheckChartPainter({
    required this.velocity,
    required this.hz,
    required this.markers,
    required this.original,
    required this.windowStart,
    required this.windowEnd,
    required this.scrubSec,
    required this.adding,
    required this.addStart,
    required this.addEnd,
    required this.labelStyle,
  });

  final List<double> velocity;
  final double hz;
  final List<RepMarker> markers, original;
  final double windowStart, windowEnd, scrubSec;
  final bool adding;
  final double? addStart, addEnd;
  final TextStyle labelStyle;

  // Stance draws in raw pixels (3–4 px lines, 10/6 px dashes, a 14 px
  // dot); these are the same at a typical 2.6x density.
  static const _markerWidth = 1.2, _lineWidth = 1.5, _dot = 5.5;

  int _indexAt(double sec) =>
      (sec * hz).floor().clamp(0, velocity.length - 1);

  @override
  void paint(Canvas canvas, Size size) {
    if (velocity.isEmpty) return;
    final span = math.max(windowEnd - windowStart, 1e-6);
    double x(double sec) => (sec - windowStart) / span * size.width;
    bool onChart(double px) => px >= 0 && px <= size.width;

    // Y range: the visible slice ± 10 % (at least 0.05 m/s).
    final from = _indexAt(windowStart);
    final to = _indexAt(windowEnd).clamp(from, velocity.length - 1);
    final slice = velocity.sublist(from, to + 1);
    final lo0 = slice.reduce(math.min), hi0 = slice.reduce(math.max);
    final pad = math.max((hi0 - lo0) * 0.1, 0.05);
    final lo = lo0 - pad, range = math.max(hi0 + pad - lo, 1e-9);
    double y(double v) => size.height * (1 - (v - lo) / range);

    final zero = y(0);
    if (zero >= 0 && zero <= size.height) {
      canvas.drawLine(Offset(0, zero), Offset(size.width, zero),
          Paint()..color = Colors.white.withValues(alpha: 0.15));
    }

    // Rep shading and numbers.
    for (final (i, m) in markers.indexed) {
      final a = x(m.startSec).clamp(0.0, size.width);
      final b = x(m.endSec).clamp(0.0, size.width);
      if (b <= 0 || a >= size.width || b <= a) continue;
      canvas.drawRect(Rect.fromLTRB(a, 0, b, size.height),
          Paint()..color = AppColors.primary.withValues(alpha: 0.12));
      final label = _text('${i + 1}');
      label.paint(canvas, Offset((a + b) / 2 - label.width / 2, 2));
    }

    // The trace.
    if (slice.length > 1) {
      final path = Path();
      for (final (k, v) in slice.indexed) {
        final p = Offset(x((from + k) / hz), y(v));
        k == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(
          path,
          Paint()
            ..color = Colors.white
            ..style = PaintingStyle.stroke
            ..strokeWidth = _lineWidth
            ..strokeJoin = StrokeJoin.round);
    }

    void dashed(double sec, Color color, double width, double dash, double gap) {
      final px = x(sec);
      if (!onChart(px)) return;
      final paint = Paint()
        ..color = color
        ..strokeWidth = width;
      for (var y0 = 0.0; y0 < size.height; y0 += dash + gap) {
        canvas.drawLine(Offset(px, y0),
            Offset(px, math.min(y0 + dash, size.height)), paint);
      }
    }

    // Saved positions, then the current markers on top.
    final ghost = AppColors.gray.withValues(alpha: 0.3);
    for (final m in original) {
      dashed(m.startSec, ghost, _markerWidth, 4, 2.5);
      dashed(m.endSec, ghost, _markerWidth, 4, 2.5);
    }
    for (final m in markers) {
      dashed(m.startSec, adding ? ghost : repStartColor.withValues(alpha: 0.7),
          _markerWidth, 4, 2.5);
      dashed(m.endSec, adding ? ghost : repEndColor.withValues(alpha: 0.7),
          _markerWidth, 4, 2.5);
    }
    if (addStart != null) dashed(addStart!, repStartColor, _lineWidth, 5, 3);
    if (addEnd != null) dashed(addEnd!, repEndColor, _lineWidth, 5, 3);

    // The scrubber: a line, a dot on the trace and its time at the bottom.
    final sx = x(scrubSec);
    if (onChart(sx)) {
      final paint = Paint()
        ..color = scrubberColor
        ..strokeWidth = _lineWidth;
      canvas.drawLine(Offset(sx, 0), Offset(sx, size.height), paint);
      final i = (scrubSec * hz).floor();
      if (i >= 0 && i < velocity.length) {
        canvas.drawCircle(Offset(sx, y(velocity[i])), _dot, paint);
      }
      final t = _text(fmtRepCheckSec(scrubSec));
      t.paint(
          canvas,
          Offset(math.min(sx + 2.5, size.width - t.width),
              size.height - t.height - 1));
    }

    // Window start and end, bottom corners.
    final l = _text(fmtRepCheckSec(windowStart));
    l.paint(canvas, Offset(0, size.height - l.height));
    final r = _text(fmtRepCheckSec(windowEnd));
    r.paint(canvas, Offset(size.width - r.width, size.height - r.height));
  }

  TextPainter _text(String s) => TextPainter(
        text: TextSpan(text: s, style: labelStyle),
        textDirection: TextDirection.ltr,
      )..layout();

  @override
  bool shouldRepaint(RepCheckChartPainter old) =>
      old.markers != markers ||
      old.original != original ||
      old.windowStart != windowStart ||
      old.windowEnd != windowEnd ||
      old.scrubSec != scrubSec ||
      old.adding != adding ||
      old.addStart != addStart ||
      old.addEnd != addEnd ||
      old.velocity != velocity;
}

/// Stance's `RepMarkerBubbleRow`: a 30 dp "R#s" (green) and "R#e" (red)
/// bubble under each visible marker. Dragging one moves its marker by the
/// drag's share of the window, clamped to the window; the page clamps it
/// against the neighbours. The dragged bubble is drawn on top. While a rep
/// is being added the bubbles are gray and don't drag.
class RepMarkerBubbleRow extends StatefulWidget {
  const RepMarkerBubbleRow({
    super.key,
    required this.markers,
    required this.windowStart,
    required this.windowEnd,
    required this.onMoved,
    this.adding = false,
  });

  final List<RepMarker> markers;
  final double windowStart, windowEnd;
  final bool adding;

  /// (rep index, is start, new time).
  final void Function(int index, bool isStart, double sec) onMoved;

  @override
  State<RepMarkerBubbleRow> createState() => _RepMarkerBubbleRowState();
}

class _RepMarkerBubbleRowState extends State<RepMarkerBubbleRow> {
  static const _size = 30.0;
  String? _dragged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: LayoutBuilder(builder: (context, box) {
        final width = box.maxWidth;
        final span = math.max(widget.windowEnd - widget.windowStart, 1e-6);
        final bubbles = <(String, Widget)>[];
        for (final (i, m) in widget.markers.indexed) {
          for (final isStart in [true, false]) {
            final t = isStart ? m.startSec : m.endSec;
            if (t < widget.windowStart || t > widget.windowEnd) continue;
            final key = '${isStart ? 'start' : 'end'}-$i';
            final color = isStart ? repStartColor : repEndColor;
            bubbles.add((
              key,
              Positioned(
                key: ValueKey('bubble-$key'),
                left: width * (t - widget.windowStart) / span - _size / 2,
                top: 0,
                child: GestureDetector(
                  key: ValueKey('marker-$key'),
                  // The marker follows the finger from touch-down, slop
                  // included.
                  dragStartBehavior: DragStartBehavior.down,
                  onPanStart: widget.adding
                      ? null
                      : (_) => setState(() => _dragged = key),
                  onPanEnd: widget.adding
                      ? null
                      : (_) => setState(() => _dragged = null),
                  onPanCancel: widget.adding
                      ? null
                      : () => setState(() => _dragged = null),
                  onPanUpdate: widget.adding
                      ? null
                      : (d) {
                          final cur = widget.markers.elementAtOrNull(i);
                          if (cur == null) return;
                          final from = isStart ? cur.startSec : cur.endSec;
                          widget.onMoved(
                              i,
                              isStart,
                              (from + d.delta.dx / width * span)
                                  .clamp(widget.windowStart, widget.windowEnd)
                                  .toDouble());
                        },
                  child: Container(
                    width: _size,
                    height: _size,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: widget.adding
                          ? AppColors.gray.withValues(alpha: 0.5)
                          : color.withValues(alpha: 0.8),
                      border: Border.all(
                          color: widget.adding ? AppColors.gray : color,
                          width: 2),
                    ),
                    child: Text(
                      'R${i + 1}${isStart ? 's' : 'e'}',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ),
            ));
          }
        }
        // Later reps over earlier ones; the dragged bubble over all.
        final ordered = [
          for (final b in bubbles)
            if (b.$1 != _dragged) b.$2,
          for (final b in bubbles)
            if (b.$1 == _dragged) b.$2,
        ];
        return Stack(clipBehavior: Clip.none, children: ordered);
      }),
    );
  }
}
