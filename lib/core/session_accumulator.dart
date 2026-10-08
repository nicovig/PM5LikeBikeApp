import 'dart:math' as math;

import 'package:pm5_bike/core/pm5_constants.dart';
import 'package:pm5_bike/core/pm5_metrics.dart';
import 'package:pm5_bike/core/power_curve.dart';

class SessionSample {
  const SessionSample({
    required this.elapsedSeconds,
    required this.watts,
    required this.rpm,
    required this.outOfRange,
  });

  final double elapsedSeconds;
  final double watts;
  final double rpm;
  final bool outOfRange;

  Map<String, Object> toJson() => {
    'elapsedSeconds': elapsedSeconds,
    'watts': watts,
    'rpm': rpm,
    'outOfRange': outOfRange,
  };

  static SessionSample? fromJson(Map<String, dynamic> json) {
    final elapsed = json['elapsedSeconds'];
    final watts = json['watts'];
    final rpm = json['rpm'];
    if (elapsed is! num || watts is! num || rpm is! num) {
      return null;
    }
    return SessionSample(
      elapsedSeconds: elapsed.toDouble(),
      watts: watts.toDouble(),
      rpm: rpm.toDouble(),
      outOfRange: json['outOfRange'] == true,
    );
  }
}

class SessionSnapshot {
  const SessionSnapshot({
    required this.elapsedSeconds,
    required this.rpm,
    required this.watts,
    required this.outOfCalibratedRange,
    required this.missingCalibration,
    required this.calibratedMinRpm,
    required this.calibratedMaxRpm,
    required this.distanceMeters,
    required this.speedMetersPerSecond,
    required this.speedKilometersPerHour,
    required this.pacePer1000MetersSeconds,
    required this.calories,
    required this.averageWatts,
    required this.pm5AverageWatts,
    required this.averageRpm,
    required this.hadOutOfRange,
    required this.outOfRangeSeconds,
    required this.usedInterpolation,
  });

  static const empty = SessionSnapshot(
    elapsedSeconds: 0,
    rpm: 0,
    watts: 0,
    outOfCalibratedRange: false,
    missingCalibration: false,
    calibratedMinRpm: null,
    calibratedMaxRpm: null,
    distanceMeters: 0,
    speedMetersPerSecond: 0,
    speedKilometersPerHour: 0,
    pacePer1000MetersSeconds: null,
    calories: 0,
    averageWatts: 0,
    pm5AverageWatts: null,
    averageRpm: 0,
    hadOutOfRange: false,
    outOfRangeSeconds: 0,
    usedInterpolation: false,
  );

  final double elapsedSeconds;
  final double rpm;
  final double watts;
  final bool outOfCalibratedRange;
  final bool missingCalibration;
  final double? calibratedMinRpm;
  final double? calibratedMaxRpm;
  final double distanceMeters;
  final double speedMetersPerSecond;
  final double speedKilometersPerHour;
  final double? pacePer1000MetersSeconds;
  final double calories;
  final double averageWatts;
  final double? pm5AverageWatts;
  final double averageRpm;
  final bool hadOutOfRange;
  final double outOfRangeSeconds;
  final bool usedInterpolation;
}

class SessionAccumulator {
  double _elapsedSeconds = 0;
  double _rpm = 0;
  double _watts = 0;
  bool _outOfRange = false;
  bool _missingCalibration = false;
  double? _minRpm;
  double? _maxRpm;
  double _distanceMeters = 0;
  double _speedMetersPerSecond = 0;
  double _speedKilometersPerHour = 0;
  double? _pacePer1000MetersSeconds;
  double _calories = 0;
  double _wattSeconds = 0;
  double _rpmSeconds = 0;
  bool _hadOutOfRange = false;
  double _outOfRangeSeconds = 0;
  bool _usedInterpolation = false;
  int _lastRecordedSecond = 0;
  final List<SessionSample> _samples = [];

