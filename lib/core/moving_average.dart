class MovingAverage {
  MovingAverage({required this.window});

  Duration window;
  final List<({DateTime at, double value})> _samples = [];

  void add(DateTime at, double value) {
    _samples.add((at: at, value: value));
    _prune(at);
  }

  double? valueAt(DateTime now) {
    _prune(now);
    if (_samples.isEmpty) {
      return null;
    }
    var sum = 0.0;
    for (final sample in _samples) {
      sum += sample.value;
    }
    return sum / _samples.length;
  }

  void clear() => _samples.clear();

  void _prune(DateTime now) {
    if (window <= Duration.zero) {
      if (_samples.length > 1) {
        final last = _samples.last;
        _samples
          ..clear()
          ..add(last);
      }
      return;
    }
    final cutoff = now.subtract(window);
    _samples.removeWhere((sample) => sample.at.isBefore(cutoff));
  }
}
