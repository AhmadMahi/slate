// The focus-mode palette has to LAY OUT, and be where you can reach it.
//
// The first build of it did neither, and both faults came from the same
// place: it was positioned with `left`/`top` inside a Stack, which lays a
// child out UNBOUNDED, and it asked for `width: double.infinity` for its drag
// handle. The palette collapsed, and the arithmetic that was supposed to put
// it at "bottom centre" clamped to (0, 0) — so on a real build it appeared as
// a dot in the top-left corner with no tools on it at all.
//
// Neither symptom was visible to any existing test, because nothing rendered
// the thing. This does, and asserts the two properties that were wrong: it
// has a real size, and it sits near the bottom of the window rather than in
// a corner.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';
import 'package:openote/ui/focus_palette.dart';

import 'support/sqlite.dart';

void main() {
  var haveSqlite = false;
  setUpAll(() => haveSqlite = initSqliteForTests());

  late Repository repo;
  late Directory tmp;
  late AppState app;

  setUp(() async {
    if (!haveSqlite) return;
    tmp = Directory.systemTemp.createTempSync('onote_palette_');
    repo = await Repository.openAt(tmp);
    final nb = await repo.createNotebook('P');
    app = AppState(repo)
      ..notebookId = nb.id
      ..spellCheckEnabled = false;
    app.reloadNodes();
  });

  tearDown(() {
    if (!haveSqlite) return;
    repo.dispose();
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  const window = Size(1400, 900);

  Future<void> pump(WidgetTester t) async {
    t.view.physicalSize = window;
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Stack(children: [
          const Positioned.fill(child: ColoredBox(color: Color(0xFF101010))),
          FocusPalette(app: app),
        ]),
      ),
    ));
    await t.pumpAndSettle();
  }

  testWidgets('it has a real size — the collapse that put it in the corner',
      (t) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    app.setTool(Tool.pen);
    await pump(t);
    expect(t.takeException(), isNull);

    final size = t.getSize(find.byType(FocusPalette));
    expect(size.width, greaterThan(300),
        reason: 'five tools, six colours, a slider and two buttons wide');
    expect(size.height, greaterThan(30));
  });

  testWidgets('and it sits at the bottom, not in a corner', (t) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    app.setTool(Tool.pen);
    await pump(t);

    final r = t.getRect(find.byType(FocusPalette));
    // Bottom half of the window, and horizontally centred — the corner is
    // exactly what went wrong, so the assertion is "not the corner".
    expect(r.top, greaterThan(window.height / 2),
        reason: 'a palette at the top covers what you are drawing');
    expect((r.center.dx - window.width / 2).abs(), lessThan(2),
        reason: 'centred by the Stack, with no size arithmetic to get wrong');
  });

  testWidgets('the tools on it are the ones you reach for mid-stroke',
      (t) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    app.setTool(Tool.pen);
    await pump(t);
    for (final tip in ['Select', 'Pen', 'Highlighter', 'Eraser', 'Lasso']) {
      expect(find.byTooltip(tip), findsOneWidget, reason: tip);
    }
    expect(find.byTooltip('Leave focus mode  (Esc)'), findsOneWidget);
    // And NOT a sidebar toggle. Focus mode has already hidden the sidebar,
    // so the button offered to hide something that was not on screen; "leave
    // focus mode" is the way back and it is right beside it.
    expect(find.byTooltip('Hide the sidebar'), findsNothing);
    expect(find.byTooltip('Show the notebook sidebar'), findsNothing);
  });

  testWidgets('the colours are on their own row, and big enough to hit',
      (t) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    app.setTool(Tool.pen);
    await pump(t);
    // By PREFIX: the well's tooltip also carries "double-click to change it",
    // so the exact string is help text and would pin a wording.
    final wells = find.byWidgetPredicate(
        (w) => w is Tooltip && (w.message ?? '').startsWith('Ink colour 1'),
        description: 'first ink well');
    expect(wells, findsOneWidget);
    final well = t.getRect(wells);
    expect(well.width, greaterThanOrEqualTo(24),
        reason: 'colour is the thing you change most while drawing; it must '
            'not be the smallest target on the panel');
    // Below the tools, not beside them.
    expect(well.top, greaterThan(t.getRect(find.byTooltip('Pen')).bottom - 2),
        reason: 'second row');
  });

  testWidgets('a tool on it actually arms that tool', (t) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    app.setTool(Tool.pen);
    await pump(t);
    await t.tap(find.byTooltip('Eraser'));
    await t.pumpAndSettle();
    expect(app.tool, Tool.eraser);
  });
}
