import 'package:flutter/material.dart';

import '../ui/theme.dart';

/// Modify tab: change the catalog by typing or speaking ("Maggi ke teen packet bache hain").
/// Filled in by the next step (command parser, confirmation, voice).
class ModifyScreen extends StatelessWidget {
  const ModifyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      appBar: GinloHeader(),
      body: Center(child: Text('Type or speak to change prices and stock — coming next')),
    );
  }
}
