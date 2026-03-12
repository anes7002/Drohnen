import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/main.dart'; 

void main() {
  testWidgets('RoboMaster TT Dashboard UI Test', (WidgetTester tester) async {
    await tester.pumpWidget(const RoboMasterApp());

    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('192.168.10.1'), findsOneWidget);

    expect(find.text('Verbinden'), findsOneWidget);

    expect(find.text('NOT STOPP'), findsOneWidget);

    expect(find.text('Start'), findsOneWidget);
    expect(find.text('Landen'), findsOneWidget);

    expect(find.text('AI Erkennung'), findsOneWidget);
    expect(find.text('Ring-Modus'), findsOneWidget);

    await tester.tap(find.text('Verbinden'));
    await tester.pump(); // Frame neu zeichnen lassen

    expect(find.text('Trennen'), findsOneWidget);
  });
}
