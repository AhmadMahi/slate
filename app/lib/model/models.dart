/// Data model per docs/specs/11-data-model-spec.md. Field names match the
/// Page JSON schema exactly, so `toJson` output IS the mirror format.
library;

import 'package:path/path.dart' as p;

import '../core/ids.dart';

int nowMs() => DateTime.now().millisecondsSinceEpoch;

// ── Hierarchy ────────────────────────────────────────────────────────────

enum NodeKind { sectionGroup, section, page }

/// The name the **published file format** gives [kind].
///
/// `kind.name` was used for this, and Dart spells the enumerator
/// `sectionGroup` — a word that appears nowhere in the CC0 spec (§3 documents
/// only the snake_case set) and nowhere in the container's own
/// `CHECK (kind IN ('section_group','section','page'))`. Measured on all four
/// of the owner's real notebooks: **6 nodes each** written with a spelling the
/// log reader then failed to recognise, so every section group came back as a
/// **page** (v0.17 plan, Step 3).
String nodeKindWire(NodeKind kind) => switch (kind) {
      NodeKind.sectionGroup => 'section_group',
      NodeKind.section => 'section',
      NodeKind.page => 'page',
    };

/// [nodeKindWire]'s inverse, or **null** for a spelling this build does not
/// know.
///
/// **Both spellings are accepted, for ever.** Every log written before the fix
/// contains `sectionGroup`, and §4.1 of the v0.17 plan is absolute that nothing
/// rewrites a log line — so dropping the old word would silently re-break the
/// exact six nodes per notebook this fix exists to repair.
///
/// **Null rather than a `page` fallback.** The old
/// `orElse: () => NodeKind.page` turned anything it did not recognise into a
/// page, and a page is not a neutral default: it has a `page_mirror` foreign
/// key, a `level`, and completely different semantics from a section group. A
/// future kind would have been flattened into a page on every older device
/// that read the log, permanently.
NodeKind? nodeKindFromWire(String wire) => switch (wire) {
      'section_group' || 'sectionGroup' => NodeKind.sectionGroup,
      'section' => NodeKind.section,
      'page' => NodeKind.page,
      _ => null,
    };

class TreeNode {
  TreeNode({
    String? id,
    required this.kind,
    this.parentId,
    this.title = '',
    this.position = 'a0',
    this.color,
    this.level = 0,
    int? createdAt,
  })  : id = id ?? newId(),
        createdAt = createdAt ?? nowMs(),
        updatedAt = createdAt ?? nowMs();

  final String id;
  final NodeKind kind;
  String? parentId;
  String title;
  String position; // fractional index, sorts lexicographically
  String? color;
  int level; // subpage indent for pages (0..2)
  final int createdAt;
  int updatedAt;
}

class NotebookRef {
  NotebookRef(
      {required this.id,
      required this.file,
      required this.title,
      this.logDir,
      this.deletedAt});
  final String id;

  /// Absolute path to the `.onote`. Mutable because a notebook can be moved
  /// into a synced folder (`Repository.moveNotebookTo`) without becoming a
  /// different notebook — the id is the identity, the path is just where it
  /// happens to live.
  String file;

  /// Where this notebook's `.onotebook` op logs live, when that is NOT the
  /// sibling of [file].
  ///
  /// **This is what keeps two devices off one SQLite file.** The container is
  /// a WAL database rewritten on every save; two machines writing one copy of
  /// it through a cloud client is the corruption case ADR-0006 §3 designs
  /// against ("cache.onote ← local-only SQLite; never synced"). The op logs
  /// are the opposite — append-only, one file per device — so they are safe to
  /// share by construction.
  ///
  /// So a device that joins an existing notebook keeps its OWN container in
  /// the workspace and points this at the shared folder. Null means the
  /// default: `<file without extension>.onotebook`.
  ///
  /// **After v0.17 Step 8's migration this is not optional.** A demoted
  /// notebook's container is `<workspace>/.cache/<id>/cache.onote`, and the
  /// default below would derive `<workspace>/.cache/<id>/cache.onotebook` from
  /// it — a log directory inside the very folder that exists to be disposable,
  /// which is the notes themselves written somewhere a rebuild deletes. So
  /// `Repository.demoteContainerToCache` records the notes folder explicitly
  /// before it moves anything, and refuses outright if it cannot find one.
  String? logDir;

