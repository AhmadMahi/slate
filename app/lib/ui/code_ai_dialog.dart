import 'package:flutter/material.dart';

import '../ai/ai_prompts.dart';
import '../code/code_ai.dart';
import '../state/app_state.dart';
import '../theme/onote_theme.dart';
import 'onote_dialog.dart';

/// Ask the AI to write or rewrite a code block.
///
/// [existing] is what the block already holds and [languageName] the chosen
/// language. Returns the generated code to drop into the block, or null if the
/// user cancelled or nothing usable came back. When there is existing code the
/// dialog is framed as "rewrite"; when empty, as "generate".
Future<String?> showCodeAiDialog(
  BuildContext context,
  AppState app, {
  required String existing,
  required String languageName,
}) {
  return showOnoteDialog<String>(
    context: context,
    builder: (_) => _CodeAiDialog(
      app: app,
      existing: existing,
      languageName: languageName,
    ),
  );
}

class _CodeAiDialog extends StatefulWidget {
  const _CodeAiDialog({
    required this.app,
    required this.existing,
    required this.languageName,
  });
  final AppState app;
  final String existing;
  final String languageName;

  @override
  State<_CodeAiDialog> createState() => _CodeAiDialogState();
}

class _CodeAiDialogState extends State<_CodeAiDialog> {
  final _instruction = TextEditingController();
  bool _busy = false;
  String? _error;

  bool get _hasCode => widget.existing.trim().isNotEmpty;

  @override
  void dispose() {
    _instruction.dispose();
    super.dispose();
  }

  Future<void> _generate() async {
    final client = widget.app.aiClient();
    if (client == null) {
      setState(() => _error =
          'Connect an AI provider first: Settings → Connections → AI provider.');
      return;
    }
    final instruction = _instruction.text.trim();
    if (instruction.isEmpty) {
      setState(() => _error = _hasCode
          ? 'Say how the code should change.'
          : 'Describe the code you want.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final res = await generateCode(
      client,
      instruction: instruction,
      existing: widget.existing,
      languageName: widget.languageName,
      systemPrompt: widget.app.systemPromptFor(AiFeature.code),
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
    Navigator.of(context).pop(res.code);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_hasCode ? 'Rewrite code with AI' : 'Generate code with AI'),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _hasCode
                  ? 'Say what to change about the ${widget.languageName} code '
                      'already in this block. The whole block is replaced with '
                      'the result.'
                  : 'Describe the ${widget.languageName} code you want. It is '
                      'written straight into this block.',
              style: const TextStyle(fontSize: 12.5, height: 1.4),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _instruction,
              autofocus: true,
              minLines: 2,
              maxLines: 5,
              style: const TextStyle(fontSize: 13, height: 1.35),
              decoration: InputDecoration(
                isDense: true,
                border: const OutlineInputBorder(),
                hintText: _hasCode
                    ? 'e.g. add error handling and comments'
                    : 'e.g. a function that reverses a linked list',
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
          label: Text(_hasCode ? 'Rewrite' : 'Generate'),
        ),
      ],
    );
  }
}
