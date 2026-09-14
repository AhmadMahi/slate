// Home and the notebook overview: the two levels above a page, built on the
// notebook state that already existed. Nothing here is faked — every card is
// a real notebook and every row a real page.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/model/models.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';
import 'package:openote/ui/home_dashboard.dart';

import 'support/sqlite.dart';

void main() {
  var haveSqlite = false;
  setUpAll(() => haveSqlite = initSqliteForTests());

  late Directory tmp;
  late Repository repo;
  late AppState app;
  late String physicsId, historyId;

  setUp(() async {
    if (!haveSqlite) return;
    AppState.syncLogEnabled = false;
    tmp = Directory.systemTemp.createTempSync('onote_home_');
    repo = await Repository.openAt(tmp);
    physicsId = (await repo.createNotebook('Physics')).id;
    historyId = (await repo.createNotebook('History')).id;
    app = AppState(repo)
      ..notebookId = physicsId
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

  Future<void> pump(WidgetTester t, Widget body) async {
    t.view.physicalSize = const Size(1400, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ListenableBuilder(listenable: app, builder: (_, __) => body),
      ),
    ));
    await t.pump();
  }

  group('the levels', () {
    test('a notebook overview is a place you leave by choosing a page',
        () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      app.openHome();
      expect(app.navHome, isTrue);
      app.openNotebookOverview();
      expect(app.navNotebook, isTrue);
      expect(app.navHome, isFalse, reason: 'one level at a time');
      await app.selectPage(app.pageId!);
      expect(app.navNotebook, isFalse);
      app.openNotebookOverview();
      app.openHome();
      expect(app.navNotebook, isFalse);
    });

    test('recent keys name the notebook as well as the page', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      expect(app.recentKeys, isNotEmpty);
      expect(app.recentKeys.first, '$physicsId:${app.pageId}');
    });

    test('nodesOf reads another notebook without switching to it', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final other = app.nodesOf(historyId);
      expect(other.where((n) => n.kind == NodeKind.page), isNotEmpty);
      expect(app.notebookId, physicsId, reason: 'a read, not a switch');
    });
  });

  group('Home', () {
    testWidgets('shows every notebook as a card, and a way to make one',
        (t) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      await pump(t, HomeDashboard(app: app));
      expect(find.text('Physics'), findsWidgets);
      expect(find.text('History'), findsOneWidget);
      expect(find.text('New notebook'), findsOneWidget);
      expect(find.text('Create a new notebook'), findsOneWidget);
      // The count is the real one.
      expect(find.text('2'), findsOneWidget);
    });

    testWidgets('a card opens THAT notebook, at its overview', (t) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      app.openHome();
      await pump(t, HomeDashboard(app: app));
      await t.tap(find.text('History'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));
      expect(app.notebookId, historyId);
      expect(app.navNotebook, isTrue);
      expect(app.navHome, isFalse);
      app.cancelPendingSave();
    });
  });

  group('the notebook overview', () {
    testWidgets('lists the sections and their pages; a page opens', (t) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      app.addSection();
      app.reloadNodes();
      final page = app.nodes.firstWhere((n) => n.kind == NodeKind.page);
      app.renameNode(page.id, 'Waves');
      app.reloadNodes();
      app.openNotebookOverview();
      await pump(t, NotebookOverview(app: app));
      expect(find.text('Waves'), findsOneWidget);
      expect(find.textContaining('2 sections'), findsOneWidget);
      await t.tap(find.text('Waves'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));
      expect(app.pageId, page.id);
      expect(app.navNotebook, isFalse, reason: 'choosing a page leaves it');
      app.cancelPendingSave();
    });
  });

  group('relativeTime', () {
    test('is coarse and honest', () {
      final now = DateTime(2026, 9, 10, 12);
      int ago(Duration d) => now.subtract(d).millisecondsSinceEpoch;
      expect(
          relativeTime(ago(const Duration(seconds: 20)), now: now), 'just now');
      expect(
          relativeTime(ago(const Duration(minutes: 5)), now: now), '5 min ago');
      expect(
          relativeTime(ago(const Duration(hours: 1)), now: now), '1 hour ago');
      expect(
          relativeTime(ago(const Duration(hours: 3)), now: now), '3 hours ago');
      expect(
          relativeTime(ago(const Duration(days: 2)), now: now), '2 days ago');
      expect(
          relativeTime(ago(const Duration(days: 15)), now: now), '2 weeks ago');
      expect(
          relativeTime(ago(const Duration(days: 60)), now: now), '12 Jul 2026');
    });
  });
}
