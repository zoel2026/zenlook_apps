import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/supabase_guard.dart';

/// Batas ukuran file audio (25 MB).
const int kMaxAudioBytes = 25 * 1024 * 1024;

/// Format file audio yang didukung untuk pesan musik.
const List<String> kAudioExtensions = ['mp3', 'm4a', 'aac', 'wav'];

/// Pemilihan file audio (MP3/M4A/AAC/WAV) untuk dikirim sebagai pesan
/// di chat. Upload ke bucket `audio-files` (public), kolom `is_audio`.
class AudioMessageService {
  /// Buka picker file audio dari perangkat.
  static Future<File?> pickFile() async {
    try {
      final res = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: kAudioExtensions,
      );
      final path = res.single.path;
      if (path == null) return null;
      return File(path);
    } catch (_) {
      return null;
    }
  }

  /// Validasi ekstensi dan ukuran file. Mengembalikan key i18n error,
  /// atau `null` jika valid.
  static String? validate(File file) {
    if (file.lengthSync() > kMaxAudioBytes) return 'audio_too_large';
    final ext = file.path.split('.').last.toLowerCase();
    if (!kAudioExtensions.contains(ext)) return 'audio_invalid_format';
    return null;
  }

  /// Durasi file audio lokal dalam detik (metadata pesan).
  static Future<double> fileDurationSeconds(String path) async {
    final p = AudioPlayer();
    try {
      await p.setSource(DeviceFileSource(path));
      final d = await p.getDuration();
      return (d?.inMilliseconds ?? 0) / 1000.0;
    } catch (_) {
      return 0;
    } finally {
      try {
        await p.dispose();
      } catch (_) {}
    }
  }

  /// Upload ke bucket `audio-files` di folder milik pengirim.
  /// Mengembalikan path di bucket untuk kolom `audio_url`.
  static Future<String?> upload(File file, {String? senderId}) async {
    final client = maybeClient();
    if (client == null) return null;
    try {
      final now = DateTime.now().toUtc().millisecondsSinceEpoch;
      final ext = file.path.split('.').last.toLowerCase();
      final name = file.path.split(RegExp(r'[/\\]')).last;
      final safe = name.replaceAll(RegExp(r'[^\w.\- ]'), '_');
      final path = '$senderId/${now}_$safe';
      await client.storage.from('audio-files').upload(
            path,
            file,
            fileOptions: FileOptions(contentType: _mime(ext)),
          );
      return path;
    } catch (_) {
      return null;
    }
  }

  /// URL publik dari path di bucket `audio-files`.
  static String publicUrl(String path) {
    final url = Supabase.instance.client.rest.url.replaceFirst('/rest/v1', '');
    return '$url/storage/v1/object/public/audio-files/$path';
  }

  static String _mime(String ext) {
    switch (ext) {
      case 'mp3':
        return 'audio/mpeg';
      case 'm4a':
        return 'audio/mp4';
      case 'aac':
        return 'audio/aac';
      case 'wav':
        return 'audio/wav';
      default:
        return 'application/octet-stream';
    }
  }
}