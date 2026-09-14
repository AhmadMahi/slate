import 'dart:math' as math;

import '../model/models.dart';

/// Auto shapes: turn a hand-drawn stroke into the shape it was meant to be.
///
/// OneNote and Notability both do this and it is the single cheapest way to
/// make a diagram look deliberate — nobody draws a clean circle freehand with
/// a mouse, and redrawing it four times is the usual alternative.
///
/// The recogniser is intentionally small and explainable. It answers three
/// questions in order, and each is a property of the stroke a person could
/// check by eye:
///
///  1. Is it CLOSED? (do the two ends nearly meet, relative to its size)
///  2. If open — is it STRAIGHT? (do the points hug the line between the ends)
///  3. If closed — how many CORNERS does the turning have? 0 → ellipse,
///     3 → triangle, 4 → rectangle.
///
/// Anything it is not confident about is left exactly as drawn. That is the
/// important half of the contract: a recogniser that mangles a stroke it
/// misread is worse than one that does nothing, because the user loses work
/// they cannot get back except by undoing and drawing again.
class ShapeSnap {
  /// Ends closer than this fraction of the stroke's size count as "joined".
  ///
  /// Loosened from 0.28 now that snapping is asked for rather than guessed:
  /// the user has held still to request it, so a circle whose ends missed by
  /// a fifth of its width is plainly a circle and refusing it is the wrong
  /// kind of caution. It cost nothing when snapping was a surprise; it costs
  /// the whole feature when it is a request.
  static const _closeFrac = 0.38;

  /// A straight line's points stay within this fraction of its length of the
  /// straight line between its ends. Also loosened, for the same reason: a
  /// line drawn with a mouse bows.
  static const _straightFrac = 0.11;

  /// A turn sharper than this is a corner. ~50°, above the wobble of a
  /// hand-drawn arc and below a real corner's 90°.
  static const _cornerAngle = 0.88;

  /// The snapped stroke, or null to keep what was drawn.
  ///
  /// [s] is not modified; the caller decides whether to take the result.
  static Stroke? snap(Stroke s) {
    final n = s.x.length;
    if (n < 8) return null; // a flick is not a shape

    final pts = [for (var i = 0; i < n; i++) Offset2(s.x[i], s.y[i])];
    final minX = pts.map((p) => p.x).reduce(math.min);
    final maxX = pts.map((p) => p.x).reduce(math.max);
    final minY = pts.map((p) => p.y).reduce(math.min);
    final maxY = pts.map((p) => p.y).reduce(math.max);
    final w = maxX - minX, h = maxY - minY;
    final size = math.max(w, h);
    // Too small to be anything but a dot or a tick.
    if (size < 24) return null;

    final gap = _dist(pts.first, pts.last);
    final closed = gap < size * _closeFrac;

    if (!closed) {
      return _isStraight(pts) ? _line(s, pts.first, pts.last) : null;
    }

    final corners = _corners(pts, closed: true);
    return switch (corners.length) {
      // A closed loop with no sharp turns is a round thing. Two corners is
      // still round: a hand almost always leaves one kink where it closes,
      // and sometimes a second where it changed grip.
      0 || 1 || 2 => _ellipse(s, minX, minY, w, h),
      3 => _polygon(s, _regularise(corners)),
      // Four or five: a rectangle whose closing corner was counted twice.
      // Snapped to the BOUNDING BOX rather than through the corners, because
      // a hand-drawn box is never square and squaring it is the entire point.
      4 || 5 => _rect(s, minX, minY, w, h),
      _ => null,
    };
  }

  /// Pull a triangle's corners out to the points the hand actually reached.
  ///
  /// The corner detector finds where the direction turned, which is a step or
  /// two INSIDE the real vertex — the resampling walks past it. Left alone,
  /// every snapped triangle comes out slightly smaller than the one drawn,
  /// which reads as the app shrinking your work.
  static List<Offset2> _regularise(List<Offset2> corners) {
    if (corners.length != 3) return corners;
    var cx = 0.0, cy = 0.0;
    for (final c in corners) {
      cx += c.x;
      cy += c.y;
    }
    cx /= 3;
    cy /= 3;
    return [
      for (final c in corners)
        Offset2(cx + (c.x - cx) * 1.06, cy + (c.y - cy) * 1.06)
    ];
  }

