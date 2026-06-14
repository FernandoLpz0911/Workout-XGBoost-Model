import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibration/vibration.dart';

/// Countdown rest timer with audio and vibration feedback.
///
/// Exposes [start], [stop], and [adjustSeconds] for UI control. Settings
/// ([soundEnabled], [vibrationEnabled], [autoStartEnabled], [volume]) are
/// toggled directly via setters and survive the widget lifecycle via
/// [ChangeNotifier].
///
/// The alert sound is synthesized at startup — no audio asset file is needed.
class RestTimer extends ChangeNotifier {
  /// Total duration of one rest interval in seconds.
  int totalSeconds = 120;

  int _remaining = 0;
  Timer? _timer;

  bool _soundEnabled = true;
  bool _vibrationEnabled = true;
  bool _autoStartEnabled = true;
  double _volume = 1.0;

  SharedPreferences? _prefs;

  final _player = AudioPlayer();

  RestTimer() {
    _loadSettings();
  }

  /// In-memory WAV bytes built once at construction — avoids bundling an asset.
  late final Uint8List _beepWav = _buildBeepWav();

  bool get isRunning => _timer?.isActive ?? false;

  /// True when the timer is not running and has not been started yet (or was stopped).
  bool get isIdle => !isRunning && _remaining == 0;

  /// Seconds remaining in the current countdown.
  int get remaining => _remaining;

  /// Fraction of [totalSeconds] remaining, used to drive a progress indicator.
  double get progress => totalSeconds > 0 ? _remaining / totalSeconds : 0.0;

  bool get soundEnabled => _soundEnabled;
  bool get vibrationEnabled => _vibrationEnabled;

  /// When true, the timer starts automatically after each logged set.
  bool get autoStartEnabled => _autoStartEnabled;
  double get volume => _volume;

  Future<void> _loadSettings() async {
    _prefs = await SharedPreferences.getInstance();
    totalSeconds = _prefs!.getInt('rest_timer_total_seconds') ?? 120;
    _soundEnabled = _prefs!.getBool('rest_timer_sound') ?? true;
    _vibrationEnabled = _prefs!.getBool('rest_timer_vibration') ?? true;
    _autoStartEnabled = _prefs!.getBool('rest_timer_auto_start') ?? true;
    _volume = _prefs!.getDouble('rest_timer_volume') ?? 1.0;
    notifyListeners();
  }

  void _saveSettings() async {
    final prefs = _prefs ??= await SharedPreferences.getInstance();
    await prefs.setInt('rest_timer_total_seconds', totalSeconds);
    await prefs.setBool('rest_timer_sound', _soundEnabled);
    await prefs.setBool('rest_timer_vibration', _vibrationEnabled);
    await prefs.setBool('rest_timer_auto_start', _autoStartEnabled);
    await prefs.setDouble('rest_timer_volume', _volume);
  }

  set soundEnabled(bool v) {
    _soundEnabled = v;
    _saveSettings();
    notifyListeners();
  }

  set vibrationEnabled(bool v) {
    _vibrationEnabled = v;
    _saveSettings();
    notifyListeners();
  }

  set autoStartEnabled(bool v) {
    _autoStartEnabled = v;
    _saveSettings();
    notifyListeners();
  }

  set volume(double v) {
    _volume = v;
    _player.setVolume(v);
    _saveSettings();
    notifyListeners();
  }

  /// Current countdown formatted as `M:SS`.
  String get displayTime {
    final m = _remaining ~/ 60;
    final s = _remaining % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  /// Starts (or restarts) the countdown from [totalSeconds].
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

  /// Cancels the countdown and resets [remaining] to zero.
  void stop() {
    _timer?.cancel();
    _timer = null;
    _remaining = 0;
    notifyListeners();
  }

  /// Adds [delta] seconds to [totalSeconds], clamped to 15–600 s.
  /// Also adjusts [remaining] if the timer is currently running.
  void adjustSeconds(int delta) {
    totalSeconds = (totalSeconds + delta).clamp(15, 600);
    if (isRunning) {
      _remaining = (_remaining + delta).clamp(0, totalSeconds);
    }
    _saveSettings();
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

/// Synthesizes a triple-beep WAV entirely in memory — no asset file needed.
///
/// Three 150 ms beeps at A5 (880 Hz) separated by 100 ms silence, with a
/// 10 ms fade-in/out envelope on each beep to prevent audio clicks.
Uint8List _buildBeepWav() {
  const sampleRate = 44100;
  const hz = 880.0; // A5 — classic timer tone
  const amplitude = 0.65;
  const beepMs = 150;
  const silenceMs = 100;
  const totalMs = beepMs * 3 + silenceMs * 2;

  final numSamples = sampleRate * totalMs ~/ 1000;
  final beepSamples = sampleRate * beepMs ~/ 1000;
  final silenceSamples = sampleRate * silenceMs ~/ 1000;

  final pcm = Int16List(numSamples);

  void fillBeep(int start, int count) {
    const fadeLen = 441; // 10 ms fade-in/out to avoid audio clicks
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
  buf.setUint16(20, 1, Endian.little); // AudioFormat: PCM
  buf.setUint16(22, 1, Endian.little); // NumChannels: Mono
  buf.setUint32(24, sampleRate, Endian.little);
  buf.setUint32(28, sampleRate * 2, Endian.little); // ByteRate
  buf.setUint16(32, 2, Endian.little); // BlockAlign
  buf.setUint16(34, 16, Endian.little); // BitsPerSample
  setStr(36, 'data');
  buf.setUint32(40, dataSize, Endian.little);

  final bytes = buf.buffer.asUint8List();
  bytes.setRange(44, 44 + dataSize, pcm.buffer.asUint8List());
  return bytes;
}
