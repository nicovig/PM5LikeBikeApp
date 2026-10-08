import 'package:pm5_bike/core/pm5_constants.dart';

enum WorkoutGoal { duration, distance, calories }

class WorkoutStep {
  const WorkoutStep({
    required this.goal,
    required this.amount,
    this.targetWatts,
    this.recovery = false,
  });

  final WorkoutGoal goal;
  final double amount;
  final double? targetWatts;
  final bool recovery;

  bool get hasWattTarget => !recovery && targetWatts != null;

  Map<String, Object?> toJson() => {
    'goal': goal.name,
    'amount': amount,
    'targetWatts': recovery ? null : targetWatts,
    'recovery': recovery,
  };
}

class WorkoutPlan {
  const WorkoutPlan({required this.steps, this.repeats = 1});

  final List<WorkoutStep> steps;
  final int repeats;

  bool get isUsable {
    if (steps.isEmpty || steps.length > Pm5Constants.maxWorkoutSteps) {
      return false;
    }
    if (repeats < 1 || repeats > Pm5Constants.maxWorkoutRepeats) {
      return false;
    }
    for (final step in steps) {
      if (!_amountOk(step.goal, step.amount)) {
        return false;
      }
      final watts = step.targetWatts;
      if (watts != null &&
          (!watts.isFinite ||
              watts <= 0 ||
              watts > Pm5Constants.maxWorkoutTargetWatts)) {
        return false;
      }
    }
    return true;
  }

  int get stepCount => steps.length * repeats;

  double? get totalDurationSeconds {
    if (steps.isEmpty ||
        steps.any((step) => step.goal != WorkoutGoal.duration)) {
      return null;
    }
    var total = 0.0;
    for (final step in steps) {
      total += step.amount;
    }
    return total * repeats;
  }

  WorkoutStep? stepAt(int index) {
    if (steps.isEmpty || index < 0 || index >= stepCount) {
      return null;
    }
    return steps[index % steps.length];
  }

  Map<String, Object?> toJson() => {
    'repeats': repeats,
    'steps': [for (final step in steps) step.toJson()],
  };

  static WorkoutPlan? tryParse(Object? raw) {
    if (raw is! Map) {
      return null;
    }
    final stepsRaw = raw['steps'];
    if (stepsRaw is! List) {
      return null;
    }
    final steps = <WorkoutStep>[];
    for (final item in stepsRaw) {
      if (steps.length >= Pm5Constants.maxWorkoutSteps) {
        break;
      }
      final step = _stepFromJson(item);
      if (step != null) {
        steps.add(step);
      }
    }
    if (steps.isEmpty) {
      return null;
    }
    final repeatsRaw = raw['repeats'];
    var repeats = repeatsRaw is num ? repeatsRaw.round() : 1;
    if (repeats < 1) {
      return null;
    }
    if (repeats > Pm5Constants.maxWorkoutRepeats) {
      repeats = Pm5Constants.maxWorkoutRepeats;
    }
    final plan = WorkoutPlan(steps: steps, repeats: repeats);
    if (!plan.isUsable) {
      return null;
    }
    return plan;
  }
}

class WorkoutProgress {
  const WorkoutProgress({
    required this.repeatIndex,
    required this.repeatCount,
    required this.indexInRepeat,
    required this.stepsPerRepeat,
    required this.remaining,
    required this.fraction,
    required this.complete,
    required this.step,
    required this.onTarget,
    required this.wattsGap,
  });

  final int repeatIndex;
  final int repeatCount;
  final int indexInRepeat;
  final int stepsPerRepeat;
  final double remaining;
  final double fraction;
  final bool complete;
  final WorkoutStep? step;
  final bool? onTarget;
  final double? wattsGap;
}

class WorkoutGuide {
  WorkoutGuide(this.plan);

  final WorkoutPlan plan;
  var _cursor = _Cursor.start;

  void reset() {
    _cursor = _Cursor.start;
  }

  WorkoutProgress progress({
    required double elapsedSeconds,
    required double distanceMeters,
    required double calories,
    required double watts,
  }) {
    _cursor = _advance(_cursor, elapsedSeconds, distanceMeters, calories);
    return _read(_cursor, elapsedSeconds, distanceMeters, calories, watts);
  }

  _Cursor _advance(
    _Cursor cursor,
    double elapsed,
    double distance,
    double calories,
  ) {
    if (cursor.complete || plan.steps.isEmpty || plan.repeats < 1) {
      return _Cursor(
        stepIndex: cursor.stepIndex,
        stepStartElapsed: cursor.stepStartElapsed,
        stepStartDistance: cursor.stepStartDistance,
        stepStartCalories: cursor.stepStartCalories,
        complete: true,
      );
    }
    var current = cursor;
    final limit = plan.stepCount;
    for (var guard = 0; guard <= limit; guard++) {
      final step = plan.stepAt(current.stepIndex);
      if (step == null) {
        return _Cursor(
          stepIndex: current.stepIndex,
          stepStartElapsed: current.stepStartElapsed,
          stepStartDistance: current.stepStartDistance,
          stepStartCalories: current.stepStartCalories,
          complete: true,
        );
      }
      final consumed = _consumed(current, step, elapsed, distance, calories);
      if (consumed + 1e-9 < step.amount) {
        return current;
      }
      final nextIndex = current.stepIndex + 1;
      final next = _Cursor(
        stepIndex: nextIndex,
        stepStartElapsed: step.goal == WorkoutGoal.duration
            ? current.stepStartElapsed + step.amount
            : elapsed,
        stepStartDistance: step.goal == WorkoutGoal.distance
            ? current.stepStartDistance + step.amount
            : distance,
        stepStartCalories: step.goal == WorkoutGoal.calories
            ? current.stepStartCalories + step.amount
            : calories,
        complete: nextIndex >= limit,
      );
      if (next.complete) {
        return next;
      }
      current = next;
    }
    return current;
  }

