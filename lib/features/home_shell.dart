import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pm5_bike/features/app_providers.dart';
import 'package:pm5_bike/features/calibration/calibration_screen.dart';
import 'package:pm5_bike/features/history/history_screen.dart';
import 'package:pm5_bike/features/live/live_screen.dart';
import 'package:pm5_bike/features/settings/settings_screen.dart';

class HomeShell extends ConsumerWidget {
  const HomeShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsControllerProvider);
    return settings.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (error, stackTrace) => const Scaffold(
        body: Center(child: Text('Impossible de lire les réglages.')),
      ),
      data: (_) => const _Shell(),
    );
  }
}

class _Shell extends StatefulWidget {
  const _Shell();

  @override
  State<_Shell> createState() => _ShellState();
}

class _ShellState extends State<_Shell> {
  var _index = 0;

  @override
  Widget build(BuildContext context) {
    final page = switch (_index) {
      0 => const LiveScreen(),
      1 => const HistoryScreen(),
      2 => const CalibrationScreen(),
      _ => const SettingsScreen(),
    };
    return Scaffold(
      body: page,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (index) => setState(() => _index = index),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.speed), label: 'Séance'),
          NavigationDestination(icon: Icon(Icons.history), label: 'Historique'),
          NavigationDestination(icon: Icon(Icons.tune), label: 'Calibration'),
          NavigationDestination(icon: Icon(Icons.settings), label: 'Réglages'),
        ],
      ),
    );
  }
}
