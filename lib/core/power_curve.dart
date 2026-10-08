import 'dart:math' as math;

import 'package:pm5_bike/core/pm5_constants.dart';

class CalibrationPoint {
  const CalibrationPoint({required this.rpm, required this.watts});

  final double rpm;
  final double watts;
}

class PowerLawFit {
  const PowerLawFit({
    required this.a,
    required this.b,
    required this.meanAbsolutePercentageError,
  });

  final double a;
  final double b;
  final double meanAbsolutePercentageError;

  @override
  String toString() =>
      'PowerLawFit(a: $a, b: $b, mape: $meanAbsolutePercentageError)';
}

class PowerEstimate {
  const PowerEstimate({
    required this.watts,
    required this.outOfCalibratedRange,
    required this.usedInterpolation,
    required this.missingCalibration,
  });

  final double watts;
  final bool outOfCalibratedRange;
  final bool usedInterpolation;
  final bool missingCalibration;
}

class PowerCurve {
  PowerCurve._({
    required this.points,
    required this.fit,
    required this.forceInterpolation,
  });

  factory PowerCurve.fromPoints(
    List<CalibrationPoint> points, {
    bool forceInterpolation = false,
  }) {
    final normalized = _normalize(points);
    return PowerCurve._(
      points: normalized,
      fit: fitPowerLaw(normalized),
      forceInterpolation: forceInterpolation,
    );
  }

  factory PowerCurve.level22Capture() {
    return PowerCurve.fromPoints([
      for (final pair in Pm5Constants.defaultLevel22Points)
        CalibrationPoint(rpm: pair.$1, watts: pair.$2),
    ]);
  }

  final List<CalibrationPoint> points;
  final PowerLawFit? fit;
  final bool forceInterpolation;

  double? get minRpm => points.isEmpty ? null : points.first.rpm;

  double? get maxRpm => points.isEmpty ? null : points.last.rpm;

  bool get usesInterpolation {
    if (points.isEmpty) {
      return false;
    }
    if (forceInterpolation) {
      return true;
    }
    final law = fit;
    if (law == null) {
      return true;
    }
    return law.meanAbsolutePercentageError >
        Pm5Constants.powerLawMaxMeanAbsolutePercentageError;
  }

  bool get decreases {
    for (var i = 1; i < points.length; i++) {
      if (points[i].watts < points[i - 1].watts) {
        return true;
      }
    }
    return false;
  }

  PowerEstimate estimate(double rpm) {
    if (!rpm.isFinite || rpm <= 0) {
      return const PowerEstimate(
        watts: 0,
        outOfCalibratedRange: false,
        usedInterpolation: false,
        missingCalibration: false,
      );
    }
    if (points.isEmpty) {
      return const PowerEstimate(
        watts: 0,
        outOfCalibratedRange: false,
        usedInterpolation: false,
        missingCalibration: true,
      );
    }

    final outOfRange = rpm < points.first.rpm || rpm > points.last.rpm;
    final interpolate = usesInterpolation;
    final computed = interpolate
        ? _interpolate(rpm)
        : fit!.a * math.pow(rpm, fit!.b).toDouble();
    final watts = computed.isFinite && computed > 0 ? computed : 0.0;
    return PowerEstimate(
      watts: watts,
      outOfCalibratedRange: outOfRange,
      usedInterpolation: interpolate,
      missingCalibration: false,
    );
  }

  static PowerLawFit? fitPowerLaw(List<CalibrationPoint> points) {
    final usable = [
      for (final point in points)
        if (point.rpm > 0 && point.watts > 0) point,
    ];
    if (usable.length < 2) {
      return null;
    }

    final logRpm = [for (final point in usable) math.log(point.rpm)];
    final logWatts = [for (final point in usable) math.log(point.watts)];
    final count = usable.length;
    final meanRpm = logRpm.reduce((a, b) => a + b) / count;
    final meanWatts = logWatts.reduce((a, b) => a + b) / count;

    var variance = 0.0;
    var covariance = 0.0;
    for (var i = 0; i < count; i++) {
      final rpmDelta = logRpm[i] - meanRpm;
      variance += rpmDelta * rpmDelta;
      covariance += rpmDelta * (logWatts[i] - meanWatts);
    }
    if (variance == 0) {
      return null;
    }

    final b = covariance / variance;
    final a = math.exp(meanWatts - b * meanRpm);
    var percentageSum = 0.0;
    for (final point in usable) {
      final predicted = a * math.pow(point.rpm, b).toDouble();
      percentageSum += (predicted - point.watts).abs() / point.watts;
    }
    return PowerLawFit(
      a: a,
      b: b,
      meanAbsolutePercentageError: percentageSum / count,
    );
  }

  double _interpolate(double rpm) {
    if (points.length == 1) {
      return points.first.watts;
    }
    if (rpm <= points.first.rpm) {
      return _lerp(points[0], points[1], rpm);
    }
    if (rpm >= points.last.rpm) {
      return _lerp(points[points.length - 2], points.last, rpm);
    }
    for (var i = 0; i < points.length - 1; i++) {
      final right = points[i + 1];
      if (rpm <= right.rpm) {
        return _lerp(points[i], right, rpm);
      }
    }
    return points.last.watts;
  }

  static double _lerp(
    CalibrationPoint left,
    CalibrationPoint right,
    double rpm,
  ) {
    final span = right.rpm - left.rpm;
    if (span == 0) {
      return left.watts;
    }
    final t = (rpm - left.rpm) / span;
    return left.watts + t * (right.watts - left.watts);
  }

  static List<CalibrationPoint> _normalize(List<CalibrationPoint> points) {
    final grouped = <double, List<double>>{};
    for (final point in points) {
      if (!point.rpm.isFinite ||
          !point.watts.isFinite ||
          point.rpm <= 0 ||
          point.watts <= 0) {
        continue;
      }
      grouped.putIfAbsent(point.rpm, () => []).add(point.watts);
    }
    final merged = [
      for (final entry in grouped.entries)
        CalibrationPoint(
          rpm: entry.key,
          watts: entry.value.reduce((a, b) => a + b) / entry.value.length,
        ),
    ]..sort((a, b) => a.rpm.compareTo(b.rpm));
    return merged;
  }
}
