import 'dart:math' as math;

import 'package:flutter/scheduler.dart' show Ticker, TickerProvider;
import 'package:flutter/widgets.dart';

/// First-party pan/zoom (Tech Eval §7.3: own transform, no InteractiveViewer).
/// Maps between screen space and page space. The model is unbounded, but
/// panning is clamped to the page origin (`clampToPage`) so the page can't be
/// lost off-screen (CANVAS-1 v0.3).
class CanvasController extends ChangeNotifier {
  double scale = 1.0;
  Offset offset = Offset.zero; // page-space origin's screen position

  static const minScale = 0.15;
  static const maxScale = 8.0;

  Matrix4 get matrix => Matrix4.identity()
    ..translate(offset.dx, offset.dy)
    ..scale(scale);

  Offset screenToPage(Offset screen) => (screen - offset) / scale;
  Offset pageToScreen(Offset page) => page * scale + offset;

  void panBy(Offset delta) {
    // Horizontal movement is dropped outright when the page already fits,
    // rather than applied and then clamped away: a trackpad's sideways
    // component is never exactly zero, so "apply then clamp" spent every
    // vertical scroll fighting a horizontal one.
    offset += canPanHorizontally ? delta : Offset(0, delta.dy);
    clampToPage();
    notifyListeners();
  }

  /// FIT-TO-WIDTH IS A MODE, not a one-off action.
  ///
  /// It was an action, and that is why horizontal scrolling kept coming back:
  /// the fit put the page at the right scale for one frame, and then anything
  /// that recomputed the surface — a stroke near the edge, content growing —
  /// left the page a little wider than the window again, with slack to drag
  /// into. Latching it means the answer to "can I scroll sideways?" is a
  /// property of the view rather than an arithmetic coincidence that has to
  /// keep holding.
  ///
  /// Zooming by hand turns it off, because at that point the user has said
  /// they want a scale of their own and sideways movement is how you reach
  /// the rest of the page at it.
  bool fitLocked = false;

  /// Zoom keeping the given screen point fixed (style guide §8.2).
  void zoomAt(Offset screenFocal, double factor) {
    fitLocked = false;
    final newScale = (scale * factor).clamp(minScale, maxScale);
    final pageFocal = screenToPage(screenFocal);
    scale = newScale;
    offset = screenFocal - pageFocal * scale;
    clampToPage();
    notifyListeners();
  }

  /// Restore an exact view (used by PDF export).
  void jumpTo(double s, Offset o) {
    scale = s;
    offset = o;
    notifyListeners();
  }

  void reset() {
    scale = 1.0;
    offset = Offset.zero; // clampToPage centres it if it fits
    clampToPage();
    notifyListeners();
  }

  /// Last known viewport size (set by the canvas widget each layout).
  Size _viewport = Size.zero;
  Size get viewport => _viewport;

  /// A LATCHED FIT SURVIVES A RESIZE.
  ///
  /// Going full screen made the window wider and left the scale where it was,
  /// so the page stopped reaching the right-hand edge and a band of desk
  /// appeared beside it — the exact thing "fit" was turned on to prevent. The
  /// fit was being treated as a one-off again, just at a different moment.
  ///
  /// Re-fitting here rather than at every call site means it holds for the
  /// window resizing, the sidebar collapsing, focus mode arriving and full
  /// screen — anything that changes how much room the page has, without each
  /// of them having to remember.
  set viewport(Size v) {
    if (v == _viewport) return;
    final widthChanged = v.width != _viewport.width;
    _viewport = v;
    if (fitLocked && widthChanged && _fitTargetWidth > 0) {
      _applyFillWidth(_fitTargetWidth);
    }
  }

  /// The page width the latch is fitting, remembered so a resize can redo it.
  double _fitTargetWidth = 0;

  /// Current page-surface size in page coords (set by the canvas each build);
  /// used to clamp panning so the page can't be lost (CANVAS-1 v0.3).
  Size? pageSize;

  /// Chrome that floats OVER the canvas — the glass bars along its top and
  /// bottom edges.
  ///
  /// Page space is still mapped onto the whole box, so content scrolls under
  /// the bars and the glass has something to blur. What changes is where the
  /// page comes to REST: its top sits just below the top bar rather than under
  /// it, and the clamp treats the strip beneath each bar as already spent.
  /// Zero when nothing floats (focus mode, tests).
  EdgeInsets _insets = EdgeInsets.zero;
  EdgeInsets get insets => _insets;
  set insets(EdgeInsets v) {
    if (v == _insets) return;
    final dTop = v.top - _insets.top;
    _insets = v;
    // A bar that appears pushes the page down by its own height, so the line
    // that was under it stays readable; one that leaves gives the space back.
    // Silent: this is set during build, where a notify would rebuild the tree
    // it is in the middle of building (the same rule as `viewport`).
    offset = Offset(offset.dx, offset.dy + dTop);
    _clampSilently();
  }

