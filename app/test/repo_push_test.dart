// Listing repos, uploading a file via the Contents API, and the path/URL
// helpers behind "push this page to the repo".
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:openote/sync/github_api.dart';

void main() {
  group('repoFullNameFromRemote', () {
    test('reads owner/name from an https clone url', () {
      expect(repoFullNameFromRemote('https://github.com/AhmadMahi/Notes.git'),
          'AhmadMahi/Notes');
      expect(repoFullNameFromRemote('https://github.com/AhmadMahi/Notes'),
          'AhmadMahi/Notes');
    });
    test('reads an ssh remote too', () {
      expect(repoFullNameFromRemote('git@github.com:AhmadMahi/Notes.git'),
          'AhmadMahi/Notes');
    });
    test('a non-github url is null', () {
      expect(repoFullNameFromRemote('https://example.com/x/y.git'), isNull);
    });
  });

  group('whiteboardPdfPath', () {
    test('nests a page under its section inside Whiteboards/', () {
      expect(whiteboardPdfPath('Day 1', 'Session 1'),
          'Whiteboards/Day 1/Session 1.pdf');
    });
    test('sanitises slashes and odd characters out of the segments', () {
      expect(whiteboardPdfPath('A/B: notes', 'x*y'),
          'Whiteboards/A-B- notes/x-y.pdf');
    });
    test('an empty title becomes Untitled', () {
      expect(whiteboardPdfPath('', ''), 'Whiteboards/Untitled/Untitled.pdf');
    });
  });

  group('listRepos', () {
    late HttpServer server;
    late String base;
    tearDown(() async => server.close(force: true));

    test('parses owner/name, clone url and privacy', () async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      base = 'http://${server.address.host}:${server.port}';
      server.listen((req) async {
        req.response.statusCode = 200;
        req.response.write(jsonEncode([
          {
            'full_name': 'me/alpha',
            'clone_url': 'https://github.com/me/alpha.git',
            'private': true
          },
          {
            'full_name': 'me/beta',
            'clone_url': 'https://github.com/me/beta.git',
            'private': false
          },
        ]));
        await req.response.close();
      });
      final repos = await GitHubApi('t', baseUrl: base).listRepos();
      expect(repos, hasLength(2));
      expect(repos.first.fullName, 'me/alpha');
      expect(repos.first.cloneUrl, 'https://github.com/me/alpha.git');
      expect(repos.first.private, isTrue);
      expect(repos[1].private, isFalse);
    });

    test('a failure is an empty list, not a throw', () async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      base = 'http://${server.address.host}:${server.port}';
      server.listen((req) async {
        req.response.statusCode = 401;
        req.response.write('{"message":"Bad credentials"}');
        await req.response.close();
      });
      expect(await GitHubApi('t', baseUrl: base).listRepos(), isEmpty);
    });
  });

  group('putFile', () {
    late HttpServer server;
    late String base;
    final methods = <String>[];
    final paths = <String>[];
    final bodies = <String>[];
    late bool fileExists;

    setUp(() {
      methods.clear();
      paths.clear();
      bodies.clear();
    });
    tearDown(() async => server.close(force: true));

    Future<void> serve() async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      base = 'http://${server.address.host}:${server.port}';
      server.listen((req) async {
        methods.add(req.method);
        paths.add(req.uri.path);
        bodies.add(await utf8.decoder.bind(req).join());
        if (req.method == 'GET') {
          if (fileExists) {
            req.response.statusCode = 200;
            req.response.write(jsonEncode({'sha': 'oldsha123'}));
          } else {
            req.response.statusCode = 404;
            req.response.write('{"message":"Not Found"}');
          }
        } else {
          req.response.statusCode = 201;
          req.response.write('{"content":{"path":"x"}}');
        }
        await req.response.close();
      });
    }

    test('a new file is a GET (404) then a PUT with base64 content, no sha',
        () async {
      fileExists = false;
      await serve();
      final err = await GitHubApi('t', baseUrl: base).putFile(
          'me/alpha', 'Whiteboards/Day 1/Session 1.pdf', [1, 2, 3], 'msg');
      expect(err, isNull);
      expect(methods, ['GET', 'PUT']);
      // The path is escaped per segment, keeping the folder slashes.
      expect(paths.last, contains('Whiteboards/Day%201/Session%201.pdf'));
      final put = jsonDecode(bodies.last) as Map;
      expect(put['content'], base64Encode([1, 2, 3]));
      expect(put.containsKey('sha'), isFalse,
          reason: 'a new file carries no sha');
      expect(put['message'], 'msg');
    });

    test('re-pushing an existing file sends its sha, making it an update',
        () async {
      fileExists = true;
      await serve();
      final err = await GitHubApi('t', baseUrl: base)
          .putFile('me/alpha', 'Whiteboards/x.pdf', [9], 'again');
      expect(err, isNull);
      expect(methods, ['GET', 'PUT']);
      expect((jsonDecode(bodies.last) as Map)['sha'], 'oldsha123');
    });

    test('a PUT rejection comes back as a message', () async {
      fileExists = false;
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      base = 'http://${server.address.host}:${server.port}';
      server.listen((req) async {
        if (req.method == 'GET') {
          req.response.statusCode = 404;
        } else {
          req.response.statusCode = 403;
          req.response.write('{"message":"no write access"}');
        }
        await req.response.close();
      });
      final err = await GitHubApi('t', baseUrl: base)
          .putFile('me/alpha', 'Whiteboards/x.pdf', [1], 'm');
      expect(err, isNotNull);
    });
  });
}
