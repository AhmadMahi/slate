import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../ai/ai_provider.dart';
import '../state/app_state.dart';
import '../theme/onote_theme.dart';
import '../theme/tokens.dart';
import 'ai_provider_dialog.dart';

/// A small translucent chat that floats at the bottom-right of the page, for
/// quick questions while teaching. Off by default (Settings → Connections →
/// Ask AI), and it uses the same provider the rest of the AI features do.
///
/// Self-contained: it owns its open/closed state and its short conversation,
/// so the canvas only has to place it. The history is kept in memory for this
/// session only — nothing is written to a notebook.
class AskAiPanel extends StatefulWidget {
  const AskAiPanel({super.key, required this.app});
  final AppState app;

  @override
  State<AskAiPanel> createState() => _AskAiPanelState();
}

class _Turn {
  _Turn(this.role, this.text);
  final String role; // 'user' | 'assistant' | 'note'
  final String text;
}

class _AskAiPanelState extends State<AskAiPanel> {
  AppState get app => widget.app;

  bool _open = false;
  bool _sending = false;
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _turns = <_Turn>[];

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _toEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
      }
    });
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    final client = app.aiClient();
    if (client == null) {
      setState(() => _turns.add(_Turn(
          'note',
          'Connect an AI provider to use Ask AI: Settings → Connections → '
              'AI provider.')));
      _toEnd();
      return;
    }
    setState(() {
      _turns.add(_Turn('user', text));
      _input.clear();
      _sending = true;
    });
    _toEnd();
    final history = <AiMessage>[
      AiMessage.system(app.askAiSystemPrompt),
      for (final t in _turns)
        if (t.role == 'user' || t.role == 'assistant')
          AiMessage(t.role, t.text),
    ];
    final res = await client.chat(history);
    app.addAiTokens(res.totalTokens);
    if (!mounted) return;
    setState(() {
      _sending = false;
      _turns.add(res.ok
          ? _Turn('assistant', res.text)
          : _Turn('note', res.error ?? 'Something went wrong.'));
    });
    _toEnd();
  }

  @override
  Widget build(BuildContext context) {
    return _open ? _panel(context) : _bubble(context);
  }

  Widget _bubble(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: 'Ask AI',
      child: Material(
        color: scheme.primary.withValues(alpha: 0.92),
        shape: const CircleBorder(),
        elevation: 3,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () => setState(() => _open = true),
          child: SizedBox(
            width: 46,
            height: 46,
            child: Icon(Icons.auto_awesome, color: scheme.onPrimary, size: 22),
          ),
        ),
      ),
    );
  }

  Widget _panel(BuildContext context) {
    final s = context.surfaces;
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return ClipRRect(
      borderRadius: OnoteRadius.lgAll,
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          width: 340,
          height: 440,
          decoration: BoxDecoration(
            color: s.raised.withValues(alpha: dark ? 0.82 : 0.86),
            borderRadius: OnoteRadius.lgAll,
            border: Border.all(color: s.border),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: dark ? 0.35 : 0.12),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            children: [
              _header(context, scheme, s),
              Expanded(child: _messages(context, scheme, s)),
              _composer(context, scheme, s),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext context, ColorScheme scheme, OnoteSurfaces s) =>
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 6, 4),
        child: Row(
          children: [
            Icon(Icons.auto_awesome, size: 16, color: scheme.primary),
            const SizedBox(width: 6),
            const Expanded(
              child: Text('Ask AI',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            ),
            if (_turns.isNotEmpty)
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 16),
                tooltip: 'Clear',
                visualDensity: VisualDensity.compact,
                onPressed: () => setState(_turns.clear),
              ),
            IconButton(
              icon: const Icon(Icons.close, size: 18),
              tooltip: 'Hide',
              visualDensity: VisualDensity.compact,
              onPressed: () => setState(() => _open = false),
            ),
          ],
        ),
      );

  Widget _messages(BuildContext context, ColorScheme scheme, OnoteSurfaces s) {
    if (_turns.isEmpty && !app.aiConnected) {
      return _empty(
        context,
        'Ask AI is not connected yet.',
        action: TextButton(
          onPressed: () => showAiProviderDialog(context, app),
          child: const Text('Connect a provider'),
        ),
      );
    }
    if (_turns.isEmpty) {
      return _empty(context, 'Ask a quick question. Answers are not saved.');
    }
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      itemCount: _turns.length + (_sending ? 1 : 0),
      itemBuilder: (context, i) {
        if (i == _turns.length) return _bubbleRow(context, scheme, s, null);
        return _bubbleRow(context, scheme, s, _turns[i]);
      },
    );
  }

  Widget _empty(BuildContext context, String text, {Widget? action}) => Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(text,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 12.5, color: OnoteColors.graphite400)),
              if (action != null) ...[const SizedBox(height: 6), action],
            ],
          ),
        ),
      );

  // A null turn is the "typing…" placeholder shown while a reply is in flight.
  Widget _bubbleRow(
      BuildContext context, ColorScheme scheme, OnoteSurfaces s, _Turn? turn) {
    if (turn?.role == 'note') {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        child: Text(turn!.text,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 11.5, color: OnoteColors.danger)),
      );
    }
    final isUser = turn?.role == 'user';
    final bg = isUser ? scheme.primary : s.well;
    final fg = isUser ? scheme.onPrimary : s.textPrimary;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        constraints: const BoxConstraints(maxWidth: 250),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
          border: isUser ? null : Border.all(color: s.border),
        ),
        child: turn == null
            ? SizedBox(
                width: 34,
                child: Text('…',
                    style: TextStyle(fontSize: 16, color: s.textSecondary)),
              )
            : SelectableText(turn.text,
                style: TextStyle(fontSize: 12.5, height: 1.35, color: fg)),
      ),
    );
  }

  Widget _composer(BuildContext context, ColorScheme scheme, OnoteSurfaces s) =>
      Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: _input,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _send(),
                style: const TextStyle(fontSize: 12.5),
                decoration: const InputDecoration(
                  isDense: true,
                  border: OutlineInputBorder(),
                  hintText: 'Ask a question…',
                ),
              ),
            ),
            const SizedBox(width: 6),
            _sending
                ? const Padding(
                    padding: EdgeInsets.all(8),
                    child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2)),
                  )
                : IconButton(
                    icon: Icon(Icons.send, color: scheme.primary),
                    tooltip: 'Send',
                    onPressed: _send,
                  ),
          ],
        ),
      );
}