  /// Where the op logs actually are — [logDir] when set, otherwise the
  /// sibling of [file].
  ///
  /// One accessor rather than the default spelled out at each call site: the
  /// sites that missed it went subtly wrong rather than failing (the sync chip
  /// read "not synced" for a device that had just joined, and moving a joined
  /// notebook looked for a log directory that was never there).
  ///
  /// The sibling default is for a notebook in the classic layout — a
  /// `Physics.onote` with a `Physics.onotebook` beside it — and stays for as
  /// long as un-migrated notebooks exist, which is for ever, because the
  /// migration is opt-in.
  String get logDirPath {
    final o = logDir;
    return (o != null && o.isNotEmpty)
        ? o
        : '${p.withoutExtension(file)}.onotebook';
  }

  String title;
  int? deletedAt; // set while the notebook sits in the recycle bin (ORG-7)
}

// ── Page properties (Data Model Spec §3 page-level; CANVAS-11) ───────────

/// A named sheet size, in the canvas's own logical pixels.
///
/// Stored as a NAME rather than a pair of numbers, so a page laid out on A4
/// stays A4 when someone opens it on a machine that thinks in inches — and so
/// these figures could be corrected without every existing page disagreeing
/// with the build that opens it. Which is exactly what happened: they were
/// first written at 96 px per inch, and the app does not work in that space.
///
/// **120 px per inch.** That is the canvas's unit — the OneNote importer's,
/// inherited by everything since — and `pdf_vector_export.dart` converts out
/// of it at `120/72` to reach PDF points. At 96 an "A4" sheet was 794 px, and
/// the exporter turned that into 476 pt: a page claiming to be A4 and printing
/// at 80% of it. The screen was wrong the same way, just less visibly, because
/// nothing on a boundless canvas tells you how big an inch is.
class PaperSize {
  const PaperSize(this.name, this.width, this.height);
  final String name;
  final double width;
  final double height;

  // inches x 120, rounded.
  static const a4 = PaperSize('A4', 992, 1403);
  static const a5 = PaperSize('A5', 699, 992);
  static const a3 = PaperSize('A3', 1403, 1984);
  static const letter = PaperSize('Letter', 1020, 1320);
  static const legal = PaperSize('Legal', 1020, 1680);
  static const tabloid = PaperSize('Tabloid', 1320, 2040);

  /// Offered in the picker, metric first — the default is A4 and most of the
  /// world's students are on it.
  static const all = [a4, a5, a3, letter, legal, tabloid];

  static PaperSize byName(String? n) =>
      all.firstWhere((p) => p.name == n, orElse: () => a4);
}

class PageProps {
  /// The default spacing of the page's background pattern, in page units.
  /// Also the value [bgSpacing] falls back to, which is what keeps a page
  /// written by any earlier build rendering byte-identically.
  static const double defaultBgSpacing = 24;

  /// The usable range. The floor is where a pattern stops being a pattern and
  /// becomes a grey wash (and where the painter's own `step < 6` cull would
  /// hide it anyway at 100%); the ceiling is roughly a third of a page.
  static const double minBgSpacing = 8;
  static const double maxBgSpacing = 120;

  PageProps({
    this.background = 'blank',
    this.gridSize = 24,
    this.bgSpacing = defaultBgSpacing,
    this.addedSheets = 0,
    this.pageWidth = 1100,
    this.layout = 'canvas',
    this.paperSize = 'A4',
    this.landscape = false,
    this.paperKind = 'ambient',
    this.paperImage,
    Map<String, dynamic>? unknownFields,
  }) : unknownFields = unknownFields ?? {};
  String background; // blank | grid | dotted | ruled
  double gridSize;

