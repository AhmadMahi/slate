/// **A multiple-choice quiz, built from a CSV or Excel file.**
///
/// One row is one question: the prompt, four options, which option is right,
/// and one line of explanation shown after the reader answers. The correct
/// answer may be written as a number (1-4), a letter (A-D) or the exact text
/// of the right option, because a spreadsheet filled in by hand will use
/// whichever the author finds natural.
///
/// The file rules live here, once, so the import dialog, the template it hands
/// out, and the tests all agree on the shape of a quiz.
library;

import 'dart:convert';
import 'dart:typed_data';

import '../export/csv_import.dart';
import '../export/xlsx_import.dart';

/// A quiz has at least this many questions and at most this many. The ceiling
/// is the owner's: a quiz in a note is a quick check, not an exam.
const int kMinQuizQuestions = 1;
const int kMaxQuizQuestions = 20;

/// Exactly four options, always — the reader's four choices.
const int kQuizOptionCount = 4;

/// One question: the prompt, its four options, the index (0-3) of the right
/// one, and a line of explanation (may be empty).
class QuizQuestion {
  const QuizQuestion({
    required this.prompt,
    required this.options,
    required this.correct,
    this.explanation = '',
  });

  final String prompt;
  final List<String> options; // always length kQuizOptionCount
  final int correct; // 0-based index into options
  final String explanation;

  Map<String, dynamic> toJson() => {
        'q': prompt,
        'options': options,
        'correct': correct,
        if (explanation.isNotEmpty) 'explanation': explanation,
      };

  static QuizQuestion fromJson(Map<String, dynamic> j) {
    final opts = [
      for (final o in (j['options'] as List? ?? const [])) o.toString(),
    ];
    while (opts.length < kQuizOptionCount) {
      opts.add('');
    }
    return QuizQuestion(
      prompt: (j['q'] ?? '').toString(),
      options: opts.take(kQuizOptionCount).toList(),
      correct: (j['correct'] as num?)?.toInt() ?? 0,
      explanation: (j['explanation'] ?? '').toString(),
    );
  }
}

/// The outcome of reading a file: the questions, or the first thing wrong with
/// it, said plainly enough to fix in the spreadsheet. Never both.
class QuizParseResult {
  const QuizParseResult.ok(this.questions) : error = null;
  const QuizParseResult.fail(this.error) : questions = const [];

  final List<QuizQuestion> questions;
  final String? error;

  bool get isOk => error == null;
}

/// True when a row reads like a header rather than a question — its first cell
/// is the word "question" (possibly "question text" and the like). A file with
/// a header and one without both work; this is the only difference.
bool _looksLikeHeader(List<String> row) {
  if (row.isEmpty) return false;
  final first = row.first.trim().toLowerCase();
  return first == 'question' ||
      first == 'questions' ||
      first.startsWith('question ') ||
      first.startsWith('question text');
}

bool _rowIsEmpty(List<String> row) => row.every((c) => c.trim().isEmpty);

/// Resolve the "correct answer" cell to a 0-based option index, accepting a
/// number (1-4), a letter (A-D) or the exact text of one of [options].
/// Returns null when it names none of them.
int? _resolveCorrect(String raw, List<String> options) {
  final s = raw.trim();
  if (s.isEmpty) return null;
  // The exact text of an option wins FIRST, so an answer that IS one of the
  // options — including a numeric one like "42" when the options are numbers —
  // is never mistaken for an option number or a letter.
  final lower = s.toLowerCase();
  for (var i = 0; i < options.length; i++) {
    if (options[i].trim().toLowerCase() == lower) return i;
  }
  // Otherwise a number 1-4 names the option by position.
  final n = int.tryParse(s);
  if (n != null) return (n >= 1 && n <= options.length) ? n - 1 : null;
  // Or a single letter A-D (or a-d).
  if (s.length == 1) {
    final code = s.toUpperCase().codeUnitAt(0) - 'A'.codeUnitAt(0);
    if (code >= 0 && code < options.length) return code;
  }
  return null;
}