  /// The height a reader can actually see the page through.
  double get _visibleHeight =>
      math.max(0.0, viewport.height - _insets.vertical);

  /// Keep the page in view, and CENTRE it horizontally when it is narrower
  /// than the window.
  ///
  /// It used to pin top-left on both axes, so a page narrower than the window
  /// sat hard against the left edge with a band of desk down the right — and
  /// because zoom re-clamps, zooming out walked the page leftwards instead of
  /// shrinking it in place. Horizontally that is wrong for a document: a
  /// sheet you are writing on belongs in the middle of the window, and
  /// zooming should happen around the middle of what you are looking at.
  ///
  /// VERTICALLY it still pins to the top. A page grows downwards and you read
  /// it from the top; centring a short page would float it in the middle of
  /// the window and move the first line every time the content got longer.
  void clampToPage() {
    final ps = pageSize;
    if (ps == null || viewport == Size.zero) return;
    final wPx = ps.width * scale;
    offset = Offset(
      // Latched to a fit: hard against the left edge, so the sheet starts at
      // the window edge and fills it. Not centred — centring is what puts a
      // margin down each side, and "no borders at all" is the ask.
      fitLocked
          ? 0.0
          // Fits: centred, and there is nowhere to scroll to. Overflows:
          // free to pan, but never past an edge.
          : wPx <= viewport.width
              ? (viewport.width - wPx) / 2
              : offset.dx.clamp(viewport.width - wPx, 0.0),
      () {
        final hPx = ps.height * scale;
        return hPx <= _visibleHeight
            ? _insets.top
            : offset.dy
                .clamp(viewport.height - _insets.bottom - hPx, _insets.top);
      }(),
    );
  }

  // ── Momentum (CANVAS-12) ─────────────────────────────────────────────
  //
  // A flick used to stop the instant the fingers left the trackpad, which
  // reads as the page being stuck to the glass. Every other scrolling surface
  // on the machine carries on and eases out, and the eye notices the absence
  // long before anyone can name it.
  //
  // Deliberately hand-rolled rather than borrowed from `Scrollable`: this
  // canvas is a transform, not a viewport of a list, and adopting Flutter's
  // physics would mean adopting its scroll model for two axes it does not own.
  // The decay is the standard exponential one — velocity × friction per frame
  // — stopped at a pixel a frame, which is below the point anything is
  // visibly still moving.

  /// Pixels per frame, decaying. Null when nothing is gliding.
  Offset? _glide;
  Ticker? _ticker;

  /// How much of the velocity survives each frame. 0.92 at 60fps is ~0.3s of
  /// visible travel: long enough to feel like release, short enough that a
  /// deliberate scroll still lands where it was aimed.
  static const _friction = 0.92;
  static const _stopBelow = 0.4;

  /// Hand [velocity] (pixels per frame) to the glide. Called on the last
  /// pointer movement of a scroll or a drag-pan.
  void fling(Offset velocity, TickerProvider vsync) {
    if (velocity.distance < 1) return;
    _glide = velocity;
    _ticker ??= vsync.createTicker((_) => _step());
    if (!_ticker!.isActive) _ticker!.start();
  }

  /// Kill any glide in progress. Anything that TOUCHES the page must call
  /// this first — a stroke that begins while the page is still moving would
  /// be drawn across a page sliding underneath it.
  void stopGlide() {
    _glide = null;
    if (_ticker?.isActive ?? false) _ticker!.stop();
  }

  void _step() {
    final v = _glide;
    if (v == null) {
      _ticker?.stop();
      return;
    }
    panBy(v);
    final next = v * _friction;
    if (next.distance < _stopBelow) {
      stopGlide();
      return;
    }
    _glide = next;
  }

  @override
  void dispose() {
    _ticker?.dispose();
    super.dispose();
  }

  /// Whether the page is wider than the window, which is the only state in
  /// which horizontal panning means anything. Everything that pans reads this
  /// so a sideways trackpad flick cannot nudge a page that already fits — it
  /// would move a page that has nowhere to go and then snap it back.
  bool get canPanHorizontally {
    // Fit means fit: while it is latched there is no sideways movement at
    // all, whatever the surface happens to measure. That is the whole point
    // of the mode — the previous rule ("is the surface wider than the
    // window?") was true again the moment anything grew sideways.
    if (fitLocked) return false;
    final ps = pageSize;
    if (ps == null || viewport == Size.zero) return false;
    return ps.width * scale > viewport.width + 0.5;
  }

  /// Initial view: page anchored top-left, filling the window (the page is at
  /// least viewport-wide, so no backdrop shows in normal use). Zooming out
  /// later reveals the page bounds — "a page that can become a canvas."
  void centerPage() {
    scale = 1.0;
    offset = Offset(0, _insets.top);
    clampToPage();
    notifyListeners();
  }

