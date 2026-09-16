import 'package:flutter/material.dart';

import '../canvas/paper.dart';
import '../core/platform_open.dart';
import '../model/models.dart';
import '../state/app_state.dart';
import '../theme/onote_theme.dart';
import '../update/app_update.dart';
import 'ai_provider_dialog.dart';
import 'central_sync_dialog.dart';
import 'mcp_dialog.dart';
import 'color_picker.dart' show ShortcutField;
import 'onote_dialog.dart';
import 'shortcut_overlay.dart';
import 'sync_dialog.dart';
import 'update_dialog.dart';

/// The centralised settings page (PLANNING "Consistency/UX"): one place
/// holding every app-wide preference and door — previously each lived only
/// wherever its feature happened to put a control. The per-feature controls
/// stay where they are (a toggle you use while drawing belongs in Draw);
/// this page is where you LOOK for one you can't find.
Future<void> showSettingsDialog(BuildContext context, AppState app) {
  return showOnoteDialog<void>(
    context: context,
    builder: (_) => _SettingsDialog(app: app),
  );
}

class _SettingsDialog extends StatefulWidget {
  const _SettingsDialog({required this.app});
  final AppState app;

  @override
  State<_SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<_SettingsDialog> {
  AppState get app => widget.app;

  bool _checking = false;
  String? _updateNote;

  Future<void> _checkNow() async {
    setState(() {
      _checking = true;
      _updateNote = null;
    });
    await app.checkForAppUpdate();
    if (!mounted) return;
    setState(() {
      _checking = false;
      _updateNote = app.updateAvailable == null
          ? "You're up to date ($kAppVersion is the newest version)."
          : null;
    });
    if (app.updateAvailable != null && mounted) {
      await showUpdateDialog(context, app);
    }
  }

  Widget _section(String title) => Padding(
        padding: const EdgeInsets.only(top: 14, bottom: 4),
        child: Text(title,
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.primary)),
      );

