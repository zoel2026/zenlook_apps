import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zenlook/screens/splash_screen.dart';

void main() {
  testWidgets('Splash screen shows branding image', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: SplashScreen()));

    expect(find.byType(Image), findsOneWidget);
    expect(find.text('Zenly Apps'), findsNothing);
  });
}