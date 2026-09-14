import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../theme/onote_theme.dart';
import '../theme/tokens.dart';

/// A translucent, blurred panel — the material floating surfaces are made of.
///
/// Used only for things that sit OVER the page: the focus palette, dialogs,
/// popovers. Glass reads as glass when there is something behind it to see;
/// on the command bar, which has the window frame behind it and text on it,
/// the same treatment costs legibility and buys nothing.
///
/// Three layers, and each is doing a job:
///  * the **blur** is what makes it glass rather than a tint;
///  * the **fill** is deliberately not fully transparent — text on pure blur
///    fails contrast the moment a dark drawing passes underneath;
///  * the **hairline** along the top edge is the specular highlight that
///    stops the panel reading as a flat rectangle. Light from above, so it is
///    on the top edge only.
class GlassPanel extends StatelessWidget {
  const GlassPanel({
    super.key,
    required this.child,
    required this.dark,
    this.radius = OnoteRadius.xl,
    this.padding = EdgeInsets.zero,
    this.opacity,
  });

  final Widget child;
  final bool dark;
  final double radius;
  final EdgeInsets padding;

  /// The fill's alpha. Null is the default glass; a popover over another
  /// sheet of glass wants more (`.88`), or it reads as part of the bar it
  /// opened from rather than a card above it.
  final double? opacity;

