import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/constants/v_map.dart';
import '../../core/protocol/virtuino_update.dart';
import '../../routing/app_router.dart';
import '../../state/providers.dart';
import '../../widgets/app_scaffold.dart';
import 'config_json.dart';

/// Parameters screen (V50=4): number of active scenes, song to play, and
/// number of manageable channels. These are plain Arduino state
/// (V0/V18/V39/V40), never pushed unsolicited, so this screen polls them
/// like every other screen that shows live V-values. The factory reset
/// lives one level deeper, in "Configuració del sistema" (reached via its
/// own button) — deliberately not on this screen, so it isn't as casually
/// reachable as the day-to-day controls here (mirrors ARDMX One's own
/// Paràmetres/Configuració del sistema split).
class ParametersScreen extends ConsumerStatefulWidget {
  const ParametersScreen({super.key});

  @override
  ConsumerState<ParametersScreen> createState() => _ParametersScreenState();
}

class _ParametersScreenState extends ConsumerState<ParametersScreen> {
  static const _pollInterval = Duration(milliseconds: 400);

  Timer? _pollTimer;
  // true while an export/import is running (_ExportImportSection) — the
  // channel bulk protocol (V63) has no request/response correlation, so
  // this screen's own periodic poll must go fully quiet during it. Without
  // this, the poll's V18/V0/V40/V39/V41/V42 bundle was observed interleaving
  // with the V63 write+read frames on real hardware, corrupting the
  // sequence badly enough that imported channel values silently reverted
  // to 0.
  bool _channelOpRunning = false;

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

    // See _channelOpRunning's doc — must stay fully quiet during an
    // export/import.
    if (_channelOpRunning) return;

