/// Writing or rewriting the contents of a code block with a cloud model.
///
/// The block itself is the prompt: whatever the user typed (a plain-language
/// description, or existing code plus an instruction) is sent, and the model is
/// asked for **raw source only** — the "reply with only code, no fences" rule
/// is always appended so the reply drops straight back into the block. If the
/// model wraps it in a ``` fence anyway, [stripCodeFence] removes it.
library;

import '../ai/ai_provider.dart';

/// The editable [persona] plus the fixed "raw code only" rule, in the chosen
/// language.
String codeSystemPrompt(String? persona, String languageName) =>
    '${(persona == null || persona.trim().isEmpty) ? 'You are an expert programmer.' : persona.trim()}\n\n'
    'Write $languageName code. Reply with ONLY the code — no explanation, no '
    'commentary before or after, and NO markdown code fences. Output raw '
    'source only.';

/// Build the user turn. With no existing code it is "write this"; with code
/// present it is "rewrite this as follows", so the same button both generates
/// and refines.
String codeUserPrompt({
  required String instruction,
  required String existing,
  required String languageName,
}) {
  if (existing.trim().isEmpty) {
    return 'Write $languageName code for the following:\n\n$instruction';
  }
  return 'Here is existing $languageName code:\n\n$existing\n\n'
      'Rewrite or modify it as follows:\n$instruction\n\n'
      'Return the complete updated code.';
}

/// The generated code, or an error, plus the token cost.
class CodeAiResult {
  const CodeAiResult({this.code, this.error, this.tokens = 0});
  final String? code;
  final String? error;
  final int tokens;
  bool get ok => error == null && (code?.trim().isNotEmpty ?? false);
}

Future<CodeAiResult> generateCode(
  AiClient client, {
  required String instruction,
  required String existing,
  required String languageName,
  String? systemPrompt,
}) async {
  final res = await client.chat(
    [
      AiMessage.system(codeSystemPrompt(systemPrompt, languageName)),
      AiMessage.user(codeUserPrompt(
          instruction: instruction,
          existing: existing,
          languageName: languageName)),
    ],
    // Low temperature: code should be deterministic, not creative.
    temperature: 0.2,
  );
  if (!res.ok) return CodeAiResult(error: res.error, tokens: 0);
  final code = stripCodeFence(res.text);
  if (code.trim().isEmpty) {
    return CodeAiResult(
        error: 'The model returned no code. Try again.',
        tokens: res.totalTokens);
  }
  return CodeAiResult(code: code, tokens: res.totalTokens);
}

/// Drop a leading ```lang fence and its closing ``` if the model added one
/// despite being told not to. A fence-free reply is returned untouched.
String stripCodeFence(String s) {
  var t = s.trim();
  if (!t.startsWith('```')) return t;
  t = t.replaceFirst(RegExp(r'^```[a-zA-Z0-9+#._-]*[ \t]*\r?\n?'), '');
  final end = t.lastIndexOf('```');
  if (end != -1) t = t.substring(0, end);
  // Keep interior blank lines; only trim the fence's own edge whitespace.
  return t.replaceFirst(RegExp(r'\r?\n?[ \t]*$'), '');
}
