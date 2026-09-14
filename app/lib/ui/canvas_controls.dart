/// The canvas's own controls, floating in its top-right corner: zoom, fit,
/// focus mode, the sheet rail.
///
/// They belong to the canvas rather than to the View card because they are
/// about *how close you are* to the page you are looking at, and that is a
/// question you ask with your eyes on the page. Every action here is one that
/// already existed — `CanvasController.setZoom`, `AppState.fitPageToWidth`,
/// `setFocusMode`, `toggleSheetRail` — presented on one small sheet of glass.
library;

import 'package:flutter/material.dart';

import '../state/app_state.dart';
import '../theme/tokens.dart';
import 'glass.dart';

class CanvasControls extends StatelessWidget {
  const CanvasControls({super.key, required this.app});
  final AppState app;

  /// The zoom levels the menu offers. Fit is on the same menu because it is
  /// the answer most people want from a zoom control.
  static const levels = [50, 75, 100, 125, 150, 200];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final s = context.surfaces;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final paged = app.pageProps.isPaged;
    Widget div() => Container(
        width: 1,
        height: 16,
        margin: const EdgeInsets.symmetric(horizontal: OnoteSpace.x1),
        color: s.border);
    return Material(
      color: Colors.transparent,
      child: GlassPanel(
        dark: dark,
        radius: OnoteRadius.lg,
        opacity: dark ? .78 : .82,
        padding: const EdgeInsets.symmetric(horizontal: OnoteSpace.x1),
        child: AnimatedBuilder(
          animation: app.canvas,
          builder: (context, _) {
            final pct = (app.canvas.scale * 100).round();
            return Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(
                icon: const Icon(Icons.open_in_full, size: OnoteIcon.sm),
                tooltip: 'Focus mode: hide everything but the page, and float '
                    'the drawing tools.\nEsc comes back.',
                visualDensity: VisualDensity.compact,
                onPressed: () => app.setFocusMode(true),
              ),
              div(),
              IconButton(
                icon: const Icon(Icons.remove, size: OnoteIcon.sm),
                tooltip: 'Zoom out  (Ctrl+-)',
                visualDensity: VisualDensity.compact,
                onPressed: () => app.canvas.setZoom(app.canvas.scale / 1.2),
              ),
              // The number is the menu: click it for the levels, or Fit.
              MenuAnchor(
                builder: (context, controller, _) => TextButton(
                  style: TextButton.styleFrom(
                    minimumSize: const Size(56, OnoteSize.buttonCompact),
                    padding:
                        const EdgeInsets.symmetric(horizontal: OnoteSpace.x3),
                    foregroundColor: s.textPrimary,
                    textStyle:
                        OnoteType.small.copyWith(fontWeight: FontWeight.w600),
                  ),
                  onPressed: () => controller.isOpen
                      ? controller.close()
                      : controller.open(),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text('$pct%'),
                    Icon(Icons.expand_more, size: 14, color: s.textSecondary),
                  ]),
                ),
                menuChildren: [
                  for (final l in levels)
                    MenuItemButton(
                      trailingIcon: pct == l && !app.canvas.fitLocked
                          ? const Icon(Icons.check, size: 16)
                          : null,
                      onPressed: () => app.canvas.setZoom(l / 100),
                      child: Text('$l%'),
                    ),
                  const Divider(height: 1),
                  MenuItemButton(
                    leadingIcon:
                        const Icon(Icons.fit_screen_outlined, size: 16),
                    trailingIcon: app.canvas.fitLocked
                        ? const Icon(Icons.check, size: 16)
                        : null,
                    onPressed: app.fitPageToWidth,
                    child: const Text('Fit to width'),
                  ),
                ],
              ),
              IconButton(
                icon: const Icon(Icons.add, size: OnoteIcon.sm),
                tooltip: 'Zoom in  (Ctrl+=)',
                visualDensity: VisualDensity.compact,
                onPressed: () => app.canvas.setZoom(app.canvas.scale * 1.2),
              ),
              div(),
              // ONE fit button, and it fits the WIDTH — see `fitPageToWidth`.
              // Shown as ON while it is latched: a mode you cannot see is a
              // mode you blame the app for.
              IconButton(
                icon: const Icon(Icons.fit_screen_outlined, size: OnoteIcon.sm),
                tooltip: app.canvas.fitLocked
                    ? 'Fitted to the window width — horizontal scrolling is '
                        'off.\nZoom by hand to release it.'
                    : (paged
                        ? 'Zoom to fit — the ${app.pageProps.paper.name} '
                            'sheet, exactly the window width, no sideways '
                            'scrolling'
                        : 'Zoom to fit — the page, exactly the window width, '
                            'no sideways scrolling'),
                isSelected: app.canvas.fitLocked,
                color: app.canvas.fitLocked ? scheme.primary : null,
                visualDensity: VisualDensity.compact,
                onPressed: app.fitPageToWidth,
              ),
              if (paged)
                IconButton(
                  icon: const Icon(Icons.vertical_split_outlined,
                      size: OnoteIcon.sm),
                  tooltip: app.sheetRailOpen
                      ? 'Hide the page list'
                      : 'Show the page list down the right-hand edge',
                  isSelected: app.sheetRailOpen,
                  visualDensity: VisualDensity.compact,
                  onPressed: app.toggleSheetRail,
                ),
            ]);
          },
        ),
      ),
    );
  }
}
