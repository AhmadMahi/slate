// The rectangle tool: a drag from one corner to the opposite one, traced as
// a single closed loop in the pen's colour and weight.
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:openote/ink/rectangle.dart';
import 'package:openote/ink/shape_snap.dart' show Offset2;
import 'package:openote/model/models.dart' show Stroke;

void main() {
  test('it is one closed stroke that returns to where it began', () {
    final r = rectangleStrokes(
        from: const Offset2(100, 100),
        to: const Offset2(300, 200),
        colorHex: '#112233',
        size: 3);
    expect(r.length, 1,
        reason: 'a rectangle never doubles back on its own path, so one '
            'stroke has no pinch to split out');
    final s = r.single;
    expect(s.colorHex, '#112233');
    expect(s.size, 3);
    // The loop is closed: last point sits on the first.
    expect(s.x.last, closeTo(s.x.first, 0.01));
    expect(s.y.last, closeTo(s.y.first, 0.01));
    // It is a sharp shape: the renderer must keep its corners square.
    expect(s.sharp, isTrue);
  });

  test('the sharp flag round-trips, and is absent by default', () {
    final rect = rectangleStrokes(
            from: const Offset2(0, 0),
            to: const Offset2(50, 50),
            colorHex: '#000000',
            size: 2)
        .single;
    expect(rect.toJson()['sharp'], true);
    expect(Stroke.fromJson(rect.toJson()).sharp, isTrue);
    // A normal pen stroke stays sharp-free, so its ink blob is unchanged.
    final pen = Stroke(tool: 'pen', colorHex: '#000000', size: 2);
    expect(pen.sharp, isFalse);
    expect(pen.toJson().containsKey('sharp'), isFalse);
  });

  test('it spans exactly the two corners, in any drag direction', () {
    // Dragging up-left must give the same box as dragging down-right.
    for (final (from, to) in [
      (const Offset2(100, 100), const Offset2(300, 200)),
      (const Offset2(300, 200), const Offset2(100, 100)),
      (const Offset2(300, 100), const Offset2(100, 200)),
    ]) {
      final s = rectangleStrokes(
              from: from, to: to, colorHex: '#000000', size: 2)
          .single;
      expect(s.x.reduce(math.min), closeTo(100, 0.01), reason: '$from→$to');
      expect(s.x.reduce(math.max), closeTo(300, 0.01), reason: '$from→$to');
      expect(s.y.reduce(math.min), closeTo(100, 0.01), reason: '$from→$to');
      expect(s.y.reduce(math.max), closeTo(200, 0.01), reason: '$from→$to');
    }
  });

  test('every drawn point stays on the box edge, never inside it', () {
    final s = rectangleStrokes(
            from: const Offset2(0, 0),
            to: const Offset2(120, 80),
            colorHex: '#000000',
            size: 2)
        .single;
    for (var i = 0; i < s.x.length; i++) {
      final onVertical = (s.x[i] - 0).abs() < 0.01 || (s.x[i] - 120).abs() < 0.01;
      final onHorizontal =
          (s.y[i] - 0).abs() < 0.01 || (s.y[i] - 80).abs() < 0.01;
      expect(onVertical || onHorizontal, isTrue,
          reason: 'point ($i) at ${s.x[i]},${s.y[i]} left the perimeter');
    }
  });

  test('a drag that went nowhere makes nothing', () {
    expect(
        rectangleStrokes(
            from: const Offset2(50, 50),
            to: const Offset2(50, 50),
            colorHex: '#000000',
            size: 3),
        isEmpty,
        reason: 'a box with no size is a dot, not a rectangle');
  });
}
