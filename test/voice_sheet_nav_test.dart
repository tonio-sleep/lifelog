import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifelog/app/theme/app_theme.dart';
import 'package:lifelog/features/journal/voice_note_sheet.dart';

void main() {
  testWidgets('voice sheet controls render above a nested navigation bar', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Navigator(
            onGenerateRoute: (_) => MaterialPageRoute<void>(
              builder: (sheetCallerContext) => Center(
                child: ElevatedButton(
                  onPressed: () => showVoiceNoteSheet(sheetCallerContext),
                  child: const Text('Open voice'),
                ),
              ),
            ),
          ),
          bottomNavigationBar: const SizedBox(
            height: 80,
            child: Center(child: Text('Nav Bar')),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open voice'));
    // The sheet has an indeterminate preparation indicator, so a full settle
    // never completes. Pump a few frames instead.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();

    // The sheet is on the root navigator: its pinned footer is present and
    // tappable instead of being covered by the bottom navigation bar.
    expect(find.text('Voice note'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    expect(find.byType(FilledButton), findsWidgets);

    await tester.tap(find.text('Cancel'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Voice note'), findsNothing);
  });
}
