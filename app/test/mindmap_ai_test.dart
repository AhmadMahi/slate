// Turning a model's Markdown outline into a mind map, via the shared importer.
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/mindmap/mindmap_ai.dart';

void main() {
  group('mindmapFromOutline', () {
    test('a heading with nested bullets becomes a centre with branches', () {
      final root = mindmapFromOutline('''
# Water cycle
- Evaporation
  - From oceans
- Condensation
- Precipitation
''');
      expect(root, isNotNull);
      expect(root!.text, 'Water cycle');
      expect(root.children.map((c) => c.text),
          containsAll(['Evaporation', 'Condensation', 'Precipitation']));
      final evap = root.children.firstWhere((c) => c.text == 'Evaporation');
      expect(evap.children.single.text, 'From oceans');
    });

    test('a code fence around the outline is stripped', () {
      final root = mindmapFromOutline('```markdown\n# Idea\n- One\n- Two\n```');
      expect(root, isNotNull);
      expect(root!.text, 'Idea');
      expect(root.children.length, 2);
    });

    test('a blank reply yields null, not a bare starter map', () {
      expect(mindmapFromOutline('   \n  '), isNull);
    });
  });

  test('the prompts steer the model toward an outline', () {
    expect(mindmapSystemPrompt().toLowerCase(), contains('outline'));
    expect(mindmapUserPrompt('photosynthesis'), contains('photosynthesis'));
  });

  group('branchesFromJson (expand one node)', () {
    test('reads branches with nested children into fresh nodes', () {
      final b = branchesFromJson('{"branches":['
          '{"text":"Transformers","children":["Attention","BERT"]},'
          '{"text":"CNNs"}]}');
      expect(b.length, 2);
      expect(b.first.text, 'Transformers');
      expect(b.first.children.map((c) => c.text), ['Attention', 'BERT']);
      expect(b[1].text, 'CNNs');
      expect(b[1].children, isEmpty);
      // Fresh ids, so appending them into a tree cannot collide.
      expect(b.first.id, isNot(b[1].id));
    });

    test('accepts a bare array and plain-string children', () {
      final b = branchesFromJson('[{"text":"A","children":["x","y"]}]');
      expect(b.single.children.map((c) => c.text), ['x', 'y']);
    });

    test('non-JSON yields no branches, not a throw', () {
      expect(branchesFromJson('sorry, here are some ideas'), isEmpty);
    });

    test('the expand prompt lists existing children to avoid repeats', () {
      final p = expandUserPrompt('ML > Architecture', ['Neural networks']);
      expect(p, contains('Architecture'));
      expect(p, contains('Neural networks'));
      expect(expandSystemPrompt(), contains('branches'));
    });
  });
}
