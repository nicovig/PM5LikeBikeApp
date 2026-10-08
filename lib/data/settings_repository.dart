import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:pm5_bike/data/app_settings.dart';

class SettingsRepository {
  static const _key = 'pm5_bike.settings';

  Future<AppSettings> load() async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(_key);
    if (raw == null) {
      return AppSettings.defaults();
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        return AppSettings.defaults();
      }
      return AppSettings.fromJson(decoded);
    } catch (_) {
      return AppSettings.defaults();
    }
  }

  Future<void> save(AppSettings settings) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_key, jsonEncode(settings.toJson()));
  }
}
