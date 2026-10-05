import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zenlook/widgets/message_delete_button.dart';

void main() {
  testWidgets('menampilkan dua pilihan cakupan hapus', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MessageDeleteButton(
            messageId: 'm1',
            onDeleted: (_) {},
          ),
        ),
      ),
    );

    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();

    expect(find.text('Hapus untuk saya'), findsOneWidget);
    expect(find.text('Hapus untuk semua orang'), findsOneWidget);
  });

  testWidgets('klik "hapus untuk semua" meminta konfirmasi', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MessageDeleteButton(
            messageId: 'm1',
            onDeleted: (_) {},
          ),
        ),
      ),
    );

    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hapus untuk semua orang'));
    await tester.pumpAndSettle();

    expect(find.text('Hapus'), findsOneWidget);
  });

  testWidgets('batal konfirmasi tidak memanggil service', (tester) async {
    var called = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MessageDeleteButton(
            messageId: 'm1',
            onDeleted: (_) => called = true,
          ),
        ),
      ),
    );

    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hapus untuk saya'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Batal'));
    await tester.pumpAndSettle();

    expect(called, isFalse);
  });
}