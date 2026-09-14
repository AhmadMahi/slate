import 'dart:math' as math;

import '../ink/shape_snap.dart' show Offset2;
import '../model/models.dart';

/// Build the strokes for an arrow from [from] to [to].
///
/// THREE strokes, not one. An arrow is a shaft and two barbs, and a single
/// polyline that doubled back on itself would be rendered by a variable-width
/// ink engine as a shape with a pinch where it reverses — visible, and wrong.
/// Three strokes in the same ink block erase, lasso and recolour together
/// because everything that acts on ink acts on a block's strokes.
///
/// The head is on the end you FINISH at, which is the end your hand is at
/// when you let go: an arrow points where you were going.
List<Stroke> arrowStrokes({
  required Offset2 from,
  required Offset2 to,
  required String colorHex,
  required double size,
}) {
  final dx = to.x - from.x, dy = to.y - from.y;
  final len = math.sqrt(dx * dx + dy * dy);
  if (len < 1) return const [];

  // The head scales with BOTH the line's weight and its length, and is capped
  // by the length: a 2px arrow needs a small head, and a long one drawn with
  // a fine pen still needs a head you can see. Without the cap, a short drag
  // produces a head longer than the shaft — an arrowhead with no arrow.
  final head = math.min(len * 0.32, 9 + size * 3.2);
  const spread = 0.42; // ~24° each side of the shaft

  final angle = math.atan2(dy, dx);
  Offset2 barb(double a) => Offset2(
        to.x - head * math.cos(angle + a),
        to.y - head * math.sin(angle + a),
      );

  Stroke line(List<Offset2> pts) => Stroke(
        tool: 'pen',
        colorHex: colorHex,
        size: size,
        x: [for (final p in pts) p.x],
        y: [for (final p in pts) p.y],
        // Flat pressure: an arrow is a drawn object, not a gesture, and
        // carrying the speed wobble of the hand into it looks like a mistake.
        p: List<double>.filled(pts.length, 0.6),
        t: [for (var i = 0; i < pts.length; i++) i * 4],
      );

  // The shaft is subdivided so the renderer's smoothing has points to work
  // with; two points would be smoothed into two points.
  final shaft = [
    for (var i = 0; i <= 12; i++)
      Offset2(from.x + dx * i / 12, from.y + dy * i / 12)
  ];

  return [
    line(shaft),
    line([barb(spread), to]),
    line([barb(-spread), to]),
  ];
}
