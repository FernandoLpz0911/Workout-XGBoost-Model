import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class RestTimer extends ChangeNotifier {
  int totalSeconds = 120;
  int _remaining = 0;
  Timer? _timer;

  bool get isRunning => _timer?.isActive ?? false;
  bool get isIdle => !isRunning && _remaining == 0;
  int get remaining => _remaining;
  double get progress =>
      totalSeconds > 0 ? _remaining / totalSeconds : 0.0;

  String get displayTime {
    final m = _remaining ~/ 60;
    final s = _remaining % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  void start() {
    _timer?.cancel();
    _remaining = totalSeconds;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_remaining > 0) {
        _remaining--;
        notifyListeners();
      } else {
        _timer?.cancel();
        _timer = null;
        HapticFeedback.heavyImpact();
        notifyListeners();
      }
    });
    notifyListeners();
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _remaining = 0;
    notifyListeners();
  }

  void adjustSeconds(int delta) {
    totalSeconds = (totalSeconds + delta).clamp(15, 600);
    if (isRunning) {
      _remaining = (_remaining + delta).clamp(0, totalSeconds);
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
