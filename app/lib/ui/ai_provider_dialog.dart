import 'package:flutter/material.dart';

import '../ai/ai_provider.dart';
import '../core/platform_open.dart';
import '../state/app_state.dart';
import '../theme/onote_theme.dart';
import 'onote_dialog.dart';

/// Connect a cloud AI by pasting your own key.
///
/// Separate from "AI access" (which lets an external tool read these notes):
/// this points Slate itself at OpenAI or OpenRouter, with the user's key, to
/// power the quiz generator, the mind-map generator and Ask AI. You pick a
/// provider, paste a key, type a model name, and Slate makes one tiny test
/// call before it keeps anything — a green tick means it worked.
Future<void> showAiProviderDialog(BuildContext context, AppState app) {
  return showOnoteDialog<void>(
    context: context,
    builder: (_) => _AiProviderDialog(app: app),
  );
}

class _AiProviderDialog extends StatefulWidget {
  const _AiProviderDialog({required this.app});
  final AppState app;

  @override
  State<_AiProviderDialog> createState() => _AiProviderDialogState();
}

class _AiProviderDialogState extends State<_AiProviderDialog> {
  AppState get app => widget.app;

  late AiProvider _provider = app.aiProvider;
  final _keyCtrl = TextEditingController();
  final _modelCtrl = TextEditingController();
  final _promptCtrl = TextEditingController();
  bool _busy = false;
  String? _error;
  bool _justConnected = false;
  bool _replacingKey = false;

  static const _green = Color(0xFF2E9E5B);

  @override
  void initState() {
    super.initState();
    _modelCtrl.text = app.aiModelFor(_provider);
    _promptCtrl.text = app.askAiSystemPrompt;
  }

  @override
  void dispose() {
    _keyCtrl.dispose();
    _modelCtrl.dispose();
    _promptCtrl.dispose();
    super.dispose();
  }

  void _switchProvider(AiProvider p) {
    if (p == _provider) return;
    setState(() {
      _provider = p;
      _keyCtrl.clear();
      _modelCtrl.text = app.aiModelFor(p);
      _error = null;
      _justConnected = false;
      _replacingKey = false;
    });
    app.setAiProvider(p);
  }

