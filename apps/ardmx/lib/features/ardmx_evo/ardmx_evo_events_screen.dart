import 'dart:async';
import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/v_map.dart';
import '../../core/protocol/virtuino_update.dart';
import '../../state/providers.dart';
import '../../widgets/app_scaffold.dart';

typedef _EventData = ({int moment, int durada, int pista, int canal});

const _emptyEvent = (moment: 0, durada: 0, pista: 0, canal: 0);
const _eventCount = 10;

/// "Events" screen (V77, ARDMX EVO only): up to 10 programmed actions — a
/// one-shot sound (`advertise()`) and/or a channel forced to 255, at a
/// given moment of the cycle for a given duration. See
/// `handleEventBulk()`/`GestioEvents()` in ardmx4-evo-firmware's main.cpp.
class ArdmxEvoEventsScreen extends ConsumerStatefulWidget {
  const ArdmxEvoEventsScreen({super.key});

  @override
  ConsumerState<ArdmxEvoEventsScreen> createState() =>
      _ArdmxEvoEventsScreenState();
}

class _ArdmxEvoEventsScreenState extends ConsumerState<ArdmxEvoEventsScreen> {
  static const _pollInterval = Duration(milliseconds: 800);
  static const _roundTripTimeout = Duration(seconds: 2);

  final List<_EventData?> _events = List.filled(_eventCount, null);
  Timer? _pollTimer;
  StreamSubscription<VirtuinoUpdate>? _repliesSubscription;

  // Mateix patró de correlació FIFO que ChannelTransitionEditor per V71:
  // una sola característica BLE entrega les trames en ordre, i
  // processFrame() al firmware respon una trama abans de llegir la
  // següent, així que les respostes de V77 sempre arriben en el mateix
  // ordre que les peticions — encara que _fetchAll() i el desat d'una fila
  // en curs d'edició coincideixin en el temps.
  final Queue<Completer<String?>> _pendingReplies = Queue<Completer<String?>>();

  @override
  void initState() {
    super.initState();
    _repliesSubscription = ref
        .read(protocolProvider)
        .updates
        .listen(_onProtocolUpdate);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _pollContext();
      unawaited(_fetchAll());
    });
    _pollTimer = Timer.periodic(_pollInterval, (_) => _pollContext());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _repliesSubscription?.cancel();
    super.dispose();
  }

  // Només el context (nombre de canals, durada total del cicle) es
  // repoll — els events en si NOMÉS es demanen un cop en obrir la
  // pantalla ([_fetchAll]), mai en bucle, perquè no esborri una edició en
  // curs de l'usuari (mateixa raó que ChannelTransitionEditor no repoll·la
  // el contingut de V71, només quin canal cal consultar).
  void _pollContext() {
    if (!(ModalRoute.of(context)?.isCurrent ?? true)) return;
    ref.read(protocolProvider).requestAll([
      VIndex.activeChannelsCount,
      VIndex.totalTime,
    ]);
  }

  void _onProtocolUpdate(VirtuinoUpdate update) {
    if (update is VirtuinoTUpdate &&
        update.index == VIndex.eventBulk &&
        _pendingReplies.isNotEmpty) {
      _pendingReplies.removeFirst().complete(update.text);
    }
  }

  Future<String?> _roundTrip(String payload) async {
    final completer = Completer<String?>();
    _pendingReplies.addLast(completer);
    ref.read(protocolProvider).writeText(VIndex.eventBulk, payload);

    final reply = await completer.future.timeout(
      _roundTripTimeout,
      onTimeout: () => null,
    );

    if (!completer.isCompleted) {
      _pendingReplies.remove(completer);
      for (final pending in _pendingReplies) {
        if (!pending.isCompleted) pending.complete(null);
      }
      _pendingReplies.clear();
    }
    return reply;
  }

  _EventData? _parse(String? reply) {
    if (reply == null) return null;
    final parts = reply.split('|');
    if (parts.length < 4) return null;
    return (
      moment: int.tryParse(parts[0]) ?? 0,
      durada: int.tryParse(parts[1]) ?? 0,
      pista: int.tryParse(parts[2]) ?? 0,
      canal: int.tryParse(parts[3]) ?? 0,
    );
  }

  Future<void> _fetchAll() async {
    for (var i = 0; i < _eventCount; i++) {
      final parsed = _parse(await _roundTrip('$i'));
      if (!mounted) return;
      setState(() => _events[i] = parsed ?? _emptyEvent);
    }
  }

  Future<void> _saveEvent(int index, _EventData data) async {
    final payload =
        '$index|${data.moment}|${data.durada}|${data.pista}|${data.canal}';
    final parsed = _parse(await _roundTrip(payload));
    if (mounted && parsed != null) setState(() => _events[index] = parsed);
  }

  @override
  Widget build(BuildContext context) {
    final numeroCanals =
        ref.watch(appStateProvider.select((s) => s.activeChannelsCount)) ?? 0;
    final totalTime = ref.watch(appStateProvider.select((s) => s.totalTime));

    return AppScaffold(
      title: 'Events',
      onBack: () => Navigator.of(context).pop(),
      body: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        itemCount: _eventCount,
        separatorBuilder: (context, index) => const SizedBox(height: 8),
        itemBuilder: (context, index) => _EventRow(
          key: ValueKey(index),
          index: index,
          data: _events[index],
          numeroCanals: numeroCanals,
          totalTimeSeconds: totalTime?.round(),
          onSave: (data) => _saveEvent(index, data),
        ),
      ),
    );
  }
}

