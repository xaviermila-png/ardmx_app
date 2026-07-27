import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/v_map.dart';
import '../../core/protocol/virtuino_update.dart';
import '../../state/providers.dart';
import '../../widgets/app_scaffold.dart';

/// ARDMX One's "Configuració del sistema" screen — one level below the
/// normal "Paràmetres" screen (reached via its own button, not the back
/// arrow), on purpose: both fields here require a real recovery step from
/// the user (re-pairing after a Bluetooth rename, losing the current scene
/// after a factory reset), so they shouldn't be as casually reachable as
/// the day-to-day channel controls.
class ArdmxOneSystemConfigScreen extends StatelessWidget {
  const ArdmxOneSystemConfigScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Configuració del sistema',
      automaticallyImplyLeading: false,
      body: Column(
        children: [
          Expanded(
            // Without this, the keyboard opening while editing the
            // Bluetooth name shrinks the available height enough to
            // overflow the two sections below — same fix already applied
            // to ARDMX4's Parameters screen for the same reason.
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Section(
                    title: 'Nom Bluetooth',
                    child: const _BluetoothNameSection(),
                  ),
                  const SizedBox(height: 8),
                  const _ResetSection(),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Row(
              children: [
                FloatingActionButton(
                  heroTag: 'ardmxOneSystemConfigBack',
                  onPressed: () => Navigator.of(context).pop(),
                  tooltip: 'Tornar a paràmetres',
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

/// Lets the user rename the device's Bluetooth name (V63) — up to 12
/// characters, letters and digits only (see `sanitizeName()` in
/// `firmware/ardmx_one/src/main.cpp`, which enforces the same limit).
/// Renaming restarts the ESP32, so Android's paired-device name won't
/// update on its own — the confirmation dialog tells the user to
/// forget/re-pair it, then exits the app.
class _BluetoothNameSection extends ConsumerStatefulWidget {
  const _BluetoothNameSection();

  @override
  ConsumerState<_BluetoothNameSection> createState() =>
      _BluetoothNameSectionState();
}

class _BluetoothNameSectionState extends ConsumerState<_BluetoothNameSection> {
  static const _btNameVIndex = 63;
  static const _maxLength = 12;

  final _controller = TextEditingController();
  StreamSubscription<VirtuinoUpdate>? _subscription;

  @override
  void initState() {
    super.initState();
    _subscription = ref.read(protocolProvider).updates.listen((update) {
      if (update is VirtuinoTUpdate && update.index == _btNameVIndex) {
        _controller.text = update.text;
      }
    });
    ref.read(protocolProvider).requestT(_btNameVIndex);
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _rename() {
    final name = _controller.text.trim();
    if (name.isEmpty) return;
    ref.read(protocolProvider).writeText(_btNameVIndex, name);
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nom enviat'),
        content: Text(
          "L'ESP32 desarà el nom nou ($name) i es reiniciarà. "
          'Un cop reiniciat, oblida aquest dispositiu i torna\'l a '
          "aparellar des dels ajustos de Bluetooth d'Android per veure'l "
          "amb el nom nou. L'app es tancarà ara.",
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              SystemNavigator.pop();
            },
            child: const Text('D\'acord'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Text(
          'Fins a 12 caràcters, només lletres i xifres.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _controller,
          textAlign: TextAlign.center,
          maxLength: _maxLength,
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp('[a-zA-Z0-9]')),
          ],
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        const SizedBox(height: 4),
        ElevatedButton(onPressed: _rename, child: const Text('Canviar nom')),
      ],
    );
  }
}

/// Factory-reset section: same armed/confirm two-step pattern as ARDMX4's
/// Parameters screen (V41 arm, V42 confirm), reusing the exact same
/// `appStateProvider` intent methods since the wire indices are identical —
/// only the firmware's idea of "what a reset resets" differs, and that's
/// entirely on the device side. Here it clears the current scene (all
/// channel values) and resets the active-channels count back to its
/// default; the Bluetooth name is left untouched. Owns its own poll timer
/// for V41/V42 (this screen has nothing else to poll), same "nothing is
/// pushed unsolicited" pattern as every other screen.
class _ResetSection extends ConsumerStatefulWidget {
  const _ResetSection();

  @override
  ConsumerState<_ResetSection> createState() => _ResetSectionState();
}

class _ResetSectionState extends ConsumerState<_ResetSection> {
  static const _pollInterval = Duration(milliseconds: 400);

  Timer? _pollTimer;
  bool _resetPending = false;

  @override
  void initState() {
    super.initState();
    // Deferred a frame: _poll() calls ModalRoute.of(context), not
    // resolvable synchronously inside initState.
    WidgetsBinding.instance.addPostFrameCallback((_) => _poll());
    _pollTimer = Timer.periodic(_pollInterval, (_) => _poll());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    // Si l'usuari torna enrere amb el reset desbloquejat (ON) sense arribar
    // a prémer "Reset", el desarma — sense això quedava "ON" en tornar a
    // obrir aquesta pantalla, com si encara estigués actiu.
    if (ref.read(appStateProvider).resetArmed) {
      ref.read(appStateProvider.notifier).setResetArmed(false);
    }
    super.dispose();
  }

  void _poll() {
    // Only the topmost route should poll — see Scene/Channels for why two
    // screens polling at once can corrupt the wire protocol.
    if (!(ModalRoute.of(context)?.isCurrent ?? true)) return;
    ref.read(protocolProvider).requestAll([
      VIndex.resetConfirm1,
      VIndex.resetConfirm2,
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final resetArmed = ref.watch(appStateProvider.select((s) => s.resetArmed));

    // Mirrors ARDMX4's Parameters screen: the firmware sets V41/V42 back to
    // 0 itself once the reset has actually run — that's the real completion
    // signal, not the instant the write is sent.
    ref.listen(
      appStateProvider.select((s) => (s.resetArmed, s.resetConfirm2)),
      (previous, next) {
        if (_resetPending && !next.$1 && next.$2 == 0) {
          setState(() => _resetPending = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Escena i canals reinicialitzats')),
          );
          // Els nivells de canal es refresquen sols perquè la pantalla de
          // Canals els demana en un poll continu — però el pessebre, la
          // descripció, el nombre de canals actius i els noms dels 3 canals
          // seleccionats només es demanen un cop en obrir cada pantalla, així
          // que sense això quedaven amb el text antic fins a desconnectar i
          // reconnectar. Com que aquestes peticions van pel mateix stream
          // que qualsevol pantalla (Paràmetres, Canals) ja escolta, si
          // segueixen obertes sota d'aquesta reben el valor buit a l'instant.
          final protocol = ref.read(protocolProvider);
          protocol.requestT(68); // nom del pessebre
          protocol.requestT(69); // descripció
          protocol.requestV(8); // nombre de canals actius
          protocol.requestT(65); // nom del canal seleccionat, slot 1
          protocol.requestT(66); // nom del canal seleccionat, slot 2
          protocol.requestT(67); // nom del canal seleccionat, slot 3
        }
      },
    );

    return _Section(
      title: 'Reset de fàbrica',
      child: Column(
        children: [
          const Text(
            "Esborra l'escena actual (tots els canals a 0) i torna el "
            'nombre de canals actius al valor de fàbrica. El nom Bluetooth '
            'no es toca.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _SelectableButton(
                label: resetArmed ? 'ON' : 'OFF',
                selected: resetArmed,
                onTap: _resetPending
                    ? () {}
                    : () => ref
                          .read(appStateProvider.notifier)
                          .setResetArmed(!resetArmed),
              ),
              if (resetArmed || _resetPending) ...[
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: _resetPending
                      ? null
                      : () {
                          setState(() => _resetPending = true);
                          ref.read(appStateProvider.notifier).confirmReset();
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
        ],
      ),
    );
  }
}

class _SelectableButton extends StatelessWidget {
  const _SelectableButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 56,
      height: 56,
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: selected ? Colors.red.shade200 : null,
          foregroundColor: selected ? Colors.red.shade900 : null,
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
