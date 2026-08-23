import 'dart:async';

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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkChannels());
    _pollTimer = Timer.periodic(_pollInterval, (_) => _checkChannels());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
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
    final protocol = ref.read(protocolProvider);
    final completer = Completer<String?>();
    late final StreamSubscription<VirtuinoUpdate> subscription;

    subscription = protocol.updates.listen((update) {
      if (update is VirtuinoTUpdate &&
          update.index == VIndex.channelBulk4Scene &&
          !completer.isCompleted) {
        completer.complete(update.text);
      }
    });

    protocol.writeText(VIndex.channelBulk4Scene, payload);
    final reply = await completer.future.timeout(
      _roundTripTimeout,
      onTimeout: () => null,
    );
    await subscription.cancel();
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
    setState(() {
      _channels[slot] = (
        valors: current.valors,
        transicions: newTransicions,
        name: current.name,
      );
    });

    final payload =
        '$channelNumber|${current.valors.join('|')}|'
        '${[for (final t in newTransicions) '${t.type.vValue}|${t.saltPercent}'].join('|')}'
        '|${current.name}';
    final parsed = _parse(await _roundTrip(payload));
    if (mounted && parsed != null) setState(() => _channels[slot] = parsed);
  }

  static const _colors = [Colors.red, Colors.green, Colors.blue];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final from = _selectedTransition + 1;
    final to = (_selectedTransition + 1) % 4 + 1;

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
                  () => _selectedTransition = (_selectedTransition + 3) % 4,
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
                  () => _selectedTransition = (_selectedTransition + 1) % 4,
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

class _ChannelColumnState extends State<_ChannelColumn> {
  final _percentController = TextEditingController();
  final _percentFocus = FocusNode();

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
      case TransitionType.salt:
        return 'Salt';
      case TransitionType.easeIn:
        return 'Ease in';
      case TransitionType.easeOut:
        return 'Ease out';
    }
  }

  void _commitPercent() {
    final current = widget.entry ?? _defaultTransition;
    final parsed = int.tryParse(_percentController.text);
    if (parsed == null) return;
    widget.onChanged((type: current.type, saltPercent: parsed.clamp(0, 100)));
  }

  @override
  Widget build(BuildContext context) {
    final current = widget.entry ?? _defaultTransition;
    if (!_percentFocus.hasFocus) {
      _percentController.text = '${current.saltPercent}';
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 3),
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
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
                    selectedItemBuilder: (context) => [
                      for (final t in TransitionType.values)
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
                      for (final t in TransitionType.values)
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
                if (current.type == TransitionType.salt)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 34,
                          child: TextField(
                            controller: _percentController,
                            focusNode: _percentFocus,
                            textAlign: TextAlign.center,
                            keyboardType: TextInputType.number,
                            maxLength: 3,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                            style: const TextStyle(fontSize: 12),
                            decoration: const InputDecoration(
                              counterText: '',
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: 2,
                              ),
                              border: OutlineInputBorder(),
                            ),
                            onSubmitted: (_) => _commitPercent(),
                            onTapOutside: (_) {
                              FocusManager.instance.primaryFocus?.unfocus();
                              _commitPercent();
                            },
                          ),
                        ),
                        const Text('%', style: TextStyle(fontSize: 11)),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}
