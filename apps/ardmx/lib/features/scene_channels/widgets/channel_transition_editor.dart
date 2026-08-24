import 'dart:async';
import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/v_map.dart';
import '../../../core/protocol/virtuino_update.dart';
import '../../../state/providers.dart';
import 'nav_arrow_button.dart';

typedef _TransitionEntry = ({TransitionType type, int saltPercent});
typedef _ChannelFull =
    ({List<int> valors, List<_TransitionEntry> transicions, String name});

const _defaultTransition = (type: TransitionType.lineal, saltPercent: 0);

/// Display order for the type picker — deliberately NOT
/// `TransitionType.values`' declaration order (which matches the fixed
/// wire `vValue`s and must never change): Lineal, Fi suau (EASE_OUT),
/// Inici suau (EASE_IN), Salt. Keep any other place in the app that lists
/// all 4 types in sync with this order/labelling.
const _displayOrder = [
  TransitionType.lineal,
  TransitionType.easeOut,
  TransitionType.easeIn,
  TransitionType.salt,
];

/// "Transició Escena N -> Escena M" editor, ONE COLUMN PER VISIBLE CHANNEL
/// (matching [ChannelSliders]' 3-way layout) — replaces both the very old
/// per-channel [TransitionModeSelector] (gradual/inicial/final) and this
/// session's own first attempt at a single GLOBAL editor shared by all
/// channels, which turned out to be wrong: different channels genuinely
/// need different transition behaviour during the same scene-to-scene
/// transition (e.g. one doing a hard SALT while another fades LINEAL).
///
/// Type AND salt% are both per-channel now (V71 carries a channel's own 4
/// values + its own 4 transitions + name, all in one atomic blob — see
/// `handleChannelBulk4Scene()`/`handleChannelBulk()` in the two firmwares).
/// There is no separate "transitions" wire index any more (V72, from the
/// global-editor design, is gone) — everything lives on V71 per channel.
///
/// Because V71 writes are atomic (the whole channel, not one field), this
/// widget keeps a full read-modify-write cache per visible slot
/// ([_channels]): it fetches a channel's complete V71 state whenever that
/// slot's selected DMX channel changes (polled, like the rest of this
/// app — [ChannelNumberBar]'s advance-group arrows don't push a
/// notification), and merges any local edit back into that cache before
/// re-sending the full blob.
class ChannelTransitionEditor extends ConsumerStatefulWidget {
  const ChannelTransitionEditor({super.key, this.trailing});

  /// Rendered at the end of the header row, alongside the "Transició
  /// Escena N → Escena M" title — see [RgbWheelButton]'s use at both call
  /// sites (this frees up the vertical space a dedicated FAB row used to
  /// cost the sliders above).
  final Widget? trailing;

  @override
  ConsumerState<ChannelTransitionEditor> createState() =>
      _ChannelTransitionEditorState();
}

