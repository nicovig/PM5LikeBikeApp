import 'dart:async';
import 'dart:io';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:pm5_bike/data/cadence_sample.dart';
import 'package:pm5_bike/data/cadence_source.dart';
import 'package:pm5_bike/data/csc_parser.dart';

class BleSensor {
  const BleSensor({required this.id, required this.name, required this.rssi});

  final String id;
  final String name;
  final int rssi;
}

bool bleDeviceIsListable({
  required String advertisedName,
  required String platformName,
  required String id,
}) {
  return id.trim().isNotEmpty ||
      advertisedName.trim().isNotEmpty ||
      platformName.trim().isNotEmpty;
}

String bleDeviceLabel({
  required String advertisedName,
  required String platformName,
  String id = '',
}) {
  final advertised = advertisedName.trim();
  if (advertised.isNotEmpty) {
    return advertised;
  }
  final platform = platformName.trim();
  if (platform.isNotEmpty) {
    return platform;
  }
  final remote = id.trim();
  if (remote.isNotEmpty) {
    return remote;
  }
  return 'Capteur';
}

String bleScanErrorMessage(String? description) {
  final text = (description ?? '').toLowerCase();
  if (text.contains('location')) {
    return 'Autorisez la localisation, et laissez-la activée, pour chercher un capteur.';
  }
  return 'Recherche impossible. Autorisez le Bluetooth, puis réessayez.';
}

class BleCadenceException implements Exception {
  BleCadenceException(this.message);

  final String message;

  @override
  String toString() => message;
}

class BleCadenceSource implements CadenceSource {
  BleCadenceSource({this.preferredDeviceId, this.preferredDeviceName});

  final String? preferredDeviceId;
  final String? preferredDeviceName;

  final _samples = StreamController<CadenceSample>.broadcast();
  final _tracker = CscCadenceTracker();
  final List<BleSensor> _found = [];

  Timer? _clock;
  Timer? _reconnectTimer;
  StreamSubscription<List<int>>? _values;
  StreamSubscription<BluetoothConnectionState>? _connection;
  BluetoothDevice? _device;
  var _wantRunning = false;
  var _generation = 0;
  var _reconnectAttempt = 0;
  var _link = CadenceLinkState.disconnected;
  String? _detail;
  var _loggingConfigured = false;

  static final _cscService = Guid('1816');
  static final _cscMeasurement = Guid('2A5B');
  static final _cscFeature = Guid('2A5C');
  static const _speedModeMessage =
      'Ce capteur est en mode vitesse (LED verte). Retire et remets la pile pour passer en cadence (LED rouge).';

  @override
  Stream<CadenceSample> get samples => _samples.stream;

  @override
  Future<void> start() async {
    _wantRunning = true;
    _configureLogging();
    _clock ??= Timer.periodic(
      const Duration(milliseconds: 200),
      (_) => _onClock(),
    );
    final deviceId = preferredDeviceId;
    if (deviceId == null || deviceId.isEmpty) {
      _emit(0, CadenceLinkState.disconnected, detail: 'Aucun capteur mémorisé');
      return;
    }
    unawaited(connect(deviceId));
  }

  @override
  Future<void> stop() async {
    _wantRunning = false;
    _generation++;
    _reconnectTimer?.cancel();
    _clock?.cancel();
    _clock = null;
    await _releaseLink();
    _tracker.reset();
    try {
      await FlutterBluePlus.stopScan();
    } catch (_) {}
    if (!_samples.isClosed) {
      await _samples.close();
    }
  }

  Future<void> scan({
    Duration timeout = const Duration(seconds: 20),
    void Function(List<BleSensor> devices)? onDevices,
  }) async {
    _configureLogging();
    await _ensureAdapterOn();
    _found.clear();
    onDevices?.call(const []);
    void absorb(List<ScanResult> results) {
      for (final result in results) {
        final advertised = result.advertisementData.advName;
        final platformName = result.device.platformName;
        final id = result.device.remoteId.str;
        if (!bleDeviceIsListable(
          advertisedName: advertised,
          platformName: platformName,
          id: id,
        )) {
          continue;
        }
        _upsert(
          BleSensor(
            id: id,
            name: bleDeviceLabel(
              advertisedName: advertised,
              platformName: platformName,
              id: id,
            ),
            rssi: result.rssi,
          ),
        );
      }
      onDevices?.call(List.unmodifiable(_found));
    }

    final subscription = FlutterBluePlus.onScanResults.listen(absorb);
    try {
      await FlutterBluePlus.startScan(
        timeout: timeout,
        androidUsesFineLocation: false,
        androidLegacy: true,
        continuousUpdates: true,
      );
      await FlutterBluePlus.isScanning.where((scanning) => !scanning).first;
      absorb(FlutterBluePlus.lastScanResults);
    } on FlutterBluePlusException catch (error) {
      throw BleCadenceException(bleScanErrorMessage(error.description));
    } finally {
      await subscription.cancel();
    }
  }

