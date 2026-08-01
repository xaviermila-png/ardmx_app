import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/v_map.dart';
import '../../state/providers.dart';
import '../../widgets/app_scaffold.dart';

/// ARDMX4's "Configuració del sistema" screen — one level below the normal
/// "Paràmetres" screen (reached via its own button, not the back arrow),
/// mirroring ARDMX One's split: the factory reset requires a real recovery
/// step from the user (losing scene data), so it shouldn't be as casually
/// reachable as the day-to-day scene/song/channel controls on Paràmetres.
class ParametersSystemConfigScreen extends ConsumerStatefulWidget {
  const ParametersSystemConfigScreen({super.key});

  @override
  ConsumerState<ParametersSystemConfigScreen> createState() =>
      _ParametersSystemConfigScreenState();
}

class _ParametersSystemConfigScreenState
    extends ConsumerState<ParametersSystemConfigScreen> {
  static const _pollInterval = Duration(milliseconds: 400);

  Timer? _pollTimer;
  bool _resetPending = false;

  @override
  void initState() {
    super.initState();
    // Deferred a frame: _poll() calls ModalRoute.of(context), which isn't
    // resolvable synchronously inside initState (see Scene/Channels and RGB
    // Wheel for the same fix and the crash it avoids).
    WidgetsBinding.instance.addPostFrameCallback((_) => _poll());
    _pollTimer = Timer.periodic(_pollInterval, (_) => _poll());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  void _poll() {
    // Only the topmost route should poll — see Scene/Channels and RGB
    // Wheel's _poll() for why: two screens polling at once can corrupt the
    // wire protocol badly enough to leave garbage stuck in Arduino state.
    if (!(ModalRoute.of(context)?.isCurrent ?? true)) return;

    ref.read(protocolProvider).requestAll([
      VIndex.resetConfirm1,
      VIndex.resetConfirm2,
    ]);
  }

  // Si l'usuari desbloqueja el reset (ON) i torna enrere sense arribar a
  // confirmar-lo, el desarma abans de sortir — mateix fix que ja té la
  // pantalla equivalent de l'ARDMX One, per la fletxa i pel gest/botó
  // enrere del sistema (vegeu PopScope més avall).
  void _attemptBack() {
    if (ref.read(appStateProvider).resetArmed) {
      ref.read(appStateProvider.notifier).setResetArmed(false);
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final resetArmed = ref.watch(appStateProvider.select((s) => s.resetArmed));

    // The Arduino sets V41/V42 back to 0 itself once it has actually
    // finished reinitializing its variables — that's the real confirmation
    // of completion, not the instant we send the trigger (which only ever
    // proves the write was sent, not that the reset ran).
    ref.listen(
      appStateProvider.select((s) => (s.resetArmed, s.resetConfirm2)),
      (previous, next) {
        if (_resetPending && !next.$1 && next.$2 == 0) {
          setState(() => _resetPending = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Variables reinicialitzades')),
          );
        }
      },
    );

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _attemptBack();
      },
      child: AppScaffold(
        title: 'Configuració del sistema',
        automaticallyImplyLeading: false,
        body: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _Section(
                      title: 'Reset de fàbrica',
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // Single toggle button: tap to arm (OFF -> ON), tap
                          // again to disarm — this alone never resets
                          // anything, it just reveals the confirm button
                          // below/beside it.
                          _SelectableButton(
                            label: resetArmed ? 'ON' : 'OFF',
                            selected: resetArmed,
                            selectedBackground: Colors.red.shade200,
                            selectedForeground: Colors.red.shade900,
                            onTap: _resetPending
                                ? () {}
                                : () => ref
                                      .read(appStateProvider.notifier)
                                      .setResetArmed(!resetArmed),
                          ),
                          // Keep showing the confirm button (as a spinner)
                          // while _resetPending — confirmReset()
                          // optimistically flips resetArmed back to false
                          // immediately, but the button must stay up until
                          // the Arduino's own confirmation arrives.
                          if (resetArmed || _resetPending) ...[
                            const SizedBox(width: 12),
                            ElevatedButton(
                              onPressed: _resetPending
                                  ? null
                                  : () {
                                      setState(() => _resetPending = true);
                                      ref
                                          .read(appStateProvider.notifier)
                                          .confirmReset();
                                    },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red.shade700,
                                foregroundColor: Colors.white,
                                disabledBackgroundColor: Colors.grey.shade400,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 24,
                                  vertical: 16,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              child: _resetPending
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Text(
                                      'Reset',
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Row(
                children: [
                  FloatingActionButton(
                    heroTag: 'parametersSystemConfigBack',
                    onPressed: _attemptBack,
                    tooltip: 'Tornar a paràmetres',
                    child: const Icon(Icons.arrow_back),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Same card look as Paràmetres' own `_Section` — kept as its own private
/// copy here rather than shared (matching the same pattern already used by
/// ARDMX One's Paràmetres/Configuració del sistema split).
class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _SelectableButton extends StatelessWidget {
  const _SelectableButton({
    required this.label,
    required this.selected,
    required this.selectedBackground,
    required this.selectedForeground,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final Color selectedBackground;
  final Color selectedForeground;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 56,
      height: 56,
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: selected ? selectedBackground : null,
          foregroundColor: selected ? selectedForeground : null,
          elevation: selected ? 4 : 1,
          padding: const EdgeInsets.all(4),
          minimumSize: Size.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            label,
            maxLines: 1,
            softWrap: false,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ),
      ),
    );
  }
}
