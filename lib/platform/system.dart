import 'package:flutter/services.dart';

/// Мост к Android: фоновая служба, показ поверх экрана блокировки, ограничения батареи.
class SystemBridge {
  static const MethodChannel _ch = MethodChannel('m365/system');

  static Future<bool> startService(String title, String text) async {
    try {
      return (await _ch.invokeMethod<bool>('startService', {'title': title, 'text': text})) ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> updateService(String title, String text) async {
    try {
      await _ch.invokeMethod<void>('updateService', {'title': title, 'text': text});
    } catch (_) {}
  }

  /// (работает ли служба, последняя ошибка запуска)
  static Future<(bool, String?)> serviceStatus() async {
    try {
      final m = await _ch.invokeMapMethod<String, dynamic>('serviceStatus');
      return (m?['running'] == true, m?['error'] as String?);
    } catch (e) {
      return (false, 'канал: $e');
    }
  }

  static Future<void> stopService() async {
    try {
      await _ch.invokeMethod<void>('stopService');
    } catch (_) {}
  }

  static Future<void> setShowWhenLocked(bool on) async {
    try {
      await _ch.invokeMethod<void>('setShowWhenLocked', {'on': on});
    } catch (_) {}
  }

  static Future<bool> isIgnoringBatteryOptimizations() async {
    try {
      return (await _ch.invokeMethod<bool>('isIgnoringBatteryOptimizations')) ?? true;
    } catch (_) {
      return true;
    }
  }

  static Future<void> requestIgnoreBatteryOptimizations() async {
    try {
      await _ch.invokeMethod<void>('requestIgnoreBatteryOptimizations');
    } catch (_) {}
  }

  static Future<void> openAppSettings() async {
    try {
      await _ch.invokeMethod<void>('openAppSettings');
    } catch (_) {}
  }
}