  /// The sheet: `ambient` (the default — near-white with the room's glow),
  /// `white`, `grey`, `cream`, `texture` (paper grain) or `image`. Per page, like the
  /// pattern drawn on it — see `lib/canvas/paper.dart`. Named `paperKind`
  /// because [paper] is already the sheet SIZE; the JSON key is `paper`.
  String paperKind;

  /// The blob hash of the picture, when [paperKind] is `image`. Content-addressed
  /// like every other blob, so a picture used on ten pages is stored once.
  String? paperImage;

  /// How far apart the background pattern is drawn: the gap between dots, the
  /// height of a ruled line, the side of a grid square.
  ///
  /// **Deliberately not [gridSize].** One value used to do both jobs, which
  /// meant the only way to widen the ruling was to widen the SNAP grid too —
  /// so changing how the paper looked silently moved every box on it the next
  /// time it was dragged. They are different questions: [gridSize] is where
  /// things land, this is what the paper looks like. Per page, like every
  /// other page property, because the lecture you scribble on and the essay
  /// you hand in do not want the same paper.
  double bgSpacing;

  /// Blank sheets the user asked for beyond what the content needs.
  ///
  /// Scrolling already offers a couple of spare pages
  /// (`AppState.spareSheets`); this is for saying "this document is five
  /// pages" before writing them, which is a different act from scrolling into
  /// space. Per page, and written only when it is not zero.
  int addedSheets;
  double pageWidth; // presented page-surface width (CANVAS-1 v0.3)

  /// `canvas` (the default, and what Openote has always been) or `paged`.
  ///
  /// Canvas is boundless and free: boxes go where you put them. Paged is a
  /// sheet of a fixed size that you write down, like a word processor — "in
  /// page mode i think text boxes shouldnt be the default, it should be like a
  /// regular text/md editor. Basically ends up being just one really big box."
  ///
  /// Deliberately per PAGE, not per notebook: a notebook holds lecture notes
  /// you scribble on and an essay you have to hand in, and forcing one shape on
  /// both is the reason people keep two apps.
  String layout;

  /// The name of a [PaperSize]. Only meaningful when [layout] is `paged`.
  String paperSize;
  bool landscape;

  bool get isPaged => layout == 'paged';

  /// The sheet, honouring orientation.
  PaperSize get paper {
    final p = PaperSize.byName(paperSize);
    return landscape ? PaperSize(p.name, p.height, p.width) : p;
  }

  /// Page-level properties written by a newer Openote (or another tool) that
  /// this build doesn't understand. Preserved verbatim so a round-trip through
  /// an older version never silently drops them (Data Model Spec §8 invariant 6
  /// — the same contract [Block.unknownFields] honours).
  final Map<String, dynamic> unknownFields;

  static const _known = {
    'background',
    'gridSize',
    'bgSpacing',
    'addedSheets',
    'pageWidth',
    'layout',
    'paperSize',
    'landscape',
    'paper',
    'paperImage',
  };

