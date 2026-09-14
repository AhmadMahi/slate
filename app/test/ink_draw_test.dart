// Does a pen drag actually leave ink on the page?
//
// There was no test anywhere that drove a real pointer across the canvas with
// a drawing tool armed, so "the pen does not draw" could regress and the
// whole 2700-test suite would stay green. This is that test.
import 'dart:io';

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
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
    tmp = Directory.systemTemp.createTempSync('onote_inkdraw_');
    repo = await Repository.openAt(tmp);
    final nb = await repo.createNotebook('Canvas');
    app = AppState(repo)..notebookId = nb.id..spellCheckEnabled = false;
    app.reloadNodes();
    await app.selectPage(app.nodes.firstWhere((n) => n.kind == NodeKind.page).id);
  });

  tearDown(() {
    AppState.syncLogEnabled = true;
    if (!haveSqlite) return;
    app.cancelPendingSave();
    repo.dispose();
    try { tmp.deleteSync(recursive: true); } catch (_) {}
  });

  Future<void> pump(WidgetTester t) async {
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(width: 800, height: 600, child: PageCanvas(state: app)),
      ),
    ));
    await t.pump();
    await t.pump();
  }

  testWidgets('a mouse drag leaves a stroke with AUTO SHAPES ON', (t) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    app.autoShape = true;
    app.setTool(Tool.pen);
    await pump(t);
    final g = await t.startGesture(const Offset(300, 300),
        kind: PointerDeviceKind.mouse);
    for (var i = 1; i <= 10; i++) {
      await g.moveTo(Offset(300 + i * 10.0, 300 + i * 5.0));
      await t.pump();
    }
    await g.up();
    await t.pumpAndSettle();
    final ink = app.blocks.where((b) => b.type == BlockType.ink).toList();
    expect(ink, isNotEmpty, reason: 'THE PEN MUST LEAVE INK');
    final strokes = ink.first.content['strokes'] as List;
    expect(strokes, isNotEmpty);
    final xs = (strokes.first as Map)['x'] as List;
    expect(xs, isNotEmpty, reason: 'a snapped stroke still has points');
    expect(ink.first.w, greaterThan(0));
    expect(ink.first.h, greaterThan(0));
    app.cancelPendingSave();
  });

  testWidgets('a mouse drag with the pen leaves a stroke', (t) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    app.setTool(Tool.pen);
    await pump(t);
    final g = await t.startGesture(const Offset(300, 300),
        kind: PointerDeviceKind.mouse);
    for (var i = 1; i <= 10; i++) {
      await g.moveTo(Offset(300 + i * 10.0, 300 + i * 5.0));
      await t.pump();
    }
    await g.up();
    await t.pumpAndSettle();
    final ink = app.blocks.where((b) => b.type == BlockType.ink).toList();
    expect(ink, isNotEmpty, reason: 'THE PEN MUST LEAVE INK');
    final strokes = ink.first.content['strokes'] as List;
    expect(strokes, isNotEmpty);
    // The block has to have real BOUNDS as well as real points: the canvas
    // culls blocks that do not overlap the viewport, so a stroke with a
    // degenerate rect is stored perfectly and drawn nowhere.
    final b = ink.first;
    expect(b.w, greaterThan(0));
    expect(b.h, greaterThan(0));
    app.cancelPendingSave();
  });
}
