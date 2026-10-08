import 'package:flutter_test/flutter_test.dart';
import 'package:pm5_bike/core/metric_format.dart';
import 'package:pm5_bike/core/pm5_constants.dart';
import 'package:pm5_bike/core/pm5_metrics.dart';
import 'package:pm5_bike/core/power_curve.dart';
import 'package:pm5_bike/core/session_accumulator.dart';

void main() {
  const vectors = <(int, double, double, int, String, String)>[
    (100, 23.7, 151.8, 644, '23,7', '2:31.8'),
    (150, 27.1, 132.6, 816, '27,1', '2:12.6'),
    (200, 29.9, 120.5, 988, '29,9', '2:00.5'),
    (250, 32.2, 111.9, 1160, '32,2', '1:51.9'),
    (300, 34.2, 105.3, 1332, '34,2', '1:45.3'),
    (373, 36.8, 97.9, 1584, '36,8', '1:37.9'),
  ];

  for (final vector in vectors) {
    final watts = vector.$1.toDouble();
    test('SPEC §5.7 vector ${vector.$1} W', () {
      expect(Pm5Metrics.speedKilometersPerHour(watts), closeTo(vector.$2, 0.1));
      expect(
        Pm5Metrics.pacePer1000MetersSeconds(watts),
        closeTo(vector.$3, 0.5),
      );
      expect(
        Pm5Metrics.kcalPerHour(watts, mode: CalorieMode.pm5Standard),
        closeTo(vector.$4, 2),
      );
      expect(formatSpeed(Pm5Metrics.speedKilometersPerHour(watts)), vector.$5);
      expect(formatPace(Pm5Metrics.pacePer1000MetersSeconds(watts)), vector.$6);
      expect(
        Pm5Metrics.kcalPerHour(watts, mode: CalorieMode.pm5Standard).round(),
        vector.$4,
      );
    });
  }

  test('rest has no pace and still burns the PM5 basal calories', () {
    expect(Pm5Metrics.speedMetersPerSecond(0), 0);
    expect(Pm5Metrics.pacePer1000MetersSeconds(0), isNull);
    expect(
      Pm5Metrics.kcalPerHour(0, mode: CalorieMode.pm5Standard),
      Pm5Constants.basalKcalPerHour,
    );
  });

  test('personal weight uses 1.714 kcal/h per pound', () {
    expect(
      Pm5Metrics.kcalPerHour(
        100,
        mode: CalorieMode.personalWeight,
        weightKg: 80,
      ),
      closeTo(646.4578539, 0.001),
    );
    final kgFor175Lb = 175 / Pm5Constants.poundsPerKilogram;
    expect(
      Pm5Metrics.kcalPerHour(
        0,
        mode: CalorieMode.personalWeight,
        weightKg: kgFor175Lb,
      ),
      closeTo(300, 0.1),
    );
  });

  test('constant power keeps the PM5 average on the arithmetic average', () {
    const watts = 200.0;
    const seconds = 30.0;
    final distance = Pm5Metrics.speedMetersPerSecond(watts) * seconds;
    expect(Pm5Metrics.realAverageWatts(watts * seconds, seconds), watts);
    expect(
      Pm5Metrics.pm5StyleAverageWatts(seconds, distance),
      closeTo(watts, 0.2),
    );
  });

  test('variable power makes the PM5 average lower than the real average', () {
    const half = 10.0;
    final distance =
        Pm5Metrics.speedMetersPerSecond(100) * half +
        Pm5Metrics.speedMetersPerSecond(300) * half;
    final real = Pm5Metrics.realAverageWatts(100 * half + 300 * half, half * 2);
    final pm5 = Pm5Metrics.pm5StyleAverageWatts(half * 2, distance)!;
    expect(real, 200);
    expect(pm5, lessThan(real - 1));
  });

  test('coasting keeps the clock and drops the PM5 average', () {
    final distance = Pm5Metrics.speedMetersPerSecond(200) * 10;
    expect(Pm5Metrics.realAverageWatts(200 * 10, 20), 100);
    expect(Pm5Metrics.pm5StyleAverageWatts(20, distance), closeTo(25, 0.5));
    expect(Pm5Metrics.pm5StyleAverageWatts(10, 0), isNull);
  });

  test('glitches above 200 RPM are rejected', () {
    expect(Pm5Metrics.sanitizeCadenceRpm(80), 80);
    expect(Pm5Metrics.sanitizeCadenceRpm(0), 0);
    expect(Pm5Metrics.sanitizeCadenceRpm(-3), 0);
    expect(Pm5Metrics.sanitizeCadenceRpm(double.nan), 0);
    expect(Pm5Metrics.sanitizeCadenceRpm(201), isNull);
  });

  test('accumulator integrates distance, basal rest, and both averages', () {
    final curve = PowerCurve.fromPoints(const [
      CalibrationPoint(rpm: 60, watts: 200),
      CalibrationPoint(rpm: 90, watts: 300),
    ], forceInterpolation: true);
    final accumulator = SessionAccumulator();
    for (var i = 0; i < 40; i++) {
      accumulator.tick(
        dtSeconds: 0.25,
        rpm: 60,
        curve: curve,
        countTime: true,
        calorieMode: CalorieMode.pm5Standard,
        weightKg: 79,
      );
    }
    final snapshot = accumulator.snapshot;
    expect(snapshot.elapsedSeconds, 10);
    expect(snapshot.watts, 200);
    expect(
      snapshot.distanceMeters,
      closeTo(Pm5Metrics.speedMetersPerSecond(200) * 10, 1e-6),
    );
    expect(
      snapshot.calories,
      closeTo(
        (Pm5Constants.wattsToKcalPerHour * 200 +
                Pm5Constants.basalKcalPerHour) *
            10 /
            3600,
        1e-6,
      ),
    );
    expect(snapshot.averageWatts, closeTo(200, 1e-6));
    expect(snapshot.pm5AverageWatts, closeTo(200, 0.2));
    expect(accumulator.samples, hasLength(10));

    final before = snapshot.elapsedSeconds;
    accumulator.tick(
      dtSeconds: 1,
      rpm: 60,
      curve: curve,
      countTime: false,
      calorieMode: CalorieMode.pm5Standard,
      weightKg: 79,
    );
    expect(accumulator.snapshot.elapsedSeconds, before);
  });

  test('a stopped pedal stroke still adds the basal 300 kcal/h', () {
    final accumulator = SessionAccumulator();
    final curve = PowerCurve.level22Capture();
    for (var i = 0; i < 40; i++) {
      accumulator.tick(
        dtSeconds: 0.25,
        rpm: 0,
        curve: curve,
        countTime: true,
        calorieMode: CalorieMode.pm5Standard,
        weightKg: 79,
      );
    }
    final snapshot = accumulator.snapshot;
    expect(snapshot.watts, 0);
    expect(snapshot.distanceMeters, 0);
    expect(
      snapshot.calories,
      closeTo(Pm5Constants.basalKcalPerHour * 10 / 3600, 1e-9),
    );
    expect(snapshot.pm5AverageWatts, isNull);
    expect(snapshot.outOfCalibratedRange, isFalse);
  });
}
