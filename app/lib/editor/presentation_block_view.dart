import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../media/pdf_pages.dart';
import '../model/models.dart';
import '../state/app_state.dart';
import '../theme/onote_theme.dart';
import '../theme/tokens.dart';

/// A presentation on the page: a stored PDF paged through one slide at a time,
/// the way you would run a deck while teaching.
///
/// content: `{ pdf: 'sha256:<hash>', name, pages }`. The PDF itself is an
/// ordinary content-addressed blob (so it syncs like any image and is kept
/// alive by the `pdf` key the reachability sweep already scans); pages are
/// rendered on demand by [PdfPages], the same engine the PDF slides use.
///
/// Back/Next (and the arrow keys, and a tap to focus) move through the deck; a
/// Present button opens the same deck full-window for the room to see. The
/// frame is deliberately rounded and soft — a slide, not a spreadsheet.
class PresentationBlockView extends StatefulWidget {
  const PresentationBlockView(
      {super.key, required this.block, required this.app});
  final Block block;
  final AppState app;

  @override
  State<PresentationBlockView> createState() => _PresentationBlockViewState();
}

class _PresentationBlockViewState extends State<PresentationBlockView> {
  int _page = 0;
  final _focus = FocusNode();

  String get _hash => (widget.block.content['pdf'] as String? ?? '')
      .replaceFirst('sha256:', '');
  int get _pages => (widget.block.content['pages'] as num?)?.toInt() ?? 1;
  String get _name => widget.block.content['name'] as String? ?? 'Presentation';

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  void _go(int delta) {
    final next = (_page + delta).clamp(0, _pages - 1);
    if (next != _page) setState(() => _page = next);
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    switch (e.logicalKey) {
      case LogicalKeyboardKey.arrowRight:
      case LogicalKeyboardKey.arrowDown:
      case LogicalKeyboardKey.pageDown:
      case LogicalKeyboardKey.space:
        _go(1);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowLeft:
      case LogicalKeyboardKey.arrowUp:
      case LogicalKeyboardKey.pageUp:
        _go(-1);
        return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Future<void> _present() async {
    await showPresentationFullscreen(
      context,
      app: widget.app,
      hash: _hash,
      pages: _pages,
      name: _name,
      initialPage: _page,
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = context.surfaces;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Focus(
      focusNode: _focus,
      onKeyEvent: _onKey,
      child: GestureDetector(
        onTap: _focus.requestFocus,
        child: Container(
          decoration: BoxDecoration(
            color: s.raised,
            borderRadius: OnoteRadius.lgAll,
            border: Border.all(color: s.border),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: dark ? 0.3 : 0.10),
                blurRadius: 14,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              Expanded(
                child: _SlideStage(
                  app: widget.app,
                  hash: _hash,
                  page: _page,
                  dark: dark,
                ),
              ),
              _bar(context, s),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bar(BuildContext context, OnoteSurfaces s) {
    final atStart = _page <= 0;
    final atEnd = _page >= _pages - 1;
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: OnoteSpace.x3),
      color: s.well,
      child: Row(
        children: [
          _round(
              Icons.chevron_left, 'Previous', atStart ? null : () => _go(-1)),
          const SizedBox(width: 4),
          _round(Icons.chevron_right, 'Next', atEnd ? null : () => _go(1)),
          const Spacer(),
          Text('${_page + 1} / $_pages',
              style: TextStyle(fontSize: 12.5, color: s.textSecondary)),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.fullscreen, size: 20),
            tooltip: 'Present full screen',
            visualDensity: VisualDensity.compact,
            onPressed: _present,
          ),
        ],
      ),
    );
  }

  Widget _round(IconData icon, String tip, VoidCallback? onTap) {
    final scheme = Theme.of(context).colorScheme;
    final on = onTap != null;
    return Material(
      color: on ? scheme.primary.withValues(alpha: 0.12) : Colors.transparent,
      shape: const CircleBorder(),
      child: IconButton(
        icon: Icon(icon, size: 20),
        color: on ? scheme.primary : Theme.of(context).disabledColor,
        tooltip: tip,
        visualDensity: VisualDensity.compact,
        onPressed: onTap,
      ),
    );
  }
}

/// One slide, rendered on a soft "projector" backdrop with rounded corners.
class _SlideStage extends StatelessWidget {
  const _SlideStage({
    required this.app,
    required this.hash,
    required this.page,
    required this.dark,
  });
  final AppState app;
  final String hash;
  final int page;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: dark ? const Color(0xFF15171B) : const Color(0xFFEDEEF1),
      padding: const EdgeInsets.all(12),
      child: Center(
        child: FutureBuilder<Uint8List?>(
          // A stable key per page so flipping slides doesn't flash the old one.
          key: ValueKey('$hash#$page'),
          future: PdfPages.pageImage(app, hash, page),
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              );
            }
            final bytes = snap.data;
            if (bytes == null) {
              return Text(
                app.blob(hash) == null
                    ? "This deck isn't on this computer yet."
                    : "That slide couldn't be shown.",
                style: const TextStyle(
                    fontSize: 12.5, color: OnoteColors.graphite400),
              );
            }
            return ClipRRect(
              borderRadius: OnoteRadius.mdAll,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: OnoteRadius.mdAll,
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withValues(alpha: 0.25),
                        blurRadius: 10,
                        offset: const Offset(0, 3)),
                  ],
                ),
                child: Image.memory(bytes,
                    fit: BoxFit.contain, gaplessPlayback: true),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Run the deck full-window: one slide at a time, arrow keys, Esc to leave.
Future<void> showPresentationFullscreen(
  BuildContext context, {
  required AppState app,
  required String hash,
  required int pages,
  required String name,
  int initialPage = 0,
}) {
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.9),
    builder: (_) => _FullscreenPresenter(
      app: app,
      hash: hash,
      pages: pages,
      name: name,
      initialPage: initialPage,
    ),
  );
}