  /// The corners the recogniser sees in [s].
  ///
  /// Public because classification hangs entirely off this number — 0-2 is a
  /// round thing, 3 a triangle, 4-5 a box — so when a rectangle comes back as
  /// an ellipse this is the only place worth looking. Testing the shape it
  /// produces tells you THAT it was wrong; this tells you why.
  static List<Offset2> cornersOf(Stroke s, {bool closed = true}) {
    final n = s.x.length;
    if (n < 8) return const [];
    return _corners([for (var i = 0; i < n; i++) Offset2(s.x[i], s.y[i])],
        closed: closed);
  }

  static double _dist(Offset2 a, Offset2 b) =>
      math.sqrt((a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y));

  /// Every point within [_straightFrac] of the chord, measured against the
  /// chord's own length so a long line is allowed a proportional wobble.
  static bool _isStraight(List<Offset2> pts) {
    final a = pts.first, b = pts.last;
    final len = _dist(a, b);
    if (len < 24) return false;
    final tol = len * _straightFrac;
    final dx = b.x - a.x, dy = b.y - a.y;
    for (final p in pts) {
      // |cross product| / |chord| is the perpendicular distance.
      final d = ((p.x - a.x) * dy - (p.y - a.y) * dx).abs() / len;
      if (d > tol) return false;
    }
    return true;
  }

  /// Corner points, found by walking the stroke in fixed-length steps and
  /// measuring how far the direction turns at each.
  ///
  /// Fixed-length steps rather than every sample: sample density depends on
  /// how fast the hand moved, so consecutive raw points near a slow corner
  /// are millimetres apart and their angles are noise.
  static List<Offset2> _corners(List<Offset2> pts, {required bool closed}) {
    // 48 rather than 32: at 32 a small triangle gets barely ten samples a
    // side and its corners blur into the arcs beside them.
    final r = _resample(pts, 48);
    if (r.length < 8) return const [];

    // TURNING MEASURED OVER A WINDOW, not between neighbours.
    //
    // A corner almost never lands exactly on a sample. Compared step to step
    // its 90 degrees arrive as two turns of 45, neither of which crosses the
    // threshold, and the corner is missed — which is why a drawn rectangle
    // came back as an ellipse. Comparing the direction of the two steps
    // BEFORE a point with the two AFTER it collects the whole turn wherever
    // the corner actually fell.
    const w = 2;

    // A CLOSED shape is walked as a loop, so the seam where the hand
    // finished is examined like any other point. Straight-line indexing
    // skips it, and a rectangle that loses its closing corner has three —
    // which is a triangle, and was being snapped to one.
    final n = r.length;
    final out = <Offset2>[];
    final first = closed ? 0 : w;
    final last = closed ? n : n - w;

    for (var i = first; i < last; i++) {
      Offset2 at(int j) => closed ? r[(j % n + n) % n] : r[j];
      final a = at(i - w), b = at(i), c = at(i + w);
      final a1 = math.atan2(b.y - a.y, b.x - a.x);
      final a2 = math.atan2(c.y - b.y, c.x - b.x);
      var turn = (a2 - a1).abs();
      if (turn > math.pi) turn = 2 * math.pi - turn;
      if (turn <= _cornerAngle) continue;
      // Merge turns near each other: a real corner spans several windows,
      // and counting one twice turns a rectangle into a shape with no name.
      if (out.isEmpty || _dist(out.last, b) > 24) out.add(b);
    }

    // On a loop the first and last found corner can be the same corner seen
    // from either side of the seam.
    if (closed && out.length > 1 && _dist(out.first, out.last) <= 24) {
      out.removeLast();
    }
    return out;
  }