class _ChannelTransitionEditorState
    extends ConsumerState<ChannelTransitionEditor> {
  static const _pollInterval = Duration(milliseconds: 800);
  static const _roundTripTimeout = Duration(seconds: 2);
  static const _channelCount = 3;

  final List<_ChannelFull?> _channels = List.filled(_channelCount, null);
  final List<int?> _fetchedFor = List.filled(_channelCount, null);
  int _selectedTransition = 0;
  Timer? _pollTimer;
  StreamSubscription<VirtuinoUpdate>? _repliesSubscription;

  /// FIFO-matches V71 replies to pending requests instead of running them
  /// one at a time. A single BLE characteristic delivers writes in order,
  /// and both firmwares' `processFrame()` handles one frame fully
  /// (including sending its reply) before reading the next, so replies
  /// always come back in the same order the requests were sent — even
  /// with several in flight together. That means the OLDEST still-
  /// unanswered request is always at the front of this queue, so this
  /// single persistent listener can just pop-and-complete it whenever a
  /// V71 reply arrives, and multiple slots can refetch concurrently
  /// (latency ~1 round trip) instead of stacking (~3 round trips, which
  /// is what made switching channel groups feel noticeably laggy).
  ///
  /// An earlier version matched replies by "whichever listener sees a
  /// reply first" (one listener per request) — broke under concurrency:
  /// 3 requests in flight, the first reply completed all 3, so all 3
  /// columns ended up showing the same channel's data (confirmed on real
  /// hardware). Fully serializing fixed that but cost 3x the latency.
  /// FIFO correlation keeps both properties.
  final Queue<Completer<String?>> _pendingReplies = Queue<Completer<String?>>();

  @override
  void initState() {
    super.initState();
    // Starts showing the transition that leaves whichever scene is
    // currently active (V9) — that's the transition this scene's own
    // "Escena N → Escena M" title refers to (see the header doc: transition
    // i is scene i+1's OUTGOING one). The editor's own arrows can still
    // browse to a different one afterward; see the ref.listen in build()
    // for what happens when the active scene changes again while browsing.
    final activeScene = ref.read(appStateProvider).activeScene;
    if (activeScene != null && activeScene >= 1 && activeScene <= 4) {
      _selectedTransition = activeScene - 1;
    }
    _repliesSubscription = ref
        .read(protocolProvider)
        .updates
        .listen(_onProtocolUpdate);
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkChannels());
    _pollTimer = Timer.periodic(_pollInterval, (_) => _checkChannels());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _repliesSubscription?.cancel();
    super.dispose();
  }

  void _onProtocolUpdate(VirtuinoUpdate update) {
    if (update is VirtuinoTUpdate &&
        update.index == VIndex.channelBulk4Scene &&
        _pendingReplies.isNotEmpty) {
      _pendingReplies.removeFirst().complete(update.text);
    }
  }

  /// Detects a change in which DMX channel each of the 3 sliders points
  /// to (e.g. the user pressed [ChannelNumberBar]'s advance-group arrow)
  /// and re-fetches that slot's full V71 state — there's no push
  /// notification for this, same reasoning as every other polled screen
  /// in this app.
  void _checkChannels() {
    if (!mounted) return;
    final state = ref.read(appStateProvider);
    final numbers = [
      state.channel1Number,
      state.channel2Number,
      state.channel3Number,
    ];
    for (var slot = 0; slot < _channelCount; slot++) {
      final n = numbers[slot];
      if (n != null && n != _fetchedFor[slot]) {
        _fetchedFor[slot] = n;
        unawaited(_fetchSlot(slot, n));
      }
    }
  }

  Future<String?> _roundTrip(String payload) async {
    final completer = Completer<String?>();
    _pendingReplies.addLast(completer);
    ref.read(protocolProvider).writeText(VIndex.channelBulk4Scene, payload);

    final reply = await completer.future.timeout(
      _roundTripTimeout,
      onTimeout: () => null,
    );

    if (!completer.isCompleted) {
      // Timed out — this request's reply, if it ever shows up late, would
      // get misattributed to whatever the next request turns out to be
      // (the FIFO is now desynced). Drop everything else pending too
      // rather than risk silently handing one slot's data to another —
      // 2s is generous, this should only happen on a real connection
      // hiccup, and any slot left unfetched just retries on the next poll
      // tick that finds its channel number changed.
      _pendingReplies.remove(completer);
      for (final pending in _pendingReplies) {
        if (!pending.isCompleted) pending.complete(null);
      }
      _pendingReplies.clear();
    }
    return reply;
  }

  _ChannelFull? _parse(String? reply) {
    if (reply == null) return null;
    final parts = reply.split('|');
    if (parts.length < 13) return null;
    final valors = [for (var i = 0; i < 4; i++) int.tryParse(parts[i]) ?? 0];
    final transicions = [
      for (var i = 0; i < 4; i++)
        (
          type: TransitionType.values.firstWhere(
            (t) => t.vValue == (int.tryParse(parts[4 + i * 2]) ?? 0),
            orElse: () => TransitionType.lineal,
          ),
          saltPercent: (int.tryParse(parts[4 + i * 2 + 1]) ?? 0).clamp(0, 100),
        ),
    ];
    final name = parts.sublist(12).join('|');
    return (valors: valors, transicions: transicions, name: name);
  }

  Future<void> _fetchSlot(int slot, int channelNumber) async {
    final parsed = _parse(await _roundTrip('$channelNumber'));
    if (!mounted || parsed == null) return;
    setState(() => _channels[slot] = parsed);
  }

  Future<void> _updateSlot(int slot, _TransitionEntry entry) async {
    final current = _channels[slot];
    final channelNumber = _fetchedFor[slot];
    if (current == null || channelNumber == null) return;

    final newTransicions = [
      for (var i = 0; i < 4; i++)
        i == _selectedTransition ? entry : current.transicions[i],
    ];

    // The active scene's level can be live-edited by ChannelSliders (a
    // sibling widget, via V01-03) completely independently of this
    // editor's own V71 cache — which only gets refetched when the
    // channel NUMBER changes, not on every slider drag. Sending back
    // current.valors as-is here would silently overwrite whatever the
    // user just dragged the slider to with this now-stale cached value
    // (confirmed on real hardware: set a level to 255, change the
    // transition type, and the level snapped back to 0). Since V71
    // writes are atomic (the whole channel, all 4 scenes, at once), the
    // fix is to fold the live value for the active scene back in right
    // before building the payload.
    final state = ref.read(appStateProvider);
    final activeScene = state.activeScene;
    final liveValues = [
      state.channel1Value,
      state.channel2Value,
      state.channel3Value,
    ];
    final live = liveValues[slot];
    final valors = [
      for (var i = 0; i < 4; i++)
        (activeScene != null && activeScene - 1 == i && live != null)
            ? live.round()
            : current.valors[i],
    ];

    setState(() {
      _channels[slot] = (valors: valors, transicions: newTransicions, name: current.name);
    });

    final payload =
        '$channelNumber|${valors.join('|')}|'
        '${[for (final t in newTransicions) '${t.type.vValue}|${t.saltPercent}'].join('|')}'
        '|${current.name}';
    final parsed = _parse(await _roundTrip(payload));
    if (mounted && parsed != null) setState(() => _channels[slot] = parsed);
  }

  static const _colors = [Colors.red, Colors.green, Colors.blue];

  @override
  Widget build(BuildContext context) {
    // Re-syncs to the newly active scene's outgoing transition whenever it
    // changes on the device (top scene navigator's arrows, or the cycle
    // auto-advancing) — mirrors the initState() seed above. Only fires on
    // an actual change, so it never fights with the editor's own arrows
    // while the active scene stays the same.
    ref.listen<int?>(appStateProvider.select((s) => s.activeScene), (
      previous,
      next,
    ) {
      if (next != null && next >= 1 && next <= 4) {
        setState(() => _selectedTransition = next - 1);
      }
    });

    // Bounds the browsable transitions to however many scenes are actually
    // active — with e.g. 2 active scenes there are only 2 real transitions
    // (1→2 and 2→1, cyclic), not 4; slots 3/4 are unconfigured leftovers
    // from the fixed-size-4 struct. Firmware's own wraparound now matches
    // this (see actualizarCanalTransicio() in either main.cpp: `% 4` ->
    // `% NumeroEscenes`).
    final activeScenesCount =
        ref.watch(appStateProvider.select((s) => s.activeScenesCount)) ?? 4;
    if (_selectedTransition >= activeScenesCount) {
      _selectedTransition = activeScenesCount - 1;
    }

    final scheme = Theme.of(context).colorScheme;
    final from = _selectedTransition + 1;
    final to = (_selectedTransition + 1) % activeScenesCount + 1;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              NavArrowButton(
                icon: Icons.arrow_back,
                onPressed: () => setState(
                  () => _selectedTransition =
                      (_selectedTransition + activeScenesCount - 1) %
                      activeScenesCount,
                ),
              ),
              Expanded(
                child: Text(
                  'Transició Escena $from → Escena $to',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              NavArrowButton(
                icon: Icons.arrow_forward,
                onPressed: () => setState(
                  () => _selectedTransition =
                      (_selectedTransition + 1) % activeScenesCount,
                ),
              ),
              if (widget.trailing != null) ...[
                const SizedBox(width: 6),
                widget.trailing!,
              ],
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              for (var slot = 0; slot < _channelCount; slot++)
                Expanded(
                  child: _ChannelColumn(
                    key: ValueKey(slot),
                    color: _colors[slot],
                    entry: _channels[slot]
                        ?.transicions[_selectedTransition],
                    onChanged: (entry) => _updateSlot(slot, entry),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ChannelColumn extends StatefulWidget {
  const _ChannelColumn({
    super.key,
    required this.color,
    required this.entry,
    required this.onChanged,
  });

  final Color color;
  final _TransitionEntry? entry;
  final ValueChanged<_TransitionEntry> onChanged;

  @override
  State<_ChannelColumn> createState() => _ChannelColumnState();
}

final _max100Formatter = TextInputFormatter.withFunction((old, next) {
  if (next.text.isEmpty) return next;
  final parsed = int.tryParse(next.text);
  return (parsed == null || parsed > 100) ? old : next;
});

class _ChannelColumnState extends State<_ChannelColumn> {
  final _percentController = TextEditingController();
  final _percentFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    // Select the whole number on focus, so typing immediately replaces it
    // instead of the user having to manually clear/backspace first — same
    // as ChannelSliders' own numeric fields.
    _percentFocus.addListener(() {
      if (_percentFocus.hasFocus) {
        _percentController.selection = TextSelection(
          baseOffset: 0,
          extentOffset: _percentController.text.length,
        );
      }
    });
  }

  @override
  void dispose() {
    _percentController.dispose();
    _percentFocus.dispose();
    super.dispose();
  }

  static String _typeLabel(TransitionType type) {
    switch (type) {
      case TransitionType.lineal:
        return 'Lineal';
      case TransitionType.easeOut:
        return 'Fi suau';
      case TransitionType.easeIn:
        return 'Inici suau';
      case TransitionType.salt:
        return 'Salt';
    }
  }

  void _commitPercentFromText() {
    final current = widget.entry ?? _defaultTransition;
    final parsed = int.tryParse(_percentController.text);
    if (parsed == null) return;
    widget.onChanged(
      (type: current.type, saltPercent: parsed.clamp(0, 100)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final current = widget.entry ?? _defaultTransition;
    if (!_percentFocus.hasFocus) {
      _percentController.text = '${current.saltPercent}';
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 3),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      decoration: BoxDecoration(
        border: Border.all(color: widget.color.withValues(alpha: 0.6), width: 2),
        borderRadius: BorderRadius.circular(10),
      ),
      child: widget.entry == null
          ? const SizedBox(
              height: 32,
              child: Center(
                child: SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonHideUnderline(
                  child: DropdownButton<TransitionType>(
                    value: current.type,
                    isDense: true,
                    isExpanded: true,
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                    // selectedItemBuilder's list must stay index-aligned
                    // with items' — both iterate _displayOrder (not
                    // TransitionType.values, whose declaration order
                    // matches the fixed wire vValues and must not change)
                    // so the picker shows Lineal/Fi suau/Inici suau/Salt.
                    selectedItemBuilder: (context) => [
                      for (final t in _displayOrder)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            _typeLabel(t),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    items: [
                      for (final t in _displayOrder)
                        DropdownMenuItem(value: t, child: Text(_typeLabel(t))),
                    ],
                    onChanged: (t) {
                      if (t != null) {
                        widget.onChanged(
                          (type: t, saltPercent: current.saltPercent),
                        );
                      }
                    },
                  ),
                ),
                // maintainSize (not just an `if`): reserves the same
                // height whether SALT is selected or not, so every
                // column's box stays the same size instead of the ones
                // without a percent field looking shorter.
                Visibility(
                  visible: current.type == TransitionType.salt,
                  maintainSize: true,
                  maintainAnimation: true,
                  maintainState: true,
                  child: Padding(
                    // Keeps the field clear of the colored border on every
                    // side, not just the top — it was touching the box
                    // edge before.
                    padding: const EdgeInsets.fromLTRB(4, 5, 4, 3),
                    child: SizedBox(
                      // Wide enough that "100%" stays fully visible while
                      // typing — a narrower field here clipped the digits,
                      // same issue ChannelSliders' own numeric field had
                      // before it was widened.
                      width: 64,
                      child: TextField(
                        controller: _percentController,
                        focusNode: _percentFocus,
                        textAlign: TextAlign.center,
                        keyboardType: TextInputType.number,
                        maxLength: 3,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          _max100Formatter,
                        ],
                        style: const TextStyle(fontSize: 13),
                        decoration: const InputDecoration(
                          // "%" lives inside the field's own box (suffix)
                          // instead of as a separate Text glued right next
                          // to it.
                          suffixText: '%',
                          suffixStyle: TextStyle(fontSize: 12),
                          counterText: '',
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 6,
                          ),
                          border: OutlineInputBorder(),
                        ),
                        onSubmitted: (_) => _commitPercentFromText(),
                        onTapOutside: (_) {
                          FocusManager.instance.primaryFocus?.unfocus();
                          _commitPercentFromText();
                        },
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
