/// Pushing a page's PDF straight into the notebook's connected GitHub repo.
///
/// The whole point: while teaching, one click sends the current session's
/// whiteboard to the same repo the notebook syncs through — no Save-as, no
/// download, no browser. It is deliberately MANUAL and deliberately narrow: it
/// uploads ONE PDF, through GitHub's Contents API, into a `Whiteboards/` folder
/// on the repo's default branch. It does not touch the op-log sync at all, so a
/// pushed whiteboard and the notes sync never interfere.
///
/// Re-pushing the same session overwrites the same file (the Contents API is
/// given the existing blob's sha), so a lesson taught twice does not leave two
/// copies behind.
library;

import 'dart:typed_data';

import '../state/app_state.dart';
import '../sync/github_api.dart';
import 'pdf_export.dart' show buildPageRasterPdf;
import 'pdf_vector_export.dart' show buildPagePdf;

/// The outcome of a push: a repo path on success, or an error to show.
class RepoPushResult {
  const RepoPushResult.ok(this.path) : error = null;
  const RepoPushResult.fail(this.error) : path = null;
  final String? path;
  final String? error;
  bool get ok => error == null;
}

/// Push the current (or given) page as a PDF into the notebook's repo. Returns
/// a [RepoPushResult]; never throws.
Future<RepoPushResult> pushPageToRepo(AppState app, {String? pageId}) async {
  final id = pageId ?? app.pageId;
  if (id == null) return const RepoPushResult.fail('Open a page first.');
  if (!app.gitEnabled || (app.gitRemote?.isEmpty ?? true)) {
    return const RepoPushResult.fail(
        'This notebook is not connected to a repository.');
  }
  final api = app.githubApi();
  if (api == null) {
    return const RepoPushResult.fail('Connect a GitHub account first.');
  }
  final full = repoFullNameFromRemote(app.gitRemote!);
  if (full == null) {
    return const RepoPushResult.fail(
        "The notebook's remote is not a GitHub repository.");
  }
  final page = app.nodes.where((n) => n.id == id).firstOrNull;
  if (page == null) {
    return const RepoPushResult.fail('That page no longer exists.');
  }
  final sectionId = app.sectionOf(id);
  final section = app.nodes.where((n) => n.id == sectionId).firstOrNull;
  final sectionTitle =
      (section?.title.trim().isNotEmpty ?? false) ? section!.title : 'Pages';
  final pageTitle = page.title.trim().isNotEmpty ? page.title : 'Untitled';

  // Save first so the PDF reflects the latest edits, then build the same vector
  // PDF the exporter produces (with its raster fallback for a page the vector
  // build cannot render). buildPageRasterPdf captures the OPEN page, which is
  // why the fallback only applies when pushing the current page.
  await app.flushSave();
  Uint8List bytes;
  try {
    bytes = await buildPagePdf(app, id, title: pageTitle);
  } catch (_) {
    final fb = (id == app.pageId) ? await buildPageRasterPdf(app) : null;
    if (fb == null) {
      return const RepoPushResult.fail('Could not build a PDF of this page.');
    }
    bytes = fb;
  }

  final path = whiteboardPdfPath(sectionTitle, pageTitle);
  final err = await api.putFile(full, path, bytes, 'Slate: $pageTitle');
  if (err != null) return RepoPushResult.fail(err);
  return RepoPushResult.ok(path);
}