    ref.read(protocolProvider).requestAll([
      VIndex.activeScenesCount,
      VIndex.songNumber,
      VIndex.activeChannelsCount,
      VIndex.maxChannels,
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
                    title: 'Configuració',
                    child: _ExportImportSection(
                      onRunningChanged: (running) =>
                          setState(() => _channelOpRunning = running),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                FloatingActionButton(
                  heroTag: 'parametersBack',
                  onPressed: () => Navigator.of(context).pop(),
                  tooltip: 'Tornar al menú principal',
                  child: const Icon(Icons.arrow_back),
                ),
                FloatingActionButton(
                  heroTag: 'parametersSystemConfig',
                  onPressed: () => Navigator.of(
                    context,
                  ).pushNamed(AppRoutes.parametersSystemConfig),
                  tooltip: 'Configuració del sistema',
                  child: const Icon(Icons.build),
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

/// Exports the whole device configuration (scene count, song, volume,
/// active channel count, the 8 cycle period durations, and every active
/// channel's 4 per-scene values+transition modes) as a JSON file shared via
/// Android's system share sheet, or imports one back. Mirrors ARDMX One's
/// own `_ExportImportSection` (`features/ardmx_one/ardmx_one_config_screen.dart`).
///
/// Channel data has no bulk read/write on the wire protocol — V01-03/V31-33
/// only ever expose the 3 currently-selected channels' values/modes for the
/// *active* scene. Both directions go through V63 instead (query/assign a
/// single channel's 4 scenes at once by its explicit number — see
/// `handleChannelBulk()` in `ARDMX4.ino`), sent sequentially and awaited one
/// at a time: the wire protocol has no request/response correlation (any
/// reply could be mistaken for a different in-flight request).
///
/// Unlike ARDMX One's V70, a plain write to V63 gets no automatic reply —
/// the Mega's VirtuinoCM library only replies to reads — so each channel
/// round trip is two frames (write the query/assignment, then explicitly
/// request a read) instead of one.
class _ExportImportSection extends ConsumerStatefulWidget {
  const _ExportImportSection({required this.onRunningChanged});

  /// Called with `true` right before an export/import starts and `false`
  /// once it finishes — lets the parent screen pause its own periodic poll
  /// for the duration (see `_channelOpRunning` in `_ParametersScreenState`).
  final ValueChanged<bool> onRunningChanged;

  @override
  ConsumerState<_ExportImportSection> createState() =>
      _ExportImportSectionState();
}

class _ExportImportSectionState extends ConsumerState<_ExportImportSection> {
  static const _firmwareVersionVIndex = 62;
  static const _channelBulkVIndex = 63;
  static const _roundTripTimeout = Duration(milliseconds: 800);

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

  /// Writes a V-index and retries until a read-back confirms it actually
  /// landed — plain `writeV` is fire-and-forget, and right after V18
  /// (scene count) changes the Mega can be busy for seconds running
  /// `InicialitzarPrograma()`, silently dropping whatever else arrives on
  /// its serial buffer meanwhile (same root cause as the channel data —
  /// see `_assignChannelVerified`, which this mirrors for the scalar
  /// parameters).
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

  /// Sends a V63 payload (either `"N"` to query channel N, or
  /// `"N|v1|m1|v2|m2|v3|m3|v4|m4"` to assign it) then a follow-up read
  /// request, and awaits the matching `"v1|m1|v2|m2|v3|m3|v4|m4"` reply the
  /// firmware leaves for either case — see the class doc for why this is
  /// two frames, not one.
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
    // Marge deliberat abans de la lectura: a 9600 bauds el Mega pot no
    // haver acabat de processar l'escriptura si la lectura arriba
    // pràcticament al mateix instant (condició de cursa observada en
    // maquinari real — els dos primers canals es quedaven a 0 sense
    // aquesta pausa, tot i que l'escriptura sortia correcta per Bluetooth).
    await Future.delayed(const Duration(milliseconds: 30));
    protocol.requestT(_channelBulkVIndex);
    final reply = await completer.future.timeout(
      _roundTripTimeout,
      onTimeout: () => null,
    );
    await sub.cancel();
    return reply;
  }

  /// [_channelRoundTripOnce] with retries — necessary because a change to
  /// V18/V40 (scene/channel count) makes the Mega run its own, blocking
  /// `InicialitzarPrograma()` (reloads timings, re-sends DMX, lots of
  /// Serial prints at 9600 bauds): while that runs, the Mega isn't draining
  /// its serial buffer, so whatever channel writes land during that window
  /// get silently dropped (observed on real hardware: importing right
  /// after a factory reset — which changes the scene count — always lost
  /// exactly the first few channels). Retrying the same round trip is
  /// simpler and more robust than trying to predict how long that takes.
  Future<String?> _channelRoundTrip(String payload) async {
    for (var attempt = 0; attempt < 3; attempt++) {
      final reply = await _channelRoundTripOnce(payload);
      if (reply != null) return reply;
    }
    return null;
  }

  (List<int>, List<int>)? _parseChannelReply(String? reply) {
    if (reply == null) return null;
    final parts = reply.split('|');
    if (parts.length != 8) return null;
    final valors = <int>[];
    final modes = <int>[];
    for (var i = 0; i < 8; i += 2) {
      valors.add(int.tryParse(parts[i]) ?? 0);
      modes.add(int.tryParse(parts[i + 1]) ?? 0);
    }
    return (valors, modes);
  }

  /// Assigns one channel's 4 scenes and retries until the Mega's own
  /// echoed-back reply actually matches what we asked for — not just until
  /// *some* reply arrives. A plain "got a reply" check isn't enough here:
  /// on real hardware, right after a scene-count change (V18), the Mega
  /// can reply with a stale/zeroed read while it's still mid-`
  /// InicialitzarPrograma()` internally, which a mere non-null check would
  /// have accepted as success. Returns false (after exhausting retries) if
  /// the channel could never be confirmed.
  Future<bool> _assignChannelVerified(Ardmx4ChannelConfigEntry entry) async {
    final fields = <String>[];
    for (var i = 0; i < 4; i++) {
      fields.add('${entry.valors[i]}');
      fields.add('${entry.modes[i]}');
    }
    final payload = '${entry.number}|${fields.join('|')}';

    for (var attempt = 0; attempt < 6; attempt++) {
      final parsed = _parseChannelReply(await _channelRoundTripOnce(payload));
      if (parsed != null &&
          _listEquals(parsed.$1, entry.valors) &&
          _listEquals(parsed.$2, entry.modes)) {
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

  Future<void> _export() async {
    widget.onRunningChanged(true);
    setState(() {
      _running = true;
      _statusText = 'Llegint configuració…';
      _progress = 0;
      _progressTotal = 1;
    });
    try {
      final firmwareVersio = await _readText(_firmwareVersionVIndex) ?? '';
      final numeroEscenes = await _readValue(VIndex.activeScenesCount) ?? 0;
      final numeroCanals = await _readValue(VIndex.activeChannelsCount);
      final numeroMusica = await _readValue(VIndex.songNumber) ?? 0;
      final nivellVolum = await _readValue(VIndex.volume) ?? 0;
      if (numeroCanals == null || numeroCanals <= 0) {
        _showMessage('No s\'ha pogut llegir el nombre de canals gestionables.');
        return;
      }

      final periodes = <double>[];
      for (var i = 0; i < 8; i++) {
        periodes.add(await _readValue(VIndex.periodDuration(i)) ?? 0);
      }

      final canalsCount = numeroCanals.round();
      final canals = <Ardmx4ChannelConfigEntry>[];
      setState(() {
        _progressTotal = canalsCount;
        _statusText = 'Llegint canals…';
      });
      for (var channel = 1; channel <= canalsCount; channel++) {
        final parsed = _parseChannelReply(await _channelRoundTrip('$channel'));
        canals.add(
          Ardmx4ChannelConfigEntry(
            number: channel,
            valors: parsed?.$1 ?? const [0, 0, 0, 0],
            modes: parsed?.$2 ?? const [0, 0, 0, 0],
          ),
        );
        if (!mounted) return;
        setState(() => _progress = channel);
      }

      final config = Ardmx4ConfigData(
        numeroEscenes: numeroEscenes.round(),
        numeroCanals: canalsCount,
        numeroMusica: numeroMusica.round(),
        nivellVolum: nivellVolum.round(),
        periodes: periodes,
        canals: canals,
        firmwareVersio: firmwareVersio,
        exportatEl: DateTime.now(),
      );
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/ardmx4_config.json');
      await file.writeAsString(config.toPrettyJson());
      await SharePlus.instance.share(
        ShareParams(files: [XFile(file.path)], text: 'Configuració ARDMX4'),
      );
    } finally {
      widget.onRunningChanged(false);
      if (mounted) setState(() => _running = false);
    }
  }

  Future<bool> _confirmImport(Ardmx4ConfigData config) async {
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
          "Es sobreescriuran el nombre d'escenes, la cançó, el volum, el "
          'nombre de canals, els temps de transició i els valors/modes de '
          '${config.canals.length} canals amb el contingut del fitxer.'
          '${origen.isNotEmpty ? '\n\nFitxer: $origen' : ''}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel·lar'),
          ),
          ElevatedButton(
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
    );
    final path = picked?.files.singleOrNull?.path;
    if (path == null) return;

    final Ardmx4ConfigData config;
    try {
      config = Ardmx4ConfigData.fromPrettyJson(await File(path).readAsString());
    } catch (_) {
      _showMessage('El fitxer no és un JSON vàlid de configuració.');
      return;
    }
    if (config.numeroCanals <= 0 || config.canals.isEmpty) {
      _showMessage('El fitxer no conté cap canal.');
      return;
    }
    // Fitxers antics exportats abans d'aquest camp tenen model buit — es
    // consideren compatibles. Només es bloqueja quan el fitxer indica
    // explícitament un model diferent (p.ex. exportat des de l'ARDMX One).
    if (config.model.isNotEmpty &&
        config.model != Ardmx4ConfigData.defaultModel) {
      _showMessage(
        'Aquest fitxer és de "${config.model}", no d\'ARDMX4. '
        'No s\'ha importat.',
      );
      return;
    }

    if (!await _confirmImport(config)) return;

    widget.onRunningChanged(true);
    // 4 valors escalars + 8 temps de transició + un pas per canal — inclou
    // els paràmetres inicials al total perquè la barra de progrés ja es
    // mogui durant aquesta fase, en lloc de quedar-se congelada a 0 fins
    // que comença el bucle de canals (que pot trigar uns segons a
    // arrencar, vegeu el marge d'assentament més avall).
    const paramStepCount = 12;
    setState(() {
      _running = true;
      _statusText = 'Aplicant configuració…';
      _progress = 0;
      _progressTotal = paramStepCount + config.canals.length;
    });
    try {
      // Escriptures verificades (no fire-and-forget): la primera d'aquestes
      // (nombre d'escenes) és precisament la que pot disparar la rutina
      // bloquejant InicialitzarPrograma() del Mega (vegeu el comentari més
      // avall) — qualsevol escriptura que arribi mentre encara està
      // ocupada es perd en silenci, i això incloïa fins ara la cançó, el
      // volum, el nombre de canals i els temps de transició, no només els
      // canals. Cada valor es reenvia fins que una lectura posterior el
      // confirma.
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
      await writeParam('cançó', VIndex.songNumber, config.numeroMusica);
      await writeParam('volum', VIndex.volume, config.nivellVolum);
      await writeParam(
        'nombre de canals',
        VIndex.activeChannelsCount,
        config.numeroCanals,
      );
      for (var i = 0; i < 8 && i < config.periodes.length; i++) {
        await writeParam(
          'temps de transició ${i + 1}',
          VIndex.periodDuration(i),
          config.periodes[i],
        );
      }

      // Marge addicional perquè el Mega acabi d'assentar-se abans de
      // començar el bombardeig de canals: si el nombre d'escenes acaba de
      // canviar (p.ex. important just després d'un reset de fàbrica), el
      // firmware llança InicialitzarPrograma() — una rutina bloquejant
      // pròpia (recarrega temps, reenvia DMX, imprimeix molt per sèrie a
      // 9600 bauds, mesurat en maquinari real fins a 3-4 s) durant la qual
      // no buida el seu buffer sèrie.
      await Future.delayed(const Duration(seconds: 5));

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
      widget.onRunningChanged(false);
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
          'Exporta o importa tota la configuració en un fitxer JSON.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton.icon(
              onPressed: _export,
              icon: const Icon(Icons.upload_file),
              label: const Text('Exportar'),
            ),
            const SizedBox(width: 12),
            OutlinedButton.icon(
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
