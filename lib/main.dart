import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'ble/scooter.dart';
import 'theme.dart';
import 'ui/battery_screen.dart';
import 'ui/ride_screen.dart';
import 'ui/scooter_screen.dart';
import 'ui/trips_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: C.surface2,
    systemNavigationBarIconBrightness: Brightness.light,
  ));
  runApp(const M365App());
  ScooterService.instance.init();
}

class M365App extends StatelessWidget {
  const M365App({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'M365 Dashboard',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        home: const HomeShell(),
      );
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  int _tab = 0;
  bool _dialogOpen = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ScooterService.instance.brain.addListener(_onBrain);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    ScooterService.instance.brain.removeListener(_onBrain);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ScooterService.instance.refreshBatteryOptimization();
      _onBrain();
    }
  }

  void _onBrain() {
    final p = ScooterService.instance.brain.pendingUnrecorded;
    if (p == null || _dialogOpen || !mounted) return;
    _dialogOpen = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final add = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          backgroundColor: C.surface,
          title: Text('Обнаружено ${p.km.toStringAsFixed(1)} км без записи'),
          content: Text(
            'Самокат проехал их, пока приложение не было подключено '
            '(между ${fmtDate(p.from)} и ${fmtDate(p.to)}).\n\n'
            'Добавить в историю? Километры точные, энергия примерная. '
            'На средний расход и прогнозы такие поездки не влияют.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Не добавлять')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Добавить')),
          ],
        ),
      );
      ScooterService.instance.brain.resolveUnrecorded(add == true);
      _dialogOpen = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      RideScreen(onOpenScooter: () => setState(() => _tab = 3)),
      const BatteryScreen(),
      const TripsScreen(),
      const ScooterScreen(),
    ];
    return Scaffold(
      body: IndexedStack(index: _tab, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.speed), label: 'Езда'),
          NavigationDestination(icon: Icon(Icons.battery_charging_full), label: 'Батарея'),
          NavigationDestination(icon: Icon(Icons.bar_chart), label: 'Поездки'),
          NavigationDestination(icon: Icon(Icons.electric_scooter), label: 'Самокат'),
        ],
      ),
    );
  }
}
