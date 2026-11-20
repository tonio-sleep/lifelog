import 'package:flutter_test/flutter_test.dart';
import 'package:lifelog/features/photos/media_import.dart';

void main() {
  test('success counts come from writes, not picked files', () {
    const summary = MediaImportSummary(total: 20, added: 3, skipped: 16, failed: 1);
    expect(summary.message, '3 items added, 16 skipped, 1 failed.');
  });

  test('zero successful imports never claims photos were added', () {
    const summary = MediaImportSummary(total: 20, added: 0, skipped: 20, failed: 0);
    expect(summary.message, '20 skipped.');
  });

  test('singular labels read naturally', () {
    const summary = MediaImportSummary(total: 1, added: 1, skipped: 0, failed: 0);
    expect(summary.message, '1 item added.');
  });
}
