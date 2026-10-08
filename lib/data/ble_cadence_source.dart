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
    Duration timeout = const Duration(seconds: 8),
    void Function(List<BleSensor> devices)? onDevices,
  }) async {
    _configureLogging();
    await _ensureAdapterOn();
    _found.clear();
    onDevices?.call(const []);
    final subscription = FlutterBluePlus.onScanResults.listen((results) {
      for (final result in results) {
        final advertised = result.advertisementData.advName.trim();
        final platformName = result.device.platformName.trim();
        final name = advertised.isNotEmpty
            ? advertised
            : platformName.isNotEmpty
            ? platformName
            : 'Capteur';
        _upsert(
          BleSensor(
            id: result.device.remoteId.str,
            name: name,
            rssi: result.rssi,
          ),
        );
      }
      onDevices?.call(List.unmodifiable(_found));
    });
    try {
      await FlutterBluePlus.startScan(
        withServices: [_cscService],
        timeout: timeout,
        androidUsesFineLocation: false,
      );
      await FlutterBluePlus.isScanning.where((scanning) => !scanning).first;
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
      if (measurement == null) {
        _fail(generation, 'Ce capteur n’expose pas la cadence (CSC).');
        return;
      }
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

  Future<BluetoothCharacteristic?> _findMeasurement(
    BluetoothDevice device,
  ) async {
    final services = await device.discoverServices();
    for (final service in services) {
      if (service.uuid != _cscService) {
        continue;
      }
      for (final characteristic in service.characteristics) {
        if (characteristic.uuid == _cscMeasurement) {
          return characteristic;
        }
      }
    }
    return null;
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
