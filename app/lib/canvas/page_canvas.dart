import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../ink/arrow.dart';
import '../ink/rectangle.dart';
import '../ink/shape_snap.dart';
import '../model/models.dart';
import '../state/app_state.dart';
import '../theme/onote_theme.dart';
import '../ui/context_menus.dart';
import 'block_view.dart';
import 'align_guides.dart';
import 'canvas_controller.dart';
import 'ink_ops.dart';
import 'media_drop.dart';
import 'ink_painter.dart';
import 'paper.dart';
import 'page_title_view.dart';

/// The page canvas (CANVAS-1 v0.3): an auto-growing page surface on a neutral
/// backdrop. Select-mode input model (style guide §8):
///   · click empty page (nothing selected)  → create text box, type (CANVAS-3)
///   · click empty page (something selected)→ deselect
///   · drag empty page                      → marquee multi-select (CANVAS-7)
///   · click ink                            → select ink block; drag moves it
///   · middle-drag                          → pan · Ctrl+scroll → zoom
///   · trackpad pan/pinch                   → pan/zoom · two-finger touch → pinch
class PageCanvas extends StatefulWidget {
  const PageCanvas(
      {super.key, required this.state, this.insets = EdgeInsets.zero});
  final AppState state;

  /// The chrome floating over this canvas's top and bottom edges — see
  /// [CanvasController.insets]. The canvas is laid out under the glass bars
  /// so they have a page to blur; this is how it knows where they are.
  final EdgeInsets insets;

  @override
  State<PageCanvas> createState() => _PageCanvasState();
}

enum _DragMode { none, pending, marquee, moveSelection, pan }

