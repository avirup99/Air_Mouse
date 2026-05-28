import 'dart:async';
import 'package:flutter/material.dart';

class DpadController extends StatefulWidget {
  final Function(double dx, double dy) onMove;
  final VoidCallback onRelease;
  final double sensitivity; // 0.2 – 5.0, default 1.0

  const DpadController({
    super.key,
    required this.onMove,
    required this.onRelease,
    this.sensitivity = 1.0,
  });

  @override
  State<DpadController> createState() => _DpadControllerState();
}

class _DpadControllerState extends State<DpadController> {
  // Base speed at sensitivity = 1.0
  final double _baseSpeed = 18.0;

  double get _speed => _baseSpeed * widget.sensitivity;

  Timer? _moveTimer;

  bool _up = false, _down = false, _left = false, _right = false;

  bool get _anyHeld => _up || _down || _left || _right;

  void _startTimer() {
    if (_moveTimer != null) return;
    _moveTimer = Timer.periodic(const Duration(milliseconds: 16), (_) {
      if (!_anyHeld) return;
      double dx = 0, dy = 0;
      if (_left) dx -= _speed;
      if (_right) dx += _speed;
      if (_up) dy -= _speed;
      if (_down) dy += _speed;
      widget.onMove(dx, dy);
    });
  }

  void _stopTimer() {
    _moveTimer?.cancel();
    _moveTimer = null;
    widget.onRelease();
  }

  void _press(String dir) {
    setState(() {
      if (dir == 'up') _up = true;
      if (dir == 'down') _down = true;
      if (dir == 'left') _left = true;
      if (dir == 'right') _right = true;
    });
    _startTimer();
  }

  void _release(String dir) {
    setState(() {
      if (dir == 'up') _up = false;
      if (dir == 'down') _down = false;
      if (dir == 'left') _left = false;
      if (dir == 'right') _right = false;
    });
    if (!_anyHeld) _stopTimer();
  }

  @override
  void dispose() {
    _moveTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 200,
      height: 200,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned(top: 0, child: _dBtn('up', Icons.arrow_drop_up)),
          Positioned(bottom: 0, child: _dBtn('down', Icons.arrow_drop_down)),
          Positioned(left: 0, child: _dBtn('left', Icons.arrow_left)),
          Positioned(right: 0, child: _dBtn('right', Icons.arrow_right)),
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceVariant,
              shape: BoxShape.circle,
              border: Border.all(
                color:
                    Theme.of(context).colorScheme.outline.withOpacity(0.3),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dBtn(String dir, IconData icon) {
    final bool held = switch (dir) {
      'up' => _up,
      'down' => _down,
      'left' => _left,
      'right' => _right,
      _ => false,
    };

    return GestureDetector(
      onTapDown: (_) => _press(dir),
      onTapUp: (_) => _release(dir),
      onTapCancel: () => _release(dir),
      onPanEnd: (_) => _release(dir),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 60),
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          color: held
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.surfaceVariant,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: Theme.of(context).colorScheme.outline.withOpacity(0.4),
            width: 2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(held ? 0.05 : 0.2),
              blurRadius: held ? 1 : 4,
              offset: Offset(0, held ? 1 : 3),
            ),
          ],
        ),
        child: Icon(
          icon,
          size: 36,
          color: held
              ? Theme.of(context).colorScheme.onPrimary
              : Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}