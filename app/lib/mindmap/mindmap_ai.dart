/// Generating a mind map from a prompt with a cloud model.
///
/// The model is asked for a **Markdown outline**, which is exactly what
/// [parseMarkdownOutline] already turns into a tree for the "import a Markdown
/// outline" button. So the AI path reuses the whole importer: the model's only
/// job is to produce good outline text, and the shape it becomes is the same
/// tested conversion an imported file goes through.
library;

import 'dart:convert';

import '../ai/ai_provider.dart';
import 'mindmap.dart';

/// The house rules: a single Markdown outline, nothing else.
///
/// [persona] is the editable behaviour set in Settings; the fixed outline
/// format is always appended so customising it can never break the importer.
String mindmapSystemPrompt([String? persona]) =>
    '${(persona == null || persona.trim().isEmpty) ? 'You design mind maps.' : persona.trim()} '
    'Reply with ONLY a Markdown outline, no prose and '
    'no code fences. Use one top-level heading "# Central idea" for the centre, '
    'then nested bullet points ("-") for branches and sub-branches, indented '
    'two spaces per level. Keep every label short — a few words at most. Aim '
    'for three to six main branches, each with a few children.';

String mindmapUserPrompt(String topic) => 'Make a mind map about:\n$topic';

/// The round trip: ask the model, count tokens, hand back the outline it wrote
/// (parsing into a tree is the caller's job, via [parseMarkdownOutline]).
class MindmapAiResult {
  const MindmapAiResult({this.markdown, this.error, this.tokens = 0});
  final String? markdown;
  final String? error;
  final int tokens;
  bool get ok => error == null && (markdown?.trim().isNotEmpty ?? false);
}

Future<MindmapAiResult> generateMindmapOutline(
  AiClient client, {
  required String topic,
  String? systemPrompt,
}) async {
  final res = await client.chat(
    [
      AiMessage.system(mindmapSystemPrompt(systemPrompt)),
      AiMessage.user(mindmapUserPrompt(topic)),
    ],
    temperature: 0.6,
  );
  if (!res.ok) return MindmapAiResult(error: res.error, tokens: 0);
  final md = _stripFence(res.text);
  if (md.trim().isEmpty) {
    return MindmapAiResult(
        error: 'The model returned an empty outline. Try again.',
        tokens: res.totalTokens);
  }
  return MindmapAiResult(markdown: md, tokens: res.totalTokens);
}

/// Parse the model's outline into a tree, or null if nothing usable came back.
MindNode? mindmapFromOutline(String markdown) {
  final root = parseMarkdownOutline(_stripFence(markdown));
  // parseMarkdownOutline never fails, but an all-blank reply yields the bare
  // starter — treat that as "nothing generated".
  if (root.children.isEmpty && root.text == MindNode.starter().text) {
    return null;
  }
  return root;
}

String _stripFence(String s) {
  var t = s.trim();
  if (!t.startsWith('```')) return t;
  t = t.replaceFirst(RegExp(r'^```[a-zA-Z]*\s*'), '');
  final end = t.lastIndexOf('```');
  if (end != -1) t = t.substring(0, end);
  return t.trim();
}

// ── Expanding one node into more branches ──────────────────────────────────

/// Grow the map from a single node: given where it sits in the tree, the model
/// suggests a few child sub-topics (each with a few of its own), which are
/// appended under that node. Structured JSON so the shape is deterministic.
String expandSystemPrompt([String? persona]) =>
    '${(persona == null || persona.trim().isEmpty) ? 'You extend a mind map.' : persona.trim()} '
    'Given a node and the path to it, suggest child '
    'sub-topics for that node. Reply with ONE JSON object and nothing else:\n'
    '{"branches":[{"text":"short label","children":["short","short"]}]}\n'
    'Rules: three to five branches; each may have zero to four short children; '
    'labels are a few words at most; do not repeat any of the existing '
    'children; no prose, no code fences.';

String expandUserPrompt(String path, List<String> existing) {
  final have = existing.where((e) => e.trim().isNotEmpty).toList();
  return 'Node path: $path\n'
      'Expand the last node in that path.'
      '${have.isEmpty ? '' : '\nIt already has these children, do not repeat '
          'them: ${have.join(', ')}.'}';
}

/// New child branches for a node, or an error, plus the token cost.
class BranchesAiResult {
  const BranchesAiResult(
      {this.branches = const [], this.error, this.tokens = 0});
  final List<MindNode> branches;
  final String? error;
  final int tokens;
  bool get ok => error == null && branches.isNotEmpty;
}

Future<BranchesAiResult> generateBranches(
  AiClient client, {
  required String path,
  required List<String> existing,
  String? systemPrompt,
}) async {
  final res = await client.chat(
    [
      AiMessage.system(expandSystemPrompt(systemPrompt)),
      AiMessage.user(expandUserPrompt(path, existing)),
    ],
    temperature: 0.6,
    jsonObject: true,
  );
  if (!res.ok) return BranchesAiResult(error: res.error, tokens: 0);
  final branches = branchesFromJson(res.text);
  if (branches.isEmpty) {
    return BranchesAiResult(
        error: 'The model did not suggest any branches. Try again.',
        tokens: res.totalTokens);
  }
  return BranchesAiResult(branches: branches, tokens: res.totalTokens);
}

/// Parse the model's JSON into fresh [MindNode]s (with new ids). Tolerant of a
/// bare array and of children given as plain strings.
List<MindNode> branchesFromJson(String reply) {
  Object? decoded;
  try {
    decoded = jsonDecode(_stripFence(reply));
  } on FormatException {
    return const [];
  }
  final list = decoded is Map ? decoded['branches'] : decoded;
  if (list is! List) return const [];
  final out = <MindNode>[];
  for (final b in list) {
    if (b is String) {
      if (b.trim().isNotEmpty) out.add(MindNode(text: b.trim()));
      continue;
    }
    if (b is! Map) continue;
    final t = (b['text'] ?? b['label'] ?? '').toString().trim();
    if (t.isEmpty) continue;
    final kids = <MindNode>[];
    final cs = b['children'];
    if (cs is List) {
      for (final c in cs) {
        final ct =
            (c is Map ? (c['text'] ?? c['label'] ?? '') : c).toString().trim();
        if (ct.isNotEmpty) kids.add(MindNode(text: ct));
      }
    }
    out.add(MindNode(text: t, children: kids));
  }
  return out;
}