class _PageCanvasState extends State<PageCanvas>
    with SingleTickerProviderStateMixin {
  Stroke? _wet;

  /// Bumped per wet-ink point so ONLY the ink layer repaints (the painter
  /// listens via `repaint:`). A setState per pointer move rebuilt every
  /// visible block at stylus rate — the "inking feels sluggish" report.
  final ValueNotifier<int> _wetTick = ValueNotifier(0);

  /// Where the mouse is, in screen space, while a drawing tool is armed —
  /// null whenever the real cursor should be showing instead (pointer off the
  /// canvas, or a non-mouse pointer, which brings its own physical tip).
  ///
  /// A notifier rather than `setState` for exactly the reason [_wetTick] is
  /// one: hover fires at pointer rate, and rebuilding every visible block to
  /// move a 20-pixel glyph is the same sluggishness bug in a different coat.
  /// Only [_PenCursorPainter] listens.
  final ValueNotifier<Offset?> _penCursor = ValueNotifier(null);
  bool _eraseUndoPushed = false;
  bool _moveUndoPushed = false;

  _DragMode _mode = _DragMode.none;
  Offset _downScreen = Offset.zero;
  Offset _marqueeStartPage = Offset.zero;
  Offset _marqueeEndPage = Offset.zero;
  Offset _lastScreen = Offset.zero;

  /// What kind of pointer went down, decided when a pending drag commits:
  /// a mouse or pen drag on empty page is a marquee, a FINGER drag is a pan.
  /// "On touch screens, by default dragging with a finger should pan around
  /// the page, it shouldn't be the selector tool" — the platform convention
  /// everywhere touch exists, and marquee stays reachable with a pen or a
  /// mouse. A finger TAP still does everything a click does.
  PointerDeviceKind _downKind = PointerDeviceKind.mouse;

  // Two-finger touch pinch tracking.
  final Map<int, Offset> _touches = {};
  double? _pinchBaseDist;
  double _pzLastScale = 1.0;

  /// The pointer of a trackpad pan/pinch a block has claimed for itself
  /// (a graph, panning its own window) — null once nothing has. Latched
  /// for the gesture's whole lifetime; see the comment on
  /// `onPointerPanZoomStart` for why this is not re-checked per update.
  int? _panZoomClaimedBy;

  // ── Scroll momentum and the auto-hiding bar ──────────────────────────
  //
  // A wheel or trackpad gives no "gesture ended" event, so the flick is armed
  // by a short timer that every further notch resets: when the notches stop,
  // the last one's size is the velocity to carry on with.
  Offset _lastScrollDelta = Offset.zero;
  Timer? _glideArm;
  Timer? _scrollFade;

  /// True for a moment after any scrolling, which is when the bar shows.
  bool _scrolledRecently = false;

  void _armGlide() {
    _glideArm?.cancel();
    _glideArm = Timer(const Duration(milliseconds: 60), () {
      if (!mounted) return;
      // Scale the last notch down to a per-frame velocity. A notch is one
      // event, not one frame, and handing it over whole launches the page.
      controller.fling(_lastScrollDelta * 0.55, this);
    });
  }

  /// Show the scroll bar, and start the clock that hides it again.
  void _noteScrollActivity() {
    if (!_scrolledRecently) setState(() => _scrolledRecently = true);
    _scrollFade?.cancel();
    _scrollFade = Timer(const Duration(milliseconds: 900), () {
      if (mounted) setState(() => _scrolledRecently = false);
    });
  }

  // Insert Space: where the drag began in page space, and how far it has
  // moved. Null when the tool is idle.
  double? _spaceAtY;
  double _spaceDy = 0;

  bool get _spaceTool => app.tool == Tool.space;

  // ── Draw and HOLD to snap a shape (INK-10, revised) ──────────────────
  //
  // Snapping used to happen on release, and it was startling: you drew a
  // line, let go, and the app changed it. You could not tell it was coming,
  // could not see what it decided, and could not decline. So it happens while
  // you are still holding the pointer down — hold still for [_holdToSnap] and
  // the tidied shape appears under your hand, which you can then accept by
  // letting go, or reject by carrying on drawing.
  //
  // The RAW stroke is kept intact throughout: [_wet] is always what the hand
  // did, and [_snapPreview] is the proposal drawn in its place. Moving again
  // throws the proposal away rather than trying to continue from it, because
  // continuing from an idealised circle is not what anybody means by
  // continuing.
  static const _holdToSnap = Duration(milliseconds: 700);
  Timer? _holdTimer;
  Stroke? _snapPreview;

  // ── Auto-shape adjust: hold to size, release to move, click to place ─────
  //
  // Once a drawn stroke snaps to a shape (INK-10), the shape LOCKS instead of
  // being thrown away the moment the hand moves again. While the drawing
  // pointer stays down, dragging up grows it and down shrinks it. On release
  // it becomes a floating, draggable copy: a drag repositions it and a plain
  // tap drops it into the page and hands the pen back.
  bool _sizingShape = false; // snapped, and the drawing pointer is still down
  double? _sizeAnchorScreenY; // pointer Y (screen) at the moment it snapped
  Stroke? _snapBase; // the snapped shape at scale 1, scaled from
  Offset? _snapCenter; // its centre, the point size grows around
  Offset? _lastInkScreenPos; // most recent ink-pointer position, for the anchor

  Stroke? _placedShape; // released and active: draggable, not yet committed
  Stroke? _placedDragBase; // the placed shape when the current drag began
  Offset? _dragAnchorScreen; // pointer position (screen) when the drag began
  double _placedMoved =
      0; // furthest the current pointer travelled (tap vs drag)

  /// A tap may wander this far (screen px) and still count as a placing click.
  static const double _placeTapSlop = 5.0;

  /// The stroke the ink layer should draw: a placed shape, else a proposal,
  /// else the wet stroke.
  Stroke? get _wetForPaint => _placedShape ?? _snapPreview ?? _wet;

  bool get _arrowTool => app.tool == Tool.arrow;
  bool get _rectTool => app.tool == Tool.rectangle;

  /// The two-corner drag tools (arrow and rectangle) share the same gesture:
  /// press one point, drag to another, and the shape is decided by the pair.
  bool get _twoCornerTool => _arrowTool || _rectTool;

  /// Where a two-corner (arrow or rectangle) drag began, in page space.
  Offset2? _arrowFrom;
  Offset2? _arrowTo;

  // Lasso-select (INK-7): the freeform loop being drawn, in page space.
  List<Offset>? _lasso;

  AppState get app => widget.state;
  CanvasController get controller => app.canvas;

  bool get _inkTool =>
      app.tool == Tool.pen ||
      app.tool == Tool.highlighter ||
      app.tool == Tool.eraser;

  /// Follow the pointer with the drawn cursor, through hover AND drag.
  ///
  /// Only a MOUSE gets one. A stylus and a finger are already physically at
  /// the point, and painting a nib under a real pen tip is a second pen
  /// chasing the first one.
  void _trackPenCursor(PointerEvent e) {
    _penCursor.value =
        _inkTool && e.kind == PointerDeviceKind.mouse ? e.localPosition : null;
  }

  /// What the drawn cursor is filled with: the armed ink, so the nib shows
  /// the colour you are about to draw in and the swatch row is not the only
  /// place that answer lives. The eraser has no ink, so it gets the page's
  /// own outline instead.
  Color _penCursorColor(bool dark) {
    if (app.tool == Tool.eraser) {
      return dark ? OnoteColors.moon300 : OnoteColors.graphite900;
    }
    // Same substitution the stroke makes on screen — see `themedInk`.
    return themedInk(app.inkColor, dark: dark);
  }

  /// When a stylus was last seen, so palm rejection can be *conditional*
  /// (INK-4) instead of absolute.
  ///
  /// The previous rule sent every touch to pan unconditionally, which does
  /// implement palm rejection — and also means **a finger can never draw**, so
  /// on a touch-only tablet ink was simply unreachable, contradicting INK-1.
  /// The distinction the old rule missed is that a resting palm is only a
  /// hazard when a pen is in use; with no pen present, a finger is the only
  /// input the user has.
  DateTime? _lastStylus;

  /// True while a file drag hovers the page, for the drop affordance.
  bool _dragOver = false;

  /// A palm rests *while* writing, so the window only has to outlive the gap
  /// between strokes, not a pause for thought.
  static const _stylusGrace = Duration(seconds: 2);

  bool get _stylusActive {
    final t = _lastStylus;
    return t != null && DateTime.now().difference(t) < _stylusGrace;
  }

  /// Whether this touch should draw rather than pan.
  ///
  /// Single finger only: a second finger always means pan/zoom, which is what
  /// every drawing app does and what makes the canvas navigable while a drawing
  /// tool is selected.
  bool _touchDraws() => touchShouldDraw(
        mode: app.touchDrawing,
        activeTouches: _touches.length,
        stylusActive: _stylusActive,
      );

  void _noteStylus(PointerEvent e) {
    if (e.kind == PointerDeviceKind.stylus ||
        e.kind == PointerDeviceKind.invertedStylus) {
      _lastStylus = DateTime.now();
    }
  }

  /// Pen proximity → inking. Hover events are how a pen announces itself
  /// before it touches — Windows Ink and most drivers report the pen floating
  /// over the digitiser — and OneNote's behaviour on that signal is the one
  /// people's hands already know: the pen means ink, immediately, no toolbar
  /// trip. Switches only FROM Select and only on the pen's APPROACH (the
  /// first stylus signal after the grace window), so picking Select — or any
  /// tool — while the pen hovers sticks until the pen leaves and comes back.
  void _stylusProximity(PointerHoverEvent e) {
    if (e.kind != PointerDeviceKind.stylus &&
        e.kind != PointerDeviceKind.invertedStylus) {
      return;
    }
    final approaching = !_stylusActive;
    _lastStylus = DateTime.now();
    if (approaching && app.penProximitySwitch && app.tool == Tool.select) {
      app.setTool(Tool.pen);
    }
  }

  /// True while the CURRENT ink gesture erases regardless of the selected
  /// tool: the pen's tail (invertedStylus — that end IS an eraser), or its
  /// barrel button held while drawing, which is the one signal a pen button
  /// reliably reaches an application as. The OS maps whatever physical
  /// button the pen has onto it; arbitrary per-button OS actions never reach
  /// us, so this is the half of the pen-buttons ask a cross-platform app can
  /// honour.
  bool _gestureErase = false;

  /// Abandon the stroke in progress without committing it — used when a second
  /// finger lands, turning what looked like a draw into a pinch. Without this
  /// the first finger of every two-finger gesture would leave a stray mark.
  void _cancelWetStroke() {
    _cancelHold();
    _snapPreview = null;
    _resetSizing();
    if (_wet != null) setState(() => _wet = null);
  }

  bool get _lassoTool => app.tool == Tool.lasso;

  /// Decoded strokes per ink block, tagged with the `updatedAt` they were
  /// decoded at: strokes are decoded once per edit, not on every frame
  /// (§7a.6 — no hot-path JSON decoding).
  ///
  /// Keyed by **block id alone**, with the revision stored alongside, so a block
  /// that changes replaces its own entry. The previous key was
  /// `'$id#$updatedAt'` with a `length > 128 → clear()` guard, which meant a
  /// continuous erase gesture (every pointer sample bumps `updatedAt`) piled up
  /// 128 dead entries and then wiped the cache for *every* block on the page,
  /// forcing a full re-decode mid-gesture.
  final Map<String, ({int rev, List<Stroke> strokes})> _strokeCache = {};

  List<Stroke> _strokesOf(Block b) {
    final hit = _strokeCache[b.id];
    if (hit != null && hit.rev == b.updatedAt) return hit.strokes;
    final decoded = [
      for (final sj in b.content['strokes'] as List)
        Stroke.fromJson((sj as Map).cast<String, dynamic>()),
    ];
    _strokeCache[b.id] = (rev: b.updatedAt, strokes: decoded);
    return decoded;
  }

  /// The page's paper picture, decoded once per hash — see [_syncPaperImage].
  ui.Image? _paperImage;
  String? _paperImageHash;
  int _paperLoad = 0;

  /// Decode the paper picture when the page's choice changes, off the build.
  /// Until it lands the painter shows the flat paper colour, which is what a
  /// picture that fails to decode shows for good.
  void _syncPaperImage() {
    final want =
        app.pageProps.paperKind == 'image' ? app.pageProps.paperImage : null;
    if (want == _paperImageHash) return;
    _paperImageHash = want;
    _paperImage?.dispose();
    _paperImage = null;
    if (want == null) return;
    final bytes = app.blob(want);
    if (bytes == null) return;
    final ticket = ++_paperLoad;
    ui.instantiateImageCodec(bytes).then((codec) async {
      final frame = await codec.getNextFrame();
      codec.dispose();
      if (!mounted || ticket != _paperLoad) {
        frame.image.dispose();
        return;
      }
      setState(() => _paperImage = frame.image);
    }).catchError((_) {});
  }

  @override
  void dispose() {
    _paperImage?.dispose();
    _wetTick.dispose();
    _penCursor.dispose();
    _glideArm?.cancel();
    _scrollFade?.cancel();
    _holdTimer?.cancel();
    controller.stopGlide();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      controller.pageSize = app.pageSize();
      // Restore this page's remembered view if the user actually adjusted it
      // (§7a.5); otherwise fit the page width so content placed off to the
      // right — e.g. imported images at their OneNote offsets — is visible on
      // open instead of sitting off-screen. A stored default view (100%,
      // top-left) counts as "unadjusted" and gets the fit.
      final mem = app.pageId == null ? null : app.viewFor(app.pageId!);
      if (mem != null && !(mem[0] == 1.0 && mem[1] == 0.0 && mem[2] == 0.0)) {
        controller.jumpTo(mem[0], Offset(mem[1], mem[2]));
        controller.clampToPage();
      } else if (app.defaultStretchToScreen) {
        // "Fit new pages to width": the page opens filling the window width
        // (fillWidth zooms IN as well as out), the reliable place being here —
        // the viewport is laid out by this post-frame, which it is not yet when
        // the page is first selected.
        app.fitPageToWidth();
      } else {
        controller.fitWidth(app.contentExtent().right);
      }
    });
  }

  // ── Ink capture (page-space, Ink Data Spec §1) ──────────────────────────

  void _inkDown(PointerDownEvent e) {
    app.claimedPointers.remove(e.pointer); // keep the claim set tidy
    _lastInkScreenPos = e.localPosition;
    // A placed shape is waiting to be moved or dropped: this pointer drives
    // it, not a new stroke. A drag repositions it; a tap (below) drops it.
    if (_placedShape != null) {
      _placedDragBase = _placedShape;
      _dragAnchorScreen = e.localPosition;
      _placedMoved = 0;
      return;
    }
    // The pen's own erase signals, per gesture: the tail end, or the barrel
    // button held at contact. (kPrimaryStylusButton shares its bit with
    // kSecondaryButton, which is exactly how Windows reports a barrel press —
    // the kind guard is what keeps a right-click mouse drag from erasing.)
    _gestureErase = e.kind == PointerDeviceKind.invertedStylus ||
        ((e.kind == PointerDeviceKind.stylus) &&
            (e.buttons & kPrimaryStylusButton) != 0);
    final pt = _clampToPagePoint(controller.screenToPage(e.localPosition));
    if (app.tool == Tool.eraser || _gestureErase) {
      _eraseAt(pt);
      return;
    }
    final dark = Theme.of(context).brightness == Brightness.dark;
    // One palette, read from state — the swatch row, this stroke and the
    // drawn cursor must agree, and they only do if they read the same list.
    var color = app.inkColor;
    if (dark && color == OnoteColors.graphite900) color = OnoteColors.moon0;
    setState(() {
      _wet = Stroke(
        tool: app.tool == Tool.highlighter ? 'highlighter' : 'pen',
        colorHex: onoteHexOf(color),
        size: app.penSize,
        opacity: app.tool == Tool.highlighter ? 0.4 : 1.0,
      );
      _addPoint(e, pt);
      _snapPreview = null;
    });
    if (app.autoShape) {
      _holdAnchor = Offset(pt.dx, pt.dy);
      _holdTimer?.cancel();
      _holdTimer = Timer(_holdToSnap, _offerShape);
    }
  }

  void _inkMove(PointerMoveEvent e) {
    if (app.tool == Tool.eraser || _gestureErase) {
      _eraseAt(controller.screenToPage(e.localPosition));
      return;
    }
    _lastInkScreenPos = e.localPosition;
    // Moving a placed shape around before it is dropped.
    if (_placedShape != null) {
      _dragPlacedShape(e);
      return;
    }
    if (_wet == null) return;
    // After a snap, the shape is LOCKED: dragging resizes it instead of
    // adding to the stroke or throwing the proposal away.
    if (_sizingShape) {
      _resizeSnappedShape(e);
      return;
    }
    // Repaint-only: grow the stroke and nudge the ink painter. No setState —
    // rebuilding every visible block per point made inking sluggish.
    _addPoint(e, _clampToPagePoint(controller.screenToPage(e.localPosition)));
    // Moving again withdraws any proposal and restarts the clock. Only a
    // MEANINGFUL move counts: a hand resting on a trackpad jitters by a
    // pixel, and treating that as "still drawing" is why a hold-to-act
    // gesture feels broken on some hardware.
    if (app.autoShape) _noteDrawingMovement();
    _wetTick.value++;
  }

  /// Resize the snapped shape while the drawing pointer is still held: up
  /// grows it, down shrinks it, about the centre it snapped at.
  void _resizeSnappedShape(PointerMoveEvent e) {
    final base = _snapBase, c = _snapCenter, anchorY = _sizeAnchorScreenY;
    if (base == null || c == null || anchorY == null) return;
    // Up is a smaller screen Y, so `anchorY - y` is positive when growing.
    // ~200px of travel doubles or halves it, which feels neither twitchy nor
    // sluggish; clamped so it can never invert or vanish.
    final dy = anchorY - e.localPosition.dy;
    final factor = (1 + dy / 200.0).clamp(0.15, 6.0);
    setState(() => _snapPreview = _scaleStroke(base, c, factor));
  }

  /// Drag the placed shape to a new spot. Screen delta becomes page delta so
  /// it tracks the pointer at any zoom.
  void _dragPlacedShape(PointerMoveEvent e) {
    final base = _placedDragBase, start = _dragAnchorScreen;
    if (base == null || start == null) return;
    final d = e.localPosition - start;
    _placedMoved = math.max(_placedMoved, d.distance);
    setState(() => _placedShape = _translateStroke(
        base, d.dx / controller.scale, d.dy / controller.scale));
  }

  /// Distance a pointer may wander and still count as held still.
  static const double _holdSlop = 3.0;
  Offset? _holdAnchor;

  void _noteDrawingMovement() {
    final w = _wet;
    if (w == null || w.x.isEmpty) return;
    final at = Offset(w.x.last, w.y.last);
    final anchor = _holdAnchor;
    if (anchor != null && (at - anchor).distance < _holdSlop) return;
    _holdAnchor = at;
    if (_snapPreview != null) {
      // Withdraw the proposal. setState because the painter's `wet` changes
      // identity, not just its contents.
      setState(() => _snapPreview = null);
    }
    _holdTimer?.cancel();
    _holdTimer = Timer(_holdToSnap, _offerShape);
  }

  /// Hold expired: propose a shape, if the stroke reads as one. The proposal
  /// then LOCKS — from here dragging resizes it rather than redrawing — so the
  /// snap arms the sizing state and remembers the shape and where it sits.
  void _offerShape() {
    final w = _wet;
    if (w == null || !app.autoShape) return;
    final snapped = ShapeSnap.snap(w);
    if (snapped == null) return;
    setState(() {
      _snapPreview = snapped;
      _snapBase = snapped;
      _snapCenter = _strokeCenter(snapped);
      _sizingShape = true;
      _sizeAnchorScreenY =
          _lastInkScreenPos?.dy ?? controller.pageToScreen(_snapCenter!).dy;
    });
  }

  void _cancelHold() {
    _holdTimer?.cancel();
    _holdTimer = null;
    _holdAnchor = null;
  }

  /// Clear the auto-shape sizing state (the snapped-and-holding phase). Does
  /// not touch a placed shape, which outlives the gesture that made it.
  void _resetSizing() {
    _sizingShape = false;
    _snapBase = null;
    _snapCenter = null;
    _sizeAnchorScreenY = null;
  }

  /// The centre of a stroke's bounding box, in page space.
  Offset _strokeCenter(Stroke s) {
    var minX = double.infinity, minY = double.infinity;
    var maxX = -double.infinity, maxY = -double.infinity;
    for (var i = 0; i < s.x.length; i++) {
      minX = math.min(minX, s.x[i]);
      maxX = math.max(maxX, s.x[i]);
      minY = math.min(minY, s.y[i]);
      maxY = math.max(maxY, s.y[i]);
    }
    return Offset((minX + maxX) / 2, (minY + maxY) / 2);
  }

  /// A copy of [s] with its coordinates remapped, keeping pressure, tilt and
  /// timing intact so the resized or moved shape is still the same ink.
  Stroke _mapStroke(
          Stroke s, double Function(double) fx, double Function(double) fy) =>
      Stroke(
        tool: s.tool,
        colorHex: s.colorHex,
        size: s.size,
        opacity: s.opacity,
        x: [for (final v in s.x) fx(v)],
        y: [for (final v in s.y) fy(v)],
        p: List<double>.of(s.p),
        tx: List<double>.of(s.tx),
        ty: List<double>.of(s.ty),
        t: List<int>.of(s.t),
        sharp: s.sharp,
      );

  Stroke _scaleStroke(Stroke s, Offset c, double factor) => _mapStroke(
      s, (v) => c.dx + (v - c.dx) * factor, (v) => c.dy + (v - c.dy) * factor);

  Stroke _translateStroke(Stroke s, double dx, double dy) =>
      _mapStroke(s, (v) => v + dx, (v) => v + dy);

  Offset _clampToPagePoint(Offset p) =>
      Offset(math.max(0, p.dx), math.max(0, p.dy));

  void _addPoint(PointerEvent e, Offset pagePt) {
    final w = _wet!;
    w.x.add(pagePt.dx);
    w.y.add(pagePt.dy);
    w.p.add(e.pressure.isFinite && e.pressureMax > 0
        ? (e.pressure / e.pressureMax).clamp(0.0, 1.0)
        : 0.5);
    w.t.add(nowMs() - w.strokeStart);
  }

  void _inkUp(PointerUpEvent e) {
    // A placed shape is being adjusted: a plain tap drops it into the page and
    // hands the pen back; a drag has just moved it, so it stays active for the
    // next drag or the placing tap.
    if (_placedShape != null) {
      final s = _placedShape!;
      final wasTap = _placedMoved < _placeTapSlop;
      _placedDragBase = null;
      _dragAnchorScreen = null;
      if (wasTap) {
        setState(() => _placedShape = null);
        _commitStroke(s);
      }
      return;
    }
    final wasErasing = app.tool == Tool.eraser || _gestureErase;
    final erasedSomething = _eraseUndoPushed;
    _eraseUndoPushed = false;
    _gestureErase = false;
    _cancelHold();
    // A snapped shape (resized or not) does NOT commit on release. It becomes
    // a floating, draggable copy; the placing tap above is what commits it.
    if (_sizingShape && _snapPreview != null) {
      setState(() {
        _placedShape = _snapPreview;
        _snapPreview = null;
        _wet = null;
        _resetSizing();
      });
      return;
    }
    _resetSizing();
    // ERASING HANDS THE PEN BACK.
    //
    // Only when something was actually rubbed out: a stray click with the
    // eraser up should not silently change tool, and `_eraseUndoPushed` is
    // exactly "this gesture removed ink" — it is what pushed the undo entry.
    // The gesture-erase path (pen tail, barrel button) is excluded because
    // the tool was never the eraser there; the hand already went back.
    if (wasErasing && erasedSomething && app.tool == Tool.eraser) {
      app.setTool(Tool.pen);
    }
    final w = _wet;
    if (w == null || w.x.length < 2) {
      setState(() => _wet = null);
      return;
    }
    app.pushUndo();
    // The stroke that was ON SCREEN when the hand let go is the one that
    // commits. If a proposal was showing, the user saw it and accepted it by
    // releasing; if not, nothing is changed underneath them.
    //
    // Deliberately NO snap attempt here any more. Snapping on release was
    // startling: you drew a line, let go, and the app rewrote it — with no
    // warning, no preview and no way to decline. Holding still is the signal
    // now, and it is a signal you can watch and take back.
    final stroke = _snapPreview ?? w;
    _snapPreview = null;
    _commitStroke(stroke, pushUndo: false);
    setState(() => _wet = null);
  }

  /// Write [stroke] into the page — the recent ink block if there is one, or a
  /// fresh block. Shared by live inking and by dropping a placed auto-shape.
  void _commitStroke(Stroke stroke, {bool pushUndo = true}) {
    if (pushUndo) app.pushUndo();
    Block? target;
    for (final b in app.blocks.reversed) {
      if (b.type == BlockType.ink &&
          nowMs() - b.updatedAt < 2000 &&
          (b.content['strokes'] as List).length < 512) {
        target = b;
        break;
      }
    }
    target ??= app.addBlock(
        Block(type: BlockType.ink, x: 0, y: 0, content: {'strokes': []}),
        recordUndo: false);
    (target.content['strokes'] as List).add(stroke.toJson());
    _refitInkBounds(target);
    app.updateBlock(target);
    setState(() {});
  }

  /// The strokes for the current two-corner tool (arrow or rectangle), in the
  /// pen's colour and weight. Shared by the commit below and the drag preview
  /// so what you drag is exactly what you get.
  List<Stroke> _twoCornerStrokes(Offset2 from, Offset2 to, String colorHex) {
    return _rectTool
        ? rectangleStrokes(
            from: from, to: to, colorHex: colorHex, size: app.penSize)
        : arrowStrokes(
            from: from, to: to, colorHex: colorHex, size: app.penSize);
  }

  /// Put a two-corner shape (arrow or rectangle) on the page, in the pen's
  /// colour and weight.
  void _commitShape(Offset2 from, Offset2 to) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    var color = app.inkColor;
    if (dark && color == OnoteColors.graphite900) color = OnoteColors.moon0;
    final strokes = _twoCornerStrokes(from, to, onoteHexOf(color));
    // Too short to have a shape — an arrow with no direction, a box with no
    // size — so there is nothing to place.
    if (strokes.isEmpty) return;
    app.pushUndo();
    final target = app.addBlock(
        Block(type: BlockType.ink, x: 0, y: 0, content: {'strokes': []}),
        recordUndo: false);
    // One block for all the shape's strokes: erase, lasso and recolour all act
    // on a block's strokes, so a shape in one block is one they treat whole.
    for (final st in strokes) {
      (target.content['strokes'] as List).add(st.toJson());
    }
    _refitInkBounds(target);
    app.updateBlock(target);
    setState(() {});
  }

  /// True area-erase (INK-6, Ink Spec §2): remove points within the eraser
  /// radius and split surviving runs into fresh strokes.
  void _eraseAt(Offset pt) {
    if (!_eraseUndoPushed) {
      app.pushUndo();
      _eraseUndoPushed = true;
    }
    final radius = 12.0 / controller.scale;
    final r2 = radius * radius;
    // INK-6: 'area' rubs points out mid-stroke (splitting survivors); 'stroke'
    // removes any stroke the eraser touches whole — OneNote's default, and the
    // mode that makes cleaning up a scratched-out word one swipe instead of
    // twenty.
    final wholeStroke = app.eraserMode == EraserMode.stroke;
    var changed = false;
    for (final b in app.blocks.where((b) => b.type == BlockType.ink)) {
      // Cheap reject: the eraser can only affect a block whose rect it touches.
      // This runs per pointer sample, so skipping distant blocks before looking
      // at any stroke is what keeps erasing cheap on an ink-heavy page.
      if (!_blockRect(b).inflate(radius).contains(pt)) continue;
      final strokes = (b.content['strokes'] as List);
      // Reuse the decoded strokes rather than re-parsing JSON per sample.
      final decoded = _strokesOf(b);
      final out = <Map<String, dynamic>>[];
      var blockChanged = false;
      for (var si = 0; si < strokes.length; si++) {
        final sj = strokes[si] as Map;
        final s = si < decoded.length
            ? decoded[si]
            : Stroke.fromJson(sj.cast<String, dynamic>());
        // Squared distance — avoids a sqrt per point per sample.
        final keep = List<bool>.generate(s.x.length, (i) {
          final dx = s.x[i] - pt.dx, dy = s.y[i] - pt.dy;
          return dx * dx + dy * dy >= r2;
        });
        if (!keep.contains(false)) {
          out.add(sj.cast<String, dynamic>());
          continue;
        }
        if (wholeStroke) {
          // Touched at all → the whole stroke goes; no splitting.
          blockChanged = true;
          continue;
        }
        blockChanged = true;
        // Split surviving runs into new strokes (fresh ids per spec §2).
        var i = 0;
        while (i < keep.length) {
          if (!keep[i]) {
            i++;
            continue;
          }
          var j = i;
          while (j < keep.length && keep[j]) {
            j++;
          }
          if (j - i >= 2) {
            out.add(Stroke(
              tool: s.tool,
              colorHex: s.colorHex,
              size: s.size,
              opacity: s.opacity,
              x: s.x.sublist(i, j),
              y: s.y.sublist(i, j),
              p: s.p.isEmpty ? [] : s.p.sublist(i, j),
              // Carry per-point channels through the split, or erasing would
              // quietly strip tilt from the surviving runs.
              tx: s.tx.isEmpty ? [] : s.tx.sublist(i, j),
              ty: s.ty.isEmpty ? [] : s.ty.sublist(i, j),
              t: s.t.sublist(i, j),
              strokeStart: s.strokeStart,
              sharp: s.sharp,
            ).toJson());
          }
          i = j;
        }
      }
      if (blockChanged) {
        changed = true;
        b.content['strokes'] = out;
        if (out.isNotEmpty) _refitInkBounds(b);
        app.updateBlock(b);
      }
    }
    if (changed) {
      app.blocks.removeWhere((b) =>
          b.type == BlockType.ink && (b.content['strokes'] as List).isEmpty);
      app.markDirty();
      setState(() {});
    }
  }

  void _refitInkBounds(Block b) {
    var mnx = double.infinity, mny = double.infinity, mxx = -1e18, mxy = -1e18;
    for (final sj in b.content['strokes'] as List) {
      final s = Stroke.fromJson((sj as Map).cast<String, dynamic>());
      final bb = s.bounds();
      mnx = math.min(mnx, bb.minX);
      mny = math.min(mny, bb.minY);
      mxx = math.max(mxx, bb.maxX);
      mxy = math.max(mxy, bb.maxY);
    }
    if (mnx.isFinite) {
      b
        ..x = mnx
        ..y = mny
        ..w = mxx - mnx
        ..h = mxy - mny;
    }
  }

  // ── Lasso-select ink (INK-7) ────────────────────────────────────────────

  void _lassoDown(PointerDownEvent e) {
    app.claimedPointers.remove(e.pointer);
    setState(() =>
        _lasso = [_clampToPagePoint(controller.screenToPage(e.localPosition))]);
  }

  void _lassoMove(PointerMoveEvent e) {
    if (_lasso == null) return;
    setState(() => _lasso!
        .add(_clampToPagePoint(controller.screenToPage(e.localPosition))));
  }

  void _lassoUp(PointerUpEvent e) {
    final poly = _lasso;
    setState(() => _lasso = null);
    if (poly == null || poly.length < 3) return;
    _gatherLassoedStrokes(poly);
  }

  /// Gather every stroke whose points mostly fall inside the drawn loop into a
  /// single new ink block, then select it — so the existing move/delete/copy
  /// machinery works on a freeform ink selection regardless of which blocks the
  /// strokes originally lived in (Ink Spec §2: strokes are immutable and carry
  /// page-absolute coordinates, so re-homing them is just a splice).
  void _gatherLassoedStrokes(List<Offset> poly) {
    // 1) Detect matches WITHOUT mutating, so the undo snapshot below captures
    //    the true pre-lasso state.
    final gathered = <Map<String, dynamic>>[];
    final keepByBlock = <String, List<dynamic>>{};
    for (final b in app.blocks.where((b) => b.type == BlockType.ink)) {
      final keep = <dynamic>[];
      var blockChanged = false;
      for (final sj in (b.content['strokes'] as List)) {
        final s = Stroke.fromJson((sj as Map).cast<String, dynamic>());
        if (_strokeInsidePoly(s, poly)) {
          gathered.add(sj.cast<String, dynamic>());
          blockChanged = true;
        } else {
          keep.add(sj);
        }
      }
      if (blockChanged) keepByBlock[b.id] = keep;
    }
    if (gathered.isEmpty) return;

    // 2) Snapshot, then apply: splice matched strokes out of their blocks,
    //    drop now-empty blocks, and re-home the gathered strokes into one new
    //    selected ink block.
    app.pushUndo();
    for (final entry in keepByBlock.entries) {
      final b = app.blocks.where((x) => x.id == entry.key).firstOrNull;
      if (b == null) continue;
      if (entry.value.isEmpty) {
        app.removeBlock(b.id, recordUndo: false);
      } else {
        b.content['strokes'] = entry.value;
        _refitInkBounds(b);
        b.updatedAt = nowMs();
      }
    }
    final grouped = app.addBlock(
        Block(type: BlockType.ink, x: 0, y: 0, content: {'strokes': gathered}),
        recordUndo: false);
    _refitInkBounds(grouped);
    app.updateBlock(grouped);
    app.select(grouped.id);
    // Switch back to Select so the gathered ink can be dragged/deleted at once.
    app.setTool(Tool.select);
  }

  /// A stroke counts as lassoed when the majority of its sample points lie
  /// inside the loop — robust to a stroke poking slightly outside the boundary.
  bool _strokeInsidePoly(Stroke s, List<Offset> poly) {
    if (s.x.isEmpty) return false;
    var inside = 0;
    for (var i = 0; i < s.x.length; i++) {
      if (_pointInPoly(Offset(s.x[i], s.y[i]), poly)) inside++;
    }
    return inside / s.x.length >= 0.6;
  }

  /// Ray-casting point-in-polygon test.
  bool _pointInPoly(Offset pt, List<Offset> poly) {
    var inside = false;
    for (var i = 0, j = poly.length - 1; i < poly.length; j = i++) {
      final a = poly[i], b = poly[j];
      if (((a.dy > pt.dy) != (b.dy > pt.dy)) &&
          (pt.dx < (b.dx - a.dx) * (pt.dy - a.dy) / (b.dy - a.dy) + a.dx)) {
        inside = !inside;
      }
    }
    return inside;
  }

  // ── Touch pan/pinch (shared: pen-mode palm rejection & navigation) ──────

  void _touchDown(PointerDownEvent e) {
    _touches[e.pointer] = e.localPosition;
    _lastScreen = e.localPosition;
    if (_touches.length == 2) {
      final pts = _touches.values.toList();
      _pinchBaseDist = (pts[0] - pts[1]).distance;
    }
  }

  void _touchMove(PointerMoveEvent e) {
    _touches[e.pointer] = e.localPosition;
    if (_touches.length >= 2 && _pinchBaseDist != null) {
      final pts = _touches.values.toList();
      final d = (pts[0] - pts[1]).distance;
      final focal = (pts[0] + pts[1]) / 2;
      if (_pinchBaseDist! > 0 && d > 0) {
        controller.zoomAt(focal, d / _pinchBaseDist!);
        _pinchBaseDist = d;
      }
      setState(() {});
    } else if (_touches.length == 1) {
      controller.panBy(e.localPosition - _lastScreen);
      _lastScreen = e.localPosition;
      setState(() {});
    }
  }

  void _touchUp(PointerUpEvent e) {
    _touches.remove(e.pointer);
    if (_touches.length < 2) _pinchBaseDist = null;
    if (_touches.length == 1) _lastScreen = _touches.values.first;
  }

  // ── Select-mode pointer model ───────────────────────────────────────────

  Rect _blockRect(Block b) =>
      Rect.fromLTWH(b.x, b.y, b.w, b.h ?? app.renderSizes[b.id]?.height ?? 60);

  String? _hitInk(Offset pagePt) {
    for (final b in app.blocks.reversed.where((b) => b.type == BlockType.ink)) {
      if (_blockRect(b).inflate(6).contains(pagePt)) return b.id;
    }
    return null;
  }

  void _selectDown(PointerDownEvent e) {
    if (app.claimedPointers.remove(e.pointer)) return; // a block owns this one
    _downScreen = e.localPosition;
    _lastScreen = e.localPosition;
    _downKind = e.kind;

    if (e.kind == PointerDeviceKind.mouse &&
        (e.buttons & kMiddleMouseButton) != 0) {
      _mode = _DragMode.pan;
      return;
    }
    // Right-click on empty canvas → context menu (blocks claim theirs first).
    if (e.kind == PointerDeviceKind.mouse &&
        (e.buttons & kSecondaryMouseButton) != 0) {
      _mode = _DragMode.none;
      showCanvasMenu(
          context, app, e.position, controller.screenToPage(e.localPosition));
      return;
    }
    if (e.kind == PointerDeviceKind.touch) {
      _touches[e.pointer] = e.localPosition;
      if (_touches.length == 2) {
        final pts = _touches.values.toList();
        _pinchBaseDist = (pts[0] - pts[1]).distance;
        _mode = _DragMode.none;
        return;
      }
    }

    final pagePt = controller.screenToPage(e.localPosition);
    final inkHit = _hitInk(pagePt);
    if (inkHit != null) {
      if (!app.selectedIds.contains(inkHit)) {
        app.select(inkHit, additive: HardwareKeyboard.instance.isShiftPressed);
      }
      _mode = _DragMode.moveSelection;
      _moveUndoPushed = false;
      app.setDragging(true);
      return;
    }
    _mode = _DragMode.pending;
    _marqueeStartPage = pagePt;
    _marqueeEndPage = pagePt;
  }

  void _selectMove(PointerMoveEvent e) {
    if (_touches.containsKey(e.pointer)) {
      _touches[e.pointer] = e.localPosition;
      if (_touches.length == 2 && _pinchBaseDist != null) {
        final pts = _touches.values.toList();
        final d = (pts[0] - pts[1]).distance;
        final focal = (pts[0] + pts[1]) / 2;
        if (_pinchBaseDist! > 0 && d > 0) {
          controller.zoomAt(focal, d / _pinchBaseDist!);
          _pinchBaseDist = d;
        }
        setState(() {});
        return;
      }
    }
    final delta = e.localPosition - _lastScreen;
    _lastScreen = e.localPosition;
    switch (_mode) {
      case _DragMode.pan:
        controller.panBy(delta);
        setState(() {});
      case _DragMode.pending:
        if ((e.localPosition - _downScreen).distance > 5) {
          if (_downKind == PointerDeviceKind.touch) {
            // A finger drag on empty page pans (see _downKind). The distance
            // already travelled is applied too, so the page doesn't hiccup
            // by the 5px it took to decide.
            _mode = _DragMode.pan;
            controller.panBy(e.localPosition - _downScreen);
          } else {
            _mode = _DragMode.marquee;
            _marqueeEndPage = controller.screenToPage(e.localPosition);
          }
          setState(() {});
        }
      case _DragMode.marquee:
        _marqueeEndPage = controller.screenToPage(e.localPosition);
        setState(() {});
      case _DragMode.moveSelection:
        if (!_moveUndoPushed) {
          app.pushUndo();
          _moveUndoPushed = true;
        }
        app.moveSelectedBy(
            delta.dx / controller.scale, delta.dy / controller.scale);
      case _DragMode.none:
        break;
    }
  }

  void _selectUp(PointerUpEvent e) {
    _touches.remove(e.pointer);
    if (_touches.length < 2) _pinchBaseDist = null;
    final mode = _mode;
    _mode = _DragMode.none;
    switch (mode) {
      case _DragMode.pending:
        final pagePt = controller.screenToPage(e.localPosition);
        if (app.tool == Tool.text) {
          _createTextAt(pagePt); // Text tool: always create
        } else if (app.selectedIds.isNotEmpty || app.editingBlockId != null) {
          app.select(null); // first click clears; next click creates
        } else {
          // Click-anywhere-to-type (CANVAS-3). The seamless backdrop is part
          // of the page, so this also works out in the margin when zoomed out.
          _createTextAt(pagePt);
        }
      case _DragMode.marquee:
        final rect = Rect.fromPoints(_marqueeStartPage, _marqueeEndPage);
        final hit = [
          for (final b in app.blocks)
            if (rect.overlaps(_blockRect(b))) b.id
        ];
        hit.isEmpty ? app.select(null) : app.selectMany(hit);
        setState(() {});
      case _DragMode.moveSelection:
        app.settleSelected();
        app.setDragging(false);
        _moveUndoPushed = false;
      default:
        break;
    }
  }

  void _createTextAt(Offset pagePt) {
    // OneNote-style: interpret intent rather than land pixel-exact.
    final pos = app.smartTextPosition(pagePt);
    final b = app.addBlock(Block(
      type: BlockType.text,
      x: pos.dx,
      y: pos.dy,
      w: 320,
      content: {'text': ''},
    ));
    // OneNote-style pending caret (owner): no chrome, and arrow keys
    // navigate the page, until the first keystroke. Set BEFORE select()
    // notifies, so BlockView's very first build already sees it — set any
    // later and the chrome would flash on for exactly one frame.
    app.pendingEmptyBlockId = b.id;
    app.select(b.id, edit: true);
    if (app.tool == Tool.text) app.setTool(Tool.select);
  }

  // ── The page scroll bar ─────────────────────────────────────────────────

  /// Hover/drag state for the bar, for the colour feedback a control that
  /// consumes your pointer owes you.
  bool _scrollbarHover = false;
  bool _scrollbarDrag = false;

  /// Screen-space vertical scroll bar, present only when the page is taller
  /// than the viewport at the current zoom. Built inside the canvas's
  /// AnimatedBuilder, so it tracks every pan and zoom without its own state.
  List<Widget> _scrollBar(BuildContext context, bool dark) {
    final vp = controller.viewport;
    final ps = controller.pageSize;
    if (ps == null || vp == Size.zero) return const [];
    final insets = widget.insets;
    final visibleH = vp.height - insets.vertical;
    final docH = ps.height * controller.scale;
    final scrollable = docH - visibleH;
    if (scrollable <= 1 || visibleH <= 0) return const [];

    const margin = 4.0;
    final trackH = visibleH - margin * 2;
    final thumbH = (trackH * visibleH / docH).clamp(48.0, trackH);
    final range = trackH - thumbH;
    if (range <= 0) return const [];
    final progress =
        ((insets.top - controller.offset.dy) / scrollable).clamp(0.0, 1.0);
    // Visible while it is being used, and for a moment after any scrolling.
    // A bar that is always on takes a strip of the page for information you
    // only want at the moment you are moving — which is why every platform
    // stopped drawing them permanently.
    final live = _scrollbarDrag || _scrollbarHover;
    final shown = live || _scrolledRecently;

    void jumpTo(double localY) {
      final p = ((localY - margin - thumbH / 2) / range).clamp(0.0, 1.0);
      controller
          .panBy(Offset(0, insets.top - p * scrollable - controller.offset.dy));
    }

    return [
      // The track: click to jump, drag to scroll. Kept narrow so the strip
      // it takes from the page edge is the width every other app's scroll
      // bar already takes.
      Positioned(
        right: 0,
        top: insets.top,
        bottom: insets.bottom,
        width: 12,
        child: MouseRegion(
          onEnter: (_) => setState(() => _scrollbarHover = true),
          onExit: (_) => setState(() => _scrollbarHover = false),
          child: Listener(
            // CLAIM the pointer, exactly as a block does. The canvas's
            // select-mode handler is a raw Listener, not a gesture-arena
            // participant — the GestureDetector below winning its arena
            // means nothing to it, so a drag on the track was ALSO a
            // pending→marquee on the canvas: "it draws up a box behind it
            // as it goes up".
            onPointerDown: (e) => app.claimedPointers.add(e.pointer),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (d) => jumpTo(d.localPosition.dy),
              onVerticalDragStart: (_) {
                controller.stopGlide();
                setState(() => _scrollbarDrag = true);
              },
              onVerticalDragUpdate: (d) {
                controller.panBy(Offset(0, -d.delta.dy * scrollable / range));
                _noteScrollActivity();
              },
              onVerticalDragEnd: (_) => setState(() => _scrollbarDrag = false),
              onVerticalDragCancel: () =>
                  setState(() => _scrollbarDrag = false),
              child: AnimatedOpacity(
                opacity: shown ? 1 : 0,
                duration: Duration(milliseconds: shown ? 90 : 320),
                curve: Curves.easeOut,
                child: Container(
                  color: (dark ? OnoteColors.night200 : OnoteColors.paper200)
                      .withValues(alpha: live ? .55 : .35),
                ),
              ),
            ),
          ),
        ),
      ),
      Positioned(
        right: 2,
        top: insets.top + margin + progress * range,
        child: IgnorePointer(
          // The track above owns the gestures; the thumb is the indicator —
          // brighter under the mouse, primary while dragging, so consuming
          // the pointer LOOKS like consuming the pointer.
          //
          // In fast, out slow: it has to be there the instant you start
          // moving, and leaving quickly reads as a flicker.
          child: AnimatedOpacity(
            opacity: shown ? 1 : 0,
            duration: Duration(milliseconds: shown ? 90 : 320),
            curve: Curves.easeOut,
            child: Container(
              width: 8,
              height: thumbH,
              decoration: BoxDecoration(
                color: _scrollbarDrag
                    ? Theme.of(context).colorScheme.primary
                    : (dark ? OnoteColors.moon100 : OnoteColors.graphite500)
                        .withValues(alpha: _scrollbarHover ? .85 : .55),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
        ),
      ),
    ];
  }

  // ── Wheel / trackpad ────────────────────────────────────────────────────

  /// Pan or zoom the page.
  ///
  /// **Through the resolver.** A wheel notch is delivered to every listener
  /// under the pointer, innermost first, and something inside the page may
  /// want it instead — a graph zooms its own window. Registering here means
  /// the page only moves when nothing inner claimed the notch first.
  void _onScroll(PointerSignalEvent e) {
    if (e is! PointerScrollEvent) return;
    GestureBinding.instance.pointerSignalResolver.register(e, (_) {
      final ctrl = HardwareKeyboard.instance.isControlPressed ||
          HardwareKeyboard.instance.isMetaPressed;
      final shift = HardwareKeyboard.instance.isShiftPressed;
      // Any new input cancels the glide. Without this a second flick fights
      // the tail of the first, and the page ends up somewhere neither of
      // them asked for.
      controller.stopGlide();
      if (ctrl) {
        controller.zoomAt(
            e.localPosition, e.scrollDelta.dy > 0 ? 1 / 1.1 : 1.1);
      } else if (shift) {
        // Shift+wheel → horizontal scroll (a mouse's vertical wheel drives X).
        controller.panBy(Offset(-e.scrollDelta.dy - e.scrollDelta.dx, 0));
      } else {
        final delta = -e.scrollDelta;
        controller.panBy(delta);
        // Remember the last notch and when it landed, so the moment the
        // scrolling STOPS we know how fast it was going. A wheel gives no
        // "end" event, so the glide is armed by a timer that the next notch
        // keeps resetting.
        _lastScrollDelta = delta;
        _armGlide();
      }
      _noteScrollActivity();
      setState(() {});
    });
  }

  // ── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    // A placed auto-shape lives on the pen/highlighter path. If the tool
    // changed out from under it (say to Select), drop it into the page rather
    // than leave a shape on screen with nothing able to move it.
    if (_placedShape != null &&
        app.tool != Tool.pen &&
        app.tool != Tool.highlighter) {
      final s = _placedShape;
      _placedShape = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (s != null && mounted) _commitStroke(s);
      });
    }
    // Page size is content-driven (this bounds scrolling — constrained
    // horizontal at normal zoom). The backdrop is drawn the same colour as the
    // page (seamless — no "page floating on canvas"), and clicks anywhere in
    // the viewport create content, so zooming out lets you place a box out in
    // the margin; if you don't, the page reconstrains to content next frame.
    final ext = app.contentExtent();
    final pw =
        math.max(app.pageProps.pageWidth, ext.right + AppState.pageGrowMargin);
    // In page mode the surface is a whole number of SHEETS, including the
    // blank ones you can scroll onto — otherwise page 2 does not exist until
    // something has been drawn at the bottom of page 1, which is the wrong
    // way round.
    final ph = app.pageProps.isPaged
        ? app.pageProps.paper.height * app.scrollableSheetCount
        : math.max(
            AppState.defaultPageHeight, ext.bottom + AppState.pageGrowMargin);
    final pageSize = Size(pw, ph);
    controller.pageSize = pageSize;
    controller.insets = widget.insets;
    _syncPaperImage();

    Widget canvas = LayoutBuilder(builder: (context, constraints) {
      controller.viewport = Size(constraints.maxWidth, constraints.maxHeight);
      return AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          // Visible page-space rect (padded) for culling (CANVAS-9). Computed
          // INSIDE the AnimatedBuilder: the transform changes without a full
          // rebuild (viewport assignment above, per-page view restore, pans), and
          // a culling list captured outside would go stale — the "page is blank
          // until I scroll" bug, where the first frame culled everything against
          // an uninitialised viewport and nothing invalidated the list.
          final visible = Rect.fromPoints(
            controller.screenToPage(Offset.zero),
            controller.screenToPage(
                Offset(controller.viewport.width, controller.viewport.height)),
          ).inflate(200);
          final inkBlocks = app.blocks.where((b) => b.type == BlockType.ink);
          final visibleStrokes = [
            for (final b in inkBlocks)
              // Never cull the selected/editing block (CANVAS-9), so a selected
              // ink block off-screen still paints under its selection rect.
              if (app.selectedIds.contains(b.id) ||
                  app.editingBlockId == b.id ||
                  visible.overlaps(_blockRect(b)))
                ..._strokesOf(b),
          ];
          final selectedInkRects = [
            for (final b in inkBlocks)
              if (app.selectedIds.contains(b.id)) _blockRect(b),
          ];
          return RepaintBoundary(
            key: app.canvasKey,
            child: ClipRect(
              child: Stack(
                children: [
                  // Backdrop + page surface + page background pattern
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _PagePainter(
                        controller: controller,
                        pageSize: pageSize,
                        background: app.pageProps.background,
                        paper: app.pageProps.paperKind,
                        paperImage: _paperImage,
                        // The PATTERN's spacing, not the SNAP grid's — see
                        // PageProps.bgSpacing for why those stopped being one
                        // number.
                        spacing: app.pageProps.bgSpacing,
                        dark: dark,
                        sheet: app.pageProps.isPaged
                            ? Size(app.pageProps.paper.width,
                                app.pageProps.paper.height)
                            : null,
                        sheets: app.scrollableSheetCount,
                      ),
                    ),
                  ),
                  // Page space. `Positioned(left/top only)` gives loose
                  // constraints so the inner Stack can be sized to the FULL page
                  // (not the viewport). This is essential for hit-testing: a Stack
                  // sized to the viewport refuses pointer events on children below
                  // the fold, so clicks on a tall text box's lower half used to
                  // fall through and create a new box (the reported bug).
                  Positioned(
                    left: 0,
                    top: 0,
                    child: Transform(
                      transform: controller.matrix,
                      child: SizedBox(
                        width: pageSize.width,
                        height: pageSize.height,
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            // In-page title band (OneNote-style)
                            Positioned(
                              left: AppState.pageLeftMargin,
                              top: 20,
                              child: IgnorePointer(
                                ignoring: _inkTool,
                                child: PageTitleView(
                                  key: ValueKey('title-${app.pageId}'),
                                  app: app,
                                  width: pageSize.width -
                                      AppState.pageLeftMargin * 2,
                                ),
                              ),
                            ),
                            // Painted in z order (review fix: z was stored but
                            // insertion order used to win) — except that the
                            // SELECTION outranks z. Hit-testing follows paint
                            // order, so a selected box whose end runs under a
                            // neighbour could not be resized or have its text
                            // reached where they overlap: the neighbour's opaque
                            // body swallowed the click. The box the user chose is
                            // the box the mouse should mean, so it paints (and
                            // therefore hit-tests) above everything while
                            // selected, and drops back into place on deselect.
                            for (final b in ([
                              ...app.blocks.where((b) =>
                                  b.type != BlockType.ink &&
                                  (visible.overlaps(_blockRect(b)) ||
                                      app.selectedIds.contains(b.id) ||
                                      app.editingBlockId == b.id))
                            ]..sort((a, b) {
                                int lift(Block x) =>
                                    app.selectedIds.contains(x.id) ||
                                            app.editingBlockId == x.id
                                        ? 1
                                        : 0;
                                final byLift = lift(a) - lift(b);
                                return byLift != 0
                                    ? byLift
                                    : a.z.compareTo(b.z);
                              })))
                              BlockView(
                                key: ValueKey('${b.id}#${app.docRevision}'),
                                block: b,
                                app: app,
                                controller: controller,
                              ),
                            // INK PAINTS OVER THE BLOCKS, and this used to be the
                            // first child of this Stack rather than the last.
                            //
                            // Every stroke was drawn UNDER every block. Blocks are
                            // opaque, so annotating a pasted photograph recorded
                            // the ink perfectly and then hid it behind the
                            // picture: "I can paste and drag images but I cannot
                            // draw on them". The strokes were always there.
                            //
                            // One layer above everything, rather than each ink
                            // block interleaved by z. Interleaving is the more
                            // faithful model and it costs a separate paint layer
                            // per ink block — this canvas opens a new one every
                            // couple of seconds of drawing, so a lesson's worth of
                            // annotation would be hundreds of layers. Ink on top
                            // is also what the tools this is used beside do:
                            // annotation is a sheet laid over the page, not
                            // another object competing for depth with it.
                            Positioned(
                              left: 0,
                              top: 0,
                              child: IgnorePointer(
                                child: RepaintBoundary(
                                  child: CustomPaint(
                                    size: Size.zero,
                                    painter: InkPainter(visibleStrokes,
                                        wet: _wetForPaint,
                                        // Black shown white on a dark page,
                                        // white shown black on a light one.
                                        themeDark: dark,
                                        // Per-point repaint without widget rebuild.
                                        repaint: _wetTick,
                                        // Theme default for "auto" strokes: dark
                                        // ink on light pages, light ink on dark.
                                        autoColor: dark
                                            ? OnoteColors.moon100
                                            : OnoteColors.graphite900),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  // Alignment grid — only visible while dragging a block
                  // effectiveSnap, not snapToGrid: holding Ctrl mid-drag pulls
                  // the block out of the grid, and the grid must stop being
                  // drawn at the same moment or the overlay is telling the user
                  // something that is no longer true.
                  if (app.draggingBlock && app.effectiveSnap)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: CustomPaint(
                          painter: _DragGridPainter(
                            controller: controller,
                            gridSize: app.gridSize,
                            dark: dark,
                          ),
                        ),
                      ),
                    ),
                  // Alignment guides (CANVAS-7), above the grid so they read as
                  // the stronger signal while dragging.
                  if (app.alignGuides.isNotEmpty)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: CustomPaint(
                          painter: _AlignGuidePainter(
                            controller: controller,
                            guides: app.alignGuides,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      ),
                    ),
                  // Marquee + selected-ink outlines (screen-space overlay)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(
                        painter: _OverlayPainter(
                          controller: controller,
                          marquee: _mode == _DragMode.marquee
                              ? Rect.fromPoints(
                                  _marqueeStartPage, _marqueeEndPage)
                              : null,
                          inkSelections: selectedInkRects,
                          lasso: _lasso,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ),
                  ),
                  // Insert Space, while the drag is happening: the line you
                  // started on, and the band that is about to open under it.
                  if (_spaceAtY != null)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: CustomPaint(
                          painter: _InsertSpacePainter(
                            controller: controller,
                            atY: _spaceAtY!,
                            dy: _spaceDy,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      ),
                    ),
                  // The shape being dragged, so its size and direction are
                  // visible before it is committed.
                  if (_arrowFrom != null && _arrowTo != null)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: CustomPaint(
                          painter: _ShapePreviewPainter(
                            controller: controller,
                            tool: app.tool,
                            from: _arrowFrom!,
                            to: _arrowTo!,
                            color: _penCursorColor(dark),
                            size: app.penSize,
                          ),
                        ),
                      ),
                    ),
                  // A placed auto-shape, waiting to be moved or dropped: a soft
                  // outline round it says it is still live — drag to move, tap
                  // to place.
                  if (_placedShape != null)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: CustomPaint(
                          painter: _PlacedShapePainter(
                            controller: controller,
                            shape: _placedShape!,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      ),
                    ),
                  // The sheet rail: which page of a paged document you are on,
                  // and one click to any other. Only in page mode, because on a
                  // boundless canvas there are no pages to list.
                  if (app.pageProps.isPaged && app.sheetRailOpen)
                    Positioned(
                      top: widget.insets.top,
                      right: 0,
                      bottom: widget.insets.bottom,
                      child: _SheetRail(app: app, dark: dark),
                    ),
                  // The drawn pen/highlighter/eraser cursor, above everything
                  // so it is never buried under a block — a cursor that can go
                  // behind the thing you are pointing at is not a cursor.
                  if (_inkTool && !app.penCursorStyle.isSystem)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: RepaintBoundary(
                          child: CustomPaint(
                            painter: _PenCursorPainter(
                              at: _penCursor,
                              tool: app.tool,
                              style: app.penCursorStyle,
                              color: _penCursorColor(dark),
                              penSize: app.penSize,
                              scale: controller.scale,
                              dark: dark,
                            ),
                          ),
                        ),
                      ),
                    ),
                  // A real scroll bar for the page — "there is also no scroll
                  // bar for the page". Wheel and drag still pan; this is the
                  // instrument for POSITION: see where you are in a long page,
                  // and cover all of it in one drag.
                  ..._scrollBar(context, dark),
                ],
              ),
            ),
          );
        },
      );
    });

    if (_twoCornerTool) {
      // Arrow and rectangle are each a drag with two corners and nothing in
      // between: the shape is decided by where you start and where you stop,
      // so there is no path to record and no reason to route it through the
      // ink handlers.
      canvas = Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (e) {
          if (app.claimedPointers.remove(e.pointer)) return;
          controller.stopGlide();
          final p = _clampToPagePoint(controller.screenToPage(e.localPosition));
          setState(() {
            _arrowFrom = Offset2(p.dx, p.dy);
            _arrowTo = _arrowFrom;
          });
        },
        onPointerMove: (e) {
          if (_arrowFrom == null) return;
          final p = _clampToPagePoint(controller.screenToPage(e.localPosition));
          setState(() => _arrowTo = Offset2(p.dx, p.dy));
        },
        onPointerUp: (e) {
          final from = _arrowFrom, to = _arrowTo;
          setState(() {
            _arrowFrom = null;
            _arrowTo = null;
          });
          if (from == null || to == null) return;
          _commitShape(from, to);
        },
        onPointerCancel: (_) => setState(() {
          _arrowFrom = null;
          _arrowTo = null;
        }),
        child: canvas,
      );
    } else if (_spaceTool) {
      // Insert Space. A drag, not a click: the distance IS the amount of
      // space, so there is nothing to type and nothing to guess. The page is
      // only rewritten on release — dragging re-lays-out the whole document
      // on every pointer move, and undo would then hold one entry per pixel.
      canvas = Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (e) {
          if (app.claimedPointers.remove(e.pointer)) return;
          setState(() {
            _spaceAtY = controller.screenToPage(e.localPosition).dy;
            _spaceDy = 0;
          });
        },
        onPointerMove: (e) {
          if (_spaceAtY == null) return;
          setState(() => _spaceDy =
              controller.screenToPage(e.localPosition).dy - _spaceAtY!);
        },
        onPointerUp: (e) {
          final at = _spaceAtY, dy = _spaceDy;
          setState(() {
            _spaceAtY = null;
            _spaceDy = 0;
          });
          // A tap is not a drag. Below a few page-units it is somebody
          // clicking to see what the tool does, and moving their document by
          // two pixels is a worse answer than doing nothing.
          if (at != null && dy.abs() >= 4) app.insertSpace(at, dy);
        },
        child: canvas,
      );
    } else if (_lassoTool) {
      // Lasso: draw a freeform loop; on release, the enclosed strokes are
      // gathered into one selection.
      canvas = Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (e) {
          // The scroll bar claims its pointers; a lasso must not start
          // under it.
          if (app.claimedPointers.remove(e.pointer)) return;
          _lassoDown(e);
        },
        onPointerMove: _lassoMove,
        onPointerUp: _lassoUp,
        child: canvas,
      );
    } else if (_inkTool) {
      // Palm rejection (INK-4), stylus-CONDITIONAL. Pen and mouse always draw.
      // A finger draws too — unless a stylus is in use, in which case touch
      // reverts to pan/pinch so a resting palm never marks the page (OneNote's
      // "draw with pen, navigate with touch"). A second finger always pans,
      // whatever the setting, so the canvas stays navigable while a drawing
      // tool is selected. See `app.touchDrawing` for the user override.
      canvas = Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (e) {
          // The scroll bar claims its pointers; the pen must not draw a
          // stroke behind it.
          if (app.claimedPointers.remove(e.pointer)) return;
          _noteStylus(e);
          if (e.kind != PointerDeviceKind.touch) {
            _inkDown(e);
            return;
          }
          _touches[e.pointer] = e.localPosition;
          if (_touches.length > 1) {
            // The first finger may already be mid-stroke; a pinch is not a
            // drawing, so drop it rather than leaving a stray mark.
            _cancelWetStroke();
            _touchDown(e);
            return;
          }
          if (_touchDraws()) {
            _touches.remove(e.pointer); // it's a drawing pointer, not a gesture
            _inkDown(e);
          } else {
            _touches.remove(e.pointer); // _touchDown re-adds and sets up pinch
            _touchDown(e);
          }
        },
        onPointerMove: (e) {
          _noteStylus(e);
          if (_touches.containsKey(e.pointer)) {
            _touchMove(e);
          } else {
            _inkMove(e);
          }
        },
        onPointerUp: (e) {
          if (_touches.containsKey(e.pointer)) {
            _touchUp(e);
          } else {
            _inkUp(e);
          }
        },
        onPointerCancel: (e) {
          _touches.remove(e.pointer);
          _gestureErase = false;
          _cancelWetStroke();
        },
        child: canvas,
      );
    } else {
      canvas = Listener(
        onPointerDown: _selectDown,
        onPointerMove: _selectMove,
        onPointerUp: _selectUp,
        behavior: HitTestBehavior.translucent,
        child: canvas,
      );
    }

    // Drag-and-drop (MEDIA-1): files dropped anywhere on the page land where
    // they were dropped. Wraps the whole canvas so the drop target matches
    // what the user sees, and highlights only while a drag is over it.
    canvas = DropTarget(
      onDragEntered: (_) => setState(() => _dragOver = true),
      onDragExited: (_) => setState(() => _dragOver = false),
      onDragDone: (details) async {
        setState(() => _dragOver = false);
        // `details.localPosition` is ALREADY local to this DropTarget —
        // desktop_drop calls globalToLocal itself. Converting a second time
        // subtracted the canvas's global origin (navigator width, command-bar
        // height) again, so every dropped file landed up and to the left of
        // the cursor. That was survivable while a drop made a floating block;
        // it is not, now that the drop point decides which text box you are
        // dropping INTO.
        final at = controller.screenToPage(details.localPosition);
        final n = await dropFilesOntoCanvas(
            app, [for (final f in details.files) f.path], at,
            dark: Theme.of(context).brightness == Brightness.dark);
        if (!context.mounted) return;
        // **A drop that lands nothing says so.** It used to be silent, which
        // is indistinguishable from the app not having noticed the drop at
        // all — and the commonest cause is a FOLDER, which nothing anywhere
        // told the student was not accepted.
        final messenger = ScaffoldMessenger.of(context);
        if (n > 0) {
          messenger.showSnackBar(
              SnackBar(content: Text('Added $n item${n == 1 ? '' : 's'}')));
        } else {
          final droppedFolder =
              details.files.any((f) => Directory(f.path).existsSync());
          messenger.showSnackBar(SnackBar(
            content: Text(droppedFolder
                ? "Folders can't be dropped in yet — only files."
                : "That couldn't be added."),
          ));
        }
      },
      child: Stack(children: [
        canvas,
        if (_dragOver)
          Positioned.fill(
            child: IgnorePointer(
              child: Container(
                color: Theme.of(context)
                    .colorScheme
                    .primary
                    .withValues(alpha: .06),
                child: Center(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: Theme.of(context).colorScheme.primary,
                          width: 1.5),
                    ),
                    child: const Padding(
                      padding:
                          EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      child: Text('Drop to add to this page'),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ]),
    );

    return Listener(
      onPointerSignal: _onScroll,
      // Hover is how a pen announces its approach; see _stylusProximity.
      onPointerHover: _stylusProximity,
      // **Trackpad pan/pinch, claim-checked exactly like a mouse drag.**
      //
      // Reported: scrolling and zooming inside a graph moved the PAGE
      // underneath it too. Wheel notches already went "through the
      // resolver" (see [_onScroll]) and a mouse drag already goes through
      // `claimedPointers` (see `_selectDown`) — but a trackpad's two-finger
      // pan and pinch arrive as a THIRD event family entirely
      // (`PointerPanZoomStartEvent`/`UpdateEvent`), which is dispatched to
      // every `Listener` along the hit-test chain like an ordinary pointer
      // event, not funnelled through a single shared resolver the way a
      // discrete wheel notch is. This handler had never checked
      // `claimedPointers` at all, so a graph could claim the pointer on
      // its OWN `onPointerPanZoomStart` — it does, now — and this would
      // still pan the page underneath it on every update regardless.
      //
      // The claim is latched for the whole gesture, not re-checked per
      // update: `claimedPointers` is emptied by `_selectDown` reacting to
      // the SAME pointer going down elsewhere (a lasso, ink, a block
      // drag), which a trackpad pan never triggers, so checking it fresh
      // on every `onPointerPanZoomUpdate` would silently start panning the
      // page mid-gesture the instant something unrelated cleared the set.
      onPointerPanZoomStart: (e) {
        _pzLastScale = 1.0;
        controller.stopGlide(); // fingers on the glass stop the page dead
        _panZoomClaimedBy =
            app.claimedPointers.contains(e.pointer) ? e.pointer : null;
      },
      onPointerPanZoomUpdate: (e) {
        if (_panZoomClaimedBy == e.pointer) return;
        if (e.scale != 1.0) {
          controller.zoomAt(e.localPosition, e.scale / _pzLastScale);
          _pzLastScale = e.scale;
        }
        if (e.panDelta != Offset.zero) {
          controller.panBy(e.panDelta);
          _lastScrollDelta = e.panDelta;
          _noteScrollActivity();
        }
        setState(() {});
      },
      onPointerPanZoomEnd: (e) {
        if (_panZoomClaimedBy == e.pointer) _panZoomClaimedBy = null;
        // A trackpad DOES tell us when the fingers left, so the flick can be
        // handed over precisely instead of guessed at by a timer.
        controller.fling(_lastScrollDelta, this);
        _lastScrollDelta = Offset.zero;
      },
      child: Listener(
        // THE DRAWN CURSOR HAS TO KEEP UP WITH A BUTTON-DOWN DRAG.
        //
        // `MouseRegion.onHover` fires only while NO button is pressed — that
        // is what "hover" means — so tracking the nib on hover alone froze it
        // at the point the stroke started and left it sitting there until the
        // button came up. You drew a line and the pen stayed behind, which is
        // the one thing a pen cursor must never do.
        //
        // A `Listener` sees the whole gesture: down, every move, and up. It is
        // wrapped OUTSIDE the MouseRegion and only ever writes a notifier, so
        // it consumes nothing and cannot change how any tool behaves.
        onPointerDown: (e) {
          // Nothing may be drawn on, dragged on or clicked on a page that is
          // still gliding: the mark would land somewhere the user was not
          // pointing by the time it committed.
          controller.stopGlide();
          _trackPenCursor(e);
        },
        onPointerMove: _trackPenCursor,
        onPointerHover: _trackPenCursor,
        onPointerUp: _trackPenCursor,
        child: MouseRegion(
          // The drawing tools hide the system cursor and draw their own
          // (see [_PenCursorPainter]). `precise` — the plus/crosshair — is a
          // *targeting* cursor: it says "this point", which is what a picker
          // does, not what a pen does. A pen has a nib, and you hold it at an
          // angle; every app people already know (Zoom's annotator, Notability,
          // OneNote) shows one, and the tip is what tells you where the mark
          // will land. Flutter desktop has no custom-image cursor API, so the
          // glyph is painted on the canvas and the real pointer is switched off
          // underneath it.
          cursor: switch (app.tool) {
            Tool.text => SystemMouseCursors.text,
            // Crosshair and Mouse are the styles we do NOT paint: the system
            // already has them, and the real pointer beats a drawn copy that
            // lags a frame behind it.
            Tool.pen || Tool.highlighter || Tool.eraser => switch (
                  app.penCursorStyle) {
                PenCursorStyle.crosshair => SystemMouseCursors.precise,
                PenCursorStyle.mouse => SystemMouseCursors.basic,
                _ => SystemMouseCursors.none,
              },
            Tool.lasso => SystemMouseCursors.precise,
            Tool.space => SystemMouseCursors.resizeUpDown,
            // Crosshair: an arrow or rectangle is placed by two exact points,
            // so the cursor's job is to say "this exact point", which is what
            // a reticle is for.
            Tool.arrow || Tool.rectangle => SystemMouseCursors.precise,
            _ => MouseCursor.defer,
          },
          // Leaving the canvas is the one thing the Listener above cannot see,
          // because a pointer that has gone gives no more events.
          onExit: (_) => _penCursor.value = null,
          child: canvas,
        ),
      ),
    );
  }
}

/// The page surface. At normal zoom the page fills the whole viewport so it
/// reads as one continuous page (no "page floating on a desk"). Only when
/// zoomed out (<85%) does it draw as a bounded sheet on a backdrop, revealing
/// that it's a page you can treat as a canvas.
class _PagePainter extends CustomPainter {
  _PagePainter({
    required this.controller,
    required this.pageSize,
    required this.background,
    required this.spacing,
    required this.dark,
    this.paper = 'white',
    this.paperImage,
    this.sheet,
    this.sheets = 1,
  });
  final CanvasController controller;
  final Size pageSize;
  final String background;

  /// The sheet — see `paper.dart` — and its picture, when it has one.
  final String paper;
  final ui.Image? paperImage;

  /// Gap between dots / height of a ruled line / side of a grid square.
  final double spacing;
  final bool dark;

  /// The paper, when this page is in paged mode. Null on open canvas.
  final Size? sheet;

  /// How many sheets of it the content occupies.
  final int sheets;

  @override
  void paint(Canvas canvas, Size size) {
    final pageColor = paperColor(paper, dark: dark);
    final paperSheet = sheet;
    if (paperSheet != null) {
      // A SHEET has edges, and edges are the whole point of page mode: the
      // desk around it is darker so the paper reads as an object you could
      // pick up, and where one sheet ends the next begins. Canvas mode paints
      // the viewport all one colour precisely because it has no edges.
      canvas.drawRect(Offset.zero & size,
          Paint()..color = dark ? OnoteColors.night200 : OnoteColors.paper200);
      final topLeft = controller.pageToScreen(Offset.zero);
      final w = paperSheet.width * controller.scale;
      final h = paperSheet.height * controller.scale;
      final shadow = Paint()
        ..color = Colors.black.withValues(alpha: dark ? .35 : .12)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
      for (var i = 0; i < sheets; i++) {
        final r = Rect.fromLTWH(topLeft.dx, topLeft.dy + h * i, w, h);
        // Skip sheets that are nowhere near the viewport: a fifty-page essay
        // must not cost fifty shadow blurs a frame.
        if (r.bottom < -h || r.top > size.height + h) continue;
        canvas.drawRect(r.deflate(1).shift(const Offset(0, 2)), shadow);
        canvas.drawRect(r, Paint()..color = pageColor);
        paintPaperDetail(canvas, r, paper, dark: dark, image: paperImage);
      }
      _paintPattern(canvas, size);
      // The break between sheets, drawn last so it sits over the pattern.
      final edge = Paint()
        ..color = dark ? OnoteColors.night300 : OnoteColors.paper300
        ..strokeWidth = 1;
      for (var i = 1; i < sheets; i++) {
        final y = topLeft.dy + h * i;
        if (y < 0 || y > size.height) continue;
        canvas.drawLine(Offset(topLeft.dx, y), Offset(topLeft.dx + w, y), edge);
      }
      return;
    }
    // Seamless: the whole viewport is the page colour — one consistent
    // surface at every zoom (the backdrop and page are the same thing).
    canvas.drawRect(Offset.zero & size, Paint()..color = pageColor);
    // Grain covers the whole surface; a picture is fitted to the page's
    // width and repeated down it, since a canvas has no bottom.
    if (paper == 'texture' || paper.startsWith('ambient')) {
      paintPaperDetail(canvas, Offset.zero & size, paper, dark: dark);
    } else if (paper == 'image') {
      final left = controller.pageToScreen(Offset.zero);
      final w = pageSize.width * controller.scale;
      paintPaperDetail(canvas,
          Rect.fromLTWH(left.dx, left.dy, w, size.height - left.dy), paper,
          dark: dark, image: paperImage, cover: false);
    }
    _paintPattern(canvas, size);
  }

  void _paintPattern(Canvas canvas, Size size) {
    // Background pattern (blank = nothing). Drawn across the visible area but
    // starting below the title band and aligned to the content top, so the
    // lines don't run over the title and match the writing spacing.
    if (background == 'blank') return;
    final step = spacing * controller.scale;
    if (step < 6) return;
    final originY =
        controller.pageToScreen(const Offset(0, AppState.contentTop)).dy;
    final right = size.width, bottom = size.height;
    final paint = Paint()
      ..color = paperRuleColor(paper, dark: dark)
      ..strokeWidth = 1;
    switch (background) {
      case 'grid':
        final ox = controller.offset.dx % step;
        for (var x = ox; x <= right; x += step) {
          canvas.drawLine(Offset(x, originY), Offset(x, bottom), paint);
        }
        for (var y = originY; y <= bottom; y += step) {
          canvas.drawLine(Offset(0, y), Offset(right, y), paint);
        }
      case 'ruled':
        for (var y = originY; y <= bottom; y += step) {
          canvas.drawLine(Offset(0, y), Offset(right, y), paint);
        }
      case 'dotted':
        final dot = Paint()..color = paint.color;
        // The dot grows with the gap, gently. Fixed at 1.2 it read as grit on
        // a wide grid and as a solid tone on a tight one — a dot has to stay
        // in proportion to the space around it to keep reading as a dot.
        final r = (step / 20).clamp(1.0, 2.6);
        final ox = controller.offset.dx % step;
        for (var x = ox; x <= right; x += step) {
          for (var y = originY; y <= bottom; y += step) {
            canvas.drawCircle(Offset(x, y), r, dot);
          }
        }
    }
  }

  @override
  bool shouldRepaint(covariant _PagePainter old) =>
      old.background != background ||
      old.paper != paper ||
      old.paperImage != paperImage ||
      // Was missing, and had to be added for the spacing control to do
      // anything at all: with `gridSize` absent from this list, changing it
      // repainted only if some *other* property happened to change too.
      old.spacing != spacing ||
      old.dark != dark ||
      old.sheet != sheet ||
      old.sheets != sheets ||
      old.pageSize != pageSize ||
      old.controller.scale != controller.scale ||
      old.controller.offset != controller.offset;
}

/// Faint alignment grid shown only while a block is being dragged.
class _DragGridPainter extends CustomPainter {
  _DragGridPainter(
      {required this.controller, required this.gridSize, required this.dark});
  final CanvasController controller;
  final double gridSize;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    final step = gridSize * controller.scale;
    if (step < 6) return;
    final paint = Paint()
      ..color = (dark ? OnoteColors.night200 : OnoteColors.paper200)
          .withValues(alpha: .7)
      ..strokeWidth = 1;
    final ox = controller.offset.dx % step;
    final oy = controller.offset.dy % step;
    for (var x = ox; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (var y = oy; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _DragGridPainter old) =>
      old.controller.scale != controller.scale ||
      old.controller.offset != controller.offset ||
      old.dark != dark;
}

/// Marquee rectangle + dashed outlines for selected ink blocks.
class _OverlayPainter extends CustomPainter {
  _OverlayPainter({
    required this.controller,
    required this.marquee,
    required this.inkSelections,
    required this.lasso,
    required this.color,
  });
  final CanvasController controller;
  final Rect? marquee;
  final List<Rect> inkSelections;
  final List<Offset>? lasso;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final lassoPts = lasso;
    if (lassoPts != null && lassoPts.length > 1) {
      final path = Path()
        ..moveTo(controller.pageToScreen(lassoPts.first).dx,
            controller.pageToScreen(lassoPts.first).dy);
      for (final pt in lassoPts.skip(1)) {
        final sp = controller.pageToScreen(pt);
        path.lineTo(sp.dx, sp.dy);
      }
      path.close();
      canvas.drawPath(path, Paint()..color = color.withValues(alpha: .08));
      canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5
            ..color = color.withValues(alpha: .7));
    }
    if (marquee != null) {
      final r = Rect.fromPoints(controller.pageToScreen(marquee!.topLeft),
          controller.pageToScreen(marquee!.bottomRight));
      canvas.drawRect(r, Paint()..color = color.withValues(alpha: .08));
      canvas.drawRect(
          r,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1
            ..color = color.withValues(alpha: .6));
    }
    for (final pr in inkSelections) {
      final r = Rect.fromPoints(controller.pageToScreen(pr.topLeft),
              controller.pageToScreen(pr.bottomRight))
          .inflate(4);
      _dashedRect(
          canvas,
          r,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5
            ..color = color);
    }
  }

  void _dashedRect(Canvas canvas, Rect r, Paint p) {
    const dash = 6.0, gap = 4.0;
    void line(Offset a, Offset b) {
      final total = (b - a).distance;
      final dir = (b - a) / total;
      var d = 0.0;
      while (d < total) {
        final e = math.min(d + dash, total);
        canvas.drawLine(a + dir * d, a + dir * e, p);
        d = e + gap;
      }
    }

    line(r.topLeft, r.topRight);
    line(r.topRight, r.bottomRight);
    line(r.bottomRight, r.bottomLeft);
    line(r.bottomLeft, r.topLeft);
  }

  @override
  bool shouldRepaint(covariant _OverlayPainter old) =>
      old.marquee != marquee ||
      old.inkSelections.length != inkSelections.length ||
      old.lasso != lasso ||
      (lasso?.length ?? 0) != (old.lasso?.length ?? 0) ||
      old.controller.offset != controller.offset ||
      old.controller.scale != controller.scale;
}

