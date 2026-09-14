// The paper a page is written on, and what a new page is born with.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/canvas/paper.dart';
import 'package:openote/model/models.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';

import 'support/sqlite.dart';

void main() {
  group('PageProps.paper', () {
    test('ambient is the default and says nothing', () {
      expect(PageProps().paperKind, 'ambient');
      expect(PageProps().toJson().containsKey('paper'), isFalse,
          reason: 'a page nobody changed serialises as every earlier build '
              'wrote it, or the next save diffs every page in the notebook');
      expect(PageProps.fromJson({'background': 'grid'}).paperKind, 'ambient',
          reason: 'a page from any earlier build takes the default look');
      expect(PageProps(paperKind: 'white').toJson()['paper'], 'white',
          reason: 'plain white is now a choice, and is written down');
    });

    test('a chosen paper and its picture round-trip', () {
      final p = PageProps(paperKind: 'image', paperImage: 'sha256:abc');
      final j = p.toJson();
      expect(j['paper'], 'image');
      expect(j['paperImage'], 'sha256:abc');
      final back = PageProps.fromJson(j);
      expect(back.paperKind, 'image');
      expect(back.paperImage, 'sha256:abc');
      expect(back.unknownFields, isEmpty,
          reason: 'known keys are not smuggled through as unknown ones');
      expect(
          PageProps.fromJson(PageProps(paperKind: 'cream').toJson()).paperKind,
          'cream');
    });
  });

  group('paper colours', () {
    test('every paper has a colour of its own, in both themes', () {
      for (final dark in [false, true]) {
        final seen = <Color>{};
        for (final p in kPapers.where((p) => p != 'image')) {
          expect(seen.add(paperColor(p, dark: dark)), isTrue,
              reason: '$p should not look like another paper (dark=$dark)');
        }
      }
    });

    test('white is the page colour every earlier build painted', () {
      expect(paperColor('white', dark: false), const Color(0xFFFFFFFF));
    });

    test('the grain tile exists and is shared', () {
      final a = paperGrainTile(dark: false);
      expect(identical(a, paperGrainTile(dark: false)), isTrue);
      expect(a.width, greaterThan(0));
    });
  });

  group('ambient family', () {
    const variants = [
      'ambient-sunset',
      'ambient-ocean',
      'ambient-forest',
      'ambient-dusk',
      'ambient-aurora',
    ];

    test('the variants are offered, after the default ambient', () {
      expect(kPapers.first, 'ambient');
      for (final v in variants) {
        expect(kPapers.contains(v), isTrue, reason: '$v is not offered');
      }
    });

    test('each variant has its own Ambient-prefixed name', () {
      final names = <String>{};
      for (final v in variants) {
        final label = paperLabel(v);
        expect(label.startsWith('Ambient '), isTrue, reason: v);
        expect(names.add(label), isTrue, reason: '$label is not unique');
      }
    });

    test('the whole family shares the default ambient rule colour', () {
      for (final dark in [false, true]) {
        final base = paperRuleColor('ambient', dark: dark);
        for (final v in variants) {
          expect(paperRuleColor(v, dark: dark), base, reason: '$v (dark=$dark)');
        }
      }
    });
  });

  group('new-page defaults', () {
    var haveSqlite = false;
    setUpAll(() => haveSqlite = initSqliteForTests());
    late Repository repo;
    late Directory tmp;
    late AppState app;
    late String sectionId;

    setUp(() async {
      if (!haveSqlite) return;
      AppState.syncLogEnabled = false;
      tmp = Directory.systemTemp.createTempSync('onote_paper_');
      repo = await Repository.openAt(tmp);
      final nb = await repo.createNotebook('Paper');
      app = AppState(repo)
        ..notebookId = nb.id
        ..spellCheckEnabled = false;
      app.reloadNodes();
      sectionId = app.nodes.firstWhere((n) => n.kind == NodeKind.section).id;
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

    test('untouched settings make a page exactly as before', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      await app.addPage(sectionId: sectionId);
      expect(app.pageProps.toJson(), PageProps().toJson());
    });

    test('a new page is born with what Settings chose', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      app.setDefaultBackground('ruled');
      app.setDefaultBgSpacing(32);
      app.setDefaultPaper('cream');
      app.setDefaultPageSize('A5');
      await app.addPage(sectionId: sectionId);
      expect(app.pageProps.background, 'ruled');
      expect(app.pageProps.bgSpacing, 32);
      expect(app.pageProps.paperKind, 'cream');
      expect(app.pageProps.isPaged, isTrue);
      expect(app.pageProps.paperSize, 'A5');
      expect(repo.getSetting('defaultPaper'), 'cream',
          reason: 'the choice outlives the session');
      app.cancelPendingSave();
    });

    test('the defaults do not touch the page you are already on', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final before = app.pageProps.toJson();
      app.setDefaultPaper('grey');
      expect(app.pageProps.toJson(), before);
    });

    test('setPaper is per page and undoable', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      app.setPaper('grey');
      expect(app.pageProps.paperKind, 'grey');
      app.setPaper('image', image: 'sha256:pic');
      expect(app.pageProps.paperImage, 'sha256:pic');
      app.setPaper('white');
      expect(app.pageProps.paperImage, isNull,
          reason: 'leaving picture paper drops the picture reference');
      app.undo();
      expect(app.pageProps.paperKind, 'image');
      app.cancelPendingSave();
    });
  });
}
