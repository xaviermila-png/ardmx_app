import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_version.dart';
import '../../state/providers.dart';
import '../../widgets/app_scaffold.dart';

/// Credits screen (V50=9): fully static project info, no other V-values to
/// poll — the only live bit is the Arduino firmware version (T62), already
/// requested once on connect by AppStateNotifier.requestInitialSnapshot. The
/// app's own version ([kAppVersion]) is shared with the Splash screen so the
/// two never show different numbers.
class CreditsScreen extends ConsumerWidget {
  const CreditsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final firmwareVersion = ref.watch(appStateProvider.select((s) => s.t62));

    return AppScaffold(
      title: 'Crèdits',
      automaticallyImplyLeading: false,
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Image.asset(
                      'assets/imatges/ARDMX_Logo.png',
                      width: 120,
                      height: 120,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Projecte: ARDMX4',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Desenvolupat per: Xavier Milà',
                    style: TextStyle(fontSize: 16),
                  ),
                  const SizedBox(height: 8),
                  const SelectableText(
                    'Contacte: ardmx4@gmail.com',
                    style: TextStyle(fontSize: 16),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Llicència:',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Creative Commons BY-NC-SA 4.0',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Padding(
                    padding: EdgeInsets.only(left: 8),
                    child: Text(
                      'Aquest projecte és lliure per a ús personal i '
                      'educatiu. No es permet fer-ne ús comercial. Si el '
                      'modifiques, has de compartir-ho amb la comunitat.',
                      style: TextStyle(fontSize: 14),
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Més informació:',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
                  const SelectableText(
                    'ardmx4.wordpress.com',
                    style: TextStyle(fontSize: 16),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    "Versió de l'app: $kAppVersion",
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Firmware Arduino: ${firmwareVersion ?? '—'}',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
            child: Row(
              children: [
                FloatingActionButton(
                  heroTag: 'creditsBack',
                  onPressed: () => Navigator.of(context).pop(),
                  tooltip: 'Tornar al menú principal',
                  child: const Icon(Icons.arrow_back),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