/// Draws the alignment guides while a block is being dragged.
///
/// Screen-space, one physical pixel wide at any zoom: a guide scaled with the
/// page becomes a fat bar zoomed in and invisible zoomed out, when what it
/// needs to be is a hairline that says "these edges match".
class _AlignGuidePainter extends CustomPainter {
  _AlignGuidePainter({
    required this.controller,
    required this.guides,
    required this.color,
  }) : super(repaint: controller);

  final CanvasController controller;
  final List<AlignGuide> guides;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withValues(alpha: .85)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    for (final g in guides) {
      final a = controller.pageToScreen(
          g.vertical ? Offset(g.position, g.from) : Offset(g.from, g.position));
      final b = controller.pageToScreen(
          g.vertical ? Offset(g.position, g.to) : Offset(g.to, g.position));
      // Extend a little past both blocks so the line clearly spans them.
      const overhang = 10.0;
      final dir = g.vertical ? const Offset(0, 1) : const Offset(1, 0);
      canvas.drawLine(a - dir * overhang, b + dir * overhang, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _AlignGuidePainter old) =>
      old.guides != guides || old.color != color;
}

/// The drawn pen / highlighter / eraser cursor.
///
/// Flutter desktop has no custom-image cursor API — `SystemMouseCursors` is a
/// closed set, and the nearest thing in it to a pen is `precise`, the plus.
/// A plus is a *targeting* reticle: it means "this exact point", which is what
/// an eyedropper does. A pen is held at an angle and marks from a nib, and
/// every annotator people arrive here already knowing (Zoom, Notability,
/// OneNote) draws one. So the real pointer is switched off in [MouseRegion]
/// and the glyph is painted here instead.
///
/// Two parts, and both earn their place:
///  * the **tip** sits exactly on the pointer, so the hot spot is honest —
///    a cursor that marks somewhere other than where it points is worse than
///    the plus it replaced;
///  * the **nib ring** is drawn at the true stroke width, so the pen shows
///    how fat the line will be *before* you commit to it. That is why it
///    scales with zoom: at 300% a 2pt pen really does lay down a wide mark.
class _PenCursorPainter extends CustomPainter {
  _PenCursorPainter({
    required this.at,
    required this.tool,
    required this.style,
    required this.color,
    required this.penSize,
    required this.scale,
    required this.dark,
  }) : super(repaint: at);

