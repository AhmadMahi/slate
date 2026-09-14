import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../model/models.dart';
import '../quiz/quiz_ai.dart';
import '../quiz/quiz_import.dart';
import '../state/app_state.dart';
import 'onote_dialog.dart';

/// Insert a quiz: name it, hand out a template if wanted, upload a CSV or
/// Excel file, and drop the block on the page. The dialog does the reading and
/// validating; nothing lands on the page unless the file parsed cleanly.
Future<void> showQuizImportDialog(
    BuildContext context, AppState app, Offset at) async {
  final draft = await showOnoteDialog<_QuizDraft>(
    context: context,
    builder: (_) => QuizImportDialog(app: app),
  );
  if (draft == null) return;
  final b = app.addBlock(Block(
    type: BlockType.quiz,
    x: at.dx,
    y: at.dy,
    w: 420,
    content: {
      'name': draft.name,
      'questions': [for (final q in draft.questions) q.toJson()],
      'answers': List<int>.filled(draft.questions.length, -1),
      'revealed': List<bool>.filled(draft.questions.length, false),
    },
  ));
  app.select(b.id);
}

class _QuizDraft {
  const _QuizDraft(this.name, this.questions);
  final String name;
  final List<QuizQuestion> questions;
}

class QuizImportDialog extends StatefulWidget {
  const QuizImportDialog({super.key, required this.app});
  final AppState app;

  @override
  State<QuizImportDialog> createState() => _QuizImportDialogState();
}

class _QuizImportDialogState extends State<QuizImportDialog> {
  final _name = TextEditingController(text: 'Quiz');
  final _paste = TextEditingController();
  final _topic = TextEditingController();
  final _count = TextEditingController(text: '5');
  bool _generating = false;
  List<QuizQuestion>? _questions;
  String? _error;
  String? _status;

  @override
  void dispose() {
    _name.dispose();
    _paste.dispose();
    _topic.dispose();
    _count.dispose();
    super.dispose();
  }

  Future<void> _generate() async {
    final client = widget.app.aiClient();
    if (client == null) {
      setState(() {
        _error = 'Connect an AI provider first: Settings → Connections → '
            'AI provider.';
        _questions = null;
        _status = null;
      });
      return;
    }
    final topic = _topic.text.trim();
    if (topic.isEmpty) {
      setState(() {
        _error = 'Type a topic to generate questions from.';
        _questions = null;
        _status = null;
      });
      return;
    }
    final count =
        (int.tryParse(_count.text.trim()) ?? 5).clamp(1, kMaxQuizQuestions);
    setState(() {
      _generating = true;
      _error = null;
      _status = 'Thinking…';
      _questions = null;
    });
    final r = await generateQuiz(client, topic: topic, count: count);
    widget.app.addAiTokens(r.tokens);
    if (!mounted) return;
    setState(() {
      _generating = false;
      if (r.parse.isOk) {
        _questions = r.parse.questions;
        _error = null;
        _status = '${r.parse.questions.length} '
            'question${r.parse.questions.length == 1 ? '' : 's'} generated';
        // Name the quiz after the topic if it is still the placeholder.
        if (_name.text.trim().isEmpty || _name.text.trim() == 'Quiz') {
          _name.text =
              topic.length > 40 ? topic.substring(0, 40).trim() : topic;
        }
      } else {
        _questions = null;
        _status = null;
        _error = r.parse.error;
      }
    });
  }

  void _loadPaste() {
    final text = _paste.text;
    if (text.trim().isEmpty) {
      setState(() {
        _error = 'Paste some rows first.';
        _questions = null;
        _status = null;
      });
      return;
    }
    final res = parseQuizText(text);
    setState(() {
      if (res.isOk) {
        _questions = res.questions;
        _error = null;
        _status = '${res.questions.length} '
            'question${res.questions.length == 1 ? '' : 's'} read from the '
            'pasted text';
      } else {
        _questions = null;
        _status = null;
        _error = res.error;
      }
    });
  }

