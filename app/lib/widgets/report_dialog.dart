import 'package:flutter/material.dart';

import '../services/locale_service.dart';

/// Dialog untuk memilih alasan laporan pengguna.
/// Mengembalikan alasan (String) atau null bila dibatalkan.
Future<String?> showReportDialogWithReasons(
  BuildContext context, {
  required String peerName,
  List<String>? reasons,
}) {
  final list =
      reasons ??
      [
        context.l.t('report_spam'),
        context.l.t('report_inappropriate'),
        context.l.t('report_harassment'),
        context.l.t('report_fake_account'),
        context.l.t('report_other'),
      ];
  return showDialog<String>(
    context: context,
    builder: (dialogCtx) => SimpleDialog(
      title: Text(
        context.l.t('report_confirm_title', args: [peerName]),
      ),
      children: [
        for (final r in list)
          SimpleDialogOption(
            onPressed: () => Navigator.of(dialogCtx).pop(r),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(r, style: const TextStyle(fontSize: 15)),
            ),
          ),
      ],
    ),
  );
}