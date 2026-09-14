import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../state/app_state.dart';
import '../theme/onote_theme.dart';
import '../theme/tokens.dart';
import '../canvas/ink_painter.dart' show themedInk;
import 'color_picker.dart';
import 'glass.dart';

/// The drawing tools, when focus mode has taken the chrome away.
///
/// Focus mode exists so the page can be edge to edge with nothing around it,
/// which means the tools cannot live in a bar along one side — a bar reserves
/// a strip, and a reserved strip is the thing focus mode was turning off. So
/// they float over the page instead, and you put them where the drawing
/// isn't.
///
/// What is on it is deliberately short. Everything Openote can do is one Esc
/// away in the full toolbar; what has to be HERE is what you reach for
/// without stopping to think while a pen is in your hand: the tools, the
/// colours, the size, and undo.
class FocusPalette extends StatefulWidget {
  const FocusPalette({super.key, required this.app});

  final AppState app;

  @override
  State<FocusPalette> createState() => _FocusPaletteState();
}

class _FocusPaletteState extends State<FocusPalette> {
  AppState get app => widget.app;

  /// Where it sits. Held here as well as in [AppState] so a drag moves it a
  /// frame at a time without pushing a notify through the whole app.
  Offset? _pos;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final s = context.surfaces;
    final pos = _pos ?? app.palettePos;

