import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/block_service.dart';
import '../services/locale_service.dart';
import '../services/location_visibility_service.dart';
import '../services/status_service.dart';
import '../services/theme_service.dart';
import '../services/wave_service.dart';
import '../utils/supabase_guard.dart';
import '../widgets/back_button_widget.dart';
import '../widgets/user_avatar.dart';
import 'chat_detail_screen.dart';

class FriendsTab extends StatefulWidget {
  const FriendsTab({super.key});

  @override
  State<FriendsTab> createState() => _FriendsTabState();
}

class _FriendsTabState extends State<FriendsTab> {
  SupabaseClient get supabase => Supabase.instance.client;
  final _searchController = TextEditingController();

  List<Map<String, dynamic>> _results = [];
  List<Map<String, dynamic>> _friendships = [];
  Map<String, Map<String, dynamic>> _profiles = {};
  bool _searching = false;
  bool _loading = true;
  String _sendingId = '';
  RealtimeChannel? _channel;
  Timer? _debounce;
  Set<String> _blocked = {};

  /// Teman yang lokasinya disembunyikan oleh pengguna ini.
  Set<String> _hiddenFrom = {};
  bool _updatingVisibility = false;

  String? get _uid => maybeClient()?.auth.currentUser?.id;

  @override
  void initState() {
    super.initState();
    _loadData();
    _subscribe();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _channel?.unsubscribe();
    _searchController.dispose();
    super.dispose();
  }

