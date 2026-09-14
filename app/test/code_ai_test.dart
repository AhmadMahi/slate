// Building the code-generation prompts and cleaning the model's reply.
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/code/code_ai.dart';

void main() {
  group('stripCodeFence', () {
    test('leaves fence-free code untouched', () {
      expect(stripCodeFence('print(1)\nprint(2)'), 'print(1)\nprint(2)');
    });

    test('drops a ```lang fence the model added anyway', () {
      expect(stripCodeFence('```python\nprint(1)\n```'), 'print(1)');
    });

    test('drops a bare ``` fence', () {
      expect(stripCodeFence('```\nx = 1\n```'), 'x = 1');
    });

    test('keeps interior blank lines', () {
      expect(stripCodeFence('```js\na\n\nb\n```'), 'a\n\nb');
    });
  });

  group('prompts', () {
    test('the system prompt carries the "no fences" rule and the language', () {
      final p = codeSystemPrompt(null, 'Python');
      expect(p, contains('Python'));
      expect(p.toLowerCase(), contains('no markdown code fences'));
    });

    test('a custom persona is used in place of the default', () {
      final p = codeSystemPrompt('Write terse code.', 'Rust');
      expect(p, contains('Write terse code.'));
      expect(p, contains('Rust'));
    });

    test('an empty block generates; a filled block rewrites', () {
      final gen = codeUserPrompt(
          instruction: 'reverse a list', existing: '', languageName: 'Python');
      expect(gen.toLowerCase(), contains('write'));
      final rewrite = codeUserPrompt(
          instruction: 'add comments', existing: 'x=1', languageName: 'Python');
      expect(rewrite.toLowerCase(), contains('rewrite'));
      expect(rewrite, contains('x=1'));
    });
  });
}
