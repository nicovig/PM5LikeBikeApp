import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pm5_bike/core/pm5_constants.dart';
import 'package:pm5_bike/core/power_curve.dart';
import 'package:pm5_bike/data/app_settings.dart';
import 'package:pm5_bike/features/app_providers.dart';
import 'package:pm5_bike/features/shared/pm5_colors.dart';

class CalibrationScreen extends ConsumerStatefulWidget {
  const CalibrationScreen({super.key});

  @override
  ConsumerState<CalibrationScreen> createState() => _CalibrationScreenState();
}

class _PointRow {
  final rpm = TextEditingController();
  final watts = TextEditingController();

  void dispose() {
    rpm.dispose();
    watts.dispose();
  }
}

class _CalibrationScreenState extends ConsumerState<CalibrationScreen> {
  final List<_PointRow> _rows = [];
  var _level = Pm5Constants.defaultResistanceLevel;
  var _ready = false;
  var _dirty = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadInitial());
  }

  @override
  void dispose() {
    for (final row in _rows) {
      row.dispose();
    }
    super.dispose();
  }

  void _loadInitial() {
    final settings = ref.read(settingsControllerProvider).value;
    if (!mounted || settings == null) {
      return;
    }
    _showLevel(settings, settings.activeLevel, dirty: false);
  }

  void _showLevel(AppSettings settings, int level, {required bool dirty}) {
    _disposeRowsLater(List<_PointRow>.of(_rows));
    _rows.clear();
    final points = settings.levels[level] ?? const <CalibrationPoint>[];
    if (points.isEmpty) {
      _rows.add(_PointRow());
      _rows.add(_PointRow());
    } else {
      for (final point in points) {
        final row = _PointRow();
        row.rpm.text = _trim(point.rpm);
        row.watts.text = _trim(point.watts);
        _rows.add(row);
      }
    }
    setState(() {
      _level = level;
      _ready = true;
      _dirty = dirty;
      _error = null;
    });
  }

  Future<void> _selectLevel(int level) async {
    if (level == _level) {
      return;
    }
    if (_dirty && !await _confirmDiscard()) {
      return;
    }
    final settings = ref.read(settingsControllerProvider).value;
    if (!mounted || settings == null) {
      return;
    }
    _showLevel(settings, level, dirty: false);
  }

  Future<bool> _confirmDiscard() async {
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Modifications non enregistrées'),
        content: const Text('Abandonner les changements de cette courbe ?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Rester'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Abandonner'),
          ),
        ],
      ),
    );
    return discard == true;
  }

  Future<void> _addLevel() async {
    final controller = TextEditingController();
    final level = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nouveau niveau'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Niveau'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(context, int.tryParse(controller.text)),
            child: const Text('Ajouter'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (!mounted || level == null) {
      return;
    }
    if (level < Pm5Constants.minResistanceLevel ||
        level > Pm5Constants.maxResistanceLevel) {
      setState(() => _error = 'Le niveau doit être entre 1 et 32.');
      return;
    }
    final settings = ref.read(settingsControllerProvider).value;
    if (settings == null) {
      return;
    }
    if (_dirty && !await _confirmDiscard()) {
      return;
    }
    if (!mounted) {
      return;
    }
    _showLevel(settings, level, dirty: settings.levels[level] == null);
  }

  void _addPoint() {
    setState(() {
      _rows.add(_PointRow());
      _dirty = true;
      _error = null;
    });
  }

  void _deletePoint(_PointRow row) {
    setState(() {
      _rows.remove(row);
      _dirty = true;
      _error = null;
    });
    _disposeRowsLater([row]);
  }

  void _disposeRowsLater(List<_PointRow> rows) {
    if (rows.isEmpty) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final row in rows) {
        row.dispose();
      }
    });
  }

  void _resetCapture() {
    final defaults =
        AppSettings.defaultLevels()[Pm5Constants.defaultResistanceLevel]!;
    _disposeRowsLater(List<_PointRow>.of(_rows));
    _rows.clear();
    for (final point in defaults) {
      final row = _PointRow();
      row.rpm.text = _trim(point.rpm);
      row.watts.text = _trim(point.watts);
      _rows.add(row);
    }
    setState(() {
      _dirty = true;
      _error = null;
    });
  }

  Future<void> _save(AppSettings settings) async {
    if (_rows.any(_rowInvalid)) {
      setState(
        () => _error =
            'Chaque point doit avoir une cadence et des watts positifs.',
      );
      return;
    }
    final points = _validPoints();
    if (points.length < 2) {
      setState(() => _error = 'Au moins deux points valides sont nécessaires.');
      return;
    }
    final levels = {
      for (final entry in settings.levels.entries) entry.key: entry.value,
    };
    levels[_level] = points;
    await ref
        .read(settingsControllerProvider.notifier)
        .save(settings.copyWith(levels: levels, activeLevel: _level));
    if (!mounted) {
      return;
    }
    setState(() {
      _dirty = false;
      _error = null;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Calibration enregistrée. Niveau actif mis à jour.'),
      ),
    );
  }

  List<CalibrationPoint> _validPoints() {
    final points = <CalibrationPoint>[];
    for (final row in _rows) {
      final rpm = _parse(row.rpm.text);
      final watts = _parse(row.watts.text);
      if (rpm == null || watts == null || rpm <= 0 || watts <= 0) {
        continue;
      }
      points.add(CalibrationPoint(rpm: rpm, watts: watts));
    }
    return points;
  }

  bool _rowInvalid(_PointRow row) {
    final rpmText = row.rpm.text.trim();
    final wattsText = row.watts.text.trim();
    if (rpmText.isEmpty && wattsText.isEmpty) {
      return false;
    }
    final rpm = _parse(rpmText);
    final watts = _parse(wattsText);
    return rpm == null || watts == null || rpm <= 0 || watts <= 0;
  }

  double? _parse(String raw) =>
      double.tryParse(raw.trim().replaceAll(',', '.'));

  String _trim(double value) {
    final text = value.toStringAsFixed(1);
    return text.endsWith('.0') ? value.round().toString() : text;
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsControllerProvider).value;
    if (!_ready || settings == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final curve = PowerCurve.fromPoints(_validPoints());
    final levels = {...settings.levels.keys, _level}.toList()..sort();
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          const Text(
            'Calibration',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          const Text(
            'Table cadence → watts du niveau choisi. a et b sont recalculés à l’enregistrement.',
            style: TextStyle(color: Pm5Colors.muted),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<int>(
                  key: ValueKey(_level),
                  initialValue: _level,
                  decoration: const InputDecoration(labelText: 'Niveau'),
                  items: [
                    for (final level in levels)
                      DropdownMenuItem(
                        value: level,
                        child: Text('Niveau $level'),
                      ),
                  ],
                  onChanged: (level) {
                    if (level != null) {
                      _selectLevel(level);
                    }
                  },
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Nouveau niveau',
                onPressed: _addLevel,
                icon: const Icon(Icons.add),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _FitSummary(curve: curve),
          const SizedBox(height: 12),
          for (final row in _rows)
            Padding(
              key: ObjectKey(row),
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: row.rpm,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(labelText: 'RPM'),
                      onChanged: (_) => setState(() {
                        _dirty = true;
                        _error = null;
                      }),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: row.watts,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(labelText: 'Watts'),
                      onChanged: (_) => setState(() {
                        _dirty = true;
                        _error = null;
                      }),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Supprimer',
                    onPressed: () => _deletePoint(row),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                _error!,
                style: const TextStyle(color: Pm5Colors.warning),
              ),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _addPoint,
              icon: const Icon(Icons.add),
              label: const Text('Ajouter un point'),
            ),
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: () => _save(settings),
            child: Text(_dirty ? 'Enregistrer' : 'Enregistrer et activer'),
          ),
          if (_level == Pm5Constants.defaultResistanceLevel)
            TextButton(
              onPressed: _resetCapture,
              child: const Text('Revenir aux relevés du niveau 22'),
            ),
        ],
      ),
    );
  }
}

