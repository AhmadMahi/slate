import 'package:flutter/material.dart';

import '../mindmap/mindmap.dart';
import '../mindmap/mindmap_ai.dart';
import '../state/app_state.dart';
import '../theme/onote_theme.dart';
import 'onote_dialog.dart';

/// Describe a mind map and let a cloud model draft it.
///
/// Returns the generated tree, or null if the user cancelled or nothing
/// usable came back. The caller decides whether to replace the current map.
Future<MindNode?> showMindmapAiDialog(BuildContext context, AppState app) {
  return showOnoteDialog<MindNode>(
    context: context,
    builder: (_) => _MindmapAiDialog(app: app),
  );
}

class _MindmapAiDialog extends StatefulWidget {
  const _MindmapAiDialog({required this.app});
  final AppState app;

  @override
  State<_MindmapAiDialog> createState() => _MindmapAiDialogState();
}

class _MindmapAiDialogState extends State<_MindmapAiDialog> {
  final _topic = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _topic.dispose();
    super.dispose();
  }

  Future<void> _generate() async {
    final client = widget.app.aiClient();
    if (client == null) {
      setState(() => _error =
          'Connect an AI provider first: Settings → Connections → AI provider.');
      return;
    }
    final topic = _topic.text.trim();
    if (topic.isEmpty) {
      setState(() => _error = 'Describe the mind map you want.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final res = await generateMindmapOutline(client, topic: topic);
    widget.app.addAiTokens(res.tokens);
    if (!mounted) return;
    if (!res.ok) {
      setState(() {
        _busy = false;
        _error = res.error ?? 'Something went wrong. Try again.';
      });
      return;
    }
    final root = mindmapFromOutline(res.markdown!);
    if (root == null) {
      setState(() {
        _busy = false;
        _error = 'The model did not return a usable outline. Try again.';
      });
      return;
    }
    Navigator.of(context).pop(root);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Generate a mind map with AI'),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Describe what the mind map should cover. The AI drafts it as a '
              'branching outline, which becomes the map.',
              style: TextStyle(fontSize: 12.5, height: 1.4),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _topic,
              autofocus: true,
              minLines: 2,
              maxLines: 4,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _busy ? null : _generate(),
              style: const TextStyle(fontSize: 13, height: 1.35),
              decoration: const InputDecoration(
                isDense: true,
                border: OutlineInputBorder(),
                hintText: 'e.g. the water cycle for a grade 6 class',
              ),
            ),
            if (_busy)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Row(children: [
                  SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2)),
                  SizedBox(width: 8),
                  Text('Thinking…', style: TextStyle(fontSize: 12.5)),
                ]),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(_error!,
                    style: const TextStyle(
                        fontSize: 12.5, color: OnoteColors.danger)),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: _busy ? null : _generate,
          icon: const Icon(Icons.auto_awesome, size: 16),
          label: const Text('Generate'),
        ),
      ],
    );
  }
}
