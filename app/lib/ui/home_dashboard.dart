/// Home and the notebook overview — the two levels above a page.
///
/// **Home** is the workspace: every notebook as a card, and the pages you were
/// last in. **A notebook** is its sections and their pages, laid out to be
/// read rather than navigated. Both are presentation over state that already
/// existed — `AppState.notebooks`, `nodesOf`, `recentKeys`, `selectNotebook`,
/// `selectPage`, `createNotebook`, the notebook manager — and neither invents
/// a number: a card shows what a notebook's own nodes say about it.
library;

import 'package:flutter/material.dart';

import '../model/models.dart';
import '../state/app_state.dart';
import '../theme/onote_theme.dart';
import '../theme/tokens.dart';
import 'notebook_manager.dart';
import 'onote_dialog.dart';
import 'sidebar.dart' show sectionColorOf;

/// "2 hours ago", from epoch milliseconds. Coarse on purpose: a dashboard
/// answers "recently?", not "when exactly?".
String relativeTime(int ms, {DateTime? now}) {
  final t = DateTime.fromMillisecondsSinceEpoch(ms);
  final d = (now ?? DateTime.now()).difference(t);
  if (d.inMinutes < 1) return 'just now';
  if (d.inMinutes < 60) return '${d.inMinutes} min ago';
  if (d.inHours < 24) {
    return '${d.inHours} hour${d.inHours == 1 ? '' : 's'} ago';
  }
  if (d.inDays < 7) return '${d.inDays} day${d.inDays == 1 ? '' : 's'} ago';
  if (d.inDays < 30) {
    final w = d.inDays ~/ 7;
    return '$w week${w == 1 ? '' : 's'} ago';
  }
  return '${t.day} ${_months[t.month - 1]} ${t.year}';
}

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// What a card says about a notebook, read from its nodes once per build of
/// the dashboard and cached until the tree changes.
class NotebookMeta {
  const NotebookMeta(
      {required this.pages, required this.sections, required this.editedAt});
  final int pages;
  final int sections;

  /// The newest `updatedAt` across the notebook, or null for an empty one.
  final int? editedAt;

  static NotebookMeta of(List<TreeNode> nodes) {
    var pages = 0, sections = 0;
    int? edited;
    for (final n in nodes) {
      if (n.kind == NodeKind.page) pages++;
      if (n.kind == NodeKind.section) sections++;
      if (edited == null || n.updatedAt > edited) edited = n.updatedAt;
    }
    return NotebookMeta(pages: pages, sections: sections, editedAt: edited);
  }
}

/// A notebook's visual identity: a hue from a short, sophisticated set, picked
/// by the notebook's id so it never changes and never has to be stored.
Color notebookHue(String id, {required bool dark}) {
  const light = [
    Color(0xFF4F7BF5), // blue
    Color(0xFF8B5CF6), // violet
    Color(0xFFE0568C), // rose
    Color(0xFF2FA86B), // green
    Color(0xFFE8892B), // amber
    Color(0xFF14A3A3), // teal
  ];
  const night = [
    Color(0xFF7FA1FF),
    Color(0xFFB08CFF),
    Color(0xFFFF7FAE),
    Color(0xFF5BD08F),
    Color(0xFFFFB35C),
    Color(0xFF4FD0D0),
  ];
  final set = dark ? night : light;
  return set[id.hashCode.abs() % set.length];
}

/// The workspace: every notebook, then the pages you were last in.
class HomeDashboard extends StatefulWidget {
  const HomeDashboard({super.key, required this.app});
  final AppState app;

  @override
  State<HomeDashboard> createState() => _HomeDashboardState();
}

class _HomeDashboardState extends State<HomeDashboard> {
  AppState get app => widget.app;

  // Nodes of every notebook, read once per tree revision. Reading another
  // notebook's nodes opens its container, so this is not done per frame.
  final Map<String, List<TreeNode>> _nodes = {};
  int _rev = -1;

  List<TreeNode> _nodesOf(String id) {
    if (_rev != app.nodesRevision) {
      _nodes.clear();
      _rev = app.nodesRevision;
    }
    return _nodes.putIfAbsent(id, () {
      try {
        return app.nodesOf(id);
      } catch (_) {
        return const [];
      }
    });
  }

  Future<void> _newNotebook(BuildContext context) async {
    final title = await promptForText(context,
        title: 'New notebook', okLabel: 'Create', hintText: 'Notebook name');
    if (title == null || title.trim().isEmpty) return;
    await app.createNotebook(title.trim());
    app.openNotebookOverview();
  }

