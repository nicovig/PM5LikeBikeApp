import 'package:flutter/material.dart';
import 'package:pm5_bike/core/workout_plan.dart';
import 'package:pm5_bike/features/live/session_controller.dart';
import 'package:pm5_bike/features/live/workout_labels.dart';
import 'package:pm5_bike/features/shared/pm5_colors.dart';

Color? workoutWattsAccent(SessionState session) {
  final guide = session.guide;
  final step = guide?.step;
  if (!session.running || guide == null || guide.complete || step == null) {
    return null;
  }
  if (!step.hasWattTarget) {
    return null;
  }
  return guide.onTarget == true ? Pm5Colors.positive : Pm5Colors.warning;
}

class WorkoutBar extends StatelessWidget {
  const WorkoutBar({super.key, required this.session, required this.onEdit});

  final SessionState session;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final plan = session.plan;
    final guide = session.guide;
    if (session.running && guide != null) {
      return _ActiveBar(guide: guide);
    }
    if (plan == null) {
      if (session.running) {
        return const SizedBox.shrink();
      }
      return _IdleBar(label: 'Séance libre', onTap: onEdit);
    }
    return _IdleBar(label: describeWorkoutPlan(plan), onTap: onEdit);
  }
}

class _IdleBar extends StatelessWidget {
  const _IdleBar({required this.label, required this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return _Shell(
      onTap: onTap,
      child: Row(
        children: [
          const Icon(Icons.timer_outlined, size: 18, color: Pm5Colors.muted),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 15, height: 1.2),
            ),
          ),
          if (onTap != null)
            const Icon(Icons.chevron_right, color: Pm5Colors.muted),
        ],
      ),
    );
  }
}

class _ActiveBar extends StatelessWidget {
  const _ActiveBar({required this.guide});

  final WorkoutProgress guide;

  @override
  Widget build(BuildContext context) {
    if (guide.complete) {
      return const _Shell(
        child: Row(
          children: [
            Icon(
              Icons.check_circle_outline,
              size: 18,
              color: Pm5Colors.positive,
            ),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Objectif atteint',
                style: TextStyle(
                  color: Pm5Colors.positive,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      );
    }
    final position = workoutPositionLabel(guide);
    final target = workoutTargetLabel(guide);
    final targetColor = guide.step?.recovery == true
        ? Pm5Colors.positive
        : guide.onTarget == true
        ? Pm5Colors.positive
        : guide.onTarget == false
        ? Pm5Colors.warning
        : Pm5Colors.muted;
    return _Shell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                workoutRemainingLabel(guide),
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w500,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  position.isEmpty ? 'restant' : position,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Pm5Colors.muted, fontSize: 13),
                ),
              ),
              if (target.isNotEmpty) ...[
                const SizedBox(width: 8),
                Text(
                  target,
                  style: TextStyle(
                    color: targetColor,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              minHeight: 4,
              value: guide.fraction,
              backgroundColor: Pm5Colors.line,
              color: targetColor,
            ),
          ),
        ],
      ),
    );
  }
}

class _Shell extends StatelessWidget {
  const _Shell({required this.child, this.onTap});

  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final box = DecoratedBox(
      decoration: BoxDecoration(
        color: Pm5Colors.panel,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: child,
      ),
    );
    if (onTap == null) {
      return box;
    }
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: box,
      ),
    );
  }
}
