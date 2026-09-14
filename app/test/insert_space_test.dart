// Insert Space (OneNote's). Drag down, and everything below the line you
// started on moves down with you.
//
// The two things that make it correct rather than merely plausible:
//
//  * Content ABOVE the line does not move. That is the whole promise — you
//    are making room *between* two things, and if the thing above drifts too
//    you have moved the page instead of opening it.
//  * INK moves by its STROKES, each one whole. An ink block's x/y is a derived
//    bounding box (page_canvas._refitInkBounds) and its stroke coordinates are
//    absolute page space, so shifting the block alone moves the box and
//    leaves the strokes behind — the first bug this file exists to prevent.
//    And a stroke that crosses the line goes where the greater part of it
//    was, rather than having its points split above and below — the second:
//    splitting stretched every crossing stroke into a tall vertical smear.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:openote/model/models.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';

import 'support/sqlite.dart';

void main() {
  var haveSqlite = false;
  setUpAll(() => haveSqlite = initSqliteForTests());

  late Repository repo;
  late Directory tmp;
  late AppState app;
  late Block above, below, ink;

  setUp(() async {
    if (!haveSqlite) return;
    AppState.syncLogEnabled = false;
    tmp = Directory.systemTemp.createTempSync('onote_space_');
    repo = await Repository.openAt(tmp);
    final nb = await repo.createNotebook('Space');
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
    above = Block(type: BlockType.image, x: 300, y: 100, w: 100, h: 100);
    below = Block(type: BlockType.image, x: 300, y: 500, w: 100, h: 100);
    ink = Block(type: BlockType.ink, x: 0, y: 0, content: {
      'strokes': [
        Stroke(
          tool: 'pen',
          colorHex: '#000000',
          size: 2,
          // One point above the cut, one below it: a tie.
          x: [310, 320],
          y: [150, 600],
          p: [0.5, 0.5],
        ).toJson(),
        Stroke(
          tool: 'pen',
          colorHex: '#000000',
          size: 2,
          // One point above the cut, two below it: mostly under.
          x: [400, 410, 420],
          y: [380, 600, 620],
          p: [0.5, 0.5, 0.5],
        ).toJson(),
      ],
    });
    app.blocks = [above, below, ink];
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

  List<double> inkYs([int stroke = 0]) {
    final ys = ((ink.content['strokes'] as List)[stroke] as Map)['y'] as List;
    return [for (final v in ys) (v as num).toDouble()];
  }

  test('everything below the line moves, and nothing above it does', () {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    app.insertSpace(400, 120);
    expect(above.y, 100, reason: 'the thing you are making room UNDER stays');
    expect(below.y, 620);
  });

  test('a stroke moves WHOLE, and goes where most of it was', () {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    app.insertSpace(400, 120);
    expect(inkYs(1), [500, 720, 740],
        reason: 'two of three points were under the line, so the whole '
            'stroke — its top point included — comes down, unstretched');
    expect(inkYs(0), [150, 600],
        reason: 'half and half is a tie, and a tie stays: nothing is '
            'stretched and nothing has to be undone');
  });

  test('a stroke is never split across the line', () {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    app.insertSpace(400, 120);
    for (final stroke in [inkYs(0), inkYs(1)]) {
      final span = stroke.reduce((a, b) => a > b ? a : b) -
          stroke.reduce((a, b) => a < b ? a : b);
      expect(span, lessThanOrEqualTo(450),
          reason: 'the stroke is as tall as it was drawn, not taller');
    }
  });

  test('closing space back up never pulls content above the line', () {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    app.insertSpace(400, -500); // far more than the gap
    expect(below.y, 400, reason: 'clamped at the line, not dragged past it');
    expect(inkYs(1), [180, 400, 420],
        reason: 'the stroke stops with its lowest under-the-line point AT '
            'the line — moved as one piece, by 200 not 500');
    expect(inkYs(0), [150, 600], reason: 'the tie stays put');
    expect(above.y, 100);
  });

  test('it is one undo', () {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    app.insertSpace(400, 120);
    app.undo();
    expect(app.blocks.firstWhere((b) => b.id == below.id).y, 500);
  });

  test('a zero drag does nothing at all', () {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final rev = app.docRevision;
    app.insertSpace(400, 0);
    expect(app.docRevision, rev, reason: 'no edit, so nothing to record');
  });
}