  /// Listened to, not read as a field — this is what keeps a mouse move from
  /// rebuilding the widget tree (see [_PageCanvasState._penCursor]).
  final ValueNotifier<Offset?> at;
  final Tool tool;
  final PenCursorStyle style;
  final Color color;
  final double penSize;
  final double scale;
  final bool dark;

  /// The stroke width the pen will actually lay down, on screen, clamped so
  /// the ring stays a readable cursor at both zoom extremes.
  double get _nib => (penSize * scale).clamp(3.0, 44.0);

  @override
  void paint(Canvas canvas, Size size) {
    final p = at.value;
    if (p == null) return;

    if (tool == Tool.eraser) {
      _paintEraser(canvas, p);
      return;
    }

    // The dot: the tip, and nothing else. Two rings so it stays visible over
    // ink of its own colour without needing a glyph to carry a halo.
    if (style == PenCursorStyle.dot) {
      canvas.drawCircle(
          p,
          4.5,
          Paint()
            ..color =
                (dark ? Colors.black : Colors.white).withValues(alpha: .75));
      canvas.drawCircle(p, 3, Paint()..color = color);
      return;
    }

    // NO RING AT THE NIB. It showed the stroke width before you committed to
    // it, which sounded useful and in practice put a circle around the exact
    // point you were trying to aim at — the one part of the glyph that has to
    // stay legible. The nib alone is the cursor.

    // The body hangs DOWN and to the right of the tip.
    //
    // It used to go UP-right, which is how a hand really holds a pen — and it
    // was wrong for a cursor. Writing runs left to right, so a barrel above
    // the nib sits squarely on the words you have just written and you cannot
    // read back the line you are on. Below the nib it covers blank paper you
    // have not reached yet. The tip stays exactly on the hot spot either way;
    // only the body moved.
    //
    // Offsets are in logical pixels and deliberately NOT scaled by zoom: the
    // pen is a cursor, and a cursor that grows when you zoom in is a bug in
    // every app that has ever shipped one.
    final body = Path();
    const double a = 0.87; // ≈50° from horizontal
    final dx = math.cos(a), dy = math.sin(a);
    // u = (dx, dy) runs down-right from the tip; v = (dy, -dx) is its
    // perpendicular, so `side` fattens the barrel symmetrically.
    Offset along(double d, double side) =>
        Offset(p.dx + dx * d + dy * side, p.dy + dy * d - dx * side);

    // Longer than it was (28px against 19): a stubby pen reads as a smudge at
    // a glance, and the length is what makes the direction legible.
    const double nibEnd = 8, tail = 28, halfWidth = 3;

    // Nib triangle: a point at the pointer opening into the barrel.
    body.moveTo(p.dx, p.dy);
    body.lineTo(along(nibEnd, halfWidth).dx, along(nibEnd, halfWidth).dy);
    body.lineTo(along(nibEnd, -halfWidth).dx, along(nibEnd, -halfWidth).dy);
    body.close();

    final barrel = Path()
      ..moveTo(along(nibEnd, halfWidth).dx, along(nibEnd, halfWidth).dy)
      ..lineTo(along(tail, halfWidth).dx, along(tail, halfWidth).dy)
      ..lineTo(along(tail, -halfWidth).dx, along(tail, -halfWidth).dy)
      ..lineTo(along(nibEnd, -halfWidth).dx, along(nibEnd, -halfWidth).dy)
      ..close();

    // A halo under the whole glyph, so the pen stays visible over ink of its
    // own colour and over a photo — the reason a plain black outline is not
    // enough on a canvas that can contain anything.
    final halo = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeJoin = StrokeJoin.round
      ..color = (dark ? Colors.black : Colors.white).withValues(alpha: .75);
    canvas.drawPath(body, halo);
    canvas.drawPath(barrel, halo);

    // The highlighter is a chisel, not a point: same body, blunt end, and
    // translucent like the ink it lays down.
    final isHi = tool == Tool.highlighter;
    canvas.drawPath(
        body, Paint()..color = color.withValues(alpha: isHi ? .55 : 1));
    canvas.drawPath(
        barrel,
        Paint()
          ..color = (dark ? OnoteColors.moon100 : OnoteColors.graphite900)
              .withValues(alpha: isHi ? .55 : .82));
    canvas.drawPath(
        barrel,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = (dark ? Colors.black : Colors.white).withValues(alpha: .6));
  }

