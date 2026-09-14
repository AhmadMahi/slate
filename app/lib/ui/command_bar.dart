import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_selector/file_selector.dart';

import '../export/markdown_export.dart';
import '../export/open_export.dart';
import '../export/pdf_export.dart';
import '../export/pdf_vector_export.dart';
import '../export/print_page.dart';
import '../editor/list_editing.dart';
import '../markdown/md_syntax.dart';
import '../model/models.dart' show PaperSize;
import '../model/tags.dart';
import '../planner/agenda.dart';
import '../state/app_state.dart';
import '../study/study_stats.dart';
import '../theme/ink_palettes.dart';
import '../theme/onote_theme.dart';
import 'color_picker.dart';
import 'command_button.dart';
import 'compacting_toolbar.dart';
import 'font_picker.dart';
import 'insert_catalog.dart';
import 'object_face.dart';
import 'settings_dialog.dart';
import '../theme/tokens.dart';
import '../canvas/ink_painter.dart' show themedInk;
import '../canvas/paper.dart';
import 'glass.dart';
import 'onote_dialog.dart';
import 'object_row.dart' show BackgroundSpacingButton, WordCount;

/// The tabbed command bar (style guide §7 revised): Home · Insert · Draw ·
/// View. OneNote's few-clicks accessibility in Slate's calm language — a
/// slim tab row over a single command row of grouped icon buttons.
class CommandBar extends StatefulWidget {
  const CommandBar({super.key, required this.app});
  final AppState app;

  @override
  State<CommandBar> createState() => _CommandBarState();
}

class _CommandBarState extends State<CommandBar> {
  /// ONE toolbar, not four tabs. The drawing tools are inline — they are the
  /// things a hand reaches for a hundred times an hour — and the three other
  /// families each open from a labelled popover: **Format** (write), **Insert**
  /// (add), **View** (how the page and the app look). Nothing that was on a
  /// tab is gone; it is one click away instead of one tab away, and the row
  /// under your pointer never changes shape as you work.
  ///
  /// There was briefly a Maths tab that appeared while an equation was open
  /// and dragged the student onto it; the equation's palette is on the object
  /// row, where it arrives without moving anybody.

  AppState get app => widget.app;

