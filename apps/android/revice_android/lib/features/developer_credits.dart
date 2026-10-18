import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme.dart';

class DeveloperCredits extends StatefulWidget {
  const DeveloperCredits({super.key});
  @override
  State<DeveloperCredits> createState() => _DeveloperCreditsState();
}

class _DeveloperCreditsState extends State<DeveloperCredits> {
  static const channel = MethodChannel('app.revice/monitoring');
  late final Future<Map<dynamic, dynamic>?> metadata = _metadata();
  Future<Map<dynamic, dynamic>?> _metadata() async {
    try {
      return await channel.invokeMapMethod('appMetadata');
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  Future<void> _openGitHub() async {
    var opened = false;
    try {
      opened =
          await channel.invokeMethod<bool>('openDeveloperProfile') ?? false;
    } on PlatformException {
      /* Show a helpful fallback below. */
    } on MissingPluginException {
      /* Only supported on the native Android app. */
    }
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Could not open a browser. Visit https://github.com/Paim41',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Developer Credits')),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Image.asset(
            'assets/revice-app-icon.png',
            height: 88,
            semanticLabel: 'Official Revice icon',
          ),
          const SizedBox(height: 12),
          const Text(
            'Revice',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.w700,
              color: lime,
            ),
          ),
          const Text(
            'Revive the Device',
            textAlign: TextAlign.center,
            style: TextStyle(color: muted),
          ),
          const SizedBox(height: 24),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.code_rounded, color: cyan),
                    title: Text('Paim41'),
                    subtitle: Text('Developer'),
                  ),
                  const SelectableText(
                    'https://github.com/Paim41',
                    style: TextStyle(color: cyan),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _openGitHub,
                    icon: const Icon(Icons.open_in_new),
                    label: const Text('Open GitHub'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: FutureBuilder<Map<dynamic, dynamic>?>(
                future: metadata,
                builder: (context, snapshot) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Application information',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text('Revice • Android'),
                    Text(
                      'Version: ${snapshot.data?['version'] ?? (snapshot.connectionState == ConnectionState.waiting ? 'Loading…' : 'Unavailable')}',
                    ),
                    Text('Build: ${snapshot.data?['build'] ?? 'Unavailable'}'),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'Developed by Paim41',
            textAlign: TextAlign.center,
            style: TextStyle(color: muted),
          ),
        ],
      ),
    ),
  );
}
