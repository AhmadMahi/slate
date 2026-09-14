import 'package:flutter/material.dart';

import '../ai/ai_prompts.dart';
import '../ai/ai_provider.dart';
import '../core/platform_open.dart';
import '../state/app_state.dart';
import '../theme/onote_theme.dart';
import 'onote_dialog.dart';

/// Connect a cloud AI by pasting your own key.
///
/// Separate from "AI access" (which lets an external tool read these notes):
/// this points Slate itself at OpenAI or OpenRouter, with the user's key, to
/// power the quiz generator, the mind-map generator, code generation, templates
/// and Ask AI. You pick a provider, paste a key, type a model name, and Slate
/// makes one tiny test call before it keeps anything — a green tick means it
/// worked. When you have keys for both, the "Provider in use" control chooses
/// which one every AI feature calls.
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

  // Which provider the FORM below is showing. It starts on the one in use, but
  // switching it only changes what you are configuring — the provider actually
  // used is chosen explicitly by "Use this provider" (or set on a fresh
  // connect), so peeking at the other provider's settings never silently
  // switches which key your quizzes go through.
  late AiProvider _editing = app.aiProvider;
  final _keyCtrl = TextEditingController();
  final _modelCtrl = TextEditingController();
  bool _busy = false;
  String? _error;
  bool _justConnected = false;
  bool _replacingKey = false;

  // One text controller per AI feature's editable instruction.
  final Map<AiFeature, TextEditingController> _prompts = {};

  static const _green = Color(0xFF2E9E5B);

  @override
  void initState() {
    super.initState();
    _modelCtrl.text = app.aiModelFor(_editing);
    for (final f in AiFeature.values) {
      _prompts[f] = TextEditingController(text: app.systemPromptFor(f));
    }
  }

  @override
  void dispose() {
    _keyCtrl.dispose();
    _modelCtrl.dispose();
    for (final c in _prompts.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _switchEditing(AiProvider p) {
    if (p == _editing) return;
    setState(() {
      _editing = p;
      _keyCtrl.clear();
      _modelCtrl.text = app.aiModelFor(p);
      _error = null;
      _justConnected = false;
      _replacingKey = false;
    });
  }

  Future<void> _connect() async {
    setState(() {
      _busy = true;
      _error = null;
      _justConnected = false;
    });
    final msg = await app.connectAi(_editing, _keyCtrl.text, _modelCtrl.text);
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
        final verified = app.aiVerified(_editing);
        return AlertDialog(
          title: const Text('AI provider'),
          content: SizedBox(
            width: 480,
            child: ListView(
              shrinkWrap: true,
              children: [
                const Text(
                  'Let Slate use a cloud AI for the quiz generator, the '
                  'mind-map generator, code generation, templates and Ask AI. '
                  'Bring your own key: it is stored in this computer\'s '
                  'password storage, never in a file or a notebook, and is sent '
                  'only to the provider you pick.',
                  style: TextStyle(fontSize: 12.5, height: 1.4),
                ),
                const SizedBox(height: 12),
                _providerInUseRow(context, scheme),
                const Divider(height: 26),
                Text('Set up ${_editing.label}',
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                SegmentedButton<AiProvider>(
                  showSelectedIcon: false,
                  style: const ButtonStyle(
                      visualDensity: VisualDensity.compact,
                      textStyle:
                          WidgetStatePropertyAll(TextStyle(fontSize: 11.5))),
                  segments: [
                    ButtonSegment(
                        value: AiProvider.openai,
                        label: Text(app.aiVerified(AiProvider.openai)
                            ? 'OpenAI ✓'
                            : 'OpenAI')),
                    ButtonSegment(
                        value: AiProvider.openrouter,
                        label: Text(app.aiVerified(AiProvider.openrouter)
                            ? 'OpenRouter ✓'
                            : 'OpenRouter')),
                  ],
                  selected: {_editing},
                  onSelectionChanged: (s) => _switchEditing(s.first),
                ),
                const SizedBox(height: 14),
                if (verified && !_replacingKey)
                  ..._connected(context, scheme)
                else
                  ..._connectForm(context, scheme),
                const Divider(height: 26),
                ..._systemPrompts(context),
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

  // Which provider every AI feature actually calls. Only a verified provider
  // can be chosen; the active one carries an "In use" tick.
  Widget _providerInUseRow(BuildContext context, ColorScheme scheme) {
    final openaiOk = app.aiVerified(AiProvider.openai);
    final routerOk = app.aiVerified(AiProvider.openrouter);
    final anyOk = openaiOk || routerOk;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Provider in use',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        const SizedBox(height: 2),
        Text(
          anyOk
              ? 'Every AI feature uses this provider. Switch it any time.'
              : 'Connect a provider below, then choose it here.',
          style:
              const TextStyle(fontSize: 11.5, color: OnoteColors.graphite400),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final p in AiProvider.values)
              _inUseChip(context, scheme, p, app.aiVerified(p)),
          ],
        ),
      ],
    );
  }

  Widget _inUseChip(
      BuildContext context, ColorScheme scheme, AiProvider p, bool connected) {
    final active = app.aiProvider == p && app.aiConnected;
    return ChoiceChip(
      showCheckmark: false,
      avatar: active
          ? const Icon(Icons.check_circle, size: 16, color: _green)
          : Icon(connected ? Icons.radio_button_unchecked : Icons.lock_outline,
              size: 16, color: OnoteColors.graphite400),
      label: Text(p.label, style: const TextStyle(fontSize: 12)),
      selected: active,
      onSelected: connected && !active
          ? (_) {
              app.setAiProvider(p);
              _switchEditing(p);
            }
          : null,
    );
  }

  // The connected state: a green tick, the model (editable), and disconnect.
  List<Widget> _connected(BuildContext context, ColorScheme scheme) {
    final inUse = app.aiProvider == _editing && app.aiConnected;
    return [
      Row(
        children: [
          const Icon(Icons.check_circle, size: 18, color: _green),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
                '${_editing.label} connected${inUse ? ' · in use' : ''}',
                style:
                    const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          ),
          TextButton(
            onPressed: () => app.disconnectAi(_editing),
            child: const Text('Disconnect', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
      const SizedBox(height: 6),
      _modelField(onChanged: (v) => app.setAiModel(_editing, v)),
      if (app.aiModelFor(_editing).trim().isEmpty)
        const Padding(
          padding: EdgeInsets.only(top: 4),
          child: Text('Type a model name to start using it.',
              style: TextStyle(fontSize: 11, color: OnoteColors.danger)),
        ),
      Row(
        children: [
          if (!inUse && app.aiModelFor(_editing).trim().isNotEmpty)
            TextButton.icon(
              icon: const Icon(Icons.play_circle_outline, size: 14),
              label: const Text('Use this provider',
                  style: TextStyle(fontSize: 12)),
              onPressed: () => app.setAiProvider(_editing),
            ),
          const Spacer(),
          TextButton.icon(
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
        ],
      ),
    ];
  }

  // The setup form: key + model + Connect (also used when replacing a key).
  List<Widget> _connectForm(BuildContext context, ColorScheme scheme) => [
        TextField(
          controller: _keyCtrl,
          obscureText: true,
          autofocus: true,
          style: const TextStyle(fontSize: 13),
          decoration: InputDecoration(
            isDense: true,
            labelText: '${_editing.label} API key',
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
              onPressed: () => PlatformOpen.url(_editing.keysPage),
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
              Text('Connected. ${_editing.label} accepted the key.',
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
          hintText: _editing.modelHint,
          border: const OutlineInputBorder(),
        ),
      );

  // Every AI feature's editable instruction, one per row. Each can be reset to
  // its built-in default or given custom text so behaviour differs across the
  // app. Only the persona is editable here — a generator's format rules are
  // always added by its own code, so this can never break a parser.
  List<Widget> _systemPrompts(BuildContext context) => [
        const Text('AI instructions',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        const SizedBox(height: 2),
        const Text(
          'How each AI feature behaves — its tone, subject or language. Reset '
          'any of these to normal, or write your own.',
          style: TextStyle(fontSize: 11.5, color: OnoteColors.graphite400),
        ),
        const SizedBox(height: 6),
        for (final f in AiFeature.values) _promptTile(context, f),
      ];

  Widget _promptTile(BuildContext context, AiFeature f) {
    final custom = app.aiPromptIsCustom(f);
    return Theme(
      // Drop the default divider lines ExpansionTile draws, so the list reads
      // as one block.
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(bottom: 8),
        dense: true,
        visualDensity: VisualDensity.compact,
        title: Row(
          children: [
            Expanded(
              child: Text(f.label,
                  style: const TextStyle(
                      fontSize: 12.5, fontWeight: FontWeight.w600)),
            ),
            if (custom)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: Theme.of(context)
                      .colorScheme
                      .primary
                      .withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text('Custom',
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.primary)),
              ),
          ],
        ),
        subtitle: Text(f.hint,
            style: const TextStyle(
                fontSize: 11, color: OnoteColors.graphite400, height: 1.3)),
        children: [
          TextField(
            controller: _prompts[f],
            minLines: 2,
            maxLines: 6,
            style: const TextStyle(fontSize: 12.5, height: 1.35),
            decoration: const InputDecoration(
              isDense: true,
              border: OutlineInputBorder(),
            ),
            onChanged: (v) => app.setSystemPrompt(f, v),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: custom
                  ? () {
                      app.resetSystemPrompt(f);
                      _prompts[f]!.text = f.defaultPrompt;
                    }
                  : null,
              child:
                  const Text('Reset to normal', style: TextStyle(fontSize: 12)),
            ),
          ),
        ],
      ),
    );
  }

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
