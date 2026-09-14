// Folding an AI's JSON reply back through the shared quiz validator.
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/quiz/quiz_ai.dart';

void main() {
  group('parseQuizJson', () {
    test('reads the documented {questions:[...]} shape', () {
      final r = parseQuizJson('''
        {"questions":[
          {"question":"2+2?","options":["3","4","5","6"],"correct":2,
           "explanation":"Two and two."}
        ]}''');
      expect(r.isOk, isTrue, reason: r.error);
      final q = r.questions.single;
      expect(q.prompt, '2+2?');
      expect(q.options, ['3', '4', '5', '6']);
      expect(q.correct, 1, reason: '"correct":2 is the second option, index 1');
      expect(q.explanation, 'Two and two.');
    });

    test('accepts a bare array too', () {
      final r = parseQuizJson(
          '[{"question":"Sky?","options":["Red","Blue","Green","Pink"],'
          '"correct":2}]');
      expect(r.isOk, isTrue, reason: r.error);
      expect(r.questions.single.correct, 1);
    });

    test('strips a markdown code fence the model added anyway', () {
      final r = parseQuizJson('```json\n'
          '{"questions":[{"question":"Q","options":["a","b","c","d"],'
          '"correct":1}]}\n```');
      expect(r.isOk, isTrue, reason: r.error);
      expect(r.questions.single.correct, 0);
    });

    test('a letter or option text as the answer still resolves', () {
      final r = parseQuizJson(
          '{"questions":[{"question":"Capital?","options":["Paris","London",'
          '"Berlin","Madrid"],"correct":"Berlin"}]}');
      expect(r.isOk, isTrue, reason: r.error);
      expect(r.questions.single.correct, 2);
    });

    test('non-JSON is a plain error, not a crash', () {
      final r = parseQuizJson('Sure! Here is your quiz: ...');
      expect(r.isOk, isFalse);
      expect(r.error, isNotNull);
    });

    test('an empty questions list is refused', () {
      final r = parseQuizJson('{"questions":[]}');
      expect(r.isOk, isFalse);
    });

    test('a question missing an option is refused by the shared validator', () {
      final r = parseQuizJson(
          '{"questions":[{"question":"Q","options":["a","b"],"correct":1}]}');
      expect(r.isOk, isFalse);
      expect(r.error, contains('option'));
    });

    test('the prompts describe the shape the parser expects', () {
      expect(quizSystemPrompt(), contains('four options'));
      expect(quizUserPrompt('photosynthesis', 3), contains('3'));
      expect(quizUserPrompt('x', 999), contains('20'),
          reason: 'the count is clamped to the max');
    });
  });
}