  Future<void> _open(NotebookRef nb) async {
    if (nb.id != app.notebookId) await app.selectNotebook(nb.id);
    app.openNotebookOverview();
  }

  Future<void> _openRecent(String nbId, String pageId) async {
    if (nbId != app.notebookId) await app.selectNotebook(nbId);
    await app.selectPage(pageId);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.surfaces;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final notebooks = app.notebooks;
    final recents = <({NotebookRef nb, TreeNode page, TreeNode? section})>[];
    for (final key in app.recentKeys) {
      final i = key.indexOf(':');
      if (i < 0) continue;
      final nbId = key.substring(0, i), pageId = key.substring(i + 1);
      final nb = notebooks.where((n) => n.id == nbId).firstOrNull;
      if (nb == null) continue;
      final nodes = _nodesOf(nbId);
      final page = nodes.where((n) => n.id == pageId).firstOrNull;
      if (page == null) continue;
      recents.add((
        nb: nb,
        page: page,
        section: nodes.where((n) => n.id == page.parentId).firstOrNull,
      ));
      if (recents.length >= 8) break;
    }

    return LayoutBuilder(builder: (context, c) {
      // Cards 240–300 wide, as many per row as fit, never stretched thin.
      final inner = c.maxWidth - 2 * OnoteSpace.x9;
      final cols = (inner / 272).floor().clamp(1, 5);
      final cardW = ((inner - (cols - 1) * OnoteSpace.x6) / cols)
          .clamp(200.0, 340.0)
          .toDouble();
      return ListView(
        padding: const EdgeInsets.fromLTRB(
            OnoteSpace.x9, OnoteSpace.x8, OnoteSpace.x9, OnoteSpace.x9),
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Home',
                        style: OnoteType.display
                            .copyWith(fontSize: 30, color: s.textPrimary)),
                    const SizedBox(height: OnoteSpace.x2),
                    Text('Pick up where you left off, or start something new.',
                        style: OnoteType.ui.copyWith(color: s.textSecondary)),
                  ],
                ),
              ),
              FilledButton.icon(
                icon: const Icon(Icons.add, size: OnoteIcon.md),
                label: const Text('New notebook'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 42),
                  padding:
                      const EdgeInsets.symmetric(horizontal: OnoteSpace.x7),
                  shape: const RoundedRectangleBorder(
                      borderRadius: OnoteRadius.lgAll),
                ),
                onPressed: () => _newNotebook(context),
              ),
            ],
          ),
          const SizedBox(height: OnoteSpace.x8),
          Row(children: [
            Text('Your notebooks',
                style: OnoteType.title.copyWith(color: s.textPrimary)),
            const SizedBox(width: OnoteSpace.x4),
            _Count(notebooks.length),
          ]),
          const SizedBox(height: OnoteSpace.x5),
          Wrap(
            spacing: OnoteSpace.x6,
            runSpacing: OnoteSpace.x6,
            children: [
              for (final nb in notebooks)
                _NotebookCard(
                  width: cardW,
                  notebook: nb,
                  meta: NotebookMeta.of(_nodesOf(nb.id)),
                  hue: notebookHue(nb.id, dark: dark),
                  current: nb.id == app.notebookId,
                  onOpen: () => _open(nb),
                  onMore: () =>
                      showNotebookManager(context, app, focusId: nb.id),
                ),
              _NewNotebookCard(
                  width: cardW, onTap: () => _newNotebook(context)),
            ],
          ),
          if (recents.isNotEmpty) ...[
            const SizedBox(height: OnoteSpace.x9),
            Text('Recent pages',
                style: OnoteType.title.copyWith(color: s.textPrimary)),
            const SizedBox(height: OnoteSpace.x1),
            Text('Continue where you left off',
                style: OnoteType.small.copyWith(color: s.textSecondary)),
            const SizedBox(height: OnoteSpace.x4),
            _Sheet(
              child: Column(children: [
                for (final (i, r) in recents.indexed) ...[
                  if (i > 0)
                    Divider(height: 1, color: s.border.withValues(alpha: .6)),
                  _RecentRow(
                    page: r.page,
                    notebook: r.nb,
                    section: r.section,
                    hue: notebookHue(r.nb.id, dark: dark),
                    onTap: () => _openRecent(r.nb.id, r.page.id),
                  ),
                ],
              ]),
            ),
          ],
        ],
      );
    });
  }
}

