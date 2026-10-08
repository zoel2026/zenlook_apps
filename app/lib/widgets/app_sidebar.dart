import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/locale_service.dart';
import '../utils/supabase_guard.dart';
import 'exit_confirmation.dart';
import 'user_avatar.dart';

class AppSidebar extends StatelessWidget {
  const AppSidebar({
    super.key,
    required this.currentIndex,
    required this.onSelect,
  });

  final int currentIndex;
  final void Function(int index) onSelect;

  static const _iconItems = [
    (icon: Icons.map_outlined, activeIcon: Icons.map, labelKey: 'map'),
    (icon: Icons.people_outline, activeIcon: Icons.people, labelKey: 'friends'),
    (
      icon: Icons.chat_bubble_outline,
      activeIcon: Icons.chat_bubble,
      labelKey: 'chat',
    ),
    (
      icon: Icons.music_note_outlined,
      activeIcon: Icons.music_note,
      labelKey: 'music',
    ),
    (icon: Icons.person_outline, activeIcon: Icons.person, labelKey: 'profile'),
  ];

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    return Drawer(
      backgroundColor: const Color(0xFF1A2130),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
              child: Row(
                children: [
                  _ProfileAvatar(),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Zenlook',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        l.t('sidebar_tagline'),
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.5),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Divider(color: Colors.white10),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                children: [
                  for (var i = 0; i < _iconItems.length; i++)
                    _buildItem(context, l, i),
                ],
              ),
            ),
            const Divider(color: Colors.white10),
            ListTile(
              leading: const Icon(
                Icons.logout,
                color: Colors.redAccent,
                size: 20,
              ),
              title: Text(
                l.t('logout_app'),
                style: const TextStyle(color: Colors.redAccent),
              ),
              onTap: () async {
                final yes = await showExitConfirmation(context);
                if (yes == true) {
                  try {
                    await Supabase.instance.client.auth.signOut();
                  } catch (_) {}
                  if (context.mounted) await SystemNavigator.pop();
                }
              },
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Zenlook v1.0.0',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.3),
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildItem(BuildContext context, AppLocalizations l, int i) {
    final item = _iconItems[i];
    final selected = i == currentIndex;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: selected
            ? const Color(0xFF3D5AFE).withValues(alpha: 0.2)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: ListTile(
          dense: true,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          leading: Icon(
            selected ? item.activeIcon : item.icon,
            color: selected ? const Color(0xFF3D5AFE) : Colors.white70,
            size: 20,
          ),
          title: Text(
            l.t(item.labelKey),
            style: TextStyle(
              color: selected ? Colors.white : Colors.white70,
              fontWeight: selected ? FontWeight.bold : FontWeight.w500,
            ),
          ),
          trailing: selected
              ? const Icon(
                  Icons.chevron_right,
                  color: Color(0xFF3D5AFE),
                  size: 20,
                )
              : null,
          onTap: () => onSelect(i),
        ),
      ),
    );
  }
}

class _ProfileAvatar extends StatefulWidget {
  @override
  State<_ProfileAvatar> createState() => _ProfileAvatarState();
}

class _ProfileAvatarState extends State<_ProfileAvatar> {
  String? _avatarUrl;
  String? _name;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final uid = maybeClient()?.auth.currentUser?.id;
    if (uid == null) return;
    try {
      final res = await Supabase.instance.client
          .from('profiles')
          .select('avatar_url, full_name, username')
          .eq('id', uid)
          .maybeSingle();
      if (!mounted) return;
      setState(() {
        _avatarUrl = (res?['avatar_url'] as String?)?.isNotEmpty == true
            ? res!['avatar_url'] as String
            : null;
        final full = (res?['full_name'] as String?)?.trim() ?? '';
        final username = (res?['username'] as String?)?.trim() ?? '';
        _name = full.isNotEmpty
            ? full
            : (username.isNotEmpty ? username : 'Zenlook');
      });
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return UserAvatar(
      name: _name ?? 'Zenlook',
      avatarUrl: _avatarUrl,
      radius: 19,
      backgroundColor: const Color(0xFF3D5AFE),
    );
  }
}
