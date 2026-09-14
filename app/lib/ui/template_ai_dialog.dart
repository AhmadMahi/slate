import 'package:flutter/material.dart';

import '../ai/ai_prompts.dart';
import '../ai/template_ai.dart';
import '../state/app_state.dart';
import '../theme/onote_theme.dart';
import 'onote_dialog.dart';

/// Describe a page template and let a cloud model design it, then lay it out
/// below whatever is on the page (the same placement as any other template).
Future<void> showTemplateAiDialog(BuildContext context, AppState app) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final applied = await showOnoteDialog<bool>(
    context: context,
    builder: (_) => _TemplateAiDialog(app: app),
  );
  if (applied == true) {
    messenger?.showSnackBar(
        const SnackBar(content: Text('Template added to the page.')));
  }
}

class _TemplateAiDialog extends StatefulWidget {
  const _TemplateAiDialog({required this.app});
  final AppState app;

  @override
  State<_TemplateAiDialog> createState() => _TemplateAiDialogState();
}

class _TemplateAiDialogState extends State<_TemplateAiDialog> {
  final _desc = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _desc.dispose();
    super.dispose();
  }

  Future<void> _generate() async {
    final client = widget.app.aiClient();
    if (client == null) {
      setState(() => _error =
          'Connect an AI provider first: Settings → Connections → AI provider.');
      return;
    }
    final desc = _desc.text.trim();
    if (desc.isEmpty) {
      setState(() => _error = 'Describe the template you want.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final res = await generateTemplate(
      client,
      description: desc,
      systemPrompt: widget.app.systemPromptFor(AiFeature.template),
    );
    widget.app.addAiTokens(res.tokens);
    if (!mounted) return;
    if (!res.ok) {
      setState(() {
        _busy = false;
        _error = res.error ?? 'Something went wrong. Try again.';
      });
      return;
    }
    final ok = widget.app.applyTemplateRaw(res.json!);
    if (!mounted) return;
    Navigator.of(context).pop(ok);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Generate a template with AI'),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Describe the page layout you want. The AI drafts it as a set of '
              'headings and sections, which are placed below anything already '
              'on the page.',
              style: TextStyle(fontSize: 12.5, height: 1.4),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _desc,
              autofocus: true,
              minLines: 2,
              maxLines: 5,
              style: const TextStyle(fontSize: 13, height: 1.35),
              decoration: const InputDecoration(
                isDense: true,
                border: OutlineInputBorder(),
                hintText: 'e.g. a weekly lesson plan with objectives, '
                    'activities, homework and notes',
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
