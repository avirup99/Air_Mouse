import 'package:flutter/material.dart';

/// A scrollable full desktop keyboard layout.
/// Rows: Esc+F1-F12 | ` 1-0 - = ⌫ | Tab Q-P [ ] \ | Caps A-L ; ' ↵ |
///       ⇧ Z-M , . / ⇧ | Ctrl Win Alt ___Space___ Alt Ctrl | ← ↑ ↓ →
class QwertyKeyboard extends StatefulWidget {
  final Function(String) onKey;
  const QwertyKeyboard({super.key, required this.onKey});

  @override
  State<QwertyKeyboard> createState() => _QwertyKeyboardState();
}

class _QwertyKeyboardState extends State<QwertyKeyboard> {
  bool _caps  = false; // CapsLock toggle (via Caps key only)
  bool _shift = false; // one-shot Shift (resets after next char)
  bool _ctrl  = false; // sticky until next char
  bool _alt   = false; // sticky until next char

  bool get _upper => _caps || _shift;

  void _send(String cmd) => widget.onKey(cmd);

  // FIX: Shift is now purely one-shot — single tap = on, tap again = off.
  // Double-tapping Shift no longer activates CapsLock. Use the Caps key for that.
  void _tapShift() {
    setState(() => _shift = !_shift);
  }

  void _tapCaps() {
    setState(() => _caps = !_caps);
  }

  void _tapCtrl() => setState(() => _ctrl = !_ctrl);
  void _tapAlt()  => setState(() => _alt  = !_alt);

  // Build modifier prefix e.g. "CTRL+ALT+" then the key.
  // NOTE: Shift is NOT sent as a modifier here because the character
  // is already uppercased before being sent (handled by _upper).
  String _withMods(String key) {
    String prefix = '';
    if (_ctrl) prefix += 'CTRL+';
    if (_alt)  prefix += 'ALT+';
    return 'key:$prefix$key';
  }

  // Reset one-shot modifiers after a character key is pressed
  void _clearOneShot() {
    if (_shift) setState(() => _shift = false);
    if (_ctrl)  setState(() => _ctrl  = false);
    if (_alt)   setState(() => _alt   = false);
  }

  void _onChar(String lower) {
    final ch = _upper ? lower.toUpperCase() : lower;
    _send(_withMods(ch));
    _clearOneShot();
  }

  void _onShifted(String normal, String shifted, {double w = 34}) {
    _send(_withMods(_upper ? shifted : normal));
    _clearOneShot();
  }

