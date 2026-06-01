import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:vibration/vibration.dart';

class RestTimer extends ChangeNotifier {
  int totalSeconds = 120;
  int _remaining = 0;
  Timer? _timer;

  bool _soundEnabled = true;
  bool _vibrationEnabled = true;
  bool _autoStartEnabled = true;
  double _volume = 1.0;

  final _player = AudioPlayer();
  late final Uint8List _beepWav = _buildBeepWav();

  bool get isRunning => _timer?.isActive ?? false;
  bool get isIdle => !isRunning && _remaining == 0;
  int get remaining => _remaining;
  double get progress => totalSeconds > 0 ? _remaining / totalSeconds : 0.0;

  bool get soundEnabled => _soundEnabled;
  bool get vibrationEnabled => _vibrationEnabled;
  bool get autoStartEnabled => _autoStartEnabled;
  double get volume => _volume;

  set soundEnabled(bool v) {
    _soundEnabled = v;
    notifyListeners();
  }

  set vibrationEnabled(bool v) {
    _vibrationEnabled = v;
    notifyListeners();
  }

  set autoStartEnabled(bool v) {
    _autoStartEnabled = v;
    notifyListeners();
  }

  set volume(double v) {
    _volume = v;
    _player.setVolume(v);
    notifyListeners();
  }

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
        _onComplete();
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

  void _onComplete() {
    if (_vibrationEnabled) _vibrate();
    if (_soundEnabled) _playSound();
  }

  void _vibrate() async {
    try {
      if (await Vibration.hasVibrator() == true) {
        Vibration.vibrate(pattern: [0, 400, 100, 400, 100, 400]);
      }
    } catch (_) {}
  }

  void _playSound() async {
    try {
      await _player.setVolume(_volume);
      await _player.play(BytesSource(_beepWav));
    } catch (_) {}
  }

  @override
  void dispose() {
    _timer?.cancel();
    _player.dispose();
    super.dispose();
  }
}

// Generates a triple-beep WAV entirely in memory — no asset file needed.
Uint8List _buildBeepWav() {
  const sampleRate = 44100;
  const hz = 880.0; // A5 — classic timer tone
  const amplitude = 0.65;
  const beepMs = 150;
  const silenceMs = 100;
  const totalMs = beepMs * 3 + silenceMs * 2; // 650 ms

  final numSamples = sampleRate * totalMs ~/ 1000;
  final beepSamples = sampleRate * beepMs ~/ 1000;
  final silenceSamples = sampleRate * silenceMs ~/ 1000;

  final pcm = Int16List(numSamples);

  void fillBeep(int start, int count) {
    const fadeLen = 441; // 10 ms fade-in/out to avoid clicks
    for (int i = 0; i < count && start + i < numSamples; i++) {
      final t = i / sampleRate;
      final env = i < fadeLen
          ? i / fadeLen.toDouble()
          : i > count - fadeLen
              ? (count - i) / fadeLen.toDouble()
              : 1.0;
      final v = (sin(2 * pi * hz * t) * amplitude * env * 32767).round();
      pcm[start + i] = v.clamp(-32768, 32767);
    }
  }

  fillBeep(0, beepSamples);
  fillBeep(beepSamples + silenceSamples, beepSamples);
  fillBeep(beepSamples * 2 + silenceSamples * 2, beepSamples);

  final dataSize = numSamples * 2; // 16-bit = 2 bytes/sample
  final buf = ByteData(44 + dataSize);

  void setStr(int offset, String s) {
    for (int i = 0; i < s.length; i++) {
      buf.setUint8(offset + i, s.codeUnitAt(i));
    }
  }

  setStr(0, 'RIFF');
  buf.setUint32(4, 36 + dataSize, Endian.little);
  setStr(8, 'WAVE');
  setStr(12, 'fmt ');
  buf.setUint32(16, 16, Endian.little); // Subchunk1Size (PCM)
  buf.setUint16(20, 1, Endian.little);  // AudioFormat: PCM
  buf.setUint16(22, 1, Endian.little);  // NumChannels: Mono
  buf.setUint32(24, sampleRate, Endian.little);
  buf.setUint32(28, sampleRate * 2, Endian.little); // ByteRate
  buf.setUint16(32, 2, Endian.little);  // BlockAlign
  buf.setUint16(34, 16, Endian.little); // BitsPerSample
  setStr(36, 'data');
  buf.setUint32(40, dataSize, Endian.little);

  final bytes = buf.buffer.asUint8List();
  bytes.setRange(44, 44 + dataSize, pcm.buffer.asUint8List());
  return bytes;
}
