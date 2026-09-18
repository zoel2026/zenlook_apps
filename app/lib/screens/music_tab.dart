import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../services/audio_player_service.dart';
import '../services/locale_service.dart';
import '../services/music_library.dart';
import '../services/theme_service.dart';
import '../widgets/back_button_widget.dart';

/// Tab Musik: pilih MP3 dari penyimpanan handphone dan putar lewat player
/// global (audio_service) — background + notifikasi media + kontrol lock
/// screen. Listening status ke teman mengalir otomatis lewat
/// `gAudioService.playbackState` yang dipantau ChatDetailScreen.
class MusicTab extends StatefulWidget {
  const MusicTab({super.key});

  @override
  State<MusicTab> createState() => _MusicTabState();
}

class _MusicTabState extends State<MusicTab> {
  final List<MusicTrack> _tracks = [];
  StreamSubscription<PlaybackState>? _playbackSub;

  bool _playing = false;
  int? _playingIndex;

  @override
  void initState() {
    super.initState();
    _playbackSub = gAudioService?.playbackState.listen((s) {
      if (!mounted) return;
      setState(() {
        _playing = s.playing;
        _playingIndex = s.queueIndex;
      });
    });
  }

  @override
  void dispose() {
    _playbackSub?.cancel();
    super.dispose();
  }

  Future<void> _pickFiles() async {
    final res = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['mp3'],
    );
    if (res.isEmpty) return;
    final paths =
        res.map((f) => f.path ?? '').where((p) => p.isNotEmpty).toList();
    if (paths.isEmpty) return;
    final newTracks = tracksFromPaths(paths);
    if (!mounted) return;
    setState(() => _tracks.addAll(newTracks));
  }

  /// Putar lagu [index] (seluruh list jadi antrean concatenating).
  Future<void> _playAt(int index) async {
    if (_tracks.isEmpty) return;
    final service = gAudioService;
    if (service == null) return;
    final items = [
      for (final t in _tracks)
        MediaItem(id: t.uri, title: t.title, duration: Duration.zero),
    ];
    await service.loadQueue(items, index: index);
    await service.play();
  }

  Future<void> _togglePlay() async {
    final service = gAudioService;
    if (service == null) return;
    if (_playing) {
      await service.pause();
    } else {
      if (_playingIndex == null && _tracks.isNotEmpty) {
        await _playAt(0);
      } else {
        await service.play();
      }
    }
  }

  Future<void> _clear() async {
    await gAudioService?.clearQueue();
    if (!mounted) return;
    setState(() {
      _tracks.clear();
      _playing = false;
      _playingIndex = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: const BackButtonWidget(icon: Icons.menu),
        automaticallyImplyLeading: false,
        centerTitle: false,
        title: Text(context.l.t('music')),
        backgroundColor: Colors.transparent,
        actions: [
          if (_tracks.isNotEmpty)
            IconButton(
              tooltip: context.l.t('clear_queue'),
              onPressed: _clear,
              icon: const Icon(Icons.delete_sweep_outlined),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'add_music',
        onPressed: _pickFiles,
        backgroundColor: const Color(0xFF3D5AFE),
        tooltip: context.l.t('add_music'),
        child: const Icon(Icons.library_music),
      ),
      body: _tracks.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.music_note,
                    size: 64,
                    color: context.textFaded(0.3),
                  ),
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 40),
                    child: Text(
                      context.l.t('no_music'),
                      textAlign: TextAlign.center,
                      style: TextStyle(color: context.textFaded(0.5)),
                    ),
                  ),
                ],
              ),
            )
          : Column(
              children: [
                _nowPlaying(context),
                Expanded(
                  child: ListView.builder(
                    itemCount: _tracks.length,
                    itemBuilder: (context, i) {
                      final t = _tracks[i];
                      final active = i == _playingIndex;
                      return ListTile(
                        leading: Icon(
                          active
                              ? Icons.graphic_eq
                              : Icons.music_note_outlined,
                          color: active ? const Color(0xFF3D5AFE) : null,
                        ),
                        title: Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                        trailing: IconButton(
                          icon: Icon(
                            active && _playing
                                ? Icons.pause_circle
                                : Icons.play_circle,
                          ),
                          onPressed: () => _playAt(i),
                        ),
                        onTap: () => _playAt(i),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }

  Widget _nowPlaying(BuildContext context) {
    final current =
        (_playingIndex != null && _playingIndex! < _tracks.length)
            ? _tracks[_playingIndex!]
            : null;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF3D5AFE).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.l.t('now_playing'),
                  style: TextStyle(
                    color: context.textFaded(0.6),
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  current?.title ?? context.l.t('music_empty_queue'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          if (current != null) ...[
            IconButton(
              onPressed: () async => gAudioService?.skipToPrevious(),
              icon: const Icon(Icons.skip_previous),
            ),
            IconButton(
              onPressed: _togglePlay,
              icon: Icon(
                _playing ? Icons.pause : Icons.play_arrow,
                color: const Color(0xFF3D5AFE),
                size: 32,
              ),
            ),
            IconButton(
              onPressed: () async => gAudioService?.skipToNext(),
              icon: const Icon(Icons.skip_next),
            ),
          ],
        ],
      ),
    );
  }
}