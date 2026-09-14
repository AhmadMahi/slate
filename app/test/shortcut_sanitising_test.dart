// A shortcut is one PRINTABLE character, or nothing.
//
// This is not a style rule. Ctrl+A does not report the letter A — it reports
// the control character U+0001, which is a single character and passed the
// "length == 1" check the capture originally had. So a stray Ctrl-chord while
// the picker was listening stored an invisible byte as an ink shortcut, and
// from then on that chord would change colour mid-stroke with nothing on
// screen to explain it.
//
// Found by binding a key on a real build and reading the settings file back,
// which is the only way it could have been found: the dialog displayed the
// key it thought it had captured, and the file on disk disagreed.
//
// Sanitising lives in the state layer as well as in the field that captures,
// because a settings file is not a trusted input — it can be hand-edited, and
// it can carry values written by an older, laxer build.
import 'package:flutter_test/flutter_test.dart';
import 'package:openote/state/app_state.dart';

void main() {
  group('the cycling key matches the KEY, not the character', () {
    // WHERE THE SHORTCUT SILENTLY DID NOTHING. The handler compared
    // `event.character`, and with Ctrl held a letter key does not report its
    // letter — it reports a control code (Ctrl+K is U+000B) or nothing, and
    // which of those differs by platform. So it never matched anywhere; it
    // was reported as a Windows problem only because that is where it was
    // noticed after the Mac had been used without trying it.
    //
    // The same mistake as storing U+0001 as a binding, made on the other side
    // of the same feature: the field that CAPTURES a key learned that a Ctrl
    // chord is not a character; the code that MATCHES one had not.
    bool matches(String binding, String label) =>
        AppState.cycleKeyMatches(binding, label);

    test('the bound key matches by its label', () {
      const binding = 'k';
      expect(matches(binding, 'K'), isTrue, reason: 'LogicalKeyboardKey.keyK.keyLabel');
      expect(matches(binding, 'k'), isTrue);
    });

    test('the CONTROL CODE a Ctrl chord produces does not match', () {
      const binding = 'k';
      expect(matches(binding, '\u000b'), isFalse,
          reason: 'Ctrl+K types a vertical tab, and that is what broke it');
      expect(matches(binding, ''), isFalse);
    });

    test('another key does not match', () {
      const binding = 'k';
      expect(matches(binding, 'J'), isFalse);
      expect(matches(binding, 'Escape'), isFalse);
    });

    test('no binding matches nothing, including an empty label', () {
      const binding = '';
      expect(matches(binding, 'K'), isFalse);
      expect(matches(binding, ''), isFalse);
    });

    test('a digit or a punctuation key works too', () {
      expect(matches('5', '5'), isTrue);
      expect(matches('/', '/'), isTrue);
    });
  });

  group('what counts as a shortcut', () {
    test('a printable character does, folded to lower case', () {
      expect(AppState.sanitiseShortcut('q'), 'q');
      expect(AppState.sanitiseShortcut('Q'), 'q');
      expect(AppState.sanitiseShortcut('5'), '5');
      expect(AppState.sanitiseShortcut('/'), '/');
    });

    test('a control character does NOT — this is the one that bit', () {
      expect(AppState.sanitiseShortcut('\u0001'), '',
          reason: 'Ctrl+A, which is what actually landed in the settings file');
      expect(AppState.sanitiseShortcut('\u001b'), '', reason: 'Escape');
      expect(AppState.sanitiseShortcut('\u007f'), '', reason: 'Delete');
      expect(AppState.sanitiseShortcut('\n'), '');
      expect(AppState.sanitiseShortcut('\t'), '');
    });

    test('nor does a space, nothing, or more than one character', () {
      expect(AppState.sanitiseShortcut(' '), '',
          reason: 'an invisible binding is one nobody can see they have');
      expect(AppState.sanitiseShortcut(''), '');
      expect(AppState.sanitiseShortcut(null), '');
      expect(AppState.sanitiseShortcut('qq'), '');
    });
  });
}