  WorkoutProgress _read(
    _Cursor cursor,
    double elapsed,
    double distance,
    double calories,
    double watts,
  ) {
    final steps = plan.steps.length;
    if (cursor.complete || steps == 0) {
      return WorkoutProgress(
        repeatIndex: plan.repeats,
        repeatCount: plan.repeats,
        indexInRepeat: steps,
        stepsPerRepeat: steps,
        remaining: 0,
        fraction: 1,
        complete: true,
        step: null,
        onTarget: null,
        wattsGap: null,
      );
    }
    final step = plan.stepAt(cursor.stepIndex)!;
    final consumed = _consumed(cursor, step, elapsed, distance, calories);
    final remaining = consumed >= step.amount ? 0.0 : step.amount - consumed;
    var fraction = step.amount <= 0 ? 1.0 : consumed / step.amount;
    if (fraction < 0) {
      fraction = 0;
    } else if (fraction > 1) {
      fraction = 1;
    }
    final target = step.hasWattTarget ? step.targetWatts : null;
    bool? onTarget;
    double? gap;
    if (target != null && watts.isFinite) {
      gap = watts - target;
      onTarget = gap.abs() <= _wattBand(target);
    }
    return WorkoutProgress(
      repeatIndex: cursor.stepIndex ~/ steps + 1,
      repeatCount: plan.repeats,
      indexInRepeat: cursor.stepIndex % steps + 1,
      stepsPerRepeat: steps,
      remaining: remaining,
      fraction: fraction,
      complete: false,
      step: step,
      onTarget: onTarget,
      wattsGap: gap,
    );
  }
}

class _Cursor {
  const _Cursor({
    required this.stepIndex,
    required this.stepStartElapsed,
    required this.stepStartDistance,
    required this.stepStartCalories,
    required this.complete,
  });

  final int stepIndex;
  final double stepStartElapsed;
  final double stepStartDistance;
  final double stepStartCalories;
  final bool complete;

  static const start = _Cursor(
    stepIndex: 0,
    stepStartElapsed: 0,
    stepStartDistance: 0,
    stepStartCalories: 0,
    complete: false,
  );
}

double _consumed(
  _Cursor cursor,
  WorkoutStep step,
  double elapsed,
  double distance,
  double calories,
) {
  return switch (step.goal) {
    WorkoutGoal.duration => elapsed - cursor.stepStartElapsed,
    WorkoutGoal.distance => distance - cursor.stepStartDistance,
    WorkoutGoal.calories => calories - cursor.stepStartCalories,
  };
}

double _wattBand(double target) {
  final relative = target.abs() * Pm5Constants.wattTargetRelativeBand;
  final minimum = Pm5Constants.wattTargetMinimumBandWatts;
  return relative > minimum ? relative : minimum;
}

bool _amountOk(WorkoutGoal goal, double amount) {
  if (!amount.isFinite || amount <= 0) {
    return false;
  }
  return switch (goal) {
    WorkoutGoal.duration => amount <= Pm5Constants.maxWorkoutStepSeconds,
    WorkoutGoal.distance => amount <= Pm5Constants.maxWorkoutStepMeters,
    WorkoutGoal.calories => amount <= Pm5Constants.maxWorkoutStepKilocalories,
  };
}

WorkoutStep? _stepFromJson(Object? raw) {
  if (raw is! Map) {
    return null;
  }
  final goal = _goalFromName(raw['goal']);
  final amountRaw = raw['amount'];
  if (goal == null || amountRaw is! num) {
    return null;
  }
  final amount = amountRaw.toDouble();
  if (!_amountOk(goal, amount)) {
    return null;
  }
  final recovery = raw['recovery'] == true;
  final wattsRaw = raw['targetWatts'];
  double? watts;
  if (!recovery && wattsRaw is num) {
    watts = wattsRaw.toDouble();
    if (!watts.isFinite || watts <= 0) {
      return null;
    }
    if (watts > Pm5Constants.maxWorkoutTargetWatts) {
      watts = Pm5Constants.maxWorkoutTargetWatts;
    }
  }
  return WorkoutStep(
    goal: goal,
    amount: amount,
    targetWatts: watts,
    recovery: recovery,
  );
}

WorkoutGoal? _goalFromName(Object? name) {
  for (final goal in WorkoutGoal.values) {
    if (goal.name == name) {
      return goal;
    }
  }
  return null;
}
