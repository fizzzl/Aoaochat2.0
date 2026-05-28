import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chat_app/main.dart';

void main() {
  testWidgets('App launches with splash screen', (tester) async {
    await tester.pumpWidget(const ChatApp());
    await tester.pump();
    // SplashScreen shows a loading indicator
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}
