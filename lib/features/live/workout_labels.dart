import 'package:pm5_bike/core/metric_format.dart';
import 'package:pm5_bike/core/workout_plan.dart';

String formatWorkoutClock(double seconds, {bool countdown = false}) {
  if (!seconds.isFinite || seconds <= 0) {
    return '0:00';
  }
  final eased = countdown ? seconds - 1e-6 : seconds;
  if (eased <= 0) {
    return '0:00';
  }
  final total = countdown ? eased.ceil() : seconds.round();
  if (total <= 0) {
    return '0:00';
  }
  final hours = total ~/ 3600;
  final minutes = (total % 3600) ~/ 60;
  final secs = total % 60;
  final mm = minutes.toString().padLeft(2, '0');
  final ss = secs.toString().padLeft(2, '0');
  if (hours > 0) {
    return '$hours:$mm:$ss';
  }
  return '$minutes:$ss';
}

String describeWorkoutStep(WorkoutStep step) {
  final amount = switch (step.goal) {
    WorkoutGoal.duration => formatWorkoutClock(step.amount),
    WorkoutGoal.distance => formatDistance(step.amount),
    WorkoutGoal.calories => '${formatKcal(step.amount)} kcal',
  };
  if (step.recovery) {
    return '$amount récup';
  }
  final watts = step.targetWatts;
  if (watts == null) {
    return amount;
  }
  return '$amount à ${watts.round()} W';
}

String describeWorkoutPlan(WorkoutPlan plan) {
  final parts = plan.steps.map(describeWorkoutStep).join(' + ');
  if (plan.repeats > 1 && plan.steps.length > 1) {
    return '${plan.repeats} × ($parts)';
  }
  if (plan.repeats > 1) {
    return '${plan.repeats} × $parts';
  }
  return parts;
}

String workoutPositionLabel(WorkoutProgress progress) {
  if (progress.complete) {
    return '';
  }
  final rounds = progress.repeatCount > 1;
  final blocks = progress.stepsPerRepeat > 1;
  if (rounds && blocks) {
    return '${progress.repeatIndex}/${progress.repeatCount} · ${progress.indexInRepeat}/${progress.stepsPerRepeat}';
  }
  if (rounds) {
    return '${progress.repeatIndex}/${progress.repeatCount}';
  }
  if (blocks) {
    return '${progress.indexInRepeat}/${progress.stepsPerRepeat}';
  }
  return '';
}

String workoutRemainingLabel(WorkoutProgress progress) {
  final step = progress.step;
  if (progress.complete || step == null) {
    return '0:00';
  }
  final remaining = progress.remaining;
  switch (step.goal) {
    case WorkoutGoal.duration:
      return formatWorkoutClock(remaining, countdown: true);
    case WorkoutGoal.distance:
      final meters = remaining <= 0 ? 0 : (remaining - 1e-6).ceil();
      return formatDistance(meters.toDouble());
    case WorkoutGoal.calories:
      if (remaining <= 0) {
        return '0 kcal';
      }
      if (remaining < 20) {
        final text = remaining.toStringAsFixed(1).replaceAll('.', ',');
        return '$text kcal';
      }
      return '${remaining.round()} kcal';
  }
}

String workoutTargetLabel(WorkoutProgress progress) {
  final step = progress.step;
  if (progress.complete || step == null) {
    return '';
  }
  if (step.recovery) {
    return 'Récup';
  }
  final watts = step.targetWatts;
  if (watts == null) {
    return '';
  }
  return '${watts.round()} W';
}
