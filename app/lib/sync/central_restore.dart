/// Restore notebooks from the central backup repo — the other half of the
/// central backup.
///
/// Connect GitHub on any machine, point this at your backup repository, and it
/// rebuilds every notebook it holds into local storage: structure, blocks, ink,
/// images and files, faithfully, from `notebook.json` + each `page.json` +
/// `assets/`. It reuses the same [ImportSink] every other importer writes
/// through, and preserves each notebook's original id so a restore is
/// idempotent (a notebook already here is skipped, not duplicated) and so a
/// restored notebook lines up with its backup for future syncs.
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../export/import_sink.dart';
import '../model/models.dart';
import '../state/app_state.dart';
import 'git_sync.dart';

class RestoreResult {
  const RestoreResult({this.imported = 0, this.skipped = 0, this.error});
  final int imported;
  final int skipped;
  final String? error;
  bool get ok => error == null;
}

/// Clone [cloneUrl] and rebuild every notebook it holds, skipping any already
/// present locally. Never throws.
Future<RestoreResult> restoreNotebooksFrom(
  AppState app,
  String cloneUrl, {
  void Function(String message)? onProgress,
}) async {
  if (await GitSync.gitExecutable() == null) {
    return const RestoreResult(
        error: 'Git is not installed on this computer. Install it from '
            'git-scm.com to restore a backup.');
  }
  final tmp = Directory.systemTemp.createTempSync('slate-restore-');
  try {
    onProgress?.call('Downloading the backup…');
    await GitSync.clone(cloneUrl, tmp.path, token: app.githubTokenForSync);
    if (!Directory(p.join(tmp.path, '.git')).existsSync()) {
      return const RestoreResult(
          error: 'Could not download that repository. Check the address and '
              'your GitHub sign-in.');
    }
    var imported = 0, skipped = 0;
    for (final dir in tmp.listSync().whereType<Directory>()) {
      if (!File(p.join(dir.path, 'notebook.json')).existsSync()) continue;
      final r = await restoreNotebookFromFolder(app, dir.path,
          onProgress: onProgress);
      if (r == RestoreOutcome.imported) imported++;
      if (r == RestoreOutcome.skipped) skipped++;
    }
    app.notifyAfterImport();
    if (imported == 0 && skipped == 0) {
      return const RestoreResult(
          error: 'No notebooks were found in that repository.');
    }
    return RestoreResult(imported: imported, skipped: skipped);
  } catch (e) {
    return RestoreResult(error: '$e');
  } finally {
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  }
}

enum RestoreOutcome { imported, skipped, unreadable }

/// Restore ONE notebook from an already-downloaded folder. Used by
/// [restoreNotebooksFrom] and directly testable without git. Skips a notebook
/// already present (by id) rather than duplicating it.
Future<RestoreOutcome> restoreNotebookFromFolder(AppState app, String folder,
    {void Function(String message)? onProgress}) async {
  final manifest = File(p.join(folder, 'notebook.json'));
  if (!manifest.existsSync()) return RestoreOutcome.unreadable;
  Map<String, dynamic> j;
  try {
    j = jsonDecode(manifest.readAsStringSync()) as Map<String, dynamic>;
  } catch (_) {
    return RestoreOutcome.unreadable;
  }
  final meta = (j['notebook'] as Map?)?.cast<String, dynamic>() ?? {};
  final oldId = meta['id'] as String?;
  final title = (meta['title'] as String?)?.trim().isNotEmpty == true
      ? meta['title'] as String
      : p.basename(folder);
  if (oldId != null && app.hasNotebook(oldId)) return RestoreOutcome.skipped;
  onProgress?.call('Restoring "$title"…');
  await _restoreOne(app, folder, j, oldId, title);
  return RestoreOutcome.imported;
}

Future<void> _restoreOne(AppState app, String root,
    Map<String, dynamic> manifest, String? oldId, String title) async {
  final ref = await app.importCreateNotebook(title, withId: oldId);
  final nbId = ref.id;
  final sink = AppStateImportSink(app, nbId);
  final seeded = sink.nodes(); // the starter section+page to purge afterwards

  sink.batch(() {
    // 1) Every asset's bytes. Content-addressed, so re-importing yields the
    //    same hash the blocks already reference — the mime is best-effort.
    final assetsDir = Directory(p.join(root, 'assets'));
    if (assetsDir.existsSync()) {
      for (final f in assetsDir.listSync().whereType<File>()) {
        try {
          sink.blob(f.readAsBytesSync(), _mimeForExt(p.extension(f.path)));
        } catch (_) {}
      }
    }

    // 2) The structure — parents before children (sort by level), original ids
    //    preserved so parent links and page ids still resolve.
    final nodeList = <Map<String, dynamic>>[
      for (final n in (manifest['nodes'] as List? ?? const []))
        if (n is Map) n.cast<String, dynamic>()
    ]..sort((a, b) => ((a['level'] as num?)?.toInt() ?? 0)
        .compareTo((b['level'] as num?)?.toInt() ?? 0));
    for (final n in nodeList) {
      sink.node(TreeNode(
        id: n['id'] as String?,
        kind: nodeKindFromWire(n['kind'] as String? ?? 'page') ?? NodeKind.page,
        parentId: n['parentId'] as String?,
        title: n['title'] as String? ?? '',
        position: n['position'] as String? ?? 'a0',
        color: n['color'] as String?,
        level: (n['level'] as num?)?.toInt() ?? 0,
        createdAt: (n['createdAt'] as num?)?.toInt(),
      ));
    }

    // 3) Each page's blocks, from its page.json.
    for (final pj in (manifest['pages'] as List? ?? const [])) {
      if (pj is! Map) continue;
      final pageId = pj['id'] as String?;
      final path = pj['path'] as String?;
      if (pageId == null || path == null) continue;
      final pageFile = File(p.join(root, path, 'page.json'));
      if (!pageFile.existsSync()) continue;
      try {
        final data =
            jsonDecode(pageFile.readAsStringSync()) as Map<String, dynamic>;
        final props =
            PageProps.fromJson((data['page'] as Map?)?.cast<String, dynamic>());
        final blocks = <Block>[
          for (final b in (data['blocks'] as List? ?? const []))
            if (b is Map) Block.fromJson(b.cast<String, dynamic>())
        ];
        sink.page(pageId, blocks, props);
      } catch (_) {}
    }

    // 4) Remove the starter section+page the new notebook was seeded with.
    for (final n in seeded) {
      sink.purgeNode(n.id);
    }
  });
}

String _mimeForExt(String ext) {
  switch (ext.toLowerCase()) {
    case '.png':
      return 'image/png';
    case '.jpg':
    case '.jpeg':
      return 'image/jpeg';
    case '.gif':
      return 'image/gif';
    case '.webp':
      return 'image/webp';
    case '.svg':
      return 'image/svg+xml';
    case '.pdf':
      return 'application/pdf';
    default:
      return 'application/octet-stream';
  }
}
