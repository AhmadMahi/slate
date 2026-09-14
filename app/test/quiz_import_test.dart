// The quiz importer: a CSV or Excel file of questions, validated into a quiz.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:openote/quiz/quiz_import.dart';

void main() {
  QuizParseResult rows(List<List<String>> r) => parseQuizRows(r);

  group('a well-formed file', () {
    test('reads question, options, correct and explanation', () {
      final r = rows([
        ['question', 'a', 'b', 'c', 'd', 'correct', 'explanation'],
        ['2+2?', '3', '4', '5', '6', '2', 'Four.'],
      ]);
      expect(r.isOk, isTrue, reason: r.error);
      expect(r.questions.length, 1);
      final q = r.questions.single;
      expect(q.prompt, '2+2?');
      expect(q.options, ['3', '4', '5', '6']);
      expect(q.correct, 1, reason: 'answer "2" is the second option, index 1');
      expect(q.explanation, 'Four.');
    });

    test('a header row is optional', () {
      final r = rows([
        ['Sky colour?', 'Red', 'Blue', 'Green', 'Pink', 'B', ''],
      ]);
      expect(r.isOk, isTrue, reason: r.error);
      expect(r.questions.single.correct, 1);
    });

    test('the correct answer may be a number, a letter, or the option text',
        () {
      for (final (cell, want) in [
        ('1', 0),
        ('4', 3),
        ('A', 0),
        ('d', 3),
        ('Green', 2),
      ]) {
        final r = rows([
          ['Q', 'Red', 'Blue', 'Green', 'Pink', cell, ''],
        ]);
        expect(r.isOk, isTrue, reason: '$cell: ${r.error}');
        expect(r.questions.single.correct, want, reason: 'for "$cell"');
      }
    });

    test('a numeric answer matching an option is that option, not an index',
        () {
      // Options are numbers and the answer "42" is one of them: it must mean
      // the option whose text is "42", not "option number 42" (out of range).
      final r = rows([
        ['6 x 7?', '36', '42', '48', '54', '42', 'Six sevens are 42.'],
      ]);
      expect(r.isOk, isTrue, reason: r.error);
      expect(r.questions.single.correct, 1, reason: 'the option reading "42"');
    });

    test('a small numeric answer prefers the matching option over its index',
        () {
      // Options 3-6, answer "3": the option labelled 3 (index 0), not the
      // third option.
      final r = rows([
        ['Pick three', '3', '4', '5', '6', '3', ''],
      ]);
      expect(r.isOk, isTrue, reason: r.error);
      expect(r.questions.single.correct, 0);
    });

    test('a numeric answer still names a position when it is not an option',
        () {
      final r = rows([
        ['Capital?', 'Paris', 'London', 'Berlin', 'Madrid', '3', ''],
      ]);
      expect(r.isOk, isTrue, reason: r.error);
      expect(r.questions.single.correct, 2, reason: '"3" is the third option');
    });

    test('the explanation column is optional', () {
      final r = rows([
        ['Q', '1', '2', '3', '4', '1'],
      ]);
      expect(r.isOk, isTrue, reason: r.error);
      expect(r.questions.single.explanation, '');
    });

    test('blank lines between questions are skipped', () {
      final r = rows([
        ['Q1', 'a', 'b', 'c', 'd', '1', ''],
        ['', '', '', '', '', '', ''],
        ['Q2', 'a', 'b', 'c', 'd', '2', ''],
      ]);
      expect(r.isOk, isTrue, reason: r.error);
      expect(r.questions.length, 2);
    });
  });

  group('refusing a bad file', () {
    test('a row missing an option is rejected', () {
      final r = rows([
        ['Q', 'a', '', 'c', 'd', '1', ''],
      ]);
      expect(r.isOk, isFalse);
      expect(r.error, contains('option'));
    });

    test('an unresolvable correct answer is rejected', () {
      final r = rows([
        ['Q', 'a', 'b', 'c', 'd', 'zzz', ''],
      ]);
      expect(r.isOk, isFalse);
      expect(r.error, contains('correct'));
    });

    test('too few columns is rejected', () {
      final r = rows([
        ['Q', 'a', 'b'],
      ]);
      expect(r.isOk, isFalse);
    });

    test('an empty file is rejected', () {
      expect(rows([]).isOk, isFalse);
      expect(
          rows([
            ['question', 'a', 'b', 'c', 'd', 'correct']
          ]).isOk,
          isFalse,
          reason: 'a header with nothing under it is empty');
    });

    test('more than the maximum is rejected', () {
      final many = [
        for (var i = 0; i < kMaxQuizQuestions + 1; i++)
          ['Q$i', 'a', 'b', 'c', 'd', '1', ''],
      ];
      final r = rows(many);
      expect(r.isOk, isFalse);
      expect(r.error, contains('$kMaxQuizQuestions'));
    });

    test('exactly the maximum is allowed', () {
      final many = [
        for (var i = 0; i < kMaxQuizQuestions; i++)
          ['Q$i', 'a', 'b', 'c', 'd', '1', ''],
      ];
      expect(rows(many).isOk, isTrue);
    });
  });

  group('from bytes', () {
    Uint8List b(String s) => Uint8List.fromList(utf8.encode(s));

    test('CSV bytes parse', () {
      final r =
          parseQuizFile('q.csv', b('Q,a,b,c,d,1,why\nQ2,a,b,c,d,B,because\n'));
      expect(r.isOk, isTrue, reason: r.error);
      expect(r.questions.length, 2);
    });

    test('TSV is tab-separated', () {
      final r = parseQuizFile('q.tsv', b('Q\ta\tb\tc\td\t1\t\n'));
      expect(r.isOk, isTrue, reason: r.error);
      expect(r.questions.single.options, ['a', 'b', 'c', 'd']);
    });

    test('pasted comma text parses', () {
      final r = parseQuizText(
          'Capital of France?,Paris,London,Berlin,Madrid,1,Since 987.');
      expect(r.isOk, isTrue, reason: r.error);
      expect(r.questions.single.correct, 0);
    });

    test('pasted tab-separated text is detected', () {
      final r = parseQuizText('Q\ta\tb\tc\td\tB\t');
      expect(r.isOk, isTrue, reason: r.error);
      expect(r.questions.single.correct, 1);
      expect(r.questions.single.options, ['a', 'b', 'c', 'd']);
    });

    test('the bundled template is itself a valid quiz', () {
      final r = parseQuizFile('quiz-template.csv', b(quizTemplateCsv()));
      expect(r.isOk, isTrue, reason: r.error);
      expect(r.questions.length, 3);
      // The template's answers are written three different ways on purpose.
      expect(r.questions[0].correct, 0); // "1"
      expect(r.questions[1].correct, 2); // "C"
      expect(r.questions[2].correct, 2); // exact text "100 C"
    });
  });
}
