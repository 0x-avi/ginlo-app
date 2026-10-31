import 'package:flutter/material.dart';

/// Camera billing: photo -> items -> total -> UPI QR. Placeholder for now.
class BillScreen extends StatelessWidget {
  const BillScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('New bill')),
      body: const Center(child: Text('Camera billing will go here')),
    );
  }
}
