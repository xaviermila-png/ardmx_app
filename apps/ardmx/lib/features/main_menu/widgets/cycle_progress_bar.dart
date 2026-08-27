import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/v_map.dart';
import '../../../state/providers.dart';

/// Cycle progress indicator shown at the top of Main Menu while a cycle is
/// running (Automàtic or Manual): elapsed time, the current phase/
/// transition and the total time are shown above a plain rectangular bar
/// (sharp corners, empty/outlined) that fills left-to-right as V14
/// progresses toward V15.
///
/// The Virtuino wire protocol is pure request/response — the Arduino never
/// pushes V10/V14/V15 on its own, so this widget polls for them while
/// visible (matching how the original Virtuino app must have kept its own
/// cycle display live). 500ms, not a full second, so the bar/elapsed time
/// catch up to a state change sooner — same cadence most of the other
/// polled screens already use during playback (Cicle, Simulació).
///
/// Space for this widget is always reserved (via [Visibility]'s
/// `maintainSize`), even when hidden (Escena fixa / Configuració modes) —
/// otherwise the button grid below it would shift position depending on
/// whether a cycle happens to be running.
class CycleProgressBar extends ConsumerStatefulWidget {
  const CycleProgressBar({super.key});

  @override
  ConsumerState<CycleProgressBar> createState() => _CycleProgressBarState();
}

class _CycleProgressBarState extends ConsumerState<CycleProgressBar> {
  static const _pollInterval = Duration(milliseconds: 500);

  /// V[10] (cycle state, 1-8) -> label, matching the Arduino sketch's own
  /// EstatActual comments (0-indexed there, V10 = EstatActual + 1).
  static const _stateLabels = {
    1: 'Escena 1',
    2: 'Transició a Escena 2',
    3: 'Escena 2',
    4: 'Transició a Escena 3',
    5: 'Escena 3',
    6: 'Transició a Escena 4',
    7: 'Escena 4',
    8: 'Transició a Escena 1',
  };

  Timer? _pollTimer;

  void _poll() {
    ref.read(protocolProvider).requestAll([
      VIndex.cycleState,
      VIndex.currentTime,
      VIndex.totalTime,
    ]);
  }

  void _startPolling() {
    if (_pollTimer != null) return;
    _poll();
    _pollTimer = Timer.periodic(_pollInterval, (_) => _poll());
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  @override
  void dispose() {
    _stopPolling();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mainSelector = ref.watch(
      appStateProvider.select((s) => s.mainSelector),
    );
    final isCycling =
        mainSelector == MainSelectorMode.automatic.vValue ||
        mainSelector == MainSelectorMode.manual.vValue;

    if (isCycling) {
      _startPolling();
    } else {
      _stopPolling();
    }

    final currentTime =
        ref.watch(appStateProvider.select((s) => s.currentTime)) ?? 0;
    final totalTime =
        ref.watch(appStateProvider.select((s) => s.totalTime)) ?? 0;
    final cycleState = ref.watch(appStateProvider.select((s) => s.cycleState));
    final stateLabel = _stateLabels[cycleState] ?? '—';
    final fraction = totalTime > 0
        ? (currentTime / totalTime).clamp(0.0, 1.0)
        : 0.0;
    final barColor = Theme.of(context).colorScheme.primary;
    final textStyle = TextStyle(
      fontWeight: FontWeight.bold,
      fontSize: 20,
      color: barColor,
    );

    return Visibility(
      visible: isCycling,
      maintainSize: true,
      maintainAnimation: true,
      maintainState: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text('${currentTime.round()}"', style: textStyle),
              Expanded(
                child: Text(
                  stateLabel,
                  textAlign: TextAlign.center,
                  style: textStyle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text('${totalTime.round()}"', style: textStyle),
            ],
          ),
          const SizedBox(height: 4),
          Container(
            height: 40,
            decoration: BoxDecoration(
              border: Border.all(color: barColor, width: 2),
            ),
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: fraction,
              child: Container(color: barColor),
            ),
          ),
        ],
      ),
    );
  }
}
