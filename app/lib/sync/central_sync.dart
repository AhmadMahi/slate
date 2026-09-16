/// Central backup: keep EVERY notebook in one GitHub repo, as clean folders.
///
/// This is the "one place where everything lives" the owner asked for. Turn it
/// on once and, on a fresh notebook, on a change, and on a schedule, every
/// notebook is written into a single repository as a readable folder tree (the
/// same `Save as folders and files` format — Markdown, JSON and images, no
/// `ops`/`blobs`/`.onote` clutter), one folder per notebook.
///
/// **It is a one-way mirror, not the op-log sync.** It never pulls edits back
/// into a notebook; it exports what is here into the repo. That is what makes it
/// safe to run across ALL notebooks at once, and what keeps the repo clean and
/// browsable. The engine below owns a persistent local clone of the central
/// repo ([_mirrorDir]) so each push sends only what changed.
library;

import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../export/md_common.dart' show safeFilename;
import '../export/open_export.dart' show materializeNotebookInto;
import '../state/app_state.dart';
import 'git_sync.dart';
import 'github_api.dart';

class CentralSync {
  CentralSync(this._app);
  final AppState _app;

  bool enabled = false;
  String? remote; // clone URL of the central repo
  String? fullName; // owner/repo
  String? status;
  bool busy = false;

  /// notebook id → the folder name it lives under in the mirror. Kept so a
  /// renamed notebook moves its folder instead of leaving the old one behind.
  final Map<String, String> _folders = {};

  Timer? _debounce;

  String get _mirrorDir => p.join(_app.workspaceDirPath, 'central-mirror');

  bool get _gitReady => Directory(p.join(_mirrorDir, '.git')).existsSync();

  // ── Persistence ─────────────────────────────────────────────────────────

  void load(Object? raw) {
    if (raw is! Map) return;
    enabled = raw['enabled'] == true;
    remote = raw['remote'] as String?;
    fullName = raw['fullName'] as String?;
    _folders.clear();
    final f = raw['folders'];
    if (f is Map) {
      f.forEach((k, v) {
        if (k is String && v is String) _folders[k] = v;
      });
    }
  }

  Map<String, Object?> _toJson() => {
        'enabled': enabled,
        if (remote != null) 'remote': remote,
        if (fullName != null) 'fullName': fullName,
        'folders': Map<String, String>.from(_folders),
      };

  void _save() => _app.persistCentralSync(enabled ? _toJson() : null);

  // ── Enable / disable ──────────────────────────────────────────────────────

  /// Turn central backup on. With [existingRemote] it binds to a repo you
  /// already have; otherwise it creates a new private one (named `slate-<you>`
  /// or [name]). Then it clones the repo locally and runs a first full backup.
  /// Returns null on success, or a message.
  Future<String?> enable({String? existingRemote, String? name}) async {
    if (!_app.githubConnected) return 'Connect a GitHub account first.';
    if (await GitSync.gitExecutable() == null) {
      return 'Git is not installed on this computer. Install it from '
          'git-scm.com to back up all notebooks.';
    }
    busy = true;
    status = 'Preparing the backup repository…';
    _app.notifyCentral();
    try {
      final api = _app.githubApi();
      if (api == null) return 'Connect a GitHub account first.';
      String url;
      String full;
      if (existingRemote != null && existingRemote.trim().isNotEmpty) {
        url = existingRemote.trim();
        final fn = repoFullNameFromRemote(url);
        if (fn == null) return 'That is not a GitHub repository URL.';
        full = fn;
      } else {
        final repoName = (name?.trim().isNotEmpty ?? false)
            ? repoNameFor(name!)
            : 'slate-${_app.githubLogin ?? 'notebooks'}';
        final made = await api.createRepo(repoName,
            private: true, description: 'Slate — all notebooks backup');
        if (!made.ok) return made.error;
        url = made.cloneUrl!;
        full = made.fullName!;
      }
      remote = url;
      fullName = full;
      enabled = true;
      // A fresh clone of the (possibly empty) repo, so pushes send only deltas.
      await _prepareMirror();
      _save();
      final err = await syncAll();
      return err;
    } catch (e) {
      return 'Could not enable backup: $e';
    } finally {
      busy = false;
      _app.notifyCentral();
    }
  }

  void disable() {
    enabled = false;
    _debounce?.cancel();
    status = null;
    _save();
    _app.notifyCentral();
  }

  /// Clone the central repo into [_mirrorDir] if it is not already a clone.
  Future<void> _prepareMirror() async {
    if (_gitReady) return;
    final dir = Directory(_mirrorDir);
    if (dir.existsSync()) dir.deleteSync(recursive: true);
    final r = await GitSync.clone(remote!, _mirrorDir,
        token: _app.githubTokenForSync);
    if (!r.ok) {
      // An empty repo clones to an empty working tree with a .git; some git
      // builds still return non-zero with a warning. Fall back to init when the
      // clone did not leave a usable repo.
      if (!_gitReady) {
        final g = GitSync(_mirrorDir, token: _app.githubTokenForSync);
        await Directory(_mirrorDir).create(recursive: true);
        await g.init();
        await g.setRemote(remote!);
      }
    }
  }

  // ── Syncing ───────────────────────────────────────────────────────────────

