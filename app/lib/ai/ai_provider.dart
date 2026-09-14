/// A thin "bring your own key" client for OpenAI-compatible chat models.
///
/// Both OpenAI and OpenRouter speak the same `/chat/completions` shape, so one
/// client serves both — they differ only in the endpoint and a couple of
/// headers. It is written over `dart:io`'s [HttpClient], exactly as
/// `sync/github_api.dart` is, so the app takes on **no new dependency** and no
/// networking package: the key is the user's, stored in the OS keychain by
/// `SecretStore`, and is sent only to the provider the user chose.
library;

import 'dart:convert';
import 'dart:io';

/// The default instructions ("system prompt") behind the Ask AI chat. The user
/// can replace this in Settings → Connections → AI provider to steer the tone
/// (a teaching style, a subject, a language). Empty in settings means "use
/// this".
const String kDefaultAskAiPrompt =
    'You are a concise, friendly teaching assistant inside a note-taking app. '
    'Explain clearly with simple language and short examples, and keep answers '
    'brief unless asked to go deeper.';

/// Which cloud AI a user brought a key for.
enum AiProvider {
  openai,
  openrouter;

  String get label => switch (this) {
        AiProvider.openai => 'OpenAI',
        AiProvider.openrouter => 'OpenRouter',
      };

  /// The chat-completions endpoint.
  String get endpoint => switch (this) {
        AiProvider.openai => 'https://api.openai.com/v1/chat/completions',
        AiProvider.openrouter =>
          'https://openrouter.ai/api/v1/chat/completions',
      };

  /// A hint shown in the empty model field — not a value that is ever sent.
  String get modelHint => switch (this) {
        AiProvider.openai => 'e.g. gpt-4o-mini',
        AiProvider.openrouter => 'e.g. openai/gpt-4o-mini',
      };

  /// Where the user makes a key, linked from the settings dialog.
  String get keysPage => switch (this) {
        AiProvider.openai => 'https://platform.openai.com/api-keys',
        AiProvider.openrouter => 'https://openrouter.ai/keys',
      };

  static AiProvider fromName(String? s) =>
      AiProvider.values.asNameMap()[s] ?? AiProvider.openai;
}

/// One chat turn.
class AiMessage {
  const AiMessage(this.role, this.content);
  const AiMessage.system(this.content) : role = 'system';
  const AiMessage.user(this.content) : role = 'user';
  final String role;
  final String content;
  Map<String, String> toJson() => {'role': role, 'content': content};
}

/// The outcome of a call: either text (and how many tokens it cost) or a
/// message fit to show a user. Never throws.
class AiResult {
  const AiResult.ok(this.text, this.totalTokens) : error = null;
  const AiResult.fail(this.error)
      : text = '',
        totalTokens = 0;
  final String text;
  final int totalTokens;
  final String? error;
  bool get ok => error == null;
}

/// A client for OpenAI-compatible chat completions.
class AiClient {
  AiClient({
    required this.provider,
    required this.apiKey,
    required this.model,
    HttpClient Function()? client,
    String? endpoint,
  })  : _client = client ?? HttpClient.new,
        _endpoint = endpoint ?? provider.endpoint;

  final AiProvider provider;
  final String apiKey;
  final String model;
  final HttpClient Function() _client;
  final String _endpoint;

  /// Send [messages] and return the reply text plus its token cost.
  ///
  /// [jsonObject] asks the model to reply with a single JSON object (the
  /// `response_format` both providers support) — the quiz generator wants
  /// structured output rather than prose.
  Future<AiResult> chat(
    List<AiMessage> messages, {
    double temperature = 0.7,
    bool jsonObject = false,
  }) async {
    if (model.trim().isEmpty) {
      return const AiResult.fail('No model name set. Type one in AI settings.');
    }
    final http = _client();
    try {
      final req = await http.postUrl(Uri.parse(_endpoint));
      req.headers
        ..set(HttpHeaders.authorizationHeader, 'Bearer $apiKey')
        ..contentType = ContentType.json;
      if (provider == AiProvider.openrouter) {
        // OpenRouter asks callers to identify themselves; ignored elsewhere.
        req.headers
          ..set('X-Title', 'Slate')
          ..set('HTTP-Referer', 'https://github.com/AhmadMahi/openote');
      }
      final body = <String, Object?>{
        'model': model.trim(),
        'messages': [for (final m in messages) m.toJson()],
        'temperature': temperature,
        if (jsonObject) 'response_format': {'type': 'json_object'},
      };
      req.add(utf8.encode(jsonEncode(body)));
      final res = await req.close().timeout(const Duration(seconds: 60));
      final text = await res.transform(utf8.decoder).join();
      if (res.statusCode != 200) {
        return AiResult.fail(_readError(res.statusCode, text));
      }
      final json = jsonDecode(text);
      if (json is! Map) return const AiResult.fail('Unexpected reply.');
      final choices = json['choices'];
      final content = (choices is List && choices.isNotEmpty)
          ? (((choices.first as Map)['message'] as Map?)?['content'])
          : null;
      final usage = json['usage'];
      final tokens =
          (usage is Map ? (usage['total_tokens'] as num?)?.toInt() : null) ?? 0;
      if (content is! String || content.trim().isEmpty) {
        return const AiResult.fail('The model returned an empty reply.');
      }
      return AiResult.ok(content, tokens);
    } on SocketException {
      return const AiResult.fail(
          'Could not reach the provider. Check your internet connection.');
    } on HttpException {
      return const AiResult.fail('The request failed. Please try again.');
    } on FormatException {
      return const AiResult.fail('The provider sent a reply Slate could not '
          'read. Check the model name.');
    } catch (e) {
      return AiResult.fail('$e');
    } finally {
      http.close(force: true);
    }
  }

  /// A tiny call to prove the key and model work, for the Connect button.
  Future<AiResult> ping() => chat(
        const [AiMessage.user('Reply with the single word: OK')],
        temperature: 0,
      );

  /// Turn a provider error body into one line worth showing.
  String _readError(int status, String body) {
    String? msg;
    try {
      final j = jsonDecode(body);
      if (j is Map && j['error'] is Map) {
        msg = (j['error'] as Map)['message'] as String?;
      }
    } catch (_) {
      // A non-JSON error body (a proxy's HTML page, say) leaves msg null.
    }
    if (status == 401 || status == 403) {
      return 'The provider rejected that API key ($status). Check it was '
          'copied whole and has not been revoked.';
    }
    if (status == 404) {
      return 'The provider did not recognise the model "$model" (404). '
          'Check the model name.';
    }
    if (status == 429) {
      return 'Rate limited or out of quota (429). ${msg ?? ''}'.trim();
    }
    return 'The provider returned an error ($status). ${msg ?? ''}'.trim();
  }
}
