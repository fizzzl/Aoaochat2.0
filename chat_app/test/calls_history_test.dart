import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chat_app/screens/calls_history_screen.dart';
import 'package:chat_app/models/call.dart';

void main() {
  group('CallsHistoryScreen', () {
    testWidgets('shows empty state when no calls', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: CallsHistoryScreen()));
      await tester.pumpAndSettle();
      expect(find.text('暂无通话记录'), findsOneWidget);
    });

    testWidgets('displays call entries when data is present', (tester) async {
      final calls = [
        Call(id: 1, callerId: 1, calleeId: 2, type: 'voice', roomId: 'r1', status: 'answered'),
        Call(id: 2, callerId: 2, calleeId: 1, type: 'video', roomId: 'r2', status: 'missed'),
      ];
      await tester.pumpWidget(MaterialApp(home: CallsHistoryScreen(calls: calls)));
      await tester.pumpAndSettle();

      expect(find.text('暂无通话记录'), findsNothing);
      expect(find.text('语音通话'), findsOneWidget);
      expect(find.text('视频通话'), findsOneWidget);
      expect(find.text('已接听'), findsOneWidget);
      expect(find.text('未接听'), findsOneWidget);
    });

    testWidgets('shows red icon for missed calls', (tester) async {
      final calls = [
        Call(id: 1, callerId: 1, calleeId: 2, type: 'voice', roomId: 'r1', status: 'missed'),
      ];
      await tester.pumpWidget(MaterialApp(home: CallsHistoryScreen(calls: calls)));
      await tester.pumpAndSettle();

      expect(find.text('未接听'), findsOneWidget);
    });
  });
}
