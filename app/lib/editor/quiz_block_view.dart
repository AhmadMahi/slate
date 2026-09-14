import 'package:flutter/material.dart';

import '../model/models.dart';
import '../quiz/quiz_import.dart';
import '../state/app_state.dart';
import '../theme/tokens.dart';

/// A multiple-choice quiz living on the page.
///
/// content: `{ name, questions:[{q,options,correct,explanation}], answers:[..],
/// revealed:[..] }`
///
/// One question at a time: its four options, a Submit that checks that
/// question and reveals the answer (green for right, red for the wrong pick)
/// with the one-line explanation, then Next. The last question leads to a
/// results card with the score and a Retake. The chosen answers and which
/// questions have been checked live in the block, so closing and reopening the
/// page keeps the reader where they were.
///
/// The questions come from a CSV or Excel file (see `quiz_import.dart`); this
/// view never edits them, it only asks and marks them.
class QuizBlockView extends StatefulWidget {
  const QuizBlockView({super.key, required this.block, required this.app});
  final Block block;
  final AppState app;

  @override
  State<QuizBlockView> createState() => _QuizBlockViewState();
}

class _QuizBlockViewState extends State<QuizBlockView> {
  int _current = 0;
  bool _showResults = false;

  Map<String, dynamic> get _c => widget.block.content;

  String get _name => (_c['name'] ?? 'Quiz').toString();

  List<QuizQuestion> get _questions => [
        for (final q in (_c['questions'] as List? ?? const []))
          QuizQuestion.fromJson((q as Map).cast<String, dynamic>()),
      ];

  // Per-question state, stored on the block so it survives a reopen.
  List<int> get _answers {
    final n = _questions.length;
    final raw = (_c['answers'] as List?) ?? const [];
    return [
      for (var i = 0; i < n; i++)
        i < raw.length ? (raw[i] as num?)?.toInt() ?? -1 : -1,
    ];
  }

  List<bool> get _revealed {
    final n = _questions.length;
    final raw = (_c['revealed'] as List?) ?? const [];
    return [
      for (var i = 0; i < n; i++) i < raw.length && raw[i] == true,
    ];
  }

  void _save(List<int> answers, List<bool> revealed) {
    _c['answers'] = answers;
    _c['revealed'] = revealed;
    widget.block.updatedAt = nowMs();
    widget.app.updateBlock(widget.block);
  }

  void _choose(int option) {
    final answers = _answers;
    if (_revealed[_current]) return; // locked once checked
    setState(() => answers[_current] = option);
    _save(answers, _revealed);
  }

  void _submit() {
    final revealed = _revealed;
    revealed[_current] = true;
    setState(() {});
    _save(_answers, revealed);
  }

  void _retake() {
    final n = _questions.length;
    setState(() {
      _current = 0;
      _showResults = false;
    });
    _save(List<int>.filled(n, -1), List<bool>.filled(n, false));
  }

  int get _score {
    final qs = _questions;
    final ans = _answers;
    var s = 0;
    for (var i = 0; i < qs.length; i++) {
      if (ans[i] == qs[i].correct) s++;
    }
    return s;
  }

  @override
  Widget build(BuildContext context) {
    final s = context.surfaces;
    final questions = _questions;
    if (questions.isEmpty) {
      return _shell(
        s,
        Padding(
          padding: const EdgeInsets.all(OnoteSpace.x4),
          child: Text('This quiz has no questions.',
              style: TextStyle(color: s.textSecondary)),
        ),
      );
    }
    return _shell(
        s, _showResults ? _results(context, s) : _questionCard(context, s));
  }

