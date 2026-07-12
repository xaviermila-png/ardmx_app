import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/providers.dart';
import '../../widgets/app_scaffold.dart';

class CreditsScreen extends ConsumerWidget {
  const CreditsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final firmwareVersion = ref.watch(appStateProvider.select((s) => s.t62));

    return AppScaffold(
      title: 'Crèdits',
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('ARDMX4'),
            const SizedBox(height: 8),
            Text('Firmware Arduino: ${firmwareVersion ?? '—'}'),
          ],
        ),
      ),
    );
  }
}
