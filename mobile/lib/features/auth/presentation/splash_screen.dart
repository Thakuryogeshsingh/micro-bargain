import 'package:flutter/material.dart';

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.storefront, size: 80, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 16),
          const CircularProgressIndicator(),
        ]),
      ),
    );
  }
}
