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

  // Slots added via "Afegir event" that aren't defined on the device yet
  // (nothing saved, so they wouldn't otherwise show up in [_visibleIndices]
  // — a freshly added row needs to stay visible while the user fills it
  // in, even though it's still all-zero on the wire).
  final Set<int> _pendingNewSlots = {};

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

  bool _isDefined(int index) {
    final e = _events[index];
    return e != null && (e.pista > 0 || e.canal > 0);
  }

  /// Slots to actually render: every defined event, plus any empty slot the
  /// user just added via "Afegir event" that hasn't been filled in (or
  /// abandoned) yet — in index order, so a newly added slot doesn't jump
  /// around as other rows get edited.
  List<int> get _visibleIndices {
    final visible = <int>{
      for (var i = 0; i < _eventCount; i++)
        if (_isDefined(i)) i,
      ..._pendingNewSlots,
    }.toList()..sort();
    return visible;
  }

  /// Reveals the lowest-numbered unused slot as a new empty row to fill in
  /// — up to [_eventCount], enforced by disabling the button once every
  /// slot is either defined or already pending (see the button's
  /// `onPressed` in build()).
  void _addEvent() {
    for (var i = 0; i < _eventCount; i++) {
      if (!_isDefined(i) && !_pendingNewSlots.contains(i)) {
        setState(() => _pendingNewSlots.add(i));
        return;
      }
    }
  }

  /// Clears a row: if it was actually defined on the device, writes all-
  /// zero to V77 first (that's what "not configured" means on the wire —
  /// see handleEventBulk()); a still-empty just-added row has nothing to
  /// write, so this only drops it from [_pendingNewSlots].
  Future<void> _removeEvent(int index) async {
    if (_isDefined(index)) await _saveEvent(index, _emptyEvent);
    if (mounted) setState(() => _pendingNewSlots.remove(index));
  }

  Future<void> _saveEvent(int index, _EventData data) async {
    // Sets the local cache to what was just committed BEFORE awaiting the
    // round trip — same fix (and same reason) as ChannelTransitionEditor's
    // own _updateSlot() for V71: this row just lost focus (that's what
    // triggered the commit), so its build() now redraws from `widget.data`
    // on every rebuild. Without this, any unrelated rebuild that lands
    // during the round trip (e.g. the context poll timer) would still see
    // the OLD `_events[index]` and snap the fields back to it — confirmed
    // on real hardware: typed values kept reverting before the write even
    // finished.
    setState(() => _events[index] = data);

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
    final stillLoading = _events.any((e) => e == null);
    final visible = _visibleIndices;
    final canAddMore = visible.length < _eventCount;

    return AppScaffold(
      title: 'Events',
      onBack: () => Navigator.of(context).pop(),
      body: stillLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: visible.isEmpty
                      ? const Center(
                          child: Padding(
                            padding: EdgeInsets.all(24),
                            child: Text(
                              'Encara no hi ha cap event configurat.',
                              textAlign: TextAlign.center,
                            ),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          itemCount: visible.length,
                          separatorBuilder: (context, i) =>
                              const SizedBox(height: 8),
                          itemBuilder: (context, i) {
                            final index = visible[i];
                            return _EventRow(
                              key: ValueKey(index),
                              index: index,
                              data: _events[index],
                              numeroCanals: numeroCanals,
                              totalTimeSeconds: totalTime?.round(),
                              onSave: (data) => _saveEvent(index, data),
                              onTest: () => ref
                                  .read(protocolProvider)
                                  .writeV(VIndex.eventTestTrigger, index),
                              onDelete: () => _removeEvent(index),
                            );
                          },
                        ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: canAddMore ? _addEvent : null,
                      icon: const Icon(Icons.add),
                      label: Text(
                        canAddMore
                            ? 'Afegir event'
                            : 'Màxim de $_eventCount events',
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

/// One event's 4 fields (so/canal/moment/durada), read-modify-write as a
/// single V77 blob, plus a "Provar" button (V78) that fires it immediately
/// on the device regardless of the cycle's position. Commits to V77 once
/// focus leaves the WHOLE row (all 4 fields), not on each field's own blur
/// — see `_wireFocus()`'s doc for why per-field commit broke typing.
class _EventRow extends StatefulWidget {
  const _EventRow({
    super.key,
    required this.index,
    required this.data,
    required this.numeroCanals,
    required this.totalTimeSeconds,
    required this.onSave,
    required this.onTest,
    required this.onDelete,
  });

  final int index;
  final _EventData? data;
  final int numeroCanals;
  final int? totalTimeSeconds;
  final ValueChanged<_EventData> onSave;
  final VoidCallback onTest;
  final VoidCallback onDelete;

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

  // Committing (and, in build(), re-syncing the fields from the device) on
  // EVERY individual field's blur was wrong: tabbing So -> Canal -> Moment
  // -> Durada blurs each field in turn while the OTHERS are still 0, so the
  // very first blur already ran validation against an incomplete row (e.g.
  // "durada ha de ser > 0" right after typing only "So") and, worse, the
  // next rebuild then reverted that field back to the stale device value —
  // confirmed on real hardware: typing into a field never stuck. Instead,
  // only commit once focus leaves the WHOLE row (all 4 nodes unfocused),
  // deferred one frame so a same-row Tab (old field loses focus, sibling
  // gains it) has time to register before this checks "is anything in this
  // row still focused" — same "commit on losing focus for any reason"
  // family of fix as every other multi-field editor this session, just
  // applied at the row level instead of per-field since these 4 fields are
  // one logical unit (one V77 write).
  void _wireFocus(FocusNode focus, TextEditingController controller) {
    focus.addListener(() {
      if (focus.hasFocus) {
        controller.selection = TextSelection(
          baseOffset: 0,
          extentOffset: controller.text.length,
        );
      } else {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && !_anyFocused()) _commit();
        });
      }
    });
  }

  bool _anyFocused() =>
      _pistaFocus.hasFocus ||
      _canalFocus.hasFocus ||
      _momentFocus.hasFocus ||
      _duradaFocus.hasFocus;

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

    // Only re-syncs from the device while NO field in this row has focus —
    // checking the whole row, not each field individually, so tabbing
    // So -> Canal -> Moment -> Durada doesn't stomp a sibling field that's
    // mid-edit (see _wireFocus()'s doc for the bug this avoids).
    if (!_anyFocused()) {
      _pistaController.text = data.pista == 0 ? '' : '${data.pista}';
      _canalController.text = data.canal == 0 ? '' : '${data.canal}';
      _momentController.text = '${data.moment}';
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
          Row(
            children: [
              Expanded(
                child: Text(
                  'Event ${widget.index + 1}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
              // Fires this event on the device right now (V78), ignoring
              // its configured "moment" — lets the user hear/see it
              // without waiting for the cycle to reach that point.
              // Disabled while the row has nothing configured yet (same
              // "so or canal" test _commit() already uses to decide
              // whether there's anything to save).
              SizedBox(
                height: 28,
                child: OutlinedButton(
                  onPressed: (data.pista > 0 || data.canal > 0)
                      ? widget.onTest
                      : null,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    textStyle: const TextStyle(fontSize: 12),
                  ),
                  child: const Text('Provar'),
                ),
              ),
              const SizedBox(width: 4),
              // Clears this row: writes all-zero to the device if it was
              // actually defined (handleEventBulk() treats pista==0 &&
              // canal==0 as "not configured"), or just drops it back out of
              // view if it was still an empty just-added row.
              IconButton(
                onPressed: widget.onDelete,
                icon: const Icon(Icons.delete_outline),
                tooltip: 'Eliminar event',
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints(),
                padding: const EdgeInsets.all(4),
              ),
            ],
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
