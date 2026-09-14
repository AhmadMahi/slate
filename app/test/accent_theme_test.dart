// Seven accents, and each one is a THEME: the chrome takes a wash of it, the
// page never does, and blue is exactly what every earlier build drew.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/theme/onote_theme.dart';
import 'package:openote/theme/tokens.dart';

void main() {
  test('the accent is the primary colour, in both modes', () {
    for (final a in OnoteAccent.values) {
      expect(
          onoteTheme(Brightness.light, accent: a).colorScheme.primary, a.light,
          reason: a.label);
      expect(onoteTheme(Brightness.dark, accent: a).colorScheme.primary, a.dark,
          reason: a.label);
    }
  });

  test('the chrome takes a wash of the accent; the page does not', () {
    final s = onoteTheme(Brightness.light, accent: OnoteAccent.green).surfaces;
    expect(s.chrome, isNot(OnoteSurfaces.light.chrome));
    expect(s.chrome2, isNot(OnoteSurfaces.light.chrome2));
    expect(s.canvas, OnoteSurfaces.light.canvas,
        reason: 'the paper is the paper whatever the app is wearing');
    expect(s.textPrimary, OnoteSurfaces.light.textPrimary);
  });

  test('blue is the default, and is the blue every earlier build drew', () {
    expect(
        onoteTheme(Brightness.light).colorScheme.primary, OnoteColors.ink500);
    expect(onoteTheme(Brightness.dark).colorScheme.primary, OnoteColors.ink400);
  });
}
