import 'package:flutter/material.dart';

/// Brand colours, measured from the Ginlo logo and mock-ups.
class GinloColors {
  static const blue = Color(0xFF0035F5); // logo letters, buttons, selected tabs
  static const blueSoft = Color(0xFFE6ECFF); // chips, icon circles, selected rows
  static const yellow = Color(0xFFFECE28); // coin
  static const background = Color(0xFFEEF2FB); // light lavender page
  static const card = Colors.white;
  static const ink = Color(0xFF111827); // main text
  static const muted = Color(0xFF6B7280); // secondary text
  static const up = Color(0xFF16A34A); // "+12% from last month"
  static const down = Color(0xFFDC2626);

  /// Donut/legend colours, in order.
  static const chart = [blue, yellow, Color(0xFF6E8BFF), Color(0xFFB4C3FF), Color(0xFFC9CED8)];
}

ThemeData ginloTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: GinloColors.blue,
    primary: GinloColors.blue,
    secondary: GinloColors.yellow,
    surface: GinloColors.card,
  );
  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    scaffoldBackgroundColor: GinloColors.background,
    appBarTheme: const AppBarTheme(
      backgroundColor: GinloColors.background,
      foregroundColor: GinloColors.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleTextStyle: TextStyle(color: GinloColors.ink, fontSize: 20, fontWeight: FontWeight.w700),
    ),
    cardTheme: CardThemeData(
      color: GinloColors.card,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Colors.white,
      indicatorColor: GinloColors.blueSoft,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (s) => TextStyle(
          fontSize: 12,
          fontWeight: s.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
          color: s.contains(WidgetState.selected) ? GinloColors.blue : GinloColors.muted,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (s) => IconThemeData(color: s.contains(WidgetState.selected) ? GinloColors.blue : GinloColors.muted),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: GinloColors.blue,
        minimumSize: const Size(48, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      ),
    ),
  );
}

/// White rounded card used for every section (store, total sales, top item...).
class GinloCard extends StatelessWidget {
  const GinloCard({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.onTap});
  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

/// Top bar of the shop app: logo on the left, an optional action on the right.
class GinloHeader extends StatelessWidget implements PreferredSizeWidget {
  const GinloHeader({super.key, this.action});
  final Widget? action;

  @override
  Size get preferredSize => const Size.fromHeight(64);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      toolbarHeight: 64,
      titleSpacing: 16,
      title: Image.asset('assets/brand/ginlo_logo.png', height: 34),
      actions: [?action, const SizedBox(width: 8)],
    );
  }
}
