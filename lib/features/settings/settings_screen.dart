import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pm5_bike/core/pm5_constants.dart';
import 'package:pm5_bike/core/pm5_metrics.dart';
import 'package:pm5_bike/data/app_settings.dart';
import 'package:pm5_bike/data/ble_cadence_source.dart';
import 'package:pm5_bike/data/cadence_sample.dart';
import 'package:pm5_bike/features/app_providers.dart';
import 'package:pm5_bike/features/shared/pm5_colors.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _weight = TextEditingController();
  final _weightFocus = FocusNode();
  var _loaded = false;
  var _smoothing = Pm5Constants.defaultSmoothingSeconds;
  var _scanning = false;
  String? _scanError;
  List<BleSensor> _found = const [];

  @override
  void initState() {
    super.initState();
    _weightFocus.addListener(() {
      if (!_weightFocus.hasFocus) {
        _commitWeight();
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _weightFocus.dispose();
    _weight.dispose();
    super.dispose();
  }

  void _load() {
    final settings = ref.read(settingsControllerProvider).value;
    if (!mounted || settings == null) {
      return;
    }
    _weight.text = _trim(settings.weightKg);
    setState(() {
      _smoothing = settings.smoothingSeconds;
      _loaded = true;
    });
  }

  Future<void> _update(AppSettings settings) {
    return ref.read(settingsControllerProvider.notifier).save(settings);
  }

  Future<void> _commitWeight() async {
    final settings = ref.read(settingsControllerProvider).value;
    if (settings == null) {
      return;
    }
    final parsed = double.tryParse(_weight.text.trim().replaceAll(',', '.'));
    if (parsed == null) {
      return;
    }
    final weight = parsed
        .clamp(Pm5Constants.minBodyWeightKg, Pm5Constants.maxBodyWeightKg)
        .toDouble();
    final text = _trim(weight);
    if (_weight.text != text) {
      _weight.text = text;
    }
    if (weight == settings.weightKg &&
        settings.calorieMode == CalorieMode.personalWeight) {
      return;
    }
    await _update(
      settings.copyWith(
        weightKg: weight,
        calorieMode: CalorieMode.personalWeight,
      ),
    );
  }

  String _trim(double value) {
    final text = value.toStringAsFixed(1);
    return text.endsWith('.0') ? value.round().toString() : text;
  }

  Future<void> _scan() async {
    final bluetooth = ref.read(cadenceHubProvider.notifier).bluetooth;
    if (bluetooth == null) {
      setState(() => _scanError = 'Le Bluetooth n’est pas encore actif.');
      return;
    }
    setState(() {
      _scanning = true;
      _scanError = null;
      _found = const [];
    });
    try {
      await bluetooth.scan(
        onDevices: (devices) {
          if (mounted) {
            setState(() => _found = devices);
          }
        },
      );
    } on BleCadenceException catch (error) {
      if (mounted) {
        setState(() => _scanError = error.message);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _scanError = 'Recherche impossible.');
      }
    } finally {
      if (mounted) {
        setState(() => _scanning = false);
      }
    }
  }

  Future<void> _selectSensor(AppSettings settings, BleSensor sensor) async {
    await _update(
      settings.copyWith(bleDeviceId: sensor.id, bleDeviceName: sensor.name),
    );
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('${sensor.name} mémorisé.')));
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsControllerProvider).value;
    final link = ref.watch(
      cadenceHubProvider.select((status) => status.sample.link),
    );
    final detail = ref.watch(
      cadenceHubProvider.select((status) => status.sample.detail),
    );
    final sourceReady = ref.watch(
      cadenceHubProvider.select((status) => status.sourceReady),
    );
    if (!_loaded || settings == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final levels = settings.levels.keys.toList()..sort();
    final active = levels.contains(settings.activeLevel)
        ? settings.activeLevel
        : levels.first;
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          const Text(
            'Réglages',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<int>(
            key: ValueKey(active),
            initialValue: active,
            decoration: const InputDecoration(labelText: 'Niveau actif'),
            items: [
              for (final level in levels)
                DropdownMenuItem(value: level, child: Text('Niveau $level')),
            ],
            onChanged: (level) {
              if (level != null) {
                _update(settings.copyWith(activeLevel: level));
              }
            },
          ),
          const SizedBox(height: 20),
          const Text('Calories', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          SegmentedButton<CalorieMode>(
            segments: const [
              ButtonSegment(
                value: CalorieMode.pm5Standard,
                label: Text('PM5 (79 kg)'),
              ),
              ButtonSegment(
                value: CalorieMode.personalWeight,
                label: Text('Mon poids'),
              ),
            ],
            selected: {settings.calorieMode},
            onSelectionChanged: (selection) {
              _update(settings.copyWith(calorieMode: selection.first));
            },
          ),
          if (settings.calorieMode == CalorieMode.personalWeight) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _weight,
              focusNode: _weightFocus,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Poids',
                suffixText: 'kg',
              ),
              onSubmitted: (_) => _commitWeight(),
            ),
          ],
          const SizedBox(height: 20),
          Text(
            'Lissage : ${_smoothing.toStringAsFixed(1).replaceAll('.', ',')} s',
          ),
          Slider(
            min: 0,
            max: Pm5Constants.maxSmoothingSeconds,
            divisions: (Pm5Constants.maxSmoothingSeconds * 2).round(),
            value: _smoothing
                .clamp(0, Pm5Constants.maxSmoothingSeconds)
                .toDouble(),
            onChanged: (value) => setState(() => _smoothing = value),
            onChangeEnd: (value) =>
                _update(settings.copyWith(smoothingSeconds: value)),
          ),
          const Text(
            'Moyenne glissante de la cadence avant le calcul des watts.',
            style: TextStyle(color: Pm5Colors.muted),
          ),
          const SizedBox(height: 20),
          const Text(
            'Source de cadence',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          SegmentedButton<CadenceSourceKind>(
            segments: const [
              ButtonSegment(
                value: CadenceSourceKind.simulation,
                label: Text('Simulation'),
              ),
              ButtonSegment(
                value: CadenceSourceKind.ble,
                label: Text('Capteur BLE'),
              ),
            ],
            selected: {settings.cadenceSource},
            onSelectionChanged: (selection) {
              _update(settings.copyWith(cadenceSource: selection.first));
            },
          ),
          if (settings.cadenceSource == CadenceSourceKind.ble) ...[
            const SizedBox(height: 16),
            Text(
              settings.bleDeviceName == null
                  ? 'Aucun capteur mémorisé.'
                  : 'Capteur : ${settings.bleDeviceName}',
            ),
            const SizedBox(height: 4),
            Text(
              detail ?? _statusLabel(link, sourceReady),
              style: const TextStyle(color: Pm5Colors.muted),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: _scanning ? null : _scan,
              child: Text(_scanning ? 'Recherche…' : 'Rechercher un capteur'),
            ),
            const SizedBox(height: 4),
            const Text(
              'Seuls les capteurs qui annoncent le service cadence (1816) apparaissent.',
              style: TextStyle(color: Pm5Colors.muted, fontSize: 13),
            ),
            if (_scanError != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _scanError!,
                  style: const TextStyle(color: Pm5Colors.warning),
                ),
              ),
            for (final sensor in _found)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(sensor.name),
                subtitle: Text(sensor.id),
                trailing: Text('${sensor.rssi} dBm'),
                onTap: () => _selectSensor(settings, sensor),
              ),
          ],
        ],
      ),
    );
  }

  String _statusLabel(CadenceLinkState link, bool sourceReady) {
    if (!sourceReady) {
      return 'Activation du Bluetooth…';
    }
    return switch (link) {
      CadenceLinkState.connected => 'Connecté',
      CadenceLinkState.connecting => 'Connexion…',
      CadenceLinkState.disconnected => 'Déconnecté',
      CadenceLinkState.simulated => 'Simulation',
    };
  }
}
