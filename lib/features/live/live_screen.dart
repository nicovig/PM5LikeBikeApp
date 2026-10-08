import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pm5_bike/core/metric_format.dart';
import 'package:pm5_bike/core/pm5_constants.dart';
import 'package:pm5_bike/core/session_accumulator.dart';
import 'package:pm5_bike/data/app_settings.dart';
import 'package:pm5_bike/data/cadence_sample.dart';
import 'package:pm5_bike/features/app_providers.dart';
import 'package:pm5_bike/features/live/session_controller.dart';
import 'package:pm5_bike/features/live/workout_bar.dart';
import 'package:pm5_bike/features/live/workout_sheet.dart';
import 'package:pm5_bike/features/shared/pm5_colors.dart';

class LiveScreen extends ConsumerWidget {
  const LiveScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionControllerProvider);
    final cadence = ref.watch(cadenceHubProvider);
    final settings = ref.watch(settingsControllerProvider).value;
    final controller = ref.read(sessionControllerProvider.notifier);
    final hub = ref.read(cadenceHubProvider.notifier);
    return _LiveBody(
      session: session,
      cadence: cadence,
      simulated: settings?.cadenceSource == CadenceSourceKind.simulation,
      onStart: controller.start,
      onPause: controller.pause,
      onResume: controller.resume,
      onFinish: () => _finish(context, ref),
      onEditPlan: session.running ? null : () => _editPlan(context, ref),
      onManualRpm: hub.setManualRpm,
      onToggleScenario: hub.toggleScenario,
    );
  }

  Future<void> _editPlan(BuildContext context, WidgetRef ref) async {
    final current = ref.read(sessionControllerProvider).plan;
    final result = await showWorkoutEditor(context, current);
    if (result == null || !context.mounted) {
      return;
    }
    ref.read(sessionControllerProvider.notifier).setPlan(result.plan);
  }

  Future<void> _finish(BuildContext context, WidgetRef ref) async {
    final elapsed = ref.read(sessionControllerProvider).metrics.elapsedSeconds;
    final controller = ref.read(sessionControllerProvider.notifier);
    if (elapsed < 1) {
      controller.discard();
      _snack(context, 'Séance trop courte pour être enregistrée.');
      return;
    }
    final choice = await showDialog<_FinishChoice>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Terminer la séance'),
        content: const Text('Enregistrer cette séance dans l’historique ?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, _FinishChoice.cancel),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, _FinishChoice.discard),
            child: const Text('Abandonner'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, _FinishChoice.save),
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );
    if (choice == null || choice == _FinishChoice.cancel) {
      return;
    }
    if (choice == _FinishChoice.discard) {
      controller.discard();
      return;
    }
    try {
      await controller.finish();
    } catch (_) {
      if (context.mounted) {
        _snack(context, 'Enregistrement impossible.');
      }
      return;
    }
    if (context.mounted) {
      _snack(context, 'Séance enregistrée.');
    }
  }

  void _snack(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }
}

enum _FinishChoice { cancel, discard, save }

class _LiveBody extends StatelessWidget {
  const _LiveBody({
    required this.session,
    required this.cadence,
    required this.simulated,
    required this.onStart,
    required this.onPause,
    required this.onResume,
    required this.onFinish,
    required this.onEditPlan,
    required this.onManualRpm,
    required this.onToggleScenario,
  });