  // Special/named VK keys — Ctrl/Alt apply, Shift does NOT (F-keys are not shifted)
  void _onSpecial(String vk) {
    _send(_withMods(vk));
    // Only clear Ctrl/Alt; leave Caps/Shift alone for special keys
    if (_ctrl) setState(() => _ctrl = false);
    if (_alt)  setState(() => _alt  = false);
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _fRow(),
          _row1(),
          _row2(),
          _row3(),
          _row4(),
          _bottomRow(),
          const SizedBox(height: 6),
          _arrowCluster(),
        ],
      ),
    );
  }

  // ── Rows ─────────────────────────────────────────────────────────────────

  Widget _fRow() => _buildRow([
    _k('Esc', w: 36, onTap: () => _onSpecial('ESCAPE')),
    _gap(8),
    _k('F1',  onTap: () => _onSpecial('F1')),
    _k('F2',  onTap: () => _onSpecial('F2')),
    _k('F3',  onTap: () => _onSpecial('F3')),
    _k('F4',  onTap: () => _onSpecial('F4')),
    _gap(6),
    _k('F5',  onTap: () => _onSpecial('F5')),
    _k('F6',  onTap: () => _onSpecial('F6')),
    _k('F7',  onTap: () => _onSpecial('F7')),
    _k('F8',  onTap: () => _onSpecial('F8')),
    _gap(6),
    _k('F9',  onTap: () => _onSpecial('F9')),
    _k('F10', onTap: () => _onSpecial('F10')),
    _k('F11', onTap: () => _onSpecial('F11')),
    _k('F12', onTap: () => _onSpecial('F12')),
    _gap(6),
    _k('PrtSc', w: 38, onTap: () => _onSpecial('SNAPSHOT')),
    _k('Del',   w: 36, onTap: () => _onSpecial('DELETE')),
  ]);

  Widget _row1() => _buildRow([
    _ks('`', '~'),
    _ks('1', '!'), _ks('2', '@'), _ks('3', '#'), _ks('4', r'$'),
    _ks('5', '%'), _ks('6', '^'), _ks('7', '&'), _ks('8', '*'),
    _ks('9', '('), _ks('0', ')'), _ks('-', '_'), _ks('=', '+'),
    _k('⌫', w: 52, onTap: () => _onSpecial('BACKSPACE')),
  ]);

  Widget _row2() => _buildRow([
    _k('Tab', w: 50, onTap: () => _onSpecial('TAB')),
    _c('q'), _c('w'), _c('e'), _c('r'), _c('t'),
    _c('y'), _c('u'), _c('i'), _c('o'), _c('p'),
    _ks('[', '{'), _ks(']', '}'), _ks('\\', '|', w: 44),
  ]);

  Widget _row3() => _buildRow([
    _k(
      _caps ? '⇪ ON' : 'Caps',
      w: 60,
      onTap: _tapCaps,
      active: _caps,
      activeColor: Colors.orange,
    ),
    _c('a'), _c('s'), _c('d'), _c('f'), _c('g'),
    _c('h'), _c('j'), _c('k'), _c('l'),
    _ks(';', ':'), _ks("'", '"'),
    _k('↵ Enter', w: 66, onTap: () => _onSpecial('ENTER')),
  ]);

  Widget _row4() => _buildRow([
    _k(
      '⇧ Shift',
      w: 76,
      onTap: _tapShift,
      active: _shift,
    ),
    _c('z'), _c('x'), _c('c'), _c('v'), _c('b'),
    _c('n'), _c('m'),
    _ks(',', '<'), _ks('.', '>'), _ks('/', '?'),
    _k(
      '⇧ Shift',
      w: 76,
      onTap: _tapShift,
      active: _shift,
    ),
  ]);

  Widget _bottomRow() => _buildRow([
    _k(
      'Ctrl', w: 50,
      onTap: _tapCtrl,
      active: _ctrl,
    ),
    _k('Win', w: 40, onTap: () => _onSpecial('LWIN')),
    _k(
      'Alt', w: 40,
      onTap: _tapAlt,
      active: _alt,
    ),
    _k('Space', w: 180, onTap: () => _onSpecial('SPACE')),
    _k(
      'Alt', w: 40,
      onTap: _tapAlt,
      active: _alt,
    ),
    _k('Ctrl', w: 50,
      onTap: _tapCtrl,
      active: _ctrl,
    ),
  ]);

  // FIX: Corrected arrow cluster layout — proper cross/inverted-T arrangement.
  // Top row: blank + ↑ + blank
  // Bottom row: ← + ↓ + →
  Widget _arrowCluster() => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      // Top row of arrows: just ↑ centered over ↓
      Padding(
        padding: const EdgeInsets.only(left: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _gap(38), // align ↑ over ↓
            _k('↑', onTap: () => _onSpecial('UP')),
            _gap(38), // blank right side
          ],
        ),
      ),
      const SizedBox(height: 3),
      // Bottom row: ← ↓ →
      Padding(
        padding: const EdgeInsets.only(left: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _k('←', onTap: () => _onSpecial('LEFT')),
            _k('↓', onTap: () => _onSpecial('DOWN')),
            _k('→', onTap: () => _onSpecial('RIGHT')),
          ],
        ),
      ),
      const SizedBox(height: 6),
      // Nav cluster
      Padding(
        padding: const EdgeInsets.only(left: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _k('Home', w: 44, onTap: () => _onSpecial('HOME')),
            _k('End',  w: 40, onTap: () => _onSpecial('END')),
            _k('PgUp', w: 44, onTap: () => _onSpecial('PRIOR')),
            _k('PgDn', w: 44, onTap: () => _onSpecial('NEXT')),
          ],
        ),
      ),
    ],
  );

  // ── Helpers ───────────────────────────────────────────────────────────────

  Widget _buildRow(List<Widget> children) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(mainAxisSize: MainAxisSize.min, children: children),
  );

  // Regular character key
  Widget _c(String lower) => _k(
    _upper ? lower.toUpperCase() : lower,
    onTap: () => _onChar(lower),
  );

  // Shifted character key (e.g. 1/!, =/+)
  Widget _ks(String normal, String shifted, {double w = 34}) => _k(
    _upper ? shifted : normal,
    w: w,
    onTap: () => _onShifted(normal, shifted),
  );

  // Gap spacer
  Widget _gap(double w) => SizedBox(width: w);

  // Base key widget
  Widget _k(
    String label, {
    double w = 34,
    required VoidCallback onTap,
    bool active = false,
    Color? activeColor,
  }) {
    final cs = Theme.of(context).colorScheme;
    Color bg;
    Color fg;
    if (active) {
      bg = activeColor ?? cs.primary;
      fg = activeColor != null ? Colors.white : cs.onPrimary;
    } else {
      bg = cs.surface;
      fg = cs.onSurface;
    }

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: w,
        height: 38,
        margin: const EdgeInsets.symmetric(horizontal: 1.5),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: cs.outline.withOpacity(0.3)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.18),
              blurRadius: 2,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: label.length > 3 ? 9 : 11,
              fontWeight: FontWeight.w500,
              color: fg,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }
}