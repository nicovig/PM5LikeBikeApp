/// Named constants from SPEC.md. Business code reads them from here.
abstract final class Pm5Constants {
  /// SPEC §5.2. BikeErg power from pace: P = 0.35 / (seconds per meter)³.
  ///
  /// The rower formula is 2.80 / pace³. BikeErg speed is twice the RowErg at
  /// the same power, so the numerator is 2.80 / 2³.
  static const double pacePowerNumerator = 0.35;

  /// SPEC §5.2. v (m/s) = 1.419 × P^(1/3).
  static const double speedMetersPerSecondFactor = 1.419;

  /// SPEC §5.2. v (km/h) = 5.108 × P^(1/3).
  static const double speedKilometersPerHourFactor = 5.108;

  /// SPEC §5.4. kcal/h from mechanical watts: 4 × 0.8604.
  static const double wattsToKcalPerHour = 3.4416;

  /// SPEC §5.4. Basal metabolism the PM5 adds continuously, including at rest.
  /// Calibrated for about 175 lb, which the spec rounds to 79 kg.
  static const double basalKcalPerHour = 300;

  /// SPEC §5.4. Personal-weight term, per pound of body mass.
  /// The spec also writes this as about 3.78 kcal/h per kg (1.714 × lb/kg).
  static const double kcalPerHourPerPound = 1.714;

  /// Pounds in one kilogram. Kept so the 1.714 lb term is the only calorie factor.
  static const double poundsPerKilogram = 2.2046226218;

  /// SPEC §5.4. Body mass shown for the stock PM5 calorie mode.
  static const double pm5ReferenceWeightKg = 79;

  /// SPEC §3. CSC event timestamps use a 1/1024 s unit.
  static const int cscTimeTicksPerSecond = 1024;

  /// SPEC §3. No new crank event for this long means pedaling has stopped.
  static const Duration cadenceStopTimeout = Duration(seconds: 2);

  /// SPEC §7.4. Faster readings are treated as a sensor glitch and dropped.
  static const double maxPlausibleRpm = 200;

  /// SPEC §4. Published fit of the illustrative 60–90 RPM example.
  /// The stored level-22 curve comes from the SPEC §6 capture, not from these.
  static const double examplePowerCoefficientA = 0.274;

  /// SPEC §4. Published exponent of the illustrative example.
  static const double examplePowerExponentB = 1.54;

  /// SPEC §2 and §7.1. Resistance level the rider uses on the Moovyoo.
  static const int defaultResistanceLevel = 22;

  /// SPEC §6. Captured (RPM, watts) pairs at level 22.
  static const List<(double, double)> defaultLevel22Points = [
    (40, 105),
    (50, 152),
    (60, 200),
    (70, 256),
    (80, 305),
    (90, 347),
    (100, 393),
  ];

  /// SPEC §5.6. Default moving-average window until a step test says otherwise.
  static const double defaultSmoothingSeconds = 2;

  /// Upper bound of the settings slider. SPEC §5.6 suggests a few seconds.
  static const double maxSmoothingSeconds = 5;

  /// SPEC §7.1. Integration rate of the live metrics.
  static const Duration metricTickInterval = Duration(milliseconds: 250);

  /// A stalled frame must not invent a long stretch of steady pedaling.
  static const double maxTickSeconds = 1;

  /// Above this mean absolute percentage error, RPM → watts uses linear
  /// interpolation instead of the power law. The SPEC §4 example is near 6%.
  static const double powerLawMaxMeanAbsolutePercentageError = 0.10;

  /// Slider ceiling in simulation. Above the level-22 capture, below the glitch filter.
  static const double simControlMaxRpm = 130;

  static const double minBodyWeightKg = 40;
  static const double maxBodyWeightKg = 150;
  static const int minResistanceLevel = 1;
  static const int maxResistanceLevel = 32;

  static const double wattTargetRelativeBand = 0.05;
  static const double wattTargetMinimumBandWatts = 8;
  static const int maxWorkoutSteps = 8;
  static const int maxWorkoutRepeats = 40;
  static const double maxWorkoutTargetWatts = 2000;
  static const double maxWorkoutStepSeconds = 6 * 3600;
  static const double maxWorkoutStepMeters = 200000;
  static const double maxWorkoutStepKilocalories = 5000;
}
