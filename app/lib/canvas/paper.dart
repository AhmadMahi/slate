/// The sheet itself — its colour, its texture, or a picture of the user's own.
///
/// A page property (`PageProps.paper`), like the background pattern beside
/// it: the lecture you scribble on and the essay you hand in do not want the
/// same paper. Everything about a paper that the canvas and the two pickers
/// need to agree on lives here, so they cannot disagree.
library;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../theme/onote_theme.dart';
import '../ui/glass.dart' show paintAmbient;

/// The papers, in the order the pickers offer them. `image` is last because
/// choosing it opens a file dialog rather than applying at once.
const kPapers = [
  'ambient',
  'ambient-sunset',
  'ambient-ocean',
  'ambient-forest',
  'ambient-dusk',
  'ambient-aurora',
  'white',
  'grey',
  'cream',
  'texture',
  'slate',
  'sage',
  'sky',
  'blush',
  'charcoal',
  'midnight',
  'image',
];

String paperLabel(String paper) => switch (paper) {
      'ambient' => 'Ambient',
      'ambient-sunset' => 'Ambient sunset',
      'ambient-ocean' => 'Ambient ocean',
      'ambient-forest' => 'Ambient forest',
      'ambient-dusk' => 'Ambient dusk',
      'ambient-aurora' => 'Ambient aurora',
      'grey' => 'Grey',
      'cream' => 'Cream',
      'texture' => 'Paper texture',
      'slate' => 'Blue grey',
      'sage' => 'Sage',
      'sky' => 'Sky',
      'blush' => 'Blush',
      'charcoal' => 'Charcoal',
      'midnight' => 'Midnight',
      'image' => 'Picture',
      _ => 'White',
    };

/// The flat colour under everything else on the sheet.
///
/// Dark mode keeps the FAMILY of each paper — grey stays a step lighter than
/// the night page, cream stays warm — rather than inverting it, so switching
/// theme changes the light in the room and not the paper on the desk.
Color paperColor(String paper, {required bool dark}) => switch (paper) {
      // The default: a near-white with the room's glow laid over it — see
      // `paintPaperDetail` and `paintAmbient`.
      'ambient' => dark ? const Color(0xFF15161C) : const Color(0xFFF9FAFF),
      // The variants keep a near-neutral sheet; the glow gives the colour.
      'ambient-sunset' =>
        dark ? const Color(0xFF181410) : const Color(0xFFFFF7F0),
      'ambient-ocean' =>
        dark ? const Color(0xFF10171B) : const Color(0xFFF0FAFC),
      'ambient-forest' =>
        dark ? const Color(0xFF121810) : const Color(0xFFF2FAF2),
      'ambient-dusk' =>
        dark ? const Color(0xFF16151E) : const Color(0xFFF8F5FF),
      'ambient-aurora' =>
        dark ? const Color(0xFF10181A) : const Color(0xFFF1FBF6),
      'grey' => dark ? const Color(0xFF232328) : const Color(0xFFECECEF),
      'cream' => dark ? const Color(0xFF211F1A) : const Color(0xFFF8F2E2),
      'texture' => dark ? const Color(0xFF1F1D19) : const Color(0xFFF4EEDE),
      // Soft tints for a light page.
      'slate' => dark ? const Color(0xFF1A1F26) : const Color(0xFFEDF1F6),
      'sage' => dark ? const Color(0xFF19201B) : const Color(0xFFEDF3EC),
      'sky' => dark ? const Color(0xFF151D25) : const Color(0xFFE9F2FB),
      'blush' => dark ? const Color(0xFF221A1E) : const Color(0xFFFBEEF1),
      // Dark sheets, dark in either theme, for a dark-background look.
      'charcoal' => dark ? const Color(0xFF17191E) : const Color(0xFF2B2F36),
      'midnight' => dark ? const Color(0xFF12141F) : const Color(0xFF1E2536),
      _ => dark ? OnoteColors.night0 : OnoteColors.paper0,
    };

