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
/// - `<page> - <name>.<ext>`     each imported file, as-is
/// - `images/<page> - image-N…`  each image, only when asked
///
/// It uploads through GitHub's Contents API and never touches the notebook's
/// own sync. Re-pushing overwrites the same files, so a session taught twice
/// does not pile up copies.
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

/// Push the current page and its contents. [includeImages] adds an `images/`
/// folder with every image on the page. Never throws.
Future<RepoPushResult> pushPageToRepo(
  AppState app, {
  bool includeImages = false,
}) async {
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
  if (page == null)
    return const RepoPushResult.fail('That page no longer exists.');
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

  // 2) The blocks on the page, each turned into a file of its own.
  var mind = 0, quiz = 0, image = 0;
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
        final bytes = _blobOf(app, b.content['pdf']);
        if (bytes == null) break;
        final label = _stripExt((b.content['name'] as String?)?.trim());
        uploads.add(_Upload(
            '$dir/$base - ${whiteboardSegment(label.isEmpty ? 'presentation' : label)}.pdf',
            bytes,
            'Slate: $pageTitle presentation'));
      case BlockType.file:
        final bytes = _blobOf(app, b.content['blob']);
        if (bytes == null) break;
        // Keep the file's own name and extension (a .pptx stays a .pptx).
        final name = (b.content['name'] as String?)?.trim();
        final safe =
            whiteboardSegment((name == null || name.isEmpty) ? 'file' : name);
        uploads.add(
            _Upload('$dir/$base - $safe', bytes, 'Slate: $pageTitle file'));
      case BlockType.image:
        if (!includeImages) break;
        final bytes = _blobOf(app, b.content['blob']);
        if (bytes == null) break;
        image++;
        final ext = _imageExt(b.content['mime'] as String?);
        uploads.add(_Upload('$dir/images/$base - image-$image$ext', bytes,
            'Slate: $pageTitle image'));
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

String _imageExt(String? mime) {
  switch (mime) {
    case 'image/jpeg':
      return '.jpg';
    case 'image/gif':
      return '.gif';
    case 'image/webp':
      return '.webp';
    case 'image/svg+xml':
      return '.svg';
    default:
      return '.png';
  }
}
