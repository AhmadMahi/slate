// Ink has to be VISIBLE over a block, not merely recorded under one.
//
// Annotating a pasted photograph worked perfectly and showed nothing: the ink
// layer was the FIRST child of the page Stack, so every stroke painted
// beneath every block, and blocks are opaque. The report was "I can paste and
// drag images but I cannot draw on them" — the strokes were there the whole
// time, behind the picture.
//
// Nothing caught it because the strokes really were being created: the data
// path was right, and `ink_draw_test` asserts exactly that. What was wrong was
// the paint order, which no test looked at.
//
// So this looks at pixels. It draws over an opaque block and asserts the ink
// colour actually reaches the screen where the block is.
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/canvas/page_canvas.dart';
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

  setUp(() async {
    if (!haveSqlite) return;
    AppState.syncLogEnabled = false;
    tmp = Directory.systemTemp.createTempSync('onote_inkover_');
    repo = await Repository.openAt(tmp);
    final nb = await repo.createNotebook('Over');
    app = AppState(repo)
      ..notebookId = nb.id
      ..spellCheckEnabled = false;
    app.reloadNodes();
    await app
        .selectPage(app.nodes.firstWhere((n) => n.kind == NodeKind.page).id);
  });

  tearDown(() {
    AppState.syncLogEnabled = true;
    if (!haveSqlite) return;
    app.cancelPendingSave();
    repo.dispose();
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  testWidgets('a stroke drawn across a block is drawn ON TOP of it',
      (t) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');

    // A code block stands in for the pasted picture: it is opaque, it is a
    // real block type, and it needs no blob store to render.
    app.blocks = [
      Block(
        type: BlockType.code,
        x: 60,
        y: 60,
        w: 400,
        h: 200,
        content: {'language': 'text', 'source': 'under the ink'},
      )
    ];
    app.setTool(Tool.pen);
    // A colour nothing else on screen uses, so finding it is unambiguous.
    app.penPalette = ['#FF00FF'];
    app.penColor = 0;
    app.select(null);

    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: RepaintBoundary(
          key: const ValueKey('shot'),
          child: SizedBox(
              width: 800, height: 600, child: PageCanvas(state: app)),
        ),
      ),
    ));
    await t.pump();
    await t.pump();

    // Straight across the middle of the block.
    final g = await t.startGesture(const Offset(90, 150),
        kind: PointerDeviceKind.mouse);
    for (var i = 1; i <= 12; i++) {
      await g.moveTo(Offset(90 + i * 25.0, 150));
      await t.pump();
    }
    await g.up();
    // Pumped, NOT settled: a caret blinks forever, so `pumpAndSettle` waits
    // for an animation that never ends and the test times out rather than
    // fails. Two frames is all a committed stroke needs.
    await t.pump();
    await t.pump(const Duration(milliseconds: 32));

    final boundary = t.renderObject<RenderRepaintBoundary>(
        find.byKey(const ValueKey('shot')));
    // `toImage` is real async work and the test binding fakes the clock, so
    // it only completes inside `runAsync`.
    late Uint8List px;
    late int width;
    await t.runAsync(() async {
      final image = await boundary.toImage();
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      px = data!.buffer.asUint8List();
      width = image.width;
    });

    // Count magenta pixels anywhere inside the block's rectangle.
    var found = 0;
    for (var y = 70; y < 250; y++) {
      for (var x = 70; x < 450; x++) {
        final i = (y * width + x) * 4;
        if (px[i] > 200 && px[i + 1] < 80 && px[i + 2] > 200) found++;
      }
    }
    expect(found, greaterThan(50),
        reason: 'the ink is behind the block again — it is recorded and '
            'invisible, which is what "I cannot draw on images" was');
    app.cancelPendingSave();
  });
}
