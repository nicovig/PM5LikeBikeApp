import 'package:pm5_bike/core/pm5_constants.dart';
import 'package:pm5_bike/core/pm5_metrics.dart';
import 'package:pm5_bike/core/power_curve.dart';
import 'package:pm5_bike/core/workout_plan.dart';

enum CadenceSourceKind { simulation, ble }

class AppSettings {
  const AppSettings({
    required this.activeLevel,
    required this.calorieMode,
    required this.weightKg,
    required this.smoothingSeconds,
    required this.cadenceSource,
    required this.bleDeviceId,
    required this.bleDeviceName,
    required this.levels,
    required this.workoutPlan,
  });

  factory AppSettings.defaults() {
    return AppSettings(
      activeLevel: Pm5Constants.defaultResistanceLevel,
      calorieMode: CalorieMode.pm5Standard,
      weightKg: Pm5Constants.pm5ReferenceWeightKg,
      smoothingSeconds: Pm5Constants.defaultSmoothingSeconds,
      cadenceSource: CadenceSourceKind.simulation,
      bleDeviceId: null,
      bleDeviceName: null,
      levels: defaultLevels(),
      workoutPlan: null,
    );
  }

  static Map<int, List<CalibrationPoint>> defaultLevels() {
    return {
      Pm5Constants.defaultResistanceLevel: [
        for (final pair in Pm5Constants.defaultLevel22Points)
          CalibrationPoint(rpm: pair.$1, watts: pair.$2),
      ],
    };
  }

  final int activeLevel;
  final CalorieMode calorieMode;
  final double weightKg;
  final double smoothingSeconds;
  final CadenceSourceKind cadenceSource;
  final String? bleDeviceId;
  final String? bleDeviceName;
  final Map<int, List<CalibrationPoint>> levels;
  final WorkoutPlan? workoutPlan;

  PowerCurve curveFor(int level) {
    return PowerCurve.fromPoints(levels[level] ?? const []);
  }

  PowerCurve get activeCurve => curveFor(activeLevel);

  AppSettings copyWith({
    int? activeLevel,
    CalorieMode? calorieMode,
    double? weightKg,
    double? smoothingSeconds,
    CadenceSourceKind? cadenceSource,
    Object? bleDeviceId = _unset,
    Object? bleDeviceName = _unset,
    Map<int, List<CalibrationPoint>>? levels,
    Object? workoutPlan = _unset,
  }) {
    return AppSettings(
      activeLevel: activeLevel ?? this.activeLevel,
      calorieMode: calorieMode ?? this.calorieMode,
      weightKg: weightKg ?? this.weightKg,
      smoothingSeconds: smoothingSeconds ?? this.smoothingSeconds,
      cadenceSource: cadenceSource ?? this.cadenceSource,
      bleDeviceId: identical(bleDeviceId, _unset)
          ? this.bleDeviceId
          : bleDeviceId as String?,
      bleDeviceName: identical(bleDeviceName, _unset)
          ? this.bleDeviceName
          : bleDeviceName as String?,
      levels: levels ?? this.levels,
      workoutPlan: identical(workoutPlan, _unset)
          ? this.workoutPlan
          : workoutPlan as WorkoutPlan?,
    );
  }

  Map<String, Object?> toJson() => {
    'activeLevel': activeLevel,
    'calorieMode': calorieMode.name,
    'weightKg': weightKg,
    'smoothingSeconds': smoothingSeconds,
    'cadenceSource': cadenceSource.name,
    'bleDeviceId': bleDeviceId,
    'bleDeviceName': bleDeviceName,
    if (workoutPlan != null) 'workoutPlan': workoutPlan!.toJson(),
    'levels': {
      for (final entry in levels.entries)
        '${entry.key}': [
          for (final point in entry.value)
            {'rpm': point.rpm, 'watts': point.watts},
        ],
    },
  };

  static AppSettings fromJson(Map<String, dynamic> json) {
    final defaults = AppSettings.defaults();
    return AppSettings(
      activeLevel: _clampLevel(
        _asInt(json['activeLevel'], defaults.activeLevel),
      ),
      calorieMode: json['calorieMode'] == CalorieMode.personalWeight.name
          ? CalorieMode.personalWeight
          : CalorieMode.pm5Standard,
      weightKg: _clampWeight(_asDouble(json['weightKg'], defaults.weightKg)),
      smoothingSeconds: _clampSmoothing(
        _asDouble(json['smoothingSeconds'], defaults.smoothingSeconds),
      ),
      cadenceSource: json['cadenceSource'] == CadenceSourceKind.ble.name
          ? CadenceSourceKind.ble
          : CadenceSourceKind.simulation,
      bleDeviceId: json['bleDeviceId'] as String?,
      bleDeviceName: json['bleDeviceName'] as String?,
      levels: _levelsFromJson(json['levels']) ?? defaults.levels,
      workoutPlan: WorkoutPlan.tryParse(json['workoutPlan']),
    );
  }

  static Map<int, List<CalibrationPoint>>? _levelsFromJson(Object? raw) {
    if (raw is! Map) {
      return null;
    }
    final levels = <int, List<CalibrationPoint>>{};
    for (final entry in raw.entries) {
      final level = int.tryParse('${entry.key}');
      final points = entry.value;
      if (level == null || points is! List) {
        continue;
      }
      final parsed = <CalibrationPoint>[];
      for (final item in points) {
        if (item is! Map) {
          continue;
        }
        final rpm = item['rpm'];
        final watts = item['watts'];
        if (rpm is! num || watts is! num) {
          continue;
        }
        if (rpm <= 0 || watts <= 0) {
          continue;
        }
        parsed.add(
          CalibrationPoint(rpm: rpm.toDouble(), watts: watts.toDouble()),
        );
      }
      if (parsed.isNotEmpty) {
        levels[_clampLevel(level)] = parsed;
      }
    }
    if (levels.isEmpty) {
      return null;
    }
    return levels;
  }

  static int _clampLevel(int level) => level
      .clamp(Pm5Constants.minResistanceLevel, Pm5Constants.maxResistanceLevel)
      .toInt();

  static double _clampWeight(double weight) => weight
      .clamp(Pm5Constants.minBodyWeightKg, Pm5Constants.maxBodyWeightKg)
      .toDouble();

  static double _clampSmoothing(double seconds) =>
      seconds.clamp(0, Pm5Constants.maxSmoothingSeconds).toDouble();

  static int _asInt(Object? value, int fallback) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.round();
    }
    return fallback;
  }

  static double _asDouble(Object? value, double fallback) {
    if (value is num) {
      return value.toDouble();
    }
    return fallback;
  }
}

const _unset = Object();
