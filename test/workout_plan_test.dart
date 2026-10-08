import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pm5_bike/core/workout_plan.dart';
import 'package:pm5_bike/data/app_settings.dart';
import 'package:pm5_bike/features/live/workout_labels.dart';

void main() {
  const workRecovery = WorkoutPlan(
    repeats: 6,
    steps: [
      WorkoutStep(goal: WorkoutGoal.duration, amount: 120, targetWatts: 180),
      WorkoutStep(goal: WorkoutGoal.duration, amount: 120, recovery: true),
    ],
  );

  test('six by four minutes keeps work and recovery apart', () {
    expect(workRecovery.totalDurationSeconds, 24 * 60);
    expect(
      describeWorkoutPlan(workRecovery),
      '6 × (2:00 à 180 W + 2:00 récup)',
    );

    final guide = WorkoutGuide(workRecovery);
    final early = guide.progress(
      elapsedSeconds: 90,
      distanceMeters: 400,
      calories: 12,
      watts: 180,
    );
    expect(early.repeatIndex, 1);
    expect(early.indexInRepeat, 1);
    expect(early.remaining, closeTo(30, 1e-6));
    expect(early.fraction, closeTo(0.75, 1e-6));
    expect(early.onTarget, isTrue);
    expect(early.complete, isFalse);
    expect(workoutPositionLabel(early), '1/6 · 1/2');
    expect(workoutRemainingLabel(early), '0:30');
    expect(workoutTargetLabel(early), '180 W');

    final recovery = guide.progress(
      elapsedSeconds: 130,
      distanceMeters: 500,
      calories: 20,
      watts: 40,
    );
    expect(recovery.repeatIndex, 1);
    expect(recovery.indexInRepeat, 2);
    expect(recovery.step!.recovery, isTrue);
    expect(recovery.onTarget, isNull);
    expect(recovery.remaining, closeTo(110, 1e-6));
    expect(workoutTargetLabel(recovery), 'Récup');

    final secondRound = guide.progress(
      elapsedSeconds: 240,
      distanceMeters: 800,
      calories: 30,
      watts: 171,
    );
    expect(secondRound.repeatIndex, 2);
    expect(secondRound.indexInRepeat, 1);
    expect(secondRound.remaining, closeTo(120, 1e-6));
    expect(secondRound.onTarget, isTrue);

    final almost = guide.progress(
      elapsedSeconds: 1439,
      distanceMeters: 1000,
      calories: 40,
      watts: 0,
    );
    expect(almost.complete, isFalse);
    expect(almost.repeatIndex, 6);
    expect(almost.indexInRepeat, 2);
    expect(almost.remaining, closeTo(1, 1e-6));

    final done = guide.progress(
      elapsedSeconds: 1440,
      distanceMeters: 1000,
      calories: 40,
      watts: 0,
    );
    expect(done.complete, isTrue);
    expect(workoutTargetLabel(done), isEmpty);

    final later = guide.progress(
      elapsedSeconds: 1800,
      distanceMeters: 2000,
      calories: 80,
      watts: 100,
    );
    expect(later.complete, isTrue);
  });

  test('two different watt targets stay on their own minutes', () {
    final plan = WorkoutPlan(
      steps: const [
        WorkoutStep(goal: WorkoutGoal.duration, amount: 120, targetWatts: 200),
        WorkoutStep(goal: WorkoutGoal.duration, amount: 120, targetWatts: 140),
      ],
    );
    expect(describeWorkoutPlan(plan), '2:00 à 200 W + 2:00 à 140 W');
    final guide = WorkoutGuide(plan);
    final second = guide.progress(
      elapsedSeconds: 130,
      distanceMeters: 0,
      calories: 0,
      watts: 140,
    );
    expect(second.indexInRepeat, 2);
    expect(second.step!.targetWatts, 140);
    expect(second.remaining, closeTo(110, 1e-6));
    expect(second.onTarget, isTrue);
    expect(workoutPositionLabel(second), '2/2');
  });

  test('a long tick carries leftover time into the next block', () {
    final guide = WorkoutGuide(workRecovery);
    final jumped = guide.progress(
      elapsedSeconds: 130,
      distanceMeters: 0,
      calories: 0,
      watts: 0,
    );
    expect(jumped.repeatIndex, 1);
    expect(jumped.indexInRepeat, 2);
    expect(jumped.remaining, closeTo(110, 1e-6));
  });

  test('the same elapsed does not consume a block twice', () {
    final guide = WorkoutGuide(workRecovery);
    final first = guide.progress(
      elapsedSeconds: 30,
      distanceMeters: 10,
      calories: 1,
      watts: 180,
    );
    final second = guide.progress(
      elapsedSeconds: 30,
      distanceMeters: 10,
      calories: 1,
      watts: 170,
    );
    expect(second.remaining, closeTo(first.remaining, 1e-9));
    expect(second.indexInRepeat, 1);
    expect(second.onTarget, isFalse);
  });

  test('distance and calorie gates', () {
    final distance = WorkoutGuide(
      const WorkoutPlan(
        steps: [
          WorkoutStep(
            goal: WorkoutGoal.distance,
            amount: 1000,
            targetWatts: 150,
          ),
        ],
      ),
    );
    final midDistance = distance.progress(
      elapsedSeconds: 40,
      distanceMeters: 250,
      calories: 5,
      watts: 150,
    );
    expect(midDistance.remaining, closeTo(750, 1e-6));
    expect(midDistance.fraction, closeTo(0.25, 1e-6));
    expect(midDistance.onTarget, isTrue);
    expect(workoutRemainingLabel(midDistance), '750 m');
    expect(workoutPositionLabel(midDistance), isEmpty);

    final calories = WorkoutGuide(
      const WorkoutPlan(
        steps: [WorkoutStep(goal: WorkoutGoal.calories, amount: 40)],
      ),
    );
    final midCalories = calories.progress(
      elapsedSeconds: 80,
      distanceMeters: 300,
      calories: 27.5,
      watts: 100,
    );
    expect(midCalories.remaining, closeTo(12.5, 1e-6));
    expect(midCalories.onTarget, isNull);
    expect(workoutRemainingLabel(midCalories), '12,5 kcal');
    expect(describeWorkoutPlan(calories.plan), '40 kcal');

    final done = calories.progress(
      elapsedSeconds: 100,
      distanceMeters: 400,
      calories: 40,
      watts: 100,
    );
    expect(done.complete, isTrue);
  });

  test('a distance block starts at the end of the previous time block', () {
    final guide = WorkoutGuide(
      const WorkoutPlan(
        steps: [
          WorkoutStep(goal: WorkoutGoal.duration, amount: 10),
          WorkoutStep(goal: WorkoutGoal.distance, amount: 100),
        ],
      ),
    );
    final atSplit = guide.progress(
      elapsedSeconds: 10,
      distanceMeters: 40,
      calories: 3,
      watts: 120,
    );
    expect(atSplit.indexInRepeat, 2);
    expect(atSplit.remaining, closeTo(100, 1e-6));

    final later = guide.progress(
      elapsedSeconds: 12,
      distanceMeters: 70,
      calories: 4,
      watts: 120,
    );
    expect(later.remaining, closeTo(70, 1e-6));
    expect(workoutPositionLabel(later), '2/2');
  });

  test('watt target uses five percent and at least eight watts', () {
    final high = WorkoutGuide(
      const WorkoutPlan(
        steps: [
          WorkoutStep(goal: WorkoutGoal.duration, amount: 60, targetWatts: 180),
        ],
      ),
    );
    expect(
      high
          .progress(
            elapsedSeconds: 1,
            distanceMeters: 0,
            calories: 0,
            watts: 189,
          )
          .onTarget,
      isTrue,
    );
    expect(
      high
          .progress(
            elapsedSeconds: 1,
            distanceMeters: 0,
            calories: 0,
            watts: 190,
          )
          .onTarget,
      isFalse,
    );

    final low = WorkoutGuide(
      const WorkoutPlan(
        steps: [
          WorkoutStep(goal: WorkoutGoal.duration, amount: 60, targetWatts: 80),
        ],
      ),
    );
    expect(
      low
          .progress(
            elapsedSeconds: 1,
            distanceMeters: 0,
            calories: 0,
            watts: 88,
          )
          .onTarget,
      isTrue,
    );
    expect(
      low
          .progress(
            elapsedSeconds: 1,
            distanceMeters: 0,
            calories: 0,
            watts: 89,
          )
          .onTarget,
      isFalse,
    );
  });

  test('a plan survives settings json and a broken plan does not', () {
    final settings = AppSettings.defaults().copyWith(workoutPlan: workRecovery);
    final kept = settings.copyWith(weightKg: 70);
    expect(kept.workoutPlan?.repeats, 6);
    expect(kept.weightKg, 70);

    final decoded = jsonDecode(jsonEncode(settings.toJson()));
    final restored = AppSettings.fromJson(decoded as Map<String, dynamic>);
    expect(restored.workoutPlan?.repeats, 6);
    expect(restored.workoutPlan?.steps[1].recovery, isTrue);
    expect(restored.workoutPlan?.steps.first.targetWatts, 180);
    expect(
      describeWorkoutPlan(restored.workoutPlan!),
      describeWorkoutPlan(workRecovery),
    );

    final cleared = restored.copyWith(workoutPlan: null);
    expect(cleared.workoutPlan, isNull);
    expect(cleared.activeLevel, settings.activeLevel);

    final broken = AppSettings.fromJson({
      'weightKg': 80,
      'workoutPlan': {'repeats': 2, 'steps': []},
    });
    expect(broken.workoutPlan, isNull);
    expect(broken.weightKg, 80);
    expect(WorkoutPlan.tryParse('nope'), isNull);
  });
}