  @override
  Widget build(BuildContext context) {
    return ChromeBar(
      child: Column(
        children: [
          // A little air above the toolbar so it does not crowd the top edge.
          const SizedBox(height: OnoteSpace.x5),
          // ── Header row: where you are, and the doors ──
          // Also the window's handle on macOS: drag it to move, double-click
          // to zoom, as the title bar it stands in for.
          SizedBox(
            height: 36,
            child: Row(
              children: [
                _breadcrumb(context),
                // **A badge, not a tab.** It says what the toolbar is
                // about and it cannot be pressed, so there is nothing here to
                // be moved onto and nothing to be moved back from.
                if (objectFaceOf(app) == ObjectFace.equation)
                  const _SubjectBadge(icon: Icons.functions, label: 'Equation'),
                // The trailing cluster COMPACTS rather than scrolling.
                //
                // Reported: "it doesnt handle resizing well (menus should
                // either compact as required or become sliding, again i
                // belive the former is cleaner)." A `Row` that overflows is
                // CLIPPED, and clipped pixels do not hit-test — so on a
                // narrow window (laptop + navigator open) the rightmost
                // buttons used to stop responding, and the horizontal-scroll
                // fix that followed traded that for "responds, but you can't
                // see it without scrolling first." `CompactingToolbar` folds
                // whatever does not fit into one "More" menu instead —
                // `alignment: end` keeps it flush against the window edge,
                // the one thing the scrolling version got right.
                Expanded(
                  child: CompactingToolbar(
                    alignment: MainAxisAlignment.end,
                    fillAvailable: true,
                    controls: [
                      // The "update to x.y" button used to sit here. It
                      // lives in Settings ▸ About now, at the owner's request:
                      // a toolbar is for the page, and a release notice is
                      // not about the page.
                      // Study: the due count is the whole nudge, so it's on the
                      // badge rather than hidden behind the panel.
                      ToolbarControl(
                        width: 40,
                        icon: Icons.school_outlined,
                        label: 'Study',
                        selected: app.showStudyPanel,
                        onPressed: app.toggleStudyPanel,
                        inline: _StudyButton(app: app),
                      ),
                      // The planner sits beside Study rather than in a menu:
                      // it is the other half of the same daily question, and
                      // the whole complaint it answers was that dates were
                      // reachable only from places you had to already be in.
                      ToolbarControl(
                        width: 40,
                        icon: Icons.event_note_outlined,
                        label: 'Planner',
                        selected: app.showPlannerPanel,
                        onPressed: app.togglePlannerPanel,
                        inline: _PlannerButton(app: app),
                      ),
                      ToolbarControl(
                        width: 40,
                        icon: Icons.label_outline,
                        label: 'Find tags',
                        selected: app.showTagsPanel,
                        onPressed: app.toggleTagsPanel,
                        inline: IconButton(
                          icon: const Icon(Icons.label_outline, size: 18),
                          tooltip: 'Find tags',
                          isSelected: app.showTagsPanel,
                          visualDensity: VisualDensity.compact,
                          onPressed: app.toggleTagsPanel,
                        ),
                      ),
                      ToolbarControl(
                        width: 40,
                        icon: Icons.toc,
                        label: 'Page outline',
                        selected: app.showTocPanel,
                        onPressed: app.toggleTocPanel,
                        inline: IconButton(
                          icon: const Icon(Icons.toc, size: 18),
                          tooltip: 'Page outline',
                          isSelected: app.showTocPanel,
                          visualDensity: VisualDensity.compact,
                          onPressed: app.toggleTocPanel,
                        ),
                      ),
                      ToolbarControl(
                        width: 40,
                        icon: Icons.account_tree_outlined,
                        label: 'Links & backlinks',
                        selected: app.showLinksPanel,
                        onPressed: app.toggleLinksPanel,
                        inline: IconButton(
                          icon:
                              const Icon(Icons.account_tree_outlined, size: 18),
                          tooltip: 'Links & backlinks',
                          isSelected: app.showLinksPanel,
                          visualDensity: VisualDensity.compact,
                          onPressed: app.toggleLinksPanel,
                        ),
                      ),
                      ToolbarControl(
                        width: 40,
                        icon: Icons.search,
                        label: 'Find on page',
                        selected: app.findOpen,
                        onPressed: app.toggleFind,
                        inline: IconButton(
                          icon: const Icon(Icons.search, size: 18),
                          tooltip: 'Find on page  (Ctrl+F)',
                          isSelected: app.findOpen,
                          visualDensity: VisualDensity.compact,
                          onPressed: app.toggleFind,
                        ),
                      ),
                      ToolbarControl(
                        width: 40,
                        icon: Icons.ios_share_outlined,
                        label: 'Export',
                        inline: MenuAnchor(
                          builder: (context, controller, _) => IconButton(
                            icon:
                                const Icon(Icons.ios_share_outlined, size: 18),
                            tooltip: 'Export page…',
                            visualDensity: VisualDensity.compact,
                            onPressed: () => controller.isOpen
                                ? controller.close()
                                : controller.open(),
                          ),
                          menuChildren: _exportMenuItems(context),
                        ),
                        submenu: [
                          ToolbarSubmenuItem(
                            icon: Icons.description_outlined,
                            label: 'Markdown (.md)',
                            onPressed: () =>
                                _export(context, exportPageMarkdown),
                          ),
                          // Vector by default: the shared/printed artefact
                          // should be searchable, selectable and small. The
                          // raster capture stays available for the rare page
                          // whose look matters more than its text.
                          ToolbarSubmenuItem(
                            icon: Icons.picture_as_pdf_outlined,
                            label: 'PDF (.pdf)',
                            onPressed: () =>
                                _export(context, exportPagePdfVector),
                          ),
                          ToolbarSubmenuItem(
                            icon: Icons.print_outlined,
                            label: 'Print…',
                            onPressed: () => printCurrentPage(app),
                          ),
                          ToolbarSubmenuItem(
                            icon: Icons.image_outlined,
                            label: 'PDF — picture of the page',
                            onPressed: () => _export(context, exportPagePdf),
                          ),
                          ToolbarSubmenuItem(
                            icon: Icons.hub_outlined,
                            label: 'For Obsidian Canvas (.canvas)',
                            onPressed: () =>
                                _export(context, exportPageJsonCanvas),
                          ),
                          ToolbarSubmenuItem(
                            icon: Icons.gesture,
                            label: 'Just the drawing (.inkml)',
                            onPressed: () => _export(context, exportPageInkML),
                          ),
                          // Say what lands on disk. "Materialize" is this
                          // codebase's own architecture vocabulary
                          // (`sync/materializer.dart`) and appears in no
                          // other user-visible string in the app.
                          ToolbarSubmenuItem(
                            icon: Icons.folder_zip_outlined,
                            label:
                                'Save the whole notebook as folders and files…',
                            onPressed: () => _exportWithProgress(
                                context,
                                'Saving the notebook…',
                                (report) => materializeNotebook(app,
                                    onProgress: (done, total) =>
                                        report('Page $done of $total…'))),
                          ),
                        ],
                      ),
                      // The one place to LOOK for a setting (PLANNING
                      // "Consistency/UX": centralised settings page).
                      ToolbarControl(
                        width: 40,
                        icon: Icons.settings_outlined,
                        label: 'Settings',
                        onPressed: () => showSettingsDialog(context, app),
                        inline: IconButton(
                          icon: const Icon(Icons.settings_outlined, size: 18),
                          tooltip: 'Settings…',
                          visualDensity: VisualDensity.compact,
                          onPressed: () => showSettingsDialog(context, app),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // ── The toolbar ──
          // Horizontally scrollable so a narrow window scrolls the controls
          // instead of throwing a RenderFlex overflow (style guide §7). A
          // horizontal `Scrollable` reads `scrollDelta.dx`, which a mouse
          // wheel does not produce — `_ToolbarScroll` is what makes a wheel
          // move it.
          //
          // Not on Home or a notebook overview: there is no page under the
          // pointer for a pen to draw on, and a row of greyed tools over a
          // dashboard is noise. The header row stays, so the doors do.
          if (!app.navHome && !app.navNotebook)
            Container(
              height: 44,
              alignment: Alignment.centerLeft,
              child: ScrollConfiguration(
                behavior: const _ToolbarScroll(),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(children: [
                    ..._undoRedo(context),
                    const _Div(),
                    // The other three families, one click away each, and
                    // FIRST so they are reachable on any window width — the
                    // tools after them are the row that may scroll. Labelled,
                    // because a popover is a place and a place has a name; the
                    // tools are actions and keep their icons.
                    _Popover(
                      icon: Icons.text_format,
                      label: 'Format',
                      tooltip: 'Text formatting — bold, headings, lists, '
                          'tags, colour, font',
                      app: app,
                      maxWidth: 640,
                      builder: (context) => Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        runSpacing: OnoteSpace.x3,
                        children: _formatTools(context),
                      ),
                    ),
                    // The catalogue WRAPS onto rows rather than compacting into
                    // a "More" menu: a popover is a place with room, and every
                    // item with its word is the shape the owner asked for.
                    _Popover(
                      icon: Icons.add_box_outlined,
                      label: 'Insert',
                      tooltip: 'Insert — text box, image, table, code, '
                          'equation and more',
                      app: app,
                      maxWidth: 720,
                      builder: (context) => Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: OnoteSpace.x1,
                        runSpacing: OnoteSpace.x3,
                        children: [
                          for (final item in kInsertRibbon)
                            _InsertButton(app: app, item: item),
                        ],
                      ),
                    ),
                    _Popover(
                      icon: Icons.tune,
                      label: 'View',
                      tooltip: 'View — paper, pattern, page size, zoom, '
                          'light or dark',
                      app: app,
                      maxWidth: 620,
                      builder: (context) => Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        runSpacing: OnoteSpace.x3,
                        children: _viewTools(context),
                      ),
                    ),
                    const _Div(),
                    ..._drawTools(context),
                  ]),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Where you are: notebook › section › page. Context, not a second
  /// navigator — one line that names the place, the way a window title does.
  Widget _breadcrumb(BuildContext context) {
    final s = context.surfaces;
    final page = app.pageId == null ? null : app.node(app.pageId!);
    final section = page == null ? null : app.node(page.parentId ?? '');
    final notebook =
        app.notebooks.where((n) => n.id == app.notebookId).firstOrNull;
    final dim = OnoteType.small.copyWith(color: s.textSecondary);
    final sep = Padding(
      padding: const EdgeInsets.symmetric(horizontal: OnoteSpace.x3),
      child: Icon(Icons.chevron_right, size: 14, color: s.textDisabled),
    );
    final here = OnoteType.small
        .copyWith(color: s.textPrimary, fontWeight: FontWeight.w600);
    // Home and the notebook overview are places too, and the crumb says so.
    if (app.navHome) {
      return Padding(
        padding: const EdgeInsets.only(left: OnoteSpace.x6),
        child: Text('Home', style: here),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(left: OnoteSpace.x6),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (notebook != null)
          Text(notebook.title, style: app.navNotebook ? here : dim),
        if (!app.navNotebook) ...[
          if (section != null) ...[sep, Text(section.title, style: dim)],
          if (page != null) ...[
            sep,
            Text(page.title.isEmpty ? 'Untitled page' : page.title,
                style: here),
          ],
        ],
      ]),
    );
  }

  List<Widget> _undoRedo(BuildContext context) => [
        IconButton(
          icon: const Icon(Icons.undo, size: 18),
          tooltip: 'Undo  (Ctrl+Z)',
          visualDensity: VisualDensity.compact,
          onPressed: app.canUndo ? app.undo : null,
        ),
        IconButton(
          icon: const Icon(Icons.redo, size: 18),
          tooltip: 'Redo  (Ctrl+Y)',
          visualDensity: VisualDensity.compact,
          onPressed: app.canRedo ? app.redo : null,
        ),
      ];

  /// Every item in the Export menu comes through here.
  ///
  /// **The failure has a face.** There was no `try`: a full disk, a read-only
  /// USB stick, an offline OneDrive folder or a filename the OS refuses threw
  /// into an unhandled Future and, with no global handler in the app, into a
  /// console no student will ever read. The menu closed, nothing happened, and
  /// they believed the work they were about to hand in was on the desktop.
  ///
  /// The messenger is taken BEFORE the await, because by the time the write
  /// fails the menu route that owned the context is gone.
  /// An export long enough to need a face, with a live count on it.
  ///
  /// The same shape as the PDF import's dialog: modal and undismissable while
  /// it runs, because half a written folder tree is not a thing anybody wants
  /// to be given quietly.
  Future<void> _exportWithProgress(
    BuildContext context,
    String opening,
    Future<String?> Function(void Function(String) report) fn,
  ) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final progress = ValueNotifier<String>(opening);
    var open = true;
    unawaited(showOnoteDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        content: Row(children: [
          const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.6)),
          const SizedBox(width: 16),
          Expanded(
            child: ValueListenableBuilder<String>(
              valueListenable: progress,
              builder: (_, text, __) => Text(text),
            ),
          ),
        ]),
      ),
    ).then((_) => open = false));
    String? path;
    Object? failed;
    try {
      path = await fn((text) => progress.value = text);
    } catch (e) {
      failed = e;
    }
    if (open && context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
      open = false;
    }
    progress.dispose();
    if (failed != null) {
      messenger?.showSnackBar(SnackBar(
        content: Text("That couldn't be saved: $failed"),
        duration: const Duration(seconds: 6),
      ));
      return;
    }
    if (path != null) {
      messenger?.showSnackBar(SnackBar(content: Text('Exported to $path')));
    }
  }

  /// The Export menu's own items — pulled out so the inline `MenuAnchor`
  /// (shown while there's room) and the folded `ToolbarSubmenuItem` list
  /// (shown once Export itself has to fold into the command bar's own
  /// "More" menu) can share one definition rather than drifting apart.
  List<Widget> _exportMenuItems(BuildContext context) => [
        MenuItemButton(
          leadingIcon: const Icon(Icons.description_outlined, size: 18),
          onPressed: () => _export(context, exportPageMarkdown),
          child: const Text('Markdown (.md)'),
        ),
        // Vector by default: the shared/printed artefact should be
        // searchable, selectable and small. The raster capture stays
        // available for the rare page whose look matters more than its text.
        MenuItemButton(
          leadingIcon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
          onPressed: () => _export(context, exportPagePdfVector),
          child: const Text('PDF (.pdf)'),
        ),
        MenuItemButton(
          leadingIcon: const Icon(Icons.print_outlined, size: 18),
          shortcut:
              const SingleActivator(LogicalKeyboardKey.keyP, control: true),
          onPressed: () => printCurrentPage(app),
          child: const Text('Print…'),
        ),
        MenuItemButton(
          leadingIcon: const Icon(Icons.image_outlined, size: 18),
          onPressed: () => _export(context, exportPagePdf),
          child: const Text('PDF — picture of the page'),
        ),
        MenuItemButton(
          leadingIcon: const Icon(Icons.hub_outlined, size: 18),
          onPressed: () => _export(context, exportPageJsonCanvas),
          child: const Text('For Obsidian Canvas (.canvas)'),
        ),
        MenuItemButton(
          leadingIcon: const Icon(Icons.gesture, size: 18),
          onPressed: () => _export(context, exportPageInkML),
          child: const Text('Just the drawing (.inkml)'),
        ),
        const Divider(height: 6),
        MenuItemButton(
          leadingIcon: const Icon(Icons.folder_zip_outlined, size: 18),
          onPressed: () => _exportWithProgress(
              context,
              'Saving the notebook…',
              (report) => materializeNotebook(app,
                  onProgress: (done, total) =>
                      report('Page $done of $total…'))),
          // Say what lands on disk. "Materialize" is this codebase's own
          // architecture vocabulary (`sync/materializer.dart`) and appears
          // in no other user-visible string in the app.
          child: const Text('Save the whole notebook as folders and files…'),
        ),
      ];

  Future<void> _export(
      BuildContext context, Future<String?> Function(AppState) fn) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      final path = await fn(app);
      if (path != null) {
        messenger?.showSnackBar(SnackBar(content: Text('Exported to $path')));
      }
    } catch (e) {
      messenger?.showSnackBar(SnackBar(
        content: Text("That couldn't be saved: $e"),
        duration: const Duration(seconds: 6),
      ));
    }
  }

  // ── HOME: history + text formatting ──────────────────────────────────

  List<Widget> _formatTools(BuildContext context) {
    // Enable from state, not child build order (fixes the greyed-out bug).
    final canFormat = app.canFormatText;
    // What is switched ON at the caret. With the markers collapsed to nothing
    // in the editor, these buttons are the ONLY thing that can tell a student
    // whether the word they are in is already bold — "just have it appear in
    // the toolbar as on" was the whole request.
    final active = app.marksAtCaret();
    Widget fmt(IconData icon, String tip, VoidCallback fn, [MdInline? mark]) =>
        IconButton(
          icon: Icon(icon, size: 18),
          tooltip: tip,
          visualDensity: VisualDensity.compact,
          isSelected: mark != null && active.contains(mark),
          onPressed: canFormat ? fn : null,
        );
    final lcv = int.tryParse(app.lastColor, radix: 16) ?? 0;
    final curColor = app.lastColor.length == 8
        ? Color(((lcv & 0xFF) << 24) | (lcv >> 8))
        : Color(0xFF000000 | lcv);
    return [
      // **The row never changes shape.** An earlier revision collapsed the
      // formatting commands to three group heads when nothing was focused, on
      // the reasoning that a wall of greyed glyphs reads as broken. That traded
      // one problem for a worse one: clicking into a text box made ~15 buttons
      // appear and shoved everything to their right across the toolbar, so the
      // control you were reaching for moved out from under the pointer at the
      // exact moment you started using the app. Layout that moves while you aim
      // at it is a harder failure than layout that looks quiet.
      //
      // So: "disabled ≠ hidden" (§7a.2) applies without exception here. Every
      // command holds its position always; the ones that need a caret are
      // greyed, and the hint at the end of the row — which only ever appears
      // AFTER the last control, so it displaces nothing — says why.
      fmt(Icons.format_bold, 'Bold  (Ctrl+B)', () => app.wrapSelection('**'),
          MdInline.bold),
      fmt(Icons.format_italic, 'Italic  (Ctrl+I)', () => app.wrapSelection('*'),
          MdInline.italic),
      fmt(Icons.format_underlined, 'Underline  (Ctrl+U)',
          () => app.wrapSelection('++'), MdInline.underline),
      fmt(Icons.strikethrough_s, 'Strikethrough', () => app.wrapSelection('~~'),
          MdInline.strike),
      fmt(Icons.code, 'Inline code', () => app.wrapSelection('`'),
          MdInline.code),
      fmt(Icons.border_color, 'Highlight', () => app.wrapSelection('=='),
          MdInline.highlight),
      const _Div(),
      fmt(Icons.title, 'Heading 1', () => app.toggleLinePrefix('# ')),
      _TextBtn('H2', canFormat, () => app.toggleLinePrefix('## ')),
      _TextBtn('H3', canFormat, () => app.toggleLinePrefix('### ')),
      const _Div(),
      fmt(Icons.format_list_bulleted, 'Bullet list',
          () => app.toggleList(ListKind.bullet)),
      fmt(Icons.format_list_numbered, 'Numbered list',
          () => app.toggleList(ListKind.numbered)),
      fmt(Icons.check_box_outlined, 'Checkbox',
          () => app.toggleList(ListKind.checkbox)),
      fmt(Icons.format_quote, 'Quote', () => app.toggleLinePrefix('> ')),
      const _Div(),
      // Tags (TEXT-5). OneNote users organise around these, so they get a
      // first-class place on Home rather than a submenu. The button shows the
      // caret line's active tags, which is why it reads state on every build.
      _TagButton(app: app),
      _MakeCardButton(app: app),
      const _Div(),
      // Text colour — split button (§7a.2): main area applies the current
      // colour; the arrow opens the full picker (palette/wheel/RGBA).
      Tooltip(
        message: 'Apply text colour',
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: canFormat ? () => app.applyTextColor(app.lastColor) : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.format_color_text,
                  size: 18,
                  color: canFormat ? null : context.surfaces.textSecondary),
              Container(
                  width: 18,
                  height: 3,
                  margin: const EdgeInsets.only(top: 1),
                  color: canFormat ? curColor : context.surfaces.textSecondary),
            ]),
          ),
        ),
      ),
      InkWell(
        borderRadius: BorderRadius.circular(4),
        onTap: canFormat
            ? () async {
                final hex = await showOnoteColorPicker(context, app,
                    initial: app.lastColor);
                if (hex != null) app.applyTextColor(hex);
              }
            : null,
        child: Icon(Icons.arrow_drop_down,
            size: 18, color: canFormat ? null : context.surfaces.textSecondary),
      ),
      // Font — opens the searchable system-font picker.
      IconButton(
        icon: const Icon(Icons.font_download_outlined, size: 18),
        tooltip: 'Text font…',
        visualDensity: VisualDensity.compact,
        onPressed: canFormat
            ? () async {
                final f = await showFontPicker(context,
                    current:
                        app.activeEditor?.block.content['font'] as String?);
                if (f != null) app.setActiveBlockFont(f);
              }
            : null,
      ),
      // Font size (TEXT-1). Points, because that's how people think about type
      // and how OneNote/Word present it; stored as 120-dpi px.
      _FontSizeField(app: app, enabled: canFormat),
      if (!canFormat) ...[
        const SizedBox(width: 10),
        Text('Click into a text box to format',
            style:
                TextStyle(fontSize: 11, color: context.surfaces.textSecondary)),
      ],
    ];
  }

  // ── INSERT ────────────────────────────────────────────────────────────

  /// **Insert renders the catalog** — the same list the canvas's right-click
  /// menu renders, so the two cannot say different things.
  ///
  /// Three groups separated by the bar's own hairline. No printed captions:
  /// only this tab would need them, and a command row that is taller on one
  /// tab than the others moves the layout under your pointer as you switch.
  /// **One row, thirteen buttons, each with its word** — the shape this row
  /// has always had, restored at the owner's request after a release that
  /// split it into three groups and took the words off four of them.
  ///
  /// The grouping did not go away: it is what the right-click menu shows as
  /// three short columns, which is a shape a menu can carry and a row cannot.
  /// [kRibbonOrder] is the row's own order, and a test pins it against the
  /// catalog so the two cannot drift.

  /// Pick a colour, and add it to the row.
  Future<void> _addColour(BuildContext context) async {
    final picked = await showOnoteColorPicker(context, app,
        initial: '#2F6FB3',
        title: app.tool == Tool.highlighter
            ? 'New highlighter colour'
            : 'New pen colour');
    if (picked == null) return;
    app.addInkColor(picked.startsWith('#') ? picked : '#$picked');
  }

  /// Ask for one key, and bind it to [t].
  Future<void> _setToolShortcut(
      BuildContext context, Tool t, String label) async {
    final chosen = await showToolShortcutDialog(
      context,
      // The tooltip carries the shortcut and a hint; the name is the first
      // line up to the first double space.
      label: label.split('  ').first,
      current: app.toolShortcut(t),
    );
    if (chosen == null) return;
    app.setToolShortcut(t, chosen);
  }

  /// The View tab: how the page looks, and how the app looks.
  ///
  /// Restored from the pre-`f36408c` bar. Two changes from what it was: the
  /// background buttons gained the spacing control beside them, and the
  /// contents are otherwise the same set of things a student actually reaches
  /// for — including the light/dark switch, which is the one people hunt for
  /// first and the one burying it in Settings hid hardest.
  List<Widget> _viewTools(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget bg(String v, IconData icon, String tip) => IconButton(
          icon: Icon(icon, size: 18),
          tooltip: 'Background: $tip',
          isSelected: app.pageProps.background == v,
          visualDensity: VisualDensity.compact,
          color: app.pageProps.background == v ? scheme.primary : null,
          onPressed: () => app.setBackground(v),
        );
    final paged = app.pageProps.isPaged;
    // The row reads left to right in the order you decide things: the
    // paper, then the sheet, then how close you are to it, then the room
    // it is in. Each group behind its own hairline.
    return [
      // ── The paper ──────────────────────────────────────────────────────
      // The sheet itself first, then what is printed on it. White, grey,
      // cream, a paper grain, or a picture of your own; per page, like the
      // pattern beside it. Lit in the accent when it is anything but white,
      // so a page on odd paper says so from the bar.
      PopupMenuButton<String>(
        tooltip: 'Paper: ${paperLabel(app.pageProps.paperKind)}',
        icon: Icon(Icons.layers_outlined,
            size: 18,
            color: app.pageProps.paperKind != 'white' ? scheme.primary : null),
        onSelected: (v) =>
            v == 'image' ? _pickPaperImage(context) : app.setPaper(v),
        itemBuilder: (_) => [
          for (final p in kPapers.where((p) => p != 'image'))
            CheckedPopupMenuItem(
              value: p,
              checked: app.pageProps.paperKind == p,
              child: Text(paperLabel(p)),
            ),
          const PopupMenuDivider(),
          CheckedPopupMenuItem(
            value: 'image',
            checked: app.pageProps.paperKind == 'image',
            child: Text(app.pageProps.paperKind == 'image'
                ? 'Choose another picture…'
                : 'Picture…'),
          ),
        ],
      ),
      bg('blank', Icons.crop_din, 'blank'),
      bg('grid', Icons.grid_4x4, 'grid'),
      bg('dotted', Icons.apps, 'dotted'),
      bg('ruled', Icons.notes, 'ruled'),
      // How far apart that pattern is drawn — dot gap, ruled line height,
      // grid square. Only with a pattern up; on a blank page it controls
      // nothing.
      if (app.pageProps.background != 'blank')
        BackgroundSpacingButton(app: app),
      const _Div(),
      // ── The sheet: open canvas, or pages of a size ──────────────────
      // Canvas or paper. Per page, not per notebook: one notebook holds the
      // lecture you scribble on and the essay you hand in, and making you
      // choose once for both is why people keep two apps.
      IconButton(
        icon: Icon(paged ? Icons.description : Icons.dashboard_customize,
            size: 18),
        tooltip: paged
            ? 'Page mode: ${app.pageProps.paper.name}'
                '${app.pageProps.landscape ? ' landscape' : ''} '
                '— click for canvas'
            : 'Canvas mode: boundless — click for pages',
        isSelected: paged,
        visualDensity: VisualDensity.compact,
        color: paged ? scheme.primary : null,
        onPressed: () => app.setPageLayout(paged ? 'canvas' : 'paged'),
      ),
      if (paged)
        PopupMenuButton<String>(
          tooltip: 'Paper size',
          icon: const Icon(Icons.aspect_ratio, size: 18),
          onSelected: (v) => v == '_rotate'
              ? app.setPageLayout('paged', landscape: !app.pageProps.landscape)
              : app.setPageLayout('paged', paper: v),
          itemBuilder: (_) => [
            for (final p in PaperSize.all)
              CheckedPopupMenuItem(
                value: p.name,
                checked: app.pageProps.paperSize == p.name,
                child: Text(p.name),
              ),
            const PopupMenuDivider(),
            CheckedPopupMenuItem(
              value: '_rotate',
              checked: app.pageProps.landscape,
              child: const Text('Landscape'),
            ),
          ],
        ),
      // The page list, zoom, fit and focus all live on the canvas controls
      // now — see `CanvasControls` — where the page they act on is in view,
      // so none of them is repeated on this toolbar.
      const _Div(),
      // ── Helpers while you work ─────────────────────────────────────────
      IconButton(
        icon: Icon(app.snapToGrid ? Icons.grid_goldenratio : Icons.grid_off,
            size: 18),
        tooltip: app.snapToGrid
            ? 'Snap to grid: ON (grid shows while dragging)'
            : 'Snap to grid: OFF — free placement',
        isSelected: app.snapToGrid,
        visualDensity: VisualDensity.compact,
        color: app.snapToGrid ? scheme.primary : null,
        onPressed: app.toggleSnap,
      ),
      // Spell check (TEXT-11). English-only in this release; the toggle exists
      // because a wordlist checker WILL flag jargon and proper nouns, and the
      // answer to that has to be one click away.
      Tooltip(
        message: 'Underline misspelled words while editing (English)',
        child: IconButton(
          icon: const Icon(Icons.spellcheck, size: 18),
          isSelected: app.spellCheckEnabled,
          visualDensity: VisualDensity.compact,
          color: app.spellCheckEnabled ? scheme.primary : null,
          onPressed: () => app.setSpellCheck(!app.spellCheckEnabled),
        ),
      ),
      const _Div(),
      // ── The room: light or dark ────────────────────────────────────
      // Light / dark. The reason this tab is back: it is the first thing
      // anyone looks for and it had no visible home at all.
      SegmentedButton<ThemeMode>(
        showSelectedIcon: false,
        style: const ButtonStyle(
            visualDensity: VisualDensity.compact,
            textStyle: WidgetStatePropertyAll(TextStyle(fontSize: 11))),
        segments: const [
          ButtonSegment(value: ThemeMode.system, label: Text('Auto')),
          ButtonSegment(value: ThemeMode.light, label: Text('Light')),
          ButtonSegment(value: ThemeMode.dark, label: Text('Dark')),
        ],
        selected: {app.themeMode},
        onSelectionChanged: (s) => app.setThemeMode(s.first),
      ),
      const _Div(),
      // Followed the page controls here when the object row emptied out, so
      // that emptying the row did not quietly delete a feature.
      WordCount(app: app),
    ];
  }

  /// Pick a picture for the paper, store it as a blob, and set it.
  Future<void> _pickPaperImage(BuildContext context) async {
    final f = await openFile(acceptedTypeGroups: const [
      XTypeGroup(
          label: 'Pictures',
          extensions: ['png', 'jpg', 'jpeg', 'webp', 'gif', 'bmp'])
    ]);
    if (f == null) return;
    final bytes = await f.readAsBytes();
    final ext = f.name.split('.').last.toLowerCase();
    final mime = f.mimeType ??
        switch (ext) {
          'png' => 'image/png',
          'webp' => 'image/webp',
          'gif' => 'image/gif',
          'bmp' => 'image/bmp',
          _ => 'image/jpeg',
        };
    final hash = app.addBlob(bytes, mime);
    app.setPaper('image', image: hash);
  }

  List<Widget> _drawTools(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Right-click any tool to give it a key of your own. The eraser is the
    // one that prompted this — E is taken by nothing else, but a hand that
    // lives on the left of the board does not want to reach for it — and
    // doing it for every tool costs nothing and avoids the question "why only
    // the eraser?".
    Widget toolButton(Tool t, IconData icon, String tip) {
      final key = app.toolShortcut(t);
      return GestureDetector(
        onSecondaryTap: () => _setToolShortcut(context, t, tip),
        onLongPress: () => _setToolShortcut(context, t, tip),
        child: IconButton(
          icon: Icon(icon, size: 18),
          tooltip: '$tip'
              '${key.isEmpty ? '' : '  ·  ${key.toUpperCase()}'}'
              '\nRight-click to set your own key',
          isSelected: app.tool == t,
          visualDensity: VisualDensity.compact,
          style: IconButton.styleFrom(
            backgroundColor:
                app.tool == t ? scheme.primary.withValues(alpha: .14) : null,
            foregroundColor: app.tool == t ? scheme.primary : null,
          ),
          onPressed: () => app.setTool(t),
        ),
      );
    }

    // The swatches also appear with ink selected, so a lassoed diagram can be
    // recoloured without first re-picking the pen.
    // The arrow is in this list because it draws in the pen's colour and
    // weight — the row it needs is the row the pen needs.
    final inkActive = app.tool == Tool.pen ||
        app.tool == Tool.highlighter ||
        app.tool == Tool.arrow ||
        app.tool == Tool.rectangle ||
        app.hasInkSelection;
    // One palette, from state. These wells are CONTENTS, not constants: the
    // selected one reopens as an editor (below), which is what makes the row
    // a Notability-style switcher rather than six fixed buttons.
    final colors = [
      for (final h in app.inkPalette)
        onoteColorFromHex(h) ?? OnoteColors.graphite900
    ];
    return [
      toolButton(Tool.select, Icons.near_me_outlined, 'Select / move  (V)'),
      toolButton(Tool.text, Icons.text_fields, 'Text  (T)'),
      toolButton(Tool.pen, Icons.edit_outlined, 'Pen  (P)'),
      toolButton(
          Tool.highlighter, Icons.border_color_outlined, 'Highlighter  (H)'),
      toolButton(Tool.eraser, Icons.cleaning_services_outlined, 'Eraser  (E)'),
      toolButton(Tool.lasso, Icons.gesture_outlined, 'Lasso-select ink'),
      toolButton(Tool.arrow, Icons.north_east,
          'Arrow  (A) — drag; the head lands where you let go'),
      toolButton(Tool.rectangle, Icons.crop_square,
          'Rectangle  (R) — drag one corner to the opposite one'),
      toolButton(
          Tool.space,
          Icons.unfold_more,
          'Insert space — drag to push '
          'everything below down'),
      const _Div(),
      // Auto shapes (INK-10). A toggle rather than a mode: you keep drawing
      // with the pen you already have, and a circle comes out round.
      Tooltip(
        message: 'Auto shapes: a drawn circle, box, triangle or line is '
            'tidied into a real one.\nAnything it cannot read confidently is '
            'left exactly as you drew it.',
        child: IconButton(
          icon: const Icon(Icons.category_outlined, size: 18),
          isSelected: app.autoShape,
          visualDensity: VisualDensity.compact,
          style: IconButton.styleFrom(
            backgroundColor:
                app.autoShape ? scheme.primary.withValues(alpha: .14) : null,
            foregroundColor: app.autoShape ? scheme.primary : null,
          ),
          onPressed: () => app.setAutoShape(!app.autoShape),
        ),
      ),
      const _Div(),
      if (inkActive) ...[
        for (final (i, c) in colors.indexed)
          _ColorWell(
            color: c,
            index: i,
            selected: app.penColor == i,
            app: app,
          ),
        // Add a colour, until the row is full. Hidden rather than disabled at
        // the ceiling: a control that is permanently greyed out is furniture.
        if (colors.length < AppState.maxPaletteColours)
          IconButton(
            icon: const Icon(Icons.add_circle_outline, size: 16),
            tooltip: 'Add a colour to this palette',
            visualDensity: VisualDensity.compact,
            onPressed: () => _addColour(context),
          ),
        // The ready-made palettes, and a way to keep your own.
        _PalettePicker(app: app),
        const SizedBox(width: 6),
        SizedBox(
          width: 110,
          child: Slider(
            value: app.penSize.clamp(AppState.minPenSize, AppState.maxPenSize),
            min: AppState.minPenSize,
            max: AppState.maxPenSize,
            // 36 steps of 0.25 — fine enough that the slider still feels
            // continuous, coarse enough that the number beside it is one you
            // could deliberately return to.
            divisions: 36,
            onChanged: app.setPenSize,
          ),
        ),
        // The number, because a width you cannot read is a width you cannot
        // get back to. Fixed width so the row does not shuffle as it changes.
        SizedBox(
          width: 26,
          child: Text(
            app.penSize.toStringAsFixed(app.penSize % 1 == 0 ? 0 : 2),
            textAlign: TextAlign.right,
            style:
                TextStyle(fontSize: 11, color: context.surfaces.textSecondary),
          ),
        ),
      ] else if (app.tool == Tool.eraser) ...[
        SegmentedButton<EraserMode>(
          segments: [
            for (final m in EraserMode.values)
              ButtonSegment(
                  value: m,
                  label: Text(m.label, style: const TextStyle(fontSize: 11))),
          ],
          selected: {app.eraserMode},
          onSelectionChanged: (s) => app.setEraserMode(s.first),
          showSelectedIcon: false,
          style: const ButtonStyle(
              visualDensity: VisualDensity.compact,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap),
        ),
        const SizedBox(width: 8),
        Text(
            app.eraserMode == EraserMode.area
                ? 'Splits strokes where you rub'
                : 'Removes any stroke you touch',
            style:
                TextStyle(fontSize: 11, color: context.surfaces.textSecondary)),
      ] else if (app.tool == Tool.lasso)
        Text('Draw a loop around ink to select it — then drag or delete',
            style:
                TextStyle(fontSize: 11, color: context.surfaces.textSecondary))
      else
        Text('Pick the pen or highlighter to draw',
            style:
                TextStyle(fontSize: 11, color: context.surfaces.textSecondary)),
      // NO `Spacer` here, and none in any command row. Every row is built
      // inside a horizontal `SingleChildScrollView`, which offers unbounded
      // width — and a flex child (`Spacer` is `Expanded`) under an unbounded
      // constraint is a hard layout assertion, not a soft one. The Draw row
      // therefore failed to lay out *at all*: no pen, no highlighter, no
      // eraser, nothing clickable. Push things apart with a fixed gap.
      const SizedBox(width: 12),
      // Touch drawing (INK-1). Exposed because the right answer depends on
      // hardware we can't detect reliably: "Auto" suits a pen-and-touch
      // convertible, "Always" a touch-only tablet, "Never" anyone who rests a
      // hand on the glass while thinking.
      const _Div(),
      Tooltip(
        message: 'Draw with your finger.\nAuto: a finger draws until you use '
            'the pen, then touch pans so your palm can\'t mark the page.\n'
            'Two fingers always pan and zoom.',
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.touch_app_outlined,
              size: 16, color: context.surfaces.textSecondary),
          const SizedBox(width: 4),
          DropdownButtonHideUnderline(
            child: DropdownButton<TouchDrawing>(
              value: app.touchDrawing,
              isDense: true,
              style: TextStyle(fontSize: 11, color: scheme.onSurface),
              items: [
                for (final v in TouchDrawing.values)
                  DropdownMenuItem(value: v, child: Text(v.label)),
              ],
              onChanged: (v) => v == null ? null : app.setTouchDrawing(v),
            ),
          ),
        ]),
      ),
      const _Div(),
      // Pen proximity → pen tool. On by default because it is what a pen
      // means; the toggle exists for people who use the pen as a pointer.
      IconButton(
        icon: const Icon(Icons.draw_outlined, size: 18),
        tooltip: 'Bringing the pen near the page switches to inking.\n'
            'Pick another tool while the pen hovers and it sticks until the\n'
            'pen leaves and comes back. The pen\'s tail (or its barrel\n'
            'button, held while drawing) erases.',
        visualDensity: VisualDensity.compact,
        isSelected: app.penProximitySwitch,
        onPressed: () => app.setPenProximitySwitch(!app.penProximitySwitch),
      ),
      // Focus mode lives on the canvas controls now (top-right of the page),
      // not repeated here.
    ];
  }
}

