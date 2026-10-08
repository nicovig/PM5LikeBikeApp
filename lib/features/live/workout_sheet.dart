import 'package:flutter/material.dart';
import 'package:pm5_bike/core/pm5_constants.dart';
import 'package:pm5_bike/core/workout_plan.dart';
import 'package:pm5_bike/features/shared/pm5_colors.dart';

class WorkoutEditorResult {
  const WorkoutEditorResult(this.plan);

  final WorkoutPlan? plan;
}

Future<WorkoutEditorResult?> showWorkoutEditor(
  BuildContext context,
  WorkoutPlan? current,
) {
  return showModalBottomSheet<WorkoutEditorResult>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Pm5Colors.panel,
    builder: (context) {
      final media = MediaQuery.of(context);
      final bottom = media.viewInsets.bottom;
      final height = (media.size.height - media.padding.top - bottom) * 0.92;
      return Padding(
        padding: EdgeInsets.only(bottom: bottom),
        child: SizedBox(
          height: height,
          child: _WorkoutEditor(initial: current),
        ),
      );
    },
  );
}

enum _Intensity { open, watts, recovery }

class _DraftStep {
  _DraftStep({
    this.goal = WorkoutGoal.duration,
    this.intensity = _Intensity.open,
    String minutes = '2',
    String seconds = '00',
    String amount = '1000',
    String watts = '',
  }) : minutes = TextEditingController(text: minutes),
       seconds = TextEditingController(text: seconds),
       amount = TextEditingController(text: amount),
       watts = TextEditingController(text: watts);

  factory _DraftStep.fromStep(WorkoutStep step) {
    final intensity = step.recovery
        ? _Intensity.recovery
        : step.hasWattTarget
        ? _Intensity.watts
        : _Intensity.open;
    final watts = step.targetWatts == null
        ? ''
        : step.targetWatts!.round().toString();
    if (step.goal == WorkoutGoal.duration) {
      final total = step.amount.round();
      return _DraftStep(
        goal: step.goal,
        intensity: intensity,
        minutes: '${total ~/ 60}',
        seconds: (total % 60).toString().padLeft(2, '0'),
        watts: watts,
      );
    }
    final amount = step.amount == step.amount.roundToDouble()
        ? step.amount.round().toString()
        : step.amount.toString().replaceAll('.', ',');
    return _DraftStep(
      goal: step.goal,
      intensity: intensity,
      amount: amount,
      watts: watts,
    );
  }

  WorkoutGoal goal;
  _Intensity intensity;
  final TextEditingController minutes;
  final TextEditingController seconds;
  final TextEditingController amount;
  final TextEditingController watts;

  void dispose() {
    minutes.dispose();
    seconds.dispose();
    amount.dispose();
    watts.dispose();
  }
}

class _WorkoutEditor extends StatefulWidget {
  const _WorkoutEditor({required this.initial});

  final WorkoutPlan? initial;

  @override
  State<_WorkoutEditor> createState() => _WorkoutEditorState();
}

class _WorkoutEditorState extends State<_WorkoutEditor> {
  late List<_DraftStep> _steps;
  late int _repeats;
  String? _error;
  final _retired = <_DraftStep>[];

  @override
  void initState() {
    super.initState();
    final plan = widget.initial;
    if (plan != null && plan.isUsable) {
      _repeats = plan.repeats;
      _steps = [for (final step in plan.steps) _DraftStep.fromStep(step)];
    } else {
      _repeats = 1;
      _steps = [_DraftStep()];
    }
  }

  @override
  void dispose() {
    for (final step in _steps) {
      step.dispose();
    }
    for (final step in _retired) {
      step.dispose();
    }
    super.dispose();
  }

  void _replace(List<_DraftStep> next, int repeats) {
    for (final step in _steps) {
      if (!next.contains(step)) {
        _retired.add(step);
      }
    }
    setState(() {
      _steps = next;
      _repeats = repeats;
      _error = null;
    });
  }

  void _presetWorkRecovery() {
    _replace([
      _DraftStep(intensity: _Intensity.watts),
      _DraftStep(intensity: _Intensity.recovery),
    ], 6);
  }

  void _presetTwoWatts() {
    _replace([
      _DraftStep(intensity: _Intensity.watts),
      _DraftStep(intensity: _Intensity.watts),
    ], 1);
  }

  void _presetDuration() {
    _replace([_DraftStep(minutes: '20', seconds: '00')], 1);
  }

