import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/locale_service.dart';
import '../services/push_service.dart';
import '../services/theme_service.dart';
import '../utils/supabase_guard.dart';
import '../widgets/back_button_widget.dart';
import '../widgets/user_avatar.dart';
import 'chat_detail_screen.dart';

class ChatTab extends StatefulWidget {
  const ChatTab({
    super.key,
    this.onIncomingMessage,
  });

  final void Function(
    String peerId,
    String peerName,
    String content,
    String? peerAvatar,
  )? onIncomingMessage;

  @override
  State<ChatTab> createState() => ChatTabState();
}

class ChatTabState extends State<ChatTab> {
  SupabaseClient get supabase => Supabase.instance.client;

  final List<Map<String, dynamic>> _conversations = [];
  bool _loading = true;
  RealtimeChannel? _channel;
  final Map<String, String> _nameCache = {};
  final Map<String, String?> _avatarCache = {};

  String? get _uid => maybeClient()?.auth.currentUser?.id;

  @override
  void initState() {
    super.initState();
    _load();
    _subscribe();
  }

  @override
  void dispose() {
    _channel?.unsubscribe();
    super.dispose();
  }

  Future<void> reload() => _load();

  Future<void> _load() async {
    final uid = _uid;
    if (uid == null) {
      if (!mounted) return;
      setState(() => _loading = false);
      return;
    }
    try {
      final messages = await supabase
          .from('messages')
          .select(
              'id, sender_id, receiver_id, content, read_at, created_at, '
              'sender:profiles!messages_sender_id_fkey(username, full_name, avatar_url), '
              'receiver:profiles!messages_receiver_id_fkey(username, full_name, avatar_url)')
          .or('sender_id.eq.$uid,receiver_id.eq.$uid')
          .order('created_at', ascending: false)
          // Catatan: percakapan yang tidak menyentuh jendela ini
          // tidak akan muncul. Solusi proper: RPC di database.
          .limit(500);

      final convs = <String, Map<String, dynamic>>{};
      final unreadCounts = <String, int>{};
      for (final m in messages) {
        final senderId = m['sender_id'] as String;
        final receiverId = m['receiver_id'] as String;
        final peerId = senderId == _uid ? receiverId : senderId;
        if (!unreadCounts.containsKey(peerId)) {
          unreadCounts[peerId] = 0;
        }
        if (!convs.containsKey(peerId)) {
          final senderName = _nameOf(m['sender']);
          final receiverName = _nameOf(m['receiver']);
          convs[peerId] = {
            'peerId': peerId,
            'name': senderId == _uid ? receiverName : senderName,
            'avatar': senderId == _uid
                ? _avatarOf(m['receiver'])
                : _avatarOf(m['sender']),
            'content': m['content'] as String,
            'created_at': m['created_at'],
            'sentByMe': senderId == _uid,
          };
        }
        if (receiverId == _uid && m['read_at'] == null) {
          unreadCounts[peerId] = unreadCounts[peerId]! + 1;
        }
      }
      if (!mounted) return;
      setState(() {
        _conversations
          ..clear()
          ..addAll(convs.values);
        for (final c in _conversations) {
          c['unread'] = unreadCounts[c['peerId']] ?? 0;
        }
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  String _nameOf(dynamic profile) {
    if (profile is! Map) return 'Pengguna';
    return (profile['username'] ?? profile['full_name'] ?? 'Pengguna')
        as String;
  }

  String? _avatarOf(dynamic profile) {
    if (profile is! Map) return null;
    return (profile['avatar_url'] ?? '') as String;
  }

  void _subscribe() {
    try {
      _channel = supabase.channel('chat_tab')
        ..onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'messages',
          callback: (payload) {
            if (payload.eventType != PostgresChangeEvent.insert) return;
            final rec = Map<String, dynamic>.from(payload.newRecord);
            final uid = _uid;
            final senderId = rec['sender_id'] as String?;
            final receiverId = rec['receiver_id'] as String?;
            if (uid == null || (senderId != uid && receiverId != uid)) return;
            if (receiverId == uid &&
                senderId != uid &&
                PushService.activePeerId != senderId) {
              _notifyIncoming(senderId!, rec['content'] as String? ?? '');
            }
            _load();
          },
        )
        ..subscribe();
    } catch (_) {}
  }

  Future<void> _notifyIncoming(String senderId, String content) async {
    var name = _nameCache[senderId] ?? 'Teman';
    var avatar = _avatarCache[senderId];
    if (!_nameCache.containsKey(senderId)) {
      try {
        final p = await supabase
            .from('profiles')
            .select('username, full_name, avatar_url')
            .eq('id', senderId)
            .maybeSingle();
        if (p != null) {
          name = ((p['username'] ?? p['full_name'] ?? 'Teman') as String);
          avatar = p['avatar_url'] as String?;
        }
      } catch (_) {}
      _nameCache[senderId] = name;
      _avatarCache[senderId] = avatar;
    }
    await PushService.show(name, content);
    widget.onIncomingMessage?.call(senderId, name, content, avatar);
  }

  String _formatTime(dynamic ts) {
    try {
      final dt = DateTime.parse(ts as String).toLocal();
      final now = DateTime.now();
      if (dt.year == now.year &&
          dt.month == now.month &&
          dt.day == now.day) {
        return DateFormat('HH:mm').format(dt);
      }
      return DateFormat('dd/MM').format(dt);
    } catch (_) {
      return '';
    }
  }

  Future<void> _startNewChat() async {
    final uid = _uid;
    if (uid == null) return;
    try {
      final fs = await supabase
          .from('friendships')
          .select('user_id, friend_id')
          .eq('status', 'accepted')
          .or('user_id.eq.$uid,friend_id.eq.$uid');
      final ids = fs
          .map<String>((f) => f['user_id'] == uid
              ? f['friend_id'] as String
              : f['user_id'] as String)
          .toSet()
          .toList();
      List<Map<String, dynamic>> friends = [];
      if (ids.isNotEmpty) {
        friends = await supabase
            .from('profiles')
            .select('id, username, full_name, avatar_url')
            .inFilter('id', ids);
      }
      if (!mounted) return;
      if (friends.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l.t('no_friend_chat'))),
        );
        return;
      }
      showModalBottomSheet(
        context: context,
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerHigh,
        builder: (sheetCtx) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  context.l.t('choose_friend'),
                  style: TextStyle(
                    color: context.textPrimary,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
              ...friends.map((p) {
                final name =
                    (p['username'] ?? p['full_name'] ?? 'Pengguna') as String;
                return ListTile(
                  leading: UserAvatar(
                    name: name,
                    avatarUrl: p['avatar_url'] as String?,
                  ),
                  title: Text(name,
                      style: TextStyle(color: context.textPrimary)),
                  onTap: () {
                    Navigator.of(sheetCtx).pop();
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => ChatDetailScreen(
                          peerId: p['id'] as String,
                          peerName: name,
                          peerAvatar: p['avatar_url'] as String?,
                        ),
                      ),
                    );
                  },
                );
              }),
            ],
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l.t('load_friends_fail'))),
      );
    }
  }

  void _openChat(Map<String, dynamic> conv) {
    final chat = ChatDetailScreen(
      peerId: conv['peerId'] as String,
      peerName: conv['name'] as String,
      peerAvatar: conv['avatar'] as String?,
    );
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => chat))
        .then((_) {
      if (mounted) _load();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: const BackButtonWidget(icon: Icons.menu),
        automaticallyImplyLeading: false,
        centerTitle: false,
        title: Text(context.l.t('chat'),),
        backgroundColor: Colors.transparent,
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _startNewChat,
        backgroundColor: const Color(0xFF3D5AFE),
        tooltip: context.l.t('start_chat'),
        child: const Icon(Icons.add_comment),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF3D5AFE)),
            )
