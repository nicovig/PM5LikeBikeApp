import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pm5_bike/data/app_settings.dart';
import 'package:pm5_bike/data/ble_cadence_source.dart';
import 'package:pm5_bike/data/cadence_sample.dart';
import 'package:pm5_bike/data/cadence_source.dart';
import 'package:pm5_bike/data/session_repository.dart';
import 'package:pm5_bike/data/settings_repository.dart';
import 'package:pm5_bike/data/sim_cadence_source.dart';
import 'package:pm5_bike/data/workout_session.dart';

final settingsRepositoryProvider = Provider<SettingsRepository>(
  (ref) => SettingsRepository(),
);

final sessionRepositoryProvider = Provider<SessionRepository>(
  (ref) => SessionRepository(),
);

final settingsControllerProvider =
    AsyncNotifierProvider<SettingsController, AppSettings>(
      SettingsController.new,
    );

class SettingsController extends AsyncNotifier<AppSettings> {
  @override
  Future<AppSettings> build() {
    return ref.read(settingsRepositoryProvider).load();
  }

  Future<void> save(AppSettings settings) async {
    await ref.read(settingsRepositoryProvider).save(settings);
    if (!ref.mounted) {
      return;
    }
    state = AsyncData(settings);
  }
}

class CadenceStatus {
  const CadenceStatus({
    required this.sample,
    required this.scenarioRunning,
    required this.manualRpm,
    required this.sourceReady,
  });

  final CadenceSample sample;
  final bool scenarioRunning;
  final double manualRpm;
  final bool sourceReady;

  static CadenceStatus initial() {
    return CadenceStatus(
      sample: CadenceSample(
        at: DateTime.now(),
        rpm: 0,
        link: CadenceLinkState.disconnected,
      ),
      scenarioRunning: false,
      manualRpm: 0,
      sourceReady: false,
    );
  }
}

final cadenceHubProvider = NotifierProvider<CadenceHub, CadenceStatus>(
  CadenceHub.new,
);

class CadenceHub extends Notifier<CadenceStatus> {
  CadenceSource? _source;
  StreamSubscription<CadenceSample>? _subscription;
  AppSettings? _applied;
  var _generation = 0;
  var _disposed = false;

  SimCadenceSource? get simulation =>
      _source is SimCadenceSource ? _source as SimCadenceSource : null;

  BleCadenceSource? get bluetooth =>
      _source is BleCadenceSource ? _source as BleCadenceSource : null;

  @override
  CadenceStatus build() {
    ref.onDispose(_dispose);
    ref.listen(settingsControllerProvider, (previous, next) {
      final settings = next.value;
      if (settings != null) {
        unawaited(_apply(settings));
      }
    }, fireImmediately: true);
    return CadenceStatus.initial();
  }

  void setManualRpm(double rpm) {
    simulation?.setManualRpm(rpm);
  }

  void toggleScenario() {
    final source = simulation;
    if (source == null) {
      return;
    }
    if (source.scenarioRunning) {
      source.stopScenario();
    } else {
      source.startScenario();
    }
  }

  Future<void> _apply(AppSettings settings) async {
    if (_keepsSource(settings)) {
      _applied = settings;
      return;
    }
    final generation = ++_generation;
    await Future<void>.delayed(Duration.zero);
    if (_disposed || generation != _generation || !ref.mounted) {
      return;
    }
    await _subscription?.cancel();
    final previous = _source;
    _source = null;
    await previous?.stop();
    if (_disposed || generation != _generation || !ref.mounted) {
      return;
    }
    final source = _create(settings);
    _source = source;
    _applied = settings;
    _subscription = source.samples.listen(_onSample);
    await source.start();
  }

  bool _keepsSource(AppSettings next) {
    final previous = _applied;
    if (previous == null || _source == null) {
      return false;
    }
    if (previous.cadenceSource != next.cadenceSource) {
      return false;
    }
    if (next.cadenceSource == CadenceSourceKind.ble &&
        previous.bleDeviceId != next.bleDeviceId) {
      return false;
    }
    return true;
  }

  CadenceSource _create(AppSettings settings) {
    if (settings.cadenceSource == CadenceSourceKind.ble) {
      return BleCadenceSource(
        preferredDeviceId: settings.bleDeviceId,
        preferredDeviceName: settings.bleDeviceName,
      );
    }
    return SimCadenceSource();
  }

  void _onSample(CadenceSample sample) {
    if (_disposed || !ref.mounted) {
      return;
    }
    final source = simulation;
    state = CadenceStatus(
      sample: sample,
      scenarioRunning: source?.scenarioRunning ?? false,
      manualRpm: source?.manualRpm ?? 0,
      sourceReady: true,
    );
  }

  void _dispose() {
    _disposed = true;
    _generation++;
    _subscription?.cancel();
    final source = _source;
    _source = null;
    unawaited(source?.stop());
  }
}

final historyProvider =
    AsyncNotifierProvider<HistoryController, List<WorkoutSession>>(
      HistoryController.new,
    );

class HistoryController extends AsyncNotifier<List<WorkoutSession>> {
  @override
  Future<List<WorkoutSession>> build() {
    return ref.read(sessionRepositoryProvider).list();
  }

  Future<void> delete(String id) async {
    await ref.read(sessionRepositoryProvider).delete(id);
    if (!ref.mounted) {
      return;
    }
    ref.invalidateSelf();
  }
}