  /// The eraser shows its own size and nothing else. It is a *region* tool —
  /// what matters is how much of the page it will take, so the cursor is that
  /// region, and no glyph competes with it for attention.
  void _paintEraser(Canvas canvas, Offset p) {
    final r = (14.0 * scale).clamp(6.0, 60.0);
    canvas.drawCircle(
        p,
        r,
        Paint()
          ..color =
              (dark ? Colors.white : Colors.black).withValues(alpha: .06));
    canvas.drawCircle(
        p,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = color.withValues(alpha: .8));
  }

  @override
  bool shouldRepaint(covariant _PenCursorPainter old) =>
      old.tool != tool ||
      old.style != style ||
      old.color != color ||
      old.penSize != penSize ||
      old.scale != scale ||
      old.dark != dark;
}

/// The sheet rail down the right-hand edge of a paged page.
///
/// A paged document can run to many sheets. This shows each as a small LIVE
/// preview — the real paper, ink and text at a readable size, drawn straight
/// from the page's data so it stays current without a costly snapshot — marks
/// the one you are looking at, jumps on a click, reorders on a drag, and
/// deletes a page from the control on it.
class _SheetRail extends StatelessWidget {
  const _SheetRail({required this.app, required this.dark});

  final AppState app;
  final bool dark;

