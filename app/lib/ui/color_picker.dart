import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../state/app_state.dart';
import '../theme/onote_theme.dart';
import '../theme/tokens.dart';
import 'onote_dialog.dart';

// The hex convention moved to `theme/onote_theme.dart` so the state layer can
// read a stored colour without importing this dialog. Re-exported because
// everything that STORES a picked colour needs the same reading of it when it
// draws — a second parser is a second convention — and every existing caller
// imports it from here.
export '../theme/onote_theme.dart' show onoteColorFromHex, onoteHexOf;

/// Full colour picker per Style Guide §7a.3: preset palette grid →
/// recent/custom row → custom area (hue slider + saturation/value field +
/// RGBA sliders + hex). Returns an RRGGBB or RRGGBBAA hex string, or null.
/// [title] names what the colour is FOR. The dialog used to say "Text
/// colour" whichever caller opened it, so choosing "Background colour…" on a
/// box put up a window headed "Text colour" — one of the two callers was
/// always contradicting the menu item that opened it.
Future<String?> showOnoteColorPicker(BuildContext context, AppState app,
    {String? initial,
    String title = 'Text colour',
    String? shortcut,
    ValueChanged<String>? onShortcut}) {
  return showOnoteDialog<String>(
    context: context,
    builder: (ctx) => _ColorPickerDialog(
      app: app,
      initial: initial,
      title: title,
      shortcut: shortcut,
      onShortcut: onShortcut,
    ),
  );
}

// 10 hues × 5 shades, OneNote-style standard grid.
const _baseHues = <double>[0, 25, 48, 90, 140, 175, 210, 240, 275, 320];

class _ColorPickerDialog extends StatefulWidget {
  const _ColorPickerDialog(
      {required this.app,
      this.initial,
      required this.title,
      this.shortcut,
      this.onShortcut});
  final AppState app;
  final String? initial;

  /// The key currently bound to whatever this picker is editing, or null when
  /// the caller has no shortcut to offer (text colour, block background —
  /// things there is only one of, so there is nothing to switch BETWEEN).
  final String? shortcut;
  final ValueChanged<String>? onShortcut;

  /// What the colour is FOR, so the heading agrees with the menu item that
  /// opened it.
  final String title;

  @override
  State<_ColorPickerDialog> createState() => _ColorPickerDialogState();
}

class _ColorPickerDialogState extends State<_ColorPickerDialog> {
  late HSVColor _hsv;
  bool _customOpen = false;
  late final TextEditingController _hex;

  @override
  void initState() {
    super.initState();
    final c = _parse(widget.initial) ?? const Color(0xFFC63838);
    _hsv = HSVColor.fromColor(c);
    _hex = TextEditingController(text: _toHex(c));
  }

  @override
  void dispose() {
    _hex.dispose();
    super.dispose();
  }

  static Color? _parse(String? hex) {
    if (hex == null) return null;
    final h = hex.replaceFirst('#', '');
    final v = int.tryParse(h, radix: 16);
    if (v == null) return null;
    if (h.length == 6) return Color(0xFF000000 | v);
    if (h.length == 8) return Color(((v & 0xFF) << 24) | (v >> 8));
    return null;
  }

  static String _toHex(Color c) {
    final a = (c.a * 255).round(), r = (c.r * 255).round();
    final g = (c.g * 255).round(), b = (c.b * 255).round();
    String two(int v) => v.toRadixString(16).padLeft(2, '0').toUpperCase();
    return a == 255 ? '${two(r)}${two(g)}${two(b)}' : '${two(r)}${two(g)}${two(b)}${two(a)}';
  }

  Color get _color => _hsv.toColor();

  void _setColor(Color c) {
    setState(() {
      _hsv = HSVColor.fromColor(c);
      _hex.text = _toHex(c);
    });
  }

  void _done() {
    final hex = _toHex(_color);
    widget.app.rememberCustomColor(hex);
    Navigator.pop(context, hex);
  }

