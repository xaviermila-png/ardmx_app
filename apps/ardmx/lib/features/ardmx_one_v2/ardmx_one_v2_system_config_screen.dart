import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/v_map.dart';
import '../../core/protocol/virtuino_update.dart';
import '../../state/providers.dart';
import '../../widgets/app_scaffold.dart';
import 'config_json.dart';

/// ARDMX One v2's "Configuració del sistema" screen — one level below
/// "Paràmetres" (reached via its own button, not the back arrow), same
/// reasoning as ARDMX EVO's own [ArdmxEvoSystemConfigScreen] (kept as its
/// own copy, per this project's separate-navigation-per-product decision):
/// everything here (Bluetooth rename, factory reset, full-config
/// export/import) requires a real recovery step or is destructive.
class ArdmxOneV2SystemConfigScreen extends ConsumerWidget {
  const ArdmxOneV2SystemConfigScreen({super.key});

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
                child: const _ExportImportSection(),
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

/// Sets or clears the device's connection PIN — identical to the ARDMX EVO
/// tree's own `_PinSection` (same V73-76 protocol, same firmware pattern in
/// ardmx-one-firmware/src/main.cpp).
class _PinSection extends ConsumerStatefulWidget {
  const _PinSection();

  @override
  ConsumerState<_PinSection> createState() => _PinSectionState();
}

class _PinSectionState extends ConsumerState<_PinSection> {
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

/// Renames the device's Bluetooth name (V63, same wire index as v1/EVO) —
/// up to 15 characters. Renaming restarts the ESP32.
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
/// confirm) as ARDMX One v1's and EVO's own reset sections — same wire
/// indices, so the shared `appStateProvider` intent methods work unchanged.
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
          final protocol = ref.read(protocolProvider);
          protocol.requestV(VIndex.activeScenesCount);
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
            'Esborra tota la configuració (escenes, transicions, canals, '
            'noms, pessebre i descripció) i la torna als valors de fàbrica. '
            'El nom Bluetooth no es toca.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _SelectableButton(
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

/// Exports the whole ARDMX One v2 configuration (scene count, active
/// channel count, the 8 cycle period durations, pessebre name, descripció,
/// and every active channel's 4 per-scene values+name) as a JSON file, or
/// imports one back — same V71 (4 values+name, no mode) protocol and
/// "Save As" flow (defaults to Baixades/Downloads) as the ARDMX EVO tree's
/// own `_ExportImportSection`.
class _ExportImportSection extends ConsumerStatefulWidget {
  const _ExportImportSection();

  @override
  ConsumerState<_ExportImportSection> createState() =>
      _ExportImportSectionState();
}

class _ExportImportSectionState extends ConsumerState<_ExportImportSection> {
  static const _firmwareVersionVIndex = 62;
  static const _pessebreVIndex = 68;
  static const _descripcioVIndex = 69;
  static const _numeroCanalsVIndex = 8;
  static const _channelBulkVIndex = 71;
  static const _roundTripTimeout = Duration(milliseconds: 800);

  static const _androidDownloadsUri =
      'content://com.android.externalstorage.documents/document/primary:Download';

  bool _running = false;
  String? _statusText;
  int _progress = 0;
  int _progressTotal = 1;

  Future<String?> _readText(int index) async {
    final protocol = ref.read(protocolProvider);
    final completer = Completer<String?>();
    late final StreamSubscription<VirtuinoUpdate> sub;
    sub = protocol.updates.listen((update) {
      if (update is VirtuinoTUpdate &&
          update.index == index &&
          !completer.isCompleted) {
        completer.complete(update.text);
      }
    });
    protocol.requestT(index);
    final result = await completer.future.timeout(
      const Duration(seconds: 2),
      onTimeout: () => null,
    );
    await sub.cancel();
    return result;
  }

  Future<double?> _readValue(int index) async {
    final protocol = ref.read(protocolProvider);
    final completer = Completer<double?>();
    late final StreamSubscription<VirtuinoUpdate> sub;
    sub = protocol.updates.listen((update) {
      if (update is VirtuinoVUpdate &&
          update.index == index &&
          !completer.isCompleted) {
        completer.complete(update.value);
      }
    });
    protocol.requestV(index);
    final result = await completer.future.timeout(
      const Duration(seconds: 2),
      onTimeout: () => null,
    );
    await sub.cancel();
    return result;
  }

