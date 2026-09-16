import 'package:flutter/material.dart';

import '../core/platform_open.dart';
import '../state/app_state.dart';
import '../sync/github_api.dart';
import '../theme/onote_theme.dart';
import 'onote_dialog.dart';

/// Settings → **Sync all notebooks**: one repo that backs up every notebook.
///
/// A one-way mirror in the clean "folders and files" format — turn it on and
/// every notebook (and every new one) is kept in a single GitHub repository,
/// automatically. See `sync/central_sync.dart`.
Future<void> showCentralSyncDialog(BuildContext context, AppState app) {
  return showOnoteDialog<void>(
    context: context,
    builder: (_) => _CentralSyncDialog(app: app),
  );
}

class _CentralSyncDialog extends StatefulWidget {
  const _CentralSyncDialog({required this.app});
  final AppState app;

  @override
  State<_CentralSyncDialog> createState() => _CentralSyncDialogState();
}

class _CentralSyncDialogState extends State<_CentralSyncDialog> {
  AppState get app => widget.app;
  final _token = TextEditingController();
  final _name = TextEditingController();
  bool _busy = false;
  String? _error;

  static const _green = Color(0xFF2E9E5B);

  @override
  void initState() {
    super.initState();
    _name.text = 'slate-${app.githubLogin ?? 'notebooks'}';
  }

  @override
  void dispose() {
    _token.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _do(Future<String?> Function() fn) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final err = await fn();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = err;
    });
  }

  Future<void> _chooseExisting() async {
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
          : 'You have no repositories yet. Create one.');
      return;
    }
    final picked = await showOnoteDialog<GitHubRepo>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Choose a backup repository'),
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
    await _do(() => app.central.enable(existingRemote: picked.cloneUrl));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        final c = app.central;
        return AlertDialog(
          title: const Text('Sync all notebooks'),
          content: SizedBox(
            width: 460,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Keep every notebook in ONE GitHub repository, as clean, '
                  'readable folders (Markdown, images and structure — no '
                  'internal clutter). It backs up automatically as you work and '
                  'whenever you make a new notebook. One-way backup: it uploads '
                  'what is here and never changes your notebooks.',
                  style: TextStyle(fontSize: 12.5, height: 1.4),
                ),
                const SizedBox(height: 12),
                if (!app.githubConnected)
                  ..._connectAccount(context)
                else if (!c.enabled)
                  ..._setup(context)
                else
                  ..._on(context, c),
                if (c.busy)
                  const Padding(
                    padding: EdgeInsets.only(top: 10),
                    child: Row(children: [
                      SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2)),
                      SizedBox(width: 8),
                      Text('Working…', style: TextStyle(fontSize: 12.5)),
                    ]),
                  ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(_error!,
                        style: const TextStyle(
                            fontSize: 12,
                            height: 1.4,
                            color: OnoteColors.danger)),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Close')),
          ],
        );
      },
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
            onPressed:
                _busy ? null : () => _do(() => app.connectGitHub(_token.text)),
            child: Text(_busy ? 'Connecting…' : 'Connect'),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: () => PlatformOpen.url(GitHubApi.tokenPage),
            child: const Text('Get a token', style: TextStyle(fontSize: 12)),
          ),
        ]),
      ];

  List<Widget> _setup(BuildContext context) => [
        Text('Signed in as ${app.githubLogin}.',
            style:
                const TextStyle(fontSize: 12, color: OnoteColors.graphite400)),
        const SizedBox(height: 8),
        TextField(
          controller: _name,
          style: const TextStyle(fontSize: 12),
          decoration: const InputDecoration(
            isDense: true,
            labelText: 'New backup repository name',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        Row(children: [
          FilledButton.icon(
            onPressed: _busy
                ? null
                : () => _do(() => app.central.enable(name: _name.text)),
            icon: const Icon(Icons.cloud_done_outlined, size: 16),
            label: const Text('Turn on backup', style: TextStyle(fontSize: 12)),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: _busy ? null : _chooseExisting,
            icon: const Icon(Icons.folder_open_outlined, size: 16),
            label: const Text('Use existing repo…',
                style: TextStyle(fontSize: 12)),
          ),
        ]),
      ];

  List<Widget> _on(BuildContext context, dynamic c) => [
        Row(children: [
          const Icon(Icons.check_circle, size: 18, color: _green),
          const SizedBox(width: 6),
          Expanded(
            child: Text('Backing up all notebooks to ${c.fullName ?? c.remote}',
                style:
                    const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          ),
        ]),
        if (c.status != null)
          Padding(
            padding: const EdgeInsets.only(top: 2, left: 24),
            child: Text(c.status as String,
                style: const TextStyle(
                    fontSize: 11.5, color: OnoteColors.graphite400)),
          ),
        const SizedBox(height: 10),
        Row(children: [
          FilledButton.tonalIcon(
            onPressed: _busy ? null : () => _do(() => app.central.syncAll()),
            icon: const Icon(Icons.sync, size: 16),
            label: const Text('Back up now', style: TextStyle(fontSize: 12)),
          ),
          const Spacer(),
          TextButton(
            onPressed: _busy ? null : () => setState(app.central.disable),
            child: const Text('Turn off', style: TextStyle(fontSize: 12)),
          ),
        ]),
        const Divider(height: 20),
        // A distinct, guarded destructive action — for clearing a borrowed
        // machine after a restore. The GitHub backup is untouched.
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: _busy ? null : _removeLocalCopies,
            icon: const Icon(Icons.delete_sweep_outlined,
                size: 16, color: OnoteColors.danger),
            label: const Text('Remove local copies…',
                style: TextStyle(fontSize: 12, color: OnoteColors.danger)),
          ),
        ),
        const Text(
          'Deletes every notebook from THIS computer. Your GitHub backup keeps '
          'them, and you can restore again any time.',
          style: TextStyle(fontSize: 11, color: OnoteColors.graphite400),
        ),
      ];

  Future<void> _removeLocalCopies() async {
    final ok = await showOnoteDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove local copies?'),
        content: const Text(
          'This deletes every notebook from this computer. Your GitHub backup '
          'is not touched — you can restore them again any time.',
          style: TextStyle(fontSize: 13, height: 1.4),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: OnoteColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove from this computer'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    final n = await app.central.removeLocalCopies();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = null;
    });
    final m = ScaffoldMessenger.maybeOf(context);
    m?.showSnackBar(SnackBar(
        content: Text('Removed $n notebook${n == 1 ? '' : 's'} from this '
            'computer. The backup is unchanged.')));
  }
}