/// The pattern-line colour that reads on this paper. The greys that sit on
/// white vanish on cream and shout on grey, so each paper names its own.
Color paperRuleColor(String paper, {required bool dark}) {
  // The whole ambient family shares one quiet rule: the glow is the texture,
  // the dots only a beat.
  if (paper.startsWith('ambient')) {
    return dark
        ? Colors.white.withValues(alpha: .10)
        : const Color(0xFF1F2433).withValues(alpha: .11);
  }
  return switch (paper) {
      'grey' => dark ? const Color(0xFF35353C) : const Color(0xFFD8D8DD),
      'cream' ||
      'texture' =>
        dark ? const Color(0xFF3A362C) : const Color(0xFFE2D9C2),
      'slate' => dark
          ? Colors.white.withValues(alpha: .10)
          : const Color(0xFF2A3340).withValues(alpha: .12),
      'sage' => dark
          ? Colors.white.withValues(alpha: .10)
          : const Color(0xFF2A3A2E).withValues(alpha: .12),
      'sky' => dark
          ? Colors.white.withValues(alpha: .10)
          : const Color(0xFF213241).withValues(alpha: .12),
      'blush' => dark
          ? Colors.white.withValues(alpha: .10)
          : const Color(0xFF3A2A30).withValues(alpha: .12),
      // Dark sheets carry a light rule in both themes.
      'charcoal' || 'midnight' => Colors.white.withValues(alpha: .10),
      _ => dark ? OnoteColors.night200 : OnoteColors.paper200,
    };
}

/// A repeating tile of paper grain, drawn once per theme and shared.
///
/// Procedural rather than a bundled bitmap: a few hundred faint specks and
/// fibres from a fixed seed are all the eye needs to read "paper", they cost
/// nothing to ship, and a seeded generator gives the same grain on every
/// machine. Built synchronously (`toImageSync`) so the first frame has it.
ui.Image paperGrainTile({required bool dark}) => dark
    ? (_tileDark ??= _grain(dark: true))
    : (_tileLight ??= _grain(dark: false));

ui.Image? _tileLight, _tileDark;
const _tile = 128.0;

ui.Image _grain({required bool dark}) {
  final rec = ui.PictureRecorder();
  final c = Canvas(rec, const Rect.fromLTWH(0, 0, _tile, _tile));
  final rnd = math.Random(7);
  final speck = Paint()
    ..color = (dark ? Colors.white : const Color(0xFF6B5A3A))
        .withValues(alpha: dark ? .035 : .07);
  for (var i = 0; i < 260; i++) {
    c.drawCircle(Offset(rnd.nextDouble() * _tile, rnd.nextDouble() * _tile),
        .5 + rnd.nextDouble() * .9, speck);
  }
  final fibre = Paint()
    ..color = (dark ? Colors.white : const Color(0xFF8A7650))
        .withValues(alpha: dark ? .025 : .05)
    ..strokeWidth = .7;
  for (var i = 0; i < 18; i++) {
    final p = Offset(rnd.nextDouble() * _tile, rnd.nextDouble() * _tile);
    final a = rnd.nextDouble() * math.pi;
    final l = 6 + rnd.nextDouble() * 14;
    c.drawLine(p, p + Offset(math.cos(a) * l, math.sin(a) * l), fibre);
  }
  return rec.endRecording().toImageSync(_tile.toInt(), _tile.toInt());
}

/// Paint the paper's detail — grain or picture — inside [rect].
///
/// [image] is the decoded picture when the paper is `image`; null while it
/// loads, in which case the flat colour already painted stands in. A picture
/// COVERS a sheet (cropped, never squashed), and on an open canvas it is
/// fitted to the page width and repeated down it, so a boundless page has
/// paper all the way down.
void paintPaperDetail(Canvas canvas, Rect rect, String paper,
    {required bool dark, ui.Image? image, bool cover = true}) {
  if (paper.startsWith('ambient')) {
    paintAmbient(canvas, rect, dark: dark, variant: paper);
    return;
  }
  if (paper == 'texture') {
    final tile = paperGrainTile(dark: dark);
    canvas.drawRect(
        rect,
        Paint()
          ..shader = ui.ImageShader(tile, TileMode.repeated, TileMode.repeated,
              Matrix4.identity().storage));
    return;
  }
  if (paper == 'image' && image != null) {
    final iw = image.width.toDouble(), ih = image.height.toDouble();
    final src = Rect.fromLTWH(0, 0, iw, ih);
    canvas.save();
    canvas.clipRect(rect);
    if (cover) {
      final s = math.max(rect.width / iw, rect.height / ih);
      final w = iw * s, h = ih * s;
      canvas.drawImageRect(
          image,
          src,
          Rect.fromLTWH(rect.left - (w - rect.width) / 2,
              rect.top - (h - rect.height) / 2, w, h),
          Paint()..filterQuality = FilterQuality.medium);
    } else {
      final h = ih * (rect.width / iw);
      for (var y = rect.top; y < rect.bottom; y += h) {
        canvas.drawImageRect(
            image,
            src,
            Rect.fromLTWH(rect.left, y, rect.width, h),
            Paint()..filterQuality = FilterQuality.medium);
        if (h <= 1) break;
      }
    }
    canvas.restore();
  }
}
