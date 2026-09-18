import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zenlook/screens/login_screen.dart';
import 'package:zenlook/screens/register_screen.dart';
import 'package:zenlook/widgets/user_avatar.dart';

void main() {
  group('UserAvatar', () {
    testWidgets('shows first letter uppercase', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: UserAvatar(name: 'budi')),
      ));
      expect(find.text('B'), findsOneWidget);
    });

    testWidgets('shows ? for empty name', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: UserAvatar(name: '')),
      ));
      expect(find.text('?'), findsOneWidget);
    });
  });

  group('LoginScreen validation', () {
    testWidgets('blocks submit when username too short', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: LoginScreen()));

      await tester.enterText(
          find.widgetWithText(TextFormField, 'Username'), 'ab');
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Password'), 'rahasia');
      await tester.tap(find.text('Masuk'));
      await tester.pump();

      expect(find.text('Minimal 3 karakter'), findsOneWidget);
    });

    testWidgets('blocks submit when fields empty', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: LoginScreen()));

      await tester.tap(find.text('Masuk'));
      await tester.pump();

      expect(find.text('Username wajib diisi'), findsOneWidget);
      expect(find.text('Password wajib diisi'), findsOneWidget);
    });
  });

  group('RegisterScreen validation', () {
    testWidgets('rejects short password', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: RegisterScreen()));

      await tester.enterText(
          find.widgetWithText(TextFormField, 'Nama Lengkap'), 'Budi');
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Username'), 'budi');
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Email'), 'budi@mail.com');
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Password'), '123');
      await tester.tap(find.widgetWithText(FilledButton, 'Daftar'));
      await tester.pump();

      expect(find.text('Minimal 6 karakter'), findsOneWidget);
    });
  });
}