  @override
  Widget build(BuildContext context) {
    final r = BorderRadius.circular(radius);
    return ClipRRect(
      borderRadius: r,
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 28, sigmaY: 28),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            borderRadius: r,
            color: (dark ? OnoteColors.night50 : OnoteColors.paper50)
                .withValues(alpha: opacity ?? (dark ? .70 : .72)),
            border: Border.all(
              color: (dark ? Colors.white : Colors.black)
                  .withValues(alpha: dark ? .12 : .06),
            ),
            // Two shadows: a tight one that seats the panel and a wide soft
            // one that says how far above the page it floats.
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: dark ? .30 : .08),
                blurRadius: 4,
                offset: const Offset(0, 1),
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: dark ? .45 : .16),
                blurRadius: 32,
                offset: const Offset(0, 14),
              ),
            ],
          ),
          child: Stack(children: [
            child,
            // The highlight, drawn over the content rather than under it, so
            // it stays on the glass surface instead of behind whatever the
            // panel happens to contain.
            Positioned(
              left: radius,
              right: radius,
              top: 0,
              child: IgnorePointer(
                child: Container(
                  height: 1,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [
                      Colors.white.withValues(alpha: 0),
                      Colors.white.withValues(alpha: dark ? .26 : .9),
                      Colors.white.withValues(alpha: 0),
                    ]),
                  ),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Which edge of a bar carries its hairline.
enum ChromeEdge { top, bottom, none }

/// The glass the floating chrome is made of — the sheet the command bar, the
/// object row and the status bar sit on.
///
/// Real glass this time, because there is now something behind it: the canvas
/// is laid out under the bars (see [CanvasController.insets]) and the page
/// scrolls beneath them, the way content passes under a macOS toolbar. Three
/// things make it read as a material and not a tinted rectangle:
///  * the **blur**, with a little added saturation so what shows through
///    keeps its colour instead of greying out;
///  * a **fill** that is translucent but not thin — legibility of the text on
///    the bar comes first, and a dark drawing passing underneath must not
///    swallow a label;
///  * the **hairlines**: a specular line along the top where the light lands
///    and one on the edge that meets the page.
///
/// One sheet per stack of bars, not one per bar — a backdrop filter is paid
/// for per instance, and the bars share one.
class GlassSheet extends StatelessWidget {
  const GlassSheet({
    super.key,
    required this.child,
    this.edge = ChromeEdge.bottom,
  });

  final Widget child;

  /// The edge that meets the page: `bottom` for the top stack, `top` for the
  /// status bar.
  final ChromeEdge edge;

  /// Vibrancy: a touch more saturation on what shows through the blur.
  static const _saturate = ColorFilter.matrix(<double>[
    0.8967, 0.1533, -0.0500, 0, 0, //
    -0.1033, 1.1533, -0.0500, 0, 0, //
    -0.1033, 0.1533, 0.9500, 0, 0, //
    0, 0, 0, 1, 0,
  ]);

  @override
  Widget build(BuildContext context) {
    final s = context.surfaces;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final side = BorderSide(
        color: dark
            ? Colors.white.withValues(alpha: .08)
            : const Color(0xFF141E3C).withValues(alpha: .06));
    // The chrome role, so the accent's wash reaches the glass too.
    final tint = s.chrome;
    return ClipRect(
      child: BackdropFilter(
        filter: ui.ImageFilter.compose(
          outer: ui.ImageFilter.blur(
              sigmaX: 24, sigmaY: 24, tileMode: TileMode.mirror),
          inner: _saturate,
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                (dark ? tint : Colors.white)
                    .withValues(alpha: dark ? .66 : .62),
                (dark ? tint : Colors.white)
                    .withValues(alpha: dark ? .58 : .52),
              ],
            ),
            border: Border(
              top: edge == ChromeEdge.top ? side : BorderSide.none,
              bottom: edge == ChromeEdge.bottom ? side : BorderSide.none,
            ),
          ),
          child: Stack(fit: StackFit.passthrough, children: [
            child,
            // The specular edge — light from above.
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: IgnorePointer(
                child: Container(
                  height: 1,
                  color: Colors.white.withValues(alpha: dark ? .07 : .85),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

/// One bar within a [GlassSheet]: the command bar, the object row, the status
/// bar. It paints no material of its own — the sheet does that — only what
/// distinguishes it from its neighbours: an optional inset tint and a hairline
/// on the edge that meets the bar above or below.
///
/// Used on its own (tests, a bar outside any sheet) it is simply transparent,
/// which is the right answer there too.
class ChromeBar extends StatelessWidget {
  const ChromeBar({
    super.key,
    required this.child,
    this.edge = ChromeEdge.none,
    this.inset = false,
    this.height,
  });

  final Widget child;
  final ChromeEdge edge;

  /// Tint with the `chrome2` role — a band that sits *within* the chrome
  /// rather than being the chrome, like the object row.
  final bool inset;
  final double? height;

  @override
  Widget build(BuildContext context) {
    final s = context.surfaces;
    final side = BorderSide(color: s.border.withValues(alpha: .7));
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: inset ? s.chrome2.withValues(alpha: .55) : null,
        border: Border(
          top: edge == ChromeEdge.top ? side : BorderSide.none,
          bottom: edge == ChromeEdge.bottom ? side : BorderSide.none,
        ),
      ),
      child: child,
    );
  }
}

/// The room the cards float in: a very light ground with a faint ambient
/// glow — cool blue low on the left, a breath of pink high on the right, a
/// touch of lavender between. It is the same light `paintAmbient` puts on the
/// page, so the window and the paper share one atmosphere. Barely there by
/// design; the reference is a premium blank page, not a wallpaper.
class AmbientBackdrop extends StatelessWidget {
  const AmbientBackdrop({super.key});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return CustomPaint(painter: _AmbientPainter(dark: dark));
  }
}

class _AmbientPainter extends CustomPainter {
  const _AmbientPainter({required this.dark});
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
        Offset.zero & size,
        Paint()
          ..color = dark ? const Color(0xFF14151B) : const Color(0xFFF3F5FC));
    paintAmbient(canvas, Offset.zero & size, dark: dark, strength: 1.3);
  }

  @override
  bool shouldRepaint(covariant _AmbientPainter old) => old.dark != dark;
}

/// The ambient glow itself, painted into [rect]: three soft radial lights.
/// Shared by the window backdrop and the `ambient` paper so both agree.
/// The signature ambient wash and its variants. Each is the same three-glow
/// composition — a large glow bottom-left, a medium one top-right, a small one
/// up top — so they feel like one family; only the colours change. The default
/// `ambient` is unchanged. Variants are chosen as a page paper (`paper.dart`).
void paintAmbient(Canvas canvas, Rect rect,
    {required bool dark, double strength = 1, String variant = 'ambient'}) {
  void glow(Alignment at, double r, Color c, double a) {
    final centre = at.withinRect(rect);
    final radius = r * math.max(rect.width, rect.height);
    canvas.drawRect(
        rect,
        Paint()
          ..shader = ui.Gradient.radial(
            centre,
            radius,
            [
              c.withValues(alpha: (a * strength).clamp(0, 1)),
              c.withValues(alpha: 0)
            ],
            const [0, 1],
          ));
  }

  // Three (colour, alpha) pairs — bottom-left, top-right, top — per variant
  // and theme. The positions and radii are shared below.
  final ({int c, double a}) g0, g1, g2;
  switch (variant) {
    case 'ambient-sunset': // warm amber, rose, peach
      (g0, g1, g2) = dark
          ? ((c: 0x6E4A2A, a: .44), (c: 0x6E2A3A, a: .34), (c: 0x5A3A24, a: .18))
          : ((c: 0xFFD9A8, a: .55), (c: 0xFBC0C6, a: .48), (c: 0xFFE3C4, a: .28));
    case 'ambient-ocean': // teal, sky, aqua
      (g0, g1, g2) = dark
          ? ((c: 0x1F4A5A, a: .44), (c: 0x23415A, a: .34), (c: 0x1F5A50, a: .16))
          : ((c: 0xA8E0E6, a: .52), (c: 0xBFE0FF, a: .46), (c: 0xC6F0EA, a: .26));
    case 'ambient-forest': // green, moss, sage
      (g0, g1, g2) = dark
          ? ((c: 0x234A2E, a: .42), (c: 0x3A4A23, a: .30), (c: 0x1F4A34, a: .16))
          : ((c: 0xBFE6C2, a: .50), (c: 0xDCEBB8, a: .44), (c: 0xCFE8D2, a: .26));
    case 'ambient-dusk': // violet, magenta, indigo
      (g0, g1, g2) = dark
          ? ((c: 0x3A2E6E, a: .46), (c: 0x4A2A5A, a: .35), (c: 0x2E2A6E, a: .20))
          : ((c: 0xCBBFFF, a: .55), (c: 0xE9C4F0, a: .46), (c: 0xD9D3FF, a: .30));
    case 'ambient-aurora': // green, teal, violet
      (g0, g1, g2) = dark
          ? ((c: 0x1F5A4A, a: .40), (c: 0x2A3C7A, a: .34), (c: 0x4A2A5A, a: .20))
          : ((c: 0xB8F0D8, a: .50), (c: 0xC4D4FF, a: .46), (c: 0xE0C6F0, a: .28));
    default: // 'ambient' — the signature wash, unchanged
      (g0, g1, g2) = dark
          ? ((c: 0x2A3C7A, a: .45), (c: 0x5A2A52, a: .35), (c: 0x3A2E6E, a: .18))
          : ((c: 0xB9CFFF, a: .55), (c: 0xF7C9E0, a: .45), (c: 0xD9D3FF, a: .28));
  }

  glow(const Alignment(-1.1, 1.1), .75, Color(0xFF000000 | g0.c), g0.a);
  glow(const Alignment(1.1, -1.1), .65, Color(0xFF000000 | g1.c), g1.a);
  glow(const Alignment(-.2, -.9), .5, Color(0xFF000000 | g2.c), g2.a);
}

/// A floating glass card: the sidebar, popovers, anything with corners that
/// sits on the ambient backdrop rather than over the page. Same blur and
/// saturation as [GlassSheet]; a whiter, more luminous fill because the light
/// behind it is the room, not a drawing; a near-white hairline and two soft
/// shadow layers so it floats instead of sitting in a box.
class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.radius = OnoteRadius.xl,
    this.padding = EdgeInsets.zero,
    this.shadow = true,
  });

  final Widget child;
  final double radius;
  final EdgeInsets padding;
  final bool shadow;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final r = BorderRadius.circular(radius);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: r,
        boxShadow: shadow
            ? [
                BoxShadow(
                  color: const Color(0xFF1E2850)
                      .withValues(alpha: dark ? .35 : .08),
                  blurRadius: 40,
                  offset: const Offset(0, 10),
                ),
                BoxShadow(
                  color: const Color(0xFF1E2850)
                      .withValues(alpha: dark ? .25 : .04),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ]
            : null,
      ),
      child: ClipRRect(
        borderRadius: r,
        child: BackdropFilter(
          filter: ui.ImageFilter.compose(
            outer: ui.ImageFilter.blur(
                sigmaX: 20, sigmaY: 20, tileMode: TileMode.mirror),
            inner: GlassSheet._saturate,
          ),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              borderRadius: r,
              color: (dark ? OnoteColors.night50 : Colors.white)
                  .withValues(alpha: dark ? .58 : .58),
              border: Border.all(
                  color: (dark ? Colors.white : Colors.white)
                      .withValues(alpha: dark ? .10 : .70)),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}
