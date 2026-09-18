import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/supabase_guard.dart';

/// Perekam pesan suara + upload ke Supabase Storage.
/// Bucket: `voice-messages` (public).
class VoiceService {
  final AudioRecorder _recorder = AudioRecorder();
  final AudioPlayer _preview = AudioPlayer();
  String? _currentPath;
  bool _recording = false;

  VoiceService() {
    _preview.onPlayerComplete.listen((_) {});
  }

  bool get isRecording => _recording;

  /// Izin mikrofon.
  Future<bool> hasPermission() => _recorder.hasPermission();

  /// Mulai merekam ke file temporer.
  Future<bool> start() async {
    try {
      if (_recording) await stop();
      final dir = await getTemporaryDirectory();
      final now = DateTime.now().millisecondsSinceEpoch;
      _currentPath = '${dir.path}/voice_$now.m4a';
      await _recorder.start(
        const RecordConfig(encoder: AudioEncoder.aacLc),
        path: _currentPath!,
      );
      _recording = true;
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Stop rekam. Mengembalikan file audio (null jika terlalu pendek/gagal).
  Future<File?> stop() async {
    try {
      final r = await _recorder.stop();
      _recording = false;
      String? path = _currentPath;
      if (r != null) {
        final v = r as dynamic;
        final p = v is String ? v : v?.path as String?;
        if (p != null) path = p;
      }
      _currentPath = null;
      if (path == null) return null;
      final f = File(path);
      if (!f.existsSync() || f.lengthSync() == 0) return null;
      return f;
    } catch (_) {
      _currentPath = null;
      return null;
    }
  }

  /// Upload file ke Storage, kembalikan path di bucket (untuk disimpan
  /// ke kolom voice_url messages).
  Future<String?> upload(File file, {String? senderId}) async {
    final client = maybeClient();
    if (client == null) return null;
    try {
      final now = DateTime.now().toUtc();
      final p = now.millisecondsSinceEpoch;
      final path = 'uploads/${senderId ?? 'user'}_$p.m4a';
      await client.storage.from('voice-messages').upload(
            path,
            file,
            fileOptions: const FileOptions(contentType: 'audio/mp4'),
          );
      return path;
    } catch (_) {
      return null;
    }
  }

  /// URL publik dari path storage.
  static String publicUrl(String path) {
    final url = Supabase.instance.client.rest.url.replaceFirst('/rest/v1', '');
    return '$url/storage/v1/object/public/voice-messages/$path';
  }

  /// Mainkan / jeda audio. Return posisi dan durasi agar bisa di-render
  /// progress. Handler onAudit memakai stream dari player.
  Future<void> playUrl(String url) async {
    try {
      final state = _preview.state;
      if (state == PlayerState.playing) {
        await _preview.pause();
      } else {
        await _preview.play(UrlSource(url));
      }
    } catch (_) {}
  }

  Stream<Duration> get onPosition => _preview.onPositionChanged;
  Stream<Duration?> get onDuration => _preview.onDurationChanged;
  Stream<PlayerState> get onState => _preview.onPlayerStateChanged;

  Future<void> stopAll() async {
    try {
      await _preview.stop();
      if (_recording) await _recorder.cancel();
      _recording = false;
      _currentPath = null;
    } catch (_) {}
  }

  /// Durasi file audio lokal (untuk metadata pesan suara).
  static Future<double> fileDuration(String path) async {
    final p = AudioPlayer();
    try {
      await p.setSource(DeviceFileSource(path));
      final d = await p.getDuration();
      return d?.inMilliseconds.toDouble() ?? 0;
    } catch (_) {
      return 0;
    } finally {
      try {
        await p.dispose();
      } catch (_) {}
    }
  }

  Future<void> dispose() async {
    try {
      await _preview.dispose();
      await _recorder.dispose();
    } catch (_) {}
  }
}