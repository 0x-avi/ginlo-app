import 'package:flutter/material.dart';

/// Products: list, teach a new product, edit price/stock. Placeholder for now.
class CatalogScreen extends StatelessWidget {
  const CatalogScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Catalog')),
      body: const Center(child: Text('Your products will show here')),
    );
  }
}
