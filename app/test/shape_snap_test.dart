// Auto shapes (INK-10). The recogniser's contract has two halves, and the
// second one matters more than the first: it snaps what it is confident
// about, and it LEAVES ALONE what it is not. A recogniser that mangles a
// stroke it misread costs the user work they cannot get back except by
// undoing and drawing again.
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:openote/ink/shape_snap.dart';
import 'package:openote/model/models.dart';

Stroke strokeOf(List<(double, double)> pts) => Stroke(
      tool: 'pen',
      colorHex: '#000000',
      size: 2,
      x: [for (final p in pts) p.$1],
      y: [for (final p in pts) p.$2],
      p: [for (final _ in pts) 0.5],
    );

/// A shaky circle: a real one plus a wobble no hand avoids.
List<(double, double)> wobblyCircle(
    {double cx = 200, double cy = 200, double r = 80, int n = 60}) {
  final rnd = math.Random(7);
  return [
    for (var i = 0; i <= n; i++)
      (
        cx + (r + rnd.nextDouble() * 6 - 3) * math.cos(i / n * 2 * math.pi),
        cy + (r + rnd.nextDouble() * 6 - 3) * math.sin(i / n * 2 * math.pi),
      )
  ];
}

void main() {
  group('what it snaps', () {
    test('a wobbly circle becomes a round one', () {
      final out = ShapeSnap.snap(strokeOf(wobblyCircle()));
      expect(out, isNotNull, reason: 'a closed, cornerless loop is an ellipse');
      // Every point the same distance from the centre is what "round" means.
      final r = [
        for (var i = 0; i < out!.x.length; i++)
          math.sqrt(math.pow(out.x[i] - 200, 2) + math.pow(out.y[i] - 200, 2))
      ];
      final spread = r.reduce(math.max) - r.reduce(math.min);
      expect(spread, lessThan(2.0),
          reason: 'the wobble is gone, not merely reduced');
    });

    test('a shaky line becomes straight', () {
      final rnd = math.Random(3);
      final out = ShapeSnap.snap(strokeOf([
        for (var i = 0; i <= 30; i++)
          (100 + i * 6.0, 300 + rnd.nextDouble() * 4 - 2)
      ]));
      expect(out, isNotNull);
      final ys = out!.y;
      expect(ys.reduce(math.max) - ys.reduce(math.min), lessThan(1.0));
    });

    test('the snapped stroke keeps its identity, not just its shape', () {
      final s = strokeOf(wobblyCircle());
      final out = ShapeSnap.snap(s)!;
      expect(out.id, s.id, reason: 'same stroke, tidied — not a new one');
      expect(out.colorHex, s.colorHex);
      expect(out.size, s.size);
      expect(out.tool, s.tool);
    });
  });

  group('the shapes it is asked for most', () {
    // Recognition was reported as poor. These are the three a diagram is made
    // of, drawn the way a hand draws them — wobbling, and not closing
    // cleanly.
    test('a wobbly rectangle becomes a square-cornered one', () {
      final rnd = math.Random(5);
      final pts = <(double, double)>[];
      void edge((double, double) a, (double, double) b) {
        for (var i = 0; i < 14; i++) {
          final t = i / 14;
          pts.add((
            a.$1 + (b.$1 - a.$1) * t + rnd.nextDouble() * 6 - 3,
            a.$2 + (b.$2 - a.$2) * t + rnd.nextDouble() * 6 - 3,
          ));
        }
      }
      edge((100, 100), (400, 100));
      edge((400, 100), (400, 300));
      edge((400, 300), (100, 300));
      edge((100, 300), (105, 108)); // closes a few pixels off, as hands do
      final out = ShapeSnap.snap(strokeOf(pts));
      expect(out, isNotNull, reason: 'four corners is a rectangle');
      // Snapped to the BOUNDING BOX: every point sits on one of the four
      // straight edges. Asserted that way rather than by counting distinct
      // coordinates, because the edges are subdivided so the renderer has
      // points to smooth — a rectangle here has plenty of distinct x values
      // and is still a rectangle.
      final xs = out!.x, ys = out.y;
      final minX = xs.reduce(math.min), maxX = xs.reduce(math.max);
      final minY = ys.reduce(math.min), maxY = ys.reduce(math.max);
      for (var i = 0; i < xs.length; i++) {
        final onEdge = (xs[i] - minX).abs() < 0.01 ||
            (xs[i] - maxX).abs() < 0.01 ||
            (ys[i] - minY).abs() < 0.01 ||
            (ys[i] - maxY).abs() < 0.01;
        expect(onEdge, isTrue,
            reason: 'point ${xs[i]},${ys[i]} is not on the box');
      }
      expect(maxX - minX, greaterThan(250), reason: 'and it kept its size');
    });

    test('a wobbly triangle stays a triangle, and does not shrink', () {
      final rnd = math.Random(9);
      final pts = <(double, double)>[];
      void edge((double, double) a, (double, double) b) {
        for (var i = 0; i < 16; i++) {
          final t = i / 16;
          pts.add((
            a.$1 + (b.$1 - a.$1) * t + rnd.nextDouble() * 5 - 2.5,
            a.$2 + (b.$2 - a.$2) * t + rnd.nextDouble() * 5 - 2.5,
          ));
        }
      }
      edge((250, 80), (420, 320));
      edge((420, 320), (80, 320));
      edge((80, 320), (252, 86));
      final out = ShapeSnap.snap(strokeOf(pts));
      expect(out, isNotNull);
      final w = out!.x.reduce(math.max) - out.x.reduce(math.min);
      // The corner detector lands INSIDE the real vertices; without pulling
      // them back out the snapped triangle comes out visibly smaller than
      // the one that was drawn.
      expect(w, greaterThan(300), reason: 'it kept the size it was drawn at');
    });

    test('a circle that does not quite close is still a circle', () {
      // 320 degrees of it, which is what a quick hand actually produces.
      final pts = [
        for (var i = 0; i <= 54; i++)
          (
            300 + 90 * math.cos(i / 54 * 2 * math.pi * 0.89),
            300 + 90 * math.sin(i / 54 * 2 * math.pi * 0.89),
          )
      ];
      expect(ShapeSnap.snap(strokeOf(pts)), isNotNull,
          reason: 'holding still is a REQUEST to snap; refusing a gap a fifth '
              'of the width wide is the wrong kind of caution');
    });
  });

  group('what it refuses to touch', () {
    test('a flick is left alone', () {
      expect(ShapeSnap.snap(strokeOf([(0, 0), (3, 3), (6, 5)])), isNull);
    });

    test('a tiny scribble is left alone', () {
      expect(
          ShapeSnap.snap(strokeOf([
            for (var i = 0; i < 20; i++) (i.toDouble(), (i % 3).toDouble())
          ])),
          isNull,
          reason: 'below the size floor it is a dot or a tick, not a shape');
    });

    test('handwriting is left alone', () {
      // An open, curvy, non-straight stroke — the shape of a written letter.
      final rnd = math.Random(11);
      final pts = [
        for (var i = 0; i < 40; i++)
          (
            100 + i * 4.0 + rnd.nextDouble() * 20,
            200 + math.sin(i / 3) * 40 + rnd.nextDouble() * 15,
          )
      ];
      expect(ShapeSnap.snap(strokeOf(pts)), isNull,
          reason: 'open and not straight means it is writing, and writing is '
              'the thing this must never rewrite');
    });
  });
}
