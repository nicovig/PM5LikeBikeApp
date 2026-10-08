import 'package:pm5_bike/core/session_accumulator.dart';

class WorkoutSession {
  const WorkoutSession({
    required this.id,
    required this.startedAt,
    required this.endedAt,
    required this.elapsedSeconds,
    required this.distanceMeters,
    required this.averageWatts,
    required this.pm5AverageWatts,
    required this.calories,
    required this.averageRpm,
    required this.level,
    required this.hadOutOfRange,
    required this.outOfRangeSeconds,
    required this.samples,
  });

  final String id;
  final DateTime startedAt;
  final DateTime endedAt;
  final double elapsedSeconds;
  final double distanceMeters;
  final double averageWatts;
  final double? pm5AverageWatts;
  final double calories;
  final double averageRpm;
  final int level;
  final bool hadOutOfRange;
  final double outOfRangeSeconds;
  final List<SessionSample> samples;
}