  Future<void> _sheetMenu(BuildContext context, int i, Offset at) async {
    final canDelete = i < app.sheetCount + app.pageProps.addedSheets;
    final choice = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(at.dx, at.dy, at.dx, at.dy),
      items: [
        PopupMenuItem(
            value: 'before',
            height: 36,
            child: Text('Insert a page before ${i + 1}')),
        PopupMenuItem(
            value: 'after',
            height: 36,
            child: Text('Insert a page after ${i + 1}')),
        const PopupMenuItem(
            value: 'end', height: 36, child: Text('Add a page at the end')),
        if (canDelete) ...[
          const PopupMenuDivider(),
          const PopupMenuItem(
            value: 'delete',
            height: 36,
            child: Row(children: [
              Icon(Icons.delete_outline, size: 16),
              SizedBox(width: 8),
              Text('Delete this page'),
            ]),
          ),
        ],
      ],
    );
    switch (choice) {
      case 'before':
        app.insertSheet(i);
      case 'after':
        app.insertSheet(i + 1);
      case 'end':
        app.addSheet();
      case 'delete':
        if (context.mounted) await _confirmDelete(context, i);
    }
  }

  Future<void> _confirmDelete(BuildContext context, int i) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete page ${i + 1}?'),
        content: const Text('What is on this page is removed and the pages '
            'below it move up. This can be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (ok == true) app.deleteSheet(i);
  }

