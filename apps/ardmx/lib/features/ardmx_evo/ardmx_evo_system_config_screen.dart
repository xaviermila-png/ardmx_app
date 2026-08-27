import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/bluetooth/device_identification_service.dart';
import '../../core/constants/v_map.dart';
import '../../core/protocol/virtuino_update.dart';
import '../../state/providers.dart';
import '../../widgets/app_scaffold.dart';
import '../system_config/config_json.dart';
import '../system_config/widgets/export_import_section.dart';

/// ARDMX EVO's "Configuració del sistema" screen — one level below
/// "Paràmetres" (reached via its own button, not the back arrow), same
/// reasoning as ARDMX4's and ARDMX One's own split: everything here
/// (Bluetooth rename, factory reset, full-config export/import) requires a
/// real recovery step or is destructive, so it shouldn't be as casually
/// reachable as the day-to-day controls on Paràmetres.
class ArdmxEvoSystemConfigScreen extends ConsumerWidget {
  const ArdmxEvoSystemConfigScreen({super.key});

  // Same disarm-on-leave fix as ARDMX One's system config screen: if the
  // user unlocks the reset (ON) and leaves without confirming, disarm it
  // first — otherwise it stays "ON" the next time this screen opens.
  // Centralized here (not in a widget's dispose()) so it covers both the
  // back-arrow FAB and the system back gesture (see PopScope below).
  void _attemptBack(WidgetRef ref, BuildContext context) {
    if (ref.read(appStateProvider).resetArmed) {
      ref.read(appStateProvider.notifier).setResetArmed(false);
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _attemptBack(ref, context);
      },
      child: AppScaffold(
        title: 'Configuració',
        onBack: () => _attemptBack(ref, context),
        body: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Section(
                title: 'Nom Bluetooth',
                child: const _BluetoothNameSection(),
              ),
              const SizedBox(height: 8),
              _Section(
                title: 'PIN de connexió',
                child: const _PinSection(),
              ),
              const SizedBox(height: 8),
              _Section(
                title: 'Exportació/Importació de la configuració',
                child: const ExportImportSection(
                  origen: ArdmxConfigData.origenEvo,
                  channelCountVIndex: VIndex.activeChannelsCount,
                  hasAudio: true,
                  hasEvents: true,
                  fileNamePrefix: 'ardmx_evo',
                ),
              ),
              const SizedBox(height: 8),
              const _ResetSection(),
            ],
          ),
        ),
      ),
    );
  }
}

/// Sets or clears the device's connection PIN (V74 to set/read, V75 to
/// clear — see [DeviceIdentificationService], which also handles V64's
/// "pin" flag and V73's verify-on-connect). Reading V74 back is only
/// reachable once already authenticated (or when no PIN is set), same
/// gating as any other index — see main.cpp's `gated` check — so showing
/// it here doesn't expose anything the app hasn't already proven it knows.
class _PinSection extends ConsumerStatefulWidget {
  const _PinSection();

  @override
  ConsumerState<_PinSection> createState() => _PinSectionState();
}

class _PinSectionState extends ConsumerState<_PinSection> {
  // Índex de lectura del PIN actual — deliberadament diferent del 74 (que
  // és l'índex d'escriptura/ACK de setPin, vegeu DeviceIdentificationService):
  // si es fes servir el mateix, l'ACK "OK"/"ERROR" d'una desada arribaria
  // per aquest mateix listener i es mostraria com si fos el PIN.
  static const _pinReadVIndex = 76;

  final _controller = TextEditingController();
  StreamSubscription<VirtuinoUpdate>? _subscription;
  bool _busy = false;
  bool _obscure = true;

  @override
  void initState() {
    super.initState();
    _subscription = ref.read(protocolProvider).updates.listen((update) {
      if (update is VirtuinoTUpdate && update.index == _pinReadVIndex) {
        _controller.text = update.text;
      }
    });
    ref.read(protocolProvider).requestT(_pinReadVIndex);
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _controller.dispose();
    super.dispose();
  }

  bool get _hasPin =>
      ref.read(deviceIdentificationServiceProvider.notifier).requiresPin;

  Future<void> _setPin() async {
    final pin = _controller.text;
    if (pin.length != 4) return;
    setState(() => _busy = true);
    final ok = await ref
        .read(deviceIdentificationServiceProvider.notifier)
        .setPin(pin);
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok ? 'PIN activat.' : "No s'ha pogut desar el PIN."),
      ),
    );
  }

  Future<void> _removePin() async {
    setState(() => _busy = true);
    final ok = await ref
        .read(deviceIdentificationServiceProvider.notifier)
        .resetPin();
    if (!mounted) return;
    if (ok) _controller.clear();
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok ? 'PIN desactivat.' : "No s'ha pogut treure el PIN."),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          _hasPin
              ? 'Activat: cal aquest PIN per connectar-s\'hi.'
              : "Desactivat: qualsevol es pot connectar-hi sense PIN.",
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 13),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _controller,
          textAlign: TextAlign.center,
          keyboardType: TextInputType.number,
          maxLength: 4,
          obscureText: _obscure,
          enabled: !_busy,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(
            counterText: '',
            border: const OutlineInputBorder(),
            suffixIcon: IconButton(
              icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
              onPressed: () => setState(() => _obscure = !_obscure),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            FilledButton(
              onPressed: _busy ? null : _setPin,
              child: Text(_hasPin ? 'Canviar PIN' : 'Activar PIN'),
            ),
            if (_hasPin) ...[
              const SizedBox(width: 12),
              OutlinedButton(
                onPressed: _busy ? null : _removePin,
                child: const Text('Treure PIN'),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

/// Lets the user rename the device's Bluetooth name (V63, same wire index
/// as ARDMX One) — freely editable per the project spec (no reserved
/// prefix required), up to 15 characters. Renaming restarts the ESP32, so
/// Android's paired-device name won't update on its own.
class _BluetoothNameSection extends ConsumerStatefulWidget {
  const _BluetoothNameSection();

  @override
  ConsumerState<_BluetoothNameSection> createState() =>
      _BluetoothNameSectionState();
}

class _BluetoothNameSectionState extends ConsumerState<_BluetoothNameSection> {
  static const _btNameVIndex = 63;
  static const _maxLength = 15;

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
          'Fins a 15 caràcters: lletres, xifres i "_".',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _controller,
          textAlign: TextAlign.center,
          maxLength: _maxLength,
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp('[a-zA-Z0-9_]')),
          ],
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        const SizedBox(height: 4),
        FilledButton(onPressed: _rename, child: const Text('Canviar nom')),
      ],
    );
  }
}

