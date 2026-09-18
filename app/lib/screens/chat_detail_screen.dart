import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/audio_message_service.dart';
import '../services/audio_player_service.dart';
import '../services/block_service.dart';
import '../services/listening_service.dart';
import '../services/locale_service.dart';
import '../services/push_service.dart';
import '../services/report_service.dart';
import '../services/theme_service.dart';
import '../services/typing_service.dart';
import '../services/voice_service.dart';
import '../utils/supabase_guard.dart';
import '../widgets/audio_message_bubble.dart';
import '../widgets/back_button_widget.dart';
import '../widgets/report_dialog.dart';
import '../widgets/user_avatar.dart';
import '../widgets/voice_message_bubble.dart';
import '../widgets/voice_recorder_button.dart';

class ChatDetailScreen extends StatefulWidget {
  const ChatDetailScreen({
    super.key,
    required this.peerId,
    required this.peerName,
    this.peerAvatar,
  });

  final String peerId;
  final String peerName;
  final String? peerAvatar;

  @override
  State<ChatDetailScreen> createState() => _ChatDetailScreenState();
}

class _ChatDetailScreenState extends State<ChatDetailScreen> {
  SupabaseClient get supabase => Supabase.instance.client;

  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final List<Map<String, dynamic>> _messages = [];
  bool _loading = true;
  bool _sending = false;
  bool _loadingMore = false;
  bool _hasMore = true;
  bool _peerTyping = false;
  bool _isBlocked = false;
  RealtimeChannel? _channel;
  RealtimeChannel? _typingChannel;
  TypingService? _typingService;
  ListeningService? _listening;
  StreamSubscription<PlaybackState>? _playbackSub;
  Timer? _peerTypingTimer;
  Timer? _peerListeningTimer;
  String? _peerListeningName;
  bool _recording = false;
  VoiceService? _voice;
  final Map<String, List<Map<String, dynamic>>> _reactions = {};

  static const int _pageSize = 40;

  String? get _uid => maybeClient()?.auth.currentUser?.id;

  @override
  void initState() {
    super.initState();
    PushService.activePeerId = widget.peerId;
    _scrollController.addListener(_onScroll);
    _load();
    _subscribe();
    _checkBlocked();
    _initTyping();
    _initListening();
  }

  Future<void> _initListening() async {
    final uid = _uid;
    if (uid == null) return;
    final service = ListeningService(peerId: widget.peerId, myId: uid)
      ..onPeerListening = _onPeerListening;
    _listening = service;
    await service.start();

    // Emit broadcast "sedang mendengarkan" saat audio message diputar.
    // PlaybackState + mediaItem global (audio_service) → mencakup tombol
    // bubble, kontrol notifikasi, dan auto-next.
    _playbackSub = gAudioService?.playbackState.listen((s) {
      final item = gAudioService?.mediaItem.value;
      final playing = s.playing == true && item != null;
      final name = item?.title ?? '';
      if (playing) {
        service.notifyListening(name);
      } else {
        service.notifyStopped();
      }
    });
  }

  void _onPeerListening(String? name) {
    _peerListeningTimer?.cancel();
    if (!mounted) return;
    setState(() => _peerListeningName = name != null && name.isNotEmpty
        ? name
        : context.l.t('music_mp3'));
    if (name != null) {
      // Fallback: hilang otomatis kalau event "stop" terlewat.
      _peerListeningTimer = Timer(const Duration(seconds: 8), () {
        if (!mounted) return;
        setState(() => _peerListeningName = null);
      });
    }
  }

  Future<void> _initTyping() async {
    final uid = _uid;
    if (uid == null) return;
    final service = TypingService(peerId: widget.peerId, myId: uid)
      ..onPeerTyping = _onPeerTyping;
    _typingService = service;
    await service.start();
  }

  void _onPeerTyping(bool typing) {
    _peerTypingTimer?.cancel();
    if (!mounted) return;
    setState(() => _peerTyping = typing);
    if (typing) {
      // Auto-hide kalau tidak ada update lagi selama 5 detik.
      _peerTypingTimer = Timer(const Duration(seconds: 5), () {
        if (!mounted) return;
        setState(() => _peerTyping = false);
      });
    }
  }