  Map<String, dynamic> toJson() => {
        'background': background,
        'gridSize': gridSize,
        'pageWidth': pageWidth,
        // Written only when it says something, for the same reason the paged
        // keys are: emitting a new key unconditionally would rewrite every
        // page in every notebook on the next save, and hand the sync log a
        // diff for all of them.
        if (bgSpacing != defaultBgSpacing) 'bgSpacing': bgSpacing,
        if (addedSheets > 0) 'addedSheets': addedSheets,
        // Written only when they say something. A canvas page is the
        // overwhelming majority and its JSON is byte-identical to what every
        // previous build wrote — which matters beyond tidiness: emitting three
        // new keys unconditionally would rewrite every page in every notebook
        // on the next save, and hand the sync log a diff for all of them.
        if (isPaged) 'layout': layout,
        if (isPaged) 'paperSize': paperSize,
        if (isPaged && landscape) 'landscape': landscape,
        // The default paper says nothing, so an unchanged page serialises
        // exactly as every earlier build wrote it.
        if (paperKind != 'ambient') 'paper': paperKind,
        if (paperImage != null) 'paperImage': paperImage,
        ...unknownFields,
      };
  factory PageProps.fromJson(Map<String, dynamic>? j) => PageProps(
        background: j?['background'] as String? ?? 'blank',
        gridSize: (j?['gridSize'] as num?)?.toDouble() ?? 24,
        // Clamped on the way IN as well as in the UI: a hand-edited or
        // newer-build value of 0 would be an infinite paint loop below.
        bgSpacing: ((j?['bgSpacing'] as num?)?.toDouble() ?? defaultBgSpacing)
            .clamp(minBgSpacing, maxBgSpacing),
        addedSheets: ((j?['addedSheets'] as num?)?.toInt() ?? 0).clamp(0, 200),
        pageWidth: (j?['pageWidth'] as num?)?.toDouble() ?? 1100,
        // Additive, and defaulted: a page written by any earlier build has no
        // `layout` key and must open exactly as it always did.
        layout: j?['layout'] as String? ?? 'canvas',
        paperSize: j?['paperSize'] as String? ?? 'A4',
        landscape: j?['landscape'] as bool? ?? false,
        paperKind: j?['paper'] as String? ?? 'ambient',
        paperImage: j?['paperImage'] as String?,
        unknownFields: {
          for (final e in (j ?? const {}).entries)
            if (!_known.contains(e.key)) e.key: e.value,
        },
      );
}

class PageData {
  PageData(this.blocks, this.props);
  final List<Block> blocks;
  final PageProps props;
}

// ── Blocks ───────────────────────────────────────────────────────────────

// `flashcard` is the newest member, and adding it was only safe because of
// `Block.rawType`: a build that predates it reads the type as `unknown`,
// carries the literal string through untouched, and writes it back — so a page
// with a card on it round-trips through an older Openote without losing the
// card. Before rawType, a new enum value destroyed data on old builds.
enum BlockType {
  text,
  ink,
  math,
  image,
  code,
  file,
  table,
  frame,
  embed,
  flashcard,
  // A trello-style task board: columns of draggable cards. Additive under
  // the same `rawType` contract that made `flashcard` safe to add — an older
  // build shows "Unsupported block: board" and round-trips it untouched.
  board,
  // A curve drawn from an equation. Additive under the same `rawType`
  // contract that made `board` and `flashcard` safe: an older build shows
  // "Unsupported block: graph" and round-trips it untouched.
  graph,
  // An equation with a value plugged into it, and the result — the graph's
  // sibling for a single point rather than a curve. Same `rawType` safety.
  substitute,
  // A multiple-choice quiz, populated from a CSV or Excel file. Additive
  // under the same `rawType` contract: an older build shows "Unsupported
  // block: quiz" and round-trips it untouched.
  quiz,
  // An auto-laid-out mind map (tree of labels). Same `rawType` safety: an
  // older build shows "Unsupported block: mindmap" and round-trips it.
  mindmap,
  // A presentation: a stored PDF paged through one slide at a time. Same
  // `rawType` safety: an older build shows "Unsupported block: presentation"
  // and round-trips it untouched.
  presentation,
  unknown
}

BlockType blockTypeFrom(String s) =>
    BlockType.values.asNameMap()[s] ?? BlockType.unknown;

class Block {
  Block({
    String? id,
    required this.type,
    required this.x,
    required this.y,
    this.w = 320,
    this.h,
    this.z = 0,
    this.rotation = 0,
    this.placement = 'free',
    this.frameId,
    Map<String, dynamic>? content,
    List<String>? absorbedIds,
    this.access,
    this.rawType,
    Map<String, dynamic>? unknownFields,
    int? createdAt,
  })  : id = id ?? newId(),
        content = content ?? {},
        absorbedIds = absorbedIds ?? [],
        unknownFields = unknownFields ?? {},
        createdAt = createdAt ?? nowMs(),
        updatedAt = createdAt ?? nowMs();

  final String id;
  final BlockType type;
  double x, y;
  double w;
  double? h; // null = auto-height
  int z;

