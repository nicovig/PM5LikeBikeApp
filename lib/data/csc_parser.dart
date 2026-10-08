import 'package:pm5_bike/core/pm5_constants.dart';

class CscPacket {
  const CscPacket({
    required this.rpm,
    required this.crankPresent,
    required this.heldPrevious,
  });

  final double? rpm;
  final bool crankPresent;
  final bool heldPrevious;
}

class CscCadenceParser {
  int? _previousRevolutions;
  int? _previousTimeTicks;

  CscPacket parse(List<int> data) {
    if (data.isEmpty) {
      return const CscPacket(
        rpm: null,
        crankPresent: false,
        heldPrevious: false,
      );
    }
    final flags = data[0];
    if ((flags & 0x02) == 0) {
      return const CscPacket(
        rpm: null,
        crankPresent: false,
        heldPrevious: false,
      );
    }

    var index = 1;
    if ((flags & 0x01) != 0) {
      index += 6;
    }
    if (data.length < index + 4) {
      return const CscPacket(
        rpm: null,
        crankPresent: true,
        heldPrevious: false,
      );
    }

    final revolutions = data[index] | (data[index + 1] << 8);
    final timeTicks = data[index + 2] | (data[index + 3] << 8);
    double? rpm;
    var heldPrevious = false;
    if (_previousRevolutions != null && _previousTimeTicks != null) {
      final revolutionDelta = (revolutions - _previousRevolutions!) & 0xFFFF;
      final timeDeltaTicks = (timeTicks - _previousTimeTicks!) & 0xFFFF;
      if (timeDeltaTicks > 0) {
        final seconds = timeDeltaTicks / Pm5Constants.cscTimeTicksPerSecond;
        rpm = revolutionDelta / seconds * 60;
      } else {
        heldPrevious = true;
      }
    }
    _previousRevolutions = revolutions;
    _previousTimeTicks = timeTicks;
    return CscPacket(rpm: rpm, crankPresent: true, heldPrevious: heldPrevious);
  }

  void reset() {
    _previousRevolutions = null;
    _previousTimeTicks = null;
  }
}

class CscCadenceTracker {
  CscCadenceTracker({
    CscCadenceParser? parser,
    this.timeout = Pm5Constants.cadenceStopTimeout,
  }) : parser = parser ?? CscCadenceParser();

  final CscCadenceParser parser;
  final Duration timeout;
  double _rpm = 0;
  DateTime? _lastEventAt;

  double get rpm => _rpm;

  double onPacket(List<int> data, DateTime at) {
    final packet = parser.parse(data);
    if (packet.rpm != null) {
      _rpm = packet.rpm!;
      _lastEventAt = at;
    }
    return _applyTimeout(at);
  }

  double onClock(DateTime at) => _applyTimeout(at);

  void reset() {
    parser.reset();
    _rpm = 0;
    _lastEventAt = null;
  }

  double _applyTimeout(DateTime at) {
    final lastEvent = _lastEventAt;
    if (lastEvent != null && at.difference(lastEvent) >= timeout) {
      _rpm = 0;
    }
    return _rpm;
  }
}
