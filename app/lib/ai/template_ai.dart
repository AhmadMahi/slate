/// Generating a page template from a description with a cloud model.
///
/// A template is the same `{page, blocks}` JSON the built-in templates use (see
/// `state/builtin_templates.dart`), so the model's only job is to produce that
/// shape and [AppState.applyTemplateRaw] lays it out. The reply is fully
/// re-normalised here before it is applied — every block is rebuilt as a plain
/// text block with numeric coordinates — so a malformed field can never reach
/// `Block.fromJson`.
library;

import 'dart:convert';

import 'ai_provider.dart';

const Set<String> _backgrounds = {'blank', 'ruled', 'grid', 'dotted'};

/// The editable [persona] plus the fixed JSON layout rules.
String templateSystemPrompt([String? persona]) =>
    '${(persona == null || persona.trim().isEmpty) ? 'You design page templates for a note-taking app.' : persona.trim()}\n\n'
    'Reply with ONE JSON object and nothing else — no markdown fences, no '
    'commentary — in exactly this shape:\n'
    '{"page":{"background":"blank"},"blocks":[\n'
    '  {"type":"text","x":60,"y":40,"w":480,"content":{"text":"# Heading\\n\\nBody"}}\n'
    ']}\n'
    'Rules:\n'
    '- "background" is one of: blank, ruled, grid, dotted.\n'
    '- Every block has "type":"text" and numeric "x", "y", "w".\n'
    '- The page is 1100 wide. Start content at x=60. Use one column (w=480 to '
    '960) or two columns at x=60 and x=600 (each w=480). Give stacked blocks '
    'about 150 units of vertical gap; the first block starts at y=40.\n'
    '- "content".text is Markdown: use #/## headings, "- " bullets, '
    '"- [ ] " checkboxes and **bold**. Use \\n for line breaks.\n'
    '- Make a practical, well-spaced layout with helpful placeholder headings '
    'the user fills in. Use four to eight blocks.';

String templateUserPrompt(String description) =>
    'Design a page template for:\n$description';

/// The generated template JSON (ready for [AppState.applyTemplateRaw]) or an
/// error, plus the token cost.
class TemplateAiResult {
  const TemplateAiResult({this.json, this.error, this.tokens = 0});
  final String? json;
  final String? error;
  final int tokens;
  bool get ok => error == null && (json?.isNotEmpty ?? false);
}

Future<TemplateAiResult> generateTemplate(
  AiClient client, {
  required String description,
  String? systemPrompt,
}) async {
  final res = await client.chat(
    [
      AiMessage.system(templateSystemPrompt(systemPrompt)),
      AiMessage.user(templateUserPrompt(description)),
    ],
    temperature: 0.5,
    jsonObject: true,
  );
  if (!res.ok) return TemplateAiResult(error: res.error, tokens: 0);
  final json = normaliseTemplateJson(res.text);
  if (json == null) {
    return TemplateAiResult(
        error: 'The model did not return a usable template. Try again.',
        tokens: res.totalTokens);
  }
  return TemplateAiResult(json: json, tokens: res.totalTokens);
}

/// Turn the model's reply into clean, guaranteed-valid template JSON, or null.
///
/// Rebuilt field by field rather than trusting the reply: the background is
/// checked against the allowed set, and every block becomes a text block with
/// numeric x/y/w and a string body. Anything unexpected is dropped, not passed
/// through.
String? normaliseTemplateJson(String reply) {
  Object? decoded;
  try {
    decoded = jsonDecode(_stripFence(reply));
  } on FormatException {
    return null;
  }
  if (decoded is! Map) return null;
  final page = decoded['page'];
  final bgRaw = page is Map ? '${page['background']}' : 'blank';
  final bg = _backgrounds.contains(bgRaw) ? bgRaw : 'blank';

  final rawBlocks = decoded['blocks'];
  if (rawBlocks is! List) return null;
  final blocks = <Map<String, Object?>>[];
  for (final b in rawBlocks) {
    if (b is! Map) continue;
    final content = b['content'];
    final text = content is Map ? content['text'] : null;
    if (text is! String) continue;
    blocks.add({
      'type': 'text',
      'x': _num(b['x'], 60),
      'y': _num(b['y'], 40),
      'w': _num(b['w'], 480).clamp(120, 1040),
      'content': {'text': text},
    });
  }
  if (blocks.isEmpty) return null;
  return jsonEncode({
    'page': {'background': bg},
    'blocks': blocks,
  });
}

num _num(Object? v, num fallback) {
  if (v is num) return v;
  if (v is String) return num.tryParse(v) ?? fallback;
  return fallback;
}

String _stripFence(String s) {
  var t = s.trim();
  if (!t.startsWith('```')) return t;
  t = t.replaceFirst(RegExp(r'^```[a-zA-Z]*\s*'), '');
  final end = t.lastIndexOf('```');
  if (end != -1) t = t.substring(0, end);
  return t.trim();
}
