import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'config.dart';
import 'screens/bill_screen.dart';
import 'screens/catalog_screen.dart';
import 'screens/home_screen.dart';
import 'screens/lab_screen.dart';
import 'screens/learn_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Portrait only: the camera frame rotation and box drawing assume it.
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(const GinLoApp());
}

/// The root of the app: theme + the first screen (the tab shell).
class GinLoApp extends StatelessWidget {
  const GinLoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GinLo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        // One seed colour; Material 3 derives the whole palette from it.
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF00BAF2)), // Paytm blue
        useMaterial3: true,
      ),
      home: const AppShell(),
    );
  }
}

/// Bottom tabs: Bill (opens first), Home (earnings), Catalog, Learn; dev adds Lab.
///
/// Stateful because it remembers which tab is selected.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _tab = 0; // Bill: the shopkeeper lands straight on billing

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // IndexedStack keeps every tab alive, so switching tabs doesn't reset them
      // (e.g. a half-finished bill survives a quick look at the catalog).
      // Camera tabs get `active` so only the visible one runs its camera.
      body: IndexedStack(
        index: _tab,
        children: [
          BillScreen(active: _tab == 0),
          const HomeScreen(),
          const CatalogScreen(),
          LearnScreen(active: _tab == 3),
          if (isDev) LabScreen(active: _tab == 4),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: [
          const NavigationDestination(
              icon: Icon(Icons.receipt_long_outlined), selectedIcon: Icon(Icons.receipt_long), label: 'Bill'),
          const NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Home'),
          const NavigationDestination(
              icon: Icon(Icons.inventory_2_outlined), selectedIcon: Icon(Icons.inventory_2), label: 'Catalog'),
          const NavigationDestination(
              icon: Icon(Icons.school_outlined), selectedIcon: Icon(Icons.school), label: 'Learn'),
          if (isDev)
            const NavigationDestination(icon: Icon(Icons.science_outlined), selectedIcon: Icon(Icons.science), label: 'Lab'),
        ],
      ),
    );
  }
}
