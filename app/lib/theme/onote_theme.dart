import 'package:flutter/material.dart';

import 'tokens.dart';

/// Style-guide tokens (docs/05-style-guide.md §3). Single source of truth for color.
/// Fallback families searched, in order, for glyphs the chosen font lacks.
///
/// This is what makes imported OneNote notes legible. A maths note is full of
/// characters outside a UI font's coverage — ∃ ∀ ∧ ∨ ⊆ ⊘ ¬ ℝ, arrows, Greek —
/// and a font without the glyph renders nothing useful. Flutter only consults
/// these when the primary family has no glyph, so naming them costs nothing for
/// ordinary text and is the difference between a symbol and a blank box.
///
/// Deliberately cross-platform and ordered widest-coverage-first, because we
/// bundle no fonts yet (style guide §4.1): Windows ships Segoe UI Symbol and
/// Cambria Math, macOS/iOS ship Apple Symbols and STIX, most Linux desktops ship
/// DejaVu Sans and Noto. Naming a family that isn't installed is harmless — it
/// is skipped. Bundling a known-coverage font is the durable fix; until then
/// this removes the worst of the platform variance.
///
/// **Order is load-bearing, not cosmetic.** Verified against the actual cmaps of
/// the shipped Windows fonts: `Segoe UI Symbol` covers ∧ ∀ ∃ ℤ ⊆ ∅ and 7 500
/// other code points, while `Symbol` and `Wingdings` cover only ~400 — *and they
/// also claim `U+00AC`*, where Symbol's glyph is a left arrow rather than the
/// negation sign. Putting them last means they are only ever reached for
/// characters nothing else defines, i.e. the Private Use Area. Move them earlier
/// and ordinary punctuation starts rendering as dingbats.
///
/// Family names are the OS-resolvable ones, checked against each font's name
/// table — a misspelled family fails silently, which is the worst possible
/// failure mode here. `Cambria Math` is a separate face inside `cambria.ttc`.
const List<String> onoteFontFallback = <String>[
  'Segoe UI Symbol', // Windows: broad symbol/arrow/maths coverage
  'Cambria Math', // Windows: maths operators, blackboard bold
  'Apple Symbols', // macOS
  'STIX Two Math', // macOS/cross-platform maths
  'Noto Sans Symbols 2',
  'Noto Sans Math',
  'DejaVu Sans', // Linux workhorse, very wide BMP coverage
  // Office stores a Symbol/Wingdings character as U+F000+n in the Private Use
  // Area, and no ordinary font claims the PUA — so those characters render as
  // blank boxes however good the rest of the fallback chain is. Microsoft's own
  // Symbol and Wingdings map that range in their cmaps, so naming them resolves
  // the glyph the document actually meant. Deliberately *not* translated to
  // "real" Unicode in the importer: Symbol's 0xAC is ← while a user typing ¬
  // means U+00AC, and there is no way to tell those apart after the fact, so
  // guessing would corrupt content. Let the font that defines the encoding draw
  // it.
  'Symbol',
  'Wingdings',
  'Segoe UI Emoji',
  'Apple Color Emoji',
  'Noto Color Emoji',
];