/// `H2` / `H3` on the Home row.
///
/// Thin wrapper over [CommandTextButton] so the call sites keep their
/// positional shorthand; the colours and metrics come from the shared control,
/// which is what stops the two heading buttons rendering in the accent while
/// the bold/italic icons beside them render in ink.
class _TextBtn extends StatelessWidget {
  const _TextBtn(this.label, this.enabled, this.onTap);
  final String label;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => CommandTextButton(
        label: label,
        onPressed: enabled ? onTap : null,
      );
}

class _Div extends StatelessWidget {
  const _Div();
  @override
  Widget build(BuildContext context) => Container(
        width: 1,
        height: 16,
        margin: const EdgeInsets.symmetric(horizontal: OnoteSpace.x3),
        color: context.surfaces.border,
      );
}

/// Font-size control for the text block being edited (TEXT-1).
///
/// A dropdown of the sizes people actually use, plus the current value shown
/// even when it came from an import — OneNote pages carry per-box sizes, and
/// before this there was no way to see or change them.
class _FontSizeField extends StatelessWidget {
  const _FontSizeField({required this.app, required this.enabled});
  final AppState app;
  final bool enabled;

  static const _sizes = <double>[
    8,
    9,
    10,
    11,
    12,
    14,
    16,
    18,
    20,
    24,
    28,
    36,
    48
  ];

