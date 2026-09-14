/// Generating a quiz from a topic with a cloud model.
///
/// The model is asked for a single JSON object in a fixed shape; the reply is
/// then folded back through the very same [parseQuizRows] validator the file
/// and paste paths use, so an AI-made quiz has to clear exactly the same bar
/// (four options each, a resolvable correct answer, 1-20 questions) before it
/// can land on the page. Nothing here trusts the model's structure blindly.
library;

import 'dart:convert';

import '../ai/ai_provider.dart';
import 'quiz_import.dart';

/// The house rules handed to the model, kept deterministic so the reply parses.
String quizSystemPrompt() =>
    'You write multiple-choice quizzes. Reply with ONE JSON object and nothing '
    'else, in exactly this shape:\n'
    '{"questions":[{"question":"...","options":["...","...","...","..."],'
    '"correct":1,"explanation":"..."}]}\n'
    'Rules: every question has exactly four options. "correct" is the 1-based '
    'position (1, 2, 3 or 4) of the right option. "explanation" is one short '
    'sentence saying why. Keep questions and options concise. Do not wrap the '
    'JSON in markdown fences or add any commentary.';

/// Build the user turn from what the teacher typed and how many they want.
String quizUserPrompt(String topic, int count) {
  final n = count.clamp(kMinQuizQuestions, kMaxQuizQuestions);
  return 'Write $n multiple-choice question${n == 1 ? '' : 's'} about:\n'
      '$topic';
}

/// Turn the model's JSON reply into questions, via the shared validator.
///
/// Tolerant of the two shapes a model tends to produce — a top-level
/// `{"questions":[…]}` object or a bare `[…]` array — and of a stray markdown
/// fence around it, but not of a wrong question shape: that goes through
/// [parseQuizRows] and comes back as the same plain error the other paths give.
QuizParseResult parseQuizJson(String reply) {
  final text = _stripFence(reply).trim();
  if (text.isEmpty) {
    return const QuizParseResult.fail('The model returned nothing to read.');
  }
  Object? decoded;
  try {
    decoded = jsonDecode(text);
  } on FormatException {
    return const QuizParseResult.fail(
        'The model did not return readable JSON. Try again, or rephrase the '
        'topic.');
  }
  final list = decoded is Map ? decoded['questions'] : decoded;
  if (list is! List || list.isEmpty) {
    return const QuizParseResult.fail(
        'The model did not return any questions. Try again.');
  }
  final rows = <List<String>>[];
  for (final item in list) {
    if (item is! Map) continue;
    final q = (item['question'] ?? item['q'] ?? '').toString().trim();
    final opts = item['options'] ?? item['choices'];
    final options = <String>[
      if (opts is List)
        for (final o in opts) o.toString().trim(),
    ];
    // "correct" may arrive as a 1-4 number, a letter, or the option's text —
    // all three of which _resolveCorrect (via parseQuizRows) already handles.
    final correct = (item['correct'] ?? item['answer'] ?? '').toString().trim();
    final expl = (item['explanation'] ?? item['why'] ?? '').toString().trim();
    while (options.length < kQuizOptionCount) {
      options.add('');
    }
    rows.add([
      q,
      ...options.take(kQuizOptionCount),
      correct,
      expl,
    ]);
  }
  return parseQuizRows(rows);
}

/// The whole round trip: ask the model, count the tokens, return questions.
class QuizAiResult {
  const QuizAiResult(this.parse, this.tokens);
  final QuizParseResult parse;
  final int tokens;
}

Future<QuizAiResult> generateQuiz(
  AiClient client, {
  required String topic,
  required int count,
}) async {
  final res = await client.chat(
    [
      AiMessage.system(quizSystemPrompt()),
      AiMessage.user(quizUserPrompt(topic, count)),
    ],
    temperature: 0.4,
    jsonObject: true,
  );
  if (!res.ok) {
    return QuizAiResult(QuizParseResult.fail(res.error!), 0);
  }
  return QuizAiResult(parseQuizJson(res.text), res.totalTokens);
}

/// Drop a ```json … ``` fence if the model added one despite being asked not to.
String _stripFence(String s) {
  var t = s.trim();
  if (!t.startsWith('```')) return t;
  t = t.replaceFirst(RegExp(r'^```[a-zA-Z]*\s*'), '');
  final end = t.lastIndexOf('```');
  if (end != -1) t = t.substring(0, end);
  return t.trim();
}
