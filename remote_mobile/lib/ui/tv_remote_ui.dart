import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:characters/characters.dart';
import 'joystick_pad.dart';
import 'dpad_controller.dart';
import 'qwerty_keyboard.dart';

/// TV Remote UI — full featured:
/// • Analog stick + D-pad toggle (sends tvkey: DPAD_* for navigation)
/// • D-pad ring with OK center button
/// • System buttons: Home, Back, Menu, Apps
/// • Volume + Media controls
/// • Colored A/B/C/D buttons
/// • Number pad
/// • Scroll pad
/// • Keyboard (mobile + QWERTY desktop)
/// • Disconnect button

enum _JoystickMode { analog, dpad }
enum _KeyboardMode { mobile, qwerty }

class TVRemoteUI extends StatefulWidget {
  final Function(String) sendCommand;
  final VoidCallback onDisconnect;

  const TVRemoteUI({
    super.key,
    required this.sendCommand,
    required this.onDisconnect,
  });

  @override
  State<TVRemoteUI> createState() => _TVRemoteUIState();
}

class _TVRemoteUIState extends State<TVRemoteUI> {
  // ── State ──────────────────────────────────────────────────────────────────
  _JoystickMode _joystickMode = _JoystickMode.analog;
  _KeyboardMode _keyboardMode = _KeyboardMode.mobile;

  double _analogSensitivity = 1.0;
  double _dpadSensitivity   = 1.0;

  double _scrollStartY = 0;
  double _scrollAccum  = 0;

  final TextEditingController _typeController = TextEditingController();
  final FocusNode _typeFocus = FocusNode();
  String _prevText = '';