  final SessionState session;
  final CadenceStatus cadence;
  final bool simulated;
  final VoidCallback onStart;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onFinish;
  final VoidCallback? onEditPlan;
  final ValueChanged<double> onManualRpm;
  final VoidCallback onToggleScenario;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final landscape = constraints.maxWidth > constraints.maxHeight + 80;
        final header = _Header(session: session, cadence: cadence);
        final watts = _WattsReadout(session: session, onEditPlan: onEditPlan);
        final metrics = _MetricGrid(metrics: session.metrics);
        final banner = _Banner(session: session);
        final simulator = simulated
            ? _SimulatorControls(
                cadence: cadence,
                onManualRpm: onManualRpm,
                onToggleScenario: onToggleScenario,
              )
            : const SizedBox.shrink();
        final buttons = _SessionButtons(
          running: session.running,
          paused: session.userPaused,
          onStart: onStart,
          onPause: onPause,
          onResume: onResume,
          onFinish: onFinish,
        );
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: landscape
                ? Row(
                    children: [
                      Expanded(
                        child: Column(
                          children: [
                            header,
                            const SizedBox(height: 8),
                            Expanded(child: watts),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          children: [
                            Expanded(
                              child: ListView(
                                children: [metrics, banner, simulator],
                              ),
                            ),
                            const SizedBox(height: 8),
                            buttons,
                          ],
                        ),
                      ),
                    ],
                  )
                : Column(
                    children: [
                      header,
                      const SizedBox(height: 4),
                      Expanded(child: watts),
                      metrics,
                      banner,
                      simulator,
                      const SizedBox(height: 8),
                      buttons,
                    ],
                  ),
          ),
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.session, required this.cadence});

  final SessionState session;
  final CadenceStatus cadence;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          'Niveau ${session.level}',
          style: const TextStyle(color: Pm5Colors.muted, fontSize: 14),
        ),
        const Spacer(),
        if (session.userPaused)
          const Padding(
            padding: EdgeInsets.only(right: 12),
            child: Text(
              'PAUSE',
              style: TextStyle(
                color: Pm5Colors.warning,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
              ),
            ),
          ),
        Flexible(
          child: Text(
            _linkLabel(cadence),
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Pm5Colors.muted, fontSize: 14),
          ),
        ),
      ],
    );
  }

  String _linkLabel(CadenceStatus status) {
    if (!status.sourceReady) {
      return 'Préparation…';
    }
    final detail = status.sample.detail;
    switch (status.sample.link) {
      case CadenceLinkState.simulated:
        return status.scenarioRunning ? 'Scénario' : 'Simulation';
      case CadenceLinkState.connecting:
        return detail ?? 'Connexion…';
      case CadenceLinkState.connected:
        return detail ?? 'Connecté';
      case CadenceLinkState.disconnected:
        return detail ?? 'Déconnecté';
    }
  }
}

class _WattsReadout extends StatelessWidget {
  const _WattsReadout({required this.session, required this.onEditPlan});

  final SessionState session;
  final VoidCallback? onEditPlan;

  @override
  Widget build(BuildContext context) {
    final metrics = session.metrics;
    final duration = formatDuration(metrics.elapsedSeconds);
    final watts = formatWatts(metrics.watts);
    final accent = workoutWattsAccent(session);
    final color = metrics.outOfCalibratedRange
        ? Pm5Colors.warning
        : accent ?? Pm5Colors.text;
    final guided = session.running && session.guide != null;
    return Column(
      children: [
        Text(
          duration,
          style: TextStyle(
            fontSize: guided ? 20 : 28,
            fontFeatures: const [FontFeature.tabularFigures()],
            color: Pm5Colors.text,
          ),
        ),
        const Text(
          'DURÉE',
          style: TextStyle(
            color: Pm5Colors.muted,
            fontSize: 11,
            letterSpacing: 1.4,
          ),
        ),
        const SizedBox(height: 8),
        WorkoutBar(session: session, onEdit: onEditPlan),
        Expanded(
          child: Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Semantics(
                label: '$watts watts',
                child: Text(
                  watts,
                  style: TextStyle(
                    fontSize: 120,
                    height: 0.9,
                    fontWeight: FontWeight.w200,
                    color: color,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ),
          ),
        ),
        const Text(
          'WATTS',
          style: TextStyle(
            color: Pm5Colors.muted,
            fontSize: 13,
            letterSpacing: 2,
          ),
        ),
      ],
    );
  }
}

class _MetricGrid extends StatelessWidget {
  const _MetricGrid({required this.metrics});

  final SessionSnapshot metrics;