  void _presetDistance() {
    _replace([
      _DraftStep(
        goal: WorkoutGoal.distance,
        amount: '2000',
        intensity: _Intensity.open,
      ),
    ], 1);
  }

  void _presetCalories() {
    _replace([
      _DraftStep(
        goal: WorkoutGoal.calories,
        amount: '200',
        intensity: _Intensity.open,
      ),
    ], 1);
  }

  void _addStep() {
    if (_steps.length >= Pm5Constants.maxWorkoutSteps) {
      return;
    }
    final last = _steps.last;
    _replace([
      ..._steps,
      _DraftStep(
        goal: last.goal,
        intensity: last.intensity,
        minutes: last.minutes.text,
        seconds: last.seconds.text,
        amount: last.amount.text,
      ),
    ], _repeats);
  }

  void _remove(int index) {
    if (_steps.length <= 1) {
      return;
    }
    _replace([
      for (var i = 0; i < _steps.length; i++)
        if (i != index) _steps[i],
    ], _repeats);
  }

  void _apply() {
    final plan = _tryBuild();
    if (plan == null) {
      setState(() {});
      return;
    }
    Navigator.pop(context, WorkoutEditorResult(plan));
  }

  WorkoutPlan? _tryBuild() {
    final steps = <WorkoutStep>[];
    for (final draft in _steps) {
      final amount = _amountOf(draft);
      if (amount == null) {
        _error = 'Chaque bloc doit avoir une valeur supérieure à zéro.';
        return null;
      }
      if (!_fits(draft.goal, amount)) {
        _error = 'Une des valeurs dépasse la limite.';
        return null;
      }
      double? watts;
      if (draft.intensity == _Intensity.watts) {
        final parsed = _parse(draft.watts.text);
        if (parsed == null || parsed <= 0) {
          _error = 'Indique le wattage de chaque bloc Watts.';
          return null;
        }
        if (parsed > Pm5Constants.maxWorkoutTargetWatts) {
          _error = 'Le wattage doit rester sous 2 000 W.';
          return null;
        }
        watts = parsed.roundToDouble();
      }
      steps.add(
        WorkoutStep(
          goal: draft.goal,
          amount: amount,
          targetWatts: watts,
          recovery: draft.intensity == _Intensity.recovery,
        ),
      );
    }
    _error = null;
    return WorkoutPlan(steps: steps, repeats: _repeats);
  }

  double? _amountOf(_DraftStep draft) {
    switch (draft.goal) {
      case WorkoutGoal.duration:
        final minutes = _parse(draft.minutes.text) ?? 0;
        final seconds = _parse(draft.seconds.text) ?? 0;
        if (minutes.isNaN || seconds.isNaN || minutes < 0 || seconds < 0) {
          return null;
        }
        final total = minutes * 60 + seconds;
        if (total <= 0) {
          return null;
        }
        return total;
      case WorkoutGoal.distance:
      case WorkoutGoal.calories:
        final amount = _parse(draft.amount.text);
        if (amount == null || amount.isNaN || amount <= 0) {
          return null;
        }
        return amount;
    }
  }

  bool _fits(WorkoutGoal goal, double amount) {
    return switch (goal) {
      WorkoutGoal.duration => amount <= Pm5Constants.maxWorkoutStepSeconds,
      WorkoutGoal.distance => amount <= Pm5Constants.maxWorkoutStepMeters,
      WorkoutGoal.calories => amount <= Pm5Constants.maxWorkoutStepKilocalories,
    };
  }

