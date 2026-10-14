import 'package:flutter_test/flutter_test.dart';
import 'package:pm5_bike/data/ble_cadence_source.dart';

void main() {
  test('an Android 10 scan failure asks for location', () {
    expect(
      bleScanErrorMessage(
        'FlutterBluePlus requires android.permission.ACCESS_FINE_LOCATION permission',
      ),
      'Autorisez la localisation, et laissez-la activée, pour chercher un capteur.',
    );
    expect(
      bleScanErrorMessage(
        'java.lang.IllegalStateException: Location services are not enabled',
      ),
      'Autorisez la localisation, et laissez-la activée, pour chercher un capteur.',
    );
    expect(
      bleScanErrorMessage('bluetooth must be turned on'),
      'Recherche impossible. Autorisez le Bluetooth, puis réessayez.',
    );
    expect(
      bleScanErrorMessage(null),
      'Recherche impossible. Autorisez le Bluetooth, puis réessayez.',
    );
  });

  test('a named sensor is listed even when it does not advertise cadence', () {
    expect(
      bleDeviceIsListable(
        advertisedName: '44885-1',
        platformName: '',
        id: 'AA:BB:CC:DD:EE:FF',
      ),
      isTrue,
    );
    expect(
      bleDeviceLabel(advertisedName: '44885-1', platformName: ''),
      '44885-1',
    );
    expect(
      bleDeviceIsListable(
        advertisedName: '',
        platformName: '',
        id: 'AA:BB:CC:DD:EE:FF',
      ),
      isTrue,
    );
    expect(
      bleDeviceLabel(
        advertisedName: '',
        platformName: '',
        id: 'AA:BB:CC:DD:EE:FF',
      ),
      'AA:BB:CC:DD:EE:FF',
    );
  });
}