  @override
  Widget build(BuildContext context) {
    // Stored px → pt for display; null means "the theme default".
    final px = app.activeBlockFontSize;
    final pt = px == null ? null : px * 72.0 / 120.0;
    final label = pt == null
        ? '–'
        : (pt % 1 == 0 ? pt.toStringAsFixed(0) : pt.toStringAsFixed(1));
    return Tooltip(
      message: enabled
          ? 'Text size (points)'
          : 'Click into a text box to change its size',
      child: MenuAnchor(
        builder: (context, controller, _) => InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: enabled
              ? () => controller.isOpen ? controller.close() : controller.open()
              : null,
          child: Container(
            constraints: const BoxConstraints(minWidth: 44),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
            margin: const EdgeInsets.symmetric(horizontal: 2),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                  color: enabled
                      ? Theme.of(context).colorScheme.outline
                      : Colors.transparent),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(label,
                  style: TextStyle(
                      fontSize: 12,
                      color: enabled ? null : context.surfaces.textSecondary)),
              Icon(Icons.arrow_drop_down,
                  size: 16,
                  color: enabled ? null : context.surfaces.textSecondary),
            ]),
          ),
        ),
        menuChildren: [
          MenuItemButton(
            onPressed: () => app.setActiveBlockFontSize(null),
            child: const Text('Default'),
          ),
          for (final s in _sizes)
            MenuItemButton(
              onPressed: () => app.setActiveBlockFontSize(s),
              child: Text('${s.toStringAsFixed(0)} pt'),
            ),
        ],
      ),
    );
  }
}