  /// Debounced backup of the OPEN notebook — cheap enough to run after edits.
  void scheduleSync() {
    if (!enabled) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 90), () {
      unawaited(syncCurrent());
    });
  }

  /// Back up every notebook. Used on enable, on create, and periodically.
  Future<String?> syncAll() => _run((mirror) async {
        await _app.flushSave();
        for (final nb in _app.notebooks) {
          await _materialiseNotebook(nb.id, nb.title);
        }
      }, 'Slate: back up all notebooks');

  /// Back up just the open notebook (the debounced path).
  Future<String?> syncCurrent() {
    final id = _app.notebookId;
    if (id == null) return Future.value();
    final nb = _app.notebooks.where((n) => n.id == id).firstOrNull;
    if (nb == null) return Future.value();
    return _run((mirror) async {
      await _app.flushSave();
      await _materialiseNotebook(nb.id, nb.title);
    }, 'Slate: back up ${nb.title}');
  }

  /// Remove a notebook's folder from the backup (after the user confirmed the
  /// deletion should also apply to GitHub).
  Future<String?> removeNotebook(String nbId, String title) =>
      _run((mirror) async {
        final folder = _folders[nbId] ?? safeFilename(title);
        final dir = Directory(p.join(mirror, folder));
        if (dir.existsSync()) dir.deleteSync(recursive: true);
        _folders.remove(nbId);
      }, 'Slate: remove $title from backup');

  /// Materialize one notebook into `mirror/<folder>/`, cleaning the folder
  /// first (so deleted pages disappear) and moving it if the notebook was
  /// renamed since last time.
  ///
  /// Page PDFs are written for the OPEN notebook (the PDF builder reads the open
  /// page). For a closed notebook we cannot regenerate them, so any PDFs already
  /// in its folder are preserved across the wipe — so a notebook keeps the PDFs
  /// from the last time it was open.
  Future<void> _materialiseNotebook(String nbId, String title) async {
    final desired = _uniqueFolder(nbId, title);
    final prev = _folders[nbId];
    if (prev != null && prev != desired) {
      final old = Directory(p.join(_mirrorDir, prev));
      if (old.existsSync()) old.deleteSync(recursive: true);
    }
    final dir = Directory(p.join(_mirrorDir, desired));
    final isOpen = nbId == _app.notebookId;

    // Preserve existing PDFs for a closed notebook (keyed by path within the
    // folder), since we cannot rebuild them here.
    final savedPdfs = <String, List<int>>{};
    if (dir.existsSync()) {
      if (!isOpen) {
        for (final f in dir.listSync(recursive: true).whereType<File>()) {
          if (f.path.toLowerCase().endsWith('.pdf')) {
            savedPdfs[p.relative(f.path, from: dir.path)] = f.readAsBytesSync();
          }
        }
      }
      dir.deleteSync(recursive: true);
    }

    await materializeNotebookInto(_app, nbId, dir.path, withPagePdf: isOpen);

    if (!isOpen) {
      for (final e in savedPdfs.entries) {
        final target = File(p.join(dir.path, e.key));
        target.parent.createSync(recursive: true);
        target.writeAsBytesSync(e.value);
      }
    }
    _folders[nbId] = desired;
  }

  /// A stable, readable, collision-free folder name for a notebook.
  String _uniqueFolder(String nbId, String title) {
    final base = safeFilename(title);
    // Keep the name this notebook already uses if it still matches its title.
    if (_folders[nbId] != null &&
        _folders[nbId] == base &&
        !_folders.entries.any((e) => e.key != nbId && e.value == base)) {
      return base;
    }
    var candidate = base;
    var i = 2;
    bool taken(String c) =>
        _folders.entries.any((e) => e.key != nbId && e.value == c);
    while (taken(candidate)) {
      candidate = '$base-$i';
      i++;
    }
    return candidate;
  }

  /// Shared wrapper: guard, prepare the mirror, run [body], commit and push.
  Future<String?> _run(
      Future<void> Function(String mirror) body, String message) async {
    if (!enabled) return null;
    if (!_app.githubConnected) {
      status = 'Sign in to GitHub to back up.';
      _app.notifyCentral();
      return status;
    }
    if (busy) return null;
    busy = true;
    status = 'Backing up…';
    _app.notifyCentral();
    try {
      await _prepareMirror();
      await body(_mirrorDir);
      _save();
      final git = GitSync(_mirrorDir, token: _app.githubTokenForSync);
      final r = await git.syncOnce(message: message);
      status =
          r.ok ? 'Backed up' : 'Backup failed: ${r.message.split('\n').first}';
      return r.ok ? null : status;
    } catch (e) {
      status = 'Backup failed: $e';
      return status;
    } finally {
      busy = false;
      _app.notifyCentral();
    }
  }

  /// Delete the LOCAL copies of every notebook — the GitHub backup keeps them.
  /// For wiping a borrowed machine clean after a restore. Returns how many were
  /// removed (the app keeps at least one notebook, so the last may remain).
  Future<int> removeLocalCopies() async {
    var removed = 0;
    for (final id in [for (final n in _app.notebooks) n.id]) {
      if (await _app.deleteNotebook(id)) removed++;
    }
    _folders.clear();
    if (enabled) _save();
    _app.notifyCentral();
    return removed;
  }

  void dispose() => _debounce?.cancel();
}
