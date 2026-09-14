import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../ai/ai_prompts.dart';
import '../ai/ai_provider.dart';
import '../mindmap/mindmap_ai.dart';
import '../model/models.dart';
import '../quiz/quiz_ai.dart';
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
  // While an "insert as…" action is generating a block from an answer, so the
  // menu buttons disable and a thin progress line shows.
  bool _acting = false;
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

  // ── Doing something with an answer ──────────────────────────────────────

  void _toast(String message) {
    final m = ScaffoldMessenger.maybeOf(context);
    m?.showSnackBar(SnackBar(content: Text(message)));
  }

  void _copy(String text) {
    Clipboard.setData(ClipboardData(text: text));
    _toast('Answer copied.');
  }

  /// Turn an answer into a text summary block at the bottom of the page.
  Future<void> _insertSummary(String answer) async {
    final client = app.aiClient();
    if (client == null) return _toast('Connect an AI provider first.');
    setState(() => _acting = true);
    final res = await client.chat([
      AiMessage.system('${app.systemPromptFor(AiFeature.summary)}\n\n'
          'Summarise the text the user sends into a concise Markdown summary. '
          'Reply with only the summary.'),
      AiMessage.user(answer),
    ], temperature: 0.3);
    app.addAiTokens(res.totalTokens);
    if (!mounted) return;
    setState(() => _acting = false);
    if (!res.ok) return _toast(res.error ?? 'Could not summarise.');
    final at = app.spotBelowContent();
    final b = app.addBlock(Block(
      type: BlockType.text,
      x: at.dx,
      y: at.dy,
      w: 480,
      content: {'text': res.text.trim()},
    ));
    app.select(b.id);
    _toast('Summary added to the page.');
  }

  /// Turn an answer into a quiz block at the bottom of the page.
  Future<void> _insertQuiz(String answer) async {
    final client = app.aiClient();
    if (client == null) return _toast('Connect an AI provider first.');
    setState(() => _acting = true);
    final r = await generateQuiz(client,
        topic: answer,
        count: 5,
        systemPrompt: app.systemPromptFor(AiFeature.quiz));
    app.addAiTokens(r.tokens);
    if (!mounted) return;
    setState(() => _acting = false);
    if (!r.parse.isOk) {
      return _toast(r.parse.error ?? 'Could not build a quiz from that.');
    }
    final qs = r.parse.questions;
    final at = app.spotBelowContent();
    final b = app.addBlock(Block(
      type: BlockType.quiz,
      x: at.dx,
      y: at.dy,
      w: 420,
      content: {
        'name': 'Quiz',
        'questions': [for (final q in qs) q.toJson()],
        'answers': List<int>.filled(qs.length, -1),
        'revealed': List<bool>.filled(qs.length, false),
      },
    ));
    app.select(b.id);
    _toast(
        '${qs.length} question${qs.length == 1 ? '' : 's'} added as a quiz.');
  }

  /// Turn an answer into a mind map block at the bottom of the page.
  Future<void> _insertMindmap(String answer) async {
    final client = app.aiClient();
    if (client == null) return _toast('Connect an AI provider first.');
    setState(() => _acting = true);
    final res = await generateMindmapOutline(client,
        topic: answer, systemPrompt: app.systemPromptFor(AiFeature.mindmap));
    app.addAiTokens(res.tokens);
    if (!mounted) return;
    setState(() => _acting = false);
    if (!res.ok) return _toast(res.error ?? 'Could not build a mind map.');
    final root = mindmapFromOutline(res.markdown!);
    if (root == null) return _toast('The model did not return a usable map.');
    final at = app.spotBelowContent();
    final b = app.addBlock(Block(
      type: BlockType.mindmap,
      x: at.dx,
      y: at.dy,
      w: 360,
      content: {'root': root.toJson()},
    ));
    app.select(b.id);
    _toast('Mind map added to the page.');
  }

  /// The menu a right-click (or the ✨ button) opens on an answer.
  Future<void> _showAnswerMenu(String text, Offset globalPos) async {
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (overlay == null) return;
    final choice = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
          globalPos & const Size(1, 1), Offset.zero & overlay.size),
      items: const [
        PopupMenuItem(value: 'copy', child: Text('Copy')),
        PopupMenuItem(value: 'summary', child: Text('Insert as summary')),
        PopupMenuItem(value: 'quiz', child: Text('Insert as quiz')),
        PopupMenuItem(value: 'mindmap', child: Text('Insert as mind map')),
      ],
    );
    switch (choice) {
      case 'copy':
        _copy(text);
      case 'summary':
        await _insertSummary(text);
      case 'quiz':
        await _insertQuiz(text);
      case 'mindmap':
        await _insertMindmap(text);
    }
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
              if (_acting) const LinearProgressIndicator(minHeight: 2),
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
    // A real, finished answer gets a right-click menu and an action row.
    final isAnswer = turn != null && turn.role == 'assistant';
    final bubble = Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onSecondaryTapDown: isAnswer
            ? (d) => _showAnswerMenu(turn.text, d.globalPosition)
            : null,
        child: Container(
          margin: const EdgeInsets.only(top: 4),
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
      ),
    );
    if (!isAnswer) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: bubble,
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [bubble, _answerActions(context, turn.text)],
      ),
    );
  }

  /// Copy, and turn-into: summary / quiz / mind map, shown under each answer.
  Widget _answerActions(BuildContext context, String text) {
    Widget btn(IconData icon, String tip, VoidCallback? onTap) => IconButton(
          icon: Icon(icon, size: 15),
          tooltip: tip,
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.all(4),
          constraints: const BoxConstraints(),
          color: OnoteColors.graphite400,
          onPressed: _acting ? null : onTap,
        );
    return Padding(
      padding: const EdgeInsets.only(left: 2, top: 1),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          btn(Icons.copy, 'Copy', () => _copy(text)),
          btn(Icons.summarize_outlined, 'Insert as summary',
              () => _insertSummary(text)),
          btn(Icons.quiz_outlined, 'Insert as quiz', () => _insertQuiz(text)),
          btn(Icons.account_tree_outlined, 'Insert as mind map',
              () => _insertMindmap(text)),
        ],
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