  /// Degrees clockwise. **Round-tripped but not yet applied when rendering** —
  /// no UI creates a rotated block. It is a real envelope field rather than an
  /// unknown-field passenger because the spec defines it; previously `toJson`
  /// hard-coded `0` while `_known` claimed the key, so any non-zero rotation in
  /// a file was destroyed on the first load→save cycle.
  double rotation;
  String placement; // 'free' | 'snapped'
  String? frameId;
  Map<String, dynamic> content;
  final List<String> absorbedIds;
  Map<String, dynamic>? access; // reserved (SYNC-9); v1 writes null
  final Map<String, dynamic> unknownFields; // forward-compat round-trip

  /// The on-the-wire `type` string when [type] is [BlockType.unknown], so
  /// re-serialising preserves it exactly.
  ///
  /// **Without this, an old build silently destroys a newer build's block on
  /// the first save.** `blockTypeFrom` folds any unrecognised name to
  /// `BlockType.unknown`, and `toJson` wrote `type.name` — the literal string
  /// `"unknown"`. `'type'` is in [_known], so it was not rescued into
  /// [unknownFields] either. A page holding a block type from a later release
  /// therefore round-tripped as `"type":"unknown"`: the content survived, its
  /// meaning did not, and no later build could ever identify it again.
  ///
  /// That makes the "new block types are additive" half of the frozen-v1
  /// promise false, which is why it is fixed here rather than worked around by
  /// whichever feature needs a new type first. [Op.rawTag] is the same idea and
  /// got it right; `Block` simply never had the equivalent.
  final String? rawType;
  final int createdAt;
  int updatedAt;

  static const _known = {
    'id',
    'type',
    'x',
    'y',
    'w',
    'h',
    'rotation',
    'z',
    'placement',
    'frameId',
    'absorbedIds',
    'access',
    'createdAt',
    'updatedAt',
    'content',
  };

  Map<String, dynamic> toJson() => {
        'id': id,
        // `rawType` first: an unrecognised type keeps the name it arrived with.
        'type': type == BlockType.unknown ? (rawType ?? type.name) : type.name,
        'x': x, 'y': y, 'w': w, 'h': h,
        'rotation': rotation,
        'z': z,
        'placement': placement,
        'frameId': frameId,
        'absorbedIds': absorbedIds,
        'access': access,
        'createdAt': createdAt,
        'updatedAt': updatedAt,
        'content': content,
        ...unknownFields,
      };

  factory Block.fromJson(Map<String, dynamic> j) => Block(
        id: j['id'] as String,
        type: blockTypeFrom(j['type'] as String? ?? 'unknown'),
        rawType: j['type'] as String?,
        x: (j['x'] as num?)?.toDouble() ?? 0,
        y: (j['y'] as num?)?.toDouble() ?? 0,
        w: (j['w'] as num?)?.toDouble() ?? 320,
        h: (j['h'] as num?)?.toDouble(),
        z: (j['z'] as num?)?.toInt() ?? 0,
        rotation: (j['rotation'] as num?)?.toDouble() ?? 0,
        placement: j['placement'] as String? ?? 'free',
        frameId: j['frameId'] as String?,
        content: (j['content'] as Map?)?.cast<String, dynamic>() ?? {},
        absorbedIds: (j['absorbedIds'] as List?)?.cast<String>() ?? [],
        access: (j['access'] as Map?)?.cast<String, dynamic>(),
        createdAt: (j['createdAt'] as num?)?.toInt(),
        unknownFields: {
          for (final e in j.entries)
            if (!_known.contains(e.key)) e.key: e.value,
        },
      )..updatedAt = (j['updatedAt'] as num?)?.toInt() ?? nowMs();
}

// ── Ink (Ink Data Spec §2: parallel arrays, immutable strokes) ───────────

class Stroke {
  Stroke({
    String? id,
    required this.tool,
    required this.colorHex,
    required this.size,
    this.opacity = 1.0,
    List<double>? x,
    List<double>? y,
    List<double>? p,
    List<double>? tx,
    List<double>? ty,
    List<int>? t,
    int? strokeStart,
    this.sharp = false,
  })  : id = id ?? newId(),
        x = x ?? [],
        y = y ?? [],
        p = p ?? [],
        tx = tx ?? [],
        ty = ty ?? [],
        t = t ?? [],
        strokeStart = strokeStart ?? nowMs();

