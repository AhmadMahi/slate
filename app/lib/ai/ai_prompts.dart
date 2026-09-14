/// **One place for every "system prompt" the app uses.**
///
/// Each AI feature (Ask AI, the quiz generator, the mind-map generator, and so
/// on) is steered by a short instruction that sets its behaviour — its tone,
/// subject, or language. Those instructions live here as one list, so Settings
/// can show them all together and let a teacher reset any to normal or write a
/// custom one for a different behaviour across the app.
///
/// **The safety split.** A generator's reply often has to parse (a quiz is JSON,
/// a mind map is a Markdown outline). If the whole system prompt were editable,
/// deleting the format rules would quietly break generation. So the *persona*
/// (what is editable here) and the *format rules* (always appended by the
/// generator's own code) are kept apart: [AppState.systemPromptFor] returns the
/// persona, and each generator adds its fixed rules after it. Customising the
/// tone can never break the parser.
library;

import 'ai_provider.dart';

/// Every place the app calls a cloud model, with a human label, a one-line hint
/// for the settings list, and the default persona used when nothing is custom.
enum AiFeature {
  askAi(
    id: 'askAi',
    label: 'Ask AI chat',
    hint: 'How the floating Ask AI chat answers — its tone, subject or '
        'language.',
    defaultPrompt: kDefaultAskAiPrompt,
  ),
  quiz(
    id: 'quiz',
    label: 'Quiz generator',
    hint: 'How quiz questions are written. The required answer format is added '
        'automatically.',
    defaultPrompt:
        'You write clear, accurate multiple-choice quiz questions for '
        'students. Keep questions and options concise and unambiguous.',
  ),
  mindmap(
    id: 'mindmap',
    label: 'Mind map generator',
    hint: 'How a mind map is drafted from a topic. The outline format is added '
        'automatically.',
    defaultPrompt: 'You design clear, well-organised mind maps. Keep every '
        'label short — a few words at most — and group ideas sensibly.',
  ),
  mindmapExpand(
    id: 'mindmapExpand',
    label: 'Mind map — grow a branch',
    hint: 'How new sub-branches are suggested for a node. The output format is '
        'added automatically.',
    defaultPrompt: 'You extend a mind map with relevant, non-repeating '
        'sub-topics. Keep labels short.',
  ),
  code(
    id: 'code',
    label: 'Code generator',
    hint: 'How code is written or rewritten in a code block. The "reply with '
        'only code" rule is added automatically.',
    defaultPrompt: 'You are an expert programmer. Write correct, idiomatic, '
        'well-structured code, with brief comments only where they add clarity.',
  ),
  summary(
    id: 'summary',
    label: 'Summary (from Ask AI)',
    hint: 'How an answer is turned into a summary block on the page.',
    defaultPrompt: 'You write concise, well-structured summaries in Markdown, '
        'using short headings and bullet points where they help.',
  ),
  template(
    id: 'template',
    label: 'Template generator',
    hint: 'How a page template is designed from your description. The required '
        'JSON layout format is added automatically.',
    defaultPrompt: 'You design clean, practical page templates for a '
        'note-taking app, with a sensible layout and helpful placeholder '
        'headings.',
  );

  const AiFeature({
    required this.id,
    required this.label,
    required this.hint,
    required this.defaultPrompt,
  });

  /// Stable key stored in settings — never change these strings.
  final String id;

  /// Shown as the row title in Settings.
  final String label;

  /// One line under the title explaining what it steers.
  final String hint;

  /// Used when the user has not written a custom instruction.
  final String defaultPrompt;

  static AiFeature? byId(String id) {
    for (final f in values) {
      if (f.id == id) return f;
    }
    return null;
  }
}