  double? _parse(String raw) {
    final text = raw.trim().replaceAll(',', '.');
    if (text.isEmpty) {
      return null;
    }
    return double.tryParse(text);
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + bottom),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Séance',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                ),
              ),
              TextButton(
                onPressed: () =>
                    Navigator.pop(context, const WorkoutEditorResult(null)),
                child: const Text('Libre'),
              ),
            ],
          ),
          const Text(
            'Après l’objectif, la séance continue jusqu’à Terminer.',
            style: TextStyle(color: Pm5Colors.muted, fontSize: 13),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _Preset('6 × 2 min + récup', _presetWorkRecovery),
              _Preset('2 min + 2 min', _presetTwoWatts),
              _Preset('20 min', _presetDuration),
              _Preset('2 000 m', _presetDistance),
              _Preset('200 kcal', _presetCalories),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Text('Répétitions'),
              const Spacer(),
              IconButton(
                onPressed: _repeats > 1
                    ? () => setState(() => _repeats -= 1)
                    : null,
                icon: const Icon(Icons.remove),
              ),
              Text(
                '$_repeats',
                style: const TextStyle(
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
              IconButton(
                onPressed: _repeats < Pm5Constants.maxWorkoutRepeats
                    ? () => setState(() => _repeats += 1)
                    : null,
                icon: const Icon(Icons.add),
              ),
            ],
          ),
          Expanded(
            child: ListView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              children: [
                for (var i = 0; i < _steps.length; i++)
                  _StepCard(
                    key: ObjectKey(_steps[i]),
                    index: i,
                    draft: _steps[i],
                    canRemove: _steps.length > 1,
                    onChanged: () => setState(() => _error = null),
                    onRemove: () => _remove(i),
                  ),
                if (_steps.length < Pm5Constants.maxWorkoutSteps)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: _addStep,
                      icon: const Icon(Icons.add),
                      label: const Text('Ajouter un bloc'),
                    ),
                  ),
              ],
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                _error!,
                style: const TextStyle(color: Pm5Colors.warning, fontSize: 13),
              ),
            ),
          FilledButton(onPressed: _apply, child: const Text('Utiliser')),
        ],
      ),
    );
  }
}

class _Preset extends StatelessWidget {
  const _Preset(this.label, this.onPressed);

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      visualDensity: VisualDensity.compact,
      label: Text(label, style: const TextStyle(fontSize: 13)),
      onPressed: onPressed,
    );
  }
}

class _StepCard extends StatelessWidget {
  const _StepCard({
    super.key,
    required this.index,
    required this.draft,
    required this.canRemove,
    required this.onChanged,
    required this.onRemove,
  });

  final int index;
  final _DraftStep draft;
  final bool canRemove;
  final VoidCallback onChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Pm5Colors.background,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 4, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Text(
                    'Bloc ${index + 1}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const Spacer(),
                  if (canRemove)
                    IconButton(
                      onPressed: onRemove,
                      icon: const Icon(Icons.close, size: 18),
                    ),
                ],
              ),
              SegmentedButton<WorkoutGoal>(
                showSelectedIcon: false,
                expandedInsets: EdgeInsets.zero,
                style: const ButtonStyle(
                  visualDensity: VisualDensity.compact,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                segments: const [
                  ButtonSegment(
                    value: WorkoutGoal.duration,
                    label: Text('Temps', style: TextStyle(fontSize: 12)),
                  ),
                  ButtonSegment(
                    value: WorkoutGoal.distance,
                    label: Text('Distance', style: TextStyle(fontSize: 12)),
                  ),
                  ButtonSegment(
                    value: WorkoutGoal.calories,
                    label: Text('Calories', style: TextStyle(fontSize: 12)),
                  ),
                ],
                selected: {draft.goal},
                onSelectionChanged: (value) {
                  draft.goal = value.first;
                  onChanged();
                },
              ),
              const SizedBox(height: 8),
              SegmentedButton<_Intensity>(
                showSelectedIcon: false,
                expandedInsets: EdgeInsets.zero,
                style: const ButtonStyle(
                  visualDensity: VisualDensity.compact,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                segments: const [
                  ButtonSegment(
                    value: _Intensity.open,
                    label: Text('Sans cible', style: TextStyle(fontSize: 12)),
                  ),
                  ButtonSegment(
                    value: _Intensity.watts,
                    label: Text('Watts', style: TextStyle(fontSize: 12)),
                  ),
                  ButtonSegment(
                    value: _Intensity.recovery,
                    label: Text('Récup', style: TextStyle(fontSize: 12)),
                  ),
                ],
                selected: {draft.intensity},
                onSelectionChanged: (value) {
                  draft.intensity = value.first;
                  onChanged();
                },
              ),
              const SizedBox(height: 8),
              if (draft.goal == WorkoutGoal.duration)
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: draft.minutes,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: _field('min'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: draft.seconds,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: _field('s'),
                      ),
                    ),
                  ],
                )
              else
                TextField(
                  controller: draft.amount,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: _field(
                    draft.goal == WorkoutGoal.distance ? 'm' : 'kcal',
                  ),
                ),
              if (draft.intensity == _Intensity.watts) ...[
                const SizedBox(height: 8),
                TextField(
                  key: ValueKey('step-watts-$index'),
                  controller: draft.watts,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: _field('W'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

InputDecoration _field(String suffix) {
  return InputDecoration(
    isDense: true,
    suffixText: suffix,
    filled: true,
    fillColor: Pm5Colors.panel,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide.none,
    ),
  );
}