  /// [count] points spaced evenly along the path by ARC LENGTH.
  static List<Offset2> _resample(List<Offset2> pts, int count) {
    var total = 0.0;
    for (var i = 1; i < pts.length; i++) {
      total += _dist(pts[i - 1], pts[i]);
    }
    if (total <= 0) return pts;
    // THIS IS WHERE THE RECOGNITION WAS GOING WRONG.
    //
    // The previous version emitted each new point by interpolating from
    // `pts[i - 1]` — the segment's ORIGINAL start — while measuring the
    // remaining distance from the point it had just emitted. On a long
    // straight edge those disagree, so it laid several samples almost on top
    // of each other near the start of the segment and left the rest of the
    // edge with none.
    //
    // A rectangle's four corners then vanished into a cloud of bunched
    // samples, the turning looked smooth, and every box came back as an
    // ellipse. It was reported as "the shape recognition is very bad", and
    // it was — not because the thresholds were wrong but because the shape
    // the detector was shown had already been mangled.
    //
    // Walking `prev` forward to each emitted point is the whole fix.
    final step = total / (count - 1);
    final out = <Offset2>[pts.first];
    var prev = pts.first;
    var acc = 0.0;
    for (var i = 1; i < pts.length; i++) {
      final curr = pts[i];
      var seg = _dist(prev, curr);
      while (seg > 0 && acc + seg >= step && out.length < count) {
        final t = (step - acc) / seg;
        final p = Offset2(
          prev.x + (curr.x - prev.x) * t,
          prev.y + (curr.y - prev.y) * t,
        );
        out.add(p);
        prev = p;
        seg = _dist(prev, curr);
        acc = 0;
      }
      acc += seg;
      prev = curr;
    }
    while (out.length < count) {
      out.add(pts.last);
    }
    return out;
  }

  // ── Builders ─────────────────────────────────────────────────────────
  //
  // Each returns a stroke with the SAME id, tool, colour, size and opacity —
  // only the geometry is replaced. Pressure is flattened to a constant: a
  // snapped shape is a drawn object, and carrying the speed wobble of the
  // hand that sketched it into a perfect circle looks like a mistake.

  static Stroke _shaped(Stroke s, List<Offset2> pts) => Stroke(
        id: s.id,
        tool: s.tool,
        colorHex: s.colorHex,
        size: s.size,
        opacity: s.opacity,
        x: [for (final p in pts) p.x],
        y: [for (final p in pts) p.y],
        p: List<double>.filled(pts.length, 0.6),
        t: [for (var i = 0; i < pts.length; i++) i * 4],
      );

  static Stroke _line(Stroke s, Offset2 a, Offset2 b) =>
      _shaped(s, [for (var i = 0; i <= 16; i++) _lerp(a, b, i / 16)]);

  static Offset2 _lerp(Offset2 a, Offset2 b, double t) =>
      Offset2(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t);

  static Stroke _ellipse(Stroke s, double x, double y, double w, double h) {
    final cx = x + w / 2, cy = y + h / 2, rx = w / 2, ry = h / 2;
    const steps = 48;
    return _shaped(s, [
      for (var i = 0; i <= steps; i++)
        Offset2(cx + rx * math.cos(i / steps * 2 * math.pi),
            cy + ry * math.sin(i / steps * 2 * math.pi)),
    ]);
  }

  static Stroke _rect(Stroke s, double x, double y, double w, double h) {
    final corners = [
      Offset2(x, y),
      Offset2(x + w, y),
      Offset2(x + w, y + h),
      Offset2(x, y + h),
    ];
    return _polygon(s, corners);
  }

  /// A closed polygon through [corners], with each edge subdivided so the
  /// renderer's smoothing has points to work with.
  static Stroke _polygon(Stroke s, List<Offset2> corners) {
    final pts = <Offset2>[];
    for (var i = 0; i < corners.length; i++) {
      final a = corners[i], b = corners[(i + 1) % corners.length];
      for (var k = 0; k < 8; k++) {
        pts.add(_lerp(a, b, k / 8));
      }
    }
    pts.add(corners.first); // close it
    return _shaped(s, pts);
  }
}

/// A plain (x, y) pair, so this file needs nothing from the widget layer.
class Offset2 {
  const Offset2(this.x, this.y);
  final double x;
  final double y;
}
