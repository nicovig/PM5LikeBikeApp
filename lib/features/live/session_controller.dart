import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pm5_bike/core/moving_average.dart';
import 'package:pm5_bike/core/pm5_constants.dart';
import 'package:pm5_bike/core/pm5_metrics.dart';
import 'package:pm5_bike/core/power_curve.dart';
import 'package:pm5_bike/core/session_accumulator.dart';
import 'package:pm5_bike/core/workout_plan.dart';
import 'package:pm5_bike/data/app_settings.dart';
import 'package:pm5_bike/data/cadence_sample.dart';
import 'package:pm5_bike/data/workout_session.dart';
import 'package:pm5_bike/features/app_providers.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

class SessionState {
  const SessionState({
    required this.running,
    required this.userPaused,
    required this.linkDown,
    required this.level,
    required this.metrics,
    required this.plan,
    required this.guide,
  });

  final bool running;
  final bool userPaused;
  final bool linkDown;
  final int level;
  final SessionSnapshot metrics;
  final WorkoutPlan? plan;
  final WorkoutProgress? guide;

  factory SessionState.idle() {
    return const SessionState(
      running: false,
      userPaused: false,
      linkDown: false,
      level: Pm5Constants.defaultResistanceLevel,
      metrics: SessionSnapshot.empty,
      plan: null,
      guide: null,
    );
  }
}

final sessionControllerProvider =
    NotifierProvider<SessionController, SessionState>(SessionController.new);

class SessionController extends Notifier<SessionState> {
  final _accumulator = SessionAccumulator();
  final _smoother = MovingAverage(
    window: Duration(
      milliseconds: (Pm5Constants.defaultSmoothingSeconds * 1000).round(),
    ),
  );
  Timer? _timer;
  DateTime _lastTick = DateTime.now();
  DateTime? _startedAt;
  WorkoutPlan? _plan;
  WorkoutGuide? _guide;
  var _planReady = false;
  var _running = false;
  var _userPaused = false;
  var _disposed = false;

  @override
  SessionState build() {
    ref.onDispose(() {
      _disposed = true;
      _timer?.cancel();
      unawaited(_setAwake(false));
    });
    _timer ??= Timer.periodic(Pm5Constants.metricTickInterval, (_) => _tick());
    _ensurePlan();
    ref.listen(settingsControllerProvider, (previous, next) {
      if (_planReady) {
        return;
      }
      final hadPlan = _plan;
      _ensurePlan();
      if (_planReady && _plan != hadPlan) {
        _tick();
      }
    });
    return _published(linkDown: false);
  }

  void setPlan(WorkoutPlan? plan) {
    if (_running) {
      return;
    }
    _planReady = true;
    if (plan != null && plan.isUsable) {
      _plan = plan;
      _guide = WorkoutGuide(plan);
    } else {
      _plan = null;
      _guide = null;
    }
    final settings = ref.read(settingsControllerProvider).value;
    if (settings != null) {
      unawaited(_persist(settings.copyWith(workoutPlan: _plan)));
    }
    _tick();
  }

  void start() {
    _accumulator.reset();
    _guide?.reset();
    _running = true;
    _userPaused = false;
    _startedAt = DateTime.now();
    _lastTick = DateTime.now();
    unawaited(_setAwake(true));
    _tick();
  }

  void pause() {
    if (!_running || _userPaused) {
      return;
    }
    _userPaused = true;
    _lastTick = DateTime.now();
    _tick();
  }

  void resume() {
    if (!_running || !_userPaused) {
      return;
    }
    _userPaused = false;
    _lastTick = DateTime.now();
    _tick();
  }

  void discard() {
    _running = false;
    _userPaused = false;
    _startedAt = null;
    _accumulator.reset();
    _guide?.reset();
    _lastTick = DateTime.now();
    unawaited(_setAwake(false));
    _tick();
  }