  Future<void> connect(String deviceId) async {
    final generation = ++_generation;
    _reconnectTimer?.cancel();
    _wantRunning = true;
    _link = CadenceLinkState.connecting;
    _detail = 'Connexion…';
    _emit(0, _link, detail: _detail);
    try {
      await _ensureAdapterOn();
      if (generation != _generation || !_wantRunning) {
        return;
      }
      await _releaseLink();
      final device = BluetoothDevice.fromId(deviceId);
      _device = device;
      await device.connect(timeout: const Duration(seconds: 12));
      if (generation != _generation || !_wantRunning) {
        return;
      }
      _listenForDrop(device, generation);
      final measurement = await _findMeasurement(device);
      _tracker.reset();
      _values = measurement.onValueReceived.listen((value) {
        if (generation != _generation || !_wantRunning || _samples.isClosed) {
          return;
        }
        final rpm = _tracker.onPacket(value, DateTime.now());
        _reconnectAttempt = 0;
        _link = CadenceLinkState.connected;
        _detail = preferredDeviceName;
        _emit(rpm, _link, detail: _detail);
      });
      await measurement.setNotifyValue(true);
      if (generation != _generation || !_wantRunning) {
        return;
      }
      _link = CadenceLinkState.connected;
      _detail = preferredDeviceName;
      _emit(_tracker.rpm, _link, detail: _detail);
    } on BleCadenceException catch (error) {
      _fail(generation, error.message);
    } catch (_) {
      _fail(generation, 'Connexion impossible');
    }
  }

  void _listenForDrop(BluetoothDevice device, int generation) {
    var sawConnected = device.isConnected;
    _connection = device.connectionState.listen((connection) {
      if (connection == BluetoothConnectionState.connected) {
        sawConnected = true;
        return;
      }
      if (connection != BluetoothConnectionState.disconnected ||
          !sawConnected ||
          generation != _generation ||
          !_wantRunning) {
        return;
      }
      _link = CadenceLinkState.disconnected;
      _tracker.reset();
      _emit(0, _link, detail: 'Capteur perdu');
      _scheduleReconnect();
    });
  }

  Future<BluetoothCharacteristic> _findMeasurement(
    BluetoothDevice device,
  ) async {
    final services = await device.discoverServices();
    BluetoothCharacteristic? measurement;
    BluetoothCharacteristic? feature;
    for (final service in services) {
      if (service.uuid != _cscService) {
        continue;
      }
      for (final characteristic in service.characteristics) {
        if (characteristic.uuid == _cscMeasurement) {
          measurement = characteristic;
        } else if (characteristic.uuid == _cscFeature) {
          feature = characteristic;
        }
      }
    }
    if (measurement == null) {
      throw BleCadenceException('Ce capteur n’expose pas la cadence (CSC).');
    }
    if (feature != null && feature.properties.read) {
      try {
        final value = await feature.read();
        if (!cscFeatureSupportsCrank(value)) {
          throw BleCadenceException(_speedModeMessage);
        }
      } on BleCadenceException {
        rethrow;
      } catch (_) {}
    }
    return measurement;
  }

  void _onClock() {
    if (!_wantRunning ||
        _samples.isClosed ||
        _link != CadenceLinkState.connected) {
      return;
    }
    final rpm = _tracker.onClock(DateTime.now());
    _emit(rpm, CadenceLinkState.connected, detail: _detail);
  }

  void _scheduleReconnect() {
    final deviceId = preferredDeviceId;
    if (!_wantRunning || deviceId == null || deviceId.isEmpty) {
      return;
    }
    _reconnectTimer?.cancel();
    final shift = _reconnectAttempt.clamp(0, 3).toInt();
    final seconds = 1 << shift;
    _reconnectAttempt++;
    _reconnectTimer = Timer(Duration(seconds: seconds > 10 ? 10 : seconds), () {
      if (_wantRunning) {
        unawaited(connect(deviceId));
      }
    });
  }

  void _fail(int generation, String message) {
    if (generation != _generation) {
      return;
    }
    _link = CadenceLinkState.disconnected;
    _detail = message;
    _emit(0, _link, detail: message);
    _scheduleReconnect();
  }

  Future<void> _ensureAdapterOn() async {
    final current = await FlutterBluePlus.adapterState.first;
    if (current == BluetoothAdapterState.on) {
      return;
    }
    if (Platform.isAndroid) {
      await FlutterBluePlus.turnOn();
      return;
    }
    throw BleCadenceException('Activez le Bluetooth.');
  }

  Future<void> _releaseLink() async {
    await _values?.cancel();
    await _connection?.cancel();
    _values = null;
    _connection = null;
    final device = _device;
    _device = null;
    if (device == null) {
      return;
    }
    try {
      await device.disconnect();
    } catch (_) {}
  }

  void _configureLogging() {
    if (_loggingConfigured) {
      return;
    }
    _loggingConfigured = true;
    unawaited(FlutterBluePlus.setLogLevel(LogLevel.none));
  }

  void _upsert(BleSensor sensor) {
    final index = _found.indexWhere((item) => item.id == sensor.id);
    if (index >= 0) {
      _found[index] = sensor;
    } else {
      _found.add(sensor);
    }
    _found.sort((a, b) => b.rssi.compareTo(a.rssi));
  }

  void _emit(double rpm, CadenceLinkState link, {String? detail}) {
    if (_samples.isClosed) {
      return;
    }
    _samples.add(
      CadenceSample(at: DateTime.now(), rpm: rpm, link: link, detail: detail),
    );
  }
}
