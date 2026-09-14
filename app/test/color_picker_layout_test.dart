// The colour picker has to LAY OUT. That sounds too obvious to test, until
// it doesn't.
//
// A `Spacer` was added to the dialog's `actions:` to push a shortcut control
// to the left. `actions` is an `OverflowBar`, not a flex, and a `Spacer` is an
// `Expanded` — "Incorrect use of ParentDataWidget", thrown while applying
// parent data. Two symptoms followed, and only one of them looked like a
// dialog bug:
//
//   * the dialog rendered as a tall grey slab with no palette in it; and
//   * the PEN STOPPED DRAWING. The route was still pushed, so its invisible
//     modal barrier sat over the whole page swallowing every pointer event.
//     Nothing on the canvas responded, and nothing about that pointed at a
//     colour dialog.
//
// So this asserts the thing that actually broke: no exception escapes while
// the dialog is up, in both shapes the caller can ask for.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';
import 'package:openote/ui/color_picker.dart';

import 'support/sqlite.dart';

void main() {
  var haveSqlite = false;
  setUpAll(() => haveSqlite = initSqliteForTests());

  late Repository repo;
  late Directory tmp;
  late AppState app;

  setUp(() async {
    if (!haveSqlite) return;
    tmp = Directory.systemTemp.createTempSync('onote_picker_');
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

  Future<void> open(WidgetTester t,
      {String? shortcut, ValueChanged<String>? onShortcut}) async {
    t.view.physicalSize = const Size(1600, 1400);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(
      home: Builder(
        builder: (c) => TextButton(
          onPressed: () => showOnoteColorPicker(c, app,
              initial: '#C63838',
              title: 'Pen colour',
              shortcut: shortcut,
              onShortcut: onShortcut),
          child: const Text('open'),
        ),
      ),
    ));
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
  }

  testWidgets('it opens cleanly with a shortcut control', (t) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    var bound = '';
    await open(t, shortcut: '', onShortcut: (k) => bound = k);
    expect(t.takeException(), isNull,
        reason: 'a dialog that throws in layout leaves a barrier over the app');
    expect(find.text('Shortcut'), findsOneWidget);
    expect(find.text('Apply'), findsOneWidget, reason: 'the buttons are there');
    expect(bound, '');
  });

  testWidgets('and cleanly without one', (t) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    await open(t);
    expect(t.takeException(), isNull);
    expect(find.text('Shortcut'), findsNothing,
        reason: 'callers with only one colour have nothing to switch between');
    expect(find.text('Apply'), findsOneWidget);
  });

  testWidgets('it can be dismissed, so the barrier goes with it', (t) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    await open(t, shortcut: '', onShortcut: (_) {});
    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();
    expect(find.text('Apply'), findsNothing,
        reason: 'the route is gone, and so is what it was swallowing');
  });
}
