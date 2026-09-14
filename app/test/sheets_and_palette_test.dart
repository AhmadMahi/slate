// Sheets you can reach before you have filled them, and a palette you own.
//
// ROOM TO KEEP WRITING. Page 2 did not exist until something had been drawn
// near the bottom of page 1: the surface stopped where the content did, so to
// get room you had to first put something in the room you did not have. Paper
// on a desk does not work that way. The blanks are deliberately kept OUT of
// `sheetCount`, which is what the document IS — an export that gained two
// empty pages because somebody scrolled would be a worse bug than the one
// this fixes.
//
// MOVING A SHEET MOVES ITS CONTENT. A list of page numbers you can drag but
// which leaves the writing behind is a lie told convincingly. Everything is
// decided by the TOP of a thing and then moved by one delta, so a stroke that
// crosses a page break is not torn in half.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/model/models.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';
import 'package:openote/theme/ink_palettes.dart';

import 'support/sqlite.dart';

void main() {
  var haveSqlite = false;
  setUpAll(() => haveSqlite = initSqliteForTests());

  late Repository repo;
  late Directory tmp;
  late AppState app;
  late double h;

  setUp(() async {
    if (!haveSqlite) return;
    AppState.syncLogEnabled = false;
    tmp = Directory.systemTemp.createTempSync('onote_sheets_');
    repo = await Repository.openAt(tmp);
    final nb = await repo.createNotebook('S');
    app = AppState(repo)
      ..notebookId = nb.id
      ..spellCheckEnabled = false;
    app.reloadNodes();
    final section = app.importNode(
        nb.id, TreeNode(kind: NodeKind.section, title: 'S', position: 'a0'));
    final page = app.importNode(
        nb.id,
        TreeNode(
            kind: NodeKind.page,
            parentId: section.id,
            title: 'P',
            position: 'a1'));
    app.reloadNodes();
    await app.selectPage(page.id);
    app.pageProps.layout = 'paged';
    app.pageProps.paperSize = 'A4';
    h = app.pageProps.paper.height;
  });

  tearDown(() {
    if (!haveSqlite) return;
    AppState.syncLogEnabled = true;
    app.cancelPendingSave();
    repo.dispose();
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('room to keep writing', () {
    test('an empty page can still be scrolled onto page 2 and 3', () {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      app.blocks = [];
      expect(app.sheetCount, 1, reason: 'the document is one page');
      expect(app.scrollableSheetCount, 1 + AppState.spareSheets,
          reason: 'and there is paper under it');
    });

    test('the spare paper is NOT part of the document', () {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      app.blocks = [];
      expect(app.sheetCount, lessThan(app.scrollableSheetCount),
          reason: 'an export must not gain blank pages from scrolling');
    });

    test('adding a page is remembered on the page itself', () {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final before = app.scrollableSheetCount;
      app.addSheet();
      expect(app.scrollableSheetCount, before + 1);
      expect(app.pageProps.addedSheets, 1);
      // Written only when it says something, like every other page property.
      expect(PageProps().toJson().containsKey('addedSheets'), isFalse);
      expect(app.pageProps.toJson()['addedSheets'], 1);
    });
  });

  group('moving a sheet moves its content', () {
    late Block onOne, onTwo;

    setUp(() {
      if (!haveSqlite) return;
      onOne = Block(type: BlockType.image, x: 100, y: 50, w: 80, h: 80);
      onTwo = Block(type: BlockType.image, x: 100, y: h + 50, w: 80, h: 80);
      app.blocks = [onOne, onTwo];
    });

    test('swapping the first two pages swaps what is on them', () {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      app.moveSheet(0, 1);
      expect(onOne.y, closeTo(h + 50, 0.01), reason: 'page 1 went down');
      expect(onTwo.y, closeTo(50, 0.01), reason: 'page 2 came up');
    });

    test('a stroke crossing a page break is not torn in half', () {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final ink = Block(type: BlockType.ink, x: 0, y: 0, content: {
        'strokes': [
          Stroke(
            tool: 'pen',
            colorHex: '#000000',
            size: 2,
            // Starts near the bottom of page 1 and runs onto page 2.
            x: [10, 20],
            y: [h - 10, h + 10],
            p: [0.5, 0.5],
          ).toJson(),
        ],
      });
      app.blocks = [ink];
      app.moveSheet(0, 1);
      final ys = ((ink.content['strokes'] as List).first as Map)['y'] as List;
      final moved = [for (final v in ys) (v as num).toDouble()];
      // Both points moved by the SAME page: decided by the stroke's top.
      expect(moved[1] - moved[0], closeTo(20, 0.01),
          reason: 'the stroke kept its shape');
      expect(moved[0], closeTo(h - 10 + h, 0.01));
    });

    test('moving a sheet onto itself does nothing at all', () {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final rev = app.docRevision;
      app.moveSheet(1, 1);
      expect(app.docRevision, rev);
      expect(onOne.y, 50);
    });
  });

  group('deleting a sheet removes it', () {
    test('page 1 goes and page 2 becomes page 1', () {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final onOne = Block(type: BlockType.image, x: 100, y: 50, w: 80, h: 80);
      final onTwo =
          Block(type: BlockType.image, x: 100, y: h + 50, w: 80, h: 80);
      app.blocks = [onOne, onTwo];
      app.deleteSheet(0);
      expect(app.blocks.contains(onOne), isFalse,
          reason: 'page 1 content is gone');
      expect(app.blocks, contains(onTwo));
      expect(onTwo.y, closeTo(50, 0.01), reason: 'page 2 came up to page 1');
    });

    test('deleting an added blank page is one fewer added page', () {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      app.blocks = [];
      app.addSheet();
      final before = app.scrollableSheetCount;
      app.deleteSheet(app.sheetCount); // the first blank past the content
      expect(app.pageProps.addedSheets, 0);
      expect(app.scrollableSheetCount, before - 1);
    });

    test('a pure spare page cannot be deleted', () {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      app.blocks = [];
      final rev = app.docRevision;
      app.deleteSheet(app.scrollableSheetCount - 1);
      expect(app.docRevision, rev, reason: 'a spare is scroll room, not a page');
    });
  });

  group('the palette is yours, up to four', () {
    test('a colour can be added until the ceiling, then not', () {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      app.setTool(Tool.pen);
      app.penPalette = ['#111111'];
      app.addInkColor('#222222');
      expect(app.penPalette.length, 2);
      expect(app.penColor, 1, reason: 'the new colour is the armed one');

      while (app.penPalette.length < AppState.maxPaletteColours) {
        app.addInkColor('#333333');
      }
      app.addInkColor('#444444');
      expect(app.penPalette.length, AppState.maxPaletteColours,
          reason: 'four is the ceiling, and asking again is a no-op');
    });

    test('the last colour cannot be removed', () {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      app.setTool(Tool.pen);
      app.penPalette = ['#111111'];
      app.removeInkColor(0);
      expect(app.penPalette.length, 1,
          reason: 'a pen with no colour is not a state anything handles');
    });

    test('removing keeps something armed', () {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      app.setTool(Tool.pen);
      app.penPalette = ['#111111', '#222222', '#333333'];
      app.penColor = 2;
      app.removeInkColor(2);
      expect(app.penColor, lessThan(app.penPalette.length));
    });

    test('a preset replaces the row and never exceeds four', () {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      app.setTool(Tool.pen);
      for (final p in InkPalettes.presets) {
        app.applyInkPalette(p);
        expect(app.penPalette.length,
            lessThanOrEqualTo(AppState.maxPaletteColours));
        expect(app.penColor, 0);
        expect(app.activePaletteName, p.name);
      }
    });

    test('cycling wraps round the palette, whatever its length', () {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      app.setTool(Tool.pen);
      app.penPalette = ['#111111', '#222222', '#333333'];
      app.penColor = 0;
      app.cycleInkColor(1);
      expect(app.penColor, 1);
      app.cycleInkColor(1);
      expect(app.penColor, 2);
      app.cycleInkColor(1);
      expect(app.penColor, 0, reason: 'round robin, which is the whole point');
    });
  });

  group('a stored palette from an older build survives', () {
    // THE ONE THAT SHIPPED WRONG. The palettes used to hold six colours. When
    // the ceiling became four, the load path still demanded an exact length
    // match, so a stored six-colour row failed the check and was ignored
    // WHOLESALE — a hand-picked palette silently replaced by the default,
    // with nothing on screen to say why. Caught by installing the build and
    // looking at the swatches, which did not match the settings file.
    const stored = [
      '#211F1B',
      '#8BF224',
      '#C63838',
      '#2E8B57',
      '#248BF2',
      '#D9971F',
    ];
    const fallback = ['#000000'];

    test('six stored colours become the first four, not the default', () {
      expect(AppState.truncatePalette(stored, fallback),
          stored.take(AppState.maxPaletteColours).toList(),
          reason: 'their colours, in their order — not the default palette');
    });

    test('a palette already within the ceiling is untouched', () {
      const four = ['#111111', '#222222', '#333333', '#444444'];
      expect(AppState.truncatePalette(four, fallback), four);
    });

    test('anything unusable falls back rather than emptying the row', () {
      // A pen with no colour is not a state anything downstream handles.
      expect(AppState.truncatePalette(const <String>[], fallback), fallback);
      expect(AppState.truncatePalette(null, fallback), fallback);
      expect(AppState.truncatePalette('#ff0000', fallback), fallback);
      expect(AppState.truncatePalette(const [1, 2, 3], fallback), fallback,
          reason: 'a list of the wrong thing is not a palette');
    });
  });

  group('every preset is fit to write with', () {
    test('four colours, all parseable, no duplicates', () {
      for (final p in InkPalettes.presets) {
        expect(p.colours.length, 4, reason: p.name);
        expect(p.colours.toSet().length, 4,
            reason: '${p.name} repeats a colour');
        for (final hex in p.colours) {
          expect(RegExp(r'^#[0-9A-Fa-f]{6}$').hasMatch(hex), isTrue,
              reason: '${p.name}: $hex');
        }
      }
    });

    test('the names are distinct, since the picker ticks by name', () {
      final names = [for (final p in InkPalettes.presets) p.name];
      expect(names.toSet().length, names.length);
    });
  });
}
