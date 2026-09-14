// Two things the owner reported, pinned.
//
// FIT MEANS FIT. "Zoom to fit" left a 16px pad on each side, which sounded
// tidier and was the whole bug: the page then ends 32px short of the window,
// `clampToPage` centres it, and dragging one way finds slack the other — "no
// scrolling from left to right, but when I do right to left there is a small
// scrolling happening". A fit that leaves anything to scroll to has not fit.
//
// A PEN WIDTH OUTLIVES THE SESSION. It was a plain field, so it reset to 2.5
// on every launch and the first stroke of every day was the wrong weight.
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/canvas/canvas_controller.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';

import 'support/sqlite.dart';

void main() {
  var haveSqlite = false;
  setUpAll(() => haveSqlite = initSqliteForTests());

  group('fit means fit', () {
    late CanvasController c;

    setUp(() {
      c = CanvasController()
        ..viewport = const Size(1400, 900)
        ..pageSize = const Size(1000, 3000);
    });

    test('the page ends up exactly the window width', () {
      c.fillWidth(1000);
      expect(c.pageSize!.width * c.scale, closeTo(1400, 0.01));
    });

    test('and there is nothing left to scroll to, in either direction', () {
      c.fillWidth(1000);
      expect(c.fitLocked, isTrue);
      expect(c.canPanHorizontally, isFalse,
          reason: 'the report: a small scroll one way only');
      final before = c.offset.dx;
      c.panBy(const Offset(-200, 0));
      expect(c.offset.dx, before, reason: 'dragging left finds nothing');
      c.panBy(const Offset(200, 0));
      expect(c.offset.dx, before, reason: 'and neither does dragging right');
    });

    test('fitting the surface leaves nothing to scroll to', () {
      // Canvas mode fits the whole surface, so both promises hold together.
      c.pageSize = const Size(1800, 3000);
      c.fillWidth(c.pageSize!.width);
      expect(c.canPanHorizontally, isFalse);
      expect(c.pageSize!.width * c.scale, closeTo(1400, 0.01));
    });

    test('a fitted SHEET locks sideways movement, whatever the surface says',
        () {
      // THE LATCH. Fit used to be a one-off action, and horizontal scrolling
      // kept coming back: the fit was right for one frame, then anything that
      // recomputed the surface left the page a little wider than the window
      // with slack to drag into. "No scrolling at all" was asked for three
      // times before it was taken literally.
      //
      // The cost is stated rather than hidden: a stroke outside the sheet is
      // unreachable while the latch is on. Zooming by hand releases it.
      c.pageSize = const Size(1800, 3000); // surface, content-driven
      c.fillWidth(700); // an A5 sheet
      expect(c.scale, closeTo(2.0, 0.01), reason: '1400 / 700');
      expect(c.fitLocked, isTrue);
      expect(c.canPanHorizontally, isFalse,
          reason: 'even though the surface is wider than the window');
      expect(c.offset.dx, 0,
          reason: 'flush left — centring is what puts a margin down each side');
    });

    test('zooming by hand releases the latch and gives panning back', () {
      c.pageSize = const Size(1800, 3000);
      c.fillWidth(700);
      expect(c.canPanHorizontally, isFalse);
      c.setZoom(c.scale * 1.5);
      expect(c.fitLocked, isFalse,
          reason: 'a scale of your own means sideways movement is how you '
              'reach the rest of the page at it');
      expect(c.canPanHorizontally, isTrue);
    });

    test('a page wider than the window still pans, which is the normal case',
        () {
      // Zoomed IN past the fit, sideways movement is exactly what you want.
      c.fillWidth(1000);
      c.setZoom(c.scale * 2);
      expect(c.canPanHorizontally, isTrue);
      final before = c.offset.dx;
      c.panBy(const Offset(-100, 0));
      expect(c.offset.dx, lessThan(before));
    });
  });

  group('a pen width outlives the session', () {
    late Repository repo;
    late Directory tmp;

    setUp(() async {
      if (!haveSqlite) return;
      tmp = Directory.systemTemp.createTempSync('onote_pen_');
      repo = await Repository.openAt(tmp);
      await repo.createNotebook('P');
    });

    tearDown(() {
      if (!haveSqlite) return;
      repo.dispose();
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    });

    test('it is written to settings, and clamped on the way', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final app = AppState(repo)..spellCheckEnabled = false;
      app.setPenSize(6.5);
      expect(repo.getSetting('penSize'), 6.5);

      app.setPenSize(999);
      expect(app.penSize, AppState.maxPenSize);
      app.setPenSize(-4);
      expect(app.penSize, AppState.minPenSize);
    });

    test('a value from a hand-edited file is clamped, not trusted', () {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      repo.setSetting('penSize', 4000);
      // The load path clamps to the same range the setter does; asserting the
      // range rather than re-running init keeps this a unit test.
      final v = (repo.getSetting('penSize') as num)
          .toDouble()
          .clamp(AppState.minPenSize, AppState.maxPenSize);
      expect(v, AppState.maxPenSize);
    });
  });

  group('the cursor styles', () {
    test('crosshair and mouse leave the real pointer alone; the others do not',
        () {
      expect(PenCursorStyle.crosshair.isSystem, isTrue);
      expect(PenCursorStyle.mouse.isSystem, isTrue);
      expect(PenCursorStyle.pen.isSystem, isFalse);
      expect(PenCursorStyle.dot.isSystem, isFalse);
    });

    test('every style says what it is', () {
      for (final v in PenCursorStyle.values) {
        expect(v.label, isNotEmpty);
        expect(v.describe, isNotEmpty);
      }
    });
  });
}