  // ── Init ───────────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _typeFocus.onKeyEvent = (node, event) {
      if (event is KeyDownEvent || event is KeyRepeatEvent) {
        final lk = event.logicalKey;
        if (lk == LogicalKeyboardKey.backspace) {
          _tvkey('BACK');
          final text = _typeController.text;
          final sel  = _typeController.selection;
          if (text.isNotEmpty && sel.baseOffset > 0) {
            final newText = text.substring(0, sel.baseOffset - 1) +
                text.substring(sel.extentOffset);
            _typeController.value = TextEditingValue(
              text: newText,
              selection: TextSelection.collapsed(offset: sel.baseOffset - 1),
            );
            _prevText = newText;
          }
          return KeyEventResult.handled;
        }
        if (lk == LogicalKeyboardKey.enter ||
            lk == LogicalKeyboardKey.numpadEnter) {
          _tvkey('DPAD_CENTER');
          return KeyEventResult.handled;
        }
      }
      return KeyEventResult.ignored;
    };
  }

  @override
  void dispose() {
    _typeController.dispose();
    _typeFocus.dispose();
    super.dispose();
  }

  // ── Helpers ────────────────────────────────────────────────────────────────
  void _send(String cmd)   => widget.sendCommand(cmd);
  void _tvkey(String key)  => _send('tvkey:$key');

  /// Analog stick / dpad move → mapped to repeated DPAD key presses
  /// Threshold-based: fires a DPAD key every time the joystick crosses a zone
  Timer?  _joystickTimer;
  double  _jDx = 0, _jDy = 0;

  void _onJoystickMove(double dx, double dy) {
    _jDx = dx; _jDy = dy;
    _joystickTimer ??= Timer.periodic(const Duration(milliseconds: 120), (_) {
      if (_jDx.abs() > _jDy.abs()) {
        if (_jDx > 2)  _tvkey('DPAD_RIGHT');
        if (_jDx < -2) _tvkey('DPAD_LEFT');
      } else {
        if (_jDy > 2)  _tvkey('DPAD_DOWN');
        if (_jDy < -2) _tvkey('DPAD_UP');
      }
    });
  }

  void _onJoystickRelease() {
    _joystickTimer?.cancel();
    _joystickTimer = null;
    _jDx = 0; _jDy = 0;
  }

  void _handleMobileKeyboard(String newValue) {
    final prev = _prevText;
    if (newValue.length <= prev.length) { _prevText = newValue; return; }
    final added = newValue.substring(prev.length);
    for (final char in added.characters) {
      if (char == '\n')  _tvkey('DPAD_CENTER');
      else if (char == ' ') _tvkey('DPAD_CENTER'); // space = OK on TV
      else _send('tvkey:TEXT_$char'); // for future text input support
    }
    _prevText = newValue;
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: Column(
        children: [
          // ── 1. System buttons ─────────────────────────────────────────────
          _buildSystemRow(),
          const SizedBox(height: 24),

          // ── 2. Joystick (analog/dpad toggle) ─────────────────────────────
          _buildJoystick(),
          const SizedBox(height: 24),

          // ── 3. D-pad ring ─────────────────────────────────────────────────
          _buildDpad(),
          const SizedBox(height: 24),

          // ── 4. Volume + Media ─────────────────────────────────────────────
          _buildMediaRow(),
          const SizedBox(height: 24),

          // ── 5. Colored buttons ────────────────────────────────────────────
          _buildColorRow(),
          const SizedBox(height: 24),

          // ── 6. Scroll pad ─────────────────────────────────────────────────
          _buildScrollPad(),
          const SizedBox(height: 24),

          // ── 7. Keyboard ───────────────────────────────────────────────────
          _buildKeyboard(),
          const SizedBox(height: 24),

          // ── 8. Number pad ─────────────────────────────────────────────────
          _buildNumpad(),
          const SizedBox(height: 24),

          // ── 9. Disconnect ─────────────────────────────────────────────────
          TextButton.icon(
            onPressed: widget.onDisconnect,
            icon: const Icon(Icons.link_off, size: 16),
            label: const Text("Disconnect"),
            style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  // ── 1. System row ──────────────────────────────────────────────────────────
  Widget _buildSystemRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _sysBtn(Icons.home_rounded,       "Home",  () => _tvkey('HOME')),
        _sysBtn(Icons.arrow_back_rounded, "Back",  () => _tvkey('BACK')),
        _sysBtn(Icons.menu_rounded,       "Menu",  () => _tvkey('MENU')),
        _sysBtn(Icons.grid_view_rounded,  "Apps",  () => _tvkey('APP_SWITCH')),
      ],
    );
  }

  // ── 2. Joystick ────────────────────────────────────────────────────────────
  Widget _buildJoystick() {
    final double sensitivity = _joystickMode == _JoystickMode.analog
        ? _analogSensitivity
        : _dpadSensitivity;

    return Column(
      children: [
        // Toggle
        Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceVariant,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(children: [
            _jsTab("🕹️ Analog", _JoystickMode.analog),
            _jsTab("🎮 D-Pad",  _JoystickMode.dpad),
          ]),
        ),
        const SizedBox(height: 12),

        // Sensitivity slider
        Row(children: [
          const Text("Sensitivity", style: TextStyle(fontSize: 12)),
          Expanded(
            child: Slider(
              value: sensitivity, min: 0.2, max: 5.0, divisions: 24,
              label: sensitivity.toStringAsFixed(1),
              onChanged: (v) => setState(() {
                if (_joystickMode == _JoystickMode.analog) {
                  _analogSensitivity = v;
                } else {
                  _dpadSensitivity = v;
                }
              }),
            ),
          ),
          SizedBox(
            width: 32,
            child: Text(sensitivity.toStringAsFixed(1),
                style: const TextStyle(fontSize: 12)),
          ),
        ]),

        Text(
          _joystickMode == _JoystickMode.analog
              ? "Drag to navigate — maps to D-pad"
              : "Hold buttons to navigate",
          style: const TextStyle(color: Colors.grey, fontSize: 12),
        ),
        const SizedBox(height: 12),

        if (_joystickMode == _JoystickMode.analog)
          JoystickPad(
            sensitivity: _analogSensitivity,
            onMove: _onJoystickMove,
            onRelease: _onJoystickRelease,
          ),
        if (_joystickMode == _JoystickMode.dpad)
          DpadController(
            sensitivity: _dpadSensitivity,
            onMove: _onJoystickMove,
            onRelease: _onJoystickRelease,
          ),
      ],
    );
  }

  // ── 3. D-pad ring ──────────────────────────────────────────────────────────
  Widget _buildDpad() {
    return Column(
      children: [
        const Text("D-Pad",
            style: TextStyle(fontSize: 12, color: Colors.grey)),
        const SizedBox(height: 8),
        SizedBox(
          width: 220, height: 220,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Outer ring
              Container(
                width: 220, height: 220,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Theme.of(context).colorScheme.surfaceVariant,
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outline.withOpacity(0.3),
                    width: 2,
                  ),
                ),
              ),
              Positioned(top: 10,    child: _dpadArrow(Icons.keyboard_arrow_up,    () => _tvkey('DPAD_UP'))),
              Positioned(bottom: 10, child: _dpadArrow(Icons.keyboard_arrow_down,  () => _tvkey('DPAD_DOWN'))),
              Positioned(left: 10,   child: _dpadArrow(Icons.keyboard_arrow_left,  () => _tvkey('DPAD_LEFT'))),
              Positioned(right: 10,  child: _dpadArrow(Icons.keyboard_arrow_right, () => _tvkey('DPAD_RIGHT'))),
              _okButton(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _dpadArrow(IconData icon, VoidCallback onTap) {
    return _HoldButton(
      onTap: onTap,
      child: Container(
        width: 60, height: 60,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Theme.of(context).colorScheme.surface,
        ),
        child: Icon(icon, size: 32,
            color: Theme.of(context).colorScheme.onSurface),
      ),
    );
  }

  Widget _okButton() {
    return GestureDetector(
      onTap: () => _tvkey('DPAD_CENTER'),
      child: Container(
        width: 72, height: 72,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Theme.of(context).colorScheme.primary,
          boxShadow: [BoxShadow(
            color: Theme.of(context).colorScheme.primary.withOpacity(0.4),
            blurRadius: 12, offset: const Offset(0, 4),
          )],
        ),
        child: Center(child: Text("OK", style: TextStyle(
          color: Theme.of(context).colorScheme.onPrimary,
          fontWeight: FontWeight.bold, fontSize: 18,
        ))),
      ),
    );
  }

  // ── 4. Media row ───────────────────────────────────────────────────────────
  Widget _buildMediaRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _mediaBtn(Icons.volume_down_rounded,   () => _tvkey('VOLUME_DOWN')),
        _mediaBtn(Icons.volume_mute_rounded,   () => _tvkey('VOLUME_MUTE')),
        _mediaBtn(Icons.volume_up_rounded,     () => _tvkey('VOLUME_UP')),
        const SizedBox(width: 24),
        _mediaBtn(Icons.skip_previous_rounded, () => _tvkey('MEDIA_PREVIOUS')),
        _mediaBtn(Icons.play_arrow_rounded,    () => _tvkey('MEDIA_PLAY_PAUSE')),
        _mediaBtn(Icons.skip_next_rounded,     () => _tvkey('MEDIA_NEXT')),
      ],
    );
  }

  // ── 5. Color buttons ───────────────────────────────────────────────────────
  Widget _buildColorRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _colorBtn(Colors.red,    "A", () => _tvkey('PROG_RED')),
        _colorBtn(Colors.green,  "B", () => _tvkey('PROG_GREEN')),
        _colorBtn(Colors.yellow, "C", () => _tvkey('PROG_YELLOW')),
        _colorBtn(Colors.blue,   "D", () => _tvkey('PROG_BLUE')),
      ],
    );
  }

  // ── 6. Scroll pad ──────────────────────────────────────────────────────────
  Widget _buildScrollPad() {
    return Container(
      height: 80,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceVariant,
        borderRadius: BorderRadius.circular(12),
      ),
      child: GestureDetector(
        onVerticalDragStart: (d) {
          _scrollStartY = d.localPosition.dy;
          _scrollAccum  = 0;
        },
        onVerticalDragUpdate: (d) {
          _scrollAccum += d.localPosition.dy - _scrollStartY;
          _scrollStartY = d.localPosition.dy;
          if (_scrollAccum.abs() >= 20) {
            final ticks = (_scrollAccum / 20).truncate();
            // Scroll down → DPAD_DOWN, scroll up → DPAD_UP
            if (ticks > 0) _tvkey('DPAD_DOWN');
            if (ticks < 0) _tvkey('DPAD_UP');
            _scrollAccum -= ticks * 20;
          }
        },
        child: const Center(
          child: Text("↕  Scroll pad  ↕",
              style: TextStyle(color: Colors.grey)),
        ),
      ),
    );
  }

  // ── 7. Keyboard ────────────────────────────────────────────────────────────
  Widget _buildKeyboard() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceVariant,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(children: [
            _kbTab("📱 Mobile",  _KeyboardMode.mobile),
            _kbTab("🖥️ Desktop", _KeyboardMode.qwerty),
          ]),
        ),
        const SizedBox(height: 12),
        if (_keyboardMode == _KeyboardMode.mobile)  _buildMobileInput(),
        if (_keyboardMode == _KeyboardMode.qwerty)
          QwertyKeyboard(onKey: (cmd) => _send(cmd)),
      ],
    );
  }

  Widget _buildMobileInput() {
    return Column(
      children: [
        const Text(
          "Type here — text sent to TV.\nEnter = OK, Backspace = Back.",
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey, fontSize: 12),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _typeController,
          focusNode: _typeFocus,
          onChanged: _handleMobileKeyboard,
          keyboardType: TextInputType.multiline,
          maxLines: 3,
          minLines: 1,
          decoration: const InputDecoration(
            labelText: "Type here — sends to TV",
            border: OutlineInputBorder(),
            hintText: "Tap and type anything...",
          ),
        ),
      ],
    );
  }

  // ── 8. Number pad ──────────────────────────────────────────────────────────
  Widget _buildNumpad() {
    final nums = [
      ['1','2','3'],
      ['4','5','6'],
      ['7','8','9'],
      ['*','0','#'],
    ];
    return Column(
      children: [
        const Text("Numpad",
            style: TextStyle(fontSize: 12, color: Colors.grey)),
        const SizedBox(height: 8),
        ...nums.map((row) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: row.map((n) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: GestureDetector(
                onTap: () => _tvkey('NUMPAD_$n'),
                child: Container(
                  width: 64, height: 48,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceVariant,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: Theme.of(context).colorScheme.outline.withOpacity(0.3)),
                  ),
                  child: Center(child: Text(n,
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold))),
                ),
              ),
            )).toList(),
          ),
        )),
      ],
    );
  }

  // ── Button helpers ─────────────────────────────────────────────────────────
  Widget _sysBtn(IconData icon, String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56, height: 56,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceVariant,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                  color: Theme.of(context).colorScheme.outline.withOpacity(0.3)),
              boxShadow: [BoxShadow(
                  color: Colors.black.withOpacity(0.15),
                  blurRadius: 4, offset: const Offset(0, 2))],
            ),
            child: Icon(icon, size: 26),
          ),
          const SizedBox(height: 6),
          Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
        ],
      ),
    );
  }

  Widget _mediaBtn(IconData icon, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 44, height: 44,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceVariant,
            shape: BoxShape.circle,
            border: Border.all(
                color: Theme.of(context).colorScheme.outline.withOpacity(0.3)),
          ),
          child: Icon(icon, size: 22),
        ),
      ),
    );
  }

  Widget _colorBtn(Color color, String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 56, height: 40,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(10),
          boxShadow: [BoxShadow(
              color: color.withOpacity(0.4),
              blurRadius: 8, offset: const Offset(0, 3))],
        ),
        child: Center(child: Text(label,
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16))),
      ),
    );
  }

  Widget _jsTab(String label, _JoystickMode mode) {
    final bool selected = _joystickMode == mode;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _joystickMode = mode),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: selected
                ? Theme.of(context).colorScheme.secondary
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: selected
                  ? Theme.of(context).colorScheme.onSecondary
                  : Theme.of(context).colorScheme.onSurfaceVariant,
              fontWeight: selected ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }

  Widget _kbTab(String label, _KeyboardMode mode) {
    final bool selected = _keyboardMode == mode;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _keyboardMode = mode),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: selected
                ? Theme.of(context).colorScheme.secondary
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: selected
                  ? Theme.of(context).colorScheme.onSecondary
                  : Theme.of(context).colorScheme.onSurfaceVariant,
              fontWeight: selected ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }
}

// ── Hold-to-repeat button ──────────────────────────────────────────────────────
class _HoldButton extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  const _HoldButton({required this.child, required this.onTap});

  @override
  State<_HoldButton> createState() => _HoldButtonState();
}

class _HoldButtonState extends State<_HoldButton> {
  Timer? _timer;

  void _startHold() {
    widget.onTap();
    _timer = Timer.periodic(
        const Duration(milliseconds: 150), (_) => widget.onTap());
  }

  void _stopHold() { _timer?.cancel(); _timer = null; }

  @override
  void dispose() { _stopHold(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown:  (_) => _startHold(),
      onTapUp:    (_) => _stopHold(),
      onTapCancel:    _stopHold,
      child: widget.child,
    );
  }
}