  @override
  Widget build(BuildContext context) {
    final elapsed = metrics.elapsedSeconds > 0;
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _Tile(
                label: 'Cadence',
                value: formatRpm(metrics.rpm),
                unit: 'rpm',
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _Tile(
                label: 'Vitesse',
                value: formatSpeed(metrics.speedKilometersPerHour),
                unit: 'km/h',
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _Tile(
                label: 'Distance',
                value: formatDistance(metrics.distanceMeters),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _Tile(
                label: 'Allure /1000 m',
                value: formatPace(metrics.pacePer1000MetersSeconds),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _Tile(
                label: 'Calories',
                value: formatKcal(metrics.calories),
                unit: 'kcal',
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _Tile(
                label: 'Moyenne réelle',
                value: formatAverageWatts(
                  metrics.averageWatts,
                  available: elapsed,
                ),
                unit: 'W',
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _Tile(
          label: 'Moyenne PM5',
          value: formatAverageWatts(
            metrics.pm5AverageWatts,
            available: elapsed,
          ),
          unit: 'W',
        ),
      ],
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.label, required this.value, this.unit});

  final String label;
  final String value;
  final String? unit;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Pm5Colors.panel,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(color: Pm5Colors.muted, fontSize: 12),
            ),
            const SizedBox(height: 2),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Row(
                children: [
                  Text(
                    value,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w500,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                  if (unit != null) ...[
                    const SizedBox(width: 4),
                    Text(
                      unit!,
                      style: const TextStyle(
                        color: Pm5Colors.muted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.session});

  final SessionState session;

  @override
  Widget build(BuildContext context) {
    final metrics = session.metrics;
    String? message;
    if (session.linkDown) {
      message = 'Capteur perdu — chrono suspendu';
    } else if (metrics.missingCalibration && metrics.rpm > 0) {
      message = 'Pas de calibration pour le niveau ${session.level}';
    } else if (metrics.outOfCalibratedRange) {
      final min = metrics.calibratedMinRpm?.round();
      final max = metrics.calibratedMaxRpm?.round();
      message = 'Hors plage calibrée ($min–$max RPM)';
    }
    if (message == null) {
      return const SizedBox(height: 8);
    }
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xFF2A2114),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              const Icon(
                Icons.warning_amber_rounded,
                color: Pm5Colors.warning,
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(
                    color: Pm5Colors.warning,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SimulatorControls extends StatelessWidget {
  const _SimulatorControls({
    required this.cadence,
    required this.onManualRpm,
    required this.onToggleScenario,
  });

  final CadenceStatus cadence;
  final ValueChanged<double> onManualRpm;
  final VoidCallback onToggleScenario;

  @override
  Widget build(BuildContext context) {
    final value = cadence.manualRpm
        .clamp(0, Pm5Constants.simControlMaxRpm)
        .toDouble();
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Column(
        children: [
          Row(
            children: [
              const Text('Consigne', style: TextStyle(color: Pm5Colors.muted)),
              const Spacer(),
              Text('${value.round()} RPM'),
              const SizedBox(width: 8),
              TextButton(
                onPressed: onToggleScenario,
                child: Text(
                  cadence.scenarioRunning ? 'Arrêter le scénario' : 'Scénario',
                ),
              ),
            ],
          ),
          Slider(
            min: 0,
            max: Pm5Constants.simControlMaxRpm,
            divisions: Pm5Constants.simControlMaxRpm.round(),
            value: value,
            onChanged: cadence.scenarioRunning ? null : onManualRpm,
          ),
        ],
      ),
    );
  }
}

class _SessionButtons extends StatelessWidget {
  const _SessionButtons({
    required this.running,
    required this.paused,
    required this.onStart,
    required this.onPause,
    required this.onResume,
    required this.onFinish,
  });

  final bool running;
  final bool paused;
  final VoidCallback onStart;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onFinish;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: FilledButton(
            onPressed: running ? null : onStart,
            child: const Text('Démarrer'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton(
            onPressed: !running
                ? null
                : paused
                ? onResume
                : onPause,
            child: Text(paused ? 'Reprendre' : 'Pause'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton(
            onPressed: running ? onFinish : null,
            child: const Text('Terminer'),
          ),
        ),
      ],
    );
  }
}
