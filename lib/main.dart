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

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;

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
