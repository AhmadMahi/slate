// The central registry of per-feature AI instructions.
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/ai/ai_prompts.dart';
import 'package:openote/ai/ai_provider.dart';

void main() {
  group('AiFeature', () {
    test('every feature has a stable id, a label, a hint and a default', () {
      for (final f in AiFeature.values) {
        expect(f.id, isNotEmpty);
        expect(f.label, isNotEmpty);
        expect(f.hint, isNotEmpty);
        expect(f.defaultPrompt.trim(), isNotEmpty, reason: f.id);
      }
    });

    test('ids are unique', () {
      final ids = AiFeature.values.map((f) => f.id).toList();
      expect(ids.toSet().length, ids.length);
    });

    test('byId round-trips and returns null for a stranger', () {
      for (final f in AiFeature.values) {
        expect(AiFeature.byId(f.id), f);
      }
      expect(AiFeature.byId('nope'), isNull);
    });

    test('Ask AI keeps the shipped default prompt', () {
      expect(AiFeature.askAi.defaultPrompt, kDefaultAskAiPrompt);
    });
  });
}
