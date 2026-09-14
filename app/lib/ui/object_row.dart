/// **The object row** — the band of chrome that belongs to what you are
/// touching (plan: v0.23, "the object row").
///
/// The owner, on the old contextual Maths tab: *"moving the user to a new menu
/// up there when entering maths mode without them doing anything is jarring
/// and its best to not force any navigation."*
///
/// The whole answer, in one sentence:
///
/// > The tab row and the command row belong to the student. This row belongs
/// > to the page — and the page lends it to an equation while the student is
/// > writing one.
///
/// ## The invariant
///
/// **The chrome is 32 + 44 + 36 = 112 px, in every state of the app.** Nothing
/// in it grows, shrinks, moves or re-points; only this row's *contents*
/// change, and they cross-fade in place. The canvas's box therefore never
/// changes size or position, so there is no compensating pan to write and no
/// promise to keep by hand.
///
/// That is why the row is permanent rather than appearing with the equation.
/// A row that slid in would push the page down 36 px, and putting the page
/// back means panning it up 36 px — which `CanvasController.panBy` discards
/// whenever the content is shorter than the viewport (`clampToPage`'s `axis()`
/// returns 0 there). On a short page, or a zoomed-out one — exactly where a
/// student is when they press Alt+= for their first equation — the page would
/// jump. A conditional band cannot honour "don't move the user". A permanent
/// one honours it by construction.
///
/// ## Hard rules for anything added here
///
///  * **No `Spacer`, `Expanded` or `Flexible` children.** A flex child under
///    the unbounded constraint a horizontal scroll view offers is a hard
///    layout assertion — it is what once killed the entire Draw row. Push
///    things apart with a `SizedBox`.
///  * **Nothing may reach through `FocusManager`.** Every control here acts on
///    something the student is in the middle of writing; taking the caret
///    away to run a command is the bug this release opened with.
///  * **Opacity only when the face changes.** A slide says "a new thing
///    arrived from elsewhere"; a fade says "this row is now about that".
library;

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';

import '../math/active_math.dart';
import '../math/evaluate.dart';
import '../model/page_stats.dart';
import '../model/models.dart';
import '../state/app_state.dart';
import '../theme/tokens.dart';
import 'glass.dart';
import 'math_bar.dart';
import 'object_face.dart';

/// The row's height, everywhere. `OnoteSize.button` plus two above and below.
const double kObjectRowHeight = 36;

class ObjectRow extends StatelessWidget {
  const ObjectRow({super.key, required this.app});

  final AppState app;

  @override
  Widget build(BuildContext context) {
    final s = context.surfaces;
    final face = objectFaceOf(app);
    // With nothing selected this row has nothing to show — its page controls
    // are on the View tab now — so it COLLAPSES rather than sitting there as
    // an empty band above the page.
    //
    // That is a deliberate reversal of "the chrome is 32 + 44 + 36 px in
    // every state": the reason for a fixed height was that the row's contents
    // used to change while staying the same size, and a band holding nothing
    // is not contents. It is animated so selecting an equation slides the row
    // open instead of jumping the page down under the cursor.
    // Nothing selected means nothing to show — the page controls are on the
    // View tab now — so the row takes NO SPACE rather than sitting above the
    // page as an empty band.
    //
    // A deliberate reversal of "the chrome is 32 + 44 + 36 px in every
    // state". The reason for the fixed height was that the row's CONTENTS
    // changed while its size did not; a band holding nothing is not contents.
    if (face == ObjectFace.page) {
      return const SizedBox(width: double.infinity, height: 0);
    }
    return _band(context, s, face);
  }

  Widget _band(BuildContext context, OnoteSurfaces s, ObjectFace face) {
    // `inset` — the "insets within chrome" role — so the row reads as a
    // different layer and is never mistaken for a second command row.
    return ChromeBar(
      inset: true,
      edge: ChromeEdge.top,
      height: kObjectRowHeight,
      child: ScrollConfiguration(
        behavior: const _RowScroll(),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: AnimatedSwitcher(
            duration: kMathMenuFade,
            // Keyed on the FACE, not on the widget, so moving between two
            // equations does not re-animate a row that is about to be
            // identical.
            switchInCurve: Curves.easeOut,
            transitionBuilder: (child, anim) =>
                FadeTransition(opacity: anim, child: child),
            child: KeyedSubtree(
              key: ValueKey(face),
              child: _face(context, face),
            ),
          ),
        ),
      ),
    );
  }

  Widget _face(BuildContext context, ObjectFace face) {
    switch (face) {
      case ObjectFace.equation:
        final m = app.activeMath;
        // One frame at most: the face is derived from `editingBlockId`, which
        // is true before the equation editor has built and registered itself.
        // Empty, NEVER the page face — falling back would flash the page
        // controls for a frame every time an equation opened.
        if (m == null) return const SizedBox(height: kObjectRowHeight);
        return EquationFace(
          math: m,
          onDrawGraph: m.drawGraph,
          onEvaluateAtValue: m.evaluateAtValue,
          angleMode: app.angleMode,
          onToggleAngleMode: () {
            // The open equation and its neighbours are worked out by
            // `setAngleMode` itself — every route to it behaves the same,
            // and only it knows which mode the page was written in.
            app.setAngleMode(app.angleMode == AngleMode.degrees
                ? AngleMode.radians
                : AngleMode.degrees);
          },
          recentIds: app.recentMathIds,
        );
      case ObjectFace.page:
        // NOTHING. Every control this row used to carry — backgrounds, page
        // mode, zoom, the word count — is on the View tab, which is always
        // one click away; this row is not, because it shows only while
        // nothing at all is selected. So the same strip appeared and vanished
        // under Home, Insert and Draw as you worked, duplicating a tab that
        // was already there. The row keeps its height so the chrome still
        // does not move (see kObjectRowHeight and the test that pins it).
        return const SizedBox.shrink();
    }
  }
}

