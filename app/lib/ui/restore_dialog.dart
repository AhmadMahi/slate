import 'package:flutter/material.dart';

import '../core/platform_open.dart';
import '../state/app_state.dart';
import '../sync/central_restore.dart';
import '../sync/github_api.dart';
import '../theme/onote_theme.dart';
import 'onote_dialog.dart';

/// Import notebooks from a GitHub backup — the restore side of "Sync all
/// notebooks". Connect an account, point at the backup repo, and every notebook
/// it holds is rebuilt locally. Notebooks already here are skipped.
Future<void> showRestoreDialog(BuildContext context, AppState app) {
  return showOnoteDialog<void>(
    context: context,
    builder: (_) => _RestoreDialog(app: app),
  );
}

class _RestoreDialog extends StatefulWidget {
  const _RestoreDialog({required this.app});
  final AppState app;

  @override
  State<_RestoreDialog> createState() => _RestoreDialogState();
}

class _RestoreDialogState extends State<_RestoreDialog> {
  AppState get app => widget.app;
  final _token = TextEditingController();
  bool _busy = false;
  String? _error;
  String? _progress;
  String? _done;

  @override
  void dispose() {
    _token.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final err = await app.connectGitHub(_token.text);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = err;
      if (err == null) _token.clear();
    });
  }

  Future<void> _restoreFrom(String cloneUrl) async {
    setState(() {
      _busy = true;
      _error = null;
      _done = null;
      _progress = 'Starting…';
    });
    final res = await restoreNotebooksFrom(app, cloneUrl, onProgress: (m) {
      if (mounted) setState(() => _progress = m);
    });
    if (!mounted) return;
    setState(() {
      _busy = false;
      _progress = null;
      if (res.ok) {
        _done = 'Restored ${res.imported} notebook'
            '${res.imported == 1 ? '' : 's'}'
            '${res.skipped > 0 ? ' (${res.skipped} already here)' : ''}.';
      } else {
        _error = res.error;
      }
    });
  }

  Future<void> _pickAndRestore() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final repos = await app.githubListRepos();
    if (!mounted) return;
    setState(() => _busy = false);
    if (repos == null || repos.isEmpty) {
      setState(() => _error = repos == null
          ? 'Could not load your repositories.'
          : 'You have no repositories yet.');
      return;
    }
    final picked = await showOnoteDialog<GitHubRepo>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Choose your backup repository'),
        children: [
          SizedBox(
            width: 400,
            height: 340,
            child: ListView.builder(
              itemCount: repos.length,
              itemBuilder: (_, i) => ListTile(
                dense: true,
                leading: Icon(
                    repos[i].private ? Icons.lock_outline : Icons.public,
                    size: 18),
                title: Text(repos[i].fullName,
                    style: const TextStyle(fontSize: 13)),
                onTap: () => Navigator.pop(ctx, repos[i]),
              ),
            ),
          ),
        ],
      ),
    );
    if (picked == null || !mounted) return;
    await _restoreFrom(picked.cloneUrl);
  }

  @override
  Widget build(BuildContext context) {
    final central = app.central;
    return AlertDialog(
      title: const Text('Import notebooks from GitHub'),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Rebuild notebooks from a GitHub backup onto this computer — '
              'structure, notes, drawings, images and files. Notebooks already '
              'here are skipped, not duplicated.',
              style: TextStyle(fontSize: 12.5, height: 1.4),
            ),
            const SizedBox(height: 14),
            if (!app.githubConnected)
              ..._connectAccount(context)
            else ...[
              if (central.remote != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: FilledButton.icon(
                    onPressed:
                        _busy ? null : () => _restoreFrom(central.remote!),
                    icon: const Icon(Icons.cloud_download_outlined, size: 16),
                    label: Text(
                      'Restore from ${central.fullName ?? 'your backup'}',
                      style: const TextStyle(fontSize: 12.5),
                    ),
                  ),
                ),
              OutlinedButton.icon(
                onPressed: _busy ? null : _pickAndRestore,
                icon: const Icon(Icons.folder_open_outlined, size: 16),
                label: Text(
                    central.remote == null
                        ? 'Choose backup repository…'
                        : 'Restore from another repository…',
                    style: const TextStyle(fontSize: 12.5)),
              ),
            ],
            if (_progress != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Row(children: [
                  const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2)),
                  const SizedBox(width: 8),
                  Expanded(
                      child: Text(_progress!,
                          style: const TextStyle(fontSize: 12.5))),
                ]),
              ),
            if (_done != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Row(children: [
                  const Icon(Icons.check_circle,
                      size: 16, color: Color(0xFF2E9E5B)),
                  const SizedBox(width: 6),
                  Expanded(
                      child:
                          Text(_done!, style: const TextStyle(fontSize: 12.5))),
                ]),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(_error!,
                    style: const TextStyle(
                        fontSize: 12, height: 1.4, color: OnoteColors.danger)),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(_done != null ? 'Done' : 'Close')),
      ],
    );
  }

  List<Widget> _connectAccount(BuildContext context) => [
        const Text('First, connect your GitHub account.',
            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        TextField(
          controller: _token,
          obscureText: true,
          style: const TextStyle(fontSize: 12),
          decoration: const InputDecoration(
            isDense: true,
            labelText: 'GitHub token',
            hintText: 'Paste a token with the "repo" scope',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        Row(children: [
          FilledButton(
            onPressed: _busy ? null : _connect,
            child: Text(_busy ? 'Connecting…' : 'Connect'),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: () => PlatformOpen.url(GitHubApi.tokenPage),
            child: const Text('Get a token', style: TextStyle(fontSize: 12)),
          ),
        ]),
      ];
}
