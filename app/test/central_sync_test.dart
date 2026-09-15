// The central backup materializes EVERY notebook, including ones that are not
// the open one — so the notebook-scoped read path (nodesOf/readPageOf/blobOf)
// has to produce a full folder tree for a notebook without opening it.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openote/export/open_export.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';
import 'package:path/path.dart' as p;

import 'support/sqlite.dart';

void main() {
  var haveSqlite = false;
  setUpAll(() => haveSqlite = initSqliteForTests());

  test('materializes a notebook that is not the open one', () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final ws = Directory.systemTemp.createTempSync('onote_central_');
    final out = Directory.systemTemp.createTempSync('onote_central_out_');
    final repo = await Repository.openAt(ws);
    addTearDown(() {
      repo.dispose();
      for (final d in [ws, out]) {
        try {
          d.deleteSync(recursive: true);
        } catch (_) {}
      }
    });

    final alpha = await repo.createNotebook('Alpha');
    final beta = await repo.createNotebook('Beta');
    // Open Alpha; Beta stays closed.
    final app = AppState(repo)..notebookId = alpha.id;
    app.reloadNodes();

    // Materialize the CLOSED notebook into a fresh folder.
    final root = p.join(out.path, 'Beta');
    await materializeNotebookInto(app, beta.id, root);

    final manifest = File(p.join(root, 'notebook.json'));
    expect(manifest.existsSync(), isTrue,
        reason: 'a notebook.json is written for the non-open notebook');
    final json = jsonDecode(manifest.readAsStringSync()) as Map;
    expect((json['notebook'] as Map)['title'], 'Beta');
    expect(json['format'], 'openote-materialized/1');
  });
}
