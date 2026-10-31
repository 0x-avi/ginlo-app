import 'package:flutter/material.dart';

import 'config.dart';
import 'screens/bill_screen.dart';
import 'screens/catalog_screen.dart';
import 'screens/home_screen.dart';
import 'screens/lab_screen.dart';
import 'screens/learn_screen.dart';
import 'screens/modify_screen.dart';
import 'ui/theme.dart';

void main() {
  // Any orientation: CameraFeed turns each frame to match how the phone is held.
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
      theme: ginloTheme(), // colours from the Ginlo logo, see ui/theme.dart
      home: const AppShell(),
    );
  }
}

/// Which screen each tab shows. The numbers are positions in the IndexedStack below.
abstract final class Tabs {
  static const bill = 0, home = 1, products = 2, learn = 3, modify = 4, lab = 5;
}

/// One tab: its icons, label and screen index.
typedef _Tab = ({IconData icon, IconData selected, String label, int index});

const _left = <_Tab>[
  (icon: Icons.home_outlined, selected: Icons.home, label: 'Home', index: Tabs.home),
  (icon: Icons.inventory_2_outlined, selected: Icons.inventory_2, label: 'Products', index: Tabs.products),
];
const _right = <_Tab>[
  (icon: Icons.school_outlined, selected: Icons.school, label: 'Learn', index: Tabs.learn),
  (icon: Icons.mic_none, selected: Icons.mic, label: 'Modify', index: Tabs.modify),
];
const _labTab = (icon: Icons.science_outlined, selected: Icons.science, label: 'Lab', index: Tabs.lab);

/// The app's frame: tabs around a big round Bill button in the middle.
/// Portrait: bottom bar with the Bill button sitting in a notch. Landscape: a rail on the left,
/// so the camera keeps its height. Opens on Bill.
///
/// Stateful because it remembers which tab is selected.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _tab = Tabs.bill; // the shopkeeper lands straight on billing

  // Portrait (bottom bar) and landscape (side rail) wrap the tabs differently; this key keeps the
  // tabs - and the running camera - the same widgets across the switch instead of rebuilding them.
  final _tabsKey = GlobalKey();

  void _select(int i) => setState(() => _tab = i);

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final landscape = size.width > size.height;
    final right = [..._right, if (isDev) _labTab];

    // IndexedStack keeps every tab alive, so switching tabs doesn't reset them
    // (e.g. a half-finished bill survives a quick look at the catalog).
    // Camera tabs get `active` so only the visible one runs its camera.
    final body = IndexedStack(
      key: _tabsKey,
      index: _tab,
      children: [
        BillScreen(active: _tab == Tabs.bill, onTeach: () => _select(Tabs.learn)),
        const HomeScreen(),
        const CatalogScreen(),
        LearnScreen(active: _tab == Tabs.learn),
        const ModifyScreen(),
        if (isDev) LabScreen(active: _tab == Tabs.lab),
      ],
    );

    if (landscape) {
      final all = [
        ..._left,
        (icon: Icons.receipt_long_outlined, selected: Icons.receipt_long, label: 'Bill', index: Tabs.bill),
        ...right,
      ];
      return Scaffold(
        body: SafeArea(
          child: Row(
            children: [
              // Scrolls when all the tabs don't fit on a short landscape screen.
              LayoutBuilder(
                builder: (context, c) => SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: c.maxHeight),
                    child: IntrinsicHeight(
                      child: NavigationRail(
                        selectedIndex: all.indexWhere((t) => t.index == _tab),
                        onDestinationSelected: (i) => _select(all[i].index),
                        labelType: NavigationRailLabelType.all,
                        destinations: [
                          for (final t in all)
                            NavigationRailDestination(
                              icon: Icon(t.icon),
                              selectedIcon: Icon(t.selected),
                              label: Text(t.label),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const VerticalDivider(width: 1),
              Expanded(child: body),
            ],
          ),
        ),
      );
    }

    Widget tab(_Tab t) {
      final selected = _tab == t.index;
      final color = selected ? GinloColors.blue : GinloColors.muted;
      return Expanded(
        child: InkResponse(
          onTap: () => _select(t.index),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(selected ? t.selected : t.icon, color: color),
              const SizedBox(height: 2),
              Text(
                t.label,
                style: TextStyle(fontSize: 12, color: color, fontWeight: selected ? FontWeight.w700 : FontWeight.w500),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      body: body,
      // The big round Bill button sits in a notch in the middle of the bar.
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      floatingActionButton: SizedBox(
        width: 68,
        height: 68,
        child: FloatingActionButton(
          heroTag: 'bill',
          shape: const CircleBorder(),
          backgroundColor: _tab == Tabs.bill ? GinloColors.blue : Colors.white,
          foregroundColor: _tab == Tabs.bill ? Colors.white : GinloColors.blue,
          elevation: 4,
          onPressed: () => _select(Tabs.bill),
          child: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.document_scanner, size: 28),
              Text('Bill', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ),
      bottomNavigationBar: BottomAppBar(
        color: Colors.white,
        shape: const CircularNotchedRectangle(),
        notchMargin: 8,
        height: 68,
        padding: EdgeInsets.zero,
        child: Row(
          children: [
            ..._left.map(tab),
            const SizedBox(width: 76), // room for the Bill button
            ...right.map(tab),
          ],
        ),
      ),
    );
  }
}
