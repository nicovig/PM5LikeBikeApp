import 'package:flutter_test/flutter_test.dart';
import 'package:pm5_bike/data/csc_parser.dart';

void main() {
  List<int> crankPacket(int revolutions, int timeTicks) {
    return [
      0x02,
      revolutions & 0xFF,
      (revolutions >> 8) & 0xFF,
      timeTicks & 0xFF,
      (timeTicks >> 8) & 0xFF,
    ];
  }

  List<int> wheelAndCrank({
    required int wheelRevolutions,
    required int wheelTimeTicks,
    required int crankRevolutions,
    required int crankTimeTicks,
  }) {
    return [
      0x03,
      wheelRevolutions & 0xFF,
      (wheelRevolutions >> 8) & 0xFF,
      (wheelRevolutions >> 16) & 0xFF,
      (wheelRevolutions >> 24) & 0xFF,
      wheelTimeTicks & 0xFF,
      (wheelTimeTicks >> 8) & 0xFF,
      crankRevolutions & 0xFF,
      (crankRevolutions >> 8) & 0xFF,
      crankTimeTicks & 0xFF,
      (crankTimeTicks >> 8) & 0xFF,
    ];
  }

  test('crank-only packets are little-endian and yield RPM', () {
    final parser = CscCadenceParser();
    final first = parser.parse(const [0x02, 0x00, 0x00, 0x00, 0x00]);
    expect(first.rpm, isNull);
    expect(first.crankPresent, isTrue);
    expect(first.heldPrevious, isFalse);

    final second = parser.parse(const [0x02, 0x02, 0x00, 0x00, 0x04]);
    expect(second.rpm, closeTo(120, 1e-9));
  });

  test('wheel data is skipped when the flag is set', () {
    final parser = CscCadenceParser();
    parser.parse(
      wheelAndCrank(
        wheelRevolutions: 99999,
        wheelTimeTicks: 50,
        crankRevolutions: 0,
        crankTimeTicks: 0,
      ),
    );
    final packet = parser.parse(
      wheelAndCrank(
        wheelRevolutions: 120000,
        wheelTimeTicks: 4000,
        crankRevolutions: 2,
        crankTimeTicks: 1024,
      ),
    );
    expect(packet.rpm, closeTo(120, 1e-9));
  });

  test('missing crank data does not move the previous sample', () {
    final parser = CscCadenceParser();
    expect(parser.parse(const [0x00]).crankPresent, isFalse);
    expect(parser.parse(const [0x01, 1, 2, 3, 4, 5, 6]).rpm, isNull);

    parser.parse(crankPacket(0, 0));
    parser.parse(crankPacket(2, 1024));
    parser.parse(const [0x01, 9, 9, 9, 9, 9, 9]);
    final next = parser.parse(crankPacket(4, 2048));
    expect(next.rpm, closeTo(120, 1e-9));
  });

  test('a truncated crank packet does not throw or desync', () {
    final parser = CscCadenceParser();
    final truncated = parser.parse(const [0x02, 0x01]);
    expect(truncated.rpm, isNull);
    expect(truncated.crankPresent, isTrue);
    parser.parse(crankPacket(0, 0));
    expect(parser.parse(crankPacket(1, 1024)).rpm, closeTo(60, 1e-9));
  });

  test('uint16 revolution overflow is masked', () {
    final parser = CscCadenceParser();
    parser.parse(crankPacket(65534, 0));
    final packet = parser.parse(crankPacket(1, 1024));
    expect(packet.rpm, closeTo(180, 1e-9));
  });

  test('uint16 event-time overflow is masked', () {
    final parser = CscCadenceParser();
    parser.parse(crankPacket(10, 65500));
    final packet = parser.parse(crankPacket(11, 100));
    expect(packet.rpm, closeTo(60 * 1024 / 136, 1e-6));
  });

  test('a zero time delta keeps the previous cadence', () {
    final parser = CscCadenceParser();
    parser.parse(crankPacket(1, 100));
    expect(parser.parse(crankPacket(4, 1124)).rpm, isNotNull);
    final held = parser.parse(crankPacket(9, 1124));
    expect(held.rpm, isNull);
    expect(held.heldPrevious, isTrue);
    expect(held.crankPresent, isTrue);

    final tracker = CscCadenceTracker();
    final start = DateTime.utc(2026, 1, 1, 12);
    tracker.onPacket(crankPacket(0, 0), start);
    expect(tracker.onPacket(crankPacket(2, 1024), start), closeTo(120, 1e-9));
    expect(
      tracker.onPacket(
        crankPacket(2, 1024),
        start.add(const Duration(milliseconds: 1900)),
      ),
      closeTo(120, 1e-9),
    );
    expect(tracker.onClock(start.add(const Duration(seconds: 2))), 0);
  });

  test('a repeated timestamp does not postpone the two-second stop', () {
    final tracker = CscCadenceTracker();
    final start = DateTime.utc(2026, 1, 1, 12);
    tracker.onPacket(crankPacket(0, 0), start);
    tracker.onPacket(crankPacket(2, 1024), start);
    tracker.onPacket(
      crankPacket(3, 2048),
      start.add(const Duration(seconds: 1)),
    );
    expect(
      tracker.onClock(start.add(const Duration(milliseconds: 2900))),
      closeTo(60, 1e-9),
    );
    expect(tracker.onClock(start.add(const Duration(seconds: 3))), 0);
  });
}