  @override
  Widget build(BuildContext context) {
    final n = app.scrollableSheetCount;
    final paper = app.pageProps.paper;
    final h = paper.height;
    final aspect = paper.width / paper.height;
    final current = ((-app.canvas.offset.dy / app.canvas.scale) / h)
        .floor()
        .clamp(0, n - 1);
    // Content pages and any added blanks can be deleted; the trailing spares
    // are scroll room, not pages.
    final deletableUpTo = app.sheetCount + app.pageProps.addedSheets;
    return Container(
      width: 132,
      decoration: BoxDecoration(
        color: (dark ? OnoteColors.night0 : OnoteColors.paper0)
            .withValues(alpha: .92),
        border: Border(
            left: BorderSide(
                color: dark ? OnoteColors.night300 : OnoteColors.paper300)),
      ),
      child: Column(children: [
        Expanded(
          child: ReorderableListView.builder(
            // Top inset clears the canvas controls that float over this corner.
            padding: const EdgeInsets.fromLTRB(10, 52, 10, 8),
            buildDefaultDragHandles: false,
            itemCount: n,
            onReorder: (from, to) {
              app.moveSheet(from, to > from ? to - 1 : to);
            },
            itemBuilder: (context, i) {
              return Padding(
                key: ValueKey('sheet-$i'),
                padding: const EdgeInsets.only(bottom: 10),
                child: ReorderableDragStartListener(
                  index: i,
                  child: Tooltip(
                    message: 'Page ${i + 1} — click to go there, drag to '
                        'reorder, right-click for more',
                    child: GestureDetector(
                      onSecondaryTapDown: (d) =>
                          _sheetMenu(context, i, d.globalPosition),
                      child: _SheetCard(
                        app: app,
                        index: i,
                        dark: dark,
                        aspect: aspect,
                        selected: i == current,
                        canDelete: i < deletableUpTo,
                        onTap: () => app.goToSheet(i),
                        onDelete: () => _confirmDelete(context, i),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const Divider(height: 1),
        IconButton(
          icon: const Icon(Icons.add, size: 18),
          tooltip: 'Add a page at the end',
          visualDensity: VisualDensity.compact,
          onPressed: app.addSheet,
        ),
      ]),
    );
  }
}

/// One page in the rail: a live thumbnail with a number, selectable, and a
/// delete control on hover.
class _SheetCard extends StatefulWidget {
  const _SheetCard({
    required this.app,
    required this.index,
    required this.dark,
    required this.aspect,
    required this.selected,
    required this.canDelete,
    required this.onTap,
    required this.onDelete,
  });

  final AppState app;
  final int index;
  final bool dark;
  final double aspect;
  final bool selected;
  final bool canDelete;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  State<_SheetCard> createState() => _SheetCardState();
}

class _SheetCardState extends State<_SheetCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Stack(children: [
          InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: widget.onTap,
            child: AspectRatio(
              aspectRatio: widget.aspect,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: widget.selected
                        ? scheme.primary
                        : (widget.dark
                            ? OnoteColors.night300
                            : OnoteColors.paper300),
                    width: widget.selected ? 2 : 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black
                          .withValues(alpha: widget.dark ? .3 : .08),
                      blurRadius: 3,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: CustomPaint(
                    painter: _SheetThumbPainter(
                      app: widget.app,
                      sheetIndex: widget.index,
                      dark: widget.dark,
                      rev: widget.app.docRevision,
                    ),
                    size: Size.infinite,
                  ),
                ),
              ),
            ),
          ),
          if (widget.canDelete && _hover)
            Positioned(
              top: 2,
              right: 2,
              child: Material(
                color: (widget.dark ? Colors.black : Colors.white)
                    .withValues(alpha: .82),
                shape: const CircleBorder(),
                child: IconButton(
                  icon: const Icon(Icons.delete_outline, size: 15),
                  tooltip: 'Delete this page',
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 24, minHeight: 24),
                  onPressed: widget.onDelete,
                ),
              ),
            ),
        ]),
        const SizedBox(height: 3),
        Text('${widget.index + 1}',
            style: TextStyle(
              fontSize: 11,
              fontWeight: widget.selected ? FontWeight.w700 : FontWeight.w400,
              color: widget.selected ? scheme.primary : null,
            )),
      ]),
    );
  }
}