/// The tag button on Home: applies a tag to the caret's line, and shows which
/// tags that line already carries.
///
/// A menu rather than a row of buttons because the set is open-ended (nine
/// built-ins plus, later, user-defined ones) and the toolbar is already dense.
class _TagButton extends StatelessWidget {
  const _TagButton({required this.app});
  final AppState app;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final active = app.tagsAtCaret();
    final enabled = app.canFormatText;
    return MenuAnchor(
      builder: (context, controller, _) => Tooltip(
        message: active.isEmpty
            ? 'Tag this line (To Do, Important, Question…)'
            : 'Tagged: ${active.map((k) => k.label).join(', ')}',
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: enabled
              ? () => controller.isOpen ? controller.close() : controller.open()
              : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(active.isEmpty ? Icons.label_outline : active.first.icon,
                  size: 18,
                  color: !enabled
                      ? context.surfaces.textSecondary
                      : active.isEmpty
                          ? null
                          : active.first.color),
              Icon(Icons.arrow_drop_down,
                  size: 16,
                  color: enabled ? null : context.surfaces.textSecondary),
            ]),
          ),
        ),
      ),
      menuChildren: [
        for (final k in TagKind.pickable)
          MenuItemButton(
            leadingIcon: Icon(k.icon, size: 16, color: k.color),
            trailingIcon: active.contains(k)
                ? Icon(Icons.check, size: 16, color: scheme.primary)
                : null,
            onPressed: () => app.toggleTagOnSelection(k),
            child: Text(k.label),
          ),
        // Dating a tag belongs here, beside applying one — a deadline you could
        // only set from a separate panel would be a feature most people never
        // found, and the line you want to date is the line you are on.
        if (active.isNotEmpty) ...[
          const Divider(height: 1),
          MenuItemButton(
            leadingIcon: const Icon(Icons.event_outlined, size: 16),
            onPressed: () => _setDue(context),
            child:
                Text(_dueOfCaret() == null ? 'Due date…' : 'Change due date…'),
          ),
          if (_dueOfCaret() != null)
            MenuItemButton(
              leadingIcon: const Icon(Icons.event_busy_outlined, size: 16),
              onPressed: _clearDue,
              child: const Text('Clear the due date'),
            ),
        ],
      ],
    );
  }

  /// The dated tag on the caret's line, if any. One date per line rather than
  /// one per tag: a line tagged both To Do and Important has one deadline, and
  /// asking which of the two icons owns it is a question nobody wants.
  NoteTag? _dueOfCaret() {
    final b = app.caretBlock();
    if (b == null) return null;
    final line = app.caretLineIndex();
    for (final t in NoteTag.listFrom(b.content)) {
      if (t.line == line && t.due != null) return t;
    }
    return null;
  }

  Future<void> _setDue(BuildContext context) async {
    final b = app.caretBlock();
    if (b == null) return;
    final line = app.caretLineIndex();
    final tags = [
      for (final t in NoteTag.listFrom(b.content))
        if (t.line == line) t
    ];
    if (tags.isEmpty) return;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final existing = _dueOfCaret()?.dueDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: existing != null && !existing.isBefore(today)
          ? existing
          : DateTime(today.year, today.month, today.day + 7),
      firstDate: DateTime(today.year, today.month, today.day - 365),
      lastDate: DateTime(today.year + 5, today.month, today.day),
      helpText: 'Due date',
      confirmText: 'Set',
    );
    if (picked == null) return;
    // Onto the first tag on the line, and any other dated tag there is cleared,
    // so the line keeps exactly one deadline however it was tagged.
    app.setTagDue(b.id, line, tags.first.kind, picked);
    for (final t in tags.skip(1)) {
      if (t.due != null) app.setTagDue(b.id, line, t.kind, null);
    }
  }

  void _clearDue() {
    final b = app.caretBlock();
    if (b == null) return;
    final line = app.caretLineIndex();
    for (final t in NoteTag.listFrom(b.content)) {
      if (t.line == line && t.due != null) {
        app.setTagDue(b.id, line, t.kind, null);
      }
    }
  }
}