/// One event's 4 fields (so/canal/moment/durada), read-modify-write as a
/// single V77 blob. Commits on losing focus for ANY reason (not just
/// `onTapOutside`) on EACH of its 4 fields — same fix as every other
/// multi-sibling-field editor in this app this session: Flutter groups
/// sibling `TextField`s into one `TextFieldTapRegion`, so jumping directly
/// between them never fires `onTapOutside`. Committing on every field's own
/// blur (not just once when the whole row loses focus) is simplest and
/// still correct: the payload always carries all 4 CURRENT controller
/// values regardless of which field triggered it, so tabbing across the
/// row just resends the same converging snapshot a few extra (harmless,
/// idempotent) times.
class _EventRow extends StatefulWidget {
  const _EventRow({
    super.key,
    required this.index,
    required this.data,
    required this.numeroCanals,
    required this.totalTimeSeconds,
    required this.onSave,
  });

  final int index;
  final _EventData? data;
  final int numeroCanals;
  final int? totalTimeSeconds;
  final ValueChanged<_EventData> onSave;

  @override
  State<_EventRow> createState() => _EventRowState();
}

class _EventRowState extends State<_EventRow> {
  final _pistaController = TextEditingController();
  final _canalController = TextEditingController();
  final _momentController = TextEditingController();
  final _duradaController = TextEditingController();
  final _pistaFocus = FocusNode();
  final _canalFocus = FocusNode();
  final _momentFocus = FocusNode();
  final _duradaFocus = FocusNode();
  String? _error;

  @override
  void initState() {
    super.initState();
    _wireFocus(_pistaFocus, _pistaController);
    _wireFocus(_canalFocus, _canalController);
    _wireFocus(_momentFocus, _momentController);
    _wireFocus(_duradaFocus, _duradaController);
  }

  void _wireFocus(FocusNode focus, TextEditingController controller) {
    focus.addListener(() {
      if (focus.hasFocus) {
        controller.selection = TextSelection(
          baseOffset: 0,
          extentOffset: controller.text.length,
        );
      } else {
        _commit();
      }
    });
  }

  @override
  void dispose() {
    _pistaController.dispose();
    _canalController.dispose();
    _momentController.dispose();
    _duradaController.dispose();
    _pistaFocus.dispose();
    _canalFocus.dispose();
    _momentFocus.dispose();
    _duradaFocus.dispose();
    super.dispose();
  }

  void _commit() {
    final pista = int.tryParse(_pistaController.text) ?? 0;
    final canal = int.tryParse(_canalController.text) ?? 0;
    final moment = int.tryParse(_momentController.text) ?? 0;
    final durada = int.tryParse(_duradaController.text) ?? 0;

    // Fila encara sense configurar (els 4 camps buits/0): res a validar ni
    // a desar — evita que totes les files buides mostrin un error just en
    // obrir la pantalla.
    if (pista == 0 && canal == 0 && moment == 0 && durada == 0) {
      setState(() => _error = null);
      return;
    }

    if (pista == 0 && canal == 0) {
      setState(() => _error = 'Cal una pista de so o un canal');
      return;
    }
    if (canal != 0 && (canal < 1 || canal > widget.numeroCanals)) {
      setState(
        () => _error = 'Canal fora de rang (1-${widget.numeroCanals})',
      );
      return;
    }
    final total = widget.totalTimeSeconds;
    if (moment < 0 || (total != null && moment > total)) {
      setState(() => _error = 'Moment fora de la durada del cicle');
      return;
    }
    if (durada <= 0) {
      setState(() => _error = 'La durada ha de ser més gran que 0');
      return;
    }

    setState(() => _error = null);
    widget.onSave((moment: moment, durada: durada, pista: pista, canal: canal));
  }

  Widget _numberField({
    required String label,
    required TextEditingController controller,
    required FocusNode focus,
  }) {
    return TextField(
      controller: controller,
      focusNode: focus,
      textAlign: TextAlign.center,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      style: const TextStyle(fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 6,
          vertical: 8,
        ),
        border: const OutlineInputBorder(),
      ),
      onSubmitted: (_) => _commit(),
      onTapOutside: (_) {
        FocusManager.instance.primaryFocus?.unfocus();
        _commit();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final scheme = Theme.of(context).colorScheme;

    if (data == null) {
      return Container(
        height: 64,
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    if (!_pistaFocus.hasFocus) {
      _pistaController.text = data.pista == 0 ? '' : '${data.pista}';
    }
    if (!_canalFocus.hasFocus) {
      _canalController.text = data.canal == 0 ? '' : '${data.canal}';
    }
    if (!_momentFocus.hasFocus) _momentController.text = '${data.moment}';
    if (!_duradaFocus.hasFocus) {
      _duradaController.text = data.durada == 0 ? '' : '${data.durada}';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Event ${widget.index + 1}',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: _numberField(
                  label: 'So',
                  controller: _pistaController,
                  focus: _pistaFocus,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _numberField(
                  label: 'Canal',
                  controller: _canalController,
                  focus: _canalFocus,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _numberField(
                  label: 'Moment (s)',
                  controller: _momentController,
                  focus: _momentFocus,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _numberField(
                  label: 'Durada (s)',
                  controller: _duradaController,
                  focus: _duradaFocus,
                ),
              ),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: 4),
            Text(
              _error!,
              style: TextStyle(color: scheme.error, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }
}