/// Draws one sheet's real content, scaled down: the paper, its ink, the text,
/// and a light footprint for every other block. Straight from the live page
/// data, so it never goes stale; cheap enough to redraw on an edit because it
/// paints the data, not a captured bitmap.
class _SheetThumbPainter extends CustomPainter {
  _SheetThumbPainter({
    required this.app,
    required this.sheetIndex,
    required this.dark,
    required this.rev,
  });

  final AppState app;
  final int sheetIndex;
  final bool dark;
  final int rev;

  @override
  void paint(Canvas canvas, Size size) {
    final props = app.pageProps;
    final paper = props.paper;
    final w = paper.width, h = paper.height;
    if (w <= 0 || h <= 0) return;
    final top = sheetIndex * h, bot = top + h;
    final scale = size.width / w;

    canvas.drawRect(Offset.zero & size,
        Paint()..color = paperColor(props.paperKind, dark: dark));

    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.scale(scale);
    canvas.translate(0, -top);

    final ink = dark ? Colors.white : Colors.black;
    // Non-ink blocks: real text, a light footprint for the rest.
    for (final b in app.blocks) {
      if (b.type == BlockType.ink) continue;
      final bh = b.h ?? 120;
      if (b.y + bh < top || b.y > bot) continue;
      if (b.type == BlockType.text) {
        final txt = _plain((b.content['text'] as String?) ?? '');
        if (txt.isEmpty) continue;
        final tp = TextPainter(
          text: TextSpan(
              text: txt,
              style: TextStyle(
                  fontSize: 15,
                  height: 1.3,
                  color: ink.withValues(alpha: .82))),
          textDirection: TextDirection.ltr,
          maxLines: (bh / 20).clamp(1, 60).floor(),
          ellipsis: '…',
        )..layout(maxWidth: b.w);
        tp.paint(canvas, Offset(b.x, b.y));
      } else {
        final rect = Rect.fromLTWH(b.x, b.y, b.w, bh);
        final rr = RRect.fromRectAndRadius(rect, const Radius.circular(4));
        canvas.drawRRect(rr, Paint()..color = ink.withValues(alpha: .05));
        canvas.drawRRect(
            rr,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1
              ..color = ink.withValues(alpha: .14));
      }
    }

    // Ink: the real strokes on this sheet, drawn by the canvas's own painter.
    final strokes = <Stroke>[];
    for (final b in app.blocks) {
      if (b.type != BlockType.ink) continue;
      final bh = b.h ?? 0;
      if (b.y + bh < top || b.y > bot) continue;
      strokes.addAll(_decode(b));
    }
    if (strokes.isNotEmpty) {
      InkPainter(strokes, themeDark: dark).paint(canvas, Size(w, bot));
    }
    canvas.restore();
  }

  /// Decoded strokes per ink block, cached by the block's `updatedAt` so a
  /// repaint (on an edit elsewhere on the page) does not re-parse every stroke
  /// — and so the decoded objects keep their identity, which lets
  /// [InkPainter]'s own outline cache hit. The same reasoning as `_strokesOf`.
  static final Map<String, ({int rev, List<Stroke> strokes})> _decodeCache = {};

  static List<Stroke> _decode(Block b) {
    final hit = _decodeCache[b.id];
    if (hit != null && hit.rev == b.updatedAt) return hit.strokes;
    final raw = b.content['strokes'];
    final decoded = <Stroke>[
      if (raw is List)
        for (final sj in raw)
          if (sj is Map) Stroke.fromJson(sj.cast<String, dynamic>()),
    ];
    _decodeCache[b.id] = (rev: b.updatedAt, strokes: decoded);
    return decoded;
  }

  /// A light strip so headings and bullets read as text, not as markup.
  static String _plain(String md) => md
      .replaceAll(RegExp(r'[*_`>#~]'), '')
      .replaceAll(RegExp(r'^\s*[-+]\s', multiLine: true), '• ')
      .trim();

  @override
  bool shouldRepaint(_SheetThumbPainter old) =>
      old.rev != rev || old.sheetIndex != sheetIndex || old.dark != dark;
}

/// The Insert Space preview: where the cut is, and how much is opening.
///
/// Shown only while the drag is live. It has to answer two questions at a
/// glance — *what moves* (everything below the line) and *by how much* — so
/// it draws the line solid and fills the band being created, rather than
/// showing a number nobody can convert into page distance.
class _InsertSpacePainter extends CustomPainter {
  _InsertSpacePainter({
    required this.controller,
    required this.atY,
    required this.dy,
    required this.color,
  });

  final CanvasController controller;
  final double atY;
  final double dy;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final y0 = controller.pageToScreen(Offset(0, atY)).dy;
    final y1 = controller.pageToScreen(Offset(0, atY + dy)).dy;
    final band =
        Rect.fromLTRB(0, math.min(y0, y1), size.width, math.max(y0, y1));
    canvas.drawRect(band, Paint()..color = color.withValues(alpha: .12));
    final line = Paint()
      ..color = color
      ..strokeWidth = 2;
    canvas.drawLine(Offset(0, y0), Offset(size.width, y0), line);
    // The leading edge dashed, so which line is the anchor and which is the
    // one following the hand is never in doubt.
    if ((y1 - y0).abs() > 1) {
      const dash = 8.0;
      for (var x = 0.0; x < size.width; x += dash * 2) {
        canvas.drawLine(
            Offset(x, y1),
            Offset(x + dash, y1),
            Paint()
              ..color = color.withValues(alpha: .7)
              ..strokeWidth = 1.5);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _InsertSpacePainter old) =>
      old.atY != atY ||
      old.dy != dy ||
      old.color != color ||
      old.controller.scale != controller.scale ||
      old.controller.offset != controller.offset;
}

/// The two-corner shape (arrow or rectangle) being dragged, drawn in screen
/// space.
///
/// A preview rather than a live ink stroke: the shape has no path to record,
/// so there is nothing to accumulate — only two corners, redrawn as the far
/// one moves. Built from the same geometry the commit uses, so what you drag
/// is what you get rather than an approximation of it.
class _ShapePreviewPainter extends CustomPainter {
  _ShapePreviewPainter({
    required this.controller,
    required this.tool,
    required this.from,
    required this.to,
    required this.color,
    required this.size,
  });

  final CanvasController controller;
  final Tool tool;
  final Offset2 from;
  final Offset2 to;
  final Color color;
  final double size;

  @override
  void paint(Canvas canvas, Size _) {
    final strokes = tool == Tool.rectangle
        ? rectangleStrokes(from: from, to: to, colorHex: '#000000', size: size)
        : arrowStrokes(from: from, to: to, colorHex: '#000000', size: size);
    if (strokes.isEmpty) return;
    // A rectangle previews with square corners (miter, closed loop) so it
    // matches the sharp stroke it commits to; the arrow keeps round joins.
    final rect = tool == Tool.rectangle;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = (size * controller.scale).clamp(1.0, 40.0)
      ..strokeCap = rect ? StrokeCap.square : StrokeCap.round
      ..strokeJoin = rect ? StrokeJoin.miter : StrokeJoin.round;
    for (final st in strokes) {
      final path = Path();
      for (var i = 0; i < st.x.length; i++) {
        final p = controller.pageToScreen(Offset(st.x[i], st.y[i]));
        if (i == 0) {
          path.moveTo(p.dx, p.dy);
        } else {
          path.lineTo(p.dx, p.dy);
        }
      }
      if (rect) path.close();
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _ShapePreviewPainter old) =>
      old.tool != tool ||
      old.from.x != from.x ||
      old.from.y != from.y ||
      old.to.x != to.x ||
      old.to.y != to.y ||
      old.color != color ||
      old.size != size ||
      old.controller.scale != controller.scale ||
      old.controller.offset != controller.offset;
}

/// A soft rounded outline around a placed auto-shape, so it reads as still
/// live — drag to move it, tap to drop it. Just the frame; the shape itself is
/// drawn by the ink painter as the wet stroke.
class _PlacedShapePainter extends CustomPainter {
  _PlacedShapePainter({
    required this.controller,
    required this.shape,
    required this.color,
  });

  final CanvasController controller;
  final Stroke shape;
  final Color color;

  @override
  void paint(Canvas canvas, Size _) {
    if (shape.x.isEmpty) return;
    var minX = double.infinity, minY = double.infinity;
    var maxX = -double.infinity, maxY = -double.infinity;
    for (var i = 0; i < shape.x.length; i++) {
      minX = math.min(minX, shape.x[i]);
      maxX = math.max(maxX, shape.x[i]);
      minY = math.min(minY, shape.y[i]);
      maxY = math.max(maxY, shape.y[i]);
    }
    final tl = controller.pageToScreen(Offset(minX, minY));
    final br = controller.pageToScreen(Offset(maxX, maxY));
    final rect = Rect.fromPoints(tl, br).inflate(10);
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(10));
    canvas.drawRRect(rrect, Paint()..color = color.withValues(alpha: .06));
    canvas.drawRRect(
        rrect,
        Paint()
          ..color = color.withValues(alpha: .55)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5);
  }

  @override
  bool shouldRepaint(covariant _PlacedShapePainter old) =>
      old.shape != shape ||
      old.color != color ||
      old.controller.scale != controller.scale ||
      old.controller.offset != controller.offset;
}