  /// A preference whose control is too wide to sit beside its label.
  ///
  /// The cursor picker has four segments and overflowed the row by 32px — a
  /// real layout assertion, not a cosmetic squeeze. Stacking keeps the
  /// dialog's one visual language (a highlighted segment says what is set)
  /// instead of dropping to a second one for the sake of width.
  Widget _rowStacked(String label, Widget control) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: 13)),
            const SizedBox(height: 6),
            SizedBox(width: double.infinity, child: control),
          ],
        ),
      );

  /// Label left, control right — and stacked instead when the dialog is
  /// squeezed (a very narrow window), so a wide control never overflows.
  Widget _row(String label, Widget control) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: LayoutBuilder(
          builder: (context, c) => c.maxWidth < 380
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: const TextStyle(fontSize: 13)),
                    const SizedBox(height: 4),
                    Align(alignment: Alignment.centerLeft, child: control),
                  ],
                )
              : Row(children: [
                  Expanded(
                      child: Text(label, style: const TextStyle(fontSize: 13))),
                  control,
                ]),
        ),
      );

  /// An on/off preference, shown the same way as the Theme row above it — a
  /// highlighted segment, not a switch. One visual language for "this is
  /// currently set to X" throughout the dialog, not two.
  Widget _toggle(bool value, ValueChanged<bool> onChanged) =>
      SegmentedButton<bool>(
        showSelectedIcon: false,
        style: const ButtonStyle(
            visualDensity: VisualDensity.compact,
            textStyle: WidgetStatePropertyAll(TextStyle(fontSize: 11))),
        segments: const [
          ButtonSegment(value: false, label: Text('Off')),
          ButtonSegment(value: true, label: Text('On')),
        ],
        selected: {value},
        onSelectionChanged: (s) => onChanged(s.first),
      );

  /// A short list of named choices, as a dense dropdown.
  Widget _pick(String value, Map<String, String> options,
          ValueChanged<String> onChanged) =>
      DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: options.containsKey(value) ? value : options.keys.first,
          isDense: true,
          style: TextStyle(
              fontSize: 12, color: Theme.of(context).colorScheme.onSurface),
          items: [
            for (final e in options.entries)
              DropdownMenuItem(value: e.key, child: Text(e.value)),
          ],
          onChanged: (v) => v == null ? null : onChanged(v),
        ),
      );

  Widget _door(IconData icon, String label, String hint, VoidCallback open) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(children: [
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: const TextStyle(fontSize: 13)),
              Text(hint,
                  style: const TextStyle(
                      fontSize: 11, color: OnoteColors.graphite400)),
            ]),
          ),
          TextButton.icon(
            icon: Icon(icon, size: 15),
            label: const Text('Open…', style: TextStyle(fontSize: 12)),
            onPressed: open,
          ),
        ]),
      );

  int _selected = 0;

  static const List<(IconData, String)> _nav = [
    (Icons.palette_outlined, 'Appearance'),
    (Icons.draw_outlined, 'Writing & drawing'),
    (Icons.description_outlined, 'Default page settings'),
    (Icons.hub_outlined, 'Connections'),
    (Icons.keyboard_outlined, 'Keyboard'),
    (Icons.info_outline, 'About'),
  ];

  List<Widget> _pageFor(BuildContext context, int i) => switch (i) {
        0 => _appearance(context),
        1 => _writing(context),
        2 => _defaultPage(context),
        3 => _connections(context),
        4 => _keyboard(context),
        _ => _about(context),
      };

  Widget _navTile(BuildContext context, int i) {
    final selected = i == _selected;
    final primary = Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: selected ? primary.withValues(alpha: .12) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => setState(() => _selected = i),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            child: Row(children: [
              Icon(_nav[i].$1, size: 18, color: selected ? primary : null),
              const SizedBox(width: 10),
              Expanded(
                child: Text(_nav[i].$2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight:
                            selected ? FontWeight.w600 : FontWeight.w400,
                        color: selected ? primary : null)),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _navChip(BuildContext context, int i) {
    final selected = i == _selected;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ChoiceChip(
        label: Text(_nav[i].$2, style: const TextStyle(fontSize: 12)),
        avatar: Icon(_nav[i].$1, size: 15),
        selected: selected,
        showCheckmark: false,
        visualDensity: VisualDensity.compact,
        onSelected: (_) => setState(() => _selected = i),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) => AlertDialog(
        title: const Text('Settings'),
        contentPadding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
        content: SizedBox(
          width: 680,
          height: 460,
          child: LayoutBuilder(
            builder: (context, c) {
              final content = ListView(
                key: ValueKey(_selected),
                padding: const EdgeInsets.only(right: 4, bottom: 8),
                children: _pageFor(context, _selected),
              );
              // Two panes when there is room; a scrolling row of chips over
              // the content when the window is too narrow for a sidebar.
              if (c.maxWidth < 460) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      height: 44,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: [
                          for (var i = 0; i < _nav.length; i++)
                            Center(child: _navChip(context, i)),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    const SizedBox(height: 8),
                    Expanded(child: content),
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: 178,
                    child: ListView(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      children: [
                        for (var i = 0; i < _nav.length; i++)
                          _navTile(context, i),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  const VerticalDivider(width: 1),
                  const SizedBox(width: 8),
                  Expanded(child: content),
                ],
              );
            },
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close')),
        ],
      ),
    );
  }

  List<Widget> _appearance(BuildContext context) => [
        _section('Appearance'),
        _row(
          'Theme',
          SegmentedButton<ThemeMode>(
            showSelectedIcon: false,
            style: const ButtonStyle(
                visualDensity: VisualDensity.compact,
                textStyle: WidgetStatePropertyAll(TextStyle(fontSize: 11))),
            segments: const [
              ButtonSegment(value: ThemeMode.system, label: Text('System')),
              ButtonSegment(value: ThemeMode.light, label: Text('Light')),
              ButtonSegment(value: ThemeMode.dark, label: Text('Dark')),
            ],
            selected: {app.themeMode},
            onSelectionChanged: (s) => app.setThemeMode(s.first),
          ),
        ),
        _rowStacked(
          'Accent',
          Wrap(
            spacing: 8,
            children: [
              for (final a in OnoteAccent.values)
                Tooltip(
                  message: a.label,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(99),
                    onTap: () => app.setAccent(a),
                    child: Container(
                      width: 26,
                      height: 26,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: a.color(
                            Theme.of(context).brightness == Brightness.dark),
                        border: a == app.accent
                            ? Border.all(
                                color: Theme.of(context).colorScheme.onSurface,
                                width: 2)
                            : null,
                      ),
                      child: a == app.accent
                          ? const Icon(Icons.check,
                              size: 14, color: Colors.white)
                          : null,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ];

  List<Widget> _writing(BuildContext context) => [
        _section('Writing & drawing'),
        _rowStacked(
          'Drawing cursor',
          SegmentedButton<PenCursorStyle>(
            showSelectedIcon: false,
            style: const ButtonStyle(
                visualDensity: VisualDensity.compact,
                textStyle: WidgetStatePropertyAll(TextStyle(fontSize: 11))),
            segments: [
              for (final v in PenCursorStyle.values)
                ButtonSegment(
                    value: v, label: Text(v.label), tooltip: v.describe),
            ],
            selected: {app.penCursorStyle},
            onSelectionChanged: (s) => app.setPenCursorStyle(s.first),
          ),
        ),
        _rowStacked(
          'Next ink colour',
          Align(
            alignment: Alignment.centerLeft,
            child: ShortcutField(
              value: app.cycleColorKey,
              onChanged: app.setCycleColorKey,
            ),
          ),
        ),
        _row('Spell check', _toggle(app.spellCheckEnabled, app.setSpellCheck)),
        _row('Pen near the page switches to inking',
            _toggle(app.penProximitySwitch, app.setPenProximitySwitch)),
      ];

  List<Widget> _defaultPage(BuildContext context) => [
        _section('Default page settings'),
        _rowStacked(
          'Pattern',
          SegmentedButton<String>(
            showSelectedIcon: false,
            style: const ButtonStyle(
                visualDensity: VisualDensity.compact,
                textStyle: WidgetStatePropertyAll(TextStyle(fontSize: 11))),
            segments: const [
              ButtonSegment(value: 'blank', label: Text('Blank')),
              ButtonSegment(value: 'grid', label: Text('Grid')),
              ButtonSegment(value: 'dotted', label: Text('Dots')),
              ButtonSegment(value: 'ruled', label: Text('Ruled')),
            ],
            selected: {app.defaultBackground},
            onSelectionChanged: (s) => app.setDefaultBackground(s.first),
          ),
        ),
        _rowStacked(
          'Pattern spacing',
          SizedBox(
            width: double.infinity,
            child: Row(children: [
              Expanded(
                child: Slider(
                  value: app.defaultBgSpacing,
                  min: PageProps.minBgSpacing,
                  max: PageProps.maxBgSpacing,
                  divisions: 28,
                  onChanged: app.setDefaultBgSpacing,
                ),
              ),
              SizedBox(
                width: 30,
                child: Text('${app.defaultBgSpacing.round()}',
                    textAlign: TextAlign.right,
                    style: const TextStyle(fontSize: 11)),
              ),
            ]),
          ),
        ),
        _row(
          'Paper background',
          _pick(
              app.defaultPaper,
              {
                for (final p in kPapers.where((p) => p != 'image'))
                  p: paperLabel(p)
              },
              app.setDefaultPaper),
        ),
        _row(
          'Page size',
          _pick(
              app.defaultPageSize,
              {
                'canvas': 'Canvas (boundless)',
                for (final p in PaperSize.all) p.name: p.name,
              },
              app.setDefaultPageSize),
        ),
        // Whether a page opens filled to the window width — the same as the
        // "Fit to width" control on the page, so the two read alike.
        _row('Fit new pages to width',
            _toggle(app.defaultStretchToScreen, app.setDefaultStretchToScreen)),
        // Whether an exported/pushed PDF carries the page's background pattern.
        _row('Add page background to the PDF export',
            _toggle(app.defaultPdfBackground, app.setDefaultPdfBackground)),
      ];

  List<Widget> _connections(BuildContext context) => [
        _section('Connections'),
        _door(
            Icons.sync,
            'Sync',
            'Back up and share this notebook — GitHub or a folder.',
            () => showSyncDialog(context, app)),
        _door(
            Icons.cloud_sync_outlined,
            'Sync all notebooks',
            app.central.enabled
                ? 'On — every notebook backs up to ${app.central.fullName ?? 'GitHub'}.'
                : 'Back up every notebook to one GitHub repo.',
            () => showCentralSyncDialog(context, app)),
        _door(
            Icons.smart_toy_outlined,
            'AI access',
            app.mcpEnabled
                ? 'On — AI helpers on this computer can use your notes.'
                : 'Off — connect Claude or other AI helpers.',
            () => showMcpDialog(context, app)),
        _door(
            Icons.auto_awesome_outlined,
            'AI provider',
            app.aiConnected
                ? 'Connected — ${app.aiProvider.label} · ${app.aiModel}'
                : 'Bring your own OpenAI or OpenRouter key.',
            () => showAiProviderDialog(context, app)),
        _row('Ask AI (chat bubble on the page)',
            _toggle(app.askAiEnabled, app.setAskAiEnabled)),
      ];

  List<Widget> _keyboard(BuildContext context) => [
        _section('Keyboard'),
        _door(
            Icons.keyboard_outlined,
            'Keyboard shortcuts',
            'Everything has a key — the full list.  (Ctrl+/)',
            () => showShortcutOverlay(context)),
      ];

  List<Widget> _about(BuildContext context) => [
        _section('About'),
        _row(
          'Slate $kAppVersion',
          _checking
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : TextButton(
                  onPressed: _checkNow,
                  child: const Text('Check for updates',
                      style: TextStyle(fontSize: 12)),
                ),
        ),
        if (app.updateAvailable != null)
          _row(
            'Version ${app.updateAvailable!.version} is available',
            TextButton(
              onPressed: () => showUpdateDialog(context, app),
              child: const Text('Update…', style: TextStyle(fontSize: 12)),
            ),
          ),
        if (_updateNote != null)
          Text(_updateNote!,
              style: const TextStyle(
                  fontSize: 11.5, color: OnoteColors.graphite400)),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: () => PlatformOpen.url(
                'https://github.com/AhmadMahi/openote/releases'),
            child: const Text("What's new", style: TextStyle(fontSize: 12)),
          ),
        ),
      ];
}
