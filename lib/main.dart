import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'screens/bill_screen.dart';
import 'screens/catalog_screen.dart';
import 'screens/home_screen.dart';

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

/// Bottom tabs: Home (earnings), Bill (camera billing), Catalog (products).
///
/// Stateful because it remembers which tab is selected.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // IndexedStack keeps every tab alive, so switching tabs doesn't reset them
      // (e.g. a half-finished bill survives a quick look at the catalog).
      body: IndexedStack(
        index: _tab,
        children: [const HomeScreen(), BillScreen(active: _tab == 1), const CatalogScreen()],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Home'),
          NavigationDestination(
              icon: Icon(Icons.receipt_long_outlined), selectedIcon: Icon(Icons.receipt_long), label: 'Bill'),
          NavigationDestination(
              icon: Icon(Icons.inventory_2_outlined), selectedIcon: Icon(Icons.inventory_2), label: 'Catalog'),
        ],
      ),
    );
  }
}