/// One button that turns the caret's line into a flashcard.
///
/// Tags remain the underlying mechanism — a card is a *view* of a tagged line,
/// which is what makes editing the note edit the card. But "tag it Question or
/// Definition, and remember which one, and get the shape right" is a rule the
/// student has to learn before anything happens, and getting it wrong produced
/// nothing with no explanation. This reads the line, picks the tag, and says
/// what it did.
class _MakeCardButton extends StatelessWidget {
  const _MakeCardButton({required this.app});
  final AppState app;

  void _say(BuildContext context, String? msg) {
    if (msg == null || !context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), duration: const Duration(seconds: 3)));
  }

  @override
  Widget build(BuildContext context) {
    // **Never disabled.** With a caret on a line it turns THAT line into a
    // card, which is the good form; with no caret it makes a new card in a
    // box of its own. That second behaviour used to be a separate Insert
    // ribbon entry with the same icon, on a different tab, doing a different
    // thing — one button, two ways of arriving at it.
    final onLine = app.canFormatText;
    return MenuAnchor(
      builder: (context, controller, _) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Tooltip(
            message: onLine ? 'Make this line a flashcard' : 'New flashcard',
            child: InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap: () {
                if (onLine) {
                  _say(context, app.makeCardAtCaret());
                } else {
                  app.insertFlashcard();
                }
              },
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 6, vertical: 5),
                child: Icon(Icons.style_outlined, size: 18),
              ),
            ),
          ),
          InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: () =>
                controller.isOpen ? controller.close() : controller.open(),
            child: const Icon(Icons.arrow_drop_down, size: 16),
          ),
        ],
      ),
      menuChildren: [
        MenuItemButton(
          leadingIcon: Icon(TagKind.question.icon,
              size: 16, color: TagKind.question.color),
          shortcut:
              const SingleActivator(LogicalKeyboardKey.digit3, control: true),
          onPressed: () => app.toggleTagOnSelection(TagKind.question),
          child: const Text('Question card'),
        ),
        MenuItemButton(
          leadingIcon: Icon(TagKind.definition.icon,
              size: 16, color: TagKind.definition.color),
          shortcut:
              const SingleActivator(LogicalKeyboardKey.digit5, control: true),
          onPressed: () => app.toggleTagOnSelection(TagKind.definition),
          child: const Text('Definition card'),
        ),
        MenuItemButton(
          leadingIcon: const Icon(Icons.format_underlined, size: 16),
          onPressed: () {
            if (!app.blankOutSelection()) {
              _say(context, 'Select the words to blank out first.');
            }
          },
          child: const Text('Blank out selection'),
        ),
        const Divider(height: 8),
        MenuItemButton(
          leadingIcon: const Icon(Icons.school_outlined, size: 16),
          onPressed: () {
            if (!app.showStudyPanel) app.toggleStudyPanel();
          },
          child: const Text('Open study panel'),
        ),
      ],
    );
  }
}

/// Study button with a due badge.
///
/// The count is the feature's entire nudge — "12 due" the week before an exam
/// is what turns notes into revision, and a bare icon says nothing.
class _StudyButton extends StatelessWidget {
  const _StudyButton({required this.app});
  final AppState app;

  /// How close an exam has to be before the badge changes colour. A week is
  /// when revision stops being a good intention, and it keeps the accent rare
  /// enough to still mean something when it appears.
  static const _urgentDays = 7;

  @override
  Widget build(BuildContext context) {
    final (due, total) = app.study.deckCounts(sectionId: app.activeSectionId);
    // Read from the date map and the counts already in hand — deliberately not
    // through `examPlanFor`, which would walk the deck a second time on a
    // widget that rebuilds with every keystroke.
    final exam = app.study.examDate(app.activeSectionId);
    final daysLeft = exam == null ? null : daysBetween(DateTime.now(), exam);
    final urgent =
        daysLeft != null && daysLeft >= 0 && daysLeft <= _urgentDays && due > 0;
    final countdown = daysLeft == null || daysLeft < 0
        ? ''
        : ' · exam ${formatCountdown(daysLeft)}';
    return Tooltip(
      message: total == 0
          ? 'Study — tag a line Question or Definition to make a card'
          : '$due of $total card${total == 1 ? '' : 's'} due in this section'
              '$countdown',
      child: Stack(clipBehavior: Clip.none, children: [
        IconButton(
          icon: const Icon(Icons.school_outlined, size: 18),
          isSelected: app.showStudyPanel,
          visualDensity: VisualDensity.compact,
          onPressed: app.toggleStudyPanel,
        ),
        if (due > 0)
          Positioned(
            right: 2,
            top: 2,
            child: IgnorePointer(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  // Brass once the exam is inside a week. Colour never carries
                  // this alone (style guide §3.5) — the tooltip says how many
                  // days, and the count itself is unchanged.
                  color: urgent
                      ? OnoteColors.brass500
                      : Theme.of(context).colorScheme.primary,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('$due',
                    style: TextStyle(
                        fontSize: 11,
                        height: 1.2,
                        fontWeight: FontWeight.w700,
                        color: urgent
                            ? Colors.white
                            : Theme.of(context).colorScheme.onPrimary)),
              ),
            ),
          ),
      ]),
    );
  }
}

/// Opens the planner, and says what is on today without opening it.
///
/// The badge counts **today's and overdue** rows, not everything dated. A
/// number that included next month's exam would be permanently non-zero, and a
/// badge that is always lit stops being read — the same reasoning that keeps
/// the study badge on cards *due* rather than on the whole deck.
class _PlannerButton extends StatelessWidget {
  const _PlannerButton({required this.app});
  final AppState app;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final sections = app.planner.sections(now: now);
    var count = 0;
    var overdue = false;
    for (final s in sections) {
      if (s.bucket == AgendaBucket.overdue) {
        overdue = true;
        count += s.items.length;
      } else if (s.bucket == AgendaBucket.today) {
        count += s.items.length;
      }
    }
    final alerts = app.planner.pendingAlerts.length;
    return Tooltip(
      message: alerts > 0
          ? '$alerts reminder${alerts == 1 ? '' : 's'} waiting'
          : count == 0
              ? 'Planner — every date you have, in one place'
              : overdue
                  ? 'Planner — $count today or overdue'
                  : 'Planner — $count today',
      child: Stack(clipBehavior: Clip.none, children: [
        IconButton(
          icon: const Icon(Icons.event_note_outlined, size: 18),
          isSelected: app.showPlannerPanel,
          visualDensity: VisualDensity.compact,
          onPressed: app.togglePlannerPanel,
        ),
        if (count > 0 || alerts > 0)
          Positioned(
            right: 2,
            top: 2,
            child: IgnorePointer(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  // Red only for something already late; a waiting reminder is
                  // brass, and an ordinary "3 today" is the primary accent.
                  // Colour never carries this alone (style guide §3.5) — the
                  // tooltip says which it is.
                  color: overdue
                      ? OnoteColors.danger
                      : alerts > 0
                          ? OnoteColors.brass500
                          : Theme.of(context).colorScheme.primary,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('${alerts > 0 ? alerts : count}',
                    style: TextStyle(
                        fontSize: 11,
                        height: 1.2,
                        fontWeight: FontWeight.w700,
                        color: overdue || alerts > 0
                            ? Colors.white
                            : Theme.of(context).colorScheme.onPrimary)),
              ),
            ),
          ),
      ]),
    );
  }
}

