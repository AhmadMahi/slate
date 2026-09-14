// The canvas's floating controls drive the SAME zoom and fit the View card
// used to, from the corner of the page they act on.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/model/models.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';
import 'package:openote/ui/canvas_controls.dart';

import 'support/sqlite.dart';

void main() {
  var haveSqlite = false;
  setUpAll(() => haveSqlite = initSqliteForTests());

  late Directory tmp;
  late Repository repo;
  late AppState app;

  setUp(() async {
    if (!haveSqlite) return;
    AppState.syncLogEnabled = false;
    tmp = Directory.systemTemp.createTempSync('onote_cc_');
    repo = await Repository.openAt(tmp);
    final nb = await repo.createNotebook('Z');
    app = AppState(repo)
      ..notebookId = nb.id
      ..spellCheckEnabled = false;
    app.reloadNodes();
    await app
        .selectPage(app.nodes.firstWhere((n) => n.kind == NodeKind.page).id);
    app.canvas.viewport = const Size(1000, 700);
    app.canvas.pageSize = const Size(1100, 1400);
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

  Future<void> pump(WidgetTester t) async {
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topRight,
          child: ListenableBuilder(
              listenable: app, builder: (_, __) => CanvasControls(app: app)),
        ),
      ),
    ));
    await t.pump();
  }

  testWidgets('shows the real zoom, and + / − change it', (t) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    app.canvas.setZoom(1.0);
    await pump(t);
    expect(find.text('100%'), findsOneWidget);
    await t.tap(find.byTooltip('Zoom in  (Ctrl+=)'));
    await t.pump();
    expect(app.canvas.scale, closeTo(1.2, .001));
    expect(find.text('120%'), findsOneWidget);
    await t.tap(find.byTooltip('Zoom out  (Ctrl+-)'));
    await t.pump();
    expect(app.canvas.scale, closeTo(1.0, .001));
  });

  testWidgets('Fit is the existing fit: it latches the width', (t) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    await pump(t);
    expect(app.canvas.fitLocked, isFalse);
    await t.tap(find.byTooltip(RegExp(r'^Zoom to fit')));
    await t.pump();
    expect(app.canvas.fitLocked, isTrue,
        reason: 'the same fitPageToWidth the View card called');
  });

  testWidgets('the zoom menu offers the levels and Fit', (t) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    app.canvas.setZoom(1.0);
    await pump(t);
    await t.tap(find.text('100%'));
    await t.pumpAndSettle();
    for (final l in CanvasControls.levels) {
      expect(find.text('$l%'), findsWidgets, reason: '$l%');
    }
    expect(find.text('Fit to width'), findsOneWidget);
    await t.tap(find.text('200%').last);
    await t.pumpAndSettle();
    expect(app.canvas.scale, closeTo(2.0, .001));
  });
}