  Future<bool> _writeVerified(int index, num value) async {
    final protocol = ref.read(protocolProvider);
    for (var attempt = 0; attempt < 6; attempt++) {
      protocol.writeV(index, value);
      final readBack = await _readValue(index);
      if (readBack != null && readBack.round() == value.round()) return true;
      await Future.delayed(const Duration(milliseconds: 400));
    }
    return false;
  }

  Future<String?> _channelRoundTripOnce(String payload) async {
    final protocol = ref.read(protocolProvider);
    final completer = Completer<String?>();
    late final StreamSubscription<VirtuinoUpdate> sub;
    sub = protocol.updates.listen((update) {
      if (update is VirtuinoTUpdate &&
          update.index == _channelBulkVIndex &&
          !completer.isCompleted) {
        completer.complete(update.text);
      }
    });
    protocol.writeText(_channelBulkVIndex, payload);
    final reply = await completer.future.timeout(
      _roundTripTimeout,
      onTimeout: () => null,
    );
    await sub.cancel();
    return reply;
  }

  Future<String?> _channelRoundTrip(String payload) async {
    for (var attempt = 0; attempt < 3; attempt++) {
      final reply = await _channelRoundTripOnce(payload);
      if (reply != null) return reply;
    }
    return null;
  }

  (List<int>, String)? _parseChannelReply(String? reply) {
    if (reply == null) return null;
    final parts = reply.split('|');
    if (parts.length < 5) return null;
    final valors = [for (var i = 0; i < 4; i++) int.tryParse(parts[i]) ?? 0];
    final name = parts.sublist(4).join('|');
    return (valors, name);
  }

  /// V72 round trip (same convention as [GlobalTransitionEditor]): `"Q"` to
  /// query, `"t1|s1|t2|s2|t3|s3|t4|s4"` to assign (never `"?"` — that
  /// collides with the wire protocol's own universal read-request
  /// convention, see main.cpp's processFrame()).
  Future<String?> _transitionsRoundTrip(String payload) async {
    final protocol = ref.read(protocolProvider);
    for (var attempt = 0; attempt < 3; attempt++) {
      final completer = Completer<String?>();
      late final StreamSubscription<VirtuinoUpdate> sub;
      sub = protocol.updates.listen((update) {
        if (update is VirtuinoTUpdate &&
            update.index == VIndex.transitionsBulk &&
            !completer.isCompleted) {
          completer.complete(update.text);
        }
      });
      protocol.writeText(VIndex.transitionsBulk, payload);
      final reply = await completer.future.timeout(
        _roundTripTimeout,
        onTimeout: () => null,
      );
      await sub.cancel();
      if (reply != null) return reply;
    }
    return null;
  }

  List<TransicioConfigEntry>? _parseTransitionsReply(String? reply) {
    if (reply == null) return null;
    final parts = reply.split('|');
    if (parts.length < 8) return null;
    return [
      for (var i = 0; i < 8; i += 2)
        TransicioConfigEntry(
          tipus: int.tryParse(parts[i]) ?? 0,
          saltPercent: int.tryParse(parts[i + 1]) ?? 0,
        ),
    ];
  }

  Future<bool> _assignChannelVerified(
    ArdmxOneV2ChannelConfigEntry entry,
  ) async {
    final payload = '${entry.number}|${entry.valors.join('|')}|${entry.name}';

    for (var attempt = 0; attempt < 6; attempt++) {
      final parsed = _parseChannelReply(await _channelRoundTripOnce(payload));
      if (parsed != null &&
          _listEquals(parsed.$1, entry.valors) &&
          parsed.$2 == entry.name) {
        return true;
      }
      await Future.delayed(const Duration(milliseconds: 400));
    }
    return false;
  }

  bool _listEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  String _suggestedFileName(String pessebre) {
    final clean = pessebre
        .trim()
        .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '')
        .replaceAll(RegExp(r'\s+'), '_');
    return clean.isEmpty ? 'ardmx_one.json' : 'ardmx_one_$clean.json';
  }