/// Parse already-tabular cells (from [parseCsv] or [readXlsxRows]) into a
/// quiz. The columns, in order, are:
///
///   question, option 1, option 2, option 3, option 4, correct, explanation
///
/// The explanation column is optional. A header row is detected and skipped.
QuizParseResult parseQuizRows(List<List<String>> rows) {
  final questions = <QuizQuestion>[];
  var rowNo = 0;
  var sawHeader = false;
  for (final raw in rows) {
    rowNo++;
    final row = List<String>.from(raw);
    if (_rowIsEmpty(row)) continue;
    if (rowNo == 1 && _looksLikeHeader(row)) {
      sawHeader = true;
      continue;
    }
    // question + 4 options + correct = 6 columns at least.
    const needed = 2 + kQuizOptionCount;
    if (row.length < needed) {
      return QuizParseResult.fail(
          'Row $rowNo has ${row.length} columns; a question needs at least '
          '$needed (the question, four options and the correct answer).');
    }
    final prompt = row[0].trim();
    if (prompt.isEmpty) {
      return QuizParseResult.fail('Row $rowNo has no question text.');
    }
    final options = [for (var i = 1; i <= kQuizOptionCount; i++) row[i].trim()];
    if (options.any((o) => o.isEmpty)) {
      return QuizParseResult.fail(
          'Row $rowNo is missing one of its four options.');
    }
    final correct = _resolveCorrect(row[1 + kQuizOptionCount], options);
    if (correct == null) {
      return QuizParseResult.fail(
          'Row $rowNo does not say which option is correct. Use 1-4, A-D, or '
          'the exact text of the right option.');
    }
    final explanation = row.length > needed ? row[needed].trim() : '';
    questions.add(QuizQuestion(
      prompt: prompt,
      options: options,
      correct: correct,
      explanation: explanation,
    ));
    if (questions.length > kMaxQuizQuestions) {
      return const QuizParseResult.fail(
          'A quiz can have at most $kMaxQuizQuestions questions; this file has '
          'more. Trim it and try again.');
    }
  }
  if (questions.isEmpty) {
    return QuizParseResult.fail(sawHeader
        ? 'The file has a header but no questions under it.'
        : 'No questions found in the file.');
  }
  return QuizParseResult.ok(questions);
}

/// Read pasted text into a quiz. The same columns as a file, sniffing whether
/// the paste is tab-separated (straight from a spreadsheet) or comma-separated
/// (an LLM told to write CSV), so either just works.
QuizParseResult parseQuizText(String text) {
  final firstLine = const LineSplitter()
      .convert(text)
      .firstWhere((l) => l.trim().isNotEmpty, orElse: () => '');
  final tabs = firstLine.split('\t').length - 1;
  final commas = firstLine.split(',').length - 1;
  final delimiter = tabs > commas ? '\t' : null; // null = comma (the default)
  return parseQuizRows(parseCsv(text, delimiter: delimiter));
}

/// Read a picked file (by name and bytes) into a quiz: `.xlsx` through the
/// minimal reader, everything else as CSV (tab-separated when it ends `.tsv`).
/// One entry point so the dialog and the tests accept exactly the same files.
QuizParseResult parseQuizFile(String name, Uint8List bytes) {
  final lower = name.toLowerCase();
  if (lower.endsWith('.xlsx')) {
    final rows = readXlsxRows(bytes);
    if (rows == null) {
      return const QuizParseResult.fail("That .xlsx file couldn't be read.");
    }
    return parseQuizRows(rows);
  }
  final text = utf8.decode(bytes, allowMalformed: true);
  return parseQuizRows(
      parseCsv(text, delimiter: lower.endsWith('.tsv') ? '\t' : null));
}

/// A ready-to-fill sample file, handed out by the import dialog so the author
/// starts from the right shape rather than guessing at it.
String quizTemplateCsv() {
  const rows = [
    'question,option 1,option 2,option 3,option 4,correct answer,explanation',
    '"What is the capital of France?",Paris,London,Berlin,Madrid,1,'
        '"Paris has been France\'s capital since 987."',
    '"Which is a prime number?",9,15,17,21,C,'
        '"17 has no divisors other than 1 and itself."',
    '"Water boils at what temperature at sea level?","50 C","90 C","100 C",'
        '"150 C","100 C","At 1 atm, water boils at 100 degrees Celsius."',
  ];
  return '${rows.join('\n')}\n';
}