: _conversations.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.chat_bubble_outline,
                        size: 64,
                        color: context.textFaded(0.3),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        context.l.t('chat_no_conversation'),
                        style: TextStyle(
                          color: context.textFaded(0.5),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        context.l.t('chat_hint'),
                        style: TextStyle(
                          color: context.textFaded(0.3),
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    itemCount: _conversations.length,
                    separatorBuilder: (_, _) => const Divider(
                      height: 1,
                      color: Colors.white10,
                    ),
                    itemBuilder: (context, i) {
                      final c = _conversations[i];
                      final name = c['name'] as String;
                      final content = c['content'] as String;
                      final unread = (c['unread'] ?? 0) as int;
                      final sentByMe = c['sentByMe'] as bool;
                      return ListTile(
                        onTap: () => _openChat(c),
                        leading: UserAvatar(
                          name: name,
                          avatarUrl: c['avatar'] as String?,
                          backgroundColor: const Color(0xFF7C4DFF),
                        ),
title: Text(
                          name,
                          style: TextStyle(
                            color: context.textPrimary,
                            fontWeight:
                                unread > 0 ? FontWeight.bold : FontWeight.w600,
                          ),
                        ),
                        subtitle: Text(
                          '${sentByMe ? '${context.l.t('you')}: ' : ''}$content',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: context.textFaded(0.5),
                          ),
                        ),
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              _formatTime(c['created_at']),
                              style: TextStyle(
                                color: context.textFaded(0.4),
                                fontSize: 12,
                              ),
                            ),
                            if (unread > 0) ...[
                              const SizedBox(height: 4),
                              Container(
                                padding: const EdgeInsets.all(5),
                                decoration: const BoxDecoration(
                                  color: Color(0xFF3D5AFE),
                                  shape: BoxShape.circle,
                                ),
                                child: Text(
                                  '$unread',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}
