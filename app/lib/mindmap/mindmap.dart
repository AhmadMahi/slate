/// **A mind map: a tree of short labels, laid out left to right.**
///
/// One root idea, with branches that fan out to the right. You build it by
/// typing (Enter for a sibling, Tab for a child), and a branch with children
/// can be collapsed. The tree is stored nested, which is what both the
/// auto-layout and the collapse logic want, and what a Markdown outline
/// naturally becomes on import.
library;

import '../core/ids.dart' show newId;

/// One node in the tree: its text, a colour key (see the block view's palette),
/// whether its children are folded away, and those children.
class MindNode {
  MindNode({
    String? id,
    this.text = '',
    this.color = 'none',
    this.collapsed = false,
    List<MindNode>? children,
  })  : id = id ?? newId(),
        children = children ?? [];

  final String id;
  String text;
  String color;
  bool collapsed;
  List<MindNode> children;

  Map<String, dynamic> toJson() => {
        'id': id,
        'text': text,
        if (color != 'none') 'color': color,
        if (collapsed) 'collapsed': true,
        if (children.isNotEmpty)
          'children': [for (final c in children) c.toJson()],
      };

  static MindNode fromJson(Map<String, dynamic> j) => MindNode(
        id: j['id'] as String?,
        text: (j['text'] ?? '').toString(),
        color: (j['color'] ?? 'none').toString(),
        collapsed: j['collapsed'] == true,
        children: [
          for (final c in (j['children'] as List? ?? const []))
            MindNode.fromJson((c as Map).cast<String, dynamic>()),
        ],
      );

  /// A fresh mind map: one central node, ready to type into.
  static MindNode starter() => MindNode(text: 'Central idea');
}

/// A line of a Markdown outline, reduced to a depth and its text.
class _OutlineLine {
  _OutlineLine(this.depth, this.text);
  final int depth;
  final String text;
}

final _reHeading = RegExp(r'^(#{1,6})\s+(.*)$');
final _reBullet = RegExp(r'^(\s*)(?:[-*+]|\d+[.)])\s+(.*)$');

/// Turn a Markdown outline into a mind map. Understands ATX headings (`#`,
/// `##`, …) and nested bullet lists (`-`, `*`, `+`, `1.`), and is lenient
/// about a plain line, which becomes a top-level branch. Bullets nest under
/// the heading above them, so a normal document outline maps to a tree the way
/// you would draw it.
MindNode parseMarkdownOutline(String md) {
  final lines = <_OutlineLine>[];
  var headingBase = -1; // depth of the most recent heading, or -1 if none yet

  for (final raw in md.split('\n')) {
    if (raw.trim().isEmpty) continue;
    final h = _reHeading.firstMatch(raw);
    if (h != null) {
      final depth = h.group(1)!.length - 1; // # -> 0, ## -> 1
      headingBase = depth;
      lines.add(_OutlineLine(depth, h.group(2)!.trim()));
      continue;
    }
    final b = _reBullet.firstMatch(raw);
    if (b != null) {
      final indent = b.group(1)!.replaceAll('\t', '  ');
      final indentLevels = indent.length ~/ 2;
      final depth = (headingBase + 1) + indentLevels;
      lines.add(_OutlineLine(depth, b.group(2)!.trim()));
      continue;
    }
    // A plain line: a branch just below the current heading (or top level).
    lines.add(_OutlineLine(headingBase + 1, raw.trim()));
  }

  final roots = <MindNode>[];
  final stack = <({int depth, MindNode node})>[];
  for (final l in lines) {
    final node = MindNode(text: l.text);
    while (stack.isNotEmpty && stack.last.depth >= l.depth) {
      stack.removeLast();
    }
    if (stack.isEmpty) {
      roots.add(node);
    } else {
      stack.last.node.children.add(node);
    }
    stack.add((depth: l.depth, node: node));
  }

  if (roots.isEmpty) return MindNode.starter();
  if (roots.length == 1) return roots.single;
  // Several top-level items and no single spine: gather them under one root so
  // the map still has a centre.
  return MindNode(text: 'Mind map', children: roots);
}
