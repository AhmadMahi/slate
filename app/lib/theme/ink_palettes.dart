/// A named set of ink colours — at most four, because that is how many a hand
/// keeps to and how many one cycling key can step round before it stops being
/// a shortcut.
class InkPalette {
  const InkPalette(this.name, this.colours);

  final String name;

  /// `#RRGGBB`, in the order they appear in the row.
  final List<String> colours;
}

/// The palettes offered in the picker.
///
/// Chosen for WRITING, not for decoration, and the constraint that shaped all
/// of them is the same: ink is thin. A colour that looks strong as a filled
/// swatch can be unreadable as a 2px line, so every one of these is picked at
/// a weight that still reads as a stroke — mid-to-dark on paper, and light
/// enough to carry on a dark page.
///
/// Four colours each, in a deliberate order: the one you write body text in
/// comes first, because that is the one the row opens on and the one
/// `cycleInkColor` returns to.
class InkPalettes {
  const InkPalettes._();

  /// Openote's own — graphite to write in, then the three marking colours
  /// that have meant the same thing in margins for a hundred years.
  static const classic = InkPalette('Classic', [
    '#211F1B', // graphite
    '#C63838', // red, for corrections
    '#2F6FB3', // blue, for notes
    '#2E8B57', // green, for ticks
  ]);

  /// For dark pages. The same four jobs at a lightness that survives being
  /// one pixel wide on near-black.
  static const night = InkPalette('Night', [
    '#E8E6E3',
    '#FF6B6B',
    '#63B3ED',
    '#68D391',
  ]);

  /// Ink and washes: what a fountain pen and two highlighters look like.
  /// Warmer than Classic, and gentler on a long page.
  static const ink = InkPalette('Ink', [
    '#2B3A55',
    '#8C3B4A',
    '#3E6B5A',
    '#B07D3B',
  ]);

  /// High contrast, for a projector or a shared screen, where a subtle
  /// colour is simply not transmitted.
  static const bold = InkPalette('Bold', [
    '#000000',
    '#E11D48',
    '#1D4ED8',
    '#047857',
  ]);

  /// Deuteranopia- and protanopia-safe: the red/green pair that carries most
  /// annotation is the pair most commonly confused, so this drops it for
  /// blue/orange, which nearly everyone separates.
  static const accessible = InkPalette('Colour-safe', [
    '#1A1A1A',
    '#0072B2',
    '#E69F00',
    '#CC79A7',
  ]);

  /// The owner's own row, restored after a preset overwrote it.
  ///
  /// Kept as a named palette rather than written straight into the settings
  /// file: a palette that exists in the picker can be switched back to, and
  /// switching away from it no longer loses it — applying anything now saves
  /// the outgoing row as "Previous" first.
  static const yours = InkPalette('Yours', [
    '#211F1B',
    '#8BF224',
    '#C63838',
    '#2E8B57',
  ]);

  static const presets = [yours, classic, night, ink, bold, accessible];
}