  final String id;
  final String tool; // pen | highlighter
  final String colorHex; // "#RRGGBB"
  final double size;
  final double opacity;
  final List<double> x, y, p;

  /// A drawn shape (rectangle) that must keep sharp corners: the renderer
  /// skips the freehand streamline/smoothing that rounds a hand-drawn line, so
  /// the four corners stay square. Written only when true, so ordinary
  /// handwriting is byte-for-byte unchanged.
  final bool sharp;

  /// Pen tilt (Ink Data Spec §2). Empty when the device didn't report it — which
  /// is every device Flutter currently exposes tilt-free, so we don't *capture*
  /// it yet. We do **round-trip** whatever a file contains: these were previously
  /// written as `const []` and never read back, so tilt recorded by another tool
  /// was destroyed by simply opening and saving the page.
  final List<double> tx, ty;
  final List<int> t;

  /// Epoch ms at pen-down, and the origin the per-point offsets in [t] are
  /// measured from — `page_canvas` records `nowMs() - strokeStart` per sample,
  /// and the area eraser carries it onto each surviving fragment so the split
  /// runs keep the same origin. That is the whole of what reads it: nothing
  /// replays, animates, orders or undoes by it, and the InkML exporter writes
  /// [t], not this.
  ///
  /// The [nowMs] default is right for live capture and wrong for anything
  /// synthesising strokes from a file, because this value is encoded into the
  /// content-addressed ink blob. A writer that stamps the clock makes
  /// byte-identical handwriting hash differently on every import — the OneNote
  /// importer did, and re-importing one notebook stored its entire ink payload
  /// again. Importers pass 0 for "no time known".
  final int strokeStart;

  Map<String, dynamic> toJson() => {
        'id': id,
        'brush': {
          'tool': tool,
          'color': colorHex,
          'size': size,
          'opacity': opacity
        },
        'x': x,
        'y': y,
        'p': p,
        'tx': tx,
        'ty': ty,
        't': t,
        'strokeStart': strokeStart,
        if (sharp) 'sharp': true,
      };

  factory Stroke.fromJson(Map<String, dynamic> j) {
    final b = (j['brush'] as Map).cast<String, dynamic>();
    return Stroke(
      id: j['id'] as String,
      tool: b['tool'] as String? ?? 'pen',
      colorHex: b['color'] as String? ?? '#211F1B',
      size: (b['size'] as num?)?.toDouble() ?? 2.5,
      opacity: (b['opacity'] as num?)?.toDouble() ?? 1.0,
      x: (j['x'] as List).map((e) => (e as num).toDouble()).toList(),
      y: (j['y'] as List).map((e) => (e as num).toDouble()).toList(),
      p: ((j['p'] as List?) ?? const [])
          .map((e) => (e as num).toDouble())
          .toList(),
      tx: ((j['tx'] as List?) ?? const [])
          .map((e) => (e as num).toDouble())
          .toList(),
      ty: ((j['ty'] as List?) ?? const [])
          .map((e) => (e as num).toDouble())
          .toList(),
      t: ((j['t'] as List?) ?? const [])
          .map((e) => (e as num).toInt())
          .toList(),
      strokeStart: (j['strokeStart'] as num?)?.toInt(),
      sharp: j['sharp'] == true,
    );
  }

  ({double minX, double minY, double maxX, double maxY}) bounds() {
    var mnx = double.infinity, mny = double.infinity;
    var mxx = -double.infinity, mxy = -double.infinity;
    for (var i = 0; i < x.length; i++) {
      if (x[i] < mnx) mnx = x[i];
      if (x[i] > mxx) mxx = x[i];
      if (y[i] < mny) mny = y[i];
      if (y[i] > mxy) mxy = y[i];
    }
    return (minX: mnx, minY: mny, maxX: mxx, maxY: mxy);
  }
}
