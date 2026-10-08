String formatDuration(double seconds) {
  if (!seconds.isFinite || seconds < 0) {
    seconds = 0;
  }
  final totalTenths = (seconds * 10).round();
  final hours = totalTenths ~/ 36000;
  final minutes = (totalTenths ~/ 600) % 60;
  final secs = (totalTenths ~/ 10) % 60;
  final tenths = totalTenths % 10;
  final mm = minutes.toString().padLeft(2, '0');
  final ss = secs.toString().padLeft(2, '0');
  if (hours > 0) {
    return '$hours:$mm:$ss';
  }
  return '$mm:$ss.$tenths';
}

String formatPace(double? secondsPer1000Meters) {
  if (secondsPer1000Meters == null ||
      !secondsPer1000Meters.isFinite ||
      secondsPer1000Meters <= 0) {
    return '—';
  }
  final totalTenths = (secondsPer1000Meters * 10).round();
  final minutes = totalTenths ~/ 600;
  final remainder = totalTenths % 600;
  final seconds = remainder ~/ 10;
  final tenths = remainder % 10;
  return '$minutes:${seconds.toString().padLeft(2, '0')}.$tenths';
}

String formatWatts(double watts) {
  if (!watts.isFinite) {
    return '—';
  }
  return watts.round().toString();
}

String formatRpm(double rpm) {
  if (!rpm.isFinite) {
    return '—';
  }
  return rpm.round().toString();
}

String formatSpeed(double kilometersPerHour) {
  if (!kilometersPerHour.isFinite) {
    return '—';
  }
  return kilometersPerHour.toStringAsFixed(1).replaceAll('.', ',');
}

String formatDistance(double meters) {
  if (!meters.isFinite || meters < 0) {
    return '0 m';
  }
  if (meters >= 1000) {
    final kilometers = (meters / 1000).toStringAsFixed(2).replaceAll('.', ',');
    return '$kilometers km';
  }
  return '${meters.round()} m';
}

String formatKcal(double kcal) {
  if (!kcal.isFinite) {
    return '—';
  }
  return kcal.round().toString();
}

String formatAverageWatts(double? watts, {required bool available}) {
  if (!available || watts == null || !watts.isFinite) {
    return '—';
  }
  return watts.round().toString();
}
