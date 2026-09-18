import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';

/// Global audio handler untuk playback musik chat di foreground/background.
/// Diinisialisasi saat app start via [AudioService.init].
AudioPlayerService? gAudioService;

/// Handler media: memainkan antrean audio (dari riwayat chat) dengan
/// just_audio + kontrol sistem (notifikasi media, lock screen, headset).
///
/// Auto-next antar lagu ditangani native oleh `ConcatenatingAudioSource`
/// (player otomatis lanjut ke lagu berikutnya saat selesai).
class AudioPlayerService extends BaseAudioHandler with SeekHandler {
  final AudioPlayer _player = AudioPlayer();
  ConcatenatingAudioSource? _source;
  bool _initialized = false;

  AudioPlayerService() {
    _player.playbackEventStream.listen(_broadcastState);
    _player.positionStream.listen((p) {
      playbackState.add(playbackState.value.copyWith(updatePosition: p));
    });
  }

  MediaItem? _itemForIndex(int? index, List<MediaItem> queue) {
    if (index == null || index < 0 || index >= queue.length) return null;
    return queue[index];
  }

  void _broadcastState(PlaybackEvent event) {
    final playing = _player.playing;
    final processing = _audioProcessing(event.processingState);
    final current = _itemForIndex(event.currentIndex, queue.value);
    mediaItem.add(current);
    playbackState.add(
      PlaybackState(
        controls: [
          if (!playing && _initialized) ...[
            MediaControl.play,
          ] else ...[
            if (_initialized) MediaControl.pause,
          ],
          MediaControl.stop,
          MediaControl.skipToNext,
          MediaControl.skipToPrevious,
        ],
        systemActions: const {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
        },
        androidCompactActionIndices: const [0, 1],
        processingState: processing,
        playing: playing,
        updatePosition: event.updatePosition,
        bufferedPosition: event.bufferedPosition,
        queueIndex: event.currentIndex,
      ),
    );
  }

  AudioProcessingState _audioProcessing(ProcessingState state) {
    switch (state) {
      case ProcessingState.idle:
        return AudioProcessingState.idle;
      case ProcessingState.loading:
        return AudioProcessingState.loading;
      case ProcessingState.buffering:
        return AudioProcessingState.buffering;
      case ProcessingState.ready:
        return AudioProcessingState.ready;
      case ProcessingState.completed:
        return AudioProcessingState.completed;
    }
  }

  /// Set antrean dari riwayat chat lalu mainkan item pada [index].
  Future<void> loadQueue(List<MediaItem> items, {int index = 0}) async {
    await _player.stop();
    if (items.isEmpty) {
      _source = null;
      _initialized = false;
      queue.add(const []);
      mediaItem.add(null);
      return;
    }
    _source = ConcatenatingAudioSource(
      children: [for (final it in items) AudioSource.uri(Uri.parse(it.id))],
    );
    queue.add(items);
    _initialized = true;
    await _player.setAudioSource(
      _source!,
      initialIndex: index,
      initialPosition: Duration.zero,
    );
    playbackState.add(playbackState.value.copyWith(queueIndex: index));
  }

  /// Mainkan item queue pada index [i] (lanjut dari posisi nol).
  Future<void> playQueueIndex(int i) async {
    if (!_initialized) return;
    await _player.seek(Duration.zero, index: i);
    await _player.play();
  }

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> stop() async {
    await _player.stop();
    await super.stop();
  }

  @override
  Future<void> skipToQueueItem(int index) async {
    if (!_initialized) return;
    if (_player.playing) {
      await _player.seek(Duration.zero, index: index);
    } else {
      await playQueueIndex(index);
    }
  }

  @override
  Future<void> skipToNext() async {
    if (!_initialized) return;
    await _player.seekToNext();
  }

  @override
  Future<void> skipToPrevious() async {
    if (!_initialized) return;
    if (_player.position > const Duration(seconds: 3)) {
      await _player.seek(Duration.zero);
    } else {
      await _player.seekToPrevious();
    }
  }

  @override
  Future<void> addQueueItem(MediaItem mediaItem) async {
    final list = [...queue.value, mediaItem];
    queue.add(list);
    await _source?.add(AudioSource.uri(Uri.parse(mediaItem.id), tag: mediaItem));
  }

  @override
  Future<void> removeQueueItem(MediaItem mediaItem) async {
    final index = queue.value.indexOf(mediaItem);
    if (index < 0) return;
    final list = [...queue.value]..removeAt(index);
    queue.add(list);
    await _source?.removeAt(index);
  }

  Future<void> clearQueue() async {
    await _player.stop();
    _initialized = false;
    _source?.clear();
    _source = null;
    queue.add(const []);
    mediaItem.add(null);
  }
}