  @override
  Widget build(BuildContext context) {
    Widget swatch(Color c, {double size = 24}) => InkWell(
          onTap: () => _setColor(c),
          borderRadius: BorderRadius.circular(4),
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: c,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                  color: _color.toARGB32() == c.toARGB32()
                      ? Theme.of(context).colorScheme.primary
                      : OnoteColors.paper300,
                  width: _color.toARGB32() == c.toARGB32() ? 2 : 1),
            ),
          ),
        );

    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 340,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Theme + standard grid
              Wrap(spacing: 5, runSpacing: 5, children: [
                for (final c in OnoteColors.penColors) swatch(c),
                swatch(Colors.white),
                swatch(Colors.black),
                swatch(OnoteColors.graphite500),
                swatch(OnoteColors.brass400),
              ]),
              const SizedBox(height: 8),
              for (final shade in const [0.95, 0.75, 0.55, 0.35])
                Padding(
                  padding: const EdgeInsets.only(bottom: 5),
                  child: Wrap(spacing: 5, children: [
                    for (final h in _baseHues)
                      swatch(HSVColor.fromAHSV(1, h, shade < 0.6 ? 1 : .85,
                              shade)
                          .toColor()),
                  ]),
                ),
              if (widget.app.customColors.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text('RECENT',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: .6,
                        color: context.surfaces.textSecondary)),
                const SizedBox(height: 4),
                Wrap(spacing: 5, children: [
                  for (final hex in widget.app.customColors)
                    if (_parse(hex) != null) swatch(_parse(hex)!),
                ]),
              ],
              const SizedBox(height: 8),
              TextButton.icon(
                icon: Icon(_customOpen ? Icons.expand_less : Icons.expand_more,
                    size: 16),
                label: const Text('Custom colour'),
                onPressed: () => setState(() => _customOpen = !_customOpen),
              ),
              if (_customOpen) ...[
                // Saturation/value field
                SizedBox(
                  height: 140,
                  child: LayoutBuilder(builder: (ctx2, cons) {
                    return GestureDetector(
                      onPanDown: (d) => _svAt(d.localPosition, cons.biggest),
                      onPanUpdate: (d) => _svAt(d.localPosition, cons.biggest),
                      child: CustomPaint(
                        size: cons.biggest,
                        painter: _SVPainter(_hsv),
                      ),
                    );
                  }),
                ),
                const SizedBox(height: 8),
                // Hue slider
                _slider('H', _hsv.hue, 360,
                    (v) => setState(() {
                          _hsv = _hsv.withHue(v);
                          _hex.text = _toHex(_color);
                        })),
                _slider('R', _color.r * 255, 255,
                    (v) => _setColor(_color.withValues(red: v / 255))),
                _slider('G', _color.g * 255, 255,
                    (v) => _setColor(_color.withValues(green: v / 255))),
                _slider('B', _color.b * 255, 255,
                    (v) => _setColor(_color.withValues(blue: v / 255))),
                _slider('A', _color.a * 255, 255,
                    (v) => _setColor(_color.withValues(alpha: v / 255))),
                Row(children: [
                  const Text('Hex  #', style: TextStyle(fontSize: 12)),
                  SizedBox(
                    width: 110,
                    child: TextField(
                      controller: _hex,
                      style: const TextStyle(
                          fontSize: 13, fontFamily: 'JetBrains Mono', fontFamilyFallback: onoteFontFallback),
                      decoration: const InputDecoration(
                          isDense: true, border: UnderlineInputBorder()),
                      onSubmitted: (v) {
                        final c = _parse(v);
                        if (c != null) _setColor(c);
                      },
                    ),
                  ),
                  const Spacer(),
                  Container(
                      width: 40,
                      height: 24,
                      decoration: BoxDecoration(
                          color: _color,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: OnoteColors.paper300))),
                ]),
              ],
              // The shortcut sits in the BODY, not the action bar.
              //
              // It was in `actions:` with a `Spacer` to push it left. That is
              // an `Expanded` inside an `OverflowBar`, which is not a flex —
              // "Incorrect use of ParentDataWidget", thrown while applying
              // parent data. The dialog then failed to lay out (a tall grey
              // slab where the palette should be) AND, because the route was
              // still pushed, its invisible modal barrier stayed over the page
              // swallowing every pointer event: the pen stopped drawing and
              // nothing on the canvas responded. One illegal widget, two
              // symptoms that looked unrelated.
              if (widget.onShortcut != null) ...[
                const Divider(height: 18),
                ShortcutField(
                  value: widget.shortcut ?? '',
                  onChanged: widget.onShortcut!,
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _done, child: const Text('Apply')),
      ],
    );
  }

  void _svAt(Offset pos, Size size) {
    setState(() {
      _hsv = _hsv
          .withSaturation((pos.dx / size.width).clamp(0, 1))
          .withValue((1 - pos.dy / size.height).clamp(0, 1));
      _hex.text = _toHex(_color);
    });
  }

  Widget _slider(String label, double value, double max,
      void Function(double) onChanged) {
    return Row(children: [
      SizedBox(
          width: 14,
          child: Text(label, style: const TextStyle(fontSize: 12))),
      Expanded(
        child: Slider(
            value: value.clamp(0, max), max: max, onChanged: onChanged),
      ),
      SizedBox(
          width: 30,
          child: Text(value.round().toString(),
              style: const TextStyle(fontSize: 11))),
    ]);
  }
}

/// Saturation (x) × value (y) field at the current hue.
class _SVPainter extends CustomPainter {
  _SVPainter(this.hsv);
  final HSVColor hsv;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    // Horizontal: white → pure hue
    canvas.drawRect(
        rect,
        Paint()
          ..shader = LinearGradient(colors: [
            Colors.white,
            HSVColor.fromAHSV(1, hsv.hue, 1, 1).toColor()
          ]).createShader(rect));
    // Vertical: transparent → black
    canvas.drawRect(
        rect,
        Paint()
          ..shader = const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Colors.black])
              .createShader(rect));
    // Cursor
    final pos = Offset(hsv.saturation * size.width, (1 - hsv.value) * size.height);
    canvas.drawCircle(
        pos,
        7,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = Colors.white);
    canvas.drawCircle(
        pos,
        8.5,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = Colors.black54);
  }

  @override
  bool shouldRepaint(covariant _SVPainter old) => old.hsv != hsv;
}

