import 'dart:math' as math;

import '../ink/shape_snap.dart' show Offset2;
import '../model/models.dart';

/// Build the stroke for a rectangle whose opposite corners are [from] and [to].
///
/// ONE stroke, a closed polyline that traces the four sides and returns to
/// where it started. Unlike the arrow, a rectangle never doubles back along
/// its own path, so a single stroke has no pinch to worry about and the four
/// corners meet cleanly. It draws with the pen's colour and weight — the tool
/// only decides the shape the drag makes.
List<Stroke> rectangleStrokes({
  required Offset2 from,
  required Offset2 to,
  required String colorHex,
  required double size,
}) {
  final left = math.min(from.x, to.x);
  final right = math.max(from.x, to.x);
  final top = math.min(from.y, to.y);
  final bottom = math.max(from.y, to.y);

  // A drag too small to be a box would be a dot; nothing to commit.
  if (right - left < 2 && bottom - top < 2) return const [];

  // Each side is subdivided so the renderer's smoothing has points to work
  // with, exactly as the arrow's shaft is — two points per side would be
  // smoothed into two points and the corner would round off.
  final corners = <Offset2>[
    Offset2(left, top),
    Offset2(right, top),
    Offset2(right, bottom),
    Offset2(left, bottom),
    Offset2(left, top), // back to the start, closing the loop
  ];

  final pts = <Offset2>[];
  for (var c = 0; c < corners.length - 1; c++) {
    final a = corners[c], b = corners[c + 1];
    // The last point of each side is the first of the next, so skip it here
    // and let the next side contribute it — no duplicated vertex at a corner.
    for (var i = 0; i < 6; i++) {
      pts.add(Offset2(a.x + (b.x - a.x) * i / 6, a.y + (b.y - a.y) * i / 6));
    }
  }
  pts.add(corners.last);

  return [
    Stroke(
      tool: 'pen',
      colorHex: colorHex,
      size: size,
      // A rectangle keeps square corners: the renderer skips the freehand
      // streamline/smoothing that would otherwise round them off.
      sharp: true,
      x: [for (final p in pts) p.x],
      y: [for (final p in pts) p.y],
      // Flat pressure: a rectangle is a drawn object, not a gesture, and
      // carrying the speed wobble of the hand into it looks like a mistake.
      p: List<double>.filled(pts.length, 0.6),
      t: [for (var i = 0; i < pts.length; i++) i * 4],
    ),
  ];
}
