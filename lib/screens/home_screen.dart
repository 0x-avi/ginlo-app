import 'package:flutter/material.dart';

/// Earnings dashboard: today's total, number of bills, top items. Placeholder for now.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('GinLo')),
      body: const Center(child: Text("Today's earnings will show here")),
    );
  }
}