/// "Shortcut: [ k ]" — bind one key to the thing this dialog is editing.
///
/// A single printable character, captured by TYPING it rather than chosen
/// from a list: the question "which key do you want" is answered fastest by
/// pressing that key, and a dropdown of every key on the board is a menu
/// nobody reads.
///
/// Deliberately no modifiers. A drawing shortcut is pressed mid-stroke with
/// the off hand, and Ctrl+Alt+3 is not something a hand does while the other
/// one is holding a line. The bare-key handler in `app_shell` already stands
/// aside whenever a text field has focus, which is what makes a bare letter
/// safe to claim.
class ShortcutField extends StatefulWidget {
  const ShortcutField(
      {super.key, required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String> onChanged;

  @override
  State<ShortcutField> createState() => _ShortcutFieldState();
}

class _ShortcutFieldState extends State<ShortcutField> {
  late String _key = widget.value;
  bool _listening = false;

  /// Something you can see on a keycap. Control characters (< 0x20) and
  /// Delete are single characters too, which is exactly why the length check
  /// alone was not enough.
  static bool _isPrintable(String ch) {
    final c = ch.codeUnitAt(0);
    return c > 0x20 && c != 0x7F;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Text('Shortcut',
          style: TextStyle(fontSize: 12, color: context.surfaces.textSecondary)),
      const SizedBox(width: 8),
      Focus(
        autofocus: false,
        onKeyEvent: (node, event) {
          if (!_listening || event is! KeyDownEvent) {
            return KeyEventResult.ignored;
          }
          final ch = event.character;
          // Escape clears, anything printable binds; everything else (arrows,
          // modifiers on their own, Enter) is left to the dialog.
          if (event.logicalKey == LogicalKeyboardKey.escape) {
            setState(() {
              _key = '';
              _listening = false;
            });
            widget.onChanged('');
            return KeyEventResult.handled;
          }
          // A HELD MODIFIER IS NOT A SHORTCUT HERE, and refusing it is not
          // fussiness: Ctrl+A does not report the letter A, it reports the
          // control character \x01. That is a single character and it passed
          // every check this had — so a stray Ctrl-chord stored an invisible
          // byte as somebody's ink shortcut, and from then on that chord
          // changed colour mid-stroke with nothing on screen explaining why.
          // Caught by binding a key on a real build and reading back what
          // landed in the settings file.
          if (HardwareKeyboard.instance.isControlPressed ||
              HardwareKeyboard.instance.isMetaPressed ||
              HardwareKeyboard.instance.isAltPressed) {
            return KeyEventResult.ignored;
          }
          if (ch == null || ch.length != 1 || !_isPrintable(ch)) {
            return KeyEventResult.ignored;
          }
          setState(() {
            _key = ch.toLowerCase();
            _listening = false;
          });
          widget.onChanged(_key);
          return KeyEventResult.handled;
        },
        child: Builder(
          builder: (context) => OutlinedButton(
            onPressed: () {
              setState(() => _listening = !_listening);
              if (_listening) Focus.of(context).requestFocus();
            },
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(64, 32),
              side: BorderSide(
                  color: _listening ? scheme.primary : scheme.outlineVariant),
            ),
            child: Text(
              _listening
                  ? 'Press a key'
                  : (_key.isEmpty ? 'None' : _key.toUpperCase()),
              style: TextStyle(
                  fontSize: 12,
                  color: _listening ? scheme.primary : null),
            ),
          ),
        ),
      ),
    ]);
  }
}

/// "Give <tool> a key" — the tool half of the shortcut story.
///
/// Lives beside the colour picker's [_ShortcutField] because it is the same
/// interaction and must not drift from it: press the key you want, Escape
/// clears, no modifiers. Returns the chosen key, '' to clear, or null if the
/// user backed out — which is not the same as clearing, and treating them the
/// same would make Cancel delete the binding you already had.
Future<String?> showToolShortcutDialog(BuildContext context,
    {required String label, required String current}) {
  return showOnoteDialog<String>(
    context: context,
    builder: (ctx) => _ToolShortcutDialog(label: label, current: current),
  );
}

class _ToolShortcutDialog extends StatefulWidget {
  const _ToolShortcutDialog({required this.label, required this.current});
  final String label;
  final String current;

  @override
  State<_ToolShortcutDialog> createState() => _ToolShortcutDialogState();
}

class _ToolShortcutDialogState extends State<_ToolShortcutDialog> {
  late String _key = widget.current;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('${widget.label}: your own key'),
      content: SizedBox(
        width: 320,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(
            'Press the key you want. It works whenever you are not typing in '
            'a box. Escape clears it.',
            style: TextStyle(
                fontSize: 12, color: context.surfaces.textSecondary),
          ),
          const SizedBox(height: 14),
          ShortcutField(
            value: _key,
            onChanged: (k) => setState(() => _key = k),
          ),
        ]),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(
            onPressed: () => Navigator.pop(context, _key),
            child: const Text('Save')),
      ],
    );
  }
}
