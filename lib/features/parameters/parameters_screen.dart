import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/v_map.dart';
import '../../state/providers.dart';
import '../../widgets/app_scaffold.dart';

/// Parameters screen (V50=4): number of active scenes, song to play,
/// number of manageable channels, and the armed/confirm reset of Arduino
/// variables. All four values are plain Arduino state (V0/V18/V39/V40/V41),
/// never pushed unsolicited, so this screen polls them like every other
/// screen that shows live V-values.
class ParametersScreen extends ConsumerStatefulWidget {
  const ParametersScreen({super.key});

  @override
  ConsumerState<ParametersScreen> createState() => _ParametersScreenState();
}

class _ParametersScreenState extends ConsumerState<ParametersScreen> {
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

    // While waiting for the reset confirmation, the Arduino can be busy
    // long enough (actually reinitializing its variables) that polling the
    // full bundle piles up faster than it drains — observed on real
    // hardware as a burst of ~30 queued requests all replied to at once.
    // Narrow to just the two indices we're actually waiting on so the
    // serial link stays light while it's busy.
    if (_resetPending) {
      ref.read(protocolProvider).requestAll([
        VIndex.resetConfirm1,
        VIndex.resetConfirm2,
      ]);
      return;
    }

    ref.read(protocolProvider).requestAll([
      VIndex.activeScenesCount,
      VIndex.songNumber,
      VIndex.activeChannelsCount,
      VIndex.maxChannels,
      VIndex.resetConfirm1,
      VIndex.resetConfirm2,
    ]);
  }

  Future<void> _editChannelsCount(int current, int max) async {
    final controller = TextEditingController(text: '$current');
    String? error;

    final result = await showDialog<int>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            void submit() {
              final parsed = int.tryParse(controller.text);
              if (parsed == null || parsed < 0 || parsed > max) {
                setDialogState(() => error = 'Ha de ser entre 0 i $max');
                return;
              }
              if (parsed % 3 != 0) {
                setDialogState(() => error = 'Ha de ser múltiple de 3');
                return;
              }
              Navigator.of(context).pop(parsed);
            }

            return AlertDialog(
              title: const Text('Canals gestionables'),
              content: TextField(
                controller: controller,
                keyboardType: TextInputType.number,
                autofocus: true,
                decoration: InputDecoration(
                  errorText: error,
                  helperText: 'Múltiple de 3, entre 0 i $max',
                ),
                onSubmitted: (_) => submit(),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel·la'),
                ),
                TextButton(onPressed: submit, child: const Text("D'acord")),
              ],
            );
          },
        );
      },
    );

    if (result != null) {
      ref.read(appStateProvider.notifier).setActiveChannelsCount(result);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scenesCount = ref.watch(
      appStateProvider.select((s) => s.activeScenesCount),
    );
    final songNumber = ref.watch(appStateProvider.select((s) => s.songNumber));
    final channelsCount = ref.watch(
      appStateProvider.select((s) => s.activeChannelsCount),
    );
    final maxChannels = ref.watch(
      appStateProvider.select((s) => s.maxChannels),
    );
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

    return AppScaffold(
      title: 'Paràmetres',
      automaticallyImplyLeading: false,
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Section(
                    title: "Nombre d'escenes",
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        for (var n = 1; n <= 4; n++)
                          _SelectableButton(
                            label: '$n',
                            selected: scenesCount == n,
                            selectedBackground: Colors.orange.shade200,
                            selectedForeground: Colors.orange.shade900,
                            onTap: () => ref
                                .read(appStateProvider.notifier)
                                .setActiveScenesCount(n),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  _Section(
                    title: 'Cançó a reproduir',
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            _SelectableButton(
                              label: 'Off',
                              selected: songNumber == 0,
                              selectedBackground: Colors.blue.shade200,
                              selectedForeground: Colors.blue.shade900,
                              onTap: () => ref
                                  .read(appStateProvider.notifier)
                                  .setSongNumber(0),
                            ),
                            for (var n = 1; n <= 4; n++)
                              _SelectableButton(
                                label: '$n',
                                selected: songNumber == n,
                                selectedBackground: Colors.blue.shade200,
                                selectedForeground: Colors.blue.shade900,
                                onTap: () => ref
                                    .read(appStateProvider.notifier)
                                    .setSongNumber(n),
                              ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Off = No música',
                          style: TextStyle(fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  _Section(
                    title: 'Canals gestionables',
                    child: Column(
                      children: [
                        const Text(
                          'Màxim nombre de canals: 99',
                          style: TextStyle(fontSize: 14),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          '(ha de ser múltiple de 3)',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 13),
                        ),
                        const SizedBox(height: 6),
                        Center(
                          child: InkWell(
                            borderRadius: BorderRadius.circular(8),
                            onTap: () => _editChannelsCount(
                              channelsCount ?? 0,
                              maxChannels ?? 100,
                            ),
                            child: Container(
                              width: 90,
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              decoration: BoxDecoration(
                                color: Colors.green.shade600,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                '${channelsCount ?? '—'}',
                                style: const TextStyle(
                                  fontSize: 26,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'En transicions és recomanable que el nombre de '
                          'canals a gestionar no passi de 48',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 12, color: Colors.black54),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  _Section(
                    title: 'Reset de fàbrica',
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Single toggle button: tap to arm (OFF -> ON), tap again
                        // to disarm — this alone never resets anything, it just
                        // reveals the confirm button below/beside it.
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
                        // while _resetPending — confirmReset() optimistically
                        // flips resetArmed back to false immediately, but
                        // the button must stay up until the Arduino's own
                        // confirmation arrives.
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
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
            child: Row(
              children: [
                FloatingActionButton(
                  heroTag: 'parametersBack',
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
          // Material's default button padding left almost no room for
          // 3-letter labels ("Off"/"OFF") inside a 56×56 box, forcing the
          // FittedBox below to shrink them down to near-invisible.
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
