// The folder names must NOT follow the app's name.
//
// Renaming the app to Slate meant renaming what it calls itself in its own
// dialogs. A sweep over string literals did that — and also rewrote
//
//     Directory(p.join(root.path, 'Openote'))
//
// which is the WORKSPACE FOLDER. The app would have looked in
// ~/Documents/Slate, found nothing, and every notebook would have appeared to
// vanish. Caught by reading the diff before it was committed; it would not
// have been caught by any test that existed, because nothing pinned the
// on-disk names.
//
// So this pins them. These strings are ON-DISK CONTRACTS with data that
// already exists on people's machines: they are not the app's name, they are
// where the app's data lives, and the two only ever looked the same.
//
// If Slate should one day move its workspace, that is a MIGRATION — read the
// old location, move the contents, leave a marker — and this test should be
// changed as part of writing it, not to make a rename compile.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  /// Every Dart source file, as text.
  Iterable<(String, String)> sources() sync* {
    for (final e in Directory('lib').listSync(recursive: true)) {
      if (e is File && e.path.endsWith('.dart')) {
        yield (e.path, e.readAsStringSync());
      }
    }
  }

  test('the workspace folder is still called Openote on disk', () {
    final hits = [
      for (final (path, src) in sources())
        if (src.contains("p.join(root.path, 'Openote')")) path
    ];
    expect(hits, isNotEmpty,
        reason: 'the workspace folder name is gone or was renamed — every '
            'existing notebook would be invisible');
  });

  test('the cloud sync subfolder is still called Openote on disk', () {
    var found = 0;
    for (final (_, src) in sources()) {
      found += "subfolder: 'Openote'".allMatches(src).length;
      found += "p.join(cloud.path, 'Openote')".allMatches(src).length;
      found += "p.join(f.path, 'Openote')".allMatches(src).length;
    }
    expect(found, greaterThanOrEqualTo(4),
        reason: 'a renamed sync folder orphans notebooks that are already '
            'syncing through the old one');
  });

  test('no path expression names the app instead of the folder', () {
    // The shape of the mistake, rather than one instance of it: a literal
    // 'Slate' anywhere a path is being built.
    final offenders = <String>[];
    final pathish = RegExp(
        r"(p\.join\([^)]*|Directory\(\s*[^)]*|File\(\s*[^)]*)'Slate'");
    for (final (path, src) in sources()) {
      if (pathish.hasMatch(src)) offenders.add(path);
    }
    expect(offenders, isEmpty,
        reason: 'folder names are an on-disk contract with data that already '
            'exists; moving one needs a migration, not a rename');
  });
}