/// Factory-reset section: same armed/confirm two-step pattern (V41 arm, V42
/// confirm) as ARDMX4's and ARDMX One's own reset sections, reusing the
/// same `appStateProvider` intent methods since the wire indices are
/// identical (the EVO firmware ports `performFactoryReset()` from the
/// Mega). Owns its own poll timer for V41/V42.
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
    WidgetsBinding.instance.addPostFrameCallback((_) => _poll());
    _pollTimer = Timer.periodic(_pollInterval, (_) => _poll());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  void _poll() {
    if (!(ModalRoute.of(context)?.isCurrent ?? true)) return;
    ref.read(protocolProvider).requestAll([
      VIndex.resetConfirm1,
      VIndex.resetConfirm2,
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final resetArmed = ref.watch(appStateProvider.select((s) => s.resetArmed));

    ref.listen(
      appStateProvider.select((s) => (s.resetArmed, s.resetConfirm2)),
      (previous, next) {
        if (_resetPending && !next.$1 && next.$2 == 0) {
          setState(() => _resetPending = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Configuració reinicialitzada')),
          );
          // Mateix problema que a ARDMX4/ARDMX One: sense re-demanar-ho
          // explícitament, qualsevol pantalla oberta per sota (Escenes,
          // Paràmetres) es queda amb els valors antics fins a reconnectar.
          final protocol = ref.read(protocolProvider);
          protocol.requestV(VIndex.activeScenesCount);
          protocol.requestV(VIndex.songNumber);
          protocol.requestV(VIndex.activeChannelsCount);
          protocol.requestV(VIndex.activeScene);
          protocol.requestV(VIndex.channel1Value);
          protocol.requestV(VIndex.channel2Value);
          protocol.requestV(VIndex.channel3Value);
          protocol.requestT(65);
          protocol.requestT(66);
          protocol.requestT(67);
          protocol.requestT(68);
          protocol.requestT(69);
        }
      },
    );

    return _Section(
      title: 'Reset de fàbrica',
      child: Column(
        children: [
          const Text(
            'Esborra tota la configuració (escenes, canals, noms, pessebre '
            'i descripció) i la torna als valors de fàbrica. El nom '
            'Bluetooth no es toca.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _SelectableButton(
                // Action-oriented label (what tapping does), not a state
                // display: "ON" invites arming it, and once armed (Reset
                // button showing) it becomes "OFF" to invite disarming it.
                label: resetArmed ? 'OFF' : 'ON',
                selected: resetArmed,
                onTap: _resetPending
                    ? () {}
                    : () => ref
                          .read(appStateProvider.notifier)
                          .setResetArmed(!resetArmed),
              ),
              if (resetArmed || _resetPending) ...[
                const SizedBox(width: 12),
                FilledButton(
                  onPressed: _resetPending
                      ? null
                      : () {
                          setState(() => _resetPending = true);
                          ref.read(appStateProvider.notifier).confirmReset();
                        },
                  style: FilledButton.styleFrom(
                    // A destructive action, not a normal selected/active
                    // state — colorScheme.error is MD3's semantic role for
                    // this, not primary.
                    backgroundColor: Theme.of(context).colorScheme.error,
                    foregroundColor: Theme.of(context).colorScheme.onError,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 16,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: _resetPending
                      ? SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Theme.of(context).colorScheme.onError,
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
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      selected: selected,
      child: SizedBox(
        width: 56,
        height: 56,
        child: FilledButton(
          onPressed: onTap,
          style: FilledButton.styleFrom(
            // Armed/OFF toggle for the destructive reset flow below — the
            // errorContainer pair (not primaryContainer) since it's arming a
            // dangerous action, not a normal selection.
            backgroundColor: selected
                ? scheme.errorContainer
                : scheme.surfaceContainerHighest,
            foregroundColor: selected
                ? scheme.onErrorContainer
                : scheme.onSurfaceVariant,
            elevation: selected ? 4 : 1,
            padding: const EdgeInsets.all(4),
            minimumSize: Size.zero,
            // The selected (armed) state isn't color/elevation alone — a
            // visible border carries the same information non-color-
            // dependently too.
            side: selected
                ? BorderSide(color: scheme.error, width: 2)
                : BorderSide.none,
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
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
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