  Future<void> _checkBlocked() async {
    final uid = _uid;
    if (uid == null) return;
    final blocked = await BlockService.isBlocked(uid, widget.peerId);
    if (!mounted) return;
    setState(() => _isBlocked = blocked);
  }

  void _onInputChanged(String text) {
    final typing = _typingService;
    if (typing == null) return;
    if (text.trim().isEmpty) {
      typing.notifyStopped();
    } else {
      typing.notifyTyping();
    }
  }

  Future<bool> _startRecording() async {
    final v = _voice ??= VoiceService();
    if (!await v.hasPermission()) return false;
    if (!await v.start()) return false;
    if (!mounted) return false;
    setState(() => _recording = true);
    _typingService?.notifyStopped();
    return true;
  }

  Future<void> _endRecording() async {
    final v = _voice;
    if (!mounted || v == null || !_recording) return;
    setState(() => _recording = false);
    final file = await v.stop();
    if (file == null) return;
    final uid = _uid;
    final path = await v.upload(file, senderId: uid);
    if (path == null || !mounted) return;
    final duration = await VoiceService.fileDuration(file.path);
    try {
      final res = await supabase
          .from('messages')
          .insert({
            'sender_id': uid,
            'receiver_id': widget.peerId,
            'content': '',
            'is_voice': true,
            'voice_url': path,
            'voice_duration': duration,
          })
          .select(
              'id, sender_id, receiver_id, content, read_at, is_voice, voice_url, voice_duration, is_audio, audio_url, audio_name, audio_duration, created_at')
          .single();
      if (!mounted) return;
      setState(() => _messages.add(res));
      _scrollToBottom();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l.t('voice_send_fail'))),
      );
    }
  }

  Future<void> _cancelRecording() async {
    final v = _voice;
    if (!mounted || v == null || !_recording) return;
    setState(() => _recording = false);
    try {
      await v.stopAll();
    } catch (_) {}
  }

  Future<void> _sendAudio() async {
    final uid = _uid;
    if (uid == null || _sending) return;
    final file = await AudioMessageService.pickFile();
    if (file == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l.t('audio_pick_fail'))),
      );
      return;
    }
    final errorKey = AudioMessageService.validate(file);
    if (errorKey != null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l.t(errorKey))),
      );
      return;
    }
    setState(() => _sending = true);
    final path = await AudioMessageService.upload(file, senderId: uid);
    if (path == null || !mounted) {
      setState(() => _sending = false);
      return;
    }
    final duration = await AudioMessageService.fileDurationSeconds(file.path);
    try {
      final res = await supabase
          .from('messages')
          .insert({
            'sender_id': uid,
            'receiver_id': widget.peerId,
            'content': '',
            'is_audio': true,
            'audio_url': path,
            'audio_name': file.path.split(RegExp(r'[/\\]')).last,
            'audio_duration': duration,
          })
          .select(
              'id, sender_id, receiver_id, content, read_at, is_voice, voice_url, voice_duration, is_audio, audio_url, audio_name, audio_duration, created_at')
          .single();
      if (!mounted) return;
      setState(() {
        _messages.add(res);
        _sending = false;
      });
      _scrollToBottom();
    } catch (_) {
      if (!mounted) return;
      setState(() => _sending = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l.t('audio_send_fail'))),
      );
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    if (PushService.activePeerId == widget.peerId) {
      PushService.activePeerId = null;
    }
    _typingService?.notifyStopped();
    _typingService?.dispose();
    _peerTypingTimer?.cancel();
    _listening?.dispose();
    _playbackSub?.cancel();
    _peerListeningTimer?.cancel();
    _voice?.dispose();
    _channel?.unsubscribe();
    _typingChannel?.unsubscribe();
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // Saat user scroll ke paling atas, muat pesan yang lebih lama.
  void _onScroll() {
    if (!_scrollController.hasClients) return;
    if (_scrollController.position.pixels < 100) {
      _loadOlder();
    }
  }

  Future<void> _loadOlder() async {
    if (_loadingMore || !_hasMore || _messages.isEmpty) return;
    setState(() => _loadingMore = true);
    final oldestDate = _messages.first['created_at'] as String?;
    if (oldestDate == null) {
      setState(() => _loadingMore = false);
      return;
    }
    try {
      final uid = _uid;
      final older = await supabase
          .from('messages')
          .select(
              'id, sender_id, receiver_id, content, read_at, is_voice, voice_url, voice_duration, is_audio, audio_url, audio_name, audio_duration, created_at')
          .or(
              'and(sender_id.eq.$uid,receiver_id.eq.${widget.peerId}),'
              'and(sender_id.eq.${widget.peerId},receiver_id.eq.$uid)')
          .lt('created_at', oldestDate)
          .order('created_at', ascending: true)
          .limit(_pageSize);
      if (!mounted) return;
      final itemCount = older.length;
      setState(() {
        _messages.insertAll(0, older);
        _hasMore = itemCount == _pageSize;
        _loadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
    }
  }

  Future<void> _load() async {
    final uid = _uid;
    if (uid == null) {
      if (!mounted) return;
      setState(() => _loading = false);
      return;
    }
    try {
      final res = await supabase
          .from('messages')
          .select(
              'id, sender_id, receiver_id, content, read_at, is_voice, voice_url, voice_duration, is_audio, audio_url, audio_name, audio_duration, created_at')
          .or(
              'and(sender_id.eq.$uid,receiver_id.eq.${widget.peerId}),'
              'and(sender_id.eq.${widget.peerId},receiver_id.eq.$uid)')
          .order('created_at', ascending: false)
          .limit(_pageSize);
      if (!mounted) return;
      setState(() {
        _messages
          ..clear()
          ..addAll(res.whereType<Map<String, dynamic>>().toList().reversed);
        _hasMore = res.length == _pageSize;
        _loading = false;
      });
      _loadReactions();
      _markAsRead();
      _scrollToBottom(force: true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _markAsRead() async {
    final uid = _uid;
    if (uid == null) return;
    try {
      await supabase
          .from('messages')
          .update({'read_at': DateTime.now().toUtc().toIso8601String()})
          .eq('receiver_id', uid)
          .eq('sender_id', widget.peerId)
          .isFilter('read_at', null);
    } catch (_) {}
  }

  Future<void> _loadReactions() async {
    final uid = _uid;
    if (uid == null) return;
    if (_messages.isEmpty) return;
    try {
      final ids = _messages.map((m) => m['id'] as String).toList();
      final res = await supabase
          .from('message_reactions')
          .select('id, message_id, user_id, emoji, created_at')
          .inFilter('message_id', ids);
      if (!mounted) return;
      setState(() {
        _reactions.clear();
        for (final r in res) {
          final mid = r['message_id'] as String;
          _reactions.putIfAbsent(mid, () => []).add(
                Map<String, dynamic>.from(r),
              );
        }
      });
    } catch (_) {}
  }

  Future<void> _toggleReaction(String messageId, String emoji) async {
    final uid = _uid;
    if (uid == null) return;
    try {
      final existing = await supabase
          .from('message_reactions')
          .select('id, emoji')
          .eq('message_id', messageId)
          .eq('user_id', uid)
          .maybeSingle();
      if (existing == null) {
        await supabase.from('message_reactions').insert({
          'message_id': messageId,
          'user_id': uid,
          'emoji': emoji,
        });
      } else if (existing['emoji'] == emoji) {
        await supabase
            .from('message_reactions')
            .delete()
            .eq('message_id', messageId)
            .eq('user_id', uid);
      } else {
        await supabase
            .from('message_reactions')
            .update({'emoji': emoji})
            .eq('message_id', messageId)
            .eq('user_id', uid);
      }
    } catch (_) {}
  }

  Future<void> _askBlock() async {
    final uid = _uid;
    if (uid == null) return;
    final l = context.l;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text(l.t('block_confirm_title', args: [widget.peerName])),
        content: Text(l.t('block_confirm_body')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: Text(l.t('cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            child: Text(l.t('block_user')),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await BlockService.blockUser(uid, widget.peerId);
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l.t('block_success'))),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l.t('block_failed'))),
      );
    }
  }

  Future<void> _askUnblock() async {
    final uid = _uid;
    if (uid == null) return;
    try {
      await BlockService.unblockUser(uid, widget.peerId);
      if (!mounted) return;
      setState(() => _isBlocked = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l.t('unblock_success'))),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l.t('unblock_failed'))),
      );
    }
  }

  Future<void> _askReport() async {
    final uid = _uid;
    if (uid == null) return;
    final already = await ReportService.hasReportedToday(uid, widget.peerId);
    if (!mounted) return;
    if (already) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l.t('report_already'))),
      );
      return;
    }
    final reason = await showReportDialogWithReasons(
      context,
      peerName: widget.peerName,
    );
    if (reason == null || reason.isEmpty || !mounted) return;
    try {
      await ReportService.reportUser(uid, widget.peerId, reason);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l.t('report_success'))),
      );
    } on PostgrestException catch (e) {
      if (!mounted) return;
      // Insert ditolak trigger 24h → tampilkan pesan "sudah lapor".
      final already =
          e.message.toLowerCase().contains('sudah melaporkan');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            already
                ? context.l.t('report_already')
                : context.l.t('report_failed'),
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l.t('report_failed'))),
      );
    }
  }

  void _subscribe() {
    _channel = supabase.channel('chat_${_uid}_${widget.peerId}')
      ..onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'messages',
        callback: (payload) {
          final rec = Map<String, dynamic>.from(payload.newRecord);

          // UPDATE: read receipt / perubahan baris yang sudah tampil.
          if (payload.eventType == PostgresChangeEvent.update) {
            final idx =
                _messages.indexWhere((m) => m['id'] == rec['id']);
            if (idx != -1 && mounted) {
              setState(() => _messages[idx] = rec);
            }
            return;
          }
          if (payload.eventType == PostgresChangeEvent.delete) return;

          final senderId = rec['sender_id'] as String?;
          final receiverId = rec['receiver_id'] as String?;
          final uid = _uid;
          if (senderId != uid && senderId != widget.peerId) return;
          if (receiverId != uid && receiverId != widget.peerId) return;
          if (_messages.any((m) => m['id'] == rec['id'])) return;
          if (!mounted) return;
          setState(() => _messages.add(rec));
          if (rec['sender_id'] != _uid) _markAsRead();
          _scrollToBottom();
        },
      )
      ..onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'message_reactions',
        callback: _handleReactionChange,
      )
      ..subscribe();
  }

  void _handleReactionChange(PostgresChangePayload payload) {
    switch (payload.eventType) {
      case PostgresChangeEvent.insert:
      case PostgresChangeEvent.update:
        final rec = Map<String, dynamic>.from(payload.newRecord);
        final mid = rec['message_id'] as String?;
        if (mid == null || !mounted) return;
        setState(() {
          final list = _reactions.putIfAbsent(mid, () => []);
          list.removeWhere((r) => r['user_id'] == rec['user_id']);
          list.add(rec);
        });
      case PostgresChangeEvent.delete:
        final old = Map<String, dynamic>.from(payload.oldRecord);
        final mid = old['message_id'] as String?;
        if (mid == null || !mounted) return;
        setState(() {
          _reactions[mid]?.removeWhere((r) => r['user_id'] == old['user_id']);
        });
      default:
        break;
    }
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending || _uid == null) return;
    setState(() => _sending = true);
    _typingService?.notifyStopped();
    try {
      final res = await supabase
          .from('messages')
          .insert({
            'sender_id': _uid,
            'receiver_id': widget.peerId,
            'content': text,
          })
          .select(
              'id, sender_id, receiver_id, content, read_at, is_voice, voice_url, voice_duration, is_audio, audio_url, audio_name, audio_duration, created_at')
          .single();
      _controller.clear();
      if (!mounted) return;
      setState(() {
        _messages.add(res);
        _sending = false;
      });
      _scrollToBottom(force: true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _sending = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l.t('send_failed_msg'))),
      );
    }
  }

  void _scrollToBottom({bool force = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      final position = _scrollController.position;
      final nearBottom =
          position.maxScrollExtent - position.pixels < 200;
      // Jangan ganggu user yang sedang membaca riwayat chat.
      if (!force && !nearBottom) return;
      _scrollController.animateTo(
        position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  String _time(dynamic ts) {
    try {
      return DateFormat('HH:mm')
          .format(DateTime.parse(ts as String).toLocal());
    } catch (_) {
      return '';
    }
  }

  bool _isMine(Map<String, dynamic> m) => m['sender_id'] == _uid;

  static const _emojis = ['👍', '❤️', '😂', '😮', '😢', '🙏'];

  Future<void> _showReactionPicker(Map<String, dynamic> m) async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerHigh,
      builder: (sheetCtx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              for (final e in _emojis)
                GestureDetector(
                  onTap: () => Navigator.of(sheetCtx).pop(e),
                  child: Text(e, style: const TextStyle(fontSize: 28)),
                ),
            ],
          ),
        ),
      ),
    );
    if (picked == null || !mounted) return;
    await _toggleReaction(m['id'] as String, picked);
  }

  Widget _reactionChips(Map<String, dynamic> m) {
    final list = _reactions[m['id']];
    if (list == null || list.isEmpty) return const SizedBox.shrink();
    final grouped = <String, int>{};
    for (final r in list) {
      grouped[r['emoji'] as String] = (grouped[r['emoji']] ?? 0) + 1;
    }
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        for (final e in grouped.entries)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0xFF3D5AFE).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '${e.key} ${e.value}',
              style: const TextStyle(fontSize: 12),
            ),
          ),
      ],
    );
  }

  Widget _audioPlaceholder(Map<String, dynamic> m) {
    final seconds = (m['audio_duration'] as num?)?.toDouble() ?? 0;
    final name = m['audio_name'] as String?;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.music_note, color: Colors.white, size: 18),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            name?.isNotEmpty == true ? name! : context.l.t('audio_message'),
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white, fontSize: 14),
          ),
        ),
        if (seconds > 0) ...[
          const SizedBox(width: 6),
          Text(
            _fmtDuration(seconds),
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.5),
              fontSize: 11,
            ),
          ),
        ],
      ],
    );
  }

  String _fmtDuration(double seconds) {
    final s = seconds.round();
    final m = s ~/ 60;
    final r = s % 60;
    return '$m:${r.toString().padLeft(2, '0')}';
  }

  /// Antrean seluruh audio message dari riwayat chat (urutan lama → baru).
  List<MediaItem> _audioQueue() {
    final items = <MediaItem>[];
    for (final m in _messages) {
      final isAudio = (m['is_audio'] ?? false) as bool;
      final url = m['audio_url'] as String?;
      if (!isAudio || url == null || url.isEmpty) continue;
      items.add(
        MediaItem(
          id: AudioMessageService.publicUrl(url),
          title: m['audio_name'] as String? ?? context.l.t('audio_message'),
          duration:
              Duration(seconds: (m['audio_duration'] as num?)?.round() ?? 0),
        ),
      );
    }
    return items;
  }

  Widget _audioBubble(Map<String, dynamic> m) {
    final url = m['audio_url'] as String? ?? '';
    final queue = _audioQueue();
    final publicUrl = url.isEmpty ? '' : AudioMessageService.publicUrl(url);
    final idx = queue.indexWhere((it) => it.id == publicUrl);
    if (idx < 0) return _audioPlaceholder(m);
    return AudioMessageBubble(
      queue: queue,
      index: idx,
      name: m['audio_name'] as String? ?? context.l.t('audio_message'),
      duration: (m['audio_duration'] as num?)?.toDouble(),
      mine: _isMine(m),
      onPlayStart: () => _voice?.stopAll(),
    );
  }

  Widget _bubble(Map<String, dynamic> m) {
    final mine = _isMine(m);
    final read = m['read_at'] != null;
    final isVoice = (m['is_voice'] ?? false) as bool;
    final isAudio = (m['is_audio'] ?? false) as bool;
    return Column(
      crossAxisAlignment:
          mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onLongPress: () => _showReactionPicker(m),
          child: Align(
            alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              padding: EdgeInsets.all(isVoice || isAudio ? 6 : 14),
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.75,
              ),
              decoration: BoxDecoration(
                color: mine ? const Color(0xFF3D5AFE) : const Color(0xFF262E40),
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(mine ? 16 : 4),
                  bottomRight: Radius.circular(mine ? 4 : 16),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isVoice)
                    VoiceMessageBubble(
                      voiceUrl: VoiceService.publicUrl(
                        m['voice_url'] as String,
                      ),
                      duration: (m['voice_duration'] as num?)?.toDouble(),
                      mine: mine,
                      onPlayStart: () => gAudioService?.pause(),
                    )
                  else if (isAudio)
                    _audioBubble(m)
                  else
                    Text(
                      m['content'] as String,
                      style: const TextStyle(color: Colors.white, fontSize: 15),
                    ),
                  const SizedBox(height: 2),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _time(m['created_at']),
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.5),
                          fontSize: 10,
                        ),
                      ),
                      if (mine) ...[
                        const SizedBox(width: 3),
                        Icon(
                          read ? Icons.done_all : Icons.done,
                          size: 14,
                          color: read
                              ? const Color(0xFF81D4FA)
                              : Colors.white.withValues(alpha: 0.5),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: _reactionChips(m),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: const BackButtonWidget(),
        automaticallyImplyLeading: false,
        title: Row(
          children: [
            UserAvatar(
              name: widget.peerName,
              avatarUrl: widget.peerAvatar,
              radius: 16,
              backgroundColor: const Color(0xFF7C4DFF),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Text(widget.peerName, overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
        backgroundColor: Colors.transparent,
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) {
              switch (v) {
                case 'block':
                  if (_isBlocked) {
                    _askUnblock();
                  } else {
                    _askBlock();
                  }
                case 'report':
                  _askReport();
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'block',
                child: Row(
                  children: [
                    Icon(
                      _isBlocked ? Icons.lock_open : Icons.block,
                      size: 18,
                      color: Colors.redAccent,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _isBlocked
                          ? context.l.t('unblock_user')
                          : context.l.t('block_user'),
                    ),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              PopupMenuItem(
                value: 'report',
                child: Row(
                  children: [
                    const Icon(
                      Icons.flag_outlined,
                      size: 18,
                      color: Colors.redAccent,
                    ),
                    const SizedBox(width: 8),
                    Text(context.l.t('report_user')),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _loading
                ? const Center(
                    child:
                        CircularProgressIndicator(color: Color(0xFF3D5AFE)),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount:
                        _messages.length + (_loadingMore ? 1 : 0),
                    itemBuilder: (_, i) {
                      if (i >= _messages.length) {
                        return const Padding(
                          padding: EdgeInsets.all(12),
                          child: Center(
                            child: SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: Color(0xFF3D5AFE),
                              ),
                            ),
                          ),
                        );
                      }
                      return _bubble(_messages[i]);
                    },
                  ),
          ),
          SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_peerTyping)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: context.accentColor,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '${widget.peerName} ${context.l.t('chat_typing')}',
                          style: TextStyle(
                            color: context.textFaded(0.5),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                if (_peerListeningName != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        Icon(
                          Icons.music_note,
                          size: 14,
                          color: const Color(0xFF7C4DFF),
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            '${widget.peerName} ${context.l.t('chat_listening_music', args: [_peerListeningName!])}',
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: context.textFaded(0.5),
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (_isBlocked)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    color: Colors.redAccent.withValues(alpha: 0.15),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.block,
                          color: Colors.redAccent,
                          size: 16,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _isBlocked
                                ? '${context.l.t('block_success')} · ${context.l.t('unblock_user')}'
                                : context.l.t('blocked_list'),
                            style: const TextStyle(
                              color: Colors.redAccent,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _controller,
                          style: TextStyle(color: context.textPrimary),
                          minLines: 1,
                          maxLines: 4,
                          textInputAction: TextInputAction.send,
                          onChanged: _onInputChanged,
                          onSubmitted: (_) => _send(),
                          decoration: InputDecoration(
                            hintText: context.l.t('message_hint'),
                            hintStyle:
                                TextStyle(color: context.textFaded(0.4)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        onPressed: _sending ? null : _sendAudio,
                        tooltip: context.l.t('audio_message'),
                        icon: const Icon(Icons.attach_file),
                      ),
                      const SizedBox(width: 8),
                      VoiceRecorderButton(
                        recording: _recording,
                        onRecordStart: _startRecording,
                        onRecordEnd: _endRecording,
                        onRecordCancel: _cancelRecording,
                      ),
                      const SizedBox(width: 8),
                      IconButton.filled(
                        onPressed: _sending ? null : _send,
                        icon: const Icon(Icons.send),
                        style: IconButton.styleFrom(
                          backgroundColor: const Color(0xFF3D5AFE),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}