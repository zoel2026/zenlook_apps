import 'dart:async';

import 'package:flutter/material.dart';

import '../screens/chat_detail_screen.dart';
import 'user_avatar.dart';

class MessageBanner extends StatefulWidget {
  const MessageBanner({
    super.key,
    required this.peerId,
    required this.peerName,
    required this.content,
    this.peerAvatar,
  });

  final String peerId;
  final String peerName;
  final String content;
  final String? peerAvatar;

  static OverlayEntry? _currentEntry;
  static Timer? _dismissTimer;

  static void show(
    BuildContext context, {
    required String peerId,
    required String peerName,
    required String content,
    String? peerAvatar,
  }) {
    dismiss();
    final entry = OverlayEntry(
      builder: (_) => MessageBanner(
        peerId: peerId,
        peerName: peerName,
        content: content,
        peerAvatar: peerAvatar,
      ),
    );
    _currentEntry = entry;
    Overlay.of(context).insert(entry);
    _dismissTimer = Timer(const Duration(seconds: 4), () => dismiss());
  }

  static void dismiss() {
    _dismissTimer?.cancel();
    _dismissTimer = null;
    _currentEntry?.remove();
    _currentEntry = null;
  }

  @override
  State<MessageBanner> createState() => _MessageBannerState();
}

class _MessageBannerState extends State<MessageBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<Offset> _slideAnim;
  late final Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, -1),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    _fadeAnim = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOut),
    );
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _onTap() {
    MessageBanner.dismiss();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatDetailScreen(
          peerId: widget.peerId,
          peerName: widget.peerName,
          peerAvatar: widget.peerAvatar,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SlideTransition(
        position: _slideAnim,
        child: FadeTransition(
          opacity: _fadeAnim,
          child: Padding(
            padding: EdgeInsets.fromLTRB(12, topPadding + 8, 12, 0),
            child: GestureDetector(
              onTap: _onTap,
              child: Material(
                elevation: 12,
                borderRadius: BorderRadius.circular(16),
                color: const Color(0xFF1E2A3A),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: const Color(0xFF3D5AFE).withValues(alpha: 0.4),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      UserAvatar(
                        name: widget.peerName,
                        avatarUrl: widget.peerAvatar,
                        radius: 20,
                        backgroundColor: const Color(0xFF7C4DFF),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              widget.peerName,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              widget.content,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.6),
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        Icons.chat_bubble,
                        color: const Color(0xFF3D5AFE).withValues(alpha: 0.7),
                        size: 18,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
