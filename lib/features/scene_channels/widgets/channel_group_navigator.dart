import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../state/providers.dart';
import 'nav_arrow_button.dart';

/// "<- CANALS ->" bar. The arrows write V[7] (channel-group order,
/// -1/0/+1) to slide the window of 3 channels; the actual channel numbers
/// (V4-V6) are shown inside each slider's own box below, not here.
class ChannelGroupNavigator extends ConsumerWidget {
  const ChannelGroupNavigator({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      color: Colors.blue.shade900,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            NavArrowButton(
              icon: Icons.arrow_back,
              onPressed: () =>
                  ref.read(appStateProvider.notifier).advanceChannelGroup(-1),
            ),
            const Expanded(
              child: Text(
                'CANALS',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            NavArrowButton(
              icon: Icons.arrow_forward,
              onPressed: () =>
                  ref.read(appStateProvider.notifier).advanceChannelGroup(1),
            ),
          ],
        ),
      ),
    );
  }
}
