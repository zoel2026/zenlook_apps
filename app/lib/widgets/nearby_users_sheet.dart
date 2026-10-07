import 'package:flutter/material.dart';

import '../services/locale_service.dart';
import '../services/nearby_service.dart';
import '../services/premium_service.dart';
import '../services/theme_service.dart';
import '../utils/supabase_guard.dart';
import 'user_avatar.dart';

/// Bottom sheet daftar pengguna dalam radius (non-teman, non-blokir).
Future<void> showNearbyUsersSheet(
  BuildContext context, {
  required double lat,
  required double lng,
  double radiusKm = 2,
}) async {
  final isPro = await PremiumService.isPremium();
  final radiusClamped = PremiumService.radiusClamped(radiusKm, isPro);
  final users = await NearbyService.scan(lat, lng, radiusKm: radiusClamped);
  if (!context.mounted) return;
  await showModalBottomSheet(
    context: context,
    backgroundColor: Theme.of(context).colorScheme.surfaceContainerHigh,
    isScrollControlled: true,
    builder: (sheetCtx) {
      final l = sheetCtx.l;
      return DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.65,
        maxChildSize: 0.9,
        builder: (ctx, scrollController) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Text(
                    l.t('nearby_users'),
                    style: TextStyle(
                      color: ctx.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    l.t('scan_notice', args: [radiusClamped.toStringAsFixed(radiusClamped >= 10 ? 0 : 1)]),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: ctx.textFaded(0.5),
                      fontSize: 12,
                    ),
                  ),
                  if (!isPro && radiusKm > 2.0) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Theme.of(ctx)
                            .colorScheme
                            .primaryContainer
                            .withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        l.t(
                          'premium_nearby_limit',
                          args: [2, 10],
                        ),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: ctx.textPrimary,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                  if (isPro) ...[
                    const SizedBox(height: 6),
                    Chip(
                      visualDensity: VisualDensity.compact,
                      label: Text(
                        l.t('premium_pro_badge'),
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: users.isEmpty
                  ? Center(
                      child: Text(
                        l.t('no_nearby'),
                        style: TextStyle(color: ctx.textFaded(0.5)),
                      ),
                    )
                  : ListView.separated(
                      controller: scrollController,
                      itemCount: users.length,
                      separatorBuilder: (_, _) =>
                          const Divider(height: 1, indent: 72),
                      itemBuilder: (_, i) {
                        final u = users[i];
                        final name = (u['full_name'] as String? ?? '').isNotEmpty
                            ? u['full_name'] as String
                            : u['username'] as String;
                        final dist = ((u['distance_m'] as num?) ?? 0).round();
                        final distLabel = dist < 1000
                            ? l.t('meters_away', args: [dist])
                            : l.t('km_away', args: [dist / 1000.0]);
                        return ListTile(
                          leading: UserAvatar(
                            name: name,
                            avatarUrl: u['avatar_url'] as String?,
                            backgroundColor: const Color(0xFF26A69A),
                          ),
                          title: Text(
                            name,
                            style:
                                TextStyle(color: ctx.textPrimary),
                          ),
                          subtitle: Text(
                            '@${u['username']} · $distLabel',
                            style: TextStyle(
                              color: ctx.textFaded(0.5),
                              fontSize: 12,
                            ),
                          ),
                          trailing: FilledButton.tonal(
                            onPressed: () async {
                              final uid = maybeClient()?.auth.currentUser?.id;
                              if (uid == null) return;
                              try {
                                await NearbyService.sendRequest(
                                  uid,
                                  u['id'] as String,
                                );
                                if (ctx.mounted) {
                                  ScaffoldMessenger.of(ctx).showSnackBar(
                                    SnackBar(
                                      content: Text(l.t('request_sent')),
                                    ),
                                  );
                                }
                              } catch (_) {}
                            },
                            child: Text(l.t('send_nearby_request')),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      );
    },
  );
}