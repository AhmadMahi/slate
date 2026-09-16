// The backup round-trip: materialize a notebook, then restore it into a fresh
// workspace and get the same structure and content back.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openote/export/open_export.dart';
import 'package:openote/model/models.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';
import 'package:openote/sync/central_restore.dart';
import 'package:path/path.dart' as p;

import 'support/sqlite.dart';

void main() {
  var haveSqlite = false;
  setUpAll(() => haveSqlite = initSqliteForTests());

  test('a materialized notebook restores with its page content', () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final ws1 = Directory.systemTemp.createTempSync('onote_src_');
    final ws2 = Directory.systemTemp.createTempSync('onote_dst_');
    final out = Directory.systemTemp.createTempSync('onote_bk_');
    final src = await Repository.openAt(ws1);
    final dst = await Repository.openAt(ws2);
    addTearDown(() {
      src.dispose();
      dst.dispose();
      for (final d in [ws1, ws2, out]) {
        try {
          d.deleteSync(recursive: true);
        } catch (_) {}
      }
    });

    // Source: a notebook with a page carrying a text block.
    final nb = await src.createNotebook('Course');
    final srcApp = AppState(src)..notebookId = nb.id;
    srcApp.reloadNodes();
    final pageId =
        srcApp.nodesOf(nb.id).firstWhere((n) => n.kind == NodeKind.page).id;
    srcApp.importPage(
        nb.id,
        pageId,
        [
          Block(
              type: BlockType.text,
              x: 60,
              y: 60,
              w: 400,
              content: {'text': 'Hello restore'})
        ],
        PageProps());

    // Back it up (the central backup's materialize).
    final root = p.join(out.path, 'Course');
    await materializeNotebookInto(srcApp, nb.id, root);

    // Restore into a SEPARATE workspace.
    final dstApp = AppState(dst);
    final outcome = await restoreNotebookFromFolder(dstApp, root);
    expect(outcome, RestoreOutcome.imported);

    // The notebook is back, with its id and its page's text.
    expect(dstApp.hasNotebook(nb.id), isTrue,
        reason: 'the original notebook id is preserved');
    final page = dstApp.readPageOf(nb.id, pageId);
    expect(page.blocks, hasLength(1));
    expect(page.blocks.single.content['text'], 'Hello restore');

    // Restoring again is a no-op (skipped, not duplicated).
    expect(
        await restoreNotebookFromFolder(dstApp, root), RestoreOutcome.skipped);
  });
}