  /// Fit [contentWidth] page-px to the viewport width, anchored top-left. Only
  /// zooms OUT (never past 100%), so a narrow page keeps its natural size while
  /// a wide imported page reveals its full width — including images placed to
  /// the right of the text at their original OneNote offsets, which otherwise
  /// sit off-screen at 100%. Vertical position stays at the top (scroll down
  /// for the rest), so text stays readable rather than shrinking to fit height.
  void fitWidth(double contentWidth) {
    if (viewport == Size.zero || contentWidth <= 0) {
      centerPage();
      return;
    }
    const pad = 24.0;
    final needed = contentWidth + pad;
    scale = needed <= viewport.width
        ? 1.0
        : (viewport.width / needed).clamp(minScale, 1.0);
    offset = Offset(0, _insets.top);
    clampToPage();
    notifyListeners();
  }

  /// Scale so [contentWidth] page-px exactly spans the viewport width.
  ///
  /// The difference from [fitWidth] is the direction it is allowed to move:
  /// `fitWidth` only ever zooms OUT and stops at 100%, which is right for
  /// opening an imported page (never magnify somebody's notes at them). This
  /// is the deliberate "make the page fill the window" action, so it zooms IN
  /// as well — on a 1470px window an A4 sheet at 100% leaves a third of the
  /// screen as desk, and stopping at 100% would silently do nothing.
  void fillWidth(double contentWidth) {
    if (viewport == Size.zero || contentWidth <= 0) {
      centerPage();
      return;
    }
    fitLocked = true;
    _fitTargetWidth = contentWidth;
    _applyFillWidth(contentWidth);
    notifyListeners();
  }

  /// The arithmetic of the fit, without the latching — so a resize can redo
  /// it without re-entering [fillWidth] and re-notifying mid-layout.
  void _applyFillWidth(double contentWidth) {
    // EXACTLY the window width, with no breathing room and no margin.
    //
    // A 16px pad each side was "tidier" and it is what left a sliver to
    // scroll to: the page then ends 32px short of the window, `clampToPage`
    // centres it, and dragging one way finds slack the other. Fit means fit —
    // edge to edge, nothing down either side.
    scale = (viewport.width / contentWidth).clamp(minScale, maxScale);
    offset = Offset(0, offset.dy);
    // NOT `clampToPage()` — that notifies, and this runs from the `viewport`
    // setter during layout, where a notify would rebuild the tree it is in
    // the middle of building. The clamp itself is still applied.
    _clampSilently();
  }

  /// [clampToPage] without the notify.
  void _clampSilently() {
    final ps = pageSize;
    if (ps == null || viewport == Size.zero) return;
    final wPx = ps.width * scale;
    final hPx = ps.height * scale;
    offset = Offset(
      fitLocked
          ? 0.0
          : wPx <= viewport.width
              ? (viewport.width - wPx) / 2
              : offset.dx.clamp(viewport.width - wPx, 0.0),
      hPx <= _visibleHeight
          ? _insets.top
          : offset.dy
              .clamp(viewport.height - _insets.bottom - hPx, _insets.top),
    );
  }

  /// Put page-space Y at the top of the viewport, leaving X alone.
  ///
  /// Distinct from [centerOn]: jumping to a sheet is a *scroll*, and centring
  /// a sheet's top would hang half a viewport of the sheet before it above
  /// the fold — you would land looking at the end of the previous page.
  void scrollToPageY(double pageY) {
    offset = Offset(offset.dx, _insets.top - pageY * scale);
    clampToPage();
    notifyListeners();
  }

  /// Center a page-space point in the viewport (find, navigation).
  void centerOn(Offset pagePoint) {
    offset = Offset(viewport.width / 2, _insets.top + _visibleHeight / 2) -
        pagePoint * scale;
    clampToPage();
    notifyListeners();
  }

  /// Zoom around the middle of the window.
  ///
  /// The vertical focal point is the centre so the line you are looking at
  /// stays put; the horizontal one only matters once the page is wider than
  /// the window, since [clampToPage] centres it otherwise.
  void setZoom(double newScale) {
    zoomAt(Offset(viewport.width / 2, viewport.height / 2), newScale / scale);
  }

  /// Zoom-to-fit a page-space rectangle (style guide §8.2).
  void fitTo(Rect pageBounds) {
    if (viewport == Size.zero || pageBounds.isEmpty) {
      reset();
      return;
    }
    const pad = 48.0;
    final sx = (viewport.width - pad * 2) / pageBounds.width;
    final sy = (viewport.height - pad * 2) / pageBounds.height;
    scale = (sx < sy ? sx : sy).clamp(minScale, maxScale);
    offset = Offset(
      (viewport.width - pageBounds.width * scale) / 2 - pageBounds.left * scale,
      (viewport.height - pageBounds.height * scale) / 2 -
          pageBounds.top * scale,
    );
    notifyListeners();
  }
}
