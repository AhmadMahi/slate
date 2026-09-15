/// A quiz as a printable PDF, for pushing to a repo alongside a page.
///
/// The shape the owner asked for: every question with its options, then a
/// single **Answers** section at the end listing the correct option (and the
/// explanation, when there is one) for each. Built with the same `pdf` package
/// the rest of the exporters use, so it takes on no new dependency.
library;

import 'dart:typed_data';

import 'package:pdf/widgets.dart' as pw;

import '../quiz/quiz_import.dart';

const _letters = ['A', 'B', 'C', 'D', 'E', 'F'];

Future<Uint8List> buildQuizPdf(
    String name, List<QuizQuestion> questions) async {
  final doc = pw.Document(title: name, creator: 'Slate');
  doc.addPage(
    pw.MultiPage(
      build: (context) => [
        pw.Text(name.trim().isEmpty ? 'Quiz' : name,
            style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 12),
        for (var i = 0; i < questions.length; i++) ...[
          pw.Text('${i + 1}. ${questions[i].prompt}',
              style:
                  pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
          for (var o = 0; o < questions[i].options.length; o++)
            if (questions[i].options[o].trim().isNotEmpty)
              pw.Padding(
                padding: const pw.EdgeInsets.only(left: 16, top: 2),
                child: pw.Text(
                    '${_letters[o.clamp(0, _letters.length - 1)]}. '
                    '${questions[i].options[o]}',
                    style: const pw.TextStyle(fontSize: 11)),
              ),
          pw.SizedBox(height: 10),
        ],
        pw.SizedBox(height: 8),
        pw.Divider(),
        pw.Text('Answers',
            style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 6),
        for (var i = 0; i < questions.length; i++)
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 2),
            child: pw.Text(
              '${i + 1}. '
              '${_letters[questions[i].correct.clamp(0, _letters.length - 1)]}'
              '${questions[i].explanation.trim().isEmpty ? '' : '  —  ${questions[i].explanation.trim()}'}',
              style: const pw.TextStyle(fontSize: 11),
            ),
          ),
      ],
    ),
  );
  return doc.save();
}
