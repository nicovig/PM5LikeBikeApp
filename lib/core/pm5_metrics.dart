import 'dart:math' as math;

import 'package:pm5_bike/core/pm5_constants.dart';

enum CalorieMode { pm5Standard, personalWeight }

class Pm5Instant {
  const Pm5Instant({
    required this.speedMetersPerSecond,
    required this.speedKilometersPerHour,
    required this.pacePer1000MetersSeconds,
    required this.kcalPerHour,
  });

  final double speedMetersPerSecond;
  final double speedKilometersPerHour;
  final double? pacePer1000MetersSeconds;
  final double kcalPerHour;
}

abstract final class Pm5Metrics {
  static Pm5Instant instant(
    double watts, {
    required CalorieMode calorieMode,
    double weightKg = Pm5Constants.pm5ReferenceWeightKg,
  }) {
    return Pm5Instant(
      speedMetersPerSecond: speedMetersPerSecond(watts),
      speedKilometersPerHour: speedKilometersPerHour(watts),
      pacePer1000MetersSeconds: pacePer1000MetersSeconds(watts),
      kcalPerHour: kcalPerHour(watts, mode: calorieMode, weightKg: weightKg),
    );
  }

  static double speedMetersPerSecond(double watts) {
    if (!_positive(watts)) {
      return 0;
    }
    return Pm5Constants.speedMetersPerSecondFactor * math.pow(watts, 1 / 3);
  }

  static double speedKilometersPerHour(double watts) {
    if (!_positive(watts)) {
      return 0;
    }
    return Pm5Constants.speedKilometersPerHourFactor * math.pow(watts, 1 / 3);
  }

  static double? pacePer1000MetersSeconds(double watts) {
    final speed = speedMetersPerSecond(watts);
    if (speed <= 0) {
      return null;
    }
    return 1000 / speed;
  }

  static double kcalPerHour(
    double watts, {
    required CalorieMode mode,
    double weightKg = Pm5Constants.pm5ReferenceWeightKg,
  }) {
    final mechanical = Pm5Constants.wattsToKcalPerHour * math.max(0, watts);
    switch (mode) {
      case CalorieMode.pm5Standard:
        return mechanical + Pm5Constants.basalKcalPerHour;
      case CalorieMode.personalWeight:
        final pounds = weightKg * Pm5Constants.poundsPerKilogram;
        return mechanical + Pm5Constants.kcalPerHourPerPound * pounds;
    }
  }

  static double calorieDelta({
    required double watts,
    required double dtSeconds,
    required CalorieMode mode,
    double weightKg = Pm5Constants.pm5ReferenceWeightKg,
  }) {
    if (dtSeconds <= 0) {
      return 0;
    }
    return kcalPerHour(watts, mode: mode, weightKg: weightKg) *
        dtSeconds /
        3600;
  }

  static double realAverageWatts(double wattSeconds, double elapsedSeconds) {
    if (elapsedSeconds <= 0) {
      return 0;
    }
    return wattSeconds / elapsedSeconds;
  }

  /// SPEC §5.5. Average derived from mean pace, not from the arithmetic mean.
  static double? pm5StyleAverageWatts(
    double elapsedSeconds,
    double distanceMeters,
  ) {
    if (elapsedSeconds <= 0 || distanceMeters <= 0) {
      return null;
    }
    final secondsPerMeter = elapsedSeconds / distanceMeters;
    final cube = secondsPerMeter * secondsPerMeter * secondsPerMeter;
    if (cube == 0) {
      return null;
    }
    return Pm5Constants.pacePowerNumerator / cube;
  }

  /// SPEC §7.4. Returns null when the sample must be ignored.
  static double? sanitizeCadenceRpm(double rpm) {
    if (!rpm.isFinite || rpm < 0) {
      return 0;
    }
    if (rpm > Pm5Constants.maxPlausibleRpm) {
      return null;
    }
    return rpm;
  }

  static bool _positive(double watts) => watts.isFinite && watts > 0;
}