/// One entry on the Insert ribbon, and its arrow when it has one.
///
/// Generic, because the catalog is: the PDF import used to be a hand-built
/// split button and everything else a plain one, so an item that grew a
/// second choice needed a new widget. Now it needs a list entry.
class _InsertButton extends StatelessWidget {
  const _InsertButton({required this.app, required this.item});

  final AppState app;
  final InsertItem item;

  Future<void> _run(BuildContext context, InsertItem which) =>
      which.run(context, app, insertAnchor(app, which));

  /// What a hover says. A labelled command adds only what the label does not
  /// already carry; a wordless one leads with its name, so nothing on the row
  /// is nameless.
  String get _tip {
    if (item.showLabel) return item.tooltip ?? '';
    return item.tooltip == null
        ? item.label
        : '${item.label} — ${item.tooltip}';
  }

  /// The button itself.
  ///
  /// [menu] is the split button's own drop-down, and pressing the main half
  /// closes it first: a file picker opening BEHIND a menu that is still
  /// sitting on top of it reads as the button having done nothing. The
  /// hand-built PDF button this replaced closed it by hand; the generic one
  /// dropped the call, for every split item at once.
  Widget _main(BuildContext context, [MenuController? menu]) {
    void press() {
      if (menu != null && menu.isOpen) menu.close();
      _run(context, item);
    }

    return Tooltip(
      message: _tip,
      child: item.showLabel
          ? CommandButton(
              icon: item.icon,
              label: item.label,
              onPressed: press,
            )
          : IconButton(
              icon: Icon(item.icon, size: OnoteIcon.sm),
              visualDensity: VisualDensity.compact,
              onPressed: press,
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Two pixels, not four. The run measured 970px against the 965 a 1280
    // window leaves once the navigator is open, and five pixels is the
    // difference between "Page window" being on screen and being a scroll
    // away — which, for the least familiar entry on the row, is the
    // difference between existing and not.
    const gap = EdgeInsets.only(right: 2);
    if (item.extras.isEmpty) {
      return Padding(
        padding: gap,
        child: _main(context),
      );
    }
    return Padding(
      padding: gap,
      child: MenuAnchor(
        builder: (context, controller, _) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _main(context, controller),
            InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap: () =>
                  controller.isOpen ? controller.close() : controller.open(),
              // A bare 16px icon leaves most of the row's height as dead
              // space around it; sized to the row so the arrow is hittable.
              child: const SizedBox(
                width: 22,
                height: 34,
                child: Icon(Icons.arrow_drop_down, size: 16),
              ),
            ),
          ],
        ),
        menuChildren: [
          for (final extra in item.extras)
            MenuItemButton(
              leadingIcon: Icon(extra.icon, size: 16),
              onPressed: () => _run(context, extra),
              child: Text(extra.label),
            ),
        ],
      ),
    );
  }
}

/// Lets the toolbar row be dragged and wheel-scrolled when it is wider than
/// the window. Flutter's default behaviour excludes mouse and trackpad from
/// drag scrolling, and a horizontal viewport ignores a vertical wheel.
class _ToolbarScroll extends MaterialScrollBehavior {
  const _ToolbarScroll();

  @override
  Set<PointerDeviceKind> get dragDevices => const {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.stylus,
      };
}

/// **What the object row is about**, shown where the contextual tab used to
/// be — and deliberately not a tab.
///
/// A pill, because the token file reserves the full radius for badges and no
/// other control in the bar is that shape. No `InkWell`, no `onTap`, no
/// underline ever: it cannot be pressed, so it cannot be misread as a fifth
/// tab, and the ambiguity is removed by removing the behaviour rather than by
/// styling around it.
class _SubjectBadge extends StatelessWidget {
  const _SubjectBadge({required this.icon, required this.label});

  final IconData icon;

  /// Always a NOUN — the thing itself. Never a verb, never "mode", never
  /// "tools".
  final String label;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return ExcludeFocus(
      child: Padding(
        padding: const EdgeInsets.only(left: 6),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 1, height: 18, color: context.surfaces.border),
          const SizedBox(width: 6),
          Tooltip(
            message: 'Esc when you are done',
            child: Container(
              height: 22,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(OnoteRadius.full),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(icon, size: 14, color: accent),
                const SizedBox(width: 4),
                Text(label,
                    style: OnoteType.caption
                        .copyWith(fontWeight: FontWeight.w600, color: accent)),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}

/// One colour well in the Draw row — the Notability switching model.
///
/// The rule that makes it feel different from six radio buttons: **double-
/// clicking a well opens it for editing.** So the row is both the switcher
/// and the way in to any colour at all, and neither costs a separate button.
/// Before this, the six built-ins were the only colours ink could be without
/// drawing a stroke and recolouring it afterwards.
///
/// The rest of the model, for the same reason — reaching a colour should not
/// need the mouse at all:
///  * **1…6** arms a well while a drawing tool is up (`app_shell`).
///  * **`[` / `]`** step to the previous / next well, wrapping.
///  * **long-press / right-click** opens the editor without arming first.
class _ColorWell extends StatefulWidget {
  const _ColorWell({
    required this.color,
    required this.index,
    required this.selected,
    required this.app,
  });

  final Color color;
  final int index;
  final bool selected;
  final AppState app;

  @override
  State<_ColorWell> createState() => _ColorWellState();
}

class _ColorWellState extends State<_ColorWell> {
  /// When this well was last clicked, for the hand-rolled double-click.
  ///
  /// NOT `InkWell.onDoubleTap`: adding a double-tap recogniser makes the
  /// single tap wait out the double-tap window before it fires, so every
  /// colour change would arrive ~300 ms late. That is precisely the lag this
  /// row exists to remove. Detecting it by timestamp keeps the first click
  /// instant and still catches the second.
  DateTime? _lastTap;
  static const _doubleTapWindow = Duration(milliseconds: 350);

  Color get color => widget.color;
  int get index => widget.index;
  bool get selected => widget.selected;
  AppState get app => widget.app;

  Future<void> _edit(BuildContext context) async {
    final picked = await showOnoteColorPicker(
      context,
      app,
      initial: app.inkPalette[index],
      title: app.tool == Tool.highlighter ? 'Highlighter colour' : 'Pen colour',
    );
    if (picked == null) return;
    app.setInkPaletteColor(index, picked.startsWith('#') ? picked : '#$picked');
    // A well edited while ink is lassoed recolours it too, for the same
    // reason arming one does: recolouring after the fact is most of why you
    // lasso a diagram (INK-7).
    if (app.hasInkSelection) app.recolorSelectedInk(app.inkPalette[index]);
  }

  void _arm() {
    app.setPenColor(index);
    // With ink selected (typically just lassoed), a colour click recolours it
    // rather than only arming the next stroke — recolouring after the fact is
    // most of why you lasso a diagram (INK-7).
    if (app.hasInkSelection) app.recolorSelectedInk(app.inkPalette[index]);
  }

  /// Where this well is on screen, for anchoring its menu.
  Offset _wellCentre(BuildContext context) {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return Offset.zero;
    return box.localToGlobal(box.size.bottomLeft(Offset.zero));
  }

  /// Right-click / long-press a well: edit it, or take it out of the row.
  Future<void> _wellMenu(BuildContext context, Offset at) async {
    final canRemove = app.inkPalette.length > 1;
    final choice = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(at.dx, at.dy, at.dx, at.dy),
      items: [
        const PopupMenuItem(
            value: 'edit', height: 36, child: Text('Change colour…')),
        PopupMenuItem(
          value: 'remove',
          height: 36,
          // The last colour cannot go: a pen with no colour is not a state
          // anything downstream is written to handle.
          enabled: canRemove,
          child: Text(canRemove
              ? 'Remove from palette'
              : 'Remove — the last colour has to stay'),
        ),
      ],
    );
    if (!context.mounted || choice == null) return;
    if (choice == 'edit') {
      await _edit(context);
    } else if (choice == 'remove') {
      app.removeInkColor(index);
    }
  }

  void _tap(BuildContext context) {
    final now = DateTime.now();
    final prev = _lastTap;
    if (prev != null && now.difference(prev) < _doubleTapWindow) {
      _lastTap = null;
      _edit(context);
      return;
    }
    _lastTap = now;
    _arm();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Tooltip(
        message: 'Ink colour ${index + 1}'
            '\nDouble-click to change it, right-click to remove it',
        child: InkWell(
          borderRadius: BorderRadius.circular(99),
          onTap: () => _tap(context),
          // `onLongPress` carries no position, so the menu is anchored on the
          // well itself — which is where it should open anyway.
          onLongPress: () => _wellMenu(context, _wellCentre(context)),
          onSecondaryTapDown: (d) => _wellMenu(context, d.globalPosition),
          child: Padding(
            // The ring sits OUTSIDE the colour rather than on it, so a well
            // reads as the same colour armed or not. A border drawn over the
            // swatch shrinks it, and the selected colour then looks like a
            // slightly different colour from the one you picked.
            padding: const EdgeInsets.all(3),
            child: Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                // The well shows the colour the stroke will be DRAWN in on
                // this theme, so a white well on a light page reads as the
                // black it will produce.
                color: themedInk(color,
                    dark: Theme.of(context).brightness == Brightness.dark),
                shape: BoxShape.circle,
                border: Border.all(
                  width: 1,
                  color: Colors.black.withValues(alpha: .22),
                ),
                boxShadow: selected
                    ? [
                        BoxShadow(
                          color: scheme.primary,
                          spreadRadius: 2.5,
                        ),
                      ]
                    : null,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The palette picker: five ready-made rows, plus whatever you have saved.
///
/// A drop-down rather than more swatches in the bar. The bar's job is the
/// four colours you are using; choosing a different four is a decision you
/// make occasionally, and occasional decisions belong behind one click rather
/// than in the row you are aiming at all day.
class _PalettePicker extends StatelessWidget {
  const _PalettePicker({required this.app});

  final AppState app;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<Object>(
      tooltip: 'Colour palettes',
      icon: const Icon(Icons.palette_outlined, size: 18),
      position: PopupMenuPosition.under,
      onSelected: (v) {
        if (v is InkPalette) {
          app.applyInkPalette(v);
        } else if (v == 'random') {
          app.applyRandomPalette();
        } else if (v == 'save') {
          _savePalette(context);
        } else if (v == 'reset') {
          _reset(context);
        }
      },
      itemBuilder: (context) => [
        // A fresh, distinct, theme-visible row every time it is chosen.
        const PopupMenuItem<Object>(
          value: 'random',
          height: 40,
          child: Row(children: [
            Icon(Icons.shuffle, size: 16),
            SizedBox(width: 10),
            Text('Random colours', style: TextStyle(fontSize: 13)),
          ]),
        ),
        const PopupMenuDivider(),
        for (final p in app.allPalettes)
          PopupMenuItem<Object>(
            value: p,
            height: 40,
            child: Row(children: [
              // The colours themselves, because the NAME of a palette is not
              // what anyone chooses on.
              for (final hex in p.colours)
                Container(
                  width: 16,
                  height: 16,
                  margin: const EdgeInsets.only(right: 5),
                  decoration: BoxDecoration(
                    color: onoteColorFromHex(hex),
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: Colors.black.withValues(alpha: .22), width: 1),
                  ),
                ),
              const SizedBox(width: 8),
              Expanded(
                  child: Text(p.name, style: const TextStyle(fontSize: 13))),
              if (app.activePaletteName == p.name)
                const Padding(
                  padding: EdgeInsets.only(right: 2),
                  child: Icon(Icons.check, size: 16),
                ),
              // Delete sits ON the palette it removes, and only for the ones
              // you made; the built-ins are the floor you can always get back
              // to. Tapping it closes the menu and removes that palette.
              if (app.customPalettes.any((c) => c.name == p.name))
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 16),
                  tooltip: 'Delete “${p.name}”',
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 28, minHeight: 28),
                  onPressed: () {
                    Navigator.of(context).pop();
                    app.deleteCustomPalette(p.name);
                  },
                ),
            ]),
          ),
        const PopupMenuDivider(),
        const PopupMenuItem<Object>(
          value: 'save',
          height: 36,
          child: Row(children: [
            Icon(Icons.bookmark_add_outlined, size: 16),
            SizedBox(width: 10),
            Text('Save these colours as a palette…',
                style: TextStyle(fontSize: 13)),
          ]),
        ),
        const PopupMenuItem<Object>(
          value: 'reset',
          height: 36,
          child: Row(children: [
            Icon(Icons.restart_alt, size: 16),
            SizedBox(width: 10),
            Text('Reset palettes', style: TextStyle(fontSize: 13)),
          ]),
        ),
      ],
    );
  }

  /// Reset asks first: it throws away every palette the user saved, and that
  /// is not something a menu click should be able to do silently.
  Future<void> _reset(BuildContext context) async {
    final ok = await showOnoteDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reset palettes?'),
        content: Text(
          app.customPalettes.isEmpty
              ? 'The colours go back to the built-in set.'
              : 'The colours go back to the built-in set, and the '
                  '${app.customPalettes.length} palette'
                  '${app.customPalettes.length == 1 ? '' : 's'} you saved '
                  'are deleted.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Reset')),
        ],
      ),
    );
    if (ok == true) app.resetPalettes();
  }

  Future<void> _savePalette(BuildContext context) async {
    final name = await promptForText(
      context,
      title: 'Name this palette',
      okLabel: 'Save',
      hintText: 'Revision, Marking, Diagrams…',
    );
    if (name == null || name.isEmpty) return;
    app.addCustomPalette(name, List<String>.from(app.inkPalette));
  }
}