  void _subscribe() {
    try {
      _channel = supabase.channel('friends_tab')
        ..onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'friendships',
          callback: (payload) {
            if (payload.eventType == PostgresChangeEvent.delete) {
              _loadData();
              return;
            }
            final raw = payload.newRecord;
            final rec = Map<String, dynamic>.from(raw);
            final uid = _uid;
            if (uid == null) return;
            final involved = rec['user_id'] == uid || rec['friend_id'] == uid;
            if (!involved) return;
            _loadData();
          },
        )
        ..subscribe();
    } catch (_) {}
  }

  Future<void> _loadData({bool showSpinner = false}) async {
    if (showSpinner && mounted) setState(() => _loading = true);
    try {
      final uid = _uid;
      if (uid == null) {
        if (!mounted) return;
        setState(() => _loading = false);
        return;
      }
      final fs = await supabase
          .from('friendships')
          .select('id, user_id, friend_id, status')
          .or('user_id.eq.$uid,friend_id.eq.$uid');
      if (!mounted) return;

      final ids = <String>{};
      for (final f in fs) {
        ids.add(f['user_id'] as String);
        ids.add(f['friend_id'] as String);
      }
      ids.remove(uid);
      final profiles = <String, Map<String, dynamic>>{};
      if (ids.isNotEmpty) {
        final res = await supabase
            .from('profiles')
            .select(
              'id, username, full_name, avatar_url, '
              'status_text, status_emoji, status_expires_at',
            )
            .inFilter('id', ids.toList());
        for (final p in res) {
          profiles[p['id'] as String] = p;
        }
      }
      if (!mounted) return;
      setState(() {
        _friendships =
            fs.whereType<Map<String, dynamic>>().toList();
        _profiles = profiles;
        _loading = false;
      });
      // Muat daftar blokir untuk filter tampilan.
      final blocked = await BlockService.getUsersWhoBlockedMe(uid);
      final mine = await BlockService.getMyBlockedUsers(uid)
          .then((list) => list.map((p) => p['id'] as String).toSet());
      if (!mounted) return;
      setState(() => _blocked = blocked.union(mine));

      // Daftar teman yang lokasinya disembunyikan.
      final hidden = await LocationVisibilityService.myHiddenPeerIds();
      if (!mounted) return;
      setState(() => _hiddenFrom = hidden);
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  /// Salin atau hentikan menyembunyikan lokasi ke [peerId].
  Future<void> _toggleVisibility(String peerId) async {
    if (_updatingVisibility) return;
    final currentlyHidden = _hiddenFrom.contains(peerId);
    final confirmed = await _confirmVisibility(peerId, !currentlyHidden);
    if (!confirmed || !mounted) return;

    setState(() => _updatingVisibility = true);
    final result = await LocationVisibilityService.setHidden(
      peerId: peerId,
      hidden: !currentlyHidden,
    );
    if (!mounted) return;
    setState(() {
      _updatingVisibility = false;
      if (result == VisibilityResult.ok) {
        if (currentlyHidden) {
          _hiddenFrom = {..._hiddenFrom}..remove(peerId);
        } else {
          _hiddenFrom = {..._hiddenFrom, peerId};
        }
      }
    });
    if (result == VisibilityResult.ok) return;
    final key = switch (result) {
      VisibilityResult.invalid => 'location_visibility_invalid',
      VisibilityResult.notAllowed => 'location_visibility_not_allowed',
      _ => 'location_visibility_failed',
    };
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l.t(key))),
    );
  }

  Future<bool> _confirmVisibility(String peerId, bool hide) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dlgCtx) => AlertDialog(
        title: Text(
          dlgCtx.l.t(
            hide ? 'hide_location' : 'show_location_to',
          ),
        ),
        content: Text(
          dlgCtx.l.t(
            hide ? 'hide_location_confirm' : 'show_location_confirm',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dlgCtx).pop(false),
            child: Text(dlgCtx.l.t('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dlgCtx).pop(true),
            child: Text(dlgCtx.l.t(hide ? 'delete_confirm_action' : 'save')),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  Future<void> _search(String query) async {
    final uid = _uid;
    if (uid == null) return;
    final q = query
        .trim()
        .replaceAll(RegExp(r'[,()"*\\]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ');
    if (q.isEmpty) {
      setState(() => _results = []);
      return;
    }
    setState(() => _searching = true);
    try {
      final res = await supabase
          .from('profiles')
          .select('id, username, full_name, avatar_url')
          .or('username.ilike.%$q%,full_name.ilike.%$q%')
          .neq('id', uid)
          .limit(20);
      if (!mounted) return;
      setState(() => _results = res
          .whereType<Map<String, dynamic>>()
          .where((p) => !_blocked.contains(p['id']))
          .toList());
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l.t('search_failed'))),
      );
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Map<String, dynamic>? _friendshipWith(String otherId) {
    for (final f in _friendships) {
      if (f['user_id'] == otherId || f['friend_id'] == otherId) return f;
    }
    return null;
  }

  bool _isIncoming(Map<String, dynamic> f) =>
      f['friend_id'] == _uid && f['status'] == 'pending';

  List<Map<String, dynamic>> get _incomingRequests => _friendships
      .where(_isIncoming)
      .where((f) {
        final other = f['user_id'] == _uid ? f['friend_id'] : f['user_id'];
        return !_blocked.contains(other);
      })
      .toList();

  List<Map<String, dynamic>> get _acceptedFriends => _friendships
      .where((f) => f['status'] == 'accepted')
      .where((f) {
        final other = f['user_id'] == _uid ? f['friend_id'] : f['user_id'];
        return !_blocked.contains(other);
      })
      .toList();

  Future<void> _sendRequest(Map<String, dynamic> profile) async {
    final uid = _uid;
    if (uid == null) return;
    final id = profile['id'] as String;
    setState(() => _sendingId = id);
    try {
      await supabase.from('friendships').insert({
        'user_id': uid,
        'friend_id': id,
        'status': 'pending',
      });
      if (!mounted) return;
      setState(() {
        _friendships.add({
          'id': '',
          'user_id': uid,
          'friend_id': id,
          'status': 'pending',
        });
        _profiles[id] = profile;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l.t('friendship_sent'))),
      );
    } on PostgrestException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l.t('send_failed'))),
      );
    } finally {
      if (mounted) setState(() => _sendingId = '');
    }
  }

  Future<void> _respond(Map<String, dynamic> f, bool accept) async {
    final uid = _uid;
    if (uid == null) return;
    try {
      if (accept) {
        await supabase
            .from('friendships')
            .update({'status': 'accepted'})
            .eq('id', f['id'])
            .eq('friend_id', uid);
      } else {
        await supabase
            .from('friendships')
            .delete()
            .eq('id', f['id'])
            .eq('friend_id', uid);
      }
      if (!mounted) return;
      setState(() => _friendships.removeWhere((x) => x['id'] == f['id']));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(accept ? context.l.t('accept_request') : context.l.t('reject_request'))),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l.t('process_failed'))),
      );
    }
  }

  /// Batalkan permintaan pertemanan yang keluar.
  Future<void> _cancelRequest(Map<String, dynamic> f) async {
    final uid = _uid;
    if (uid == null) return;
    try {
      await supabase
          .from('friendships')
          .delete()
          .eq('id', f['id'])
          .eq('user_id', uid);
      if (!mounted) return;
      setState(() => _friendships.removeWhere((x) => x['id'] == f['id']));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l.t('cancel_request'))),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l.t('cancel_failed'))),
      );
    }
  }

  /// Hapus teman (dengan konfirmasi).
  Future<void> _removeFriend(Map<String, dynamic> f, String name) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: const Color(0xFF1A2130),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          context.l.t('delete_friend_title', args: [name]),
          style: const TextStyle(color: Colors.white, fontSize: 18),
        ),
        content: Text(
          context.l.t('delete_friend_body'),
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: Text(context.l.t('cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.redAccent,
            ),
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            child: Text(context.l.t('delete')),
          ),
        ],
      ),
    );
    if (yes != true) return;
    try {
      await supabase.from('friendships').delete().eq('id', f['id']);
      if (!mounted) return;
      setState(() => _friendships.removeWhere((x) => x['id'] == f['id']));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.l.t('delete_friend_success', args: [name]),
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l.t('delete_friend_failed'))),
      );
    }
  }

  Widget _avatar(String name, String? avatarUrl, Color color) {
    return UserAvatar(
      name: name,
      avatarUrl: avatarUrl,
      radius: 20,
      backgroundColor: color,
    );
  }

  Future<void> _sendWave(String peerId) async {
    final uid = _uid;
    if (uid == null) return;
    final l = context.l;
    final result = await WaveService.sendWave(fromId: uid, toId: peerId);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l.t(waveMessageKey(result)))),
    );
  }

  void _openChat(String peerId, String peerName, String? avatarUrl) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatDetailScreen(
          peerId: peerId,
          peerName: peerName,
          peerAvatar: avatarUrl,
        ),
      ),
    );
  }

  /// Subtitle baris teman: status aktivitas kalau masih aktif, kalau tidak
  /// Display nada. Null kalau status kosong / sudah hangus.
  Widget? _statusSubtitle(Map<String, dynamic> p) {
    final line = statusLine(
      emoji: p['status_emoji'] as String?,
      text: p['status_text'] as String?,
      expiresAt: DateTime.tryParse((p['status_expires_at'] ?? '') as String),
      now: DateTime.now(),
    );
    if (line == null) return null;
    return Text(line, style: TextStyle(color: context.textFaded(0.6)));
  }

  Widget _resultTile(Map<String, dynamic> p) {
    final id = p['id'] as String;
    final name = (p['username'] ?? p['full_name'] ?? 'Pengguna') as String;
    final username = (p['username'] ?? '') as String;
    final rel = _friendshipWith(id);
    final sending = _sendingId == id;

    Widget? action;
    if (rel == null) {
      action = FilledButton.tonal(
        onPressed: sending ? null : () => _sendRequest(p),
        child: sending
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Text(context.l.t('add')),
      );
    } else if (rel['status'] == 'accepted') {
      action = Text(
        context.l.t('friend'),
        style: const TextStyle(color: Colors.greenAccent),
      );
    } else if (_isIncoming(rel)) {
      action = FilledButton(
        onPressed: () => _respond(rel, true),
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFF3D5AFE),
        ),
        child: Text(context.l.t('accept')),
      );
    } else if (rel['id'] != '') {
      // Permintaan keluar yang masih pending -> bisa dibatalkan.
      action = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            context.l.t('waiting'),
            style: const TextStyle(color: Colors.orangeAccent),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18, color: Colors.redAccent),
            tooltip: context.l.t('interrupted'),
            onPressed: () => _cancelRequest(rel),
          ),
        ],
      );
    } else {
      action = Text(
        context.l.t('waiting'),
        style: const TextStyle(color: Colors.orangeAccent),
      );
    }

    return ListTile(
      leading: _avatar(
        username.isNotEmpty ? username : name,
        p['avatar_url'] as String?,
        const Color(0xFF7C4DFF),
      ),
      title: Text(name,
          style: TextStyle(
              color: context.textPrimary, fontWeight: FontWeight.w600)),
      subtitle: username.isNotEmpty
          ? Text('@$username',
              style: TextStyle(color: context.textFaded(0.5)))
          : null,
      trailing: action,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: const BackButtonWidget(icon: Icons.menu),
        automaticallyImplyLeading: false,
        centerTitle: false,
        title: Text(context.l.t('friends')),
        backgroundColor: Colors.transparent,
      ),
      body: RefreshIndicator(
        onRefresh: _loadData,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextField(
              controller: _searchController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: context.l.t('search_friend'),
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          _debounce?.cancel();
                          _searchController.clear();
                          _search('');
                        },
                      ),
              ),
              onChanged: (q) {
                _debounce?.cancel();
                _debounce = Timer(const Duration(milliseconds: 400), () {
                  _search(q);
                });
              },
            ),
            if (_searching)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(
                  child: CircularProgressIndicator(color: Color(0xFF3D5AFE)),
                ),
              )
            else if (_searchController.text.trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              ..._results.map(_resultTile),
              if (_results.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Center(
                    child: Text(
                      context.l.t('no_result'),
                      style: TextStyle(color: context.textPrimary),
                    ),
                  ),
                ),
            ],
            const SizedBox(height: 24),
            if (_loading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: CircularProgressIndicator(color: Color(0xFF3D5AFE)),
                ),
              )
            else ...[
              if (_incomingRequests.isNotEmpty) ...[
                Text(
                  context.l.t('incoming_requests'),
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.6),
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 8),
                ..._incomingRequests.map((f) {
                  final p = _profiles[f['user_id']];
                  if (p == null) return const SizedBox.shrink();
                  final name =
                      (p['username'] ?? p['full_name'] ?? 'Pengguna') as String;
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: _avatar(
                      name,
                      p['avatar_url'] as String?,
                      const Color(0xFFFF7043),
                    ),
                    title: Text(name,
                        style: TextStyle(
                            color: context.textPrimary,
                            fontWeight: FontWeight.w600)),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.redAccent),
                          tooltip: context.l.t('reject'),
                          onPressed: () => _respond(f, false),
                        ),
                        IconButton(
                          icon: const Icon(Icons.check, color: Colors.greenAccent),
                          tooltip: context.l.t('accept'),
                          onPressed: () => _respond(f, true),
                        ),
                      ],
                    ),
                  );
                }),
                const SizedBox(height: 24),
              ],
              if (_acceptedFriends.isNotEmpty) ...[
                Text(
                  context.l.t('friend_list', args: [_acceptedFriends.length]),
                  style: TextStyle(
                    color: context.textFaded(0.6),
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 8),
                ..._acceptedFriends.map((f) {
                  final otherId =
                      f['user_id'] == _uid ? f['friend_id'] : f['user_id'];
                  final p = _profiles[otherId];
                  if (p == null) return const SizedBox.shrink();
                  final name =
                      (p['username'] ?? p['full_name'] ?? 'Teman') as String;
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: _avatar(
                      name,
                      p['avatar_url'] as String?,
                      const Color(0xFF26A69A),
                    ),
                    title: Text(name,
                        style: TextStyle(
                            color: context.textPrimary,
                            fontWeight: FontWeight.w600)),
                    subtitle: _statusSubtitle(p),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: Icon(
                            _hiddenFrom.contains(otherId)
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                            color: _hiddenFrom.contains(otherId)
                                ? Colors.orangeAccent
                                : Colors.white54,
                            size: 20,
                          ),
                          tooltip: context.l.t(
                            visibilityToggleLabel(
                              _hiddenFrom.contains(otherId),
                            ),
                          ),
                          onPressed: _updatingVisibility
                              ? null
                              : () => _toggleVisibility(otherId),
                        ),
                        IconButton(
                          icon: const Icon(
                            Icons.person_remove_outlined,
                            color: Colors.redAccent,
                            size: 20,
                          ),
                          tooltip: context.l.t('delete_friend_tooltip'),
                          onPressed: () => _removeFriend(f, name),
                        ),
                        IconButton(
                          icon: const Icon(
                            Icons.waving_hand_outlined,
                            color: Color(0xFFFFC107),
                            size: 20,
                          ),
                          tooltip: context.l.t('wave_send_tooltip'),
                          onPressed: () => _sendWave(otherId),
                        ),
                        IconButton(
                          icon: const Icon(
                            Icons.chat_bubble_outline,
                            color: Color(0xFF3D5AFE),
                          ),
                          tooltip: context.l.t('chat'),
                          onPressed: () => _openChat(
                            otherId,
                            name,
                            p['avatar_url'] as String?,
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ],
              if (_incomingRequests.isEmpty && _acceptedFriends.isEmpty) ...[
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Center(
                    child: Text(
                      context.l.t('no_friends'),
                      textAlign: TextAlign.center,
                      style:
                          TextStyle(color: context.textFaded(0.5)),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
