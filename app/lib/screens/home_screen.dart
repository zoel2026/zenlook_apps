import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/fcm_service.dart';
import '../services/locale_service.dart';
import '../widgets/app_sidebar.dart';
import '../widgets/exit_confirmation.dart';
import '../widgets/message_banner.dart';
import 'chat_tab.dart';
import 'friends_tab.dart';
import 'login_screen.dart';
import 'map_tab.dart';
import 'music_tab.dart';
import 'profile_tab.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with WidgetsBindingObserver {
  int _index = 0;
  final _mapKey = GlobalKey<MapTabState>();
  final _chatKey = GlobalKey<ChatTabState>();
  StreamSubscription<AuthState>? _authSub;

  static const _dark = Color(0xFF1A2130);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Jika sesi berakhir (sign out), balik ke login supaya layar-layar
    // yang mengandalkan sesi tidak crash.
    try {
      _authSub =
          Supabase.instance.client.auth.onAuthStateChange.listen((data) {
        final event = data.event;
        if (!mounted) return;
        if (event == AuthChangeEvent.signedOut) {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const LoginScreen()),
            (route) => false,
          );
        }
      });
    } catch (_) {
      // Supabase belum terinisialisasi (mis. lingkungan test) — abaikan.
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // App kembali ke foreground — coba sinkron ulang token FCM
    // kalau sebelumnya gagal (mis. saat offline).
    if (state == AppLifecycleState.resumed) {
      FcmService.resync();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _authSub?.cancel();
    super.dispose();
  }

  void _selectTab(int i) {
    setState(() => _index = i);
    if (i == 0) _mapKey.currentState?.reloadFriends();
    if (i == 2) _chatKey.currentState?.reload();
  }

  void _onIncomingMessage(
    String peerId,
    String peerName,
    String content,
    String? peerAvatar,
  ) {
    if (!mounted) return;
    MessageBanner.show(
      context,
      peerId: peerId,
      peerName: peerName,
      content: content,
      peerAvatar: peerAvatar,
    );
  }

  NavigationBarThemeData _navTheme(BuildContext context) {
    final base = Theme.of(context).navigationBarTheme;
    return base.copyWith(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.white,
      shadowColor: Colors.black12,
      indicatorColor: _dark,
      height: 68,
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          size: 24,
          color: states.contains(WidgetState.selected)
              ? Colors.white
              : Colors.black54,
        ),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontSize: 12,
          fontWeight: states.contains(WidgetState.selected)
              ? FontWeight.bold
              : FontWeight.w500,
          color: states.contains(WidgetState.selected)
              ? _dark
              : Colors.black54,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: AppSidebar(
        currentIndex: _index,
        onSelect: (i) {
          Navigator.of(context).pop();
          _selectTab(i);
        },
      ),
      body: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) async {
          if (didPop) return;
          final yes = await showExitConfirmation(context);
          if (yes == true && context.mounted) {
            try {
              await Supabase.instance.client.auth.signOut();
            } catch (_) {}
            if (context.mounted) await SystemNavigator.pop();
          }
        },
        child: IndexedStack(
          index: _index,
          children: [
            MapTab(key: _mapKey),
            const FriendsTab(),
            ChatTab(key: _chatKey, onIncomingMessage: _onIncomingMessage),
            const MusicTab(),
            const ProfileTab(),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBarTheme(
        data: _navTheme(context),
        child: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: _selectTab,
          destinations: [
            NavigationDestination(
              icon: const Icon(Icons.map_outlined),
              selectedIcon: const Icon(Icons.map),
              label: context.l.t('map'),
            ),
            NavigationDestination(
              icon: const Icon(Icons.people_outline),
              selectedIcon: const Icon(Icons.people),
              label: context.l.t('friends'),
            ),
            NavigationDestination(
              icon: const Icon(Icons.chat_bubble_outline),
              selectedIcon: const Icon(Icons.chat_bubble),
              label: context.l.t('chat'),
            ),
            NavigationDestination(
              icon: const Icon(Icons.music_note_outlined),
              selectedIcon: const Icon(Icons.music_note),
              label: context.l.t('music'),
            ),
            NavigationDestination(
              icon: const Icon(Icons.person_outline),
              selectedIcon: const Icon(Icons.person),
              label: context.l.t('profile'),
            ),
          ],
        ),
      ),
    );
  }
}