/// The palette, while an equation is being written.
///
/// **The parity rule, made mechanical.** This takes an [ActiveMathEditor] and
/// primitives — no `AppState`, no `Block`, no `BlockType`, no block id, no
/// placement. A standalone equation and one inside a sentence therefore
/// produce the same row in the same pixels, because nothing here is given
/// anything it could tell them apart with. The owner: *"A regular user is not
/// going to think a standalone maths box is any different to one in a text
/// box, so they must have exact feature and behaviour parrody."*
///
/// Keeping that a compile error rather than a review catch is the point;
/// `EquationPlacement` exists two files away, and discipline is what wore out
/// last time.
class EquationFace extends StatelessWidget {
  const EquationFace({
    super.key,
    required this.math,
    required this.angleMode,
    required this.onToggleAngleMode,
    this.onDrawGraph,
    this.onEvaluateAtValue,
    this.recentIds = const [],
  });

  final ActiveMathEditor math;

  /// Draw this equation, or null when it cannot be drawn from here.
  final VoidCallback? onDrawGraph;

  /// Plug a value into this equation, or null when it cannot be from here.
  final VoidCallback? onEvaluateAtValue;
  final AngleMode angleMode;
  final VoidCallback onToggleAngleMode;
  final List<String> recentIds;

  @override
  Widget build(BuildContext context) => MathBar(
        onInsert: math.insert,
        onDrawGraph: onDrawGraph,
        onEvaluateAtValue: onEvaluateAtValue,
        latexMode: math.latexMode,
        latexAvailable: math.latexAvailable,
        onToggleLatex: math.toggleLatex,
        angleMode: angleMode,
        onToggleAngleMode: onToggleAngleMode,
        recentIds: recentIds,
      );
}

class WordCount extends StatefulWidget {
  const WordCount({super.key, required this.app});

  final AppState app;

  @override
  State<WordCount> createState() => _WordCountState();
}

class _WordCountState extends State<WordCount> {
  /// **Stateful only for this.** Counting the whole page from scratch is 68 ms
  /// on a page of eight hundred blocks — four dropped frames — and this row
  /// rebuilds on every keystroke. The cache re-counts only the block that
  /// changed; the rest are string comparisons. Measured after: 0.2 ms.
  final _cache = PageStatsCache();

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    final s = context.surfaces;
    final stats = _cache.of(app.blocks);
    return Tooltip(
      message: 'Words on this page — click for characters and reading time',
      child: PopupMenuButton<void>(
        position: PopupMenuPosition.under,
        tooltip: '',
        // Wide enough for the longest label and the longest number a page
        // will realistically carry, so the four rows line up as a column of
        // figures rather than four ragged pairs.
        constraints: const BoxConstraints(minWidth: 224, maxWidth: 260),
        itemBuilder: (_) => [
          PopupMenuItem<void>(
            enabled: false,
            height: 34,
            child: _row('Words', _n(stats.words)),
          ),
          PopupMenuItem<void>(
            enabled: false,
            height: 34,
            child: _row('Characters', _n(stats.characters)),
          ),
          PopupMenuItem<void>(
            enabled: false,
            height: 34,
            child: _row('Without spaces', _n(stats.charactersNoSpaces)),
          ),
          const PopupMenuDivider(),
          PopupMenuItem<void>(
            enabled: false,
            height: 34,
            // Rounded UP and never zero: "0 min" reads as a failure, and
            // anything written at all takes a moment to read.
            child: _row('Reading time',
                stats.words == 0 ? '—' : '${stats.readingMinutes} min'),
          ),
        ],
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Text(
            // Singular when it is one, because "1 words" is the sort of thing
            // that makes a student trust nothing else the app tells them.
            '${_n(stats.words)} ${stats.words == 1 ? 'word' : 'words'}',
            style: OnoteType.small.copyWith(color: s.textSecondary),
          ),
        ),
      ),
    );
  }

  static Widget _row(String label, String value) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Text(label,
                style: OnoteType.small, overflow: TextOverflow.ellipsis),
          ),
          const SizedBox(width: 16),
          Text(value,
              style: OnoteType.small.copyWith(fontWeight: FontWeight.w600)),
        ],
      );

  /// Thousands separated, because 12480 and 1248 are one glance apart and a
  /// word limit is exactly the number you are squinting at.
  static String _n(int v) {
    final digits = v.toString();
    final out = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) out.write(',');
      out.write(digits[i]);
    }
    return out.toString();
  }
}

