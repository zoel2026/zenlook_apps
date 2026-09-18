import 'package:flutter/material.dart';

import '../services/locale_service.dart';

Future<bool?> showExitConfirmation(BuildContext context) {
  final l = context.l;
  return showDialog<bool>(
    context: context,
    builder: (dialogCtx) => AlertDialog(
      backgroundColor: const Color(0xFF1A2130),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          const Icon(Icons.logout, color: Colors.redAccent),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              l.t('exit_title'),
              style: const TextStyle(color: Colors.white, fontSize: 18),
            ),
          ),
        ],
      ),
      content: Text(
        l.t('exit_body'),
        style: const TextStyle(color: Colors.white70),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogCtx).pop(false),
          child: Text(l.t('no')),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF3D5AFE),
          ),
          onPressed: () => Navigator.of(dialogCtx).pop(true),
          child: Text(l.t('yes')),
        ),
      ],
    ),
  );
}
