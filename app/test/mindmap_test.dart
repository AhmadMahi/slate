// The mind map: a tree of labels, built by typing or imported from Markdown.
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/mindmap/mindmap.dart';

void main() {
  group('Markdown import', () {
    test('a nested bullet list becomes a tree', () {
      final root = parseMarkdownOutline('''
- Animals
  - Dogs
    - Labrador
  - Cats
''');
      expect(root.text, 'Animals');
      expect(root.children.map((c) => c.text), ['Dogs', 'Cats']);
      expect(root.children.first.children.single.text, 'Labrador');
    });

    test('headings set depth, bullets nest under them', () {
      final root = parseMarkdownOutline('''
# Plan
## Research
- read papers
## Build
- prototype
- test
''');
      expect(root.text, 'Plan');
      expect(root.children.map((c) => c.text), ['Research', 'Build']);
      expect(root.children[0].children.single.text, 'read papers');
      expect(
          root.children[1].children.map((c) => c.text), ['prototype', 'test']);
    });

    test('several top-level items are gathered under one centre', () {
      final root = parseMarkdownOutline('- One\n- Two\n- Three\n');
      expect(root.text, 'Mind map');
      expect(root.children.map((c) => c.text), ['One', 'Two', 'Three']);
    });

    test('a single top-level bullet is the root itself', () {
      final root = parseMarkdownOutline('- Only\n  - child\n');
      expect(root.text, 'Only');
      expect(root.children.single.text, 'child');
    });

    test('empty input still yields a usable starter', () {
      final root = parseMarkdownOutline('   \n\n');
      expect(root.text.isNotEmpty, isTrue);
      expect(root.children, isEmpty);
    });

    test('numbered lists work too', () {
      final root = parseMarkdownOutline('1. First\n2. Second\n');
      expect(root.children.map((c) => c.text), ['First', 'Second']);
    });
  });

  group('round-trip', () {
    test('a tree survives toJson/fromJson with colour and collapse', () {
      final root = MindNode(text: 'Root', children: [
        MindNode(text: 'A', color: 'blue', collapsed: true, children: [
          MindNode(text: 'A1'),
        ]),
        MindNode(text: 'B', color: 'green-solid'),
      ]);
      final back = MindNode.fromJson(root.toJson());
      expect(back.text, 'Root');
      expect(back.children[0].text, 'A');
      expect(back.children[0].color, 'blue');
      expect(back.children[0].collapsed, isTrue);
      expect(back.children[0].children.single.text, 'A1');
      expect(back.children[1].color, 'green-solid');
    });

    test('default colour is not written, keeping older files small', () {
      final j = MindNode(text: 'x').toJson();
      expect(j.containsKey('color'), isFalse);
      expect(j.containsKey('collapsed'), isFalse);
    });
  });
}
