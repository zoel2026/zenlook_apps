import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zenlook/screens/home_screen.dart';

void main() {
  testWidgets('Home screen shows navigation bar', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
    await tester.pump();

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('Peta'), findsOneWidget);
    expect(find.text('Teman'), findsOneWidget);
    expect(find.text('Chat'), findsOneWidget);
    expect(find.text('Profil'), findsOneWidget);
  });

  testWidgets('Friends tab shows search field', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
    await tester.pump();

    await tester.tap(find.byIcon(Icons.people_outline));
    await tester.pump();

    expect(find.text('Cari nama atau username...'), findsOneWidget);
  });

  testWidgets('Profile tab shows save button', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.byIcon(Icons.person_outline));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Simpan Profil'), findsOneWidget);
    expect(find.text('Keluar'), findsOneWidget);
  });

  testWidgets('Chat tab shows empty state', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.byIcon(Icons.chat_bubble_outline));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Belum ada percakapan'), findsOneWidget);
  });
}