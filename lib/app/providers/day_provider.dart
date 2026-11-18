import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/util/dates.dart';

/// The day currently shown on the Today screen. Shared so the global quick-add
/// sheet writes to the day you are looking at, not always to "now".
final selectedDayProvider = NotifierProvider<SelectedDayController, DateTime>(
  SelectedDayController.new,
);

class SelectedDayController extends Notifier<DateTime> {
  @override
  DateTime build() => dayStart(DateTime.now());

  void select(DateTime day) => state = dayStart(day);

  void shift(int days) =>
      state = DateTime(state.year, state.month, state.day + days);

  void today() => state = dayStart(DateTime.now());
}