  Future<void> finish() async {
    final snapshot = _accumulator.snapshot;
    final startedAt = _startedAt;
    if (snapshot.elapsedSeconds < 1 || startedAt == null) {
      discard();
      return;
    }
    final settings = ref.read(settingsControllerProvider).value;
    final session = WorkoutSession(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      startedAt: startedAt,
      endedAt: DateTime.now(),
      elapsedSeconds: snapshot.elapsedSeconds,
      distanceMeters: snapshot.distanceMeters,
      averageWatts: snapshot.averageWatts,
      pm5AverageWatts: snapshot.pm5AverageWatts,
      calories: snapshot.calories,
      averageRpm: snapshot.averageRpm,
      level: settings?.activeLevel ?? Pm5Constants.defaultResistanceLevel,
      hadOutOfRange: snapshot.hadOutOfRange,
      outOfRangeSeconds: snapshot.outOfRangeSeconds,
      samples: _accumulator.samples,
    );
    await ref.read(sessionRepositoryProvider).insert(session);
    if (!ref.mounted) {
      return;
    }
    discard();
    ref.invalidate(historyProvider);
  }

  void _tick() {
    if (_disposed || !ref.mounted) {
      return;
    }
    _ensurePlan();
    final now = DateTime.now();
    final dt = now.difference(_lastTick).inMicroseconds / 1e6;
    _lastTick = now;

    final settings = ref.read(settingsControllerProvider).value;
    final cadence = ref.read(cadenceHubProvider);
    final sensorDown =
        cadence.sample.link == CadenceLinkState.disconnected ||
        cadence.sample.link == CadenceLinkState.connecting;
    final holdClock = !cadence.sourceReady || sensorDown;

    if (settings != null) {
      _smoother.window = Duration(
        milliseconds: (settings.smoothingSeconds * 1000).round(),
      );
    }

    var rpm = 0.0;
    if (holdClock) {
      _smoother.clear();
    } else {
      final sanitized = Pm5Metrics.sanitizeCadenceRpm(cadence.sample.rpm);
      if (sanitized != null) {
        _smoother.add(now, sanitized);
      }
      rpm = _smoother.valueAt(now) ?? 0;
    }

    _accumulator.tick(
      dtSeconds: dt,
      rpm: rpm,
      curve: settings?.activeCurve ?? PowerCurve.fromPoints(const []),
      countTime: _running && !_userPaused && !holdClock,
      calorieMode: settings?.calorieMode ?? CalorieMode.pm5Standard,
      weightKg: settings?.weightKg ?? Pm5Constants.pm5ReferenceWeightKg,
    );

    state = _published(
      linkDown: _running && cadence.sourceReady && sensorDown,
      level: settings?.activeLevel ?? Pm5Constants.defaultResistanceLevel,
    );
  }

  void _ensurePlan() {
    if (_planReady) {
      return;
    }
    final settings = ref.read(settingsControllerProvider).value;
    if (settings == null) {
      return;
    }
    _planReady = true;
    final saved = settings.workoutPlan;
    if (saved != null && saved.isUsable) {
      _plan = saved;
      _guide = WorkoutGuide(saved);
    }
  }

  SessionState _published({required bool linkDown, int? level}) {
    final settings = ref.read(settingsControllerProvider).value;
    return SessionState(
      running: _running,
      userPaused: _userPaused,
      linkDown: linkDown,
      level:
          level ?? settings?.activeLevel ?? Pm5Constants.defaultResistanceLevel,
      metrics: _accumulator.snapshot,
      plan: _plan,
      guide: _liveGuide(),
    );
  }

  WorkoutProgress? _liveGuide() {
    if (!_running) {
      return null;
    }
    final guide = _guide;
    if (guide == null) {
      return null;
    }
    final metrics = _accumulator.snapshot;
    return guide.progress(
      elapsedSeconds: metrics.elapsedSeconds,
      distanceMeters: metrics.distanceMeters,
      calories: metrics.calories,
      watts: metrics.watts,
    );
  }

  Future<void> _persist(AppSettings settings) async {
    try {
      await ref.read(settingsControllerProvider.notifier).save(settings);
    } catch (_) {
      return;
    }
  }

  Future<void> _setAwake(bool enabled) async {
    try {
      if (enabled) {
        await WakelockPlus.enable();
      } else {
        await WakelockPlus.disable();
      }
    } on MissingPluginException {
      return;
    } on PlatformException {
      return;
    }
  }
}