    // UNDRAGGED, IT IS PLACED BY THE STACK, NOT BY ARITHMETIC.
    //
    // The first cut computed "bottom centre" from `MediaQuery.sizeOf` and
    // clamped the result. When that size came back degenerate the clamps
    // collapsed to (0, 0) and the palette appeared as a dot in the top-left
    // corner — which is what it did on the first real build. Letting the
    // Stack centre it needs no size at all, so there is no number to be
    // wrong: `left: 0, right: 0` gives it the full width to centre in.
    final palette = _body(context, scheme, s);
    if (pos == null) {
      return Positioned(
        left: 0,
        right: 0,
        bottom: 24,
        child: Center(child: palette),
      );
    }
    final size = MediaQuery.sizeOf(context);
    return Positioned(
      // Once dragged it is wherever it was put — kept far enough inside the
      // window that the grip is always reachable, however the window resized
      // since.
      left: pos.dx.clamp(0.0, math.max(0.0, size.width - 80)),
      top: pos.dy.clamp(0.0, math.max(0.0, size.height - 40)),
      child: palette,
    );
  }

  Widget _body(BuildContext context, ColorScheme scheme, OnoteSurfaces s) {
    return Material(
      color: Colors.transparent,
      child: GlassPanel(
        dark: Theme.of(context).brightness == Brightness.dark,
        radius: OnoteRadius.xl,
        child: IntrinsicWidth(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            // So the grip spans the palette instead of hugging its handle.
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _grip(context),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  _tool(scheme, Tool.select, Icons.near_me_outlined, 'Select'),
                  _tool(scheme, Tool.pen, Icons.edit_outlined, 'Pen'),
                  _tool(scheme, Tool.highlighter, Icons.border_color_outlined,
                      'Highlighter'),
                  _tool(scheme, Tool.eraser, Icons.cleaning_services_outlined,
                      'Eraser'),
                  _tool(scheme, Tool.lasso, Icons.gesture_outlined, 'Lasso'),
                  _tool(scheme, Tool.text, Icons.text_fields, 'Text'),
                  _tool(scheme, Tool.arrow, Icons.north_east, 'Arrow'),
                  _tool(scheme, Tool.rectangle, Icons.crop_square, 'Rectangle'),
                  _tool(scheme, Tool.space, Icons.unfold_more, 'Insert space'),
                  _divider(s),
                  IconButton(
                    icon: const Icon(Icons.undo, size: 18),
                    tooltip: 'Undo  (Ctrl+Z)',
                    visualDensity: VisualDensity.compact,
                    onPressed: app.undo,
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_fullscreen, size: 18),
                    tooltip: 'Leave focus mode  (Esc)',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => app.setFocusMode(false),
                  ),
                ]),
              ),
              // SECOND ROW: the colours, at a size you can hit without
              // looking. Notability's arrangement, and its reason: colour is
              // the thing you change most often while drawing, so it must not
              // be the smallest target on the panel.
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  for (var i = 0; i < app.inkPalette.length; i++)
                    _well(scheme, i),
                  _divider(s),
                  SizedBox(
                    width: 110,
                    child: Slider(
                      value: app.penSize
                          .clamp(AppState.minPenSize, AppState.maxPenSize),
                      min: AppState.minPenSize,
                      max: AppState.maxPenSize,
                      divisions: 36,
                      // Through the state, so a width set here survives a
                      // restart exactly as one set on the Draw row does.
                      onChanged: app.setPenSize,
                    ),
                  ),
                  SizedBox(
                    width: 26,
                    child: Text(
                      app.penSize.toStringAsFixed(app.penSize % 1 == 0 ? 0 : 2),
                      textAlign: TextAlign.right,
                      style: TextStyle(fontSize: 11, color: s.textSecondary),
                    ),
                  ),
                ]),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The palette's current top-left in window coordinates, read from the
  /// render box. Falls back to the origin only if it has not been laid out.
  Offset _currentTopLeft(BuildContext context) {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return Offset.zero;
    return box.localToGlobal(Offset.zero);
  }

  /// The notch. It is the whole top edge, not a small tab: a handle you have
  /// to aim for is a handle people drag the wrong part of and then think the
  /// panel is stuck.
  Widget _grip(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanUpdate: (d) => setState(() {
          // The first drag has no stored position to add to, so it starts
          // from where the palette actually IS — read off the render box
          // rather than recomputed, which is what keeps it from jumping to a
          // guessed origin under the first millimetre of movement.
          _pos = (_pos ?? app.palettePos ?? _currentTopLeft(context)) + d.delta;
        }),
        // Written back to state only when the drag ENDS. Notifying per frame
        // would rebuild the shell — and the canvas under it — at pointer rate
        // for a move nothing else on screen depends on.
        onPanEnd: (_) {
          if (_pos != null) app.movePalette(_pos!);
        },
        child: MouseRegion(
          cursor: SystemMouseCursors.grab,
          child: SizedBox(
            // NOT `double.infinity`. A Stack child positioned by left/top is
            // laid out UNBOUNDED, and an infinite width there collapsed the
            // whole palette — the bug that put it in the corner as a dot.
            // `IntrinsicWidth` + a stretched Column give the grip the row's
            // width without anyone having to know what that width is.
            height: 18,
            child: Center(
              child: Container(
                width: 34,
                height: 4,
                decoration: BoxDecoration(
                  color: context.surfaces.textSecondary.withValues(alpha: .45),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
        ),
      );

  Widget _divider(OnoteSurfaces s) => Container(
        width: 1,
        height: 20,
        margin: const EdgeInsets.symmetric(horizontal: 6),
        color: s.border,
      );

  Widget _tool(ColorScheme scheme, Tool t, IconData icon, String tip) {
    final on = app.tool == t;
    final key = app.toolShortcut(t);
    // The armed tool sits in a soft tinted square — a glow, not a filled
    // button — the way the reference marks its active tool.
    return IconButton(
      icon: Icon(icon, size: OnoteIcon.md),
      tooltip: '$tip${key.isEmpty ? '' : '  ·  ${key.toUpperCase()}'}',
      visualDensity: VisualDensity.compact,
      style: IconButton.styleFrom(
        backgroundColor:
            on ? scheme.primary.withValues(alpha: OnoteAlpha.selected) : null,
        foregroundColor: on ? scheme.primary : null,
        shape: const RoundedRectangleBorder(borderRadius: OnoteRadius.lgAll),
      ),
      onPressed: () => app.setTool(t),
    );
  }

  /// Same behaviour as the Draw row's wells, including double-click to edit,
  /// so the two places you can pick a colour do not disagree about how.
  Widget _well(ColorScheme scheme, int i) {
    // Shown as it will draw on this theme — see `themedInk`.
    final c = themedInk(
        onoteColorFromHex(app.inkPalette[i]) ?? OnoteColors.graphite900,
        dark: Theme.of(context).brightness == Brightness.dark);
    final on = app.penColor == i;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Tooltip(
        message: 'Ink colour ${i + 1}\nDouble-click to change it',
        child: InkWell(
          borderRadius: BorderRadius.circular(99),
          onTap: () => _armOrEdit(i),
          onLongPress: () => _editWell(i),
          onSecondaryTap: () => _editWell(i),
          child: Padding(
            padding: const EdgeInsets.all(3),
            child: Container(
              width: 24,
              height: 24,
              // Clean filled discs; the armed one wears a thin ring in the
              // accent, standing a little off the disc.
              decoration: BoxDecoration(
                color: c,
                shape: BoxShape.circle,
                border: Border.all(
                    width: 1, color: Colors.black.withValues(alpha: .10)),
                boxShadow: on
                    ? [
                        BoxShadow(color: Colors.white, spreadRadius: 2),
                        BoxShadow(color: scheme.primary, spreadRadius: 3.5),
                      ]
                    : null,
              ),
            ),
          ),
        ),
      ),
    );
  }

  DateTime? _lastTap;
  static const _doubleTapWindow = Duration(milliseconds: 350);

  void _armOrEdit(int i) {
    final now = DateTime.now();
    final prev = _lastTap;
    if (prev != null && now.difference(prev) < _doubleTapWindow) {
      _lastTap = null;
      _editWell(i);
      return;
    }
    _lastTap = now;
    app.setPenColor(i);
    if (app.hasInkSelection) app.recolorSelectedInk(app.inkPalette[i]);
  }

  Future<void> _editWell(int i) async {
    final picked = await showOnoteColorPicker(
      context,
      app,
      initial: app.inkPalette[i],
      title: app.tool == Tool.highlighter ? 'Highlighter colour' : 'Pen colour',
    );
    if (picked == null) return;
    app.setInkPaletteColor(i, picked.startsWith('#') ? picked : '#$picked');
    if (app.hasInkSelection) app.recolorSelectedInk(app.inkPalette[i]);
  }
}
