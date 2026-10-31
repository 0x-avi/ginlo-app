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
  // Portrait only: one simple, steady camera view; frames are turned by the sensor's fixed angle.
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

/// One tab: its icons and label.
typedef _Tab = ({IconData icon, IconData selected, String label});

const List<_Tab> _tabs = [
  (icon: Icons.receipt_long_outlined, selected: Icons.receipt_long, label: 'Bill'),
  (icon: Icons.home_outlined, selected: Icons.home, label: 'Home'),
  (icon: Icons.inventory_2_outlined, selected: Icons.inventory_2, label: 'Catalog'),
  (icon: Icons.school_outlined, selected: Icons.school, label: 'Learn'),
  (icon: Icons.science_outlined, selected: Icons.science, label: 'Lab'), // dev only
];

/// Tabs: Bill (opens first), Home (earnings), Catalog, Learn; dev adds Lab.
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
    final tabs = isDev ? _tabs : _tabs.sublist(0, 4);

    // IndexedStack keeps every tab alive, so switching tabs doesn't reset them
    // (e.g. a half-finished bill survives a quick look at the catalog).
    // Camera tabs get `active` so only the visible one runs its camera.
    final body = IndexedStack(
      index: _tab,
      children: [
        BillScreen(active: _tab == 0),
        const HomeScreen(),
        const CatalogScreen(),
        LearnScreen(active: _tab == 3),
        if (isDev) LabScreen(active: _tab == 4),
      ],
    );
    void select(int i) => setState(() => _tab = i);

    return Scaffold(
      body: body,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: select,
        destinations: [
          for (final t in tabs)
            NavigationDestination(icon: Icon(t.icon), selectedIcon: Icon(t.selected), label: t.label),
        ],
      ),
    );
  }
}
