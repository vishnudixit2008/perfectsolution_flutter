import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';

class CallAlertAudioService {
  static final CallAlertAudioService instance = CallAlertAudioService._internal();
  CallAlertAudioService._internal();

  AudioPlayer? _player;
  bool _isPlaying = false;

  bool get isPlaying => _isPlaying;

  /// Plays the soothing alert chime in a loop until stopped
  Future<void> playSoothingAlertLoop() async {
    try {
      if (_isPlaying) return;
      _player ??= AudioPlayer();
      _isPlaying = true;

      await _player!.setLoopMode(LoopMode.one);
      await _player!.setVolume(1.0);
      await _player!.setAsset('assets/sounds/soothing_alert.wav');
      await _player!.play();
      debugPrint('CallAlertAudioService: Playing soothing alert chime in loop');
    } catch (e) {
      debugPrint('CallAlertAudioService: Error playing alert sound: $e');
    }
  }

  /// Plays the soothing chime once
  Future<void> playSoothingAlertOnce() async {
    try {
      _player ??= AudioPlayer();
      await _player!.setLoopMode(LoopMode.off);
      await _player!.setVolume(1.0);
      await _player!.setAsset('assets/sounds/soothing_alert.wav');
      await _player!.play();
      debugPrint('CallAlertAudioService: Playing single soothing chime');
    } catch (e) {
      debugPrint('CallAlertAudioService: Error playing alert sound once: $e');
    }
  }

  /// Stops and releases the alert sound
  Future<void> stopAlert() async {
    try {
      _isPlaying = false;
      if (_player != null) {
        await _player!.stop();
        debugPrint('CallAlertAudioService: Alert sound stopped');
      }
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        try {
          const channel = MethodChannel('com.perfectsolution.kiosk/overlay');
          await channel.invokeMethod('stopNativeAlert');
        } catch (_) {}
      }
    } catch (e) {
      debugPrint('CallAlertAudioService: Error stopping alert sound: $e');
    }
  }

  void dispose() {
    _player?.dispose();
    _player = null;
    _isPlaying = false;
  }
}
