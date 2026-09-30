import 'package:flutter/material.dart';

import 'fingerprint_test_page.dart';

void main() => runApp(const FingerprintTestApp());

class FingerprintTestApp extends StatelessWidget {
  const FingerprintTestApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Fingerprint Test',
      theme: ThemeData(
        colorSchemeSeed: Colors.indigo,
        useMaterial3: true,
      ),
      home: const FingerprintTestPage(),
    );
  }
}
