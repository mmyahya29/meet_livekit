// Smoke tests for the example app.
//
// This previously asserted against a `Counter` template that no longer exists,
// so `flutter test` in example/ failed on a freshly cloned checkout.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:example/main.dart';

void main() {
  testWidgets('entry screen renders the join form', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: MyApp()));

    expect(find.text('Join LiveKit Room'), findsOneWidget);
    expect(find.text('Join Room'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Server URL'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'LiveKit Token'), findsOneWidget);
  });

  testWidgets('joining without a URL or token is rejected', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: MyApp()));

    // The fields ship pre-filled with placeholders, so clear them first to
    // exercise the guard. Without clearing, Join would attempt a real
    // connection against a fake credential.
    await tester.enterText(find.widgetWithText(TextField, 'Server URL'), '');
    await tester.enterText(find.widgetWithText(TextField, 'LiveKit Token'), '');

    await tester.tap(find.text('Join Room'));
    await tester.pump();

    // The guard should keep us on the entry screen instead of navigating into
    // a call with empty credentials.
    expect(find.text('Please enter a URL and Token'), findsOneWidget);
    expect(find.text('Join LiveKit Room'), findsOneWidget);
  });
}