  Future<void> _connect() async {
    setState(() {
      _busy = true;
      _error = null;
      _justConnected = false;
    });
    final msg = await app.connectAi(_provider, _keyCtrl.text, _modelCtrl.text);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = msg;
      _justConnected = msg == null;
      if (msg == null) {
        _keyCtrl.clear();
        _replacingKey = false;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        final verified = app.aiVerified(_provider);
        return AlertDialog(
          title: const Text('AI provider'),
          content: SizedBox(
            width: 480,
            child: ListView(
              shrinkWrap: true,
              children: [
                const Text(
                  'Let Slate use a cloud AI for the quiz generator, the '
                  'mind-map generator and Ask AI. Bring your own key: it is '
                  'stored in this computer\'s password storage, never in a '
                  'file or a notebook, and is sent only to the provider you '
                  'pick.',
                  style: TextStyle(fontSize: 12.5, height: 1.4),
                ),
                const SizedBox(height: 12),
                SegmentedButton<AiProvider>(
                  showSelectedIcon: false,
                  style: const ButtonStyle(
                      visualDensity: VisualDensity.compact,
                      textStyle:
                          WidgetStatePropertyAll(TextStyle(fontSize: 11.5))),
                  segments: const [
                    ButtonSegment(
                        value: AiProvider.openai, label: Text('OpenAI')),
                    ButtonSegment(
                        value: AiProvider.openrouter,
                        label: Text('OpenRouter')),
                  ],
                  selected: {_provider},
                  onSelectionChanged: (s) => _switchProvider(s.first),
                ),
                const SizedBox(height: 14),
                if (verified && !_replacingKey)
                  ..._connected(context, scheme)
                else
                  ..._connectForm(context, scheme),
                const Divider(height: 26),
                ..._askAiInstructions(context),
                const Divider(height: 26),
                _tokenRow(context),
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

  // The connected state: a green tick, the model (editable), and disconnect.
  List<Widget> _connected(BuildContext context, ColorScheme scheme) => [
        Row(
          children: [
            const Icon(Icons.check_circle, size: 18, color: _green),
            const SizedBox(width: 6),
            Expanded(
              child: Text('${_provider.label} connected',
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600)),
            ),
            TextButton(
              onPressed: () => app.disconnectAi(_provider),
              child: const Text('Disconnect', style: TextStyle(fontSize: 12)),
            ),
          ],
        ),
        const SizedBox(height: 6),
        _modelField(onChanged: (v) => app.setAiModel(_provider, v)),
        if (app.aiModel.trim().isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text('Type a model name to start using it.',
                style: TextStyle(fontSize: 11, color: OnoteColors.danger)),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            icon: const Icon(Icons.key, size: 14),
            label:
                const Text('Replace API key', style: TextStyle(fontSize: 12)),
            onPressed: () => setState(() {
              _replacingKey = true;
              _keyCtrl.clear();
              _error = null;
              _justConnected = false;
            }),
          ),
        ),
      ];

  // The setup form: key + model + Connect (also used when replacing a key).
  List<Widget> _connectForm(BuildContext context, ColorScheme scheme) => [
        TextField(
          controller: _keyCtrl,
          obscureText: true,
          autofocus: true,
          style: const TextStyle(fontSize: 13),
          decoration: InputDecoration(
            isDense: true,
            labelText: '${_provider.label} API key',
            hintText: 'Paste your key',
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 10),
        _modelField(),
        const SizedBox(height: 10),
        Row(
          children: [
            FilledButton.icon(
              icon: _busy
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.link, size: 16),
              label: Text(_busy ? 'Testing…' : 'Connect'),
              onPressed: _busy ? null : _connect,
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: () => PlatformOpen.url(_provider.keysPage),
              child: const Text('Get a key', style: TextStyle(fontSize: 12)),
            ),
            if (_replacingKey) ...[
              const Spacer(),
              TextButton(
                onPressed: () => setState(() => _replacingKey = false),
                child: const Text('Cancel', style: TextStyle(fontSize: 12)),
              ),
            ],
          ],
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(_error!,
                style: const TextStyle(
                    fontSize: 12, height: 1.4, color: OnoteColors.danger)),
          ),
        if (_justConnected)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(children: [
              const Icon(Icons.check_circle, size: 16, color: _green),
              const SizedBox(width: 6),
              Text('Connected. ${_provider.label} accepted the key.',
                  style: const TextStyle(fontSize: 12, color: _green)),
            ]),
          ),
      ];

  Widget _modelField({ValueChanged<String>? onChanged}) => TextField(
        controller: _modelCtrl,
        onChanged: onChanged,
        style: const TextStyle(fontSize: 13),
        decoration: InputDecoration(
          isDense: true,
          labelText: 'Model',
          hintText: _provider.modelHint,
          border: const OutlineInputBorder(),
        ),
      );

  // The Ask AI system prompt, editable so a teacher can steer tone/subject.
  List<Widget> _askAiInstructions(BuildContext context) => [
        Row(
          children: [
            const Expanded(
              child: Text('Ask AI instructions',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            ),
            TextButton(
              onPressed: () {
                _promptCtrl.text = kDefaultAskAiPrompt;
                app.setAskAiSystemPrompt(kDefaultAskAiPrompt);
              },
              child: const Text('Reset', style: TextStyle(fontSize: 12)),
            ),
          ],
        ),
        const Text(
          'How the Ask AI chat should answer — its style, subject or language. '
          'For example: "You are a patient tutor for high-school biology. Use '
          'simple analogies and end with a quick check question."',
          style: TextStyle(fontSize: 11.5, color: OnoteColors.graphite400),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _promptCtrl,
          minLines: 3,
          maxLines: 6,
          style: const TextStyle(fontSize: 12.5, height: 1.35),
          decoration: const InputDecoration(
            isDense: true,
            border: OutlineInputBorder(),
          ),
          onChanged: app.setAskAiSystemPrompt,
        ),
      ];

  Widget _tokenRow(BuildContext context) => Row(
        children: [
          const Icon(Icons.data_usage,
              size: 15, color: OnoteColors.graphite400),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'Tokens used: ${_formatCount(app.aiTokensUsed)}',
              style:
                  const TextStyle(fontSize: 12, color: OnoteColors.graphite400),
            ),
          ),
          if (app.aiTokensUsed > 0)
            TextButton(
              onPressed: app.resetAiTokens,
              child: const Text('Reset', style: TextStyle(fontSize: 12)),
            ),
        ],
      );

  static String _formatCount(int n) {
    final s = n.toString();
    final b = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
      b.write(s[i]);
    }
    return b.toString();
  }
}
