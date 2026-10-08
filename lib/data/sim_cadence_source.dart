import 'dart:async';

import 'package:pm5_bike/core/pm5_constants.dart';
import 'package:pm5_bike/data/cadence_sample.dart';
import 'package:pm5_bike/data/cadence_source.dart';

class SimCadenceSource implements CadenceSource {
  final _samples = StreamController<CadenceSample>.broadcast();
  Timer? _timer;
  double _manualRpm = 0;
  bool _scenarioRunning = false;
  DateTime? _scenarioStarted;

  static const _scenario = <(double, double)>[
    (0, 0),
    (10, 70),
    (22, 75),
    (32, 92),
    (42, 58),
    (50, 84),
    (54, 0),
    (62, 0),
    (74, 88),
    (90, 66),
  ];

  double get manualRpm => _manualRpm;

  bool get scenarioRunning => _scenarioRunning;

  @override
  Stream<CadenceSample> get samples => _samples.stream;

  @override
  Future<void> start() async {
    if (_timer != null) {
      return;
    }
    _emit();
    _timer = Timer.periodic(Pm5Constants.metricTickInterval, (_) => _emit());
  }

  @override
  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    _scenarioRunning = false;
    if (!_samples.isClosed) {
      await _samples.close();
    }
  }

  void setManualRpm(double rpm) {
    _scenarioRunning = false;
    _scenarioStarted = null;
    _manualRpm = rpm.clamp(0, Pm5Constants.simControlMaxRpm).toDouble();
    _emit();
  }

  void startScenario() {
    _scenarioRunning = true;
    _scenarioStarted = DateTime.now();
    _emit();
  }

  void stopScenario() {
    _scenarioRunning = false;
    _scenarioStarted = null;
    _emit();
  }

  void _emit() {
    if (_samples.isClosed) {
      return;
    }
    _samples.add(
      CadenceSample(
        at: DateTime.now(),
        rpm: _currentRpm(DateTime.now()),
        link: CadenceLinkState.simulated,
      ),
    );
  }

  double _currentRpm(DateTime now) {
    if (!_scenarioRunning) {
      return _manualRpm;
    }
    final started = _scenarioStarted;
    if (started == null) {
      return _manualRpm;
    }
    final elapsed = now.difference(started).inMicroseconds / 1e6;
    if (elapsed >= _scenario.last.$1) {
      _scenarioRunning = false;
      _scenarioStarted = null;
      _manualRpm = _scenario.last.$2;
      return _manualRpm;
    }
    return _rpmAt(elapsed);
  }

  double _rpmAt(double elapsed) {
    if (elapsed <= _scenario.first.$1) {
      return _scenario.first.$2;
    }
    for (var i = 1; i < _scenario.length; i++) {
      final right = _scenario[i];
      if (elapsed <= right.$1) {
        final left = _scenario[i - 1];
        final span = right.$1 - left.$1;
        if (span <= 0) {
          return right.$2;
        }
        final t = (elapsed - left.$1) / span;
        return left.$2 + t * (right.$2 - left.$2);
      }
    }
    return _scenario.last.$2;
  }
}
