import 'package:flutter/material.dart';

import '../services/locale_service.dart';
import '../services/message_service.dart';

/// Tombol hapus pesan milik sendiri + dialog konfirmasi.
///
/// Dipisah dari `chat_detail_screen.dart` supaya file layar chat yang sudah
/// besar tidak tambah panjang. Lihat `docs/SPEC-delete-message.md`.
class MessageDeleteButton extends StatelessWidget {
  const MessageDeleteButton({
    super.key,
    required this.messageId,
    required this.onDeleted,
  });

  final String messageId;

  /// Dipanggil dengan [DeleteResult] setelah server menjawab.
  final ValueChanged<DeleteResult> onDeleted;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.delete_outline, size: 14),
      color: Colors.white54,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
      tooltip: context.l.t('delete_menu'),
      onPressed: () => _ask(context),
    );
  }

  Future<void> _ask(BuildContext context) async {
    final scope = await showModalBottomSheet<DeleteScope>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerHigh,
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final s in DeleteScope.values)
              ListTile(
                leading: Icon(
                  s.affectsOtherPerson
                      ? Icons.delete_forever_outlined
                      : Icons.visibility_off_outlined,
                  color: s.affectsOtherPerson ? Colors.redAccent : null,
                ),
                title: Text(sheetCtx.l.t(deleteMessageKey(s))),
                onTap: () => Navigator.of(sheetCtx).pop(s),
              ),
          ],
        ),
      ),
    );
    if (scope == null || !context.mounted) return;

    final confirmed = await _confirm(context, scope);
    if (!confirmed || !context.mounted) return;

    final result = await MessageService.deleteMessage(
      messageId: messageId,
      scope: scope,
    );
    if (!context.mounted) return;
    onDeleted(result);
  }

  Future<bool> _confirm(BuildContext context, DeleteScope scope) async {
    final l = context.l;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dlgCtx) => AlertDialog(
        title: Text(l.t(confirmDeleteMessageKey(scope))),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dlgCtx).pop(false),
            child: Text(l.t('cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: scope.affectsOtherPerson
                  ? const Color(0xFFD64545)
                  : null,
            ),
            onPressed: () => Navigator.of(dlgCtx).pop(true),
            child: Text(l.t('delete_confirm_action')),
          ),
        ],
      ),
    );
    return ok ?? false;
  }
}