/// Pushing a page — and everything on it — into the notebook's push-target
/// repo, as PDFs and files.
///
/// The whole point: while teaching, one action sends the current session's
/// whiteboard to the repo the notebook is connected to — no Save-as, no
/// download, no browser. Everything for a page lands in one tidy folder,
/// `Whiteboards/<page>/`:
///
/// - `<page> - whiteboard.pdf`   the page itself
/// - `<page> - mindmap.pdf`      each mind map, fully expanded
/// - `<page> - quiz.pdf`         each quiz (questions, then all answers)
/// - `<page> - <name>.pdf`       each presentation / imported PDF
///
/// **PDFs only** — images and non-PDF files are deliberately not uploaded, so
/// the repo stays a clean set of readable documents. It uploads through
/// GitHub's Contents API and never touches the notebook's own sync. Re-pushing
/// overwrites the same files, so a session taught twice does not pile up copies.
library;

import 'dart:typed_data';

import '../mindmap/mindmap.dart';
import '../model/models.dart';
import '../quiz/quiz_import.dart';
import '../state/app_state.dart';
import '../sync/github_api.dart';
import 'mindmap_pdf.dart';
import 'pdf_export.dart' show buildPageRasterPdf;
import 'pdf_vector_export.dart' show buildPagePdf;
import 'quiz_pdf.dart';

/// The outcome of a push: a short summary on success, or an error to show.
class RepoPushResult {
  const RepoPushResult.ok(this.summary) : error = null;
  const RepoPushResult.fail(this.error) : summary = null;
  final String? summary;
  final String? error;
  bool get ok => error == null;
}

/// One thing to upload.
class _Upload {
  _Upload(this.path, this.bytes, this.message);
  final String path;
  final List<int> bytes;
  final String message;
}

/// Push the current page and its contents — **PDFs only**. The page, each mind
/// map, each quiz, and each presentation/PDF on it go up as PDF files; nothing
/// else (no images, no non-PDF files) is uploaded. Never throws.
Future<RepoPushResult> pushPageToRepo(AppState app) async {
  final id = app.pageId;
  if (id == null) return const RepoPushResult.fail('Open a page first.');
  if (!app.connectedForPush || (app.pushRepo?.isEmpty ?? true)) {
    return const RepoPushResult.fail(
        'This notebook is not connected to a repository. Connect one in Sync.');
  }
  final api = app.githubApi();
  if (api == null) {
    return const RepoPushResult.fail('Connect a GitHub account first.');
  }
  final full = repoFullNameFromRemote(app.pushRepo!);
  if (full == null) {
    return const RepoPushResult.fail(
        "The push target is not a GitHub repository.");
  }
  final page = app.nodes.where((n) => n.id == id).firstOrNull;
  if (page == null) {
    return const RepoPushResult.fail('That page no longer exists.');
  }
  final pageTitle = page.title.trim().isNotEmpty ? page.title : 'Untitled';
  final dir = whiteboardDir(pageTitle);
  final base = whiteboardSegment(pageTitle);

  await app.flushSave();

  final uploads = <_Upload>[];

  // 1) The page itself, as a PDF (vector, with the raster fallback the exporter
  //    uses for a page the vector build cannot render).
  Uint8List pageBytes;
  try {
    pageBytes = await buildPagePdf(app, id, title: pageTitle);
  } catch (_) {
    final fb = await buildPageRasterPdf(app);
    if (fb == null) {
      return const RepoPushResult.fail('Could not build a PDF of this page.');
    }
    pageBytes = fb;
  }
  uploads.add(
      _Upload('$dir/$base - whiteboard.pdf', pageBytes, 'Slate: $pageTitle'));

  // 2) The blocks on the page, each turned into a PDF of its own. PDFs only:
  //    mind maps and quizzes are rendered to PDF; presentations and imported
  //    files ride along only when they are already PDFs. Images and other file
  //    types are deliberately skipped.
  var mind = 0, quiz = 0, doc = 0;
  for (final b in app.blocks) {
    switch (b.type) {
      case BlockType.mindmap:
        final raw = b.content['root'];
        if (raw is! Map) break;
        final root = MindNode.fromJson(raw.cast<String, dynamic>());
        final bytes = await buildMindmapOutlinePdf(pageTitle, root);
        mind++;
        final s = mind == 1 ? 'mindmap' : 'mindmap-$mind';
        uploads.add(_Upload(
            '$dir/$base - $s.pdf', bytes, 'Slate: $pageTitle mind map'));
      case BlockType.quiz:
        final qs = <QuizQuestion>[
          for (final q in (b.content['questions'] as List? ?? const []))
            if (q is Map) QuizQuestion.fromJson(q.cast<String, dynamic>())
        ];
        if (qs.isEmpty) break;
        final bytes =
            await buildQuizPdf(b.content['name'] as String? ?? 'Quiz', qs);
        quiz++;
        final s = quiz == 1 ? 'quiz' : 'quiz-$quiz';
        uploads.add(
            _Upload('$dir/$base - $s.pdf', bytes, 'Slate: $pageTitle quiz'));
      case BlockType.presentation:
        // A presentation is stored as a PDF blob.
        final bytes = _blobOf(app, b.content['pdf']);
        if (bytes == null) break;
        final label = _stripExt((b.content['name'] as String?)?.trim());
        doc++;
        final safe =
            whiteboardSegment(label.isEmpty ? 'presentation-$doc' : label);
        uploads.add(_Upload(
            '$dir/$base - $safe.pdf', bytes, 'Slate: $pageTitle presentation'));
      case BlockType.file:
        // Only PDFs ride along; other file types are skipped.
        if (!_isPdf(b.content)) break;
        final bytes = _blobOf(app, b.content['blob']);
        if (bytes == null) break;
        final label = _stripExt((b.content['name'] as String?)?.trim());
        doc++;
        final safe = whiteboardSegment(label.isEmpty ? 'document-$doc' : label);
        uploads.add(
            _Upload('$dir/$base - $safe.pdf', bytes, 'Slate: $pageTitle file'));
      default:
        break;
    }
  }

  // 3) Upload them all. One failure does not abort the rest; the summary says
  //    what happened.
  final failures = <String>[];
  for (final u in uploads) {
    final err = await api.putFile(full, u.path, u.bytes, u.message);
    if (err != null) failures.add(err);
  }
  final n = uploads.length - failures.length;
  if (failures.isNotEmpty) {
    return RepoPushResult.fail(
        '$n of ${uploads.length} pushed. ${failures.first}');
  }
  return RepoPushResult.ok('$dir ($n file${n == 1 ? '' : 's'})');
}

/// Bytes of a `sha256:…` blob reference, or null.
Uint8List? _blobOf(AppState app, Object? ref) {
  if (ref is! String || ref.isEmpty) return null;
  final hash = ref.replaceFirst('sha256:', '');
  return app.blob(hash);
}

String _stripExt(String? name) {
  if (name == null || name.isEmpty) return '';
  final dot = name.lastIndexOf('.');
  return dot > 0 ? name.substring(0, dot) : name;
}

/// Whether a file block holds a PDF (by mime or by name), so only PDFs push.
bool _isPdf(Map<String, dynamic> content) {
  final mime = (content['mime'] as String? ?? '').toLowerCase();
  if (mime == 'application/pdf') return true;
  final name = (content['name'] as String? ?? '').toLowerCase();
  return name.endsWith('.pdf');
}
