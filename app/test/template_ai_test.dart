// Normalising the model's reply into safe {page, blocks} template JSON.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:openote/ai/template_ai.dart';

void main() {
  group('normaliseTemplateJson', () {
    test('rebuilds a well-formed template', () {
      final json = normaliseTemplateJson(
          '{"page":{"background":"grid"},"blocks":['
          '{"type":"text","x":60,"y":40,"w":480,"content":{"text":"# Hi"}}]}');
      expect(json, isNotNull);
      final m = jsonDecode(json!) as Map<String, dynamic>;
      expect((m['page'] as Map)['background'], 'grid');
      final blocks = m['blocks'] as List;
      expect(blocks, hasLength(1));
      expect((blocks.first as Map)['type'], 'text');
    });

    test('an unknown background falls back to blank', () {
      final json =
          normaliseTemplateJson('{"page":{"background":"rainbow"},"blocks":['
              '{"type":"text","x":1,"y":1,"w":1,"content":{"text":"a"}}]}');
      final m = jsonDecode(json!) as Map<String, dynamic>;
      expect((m['page'] as Map)['background'], 'blank');
    });

    test('strips a code fence and coerces string coordinates', () {
      final json = normaliseTemplateJson('```json\n'
          '{"blocks":[{"type":"text","x":"60","y":"40","w":"500",'
          '"content":{"text":"body"}}]}\n```');
      expect(json, isNotNull);
      final b = (jsonDecode(json!)['blocks'] as List).first as Map;
      expect(b['x'], 60);
      expect(b['w'], 500);
    });

    test('drops blocks with no text and refuses an empty result', () {
      expect(
          normaliseTemplateJson(
              '{"blocks":[{"type":"text","x":1,"y":1,"w":1}]}'),
          isNull);
    });

    test('non-JSON is null, not a crash', () {
      expect(normaliseTemplateJson('Here is your template!'), isNull);
    });

    test('clamps an absurd width into range', () {
      final json = normaliseTemplateJson(
          '{"blocks":[{"type":"text","x":0,"y":0,"w":99999,'
          '"content":{"text":"a"}}]}');
      final b = (jsonDecode(json!)['blocks'] as List).first as Map;
      expect(b['w'], lessThanOrEqualTo(1040));
    });
  });

  group('prompts', () {
    test('the system prompt names the JSON shape and a custom persona', () {
      final p = templateSystemPrompt('Design minimalist templates.');
      expect(p, contains('Design minimalist templates.'));
      expect(p, contains('"blocks"'));
      expect(p.toLowerCase(), contains('background'));
    });
  });
}
