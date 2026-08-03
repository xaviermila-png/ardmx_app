import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/protocol/virtuino_update.dart';
import '../../routing/app_router.dart';
import '../../state/providers.dart';
import '../../widgets/app_scaffold.dart';
import 'config_json.dart';

/// ARDMX One's own "Paràmetres" screen — reached from [ArdmxOneScreen] via a
/// button between the back arrow and the exit button. Kept separate from
/// ARDMX4's Parameters screen: different device, different fields.
///
/// Only "Nombre de canals actius" for now (wire index V08 — see
/// `firmware/ardmx_one/src/main.cpp`); more fields will be added here as the
/// firmware grows to support them. The Bluetooth name change and factory
/// reset live one level deeper, in the "Configuració del sistema" screen —
/// deliberately not on this screen, so a user browsing normal settings can't
/// stumble into either by accident (both require real recovery steps:
/// re-pairing after a rename, losing the current scene after a reset).
class ArdmxOneConfigScreen extends ConsumerStatefulWidget {
  const ArdmxOneConfigScreen({super.key});

  @override
  ConsumerState<ArdmxOneConfigScreen> createState() =>
      _ArdmxOneConfigScreenState();
}

class _ArdmxOneConfigScreenState extends ConsumerState<ArdmxOneConfigScreen> {
  static const _numeroCanalsVIndex = 8;
  static const _pessebeNameVIndex = 68;
  static const _descriptionVIndex = 69;

  final _numeroCanalsController = TextEditingController();
  StreamSubscription<VirtuinoUpdate>? _subscription;
  String? _numeroCanalsError;

  @override
  void initState() {
    super.initState();
    _subscription = ref.read(protocolProvider).updates.listen((update) {
      if (update is VirtuinoVUpdate && update.index == _numeroCanalsVIndex) {
        setState(() {
          _numeroCanalsController.text = update.value.round().toString();
          _numeroCanalsError = null;
        });
      }
    });
    ref.read(protocolProvider).requestV(_numeroCanalsVIndex);
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _numeroCanalsController.dispose();
    super.dispose();
  }

  // El firmware exigeix que numeroCanals sigui sempre múltiple de 3 (cada
  // slider en controla un grup de 3) — en lloc de corregir-ho en silenci,
  // avisem i no enviem res fins que l'usuari ho arregli. Retorna el valor
  // vàlid, o null si l'entrada actual encara no ho és.
  int? _validate(String raw) {
    final value = int.tryParse(raw);
    if (value == null || value < 1 || value > 512 || value % 3 != 0) {
      setState(() {
        _numeroCanalsError =
            'Ha de ser un múltiple de 3, entre 1 i 510 (p.ex. 48, 51, 54...)';
      });
      return null;
    }
    setState(() => _numeroCanalsError = null);
    return value;
  }

  // Es crida en cada pulsació — només actualitza l'error en directe (no
  // envia res encara). Sense això, si l'usuari corregeix el número i després
  // tanca el teclat amb el gest "enrere" d'Android en lloc de tocar fora del
  // camp o prémer "Fet", `onTapOutside`/`onSubmitted` mai arriben a disparar-
  // se i l'error queda enganxat encara que el valor ja sigui correcte.
  void _onChanged(String raw) => _validate(raw);

  // Es crida en perdre el focus (tocar fora del camp o prémer "Fet" al
  // teclat) — és quan realment s'envia el valor a l'ARDMX One, no a cada
  // tecla, per no inundar el protocol amb escriptures intermèdies mentre
  // s'escriu un número de diverses xifres.
  void _submit(String raw) {
    final value = _validate(raw);
    if (value != null) {
      ref.read(protocolProvider).writeV(_numeroCanalsVIndex, value);
    }
  }

