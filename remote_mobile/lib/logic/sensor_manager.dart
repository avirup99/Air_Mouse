import 'dart:async';
import 'package:sensors_plus/sensors_plus.dart';

class SensorManager {
  StreamSubscription? _gyroSubscription;
  double sensitivity = 3.0;

  // Smoothing — raised from 0.08 → 0.35 to cut lag significantly
  // while still removing jitter. Tune between 0.25–0.5 to taste.
  double _smoothDx = 0;
  double _smoothDy = 0;
  final double _filterFactor = 0.35;

  void start(Function(double dx, double dy) onMove) {
    _gyroSubscription = gyroscopeEvents.listen((GyroscopeEvent event) {
      // 1. Deadzone — ignore micro-tremors
      if (event.z.abs() < 0.015 && event.x.abs() < 0.015) return;

      // 2. Low-pass filter with less lag
      _smoothDx = (_smoothDx * (1 - _filterFactor)) + (event.z * _filterFactor);
      _smoothDy = (_smoothDy * (1 - _filterFactor)) + (event.x * _filterFactor);

      // 3. Compute delta and send immediately — no batching timer
      final dx = (_smoothDx * -100 * sensitivity).clamp(-150.0, 150.0);
      final dy = (_smoothDy * -100 * sensitivity).clamp(-150.0, 150.0);

      if (dx.abs() > 0.1 || dy.abs() > 0.1) {
        onMove(dx, dy);
      }
    });
  }

  void stop() {
    _gyroSubscription?.cancel();
    // No timer to cancel anymore
  }
}