abstract final class OnoteColors {
  // Ink (primary) — the system-blue ramp. `ink500` is the light-mode accent,
  // `ink400` the dark-mode one; the rest are its tints for tinted fills and
  // link colour in rendered Markdown.
  static const ink50 = Color(0xFFEAF3FF);
  static const ink100 = Color(0xFFD6E8FF);
  static const ink200 = Color(0xFFB3D4FF);
  static const ink300 = Color(0xFF7FB8FF);
  static const ink400 = Color(0xFF6E96FF);
  static const ink500 = Color(0xFF3B6FF0);
  static const ink600 = Color(0xFF0066DB);
  static const ink700 = Color(0xFF0052B4);
  static const ink800 = Color(0xFF003E8C);
  static const ink900 = Color(0xFF002A5C);
  // Brass (accent) — the warm counterpart, for favourites and reminders.
  static const brass100 = Color(0xFFFFEFD6);
  static const brass400 = Color(0xFFF5A524);
  static const brass500 = Color(0xFFE08E0B);
  static const brass700 = Color(0xFF9A5E05);
  // Paper & graphite (light). Cool neutrals: a white page, a near-white
  // toolbar, a grey sidebar, and hairlines two steps darker than the chrome
  // they divide. No warmth in the greys — the page's own paper carries it.
  static const paper0 = Color(0xFFFFFFFF);
  static const paper50 = Color(0xFFF7F9FE);
  static const paper100 = Color(0xFFEFF3FC);
  static const paper200 = Color(0xFFE2E8F5);
  static const paper300 = Color(0xFFCDD5E6);
  static const graphite400 = Color(0xFF8E96A8);
  static const graphite500 = Color(0xFF6B7280);
  static const graphite700 = Color(0xFF1F2433);
  // Kept: this is also the default pen ink, and pen ink is data on disk.
  static const graphite900 = Color(0xFF211F1B);
  // Night ink (dark). Same ordering, so the roles fall out the same way.
  static const night0 = Color(0xFF17171A);
  static const night50 = Color(0xFF1F1F23);
  static const night100 = Color(0xFF29292E);
  static const night200 = Color(0xFF37373D);
  static const night300 = Color(0xFF4A4A52);
  static const moon0 = Color(0xFFF5F5F7);
  static const moon100 = Color(0xFFE8E8ED);
  static const moon300 = Color(0xFFB0B0B8);
  static const moon400 = Color(0xFF8A8A93);
  // Semantic
  static const danger = Color(0xFFD93634);
  static const success = Color(0xFF2DA44E);

  /// Default content-ink pen colors (style guide §3.6).
  static const penColors = <Color>[
    graphite900,
    Color(0xFF2F6FB3),
    danger,
    success,
    Color(0xFF6A4BC0),
    brass500,
  ];
  static const highlighterColors = <Color>[
    Color(0xFFF7E27A),
    Color(0xFFB6E39A),
    Color(0xFFF3B0C6),
    Color(0xFFA8CCF0),
  ];
}

/// The app's one hex convention, decoded: `RRGGBB` (opaque) or `RRGGBBAA`.
///
/// It lives HERE, beside the palette, rather than in the colour picker, so
/// the state layer can read a stored colour without importing a dialog. The
/// picker still exports it, so every existing caller is unchanged — the point
/// of the original comment ("a second parser is a second convention") holds
/// either way; this just puts the one parser where every layer can reach it.
Color? onoteColorFromHex(String? hex) {
  if (hex == null) return null;
  final h = hex.replaceFirst('#', '');
  final v = int.tryParse(h, radix: 16);
  if (v == null) return null;
  if (h.length == 6) return Color(0xFF000000 | v);
  if (h.length == 8) return Color(((v & 0xFF) << 24) | (v >> 8));
  return null;
}

/// `Color` → the same `#RRGGBB` convention, which is what a stroke stores.
String onoteHexOf(Color c) =>
    '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

/// Desktop apps do not ripple.
///
/// Material's ink splash is a touch affordance — it exists to show a finger
/// where it landed on a surface it was covering. On a pointer device it reads
/// as a phone gesture echo, and it was one of the loudest "this is a mobile
/// toolkit" tells in the 2026-08 UI review. Hover and pressed *tints*
/// (`OnoteAlpha`) carry the same information without the animation, so the
/// theme installs `NoSplash.splashFactory` app-wide and on every button.

/// The accent the user chose, and the tint of the chrome that carries it.
///
/// Seven, OneNote-style: each is a pair — a light-mode colour dark enough to
/// hold white text, a dark-mode colour bright enough to read on night — and a
/// name. [tinted] is what makes it a THEME rather than a button colour: the
/// toolbar glass and the sidebar take a faint wash of it, so a green notebook
/// feels green everywhere and not only where something is selected. The wash
/// is deliberately slight (5–9%); chrome that shouts its colour tires the eye
/// and competes with the page.
enum OnoteAccent {
  blue('Blue', Color(0xFF3B6FF0), Color(0xFF6E96FF)),
  graphite('Graphite', Color(0xFF5E5E64), Color(0xFFB4B4BC)),
  green('Green', Color(0xFF2DA44E), Color(0xFF4CC26A)),
  teal('Teal', Color(0xFF0E8A8A), Color(0xFF3FBFBF)),
  purple('Purple', Color(0xFF7A4DE0), Color(0xFFA98BFF)),
  rose('Rose', Color(0xFFD6336C), Color(0xFFFF6B9E)),
  orange('Orange', Color(0xFFE0740B), Color(0xFFFFA033));

