import 'package:flutter/material.dart';

import '../config.dart';
import 'live_detect_view.dart';

/// Camera billing: photo -> items -> total -> UPI QR.
///
/// [active] is true while the Bill tab is on screen; the camera only runs then.
class BillScreen extends StatelessWidget {
  const BillScreen({super.key, required this.active});
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(isDev ? 'New bill · live detector' : 'New bill')),
      body: isDev && active ? const LiveDetectView() : const Center(child: Text('Camera billing will go here')),
    );
  }
}
