import 'package:pm5_bike/data/cadence_sample.dart';

abstract class CadenceSource {
  Stream<CadenceSample> get samples;

  Future<void> start();

  Future<void> stop();
}
