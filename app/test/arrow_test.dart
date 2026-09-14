// The arrow tool: a drag with two ends and a head on the one you finish at.
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:openote/ink/arrow.dart';
import 'package:openote/ink/shape_snap.dart' show Offset2;

void main() {
  List<double> allX(List<dynamic> strokes) =>
      [for (final s in strokes) ...(s.x as List<double>)];

  test('it is three strokes: a shaft and two barbs', () {
    final a = arrowStrokes(
        from: const Offset2(100, 100),
        to: const Offset2(300, 100),
        colorHex: '#112233',
        size: 3);
    expect(a.length, 3,
        reason: 'one polyline doubling back on itself pinches where it '
            'reverses under a variable-width ink engine');
    for (final s in a) {
      expect(s.colorHex, '#112233');
      expect(s.size, 3);
    }
  });

  test('the head is at the END you finish at', () {
    const from = Offset2(100, 100);
    const to = Offset2(300, 100);
    final a = arrowStrokes(
        from: from, to: to, colorHex: '#000000', size: 3);
    // Both barbs touch the finishing point and trail back towards the start.
    for (final barb in a.skip(1)) {
      final endX = barb.x.last, endY = barb.y.last;
      expect(endX, closeTo(to.x, 0.01));
      expect(endY, closeTo(to.y, 0.01));
      expect(barb.x.first, lessThan(to.x),
          reason: 'the barb comes back from the head, not past it');
    }
  });

  test('a short drag still gets a head that fits inside it', () {
    // Without a cap the head is longer than the shaft: an arrowhead with no
    // arrow behind it.
    final a = arrowStrokes(
        from: const Offset2(0, 0),
        to: const Offset2(20, 0),
        colorHex: '#000000',
        size: 8);
    expect(a, isNotEmpty);
    final xs = allX(a);
    expect(xs.reduce(math.min), greaterThanOrEqualTo(-0.01),
        reason: 'the head does not reach back past where the drag began');
  });

  test('a drag that went nowhere makes nothing', () {
    expect(
        arrowStrokes(
            from: const Offset2(50, 50),
            to: const Offset2(50, 50),
            colorHex: '#000000',
            size: 3),
        isEmpty,
        reason: 'a head with no direction points nowhere');
  });

  test('it points the way it was drawn, in every direction', () {
    const from = Offset2(200, 200);
    for (final to in [
      const Offset2(400, 200),
      const Offset2(200, 400),
      const Offset2(50, 60),
      const Offset2(90, 380),
    ]) {
      final a = arrowStrokes(
          from: from, to: to, colorHex: '#000000', size: 2);
      expect(a.length, 3, reason: '$to');
      // The shaft runs from the start to the finish.
      expect(a.first.x.first, closeTo(from.x, 0.01));
      expect(a.first.y.first, closeTo(from.y, 0.01));
      expect(a.first.x.last, closeTo(to.x, 0.01));
      expect(a.first.y.last, closeTo(to.y, 0.01));
    }
  });
}