  Future<void> _export() async {
    setState(() {
      _running = true;
      _statusText = 'Llegint configuració…';
      _progress = 0;
      _progressTotal = 1;
    });
    try {
      final firmwareVersio = await _readText(_firmwareVersionVIndex) ?? '';
      final pessebre = await _readText(_pessebreVIndex) ?? '';
      final descripcio = await _readText(_descripcioVIndex) ?? '';
      final numeroEscenes = await _readValue(VIndex.activeScenesCount) ?? 0;
      final numeroCanals = await _readValue(_numeroCanalsVIndex);
      if (numeroCanals == null || numeroCanals <= 0) {
        _showMessage('No s\'ha pogut llegir el nombre de canals gestionables.');
        return;
      }

      final periodes = <double>[];
      for (var i = 0; i < 8; i++) {
        periodes.add(await _readValue(VIndex.periodDuration(i)) ?? 0);
      }

      final transicions = _parseTransitionsReply(
        await _transitionsRoundTrip('Q'),
      );

      final canalsCount = numeroCanals.round();
      final canals = <ArdmxOneV2ChannelConfigEntry>[];
      setState(() {
        _progressTotal = canalsCount;
        _statusText = 'Llegint canals…';
      });
      for (var channel = 1; channel <= canalsCount; channel++) {
        final parsed = _parseChannelReply(await _channelRoundTrip('$channel'));
        canals.add(
          ArdmxOneV2ChannelConfigEntry(
            number: channel,
            valors: parsed?.$1 ?? const [0, 0, 0, 0],
            name: parsed?.$2 ?? '',
          ),
        );
        if (!mounted) return;
        setState(() => _progress = channel);
      }

      final config = ArdmxOneV2ConfigData(
        numeroEscenes: numeroEscenes.round(),
        numeroCanals: canalsCount,
        periodes: periodes,
        pessebre: pessebre,
        descripcio: descripcio,
        canals: canals,
        transicions: transicions ?? const [],
        firmwareVersio: firmwareVersio,
        exportatEl: DateTime.now(),
      );
      final savedPath = await FilePicker.saveFile(
        fileName: _suggestedFileName(pessebre),
        type: FileType.custom,
        allowedExtensions: ['json'],
        initialDirectory: _androidDownloadsUri,
        bytes: Uint8List.fromList(utf8.encode(config.toPrettyJson())),
      );
      if (savedPath != null) _showMessage('Configuració desada.');
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  Future<bool> _confirmImport(ArdmxOneV2ConfigData config) async {
    final exportatEl = config.exportatEl;
    final origen = [
      if (config.firmwareVersio.isNotEmpty) config.firmwareVersio,
      if (exportatEl != null)
        'exportat el ${exportatEl.day.toString().padLeft(2, '0')}/'
            '${exportatEl.month.toString().padLeft(2, '0')}/'
            '${exportatEl.year} '
            '${exportatEl.hour.toString().padLeft(2, '0')}:'
            '${exportatEl.minute.toString().padLeft(2, '0')}',
    ].join(', ');
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Importar configuració?'),
        content: Text(
          "Es sobreescriuran el nombre d'escenes, el nombre de canals, els "
          'temps de transició, el pessebre, la descripció i els valors/noms '
          'de ${config.canals.length} canals '
          '${config.transicions.length == 4 ? 'i les 4 transicions globals ' : ''}'
          'amb el contingut del fitxer.'
          '${origen.isNotEmpty ? '\n\nFitxer: $origen' : ''}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel·lar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Importar'),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  Future<void> _import() async {
    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
      initialDirectory: _androidDownloadsUri,
    );
    final path = picked?.files.singleOrNull?.path;
    if (path == null) return;

    final ArdmxOneV2ConfigData config;
    try {
      config = ArdmxOneV2ConfigData.fromPrettyJson(
        await File(path).readAsString(),
      );
    } catch (_) {
      _showMessage('El fitxer no és un JSON vàlid de configuració.');
      return;
    }
    if (config.numeroCanals <= 0 || config.canals.isEmpty) {
      _showMessage('El fitxer no conté cap canal.');
      return;
    }
    if (config.model.isNotEmpty &&
        config.model != ArdmxOneV2ConfigData.defaultModel) {
      _showMessage(
        'Aquest fitxer és de "${config.model}", no d\'ARDMX One v2. '
        'No s\'ha importat.',
      );
      return;
    }

    if (!await _confirmImport(config)) return;

    const paramStepCount = 12;
    setState(() {
      _running = true;
      _statusText = 'Aplicant configuració…';
      _progress = 0;
      _progressTotal = paramStepCount + config.canals.length;
    });
    try {
      final paramFailures = <String>[];
      Future<void> writeParam(String label, int index, num value) async {
        if (!await _writeVerified(index, value)) paramFailures.add(label);
        if (mounted) setState(() => _progress++);
      }

      await writeParam(
        'nombre d\'escenes',
        VIndex.activeScenesCount,
        config.numeroEscenes,
      );
      await writeParam(
        'nombre de canals',
        _numeroCanalsVIndex,
        config.numeroCanals,
      );
      for (var i = 0; i < 8 && i < config.periodes.length; i++) {
        await writeParam(
          'temps de transició ${i + 1}',
          VIndex.periodDuration(i),
          config.periodes[i],
        );
      }

      final protocol = ref.read(protocolProvider);
      protocol.writeText(_pessebreVIndex, config.pessebre);
      if (mounted) setState(() => _progress++);
      protocol.writeText(_descripcioVIndex, config.descripcio);
      if (mounted) setState(() => _progress++);

      // Fitxers exportats abans que aquest camp existís porten una llista
      // buida — es deixen les transicions del dispositiu tal com estan en
      // lloc de sobreescriure-les amb valors de fàbrica.
      var transitionsFailed = false;
      if (config.transicions.length == 4) {
        final payload = [
          for (final t in config.transicions) '${t.tipus}|${t.saltPercent}',
        ].join('|');
        transitionsFailed = await _transitionsRoundTrip(payload) == null;
      }
      if (mounted) setState(() => _progress++);

      await Future.delayed(const Duration(seconds: 3));

      final failedChannels = <int>[];
      for (final entry in config.canals) {
        final ok = await _assignChannelVerified(entry);
        if (!ok) failedChannels.add(entry.number);
        if (!mounted) return;
        setState(() => _progress++);
      }

      final problems = [
        if (paramFailures.isNotEmpty)
          'paràmetres no confirmats: ${paramFailures.join(', ')}',
        if (transitionsFailed) 'transicions no confirmades',
        if (failedChannels.isNotEmpty)
          '${failedChannels.length} canal(s) no confirmats: '
              '${failedChannels.join(', ')}',
      ];
      _showMessage(
        problems.isEmpty
            ? 'Configuració importada.'
            : 'Configuració importada amb incidències — ${problems.join('; ')}.',
      );
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_running) {
      return Column(
        children: [
          Text(_statusText ?? '', style: const TextStyle(fontSize: 13)),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: _progressTotal > 0 ? _progress / _progressTotal : null,
          ),
          const SizedBox(height: 4),
          Text(
            _progressTotal > 0
                ? '${(100 * _progress / _progressTotal).round()} %'
                : '',
            style: const TextStyle(fontSize: 12),
          ),
        ],
      );
    }

    return Column(
      children: [
        const Text(
          'Exporta o importa tota la configuració en un fitxer JSON',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            FilledButton.icon(
              onPressed: _export,
              icon: const Icon(Icons.upload_file),
              label: const Text('Exportar'),
            ),
            const SizedBox(width: 12),
            FilledButton.icon(
              onPressed: _import,
              icon: const Icon(Icons.download),
              label: const Text('Importar'),
            ),
          ],
        ),
      ],
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
            backgroundColor: selected
                ? scheme.errorContainer
                : scheme.surfaceContainerHighest,
            foregroundColor: selected
                ? scheme.onErrorContainer
                : scheme.onSurfaceVariant,
            elevation: selected ? 4 : 1,
            padding: const EdgeInsets.all(4),
            minimumSize: Size.zero,
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