  Future<void> _pickFile() async {
    XFile? file;
    try {
      file = await openFile(acceptedTypeGroups: const [
        XTypeGroup(label: 'Quiz', extensions: ['csv', 'tsv', 'xlsx'])
      ]);
    } catch (e) {
      setState(() => _error = "Couldn't open the file picker: $e");
      return;
    }
    if (file == null) return;
    final Uint8List bytes = await file.readAsBytes();
    final res = parseQuizFile(file.name, bytes);
    if (!mounted) return;
    setState(() {
      if (res.isOk) {
        _questions = res.questions;
        _error = null;
        _status = '${res.questions.length} '
            'question${res.questions.length == 1 ? '' : 's'} loaded from '
            '${file!.name}';
        // Name the quiz after the file if it is still the placeholder.
        if (_name.text.trim().isEmpty || _name.text.trim() == 'Quiz') {
          final base = file.name.replaceAll(RegExp(r'\.[^.]+$'), '').trim();
          if (base.isNotEmpty) _name.text = base;
        }
      } else {
        _questions = null;
        _status = null;
        _error = res.error;
      }
    });
  }

  Future<void> _downloadTemplate() async {
    final loc = await getSaveLocation(
      suggestedName: 'quiz-template.csv',
      acceptedTypeGroups: const [
        XTypeGroup(label: 'CSV', extensions: ['csv'])
      ],
    );
    if (loc == null) return;
    try {
      await File(loc.path).writeAsString(quizTemplateCsv());
      if (mounted) {
        setState(
            () => _status = 'Template saved. Fill it in, then upload it here.');
      }
    } catch (e) {
      if (mounted) setState(() => _error = "Couldn't save the template: $e");
    }
  }

  void _create() {
    final qs = _questions;
    if (qs == null || qs.isEmpty) return;
    final name = _name.text.trim().isEmpty ? 'Quiz' : _name.text.trim();
    Navigator.of(context).pop(_QuizDraft(name, qs));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ready = _questions != null && _questions!.isNotEmpty;
    return AlertDialog(
      title: const Text('Create a quiz'),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Upload a CSV or Excel file: one row per question, with the '
              'question, four options, the correct answer (1-4, A-D or the '
              'exact text), and an optional explanation. One to 20 questions.',
              style: TextStyle(fontSize: 12.5, height: 1.4),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _name,
              decoration: const InputDecoration(
                labelText: 'Quiz name',
                hintText: 'Chapter 3 review',
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: _downloadTemplate,
                  icon: const Icon(Icons.download_outlined, size: 18),
                  label: const Text('Download template'),
                ),
                const SizedBox(width: 10),
                FilledButton.icon(
                  onPressed: _pickFile,
                  icon: const Icon(Icons.upload_file_outlined, size: 18),
                  label: Text(ready ? 'Choose another file' : 'Upload file'),
                ),
              ],
            ),
            const SizedBox(height: 14),
            const Text('Or paste rows',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            TextField(
              controller: _paste,
              minLines: 3,
              maxLines: 6,
              style: const TextStyle(fontSize: 12, height: 1.35),
              decoration: const InputDecoration(
                isDense: true,
                border: OutlineInputBorder(),
                hintText: 'question, option 1, option 2, option 3, option 4, '
                    'correct answer, explanation',
              ),
            ),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: _loadPaste,
                icon: const Icon(Icons.playlist_add_check, size: 18),
                label: const Text('Use pasted questions'),
              ),
            ),
            const SizedBox(height: 14),
            const Row(
              children: [
                Icon(Icons.auto_awesome_outlined, size: 15),
                SizedBox(width: 6),
                Text('Or auto generate with AI',
                    style:
                        TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _topic,
              minLines: 2,
              maxLines: 3,
              style: const TextStyle(fontSize: 12, height: 1.35),
              decoration: const InputDecoration(
                isDense: true,
                border: OutlineInputBorder(),
                hintText: 'What should the quiz be about? '
                    'e.g. photosynthesis for grade 8',
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                SizedBox(
                  width: 88,
                  child: TextField(
                    controller: _count,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(fontSize: 12),
                    decoration: const InputDecoration(
                      isDense: true,
                      border: OutlineInputBorder(),
                      labelText: 'How many',
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                FilledButton.tonalIcon(
                  onPressed: _generating ? null : _generate,
                  icon: _generating
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.auto_awesome, size: 18),
                  label: Text(_generating ? 'Thinking…' : 'Generate with AI'),
                ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.error_outline, size: 16, color: scheme.error),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(_error!,
                        style: TextStyle(fontSize: 12.5, color: scheme.error)),
                  ),
                ],
              ),
            ],
            if (_status != null && _error == null) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(Icons.check_circle_outline,
                      size: 16, color: scheme.primary),
                  const SizedBox(width: 6),
                  Expanded(
                    child:
                        Text(_status!, style: const TextStyle(fontSize: 12.5)),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: ready ? _create : null,
          child: const Text('Create quiz'),
        ),
      ],
    );
  }
}
