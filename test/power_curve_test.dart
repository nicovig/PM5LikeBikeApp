import 'package:flutter_test/flutter_test.dart';
import 'package:pm5_bike/core/pm5_constants.dart';
import 'package:pm5_bike/core/power_curve.dart';

void main() {
  const example = [
    CalibrationPoint(rpm: 60, watts: 150),
    CalibrationPoint(rpm: 70, watts: 180),
    CalibrationPoint(rpm: 80, watts: 220),
    CalibrationPoint(rpm: 90, watts: 280),
  ];

  test('SPEC §4 example fits near a = 0.274 and b = 1.54', () {
    final curve = PowerCurve.fromPoints(example);
    final fit = curve.fit!;
    expect(fit.a, closeTo(Pm5Constants.examplePowerCoefficientA, 0.03));
    expect(fit.b, closeTo(Pm5Constants.examplePowerExponentB, 0.03));
    expect(fit.meanAbsolutePercentageError, lessThan(0.06));
    expect(curve.usesInterpolation, isFalse);
    expect(curve.decreases, isFalse);
  });

  test('linear interpolation is exact between and outside the points', () {
    final curve = PowerCurve.fromPoints(example, forceInterpolation: true);
    expect(curve.usesInterpolation, isTrue);
    expect(curve.estimate(65).watts, closeTo(165, 1e-9));
    expect(curve.estimate(65).outOfCalibratedRange, isFalse);
    expect(curve.estimate(50).outOfCalibratedRange, isTrue);
    expect(curve.estimate(50).watts, closeTo(120, 1e-9));
    expect(curve.estimate(100).outOfCalibratedRange, isTrue);
    expect(curve.estimate(100).watts, closeTo(340, 1e-9));
  });

  test('rpm 0 is rest, not an out-of-range extrapolation', () {
    final curve = PowerCurve.fromPoints(example);
    final estimate = curve.estimate(0);
    expect(estimate.watts, 0);
    expect(estimate.outOfCalibratedRange, isFalse);
    expect(curve.estimate(-10).watts, 0);
  });

  test('duplicate rpm values are averaged before the fit', () {
    final curve = PowerCurve.fromPoints(const [
      CalibrationPoint(rpm: 80, watts: 200),
      CalibrationPoint(rpm: 60, watts: 100),
      CalibrationPoint(rpm: 60, watts: 200),
    ], forceInterpolation: true);
    expect(curve.points.map((point) => point.rpm), [60, 80]);
    expect(curve.points.first.watts, 150);
    expect(curve.estimate(70).watts, closeTo(175, 1e-9));
    expect(curve.estimate(70).outOfCalibratedRange, isFalse);
  });

  test('a jagged table falls back to interpolation', () {
    final curve = PowerCurve.fromPoints(const [
      CalibrationPoint(rpm: 40, watts: 300),
      CalibrationPoint(rpm: 60, watts: 40),
      CalibrationPoint(rpm: 80, watts: 350),
      CalibrationPoint(rpm: 100, watts: 30),
    ]);
    expect(curve.usesInterpolation, isTrue);
    expect(curve.decreases, isTrue);
    expect(curve.estimate(50).watts, closeTo(170, 1e-9));
    expect(curve.estimate(50).outOfCalibratedRange, isFalse);
  });

  test('an empty table reports a missing calibration', () {
    final estimate = PowerCurve.fromPoints(const []).estimate(70);
    expect(estimate.watts, 0);
    expect(estimate.missingCalibration, isTrue);
  });

  test('SPEC §6 level 22 capture stays inside a smooth power law', () {
    final curve = PowerCurve.level22Capture();
    expect(curve.minRpm, 40);
    expect(curve.maxRpm, 100);
    expect(curve.usesInterpolation, isFalse);
    expect(curve.fit!.b, inInclusiveRange(1, 2));
    expect(curve.estimate(70).outOfCalibratedRange, isFalse);
    expect(curve.estimate(30).outOfCalibratedRange, isTrue);
    expect(curve.estimate(110).outOfCalibratedRange, isTrue);
    expect(curve.estimate(70).watts, greaterThan(200));
    expect(curve.estimate(90).watts, greaterThan(curve.estimate(70).watts));
  });
}