/// One notebook: its sections, each with its pages.
class NotebookOverview extends StatelessWidget {
  const NotebookOverview({super.key, required this.app});
  final AppState app;

  @override
  Widget build(BuildContext context) {
    final s = context.surfaces;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final nb = app.notebooks.where((n) => n.id == app.notebookId).firstOrNull;
    final sections = app.nodes.where((n) => n.kind == NodeKind.section).toList()
      ..sort((a, b) => a.position.compareTo(b.position));
    final pageCount = app.nodes.where((n) => n.kind == NodeKind.page).length;
    final hue = nb == null ? s.textSecondary : notebookHue(nb.id, dark: dark);

    return LayoutBuilder(builder: (context, c) {
      final inner = c.maxWidth - 2 * OnoteSpace.x9;
      final cols = (inner / 300).floor().clamp(1, 4);
      final cardW = ((inner - (cols - 1) * OnoteSpace.x6) / cols)
          .clamp(220.0, 420.0)
          .toDouble();
      return ListView(
        padding: const EdgeInsets.fromLTRB(
            OnoteSpace.x9, OnoteSpace.x8, OnoteSpace.x9, OnoteSpace.x9),
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _HueIcon(hue: hue, icon: Icons.auto_stories_outlined, size: 44),
              const SizedBox(width: OnoteSpace.x6),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(nb?.title ?? 'Notebook',
                        style: OnoteType.display
                            .copyWith(fontSize: 30, color: s.textPrimary)),
                    const SizedBox(height: OnoteSpace.x2),
                    Text(
                        '${_plural(sections.length, 'section')} · '
                        '${_plural(pageCount, 'page')}',
                        style: OnoteType.ui.copyWith(color: s.textSecondary)),
                  ],
                ),
              ),
              // The same actions the navigator's footer has always had.
              OutlinedButton.icon(
                icon: const Icon(Icons.create_new_folder_outlined,
                    size: OnoteIcon.sm),
                label: const Text('New section'),
                onPressed: () => app.addSection(),
              ),
              const SizedBox(width: OnoteSpace.x4),
              FilledButton.icon(
                icon: const Icon(Icons.note_add_outlined, size: OnoteIcon.sm),
                label: const Text('New page'),
                onPressed: sections.isEmpty ? null : () => app.addPage(),
              ),
              const SizedBox(width: OnoteSpace.x2),
              IconButton(
                icon: const Icon(Icons.more_horiz),
                tooltip: 'Notebook — rename, duplicate, import…',
                onPressed: () =>
                    showNotebookManager(context, app, focusId: app.notebookId),
              ),
            ],
          ),
          const SizedBox(height: OnoteSpace.x8),
          if (sections.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: OnoteSpace.x9),
              child: Center(
                child: Text('No sections yet — create one to start writing.',
                    style: OnoteType.ui.copyWith(color: s.textSecondary)),
              ),
            )
          else
            Wrap(
              spacing: OnoteSpace.x6,
              runSpacing: OnoteSpace.x6,
              children: [
                for (final sec in sections)
                  _SectionCard(
                    width: cardW,
                    section: sec,
                    pages: app.pagesOf(sec.id),
                    color: sectionColorOf(sec.color, dark),
                    currentPageId: app.pageId,
                    onOpenPage: (id) => app.selectPage(id),
                    onOpenSection: () => app.activateSection(sec.id),
                  ),
              ],
            ),
        ],
      );
    });
  }
}

String _plural(int n, String word) => '$n $word${n == 1 ? '' : 's'}';

// ── Pieces ─────────────────────────────────────────────────────────────

/// A translucent tile on the ambient page. No blur of its own: a dozen of
/// these would be a dozen backdrop filters, and the page under them is
/// already the material they need.
class _Sheet extends StatelessWidget {
  const _Sheet({required this.child, this.width, this.padding, this.glow});
  final Widget child;
  final double? width;
  final EdgeInsets? padding;

