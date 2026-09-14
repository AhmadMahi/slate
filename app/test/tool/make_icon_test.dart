// Draws the app icon and writes it to assets/icon/slate_icon.png.
//
// A test rather than a script because rendering to a PNG needs a Flutter
// binding, and `flutter test` is the only way to get one without a device.
// It asserts nothing about the app; run it with:
//
//     flutter test test/tool/make_icon_test.dart
//
// then `dart run flutter_launcher_icons` to cut the platform sizes.
//
// THE DESIGN, and why each part is there:
//
//  * A NIB ON PAPER. The two things the app is: handwriting, and a sheet.
//    Drawn as one silhouette rather than an illustration, because the icon
//    has to survive being 16px in a menu bar, where any interior detail turns
//    to mud.
//  * The nib sits ON the sheet's diagonal fold, so at small sizes the shape
//    still reads as two overlapping objects rather than one blob.
//  * The ink stroke trailing from the tip is the only "action" in it, and it
//    is what stops the mark reading as a paper aeroplane.
//  * Colours come from the app's own palette — graphite paper, the Classic
//    blue for the nib — so the icon and the first thing you see inside it
//    agree.
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _size = 1024.0;

void main() {
  test('render the app icon', () async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, const Rect.fromLTWH(0, 0, _size, _size));
    _paintIcon(canvas);
    final picture = recorder.endRecording();
    final image = await picture.toImage(_size.toInt(), _size.toInt());
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final out = File('assets/icon/slate_icon.png');
    out.parent.createSync(recursive: true);
    out.writeAsBytesSync(bytes!.buffer.asUint8List());
    expect(out.lengthSync(), greaterThan(1000));
  });
}

void _paintIcon(Canvas canvas) {
  const r = _size;
  final full = Rect.fromLTWH(0, 0, r, r);

  // The ground: a squircle in slate, lit from the top-left the way macOS
  // icons are. Not a full-bleed square — every other icon in the Dock is
  // rounded, and a hard square reads as a screenshot of an icon.
  final squircle = RRect.fromRectAndRadius(
      full.deflate(r * 0.06), Radius.circular(r * 0.225));
  canvas.drawRRect(
    squircle,
    Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF3C4557), Color(0xFF222834)],
      ).createShader(full),
  );

  canvas.save();
  canvas.clipRRect(squircle);

  // THE SHEET: a page with its top-right corner turned down. Rotated a few
  // degrees so the icon has a direction; upright would read as a document
  // icon, which is what this is not.
  canvas.translate(r * 0.5, r * 0.53);
  canvas.rotate(-0.10);
  canvas.translate(-r * 0.5, -r * 0.53);

  const sheetW = r * 0.44;
  const sheetH = r * 0.56;
  final sheetL = (r - sheetW) / 2;
  const sheetT = r * 0.24;
  const fold = r * 0.13;

  final sheet = Path()
    ..moveTo(sheetL, sheetT)
    ..lineTo(sheetL + sheetW - fold, sheetT)
    ..lineTo(sheetL + sheetW, sheetT + fold)
    ..lineTo(sheetL + sheetW, sheetT + sheetH)
    ..lineTo(sheetL, sheetT + sheetH)
    ..close();

  // A soft drop shadow lifts the sheet off the ground without an outline,
  // which is what keeps the silhouette clean at 16px.
  canvas.drawPath(
      sheet.shift(const Offset(0, r * 0.012)),
      Paint()
        ..color = Colors.black.withValues(alpha: .28)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18));
  canvas.drawPath(sheet, Paint()..color = const Color(0xFFF6F4EF));

  // The turned corner, darker so the fold is legible as a fold.
  canvas.drawPath(
      Path()
        ..moveTo(sheetL + sheetW - fold, sheetT)
        ..lineTo(sheetL + sheetW, sheetT + fold)
        ..lineTo(sheetL + sheetW - fold, sheetT + fold)
        ..close(),
      Paint()..color = const Color(0xFFD9D4C9));

  // Two ruled lines, high on the sheet and clear of the nib. Two, not five:
  // at small sizes more becomes a grey band. Kept ABOVE the nib rather than
  // behind it — a pair of short bars either side of a point is the other half
  // of the face the first version accidentally drew.
  final rule = Paint()
    ..color = const Color(0xFFC9C3B6)
    ..strokeWidth = r * 0.015
    ..strokeCap = StrokeCap.round;
  for (var i = 0; i < 2; i++) {
    final y = sheetT + sheetH * (0.14 + i * 0.13);
    canvas.drawLine(Offset(sheetL + sheetW * 0.15, y),
        Offset(sheetL + sheetW * (i == 0 ? 0.78 : 0.60), y), rule);
  }

  canvas.restore();

  // THE NIB, over the sheet's lower half and running off its edge — the
  // overlap is what makes two objects read as two at a glance.
  canvas.save();
  canvas.translate(r * 0.60, r * 0.62);
  canvas.rotate(math.pi * 0.75);

  const nibLen = r * 0.30;
  const nibHalf = r * 0.075;
  final nib = Path()
    ..moveTo(0, 0)
    ..lineTo(nibHalf, nibLen * 0.42)
    ..lineTo(nibHalf * 0.55, nibLen)
    ..lineTo(-nibHalf * 0.55, nibLen)
    ..lineTo(-nibHalf, nibLen * 0.42)
    ..close();

  canvas.drawPath(
      nib.shift(const Offset(0, r * 0.010)),
      Paint()
        ..color = Colors.black.withValues(alpha: .35)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14));
  canvas.drawPath(
    nib,
    Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF5C8FD6), Color(0xFF2F6FB3)],
      ).createShader(Rect.fromLTWH(-nibHalf, 0, nibHalf * 2, nibLen)),
  );

  // The slit down the middle, which is the one detail that says "nib" rather
  // than "arrow". Kept to a single line so it survives downscaling.
  canvas.drawLine(
      const Offset(0, nibLen * 0.30),
      const Offset(0, nibLen * 0.92),
      Paint()
        ..color = const Color(0xFF1B4B80)
        ..strokeWidth = r * 0.012
        ..strokeCap = StrokeCap.round);
  canvas.restore();

  // The ink it just laid down: a short stroke TRAILING FROM THE TIP.
  //
  // The first cut put a wide symmetric arc across the lower half of the
  // sheet. Under two ruled lines that reads as a mouth under two eyes — the
  // icon was a face, which is the sort of thing you only see once it is
  // rendered. It starts at the nib's point now and runs off to one side, so
  // it is a mark being made rather than a shape in its own right.
  final ink = Path()
    ..moveTo(r * 0.600, r * 0.632)
    ..cubicTo(r * 0.660, r * 0.690, r * 0.700, r * 0.706, r * 0.760, r * 0.700);
  canvas.drawPath(
      ink,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.026
        ..strokeCap = StrokeCap.round
        ..color = const Color(0xFF8BF224));

  canvas.restore();
}
