// This is a basic Flutter widget test for FeedForward app

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:feedforward/main.dart';

void main() {
  testWidgets('FeedForward app launches with role selection screen',
      (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const FeedForwardApp());

    // Verify that the app title is displayed
    expect(find.text('FeedForward'), findsOneWidget);

    // Verify that both role selection buttons are present
    expect(find.text('Continue as Food Donor'), findsOneWidget);
    expect(find.text('Continue as NGO'), findsOneWidget);

    // Verify the subtitle is present
    expect(find.text('Share food, spread kindness'), findsOneWidget);
  });

  testWidgets('Role selection buttons navigate correctly',
      (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const FeedForwardApp());

    // Tap the donor button
    await tester.tap(find.text('Continue as Food Donor'));
    await tester.pumpAndSettle();

    // Verify we're on the donor login screen
    expect(find.text('Donor Login'), findsOneWidget);
    expect(find.text('Welcome Back!'), findsOneWidget);

    // Go back
    await tester.pageBack();
    await tester.pumpAndSettle();

    // Tap the NGO button
    await tester.tap(find.text('Continue as NGO'));
    await tester.pumpAndSettle();

    // Verify we're on the NGO login screen
    expect(find.text('NGO Login'), findsOneWidget);
  });

  testWidgets('Login screen has required fields', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const FeedForwardApp());

    // Navigate to donor login
    await tester.tap(find.text('Continue as Food Donor'));
    await tester.pumpAndSettle();

    // Verify login form fields are present
    expect(find.text('Email'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
    expect(find.text('Login'), findsOneWidget);
    expect(find.text('Sign Up'), findsOneWidget);
  });
}
