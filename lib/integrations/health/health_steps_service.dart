import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:health/health.dart';

/// Reads daily step counts from Apple Health (iOS) / Health Connect (Android)
/// when available. On unsupported platforms this is a no-op.
class HealthStepsService {
  final Health _health = Health();

  bool get isSupported => !kIsWeb && (Platform.isIOS || Platform.isAndroid);

  static const _types = <HealthDataType>[HealthDataType.STEPS];
  static const _permissions = <HealthDataAccess>[HealthDataAccess.READ];

  Future<bool> hasPermission() async {
    if (!isSupported) return false;
    try {
      final has = await _health.hasPermissions(_types, permissions: _permissions);
      return has == true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> requestPermission() async {
    if (!isSupported) return false;
    try {
      final granted = await _health.requestAuthorization(
        _types,
        permissions: _permissions,
      );
      return granted;
    } catch (_) {
      return false;
    }
  }

  /// Returns total steps for [day] (local day), or null if unavailable.
  Future<int?> getStepsForDay(DateTime day) async {
    if (!isSupported) return null;
    try {
      final start = DateTime(day.year, day.month, day.day);
      final end = start.add(const Duration(days: 1)).subtract(const Duration(milliseconds: 1));
      final now = DateTime.now();
      final effectiveEnd = end.isAfter(now) ? now : end;
      if (!effectiveEnd.isAfter(start)) return 0;
      final steps = await _health.getTotalStepsInInterval(start, effectiveEnd);
      return steps;
    } catch (_) {
      return null;
    }
  }
}
