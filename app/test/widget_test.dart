import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'package:zenlook/screens/splash_screen.dart';

void main() {
  setUpAll(() async {
    try {
      await dotenv.load(fileName: '.env');
    } catch (_) {
      await dotenv.load(fileName: '.env.example');
    }
  });

  testWidgets('Splash screen shows branding image', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: SplashScreen()));

    expect(find.byType(Image), findsOneWidget);
    expect(find.text('Zenly Apps'), findsNothing);
  });
}