class _FullscreenPresenter extends StatefulWidget {
  const _FullscreenPresenter({
    required this.app,
    required this.hash,
    required this.pages,
    required this.name,
    required this.initialPage,
  });
  final AppState app;
  final String hash;
  final int pages;
  final String name;
  final int initialPage;

  @override
  State<_FullscreenPresenter> createState() => _FullscreenPresenterState();
}

class _FullscreenPresenterState extends State<_FullscreenPresenter> {
  late int _page = widget.initialPage.clamp(0, widget.pages - 1);
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  void _go(int delta) {
    final next = (_page + delta).clamp(0, widget.pages - 1);
    if (next != _page) setState(() => _page = next);
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    switch (e.logicalKey) {
      case LogicalKeyboardKey.arrowRight:
      case LogicalKeyboardKey.arrowDown:
      case LogicalKeyboardKey.pageDown:
      case LogicalKeyboardKey.space:
        _go(1);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowLeft:
      case LogicalKeyboardKey.arrowUp:
      case LogicalKeyboardKey.pageUp:
        _go(-1);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.escape:
        Navigator.of(context).pop();
        return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final atStart = _page <= 0;
    final atEnd = _page >= widget.pages - 1;
    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: _onKey,
      child: Stack(
        children: [
          // The slide, as large as the window allows.
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 64),
              child: Center(
                child: FutureBuilder<Uint8List?>(
                  key: ValueKey('${widget.hash}#$_page'),
                  future: PdfPages.pageImage(widget.app, widget.hash, _page),
                  builder: (context, snap) {
                    final bytes = snap.data;
                    if (bytes == null) {
                      return snap.connectionState == ConnectionState.done
                          ? const Text("That slide couldn't be shown.",
                              style: TextStyle(color: Colors.white70))
                          : const CircularProgressIndicator();
                    }
                    return ClipRRect(
                      borderRadius: OnoteRadius.lgAll,
                      child: Image.memory(bytes,
                          fit: BoxFit.contain, gaplessPlayback: true),
                    );
                  },
                ),
              ),
            ),
          ),
          // Big invisible tap zones: left half back, right half forward.
          Positioned.fill(
            child: Row(children: [
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: atStart ? null : () => _go(-1),
                ),
              ),
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: atEnd ? null : () => _go(1),
                ),
              ),
            ]),
          ),
          // A slim control strip at the bottom.
          Positioned(
            left: 0,
            right: 0,
            bottom: 16,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _fsButton(Icons.chevron_left, atStart ? null : () => _go(-1)),
                const SizedBox(width: 14),
                Text('${_page + 1} / ${widget.pages}',
                    style: const TextStyle(color: Colors.white, fontSize: 13)),
                const SizedBox(width: 14),
                _fsButton(Icons.chevron_right, atEnd ? null : () => _go(1)),
                const SizedBox(width: 24),
                _fsButton(Icons.close, () => Navigator.of(context).pop()),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _fsButton(IconData icon, VoidCallback? onTap) => Material(
        color: Colors.white.withValues(alpha: onTap == null ? 0.06 : 0.16),
        shape: const CircleBorder(),
        child: IconButton(
          icon: Icon(icon, size: 22),
          color: onTap == null ? Colors.white38 : Colors.white,
          onPressed: onTap,
        ),
      );
}
