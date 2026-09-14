// The colour a stroke is SHOWN in depends on the page it is shown on: black
// on a dark page and white on a light page are both invisible, and both are
// in real notebooks. The stored colour never changes; only the display swaps.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/canvas/ink_painter.dart';
import 'package:openote/theme/onote_theme.dart';

void main() {
  test('black is shown white on a dark page, and only there', () {
    expect(themedInk(const Color(0xFF000000), dark: true), OnoteColors.moon0);
    expect(themedInk(OnoteColors.graphite900, dark: true), OnoteColors.moon0,
        reason: 'the warm default ink counts as black');
    expect(themedInk(OnoteColors.graphite900, dark: false),
        OnoteColors.graphite900);
  });

  test('white is shown black on a light page, and only there', () {
    expect(themedInk(const Color(0xFFFFFFFF), dark: false),
        OnoteColors.graphite900);
    expect(themedInk(OnoteColors.moon0, dark: false), OnoteColors.graphite900,
        reason: 'what dark mode has always written for "black"');
    expect(themedInk(OnoteColors.moon0, dark: true), OnoteColors.moon0);
  });

  test('anything with a hue keeps it, on either page', () {
    for (final c in const [
      Color(0xFF2F6FB3), // the palette blue
      OnoteColors.danger,
      OnoteColors.success,
      Color(0xFFF7E27A), // highlighter yellow — light, but not white
      Color(0xFF6A4BC0),
    ]) {
      expect(themedInk(c, dark: true), c, reason: '$c');
      expect(themedInk(c, dark: false), c, reason: '$c');
    }
  });
}
