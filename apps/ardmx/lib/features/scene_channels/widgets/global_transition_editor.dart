import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/v_map.dart';
import '../../../core/protocol/virtuino_update.dart';
import '../../../state/providers.dart';
import 'nav_arrow_button.dart';

/// One of the 4 global transitions (type + salt%) — local widget state, not
/// carried through [AppStateProvider]: like V71 (channel bulk export), V72
/// is an out-of-band text index, round-tripped directly (see
/// `_ExportImportSectionState` in the EVO/One v2 system config screens for
/// the same pattern applied to channel data).
typedef _TransitionEntry = ({TransitionType type, int saltPercent});

const _defaultTransition = (type: TransitionType.lineal, saltPercent: 0);

/// "Transició Escena N -> Escena M" editor — replaces the old per-channel
/// [TransitionModeSelector] (gradual/inicial/final per R/G/B channel) with a
/// single global type (LINEAL/SALT/EASE_IN/EASE_OUT) shared by every channel
/// during that transition, plus a salt-percentage slider only relevant to
/// SALT. [_selected] (which of the 4 transitions is being edited) is pure
/// local UI state — cycling it never writes to the wire, only reading or
/// changing the transition's own type/percentage does (a full V72 bulk
/// write of all 4 transitions each time, simplest given the wire format).
class GlobalTransitionEditor extends ConsumerStatefulWidget {
  const GlobalTransitionEditor({super.key});

  @override
  ConsumerState<GlobalTransitionEditor> createState() =>
      _GlobalTransitionEditorState();
}

class _GlobalTransitionEditorState
    extends ConsumerState<GlobalTransitionEditor> {
  static const _roundTripTimeout = Duration(seconds: 2);

  List<_TransitionEntry> _transitions = List.filled(4, _defaultTransition);
  int _selected = 0;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<String?> _roundTrip(String payload) async {
    final protocol = ref.read(protocolProvider);
    final completer = Completer<String?>();
    late final StreamSubscription<VirtuinoUpdate> subscription;

    subscription = protocol.updates.listen((update) {
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
    await subscription.cancel();
    return reply;
  }

  List<_TransitionEntry>? _parse(String? reply) {
    if (reply == null) return null;
    final parts = reply.split('|');
    if (parts.length < 8) return null;
    return [
      for (var i = 0; i < 8; i += 2)
        (
          type: TransitionType.values.firstWhere(
            (t) => t.vValue == (int.tryParse(parts[i]) ?? 0),
            orElse: () => TransitionType.lineal,
          ),
          saltPercent: (int.tryParse(parts[i + 1]) ?? 0).clamp(0, 100),
        ),
    ];
  }

  Future<void> _refresh() async {
    final parsed = _parse(await _roundTrip('?'));
    if (!mounted || parsed == null) return;
    setState(() {
      _transitions = parsed;
      _loaded = true;
    });
  }

  Future<void> _send() async {
    final payload = [
      for (final t in _transitions) '${t.type.vValue}|${t.saltPercent}',
    ].join('|');
    final parsed = _parse(await _roundTrip(payload));
    if (!mounted || parsed == null) return;
    setState(() => _transitions = parsed);
  }

  void _updateSelected(_TransitionEntry entry) {
    setState(() {
      _transitions = [
        for (var i = 0; i < 4; i++) i == _selected ? entry : _transitions[i],
      ];
    });
    _send();
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

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final current = _transitions[_selected];
    final from = _selected + 1;
    final to = (_selected + 1) % 4 + 1;

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
                onPressed: () =>
                    setState(() => _selected = (_selected + 3) % 4),
              ),
              Expanded(
                child: Text(
                  'Transició Escena $from → Escena $to',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              NavArrowButton(
                icon: Icons.arrow_forward,
                onPressed: () =>
                    setState(() => _selected = (_selected + 1) % 4),
              ),
            ],
          ),
          const SizedBox(height: 4),
          if (!_loaded)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else ...[
            SegmentedButton<TransitionType>(
              segments: [
                for (final type in TransitionType.values)
                  ButtonSegment(value: type, label: Text(_typeLabel(type))),
              ],
              selected: {current.type},
              onSelectionChanged: (selection) =>
                  _updateSelected((type: selection.first, saltPercent: current.saltPercent)),
              style: const ButtonStyle(
                visualDensity: VisualDensity.compact,
              ),
            ),
            if (current.type == TransitionType.salt)
              Row(
                children: [
                  const SizedBox(width: 8),
                  const Text('Salt al', style: TextStyle(fontSize: 13)),
                  Expanded(
                    child: Slider(
                      value: current.saltPercent.toDouble(),
                      min: 0,
                      max: 100,
                      divisions: 100,
                      label: '${current.saltPercent}%',
                      onChanged: (v) => setState(() {
                        _transitions = [
                          for (var i = 0; i < 4; i++)
                            i == _selected
                                ? (type: current.type, saltPercent: v.round())
                                : _transitions[i],
                        ];
                      }),
                      onChangeEnd: (v) => _updateSelected(
                        (type: current.type, saltPercent: v.round()),
                      ),
                    ),
                  ),
                  Text('${current.saltPercent}%', style: const TextStyle(fontSize: 13)),
                  const SizedBox(width: 8),
                ],
              ),
          ],
        ],
      ),
    );
  }
}
