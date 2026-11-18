import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Session lock state. Kept separate from persisted settings so a manual lock
/// or an inactivity timeout can hide the app without changing preferences.
final sessionLockProvider = NotifierProvider<SessionLockController, bool>(
  SessionLockController.new,
);

class SessionLockController extends Notifier<bool> {
  @override
  bool build() => false;

  void lock() => state = true;

  void unlock() => state = false;
}
