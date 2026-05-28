import 'dart:async';
import 'package:flutter/material.dart';

class JoystickPad extends StatefulWidget {
  final Function(double dx, double dy) onMove;
  final VoidCallback onRelease;
  final double sensitivity; // 0.2 – 5.0, default 1.0

  const JoystickPad({
    super.key,
    required this.onMove,
    required this.onRelease,
    this.sensitivity = 1.0,
  });

  @override
  State<JoystickPad> createState() => _JoystickPadState();
}

class _JoystickPadState extends State<JoystickPad> {
  Offset _knobOffset = Offset.zero;
  bool _active = false;
  Timer? _moveTimer;

  // Max radius the knob can travel from center
  final double _maxRadius = 60.0;
  // Base speed at sensitivity = 1.0
  final double _baseSpeed = 18.0;

  double get _maxSpeed => _baseSpeed * widget.sensitivity;

  void _onPanStart(DragStartDetails d) {
    setState(() => _active = true);
    _startSending();
  }

  void _onPanUpdate(DragUpdateDetails d) {
    Offset raw = _knobOffset + d.delta;
    if (raw.distance > _maxRadius) {
      raw = raw / raw.distance * _maxRadius;
    }
    setState(() => _knobOffset = raw);
  }

  void _onPanEnd(DragEndDetails d) {
    _stopSending();
    setState(() {
      _knobOffset = Offset.zero;
      _active = false;
    });
    widget.onRelease();
  }

  void _startSending() {
    _moveTimer?.cancel();
    _moveTimer = Timer.periodic(const Duration(milliseconds: 16), (_) {
      if (_knobOffset.distance > 2.0) {
        final normalized = _knobOffset / _maxRadius;
        final dx = normalized.dx * _maxSpeed;
        final dy = normalized.dy * _maxSpeed;
        widget.onMove(dx, dy);
      }
    });
  }

  void _stopSending() {
    _moveTimer?.cancel();
    _moveTimer = null;
  }

  @override
  void dispose() {
    _stopSending();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const double padSize = 200.0;

    return GestureDetector(
      onPanStart: _onPanStart,
      onPanUpdate: _onPanUpdate,
      onPanEnd: _onPanEnd,
      child: Container(
        width: padSize,
        height: padSize,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: _active
              ? Theme.of(context).colorScheme.primaryContainer
              : Theme.of(context).colorScheme.surfaceVariant,
          border: Border.all(
            color: Theme.of(context).colorScheme.outline.withOpacity(0.4),
            width: 2,
          ),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Icon(Icons.add,
                size: 24,
                color:
                    Theme.of(context).colorScheme.outline.withOpacity(0.3)),
            Transform.translate(
              offset: _knobOffset,
              child: Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _active
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.secondary,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 6,
                      offset: const Offset(0, 3),
                    )
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}