  // Flotant i amb marge inferior perquè no quedi tapat pel botó de
  // "Configuració del sistema" (56px d'alçada + 12px de padding, vegeu el
  // Padding que l'envolta més avall).
  void _showBackBlockedMessage() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        behavior: SnackBarBehavior.floating,
        margin: EdgeInsets.only(bottom: 90, left: 16, right: 16),
        content: Text('Corregeix el nombre de canals abans de tornar enrere.'),
      ),
    );
  }

  // Sortir d'aquesta pantalla (fletxa pròpia o gest/botó enrere del
  // sistema) és l'única manera fiable de saber que l'usuari ha acabat
  // d'editar — per això sempre es crida _submit() aquí abans de decidir si
  // es pot sortir, en lloc de confiar només en onSubmitted/onTapOutside del
  // camp (que mai arriben a disparar-se si es surt amb el gest enrere
  // d'Android, deixant el valor escrit sense enviar mai al dispositiu).
  void _attemptBack() {
    _submit(_numeroCanalsController.text);
    if (_numeroCanalsError != null) {
      _showBackBlockedMessage();
      return;
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // canPop sempre fals: tota la decisió (confirmar el valor i, si és
      // vàlid, sortir) es delega a _attemptBack() des d'aquí baix, perquè
      // el gest/botó enrere del sistema faci exactament el mateix que la
      // fletxa pròpia.
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _attemptBack();
      },
      child: AppScaffold(
        title: 'Paràmetres',
        onBack: _attemptBack,
        body: Column(
          children: [
            // Desplaçable: amb el teclat obert per editar la descripció (fins
            // a 128 caràcters), el contingut ja no cap sencer en pantalles
            // petites — mateix arranjament que ArdmxOneSystemConfigScreen.
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    const Padding(
                      padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
                      child: Column(
                        children: [
                          _EditableTextSection(
                            title: 'Nom del pessebre',
                            vIndex: _pessebeNameVIndex,
                            maxLength: 32,
                          ),
                          SizedBox(height: 10),
                          _EditableTextSection(
                            title: 'Descripció',
                            vIndex: _descriptionVIndex,
                            maxLength: 128,
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                      child: _Section(
                        title: 'Nombre de canals actius',
                        child: Column(
                          children: [
                            Container(
                              width: 80,
                              padding: const EdgeInsets.symmetric(vertical: 2),
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.primary,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: TextField(
                                controller: _numeroCanalsController,
                                textAlign: TextAlign.center,
                                keyboardType: TextInputType.number,
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                ],
                                style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onPrimary,
                                ),
                                decoration: const InputDecoration(
                                  border: InputBorder.none,
                                  isDense: true,
                                  contentPadding: EdgeInsets.zero,
                                ),
                                onChanged: _onChanged,
                                onSubmitted: _submit,
                                onTapOutside: (_) {
                                  FocusManager.instance.primaryFocus?.unfocus();
                                  _submit(_numeroCanalsController.text);
                                },
                              ),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'Múltiple de 3, màxim 510',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 12),
                            ),
                            if (_numeroCanalsError != null) ...[
                              const SizedBox(height: 4),
                              Text(
                                _numeroCanalsError!,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Theme.of(context).colorScheme.error,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                      child: _Section(
                        title: 'Configuració',
                        child: const _ExportImportSection(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  FloatingActionButton(
                    heroTag: 'ardmxOneSystemConfig',
                    onPressed: () {
                      _submit(_numeroCanalsController.text);
                      if (_numeroCanalsError != null) {
                        _showBackBlockedMessage();
                        return;
                      }
                      Navigator.of(
                        context,
                      ).pushNamed(AppRoutes.ardmxOneSystemConfig);
                    },
                    tooltip: 'Configuració del sistema',
                    child: const Icon(Icons.build),
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

/// Same card look as ARDMX4's Parameters screen (`_Section` there) — grey
/// rounded box with a bold centered title — kept as its own private copy
/// here rather than shared, since these two screens' widgets are otherwise
/// deliberately independent (see the class doc up top). Also reused by
/// `ArdmxOneSystemConfigScreen` via its own private copy, for the same
/// reason.
class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
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
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          child,
        ],
      ),
    );
  }
}

/// Free-text field backed by a single wire text index (V68 nom del pessebe,
/// V69 descripció) — requests its current value once on mount, then sends
/// the edited text back on blur/Enter (same "confirm on losing focus"
/// pattern as [_numeroCanalsController] above, minus the validation: any
/// text up to [maxLength] is valid here, so there's nothing to block leaving
/// the screen for). The firmware is the source of truth for the actual
/// stored length (it truncates UTF-8-safely if needed — see
/// `sanitizeText()` in `firmware/ardmx_one/src/main.cpp`), this is just the
/// UI-side hint.
class _EditableTextSection extends ConsumerStatefulWidget {
  const _EditableTextSection({
    required this.title,
    required this.vIndex,
    required this.maxLength,
  });

  final String title;
  final int vIndex;
  final int maxLength;

  @override
  ConsumerState<_EditableTextSection> createState() =>
      _EditableTextSectionState();
}

class _EditableTextSectionState extends ConsumerState<_EditableTextSection> {
  final _controller = TextEditingController();
  StreamSubscription<VirtuinoUpdate>? _subscription;

  @override
  void initState() {
    super.initState();
    _subscription = ref.read(protocolProvider).updates.listen((update) {
      if (update is VirtuinoTUpdate && update.index == widget.vIndex) {
        _controller.text = update.text;
      }
    });
    ref.read(protocolProvider).requestT(widget.vIndex);
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _submit(String text) =>
      ref.read(protocolProvider).writeText(widget.vIndex, text);

  @override
  Widget build(BuildContext context) {
    return _Section(
      title: widget.title,
      child: TextField(
        controller: _controller,
        textAlign: TextAlign.left,
        // The long field (description) gets a fixed 3-line box — same
        // height whether empty or full, so the layout doesn't jump around
        // as the user types — while the short field (pessebe name) stays
        // compact. Scaled off maxLength since this widget is shared by
        // both.
        minLines: widget.maxLength > 40 ? 3 : 1,
        maxLines: widget.maxLength > 40 ? 3 : 2,
        textInputAction: TextInputAction.done,
        maxLength: widget.maxLength,
        decoration: const InputDecoration(border: OutlineInputBorder()),
        onSubmitted: _submit,
        onTapOutside: (_) {
          FocusManager.instance.primaryFocus?.unfocus();
          _submit(_controller.text);
        },
      ),
    );
  }
}

/// Exports the whole device configuration (pessebre name, description,
/// active channel count, and every active channel's name+value) as a JSON
/// file shared via Android's system share sheet, or imports one back.
///
/// Channel data has no bulk read/write on the wire protocol — V01-03/
/// V04-06/V65-67 only ever expose the 3 currently-selected slider channels.
/// Both directions go through V70 instead (query/assign a single channel by
/// its explicit number, one round trip per channel — see
/// `firmware/ardmx_one/src/main.cpp`), sent sequentially and awaited one at
/// a time: the wire protocol has no request/response correlation (any
/// reply could be mistaken for a different in-flight request), and firing
/// hundreds of writes at once risked reintroducing the DMX-vs-NVS timing
/// crash that was just fixed on the firmware side.
class _ExportImportSection extends ConsumerStatefulWidget {
  const _ExportImportSection();

  @override
  ConsumerState<_ExportImportSection> createState() =>
      _ExportImportSectionState();
}

class _ExportImportSectionState extends ConsumerState<_ExportImportSection> {
  static const _pessebreVIndex = 68;
  static const _descripcioVIndex = 69;
  static const _numeroCanalsVIndex = 8;
  static const _channelBulkVIndex = 70;
  static const _firmwareVersionVIndex = 62;
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

  Future<int?> _readValue(int index) async {
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
    return result?.round();
  }

  /// Sends a V70 payload (either `"N"` to query channel N, or
  /// `"N|value|name"` to assign it) and awaits the matching `"value|name"`
  /// reply, which the firmware sends for both cases.
  Future<(int value, String name)?> _channelRoundTrip(String payload) async {
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
    if (reply == null) return null;
    final pipe = reply.indexOf('|');
    if (pipe == -1) return null;
    final value = int.tryParse(reply.substring(0, pipe)) ?? 0;
    return (value, reply.substring(pipe + 1));
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _export() async {
    setState(() {
      _running = true;
      _statusText = 'Llegint configuració…';
      _progress = 0;
      _progressTotal = 1;
    });
    try {
      final pessebre = await _readText(_pessebreVIndex) ?? '';
      final descripcio = await _readText(_descripcioVIndex) ?? '';
      final firmwareVersio = await _readText(_firmwareVersionVIndex) ?? '';
      final numeroCanals = await _readValue(_numeroCanalsVIndex);
      if (numeroCanals == null || numeroCanals <= 0) {
        _showMessage('No s\'ha pogut llegir el nombre de canals actius.');
        return;
      }

      final canals = <ChannelConfigEntry>[];
      setState(() {
        _progressTotal = numeroCanals;
        _statusText = 'Llegint canals…';
      });
      for (var channel = 1; channel <= numeroCanals; channel++) {
        final result = await _channelRoundTrip('$channel');
        canals.add(
          ChannelConfigEntry(
            number: channel,
            name: result?.$2 ?? '',
            value: result?.$1 ?? 0,
          ),
        );
        if (!mounted) return;
        setState(() => _progress = channel);
      }

      final config = ArdmxOneConfigData(
        pessebre: pessebre,
        descripcio: descripcio,
        numeroCanals: numeroCanals,
        canals: canals,
        firmwareVersio: firmwareVersio,
        exportatEl: DateTime.now(),
      );
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/ardmx_one_config.json');
      await file.writeAsString(config.toPrettyJson());
      await SharePlus.instance.share(
        ShareParams(files: [XFile(file.path)], text: 'Configuració ARDMX One'),
      );
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  Future<bool> _confirmImport(ArdmxOneConfigData config) async {
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
          'Es sobreescriuran el nom del pessebre, la descripció, el nombre '
          'de canals actius i els noms/valors de ${config.canals.length} '
          'canals amb el contingut del fitxer.'
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
    );
    final path = picked?.files.singleOrNull?.path;
    if (path == null) return;

    final ArdmxOneConfigData config;
    try {
      config = ArdmxOneConfigData.fromPrettyJson(
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
    // Fitxers antics exportats abans d'aquest camp tenen model buit — es
    // consideren compatibles (probablement del mateix dispositiu, d'abans
    // d'afegir aquesta comprovació). Només es bloqueja quan el fitxer indica
    // explícitament un model diferent (p.ex. exportat des de l'ARDMX4).
    if (config.model.isNotEmpty &&
        config.model != ArdmxOneConfigData.defaultModel) {
      _showMessage(
        'Aquest fitxer és de "${config.model}", no d\'ARDMX One. '
        'No s\'ha importat.',
      );
      return;
    }

    if (!await _confirmImport(config)) return;

    setState(() {
      _running = true;
      _statusText = 'Aplicant configuració…';
      _progress = 0;
      _progressTotal = config.canals.length;
    });
    try {
      final protocol = ref.read(protocolProvider);
      protocol.writeV(_numeroCanalsVIndex, config.numeroCanals);
      protocol.writeText(_pessebreVIndex, config.pessebre);
      protocol.writeText(_descripcioVIndex, config.descripcio);

      for (final entry in config.canals) {
        await _channelRoundTrip('${entry.number}|${entry.value}|${entry.name}');
        if (!mounted) return;
        setState(() => _progress++);
      }

      // El pessebre/descripció es refresquen sols (el firmware els torna a
      // enviar en resposta a la pròpia escriptura — replyText a V68/V69),
      // però V08 i el canal seleccionat (V01-03/V65-67) NO tenen eco
      // automàtic, així que sense això la pantalla de Canals (si segueix
      // oberta per sota) es quedava amb els valors/noms antics fins a
      // desconnectar i reconnectar — mateix problema que al reset de
      // fàbrica.
      protocol.requestV(_numeroCanalsVIndex);
      protocol.requestV(1);
      protocol.requestV(2);
      protocol.requestV(3);
      protocol.requestT(65);
      protocol.requestT(66);
      protocol.requestT(67);

      _showMessage('Configuració importada.');
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
          'Exporta o importa tota la configuració en un fitxer JSON.',
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
