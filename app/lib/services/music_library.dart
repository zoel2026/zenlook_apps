import 'dart:io';

/// Model immutable: satu track MP3 lokal untuk Music Tab.
class MusicTrack {
  const MusicTrack({required this.title, required this.uri});

  /// Judul tampil = nama file tanpa ekstensi.
  final String title;

  /// URI playable (file://...).
  final String uri;
}

/// Konversi path absolut menjadi file:// URI yang bisa diputar just_audio.
String fileUri(String path) => Uri.file(path).toString();

/// Bangun daftar antrean dari path MP3. Dedup path sama.
List<MusicTrack> tracksFromPaths(List<String> paths) {
  final seen = <String>{}; // path normal (case-sensitive lower) utk dedup
  final out = <MusicTrack>[];
  for (final p in paths) {
    final norm = p.replaceAll(RegExp(r'[\\/]'), '/').toLowerCase();
    if (!seen.add(norm)) continue;
    final base = File(p).uri.pathSegments.isEmpty
        ? p
        : File(p).uri.pathSegments.last;
    final ext = base.lastIndexOf('.');
    final title = ext > 0 ? base.substring(0, ext) : base;
    out.add(MusicTrack(title: title, uri: fileUri(p)));
  }
  return out;
}

/// Format durasi mm:ss (e.g. 754s -> "12:34").
String formatDuration(Duration d) {
  final s = d.inSeconds % 60;
  final m = d.inMinutes;
  return '$m:${s.toString().padLeft(2, '0')}';
}