  /// A colour breathed into the tile's top-right corner — the notebook's hue.
  final Color? glow;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: width,
      padding: padding,
      decoration: BoxDecoration(
        borderRadius: OnoteRadius.xlAll,
        color: (dark ? OnoteColors.night100 : Colors.white)
            .withValues(alpha: dark ? .55 : .62),
        border: Border.all(
            color: (dark ? Colors.white : Colors.white)
                .withValues(alpha: dark ? .08 : .75)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1E2850).withValues(alpha: dark ? .30 : .06),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
        gradient: glow == null
            ? null
            : RadialGradient(
                center: const Alignment(1.1, -1.1),
                radius: 1.1,
                colors: [
                  glow!.withValues(alpha: dark ? .22 : .16),
                  glow!.withValues(alpha: 0),
                ],
              ),
      ),
      child: child,
    );
  }
}

class _HueIcon extends StatelessWidget {
  const _HueIcon({required this.hue, required this.icon, this.size = 40});
  final Color hue;
  final IconData icon;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: hue.withValues(alpha: .14),
          borderRadius: OnoteRadius.lgAll,
        ),
        child: Icon(icon, size: size * .5, color: hue),
      );
}

class _Count extends StatelessWidget {
  const _Count(this.n);
  final int n;

  @override
  Widget build(BuildContext context) {
    final s = context.surfaces;
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: OnoteSpace.x3, vertical: OnoteSpace.x1),
      decoration: BoxDecoration(
        color: s.chrome2.withValues(alpha: .8),
        borderRadius: BorderRadius.circular(OnoteRadius.full),
      ),
      child: Text('$n',
          style: OnoteType.caption
              .copyWith(color: s.textSecondary, fontWeight: FontWeight.w600)),
    );
  }
}

class _NotebookCard extends StatefulWidget {
  const _NotebookCard({
    required this.width,
    required this.notebook,
    required this.meta,
    required this.hue,
    required this.current,
    required this.onOpen,
    required this.onMore,
  });
  final double width;
  final NotebookRef notebook;
  final NotebookMeta meta;
  final Color hue;
  final bool current;
  final VoidCallback onOpen;
  final VoidCallback onMore;

  @override
  State<_NotebookCard> createState() => _NotebookCardState();
}