  SessionSnapshot get snapshot {
    return SessionSnapshot(
      elapsedSeconds: _elapsedSeconds,
      rpm: _rpm,
      watts: _watts,
      outOfCalibratedRange: _outOfRange,
      missingCalibration: _missingCalibration,
      calibratedMinRpm: _minRpm,
      calibratedMaxRpm: _maxRpm,
      distanceMeters: _distanceMeters,
      speedMetersPerSecond: _speedMetersPerSecond,
      speedKilometersPerHour: _speedKilometersPerHour,
      pacePer1000MetersSeconds: _pacePer1000MetersSeconds,
      calories: _calories,
      averageWatts: Pm5Metrics.realAverageWatts(_wattSeconds, _elapsedSeconds),
      pm5AverageWatts: Pm5Metrics.pm5StyleAverageWatts(
        _elapsedSeconds,
        _distanceMeters,
      ),
      averageRpm: _elapsedSeconds <= 0 ? 0 : _rpmSeconds / _elapsedSeconds,
      hadOutOfRange: _hadOutOfRange,
      outOfRangeSeconds: _outOfRangeSeconds,
      usedInterpolation: _usedInterpolation,
    );
  }

  List<SessionSample> get samples => List.unmodifiable(_samples);

  void reset() {
    _elapsedSeconds = 0;
    _rpm = 0;
    _watts = 0;
    _outOfRange = false;
    _missingCalibration = false;
    _minRpm = null;
    _maxRpm = null;
    _distanceMeters = 0;
    _speedMetersPerSecond = 0;
    _speedKilometersPerHour = 0;
    _pacePer1000MetersSeconds = null;
    _calories = 0;
    _wattSeconds = 0;
    _rpmSeconds = 0;
    _hadOutOfRange = false;
    _outOfRangeSeconds = 0;
    _usedInterpolation = false;
    _lastRecordedSecond = 0;
    _samples.clear();
  }

  void tick({
    required double dtSeconds,
    required double rpm,
    required PowerCurve curve,
    required bool countTime,
    required CalorieMode calorieMode,
    required double weightKg,
  }) {
    final estimate = curve.estimate(rpm);
    _rpm = rpm;
    _watts = estimate.watts;
    _outOfRange = estimate.outOfCalibratedRange;
    _missingCalibration = estimate.missingCalibration;
    _minRpm = curve.minRpm;
    _maxRpm = curve.maxRpm;
    _usedInterpolation = estimate.usedInterpolation;
    _speedMetersPerSecond = Pm5Metrics.speedMetersPerSecond(_watts);
    _speedKilometersPerHour = Pm5Metrics.speedKilometersPerHour(_watts);
    _pacePer1000MetersSeconds = Pm5Metrics.pacePer1000MetersSeconds(_watts);
    if (!countTime || dtSeconds <= 0) {
      return;
    }

    final dt = math.min(dtSeconds, Pm5Constants.maxTickSeconds).toDouble();
    _elapsedSeconds += dt;
    _distanceMeters += _speedMetersPerSecond * dt;
    _calories += Pm5Metrics.calorieDelta(
      watts: _watts,
      dtSeconds: dt,
      mode: calorieMode,
      weightKg: weightKg,
    );
    _wattSeconds += _watts * dt;
    _rpmSeconds += _rpm * dt;
    if (_outOfRange) {
      _hadOutOfRange = true;
      _outOfRangeSeconds += dt;
    }
    _recordCrossedSeconds();
  }

  void _recordCrossedSeconds() {
    final second = _elapsedSeconds.floor();
    while (_lastRecordedSecond < second) {
      _lastRecordedSecond += 1;
      _samples.add(
        SessionSample(
          elapsedSeconds: _lastRecordedSecond.toDouble(),
          watts: _watts,
          rpm: _rpm,
          outOfRange: _outOfRange,
        ),
      );
    }
  }
}