  /// The card the quiz sits in: name at the top, body below.
  Widget _shell(OnoteSurfaces s, Widget body) {
    return Container(
      decoration: BoxDecoration(
        color: s.raised,
        borderRadius: OnoteRadius.lgAll,
        border: Border.all(color: s.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: OnoteSpace.x4, vertical: OnoteSpace.x3),
            color: s.well,
            child: Row(
              children: [
                Icon(Icons.quiz_outlined, size: 18, color: s.textSecondary),
                const SizedBox(width: OnoteSpace.x2),
                Expanded(
                  child: Text(_name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: OnoteType.title.copyWith(color: s.textPrimary)),
                ),
              ],
            ),
          ),
          Flexible(child: body),
        ],
      ),
    );
  }

  Widget _questionCard(BuildContext context, OnoteSurfaces s) {
    final questions = _questions;
    final q = questions[_current];
    final answers = _answers;
    final revealed = _revealed[_current];
    final chosen = answers[_current];
    final isLast = _current == questions.length - 1;

    return Padding(
      padding: const EdgeInsets.all(OnoteSpace.x4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Question ${_current + 1} of ${questions.length}',
              style: OnoteType.caption.copyWith(color: s.textSecondary)),
          const SizedBox(height: OnoteSpace.x2),
          Text(q.prompt,
              style: OnoteType.uiStrong
                  .copyWith(color: s.textPrimary, fontWeight: FontWeight.w600)),
          const SizedBox(height: OnoteSpace.x3),
          for (var i = 0; i < q.options.length; i++)
            _option(context, s, q, i, chosen, revealed),
          if (revealed && q.explanation.isNotEmpty) ...[
            const SizedBox(height: OnoteSpace.x3),
            Container(
              padding: const EdgeInsets.all(OnoteSpace.x3),
              decoration: BoxDecoration(
                color: s.well,
                borderRadius: OnoteRadius.mdAll,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline, size: 16, color: s.textSecondary),
                  const SizedBox(width: OnoteSpace.x2),
                  Expanded(
                    child: Text(q.explanation,
                        style: OnoteType.ui.copyWith(color: s.textSecondary)),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: OnoteSpace.x4),
          Row(
            children: [
              TextButton.icon(
                onPressed:
                    _current > 0 ? () => setState(() => _current--) : null,
                icon: const Icon(Icons.chevron_left, size: 18),
                label: const Text('Back'),
              ),
              const Spacer(),
              if (!revealed)
                FilledButton(
                  onPressed: chosen >= 0 ? _submit : null,
                  child: const Text('Submit'),
                )
              else if (isLast)
                FilledButton.icon(
                  onPressed: () => setState(() => _showResults = true),
                  icon: const Icon(Icons.flag_outlined, size: 18),
                  label: const Text('See results'),
                )
              else
                FilledButton.icon(
                  onPressed: () => setState(() => _current++),
                  icon: const Icon(Icons.chevron_right, size: 18),
                  label: const Text('Next'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  /// One answer row. Plain and tappable before the check; after it, the right
  /// option turns green and a wrong pick turns red.
  Widget _option(BuildContext context, OnoteSurfaces s, QuizQuestion q, int i,
      int chosen, bool revealed) {
    final scheme = Theme.of(context).colorScheme;
    final isChosen = chosen == i;
    final isCorrect = q.correct == i;

    Color bg = Colors.transparent;
    Color border = s.border;
    Color fg = s.textPrimary;
    IconData? mark;
    Color markColor = s.textSecondary;

    if (!revealed) {
      if (isChosen) {
        bg = scheme.primary.withValues(alpha: .12);
        border = scheme.primary;
      }
      mark =
          isChosen ? Icons.radio_button_checked : Icons.radio_button_unchecked;
      markColor = isChosen ? scheme.primary : s.textSecondary;
    } else {
      if (isCorrect) {
        bg = _green.withValues(alpha: .15);
        border = _green;
        markColor = _green;
        mark = Icons.check_circle;
      } else if (isChosen) {
        bg = _red.withValues(alpha: .15);
        border = _red;
        markColor = _red;
        mark = Icons.cancel;
      } else {
        mark = Icons.radio_button_unchecked;
      }
    }

    final letter = String.fromCharCode('A'.codeUnitAt(0) + i);
    return Padding(
      padding: const EdgeInsets.only(bottom: OnoteSpace.x2),
      child: InkWell(
        borderRadius: OnoteRadius.mdAll,
        onTap: revealed ? null : () => _choose(i),
        child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: OnoteSpace.x3, vertical: OnoteSpace.x3),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: OnoteRadius.mdAll,
            border: Border.all(color: border),
          ),
          child: Row(
            children: [
              Icon(mark, size: 18, color: markColor),
              const SizedBox(width: OnoteSpace.x3),
              Text('$letter.  ',
                  style: OnoteType.ui.copyWith(
                      color: s.textSecondary, fontWeight: FontWeight.w600)),
              Expanded(
                child:
                    Text(q.options[i], style: OnoteType.ui.copyWith(color: fg)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _results(BuildContext context, OnoteSurfaces s) {
    final questions = _questions;
    final score = _score;
    final total = questions.length;
    final answers = _answers;
    return Padding(
      padding: const EdgeInsets.all(OnoteSpace.x4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Your score',
              style: OnoteType.caption.copyWith(color: s.textSecondary)),
          const SizedBox(height: OnoteSpace.x1),
          Text('$score / $total',
              style: OnoteType.headline
                  .copyWith(color: score * 2 >= total ? _green : _red)),
          const SizedBox(height: OnoteSpace.x3),
          Wrap(
            spacing: OnoteSpace.x2,
            runSpacing: OnoteSpace.x2,
            children: [
              for (var i = 0; i < total; i++)
                GestureDetector(
                  onTap: () => setState(() {
                    _current = i;
                    _showResults = false;
                  }),
                  child: Container(
                    width: 28,
                    height: 28,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color:
                          (answers[i] == questions[i].correct ? _green : _red)
                              .withValues(alpha: .15),
                      borderRadius: OnoteRadius.smAll,
                      border: Border.all(
                          color: answers[i] == questions[i].correct
                              ? _green
                              : _red),
                    ),
                    child: Text('${i + 1}',
                        style: OnoteType.caption.copyWith(
                            color: answers[i] == questions[i].correct
                                ? _green
                                : _red)),
                  ),
                ),
            ],
          ),
          const SizedBox(height: OnoteSpace.x4),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: _retake,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Retake'),
            ),
          ),
        ],
      ),
    );
  }

  // Readable in both themes: the tint carries the meaning, over a faint fill.
  static const _green = Color(0xFF2E9E5B);
  static const _red = Color(0xFFE5484D);
}
