// The bring-your-own-key AI client. Run against a real local HttpServer
// rather than a mock, for the same reason github_publish_test does: the
// failures worth catching are in headers, status codes and JSON shapes.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:openote/ai/ai_provider.dart';

void main() {
  group('provider metadata', () {
    test('each provider has its own endpoint and hints', () {
      expect(AiProvider.openai.endpoint, contains('api.openai.com'));
      expect(AiProvider.openrouter.endpoint, contains('openrouter.ai'));
      expect(AiProvider.openai.label, 'OpenAI');
      expect(AiProvider.openrouter.label, 'OpenRouter');
      expect(AiProvider.fromName('openrouter'), AiProvider.openrouter);
      expect(AiProvider.fromName(null), AiProvider.openai);
      expect(AiProvider.fromName('nonsense'), AiProvider.openai);
    });
  });

  group('talking to a chat-completions endpoint', () {
    late HttpServer server;
    late String base;
    final requests = <HttpRequest>[];
    final bodies = <String>[];

    Future<void> serve(int status, Object? body) async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      base = 'http://${server.address.host}:${server.port}';
      server.listen((req) async {
        requests.add(req);
        bodies.add(await utf8.decoder.bind(req).join());
        req.response.statusCode = status;
        req.response.headers.contentType = ContentType.json;
        req.response.write(body is String ? body : jsonEncode(body));
        await req.response.close();
      });
    }

    tearDown(() async {
      await server.close(force: true);
      requests.clear();
      bodies.clear();
    });

    AiClient client({
      AiProvider provider = AiProvider.openai,
      String model = 'gpt-4o-mini',
    }) =>
        AiClient(
            provider: provider,
            apiKey: 'sk-test',
            model: model,
            endpoint: base);

    Map<String, Object?> reply(String content, {int tokens = 42}) => {
          'choices': [
            {
              'message': {'role': 'assistant', 'content': content}
            }
          ],
          'usage': {'total_tokens': tokens},
        };

    test('a good reply yields the text and its token cost', () async {
      await serve(200, reply('Four.', tokens: 17));
      final r = await client().chat(const [AiMessage.user('2+2?')]);
      expect(r.ok, isTrue, reason: r.error);
      expect(r.text, 'Four.');
      expect(r.totalTokens, 17);
    });

    test('the request carries the bearer key, model and messages', () async {
      await serve(200, reply('OK'));
      await client(model: 'my-model').chat(const [
        AiMessage.system('be brief'),
        AiMessage.user('hi'),
      ]);
      expect(requests.single.headers.value(HttpHeaders.authorizationHeader),
          'Bearer sk-test');
      final sent = jsonDecode(bodies.single) as Map;
      expect(sent['model'], 'my-model');
      final msgs = (sent['messages'] as List).cast<Map>();
      expect(msgs.first['role'], 'system');
      expect(msgs.last['content'], 'hi');
      expect(sent.containsKey('response_format'), isFalse);
    });

    test('jsonObject asks for a JSON response_format', () async {
      await serve(200, reply('{}'));
      await client().chat(const [AiMessage.user('x')], jsonObject: true);
      final sent = jsonDecode(bodies.single) as Map;
      expect((sent['response_format'] as Map)['type'], 'json_object');
    });

    test('OpenRouter identifies itself with an X-Title header', () async {
      await serve(200, reply('OK'));
      await client(provider: AiProvider.openrouter)
          .chat(const [AiMessage.user('x')]);
      expect(requests.single.headers.value('X-Title'), 'Slate');
    });

    test('a 401 is reported as a rejected key, not a crash', () async {
      await serve(401, {
        'error': {'message': 'Incorrect API key provided'}
      });
      final r = await client().chat(const [AiMessage.user('x')]);
      expect(r.ok, isFalse);
      expect(r.error, contains('rejected'));
      expect(r.error, contains('401'));
    });

    test('a 404 points at the model name', () async {
      await serve(404, {
        'error': {'message': 'model not found'}
      });
      final r = await client(model: 'nope').chat(const [AiMessage.user('x')]);
      expect(r.ok, isFalse);
      expect(r.error, contains('model'));
    });

    test('an empty completion is a failure, not empty success', () async {
      await serve(200, reply(''));
      final r = await client().chat(const [AiMessage.user('x')]);
      expect(r.ok, isFalse);
      expect(r.error, contains('empty'));
    });

    test('an empty model name never hits the network', () async {
      await serve(200, reply('unused'));
      final r = await client(model: '  ').chat(const [AiMessage.user('x')]);
      expect(r.ok, isFalse);
      expect(requests, isEmpty);
    });

    test('ping sends a single short user turn', () async {
      await serve(200, reply('OK', tokens: 3));
      final r = await client().ping();
      expect(r.ok, isTrue);
      final sent = jsonDecode(bodies.single) as Map;
      expect((sent['messages'] as List).length, 1);
    });
  });
}
