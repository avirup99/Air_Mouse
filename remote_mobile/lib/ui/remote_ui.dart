import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:characters/characters.dart';
import '../ui/joystick_pad.dart';
import '../ui/dpad_controller.dart';
import '../ui/qwerty_keyboard.dart';

class RemoteUI extends StatefulWidget {
  final Function(String) sendCommand;
  final VoidCallback onDisconnect;
  const RemoteUI(
      {super.key, required this.sendCommand, required this.onDisconnect});

  @override
  State<RemoteUI> createState() => _RemoteUIState();
}

enum JoystickMode { analog, dpad }
enum KeyboardMode { mobile, qwerty }

class _RemoteUIState extends State<RemoteUI> {
  final TextEditingController _typeController = TextEditingController();
  final FocusNode _typeFocus = FocusNode();

  JoystickMode _joystickMode = JoystickMode.analog;
  KeyboardMode _keyboardMode = KeyboardMode.mobile;

  // Separate sensitivity for analog and dpad
  double _analogSensitivity = 1.0;
  double _dpadSensitivity = 1.0;

  double _scrollStartY = 0;
  double _scrollAccum = 0;

  String _prevText = '';

  @override
  void initState() {
    super.initState();

    _typeFocus.onKeyEvent = (node, event) {
      if (event is KeyDownEvent || event is KeyRepeatEvent) {
        final lk = event.logicalKey;

        if (lk == LogicalKeyboardKey.backspace) {
          // Hardware keyboard backspace — send to laptop AND update local box
          widget.sendCommand("key:BACKSPACE");
          final text = _typeController.text;
          final sel = _typeController.selection;
          if (text.isNotEmpty && sel.baseOffset > 0) {
            final newText = text.substring(0, sel.baseOffset - 1) +
                text.substring(sel.extentOffset);
            _typeController.value = TextEditingValue(
              text: newText,
              selection:
                  TextSelection.collapsed(offset: sel.baseOffset - 1),
            );
            _prevText = newText;
          }
          return KeyEventResult.handled;
        }

        if (lk == LogicalKeyboardKey.enter ||
            lk == LogicalKeyboardKey.numpadEnter) {
          widget.sendCommand("key:ENTER");
          return KeyEventResult.handled;
        }
      }
      return KeyEventResult.ignored;
    };
  }

  void _handleMobileKeyboard(String newValue) {
    final prev = _prevText;
    _prevText = newValue;

    if (newValue.length < prev.length) {
      // Text was deleted — send one BACKSPACE per deleted character
      final deletedCount = prev.length - newValue.length;
      for (int i = 0; i < deletedCount; i++) {
        widget.sendCommand("key:BACKSPACE");
      }
      return;
    }

    if (newValue.length == prev.length) return; // selection change, ignore

    // Text was added — send each new character
    final added = newValue.substring(prev.length);
    for (final char in added.characters) {
      if (char == '\n') {
        widget.sendCommand("key:ENTER");
      } else if (char == ' ') {
        widget.sendCommand("key:SPACE");
      } else {
        widget.sendCommand("key:$char");
      }
    }
  }

  @override
  void dispose() {
    _typeController.dispose();
    _typeFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          _buildJoystick(),
          const SizedBox(height: 20),
          _buildKeyboard(),
          const SizedBox(height: 20),
          _buildScrollPad(),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _mouseBtn("L", () => widget.sendCommand("click:left")),
              _mouseBtn("M", () => widget.sendCommand("click:middle")),
              _mouseBtn("R", () => widget.sendCommand("click:right")),
            ],
          ),
          const SizedBox(height: 20),
          TextButton.icon(
            onPressed: widget.onDisconnect,
            icon: const Icon(Icons.link_off, size: 16),
            label: const Text("Disconnect"),
            style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
          ),
        ],
      ),
    );
  }

  Widget _buildJoystick() {
    final double sensitivity =
        _joystickMode == JoystickMode.analog ? _analogSensitivity : _dpadSensitivity;

    return Column(
      children: [
        // Analog / D-pad toggle
        Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceVariant,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              _jsTab("🕹️ Analog", JoystickMode.analog),
              _jsTab("🎮 D-Pad", JoystickMode.dpad),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Sensitivity slider (per mode)
        Row(
          children: [
            const Text("Sensitivity", style: TextStyle(fontSize: 12)),
            Expanded(
              child: Slider(
                value: sensitivity,
                min: 0.2,
                max: 5.0,
                divisions: 24,
                label: sensitivity.toStringAsFixed(1),
                onChanged: (v) => setState(() {
                  if (_joystickMode == JoystickMode.analog) {
                    _analogSensitivity = v;
                  } else {
                    _dpadSensitivity = v;
                  }
                }),
              ),
            ),
            SizedBox(
              width: 28,
              child: Text(
                sensitivity.toStringAsFixed(1),
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ],
        ),

        Text(
          _joystickMode == JoystickMode.analog
              ? "Drag to move cursor"
              : "Hold buttons to move cursor",
          style: const TextStyle(color: Colors.grey, fontSize: 12),
        ),
        const SizedBox(height: 12),

        if (_joystickMode == JoystickMode.analog)
          JoystickPad(
            sensitivity: _analogSensitivity,
            onMove: (dx, dy) => widget.sendCommand("move:$dx,$dy"),
            onRelease: () {},
          ),
        if (_joystickMode == JoystickMode.dpad)
          DpadController(
            sensitivity: _dpadSensitivity,
            onMove: (dx, dy) => widget.sendCommand("move:$dx,$dy"),
            onRelease: () {},
          ),
      ],
    );
  }

  Widget _buildKeyboard() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Mobile / Desktop keyboard toggle
        Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceVariant,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              _kbTab("📱 Mobile", KeyboardMode.mobile),
              _kbTab("🖥️ Desktop", KeyboardMode.qwerty),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (_keyboardMode == KeyboardMode.mobile) _buildMobileInput(),
        if (_keyboardMode == KeyboardMode.qwerty)
          QwertyKeyboard(onKey: (cmd) => widget.sendCommand(cmd)),
      ],
    );
  }

  Widget _buildMobileInput() {
    return Column(
      children: [
        const Text(
          "Your phone keyboard — caps, backspace,\nenter, symbols all sent to laptop.",
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
            labelText: "Type here — sends to laptop",
            border: OutlineInputBorder(),
            hintText: "Tap and type anything...",
          ),
        ),
      ],
    );
  }

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
          _scrollAccum = 0;
        },
        onVerticalDragUpdate: (d) {
          _scrollAccum += d.localPosition.dy - _scrollStartY;
          _scrollStartY = d.localPosition.dy;
          if (_scrollAccum.abs() >= 20) {
            int ticks = (_scrollAccum / 20).truncate();
            widget.sendCommand("scroll:${-ticks}");
            _scrollAccum -= ticks * 20;
          }
        },
        child: const Center(
          child:
              Text("↕  Scroll pad  ↕", style: TextStyle(color: Colors.grey)),
        ),
      ),
    );
  }

  Widget _jsTab(String label, JoystickMode mode) {
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
          child: Text(
            label,
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

  Widget _kbTab(String label, KeyboardMode mode) {
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
          child: Text(
            label,
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

  Widget _mouseBtn(String label, VoidCallback onPress) {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        minimumSize: const Size(80, 80),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      onPressed: onPress,
      child: Text(label),
    );
  }
}