class _NotebookCardState extends State<_NotebookCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final s = context.surfaces;
    final m = widget.meta;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onOpen,
        child: AnimatedScale(
          scale: _hover ? 1.015 : 1,
          duration: OnoteMotion.standard,
          curve: OnoteMotion.curve,
          child: _Sheet(
            width: widget.width,
            glow: widget.hue,
            padding: const EdgeInsets.all(OnoteSpace.x7),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  _HueIcon(hue: widget.hue, icon: Icons.auto_stories_outlined),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.more_horiz, size: OnoteIcon.md),
                    tooltip: 'Rename, duplicate, import…',
                    visualDensity: VisualDensity.compact,
                    onPressed: widget.onMore,
                  ),
                ]),
                const SizedBox(height: OnoteSpace.x6),
                Text(widget.notebook.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: OnoteType.headline.copyWith(color: s.textPrimary)),
                const SizedBox(height: OnoteSpace.x1),
                Text(
                    '${_plural(m.pages, 'page')} · '
                    '${_plural(m.sections, 'section')}',
                    style: OnoteType.small.copyWith(color: s.textSecondary)),
                const SizedBox(height: OnoteSpace.x7),
                Row(children: [
                  Expanded(
                    child: Text(
                        m.editedAt == null
                            ? 'Nothing written yet'
                            : 'Edited ${relativeTime(m.editedAt!)}',
                        style:
                            OnoteType.caption.copyWith(color: s.textSecondary)),
                  ),
                  if (widget.current)
                    Padding(
                      padding: const EdgeInsets.only(right: OnoteSpace.x3),
                      child: Text('Open',
                          style: OnoteType.caption.copyWith(
                              color: widget.hue, fontWeight: FontWeight.w600)),
                    ),
                  Container(
                    width: 28,
                    height: 28,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: widget.hue.withValues(alpha: _hover ? .22 : .12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.chevron_right,
                        size: OnoteIcon.sm, color: widget.hue),
                  ),
                ]),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NewNotebookCard extends StatelessWidget {
  const _NewNotebookCard({required this.width, required this.onTap});
  final double width;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = context.surfaces;
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: width,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: OnoteRadius.xlAll,
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(OnoteSpace.x7),
            decoration: BoxDecoration(
              borderRadius: OnoteRadius.xlAll,
              // Dashed in spirit: a hairline a shade stronger than the tiles'
              // says "not a notebook yet" without a second visual language.
              border: Border.all(color: s.border, width: 1.2),
              color: Colors.white.withValues(alpha: .18),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: .10),
                    borderRadius: OnoteRadius.lgAll,
                  ),
                  child: Icon(Icons.add, color: scheme.primary),
                ),
                const SizedBox(height: OnoteSpace.x6),
                Text('Create a new notebook',
                    style: OnoteType.headline.copyWith(color: s.textPrimary)),
                const SizedBox(height: OnoteSpace.x1),
                Text('Organise your thoughts, ideas and notes',
                    style: OnoteType.small.copyWith(color: s.textSecondary)),
                const SizedBox(height: OnoteSpace.x7 + 28),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RecentRow extends StatelessWidget {
  const _RecentRow({
    required this.page,
    required this.notebook,
    required this.section,
    required this.hue,
    required this.onTap,
  });
  final TreeNode page;
  final NotebookRef notebook;
  final TreeNode? section;
  final Color hue;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = context.surfaces;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: OnoteSpace.x6, vertical: OnoteSpace.x5),
          child: Row(children: [
            _HueIcon(hue: hue, icon: Icons.description_outlined, size: 32),
            const SizedBox(width: OnoteSpace.x5),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(page.title.isEmpty ? 'Untitled page' : page.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: OnoteType.uiStrong.copyWith(color: s.textPrimary)),
                  Text(
                      [notebook.title, if (section != null) section!.title]
                          .join(' › '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          OnoteType.caption.copyWith(color: s.textSecondary)),
                ],
              ),
            ),
            const SizedBox(width: OnoteSpace.x5),
            Text('Edited ${relativeTime(page.updatedAt)}',
                style: OnoteType.caption.copyWith(color: s.textSecondary)),
            const SizedBox(width: OnoteSpace.x3),
            Icon(Icons.chevron_right,
                size: OnoteIcon.sm, color: s.textDisabled),
          ]),
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.width,
    required this.section,
    required this.pages,
    required this.color,
    required this.currentPageId,
    required this.onOpenPage,
    required this.onOpenSection,
  });
  final double width;
  final TreeNode section;
  final List<TreeNode> pages;
  final Color color;
  final String? currentPageId;
  final ValueChanged<String> onOpenPage;
  final VoidCallback onOpenSection;

  @override
  Widget build(BuildContext context) {
    final s = context.surfaces;
    final scheme = Theme.of(context).colorScheme;
    return _Sheet(
      width: width,
      padding: const EdgeInsets.fromLTRB(
          OnoteSpace.x6, OnoteSpace.x6, OnoteSpace.x6, OnoteSpace.x4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: OnoteRadius.mdAll,
            onTap: onOpenSection,
            child: Row(children: [
              Container(
                width: 4,
                height: 20,
                decoration: BoxDecoration(
                    color: color, borderRadius: BorderRadius.circular(2)),
              ),
              const SizedBox(width: OnoteSpace.x4),
              Expanded(
                child: Text(section.title.isEmpty ? 'Section' : section.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: OnoteType.title.copyWith(color: s.textPrimary)),
              ),
              Text(_plural(pages.length, 'page'),
                  style: OnoteType.caption.copyWith(color: s.textSecondary)),
            ]),
          ),
          const SizedBox(height: OnoteSpace.x4),
          if (pages.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: OnoteSpace.x4),
              child: Text('No pages yet',
                  style: OnoteType.small.copyWith(color: s.textSecondary)),
            ),
          for (final p in pages)
            Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: OnoteRadius.mdAll,
                onTap: () => onOpenPage(p.id),
                child: Container(
                  padding: EdgeInsets.fromLTRB(
                      OnoteSpace.x4 + p.level * OnoteSpace.x6,
                      OnoteSpace.x3,
                      OnoteSpace.x4,
                      OnoteSpace.x3),
                  decoration: p.id == currentPageId
                      ? BoxDecoration(
                          color: scheme.primary
                              .withValues(alpha: OnoteAlpha.selected),
                          borderRadius: OnoteRadius.mdAll)
                      : null,
                  child: Row(children: [
                    Icon(Icons.description_outlined,
                        size: OnoteIcon.sm,
                        color: p.id == currentPageId
                            ? scheme.primary
                            : s.textSecondary),
                    const SizedBox(width: OnoteSpace.x4),
                    Expanded(
                      child: Text(p.title.isEmpty ? 'Untitled page' : p.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: OnoteType.ui.copyWith(
                              color: p.id == currentPageId
                                  ? scheme.primary
                                  : s.textPrimary)),
                    ),
                  ]),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