class _Sep extends StatelessWidget {
  const _Sep();
  @override
  Widget build(BuildContext context) => Container(
        width: 1,
        height: 20,
        margin: const EdgeInsets.symmetric(horizontal: 6),
        color: context.surfaces.border,
      );
}

/// A row wider than the window must SCROLL, not clip: clipped pixels do not
/// hit-test, so on a narrow window the rightmost controls simply stop
/// responding with no visible reason. Mouse and trackpad are added to the drag
/// devices for the same reason the toolbar's own scroller adds them.
class _RowScroll extends MaterialScrollBehavior {
  const _RowScroll();

  @override
  Set<PointerDeviceKind> get dragDevices => const {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.stylus,
      };
}

/// The background pattern's spacing: dot gap, ruled line height, grid square.
///
/// Public because the View tab shows it too: the object row is contextual
/// (it appears only when nothing is selected) and the tab is always there.
///
/// Openote could always choose a pattern but never its size, so ruled lines
/// came at one height whether you write large or small, and the dot grid came
/// at one density whatever you were sketching. This is the missing half of
/// that control.
///
/// A popover rather than an always-visible slider because the page row is
/// already the widest thing in the toolbar, and this is a set-once-per-page
/// decision, not a per-stroke one. It offers named presets first — the sizes
/// real paper actually comes in — with a slider under them for anything else,
/// because "8 mm ruled" is a thing people can pick and "31.6" is not.
class BackgroundSpacingButton extends StatelessWidget {
  const BackgroundSpacingButton({super.key, required this.app});

  final AppState app;

  /// Presets in page units, named for what they are on paper. The numbers are
  /// the familiar rulings: narrow ~7 mm, wide ~8.7 mm, and so on at Openote's
  /// ~3.8 units/mm page scale.
  static const _presets = <(String, double)>[
    ('Tight', 14),
    ('Narrow', 20),
    ('Standard', PageProps.defaultBgSpacing),
    ('Wide', 32),
    ('Extra wide', 44),
  ];

  String _label(double v) {
    for (final (name, size) in _presets) {
      if ((v - size).abs() < 0.5) return name;
    }
    return v.toStringAsFixed(0);
  }

  /// What the number MEANS depends on the pattern, so the menu says so
  /// rather than making the user infer it from the page.
  String get _what => switch (app.pageProps.background) {
        'ruled' => 'Line height',
        'dotted' => 'Dot spacing',
        _ => 'Grid size',
      };

  @override
  Widget build(BuildContext context) {
    final v = app.pageProps.bgSpacing;
    return MenuAnchor(
      builder: (context, controller, _) => IconButton(
        icon: const Icon(Icons.format_line_spacing, size: OnoteIcon.md),
        tooltip: '$_what: ${_label(v)}',
        visualDensity: VisualDensity.compact,
        onPressed: () =>
            controller.isOpen ? controller.close() : controller.open(),
      ),
      menuChildren: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 2),
          child: Text(_what,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: context.surfaces.textSecondary)),
        ),
        for (final (name, size) in _presets)
          MenuItemButton(
            leadingIcon: Icon(
              (v - size).abs() < 0.5 ? Icons.check : null,
              size: 16,
            ),
            onPressed: () => app.setBackgroundSpacing(size),
            child: Text('$name  ·  ${size.toStringAsFixed(0)}',
                style: const TextStyle(fontSize: 13)),
          ),
        const Divider(height: 9),
        // The slider is live: the page redraws as it is dragged, so the
        // choice is made by looking at the paper rather than at a number.
        // (This is what needed the missing `spacing` comparison in
        // _PagePainter.shouldRepaint — without it the drag did nothing.)
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 0, 10, 4),
          child: SizedBox(
            width: 210,
            child: Row(children: [
              Expanded(
                child: Slider(
                  value:
                      v.clamp(PageProps.minBgSpacing, PageProps.maxBgSpacing),
                  min: PageProps.minBgSpacing,
                  max: PageProps.maxBgSpacing,
                  onChanged: (x) => app.setBackgroundSpacing(x.roundToDouble()),
                ),
              ),
              SizedBox(
                width: 26,
                child: Text(v.toStringAsFixed(0),
                    textAlign: TextAlign.right,
                    style: TextStyle(
                        fontSize: 12, color: context.surfaces.textSecondary)),
              ),
            ]),
          ),
        ),
      ],
    );
  }
}