  const OnoteAccent(this.label, this.light, this.dark);
  final String label;
  final Color light;
  final Color dark;

  Color color(bool isDark) => isDark ? dark : light;

  /// The surface roles with this accent washed through the chrome.
  OnoteSurfaces tinted(OnoteSurfaces s, bool isDark) {
    final c = color(isDark);
    final a = isDark ? .07 : .05;
    return s.copyWith(
      chrome: Color.lerp(s.chrome, c, a),
      chrome2: Color.lerp(s.chrome2, c, a + .02),
      border: Color.lerp(s.border, c, a),
      well: Color.lerp(s.well, c, isDark ? .04 : .0),
    );
  }
}

/// The app theme.
///
/// **Everything Material renders is themed here** (v0.6 stage 2). Before this
/// pass the function set colours, the font and density and stopped — so every
/// Material widget the app reached for rendered in stock *mobile* Material 3
/// beside the hand-rolled dense desktop panels: full-window-width snackbar
/// slabs, stadium-pill buttons, 28px-radius dialogs, mobile-metric menus and
/// pickers. Two design languages in one window, which is what "it feels a bit
/// off and unprofessional" turned out to be.
///
/// The rule for anything added later: if a Material component can appear in
/// the app, it gets a theme here. A component that inherits M3 defaults is a
/// component that will look like a different product.
ThemeData onoteTheme(Brightness brightness,
    {OnoteAccent accent = OnoteAccent.blue}) {
  final dark = brightness == Brightness.dark;
  final surfaces =
      accent.tinted(dark ? OnoteSurfaces.dark : OnoteSurfaces.light, dark);
  final primary = accent.color(dark);
  final scheme = ColorScheme(
    brightness: brightness,
    primary: primary,
    onPrimary: dark ? OnoteColors.graphite900 : Colors.white,
    secondary: OnoteColors.brass400,
    onSecondary: OnoteColors.graphite900,
    error: OnoteColors.danger,
    onError: Colors.white,
    surface: surfaces.chrome,
    onSurface: surfaces.textPrimary,
    surfaceContainerHighest: surfaces.chrome2,
    outline: dark ? OnoteColors.night300 : OnoteColors.paper300,
  );

  // The chrome ramp (style guide §4.2a) as Material's text theme, so anything
  // that reads `Theme.of(context).textTheme` — menus, dialogs, buttons, list
  // tiles — lands on the ramp without each call site restating it.
  //
  // **The family is applied here, explicitly.** `ThemeData.fontFamily` only
  // reaches the text theme Flutter *derives from typography* — pass an explicit
  // `textTheme` and its null families stay null, so they resolve to Flutter's
  // default (Roboto). That is not theoretical: it rendered every button label
  // in the app in a different face from everything around it, which is exactly
  // the per-surface inconsistency this pass exists to remove.
  final text = const TextTheme(
    titleMedium: OnoteType.title,
    titleSmall: OnoteType.uiStrong,
    bodyMedium: OnoteType.ui,
    bodySmall: OnoteType.small,
    labelLarge: OnoteType.ui,
    labelMedium: OnoteType.small,
    labelSmall: OnoteType.caption,
  ).apply(
    fontFamily: 'Inter',
    fontFamilyFallback: onoteFontFallback,
    bodyColor: surfaces.textPrimary,
    displayColor: surfaces.textPrimary,
  );

  // Focus is an accessibility requirement (style guide §9), and M3's default
  // is nearly invisible on these surfaces.
  final focusBorder = OutlineInputBorder(
    borderRadius: OnoteRadius.smAll,
    borderSide: BorderSide(color: primary.withValues(alpha: .75), width: 1.5),
  );
  final restBorder = OutlineInputBorder(
    borderRadius: OnoteRadius.smAll,
    borderSide: BorderSide(color: surfaces.border),
  );

  // Hover and press are a wash of the text colour over the control — the
  // same wash on every control in the app — never Material's coloured splash.
  Color? overlayFor(Set<WidgetState> states) {
    if (states.contains(WidgetState.pressed)) {
      return surfaces.textPrimary.withValues(alpha: OnoteAlpha.selected);
    }
    if (states.contains(WidgetState.hovered) ||
        states.contains(WidgetState.focused)) {
      return surfaces.textPrimary.withValues(alpha: OnoteAlpha.hover);
    }
    return null;
  }

  ButtonStyle buttonBase({Color? fg, Color? bg}) => ButtonStyle(
        minimumSize:
            const WidgetStatePropertyAll(Size(0, OnoteSize.buttonCompact)),
        padding: const WidgetStatePropertyAll(OnoteSpace.control),
        textStyle: const WidgetStatePropertyAll(OnoteType.ui),
        foregroundColor: fg == null ? null : WidgetStatePropertyAll(fg),
        backgroundColor: bg == null ? null : WidgetStatePropertyAll(bg),
        overlayColor: WidgetStateProperty.resolveWith(overlayFor),
        // Never the stadium. This single line is the difference between
        // "an app" and "a Material demo" on every dialog in the product.
        shape: const WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: OnoteRadius.mdAll)),
        splashFactory: NoSplash.splashFactory,
        visualDensity: VisualDensity.compact,
      );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: surfaces.chrome,
    canvasColor: surfaces.canvas,
    dividerColor: surfaces.border,
    // Bundled Inter (style guide §4.1) — the app finally looks the same on
    // every OS. The fallback chain stays exactly as verified in review §O.3:
    // it resolves the math/symbol glyphs Inter lacks, and Symbol/Wingdings
    // must stay LAST in it (they claim U+00AC with the wrong glyph).
    fontFamily: 'Inter',
    fontFamilyFallback: onoteFontFallback,
    visualDensity: VisualDensity.compact,
    textTheme: text,
    splashFactory: NoSplash.splashFactory,
    extensions: [surfaces],

    hoverColor: surfaces.textPrimary.withValues(alpha: OnoteAlpha.hover),
    highlightColor: surfaces.textPrimary.withValues(alpha: OnoteAlpha.selected),
    splashColor: Colors.transparent,

    dividerTheme:
        DividerThemeData(color: surfaces.border, thickness: 1, space: 1),

    iconTheme: IconThemeData(size: OnoteIcon.sm, color: surfaces.textPrimary),

    tooltipTheme: TooltipThemeData(
      waitDuration: const Duration(milliseconds: 500),
      textStyle: OnoteType.caption.copyWith(color: surfaces.textPrimary),
      decoration: BoxDecoration(
        color: dark ? OnoteColors.night200 : OnoteColors.paper0,
        borderRadius: OnoteRadius.smAll,
        border: Border.all(color: surfaces.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: dark ? .45 : .14),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(
          horizontal: OnoteSpace.x4, vertical: OnoteSpace.x3),
    ),

    // ── Buttons ────────────────────────────────────────────────────────
    filledButtonTheme: FilledButtonThemeData(style: buttonBase()),
    elevatedButtonTheme: ElevatedButtonThemeData(style: buttonBase()),
    textButtonTheme: TextButtonThemeData(style: buttonBase()),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: buttonBase().copyWith(
        side: WidgetStatePropertyAll(BorderSide(color: surfaces.border)),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: ButtonStyle(
        iconSize: const WidgetStatePropertyAll(OnoteIcon.sm),
        splashFactory: NoSplash.splashFactory,
        shape: const WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: OnoteRadius.mdAll)),
        visualDensity: VisualDensity.compact,
        overlayColor: WidgetStateProperty.resolveWith(overlayFor),
        // The active tool, the open panel: a tinted pill in the accent, the
        // way a toolbar toggle sits "down" on macOS. Rest state stays ink.
        backgroundColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected)
                ? primary.withValues(alpha: OnoteAlpha.selectedStrong)
                : null),
        foregroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected)
                ? primary
                : s.contains(WidgetState.disabled)
                    ? surfaces.textDisabled
                    : surfaces.textPrimary),
      ),
    ),

    // ── Segmented controls ─────────────────────────────────────────────
    //
    // A sunk track with the chosen segment lifted off it as a bright pill —
    // the macOS control, not M3's row of outlined cells.
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        visualDensity: VisualDensity.compact,
        splashFactory: NoSplash.splashFactory,
        minimumSize:
            const WidgetStatePropertyAll(Size(0, OnoteSize.buttonCompact)),
        padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: OnoteSpace.x4)),
        textStyle: WidgetStatePropertyAll(
            OnoteType.caption.copyWith(fontWeight: FontWeight.w500)),
        // The chosen segment is filled with the accent so it reads as
        // selected at a glance; an unselected one sits quietly on the track.
        // (It was `surfaces.lift`, a half-step off `well` that was nearly
        // invisible — the owner could not tell which option was set.)
        side: WidgetStateProperty.resolveWith((s) => BorderSide(
            color: s.contains(WidgetState.selected) ? primary : surfaces.border)),
        shape: const WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: OnoteRadius.mdAll)),
        backgroundColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected) ? primary : surfaces.well),
        foregroundColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected)
                ? scheme.onPrimary
                : surfaces.textSecondary),
        overlayColor: WidgetStateProperty.resolveWith(overlayFor),
      ),
    ),

    // ── Menus (style guide §7a.1) ──────────────────────────────────────
    //
    // 36px rows and `raised` surfaces, against M3's taller mobile metrics.
    popupMenuTheme: PopupMenuThemeData(
      color: surfaces.raised,
      surfaceTintColor: Colors.transparent,
      elevation: 12,
      shadowColor: Colors.black.withValues(alpha: dark ? .6 : .22),
      textStyle: OnoteType.ui.copyWith(color: surfaces.textPrimary),
      shape: RoundedRectangleBorder(
        borderRadius: OnoteRadius.lgAll,
        side: BorderSide(color: surfaces.border),
      ),
      menuPadding: const EdgeInsets.symmetric(vertical: OnoteSpace.x3),
    ),
    menuTheme: MenuThemeData(
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(surfaces.raised),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        shadowColor: WidgetStatePropertyAll(
            Colors.black.withValues(alpha: dark ? .6 : .22)),
        elevation: const WidgetStatePropertyAll(12),
        padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(vertical: OnoteSpace.x3)),
        shape: WidgetStatePropertyAll(RoundedRectangleBorder(
          borderRadius: OnoteRadius.lgAll,
          side: BorderSide(color: surfaces.border),
        )),
      ),
    ),
    menuButtonTheme: MenuButtonThemeData(
      style: ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(Size(0, OnoteSize.menuRow)),
        padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: OnoteSpace.x5)),
        textStyle: const WidgetStatePropertyAll(OnoteType.ui),
        splashFactory: NoSplash.splashFactory,
        shape: const WidgetStatePropertyAll(RoundedRectangleBorder()),
        visualDensity: VisualDensity.compact,
        overlayColor: WidgetStateProperty.resolveWith(overlayFor),
      ),
    ),
    menuBarTheme: MenuBarThemeData(
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(surfaces.chrome),
        elevation: const WidgetStatePropertyAll(0),
      ),
    ),

    // ── Dialogs ────────────────────────────────────────────────────────
    dialogTheme: DialogThemeData(
      // Translucent, so the blurred page shows through — see
      // `showOnoteDialog`, which animates a BackdropFilter in behind it.
      // Not fully transparent: text on pure blur fails contrast the moment a
      // dark drawing passes underneath.
      backgroundColor: surfaces.raised.withValues(alpha: .88),
      surfaceTintColor: Colors.transparent,
      elevation: 8,
      shape: RoundedRectangleBorder(
        borderRadius: OnoteRadius.xlAll,
        side: BorderSide(color: surfaces.border),
      ),
      titleTextStyle: OnoteType.title.copyWith(color: surfaces.textPrimary),
      contentTextStyle: OnoteType.ui.copyWith(color: surfaces.textPrimary),
    ),

    // Date and time pickers are the planner's flagship interactions and were
    // the most obviously *mobile* surfaces in the app.
    datePickerTheme: DatePickerThemeData(
      backgroundColor: surfaces.raised,
      surfaceTintColor: Colors.transparent,
      elevation: 8,
      shape: RoundedRectangleBorder(
        borderRadius: OnoteRadius.xlAll,
        side: BorderSide(color: surfaces.border),
      ),
      headerBackgroundColor: surfaces.chrome2,
      headerForegroundColor: surfaces.textPrimary,
      headerHelpStyle: OnoteType.small.copyWith(color: surfaces.textSecondary),
      headerHeadlineStyle: OnoteType.title.copyWith(fontSize: 22),
      dayStyle: OnoteType.ui,
      weekdayStyle: OnoteType.caption.copyWith(color: surfaces.textSecondary),
      yearStyle: OnoteType.ui,
      dayShape: const WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: OnoteRadius.mdAll)),
    ),
    timePickerTheme: TimePickerThemeData(
      backgroundColor: surfaces.raised,
      elevation: 8,
      shape: RoundedRectangleBorder(
        borderRadius: OnoteRadius.xlAll,
        side: BorderSide(color: surfaces.border),
      ),
      helpTextStyle: OnoteType.small.copyWith(color: surfaces.textSecondary),
      dialTextStyle: OnoteType.ui,
      hourMinuteShape:
          const RoundedRectangleBorder(borderRadius: OnoteRadius.lgAll),
    ),

    // ── Toasts (style guide §7 Toasts) ─────────────────────────────────
    //
    // The single highest-leverage line in this file: 52 call sites were
    // rendering a full-window-width mobile slab to say "Saved".
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      width: 440,
      backgroundColor: dark ? OnoteColors.night200 : OnoteColors.graphite900,
      contentTextStyle: OnoteType.small
          .copyWith(color: dark ? OnoteColors.moon0 : OnoteColors.paper0),
      actionTextColor: dark ? OnoteColors.ink300 : OnoteColors.ink200,
      elevation: 6,
      shape: const RoundedRectangleBorder(borderRadius: OnoteRadius.lgAll),
      insetPadding: const EdgeInsets.all(OnoteSpace.x6),
    ),

    // ── Inputs & controls ──────────────────────────────────────────────
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      filled: true,
      fillColor: surfaces.well,
      contentPadding: OnoteSpace.control,
      border: restBorder,
      enabledBorder: restBorder,
      focusedBorder: focusBorder,
      hintStyle: OnoteType.ui.copyWith(color: surfaces.textSecondary),
      labelStyle: OnoteType.small.copyWith(color: surfaces.textSecondary),
      helperStyle: OnoteType.caption.copyWith(color: surfaces.textSecondary),
      errorStyle: OnoteType.caption.copyWith(color: OnoteColors.danger),
    ),
    checkboxTheme: CheckboxThemeData(
      side: BorderSide(color: surfaces.textSecondary, width: 1.4),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(4))),
      splashRadius: 0,
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    ),
    radioTheme: const RadioThemeData(
        splashRadius: 0, visualDensity: VisualDensity.compact),
    switchTheme: const SwitchThemeData(splashRadius: 0),
    chipTheme: ChipThemeData(
      backgroundColor: surfaces.chrome2,
      side: BorderSide(color: surfaces.border),
      labelStyle: OnoteType.small.copyWith(color: surfaces.textPrimary),
      padding: const EdgeInsets.symmetric(
          horizontal: OnoteSpace.x4, vertical: OnoteSpace.x1),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(OnoteRadius.full))),
    ),
    sliderTheme: SliderThemeData(
      trackHeight: 4,
      activeTrackColor: primary,
      inactiveTrackColor: surfaces.well,
      thumbColor: surfaces.lift,
      thumbShape: const RoundSliderThumbShape(
          enabledThumbRadius: 9, elevation: 2, pressedElevation: 3),
      overlayShape: SliderComponentShape.noOverlay,
      overlayColor: Colors.transparent,
    ),
    listTileTheme: ListTileThemeData(
      dense: true,
      minVerticalPadding: OnoteSpace.x3,
      titleTextStyle: OnoteType.ui.copyWith(color: surfaces.textPrimary),
      subtitleTextStyle:
          OnoteType.caption.copyWith(color: surfaces.textSecondary),
      shape: const RoundedRectangleBorder(borderRadius: OnoteRadius.mdAll),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: primary,
      linearMinHeight: 3,
      linearTrackColor: surfaces.chrome2,
    ),
    scrollbarTheme: ScrollbarThemeData(
      thickness: const WidgetStatePropertyAll(6),
      radius: const Radius.circular(OnoteRadius.full),
      thumbColor:
          WidgetStatePropertyAll(surfaces.textDisabled.withValues(alpha: .55)),
      crossAxisMargin: 3,
      mainAxisMargin: 3,
    ),
  );
}