/// A labelled button that opens one family of controls on a floating glass
/// card under itself.
///
/// The card is the size of what it holds (up to [maxWidth]; the contents
/// wrap), its left edge sits on the button's left edge, and it is nudged
/// inward only when the window edge would cut it — so it reads as THIS
/// button's panel and not as another bar across the window. Its own overlay
/// rather than a `MenuAnchor`: a menu is a list of items, and what opens here
/// is a toolbar. Positioned by a layout delegate from the button's rectangle,
/// not a `CompositedTransformFollower`: a follower layer makes the paint
/// transform of everything inside it "unreliable", which is exactly what a
/// dropdown inside the panel needs in order to open. Clicking anywhere
/// outside closes it; the panel rebuilds with the app so a control that greys
/// out when the caret leaves a box does so here too.
class _Popover extends StatefulWidget {
  const _Popover({
    required this.icon,
    required this.label,
    required this.tooltip,
    required this.app,
    required this.builder,
    this.maxWidth = 640,
  });

  final IconData icon;
  final String label;
  final String tooltip;
  final AppState app;
  final WidgetBuilder builder;
  final double maxWidth;

  @override
  State<_Popover> createState() => _PopoverState();
}

class _PopoverState extends State<_Popover> {
  final _ctl = OverlayPortalController();

  // The controller is not a Listenable in this Flutter, so the button's own
  // open/closed look is kept in sync by hand.
  void _toggle() => setState(() => _ctl.isShowing ? _ctl.hide() : _ctl.show());
  void _close() {
    if (_ctl.isShowing) setState(_ctl.hide);
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final s = context.surfaces;
    return OverlayPortal(
      controller: _ctl,
      overlayChildBuilder: (context) {
        final box = this.context.findRenderObject() as RenderBox?;
        final anchor = box == null || !box.hasSize
            ? Rect.zero
            : box.localToGlobal(Offset.zero) & box.size;
        return Stack(children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _close,
              onSecondaryTap: _close,
            ),
          ),
          Positioned.fill(
            child: CustomSingleChildLayout(
              delegate:
                  _PopoverLayout(anchor: anchor, maxWidth: widget.maxWidth),
              child: Material(
                color: Colors.transparent,
                child: GlassPanel(
                  dark: dark,
                  radius: OnoteRadius.xl,
                  opacity: dark ? .86 : .88,
                  padding: const EdgeInsets.fromLTRB(OnoteSpace.x5,
                      OnoteSpace.x4, OnoteSpace.x5, OnoteSpace.x5),
                  // No `IntrinsicWidth` here: a Wrap already shrinks to its
                  // longest row, and intrinsic-width probing crashes on the
                  // segmented buttons the View card holds.
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // The card says what it is, once, in the overline —
                      // the one all-caps style, reserved for exactly this.
                      Padding(
                        padding: const EdgeInsets.only(
                            left: OnoteSpace.x2, bottom: OnoteSpace.x3),
                        child: Text(widget.label.toUpperCase(),
                            style: OnoteType.overline
                                .copyWith(color: s.textSecondary)),
                      ),
                      ListenableBuilder(
                        listenable: widget.app,
                        builder: (context, _) => widget.builder(context),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ]);
      },
      child: Tooltip(
        message: widget.tooltip,
        child: TextButton.icon(
          onPressed: _toggle,
          style: TextButton.styleFrom(
            foregroundColor: _ctl.isShowing
                ? Theme.of(context).colorScheme.primary
                : s.textPrimary,
            backgroundColor: _ctl.isShowing
                ? Theme.of(context)
                    .colorScheme
                    .primary
                    .withValues(alpha: OnoteAlpha.selected)
                : null,
            textStyle: OnoteType.small,
            visualDensity: VisualDensity.compact,
            minimumSize: const Size(0, OnoteSize.button),
            padding: const EdgeInsets.symmetric(horizontal: OnoteSpace.x4),
          ),
          icon: Icon(widget.icon, size: OnoteIcon.sm),
          label: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(widget.label),
            Icon(Icons.expand_more, size: 14, color: s.textSecondary),
          ]),
        ),
      ),
    );
  }
}

/// Puts the popover card under its button: left edges aligned, six points
/// down, kept inside the window by a 12-point margin on either side.
class _PopoverLayout extends SingleChildLayoutDelegate {
  const _PopoverLayout({required this.anchor, required this.maxWidth});
  final Rect anchor;
  final double maxWidth;

  static const _margin = 12.0;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints(
        maxWidth: math.min(maxWidth, constraints.maxWidth - 2 * _margin),
        maxHeight:
            constraints.maxHeight - anchor.bottom - OnoteSpace.x3 - _margin,
      );

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final maxLeft = size.width - childSize.width - _margin;
    final left =
        anchor.left.clamp(_margin, math.max(_margin, maxLeft)).toDouble();
    return Offset(left, anchor.bottom + OnoteSpace.x3);
  }

  @override
  bool shouldRelayout(covariant _PopoverLayout old) =>
      old.anchor != anchor || old.maxWidth != maxWidth;
}
