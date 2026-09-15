/// A mind map as a printable PDF, for pushing to a repo alongside a page.
///
/// The owner asked for the map "fully expanded" — so this walks the WHOLE tree
/// regardless of any node's collapsed state and lays it out as a nested,
/// indented outline. An outline is robust at any size, stays searchable and
/// selectable, and needs no off-screen rendering of the diagram.
library;

import 'dart:typed_data';

import 'package:pdf/widgets.dart' as pw;

import '../mindmap/mindmap.dart';

Future<Uint8List> buildMindmapOutlinePdf(String title, MindNode root) async {
  final doc = pw.Document(title: title, creator: 'Slate');
  final lines = <pw.Widget>[];

  void walk(MindNode n, int depth) {
    final text = n.text.trim().isEmpty ? '(untitled)' : n.text.trim();
    if (depth == 0) {
      lines.add(pw.Text(text,
          style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)));
      lines.add(pw.SizedBox(height: 8));
    } else {
      lines.add(pw.Padding(
        padding: pw.EdgeInsets.only(left: 16.0 * (depth - 1), top: 3),
        child: pw.Text('• $text', style: const pw.TextStyle(fontSize: 11)),
      ));
    }
    for (final c in n.children) {
      walk(c, depth + 1); // fully expanded: collapsed flags are ignored
    }
  }

  walk(root, 0);

  doc.addPage(pw.MultiPage(build: (context) => lines));
  return doc.save();
}