class _FitSummary extends StatelessWidget {
  const _FitSummary({required this.curve});

  final PowerCurve curve;

  @override
  Widget build(BuildContext context) {
    final fit = curve.fit;
    final min = curve.minRpm;
    final max = curve.maxRpm;
    final model = curve.points.length < 2
        ? 'Pas assez de points'
        : curve.usesInterpolation
        ? 'Interpolation linéaire'
        : 'Loi de puissance';
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Pm5Colors.panel,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(model, style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Text(
              fit == null
                  ? 'a —    b —'
                  : 'a ${_coef(fit.a)}    b ${_coef(fit.b)}    écart ${_percent(fit.meanAbsolutePercentageError)}',
            ),
            const SizedBox(height: 4),
            Text(
              min == null || max == null
                  ? 'Plage valide : —'
                  : 'Plage valide : ${min.round()} – ${max.round()} RPM',
              style: const TextStyle(color: Pm5Colors.muted),
            ),
            if (curve.decreases)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text(
                  'La courbe n’est pas croissante.',
                  style: TextStyle(color: Pm5Colors.warning),
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _coef(double value) => value.toStringAsFixed(3).replaceAll('.', ',');

  String _percent(double value) =>
      '${(value * 100).toStringAsFixed(1).replaceAll('.', ',')} %';
}
