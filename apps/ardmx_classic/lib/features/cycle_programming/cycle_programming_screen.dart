import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/v_map.dart';
import '../../state/providers.dart';
import '../../widgets/app_scaffold.dart';
import '../main_menu/widgets/volume_slider.dart';

/// Cycle Programming screen (V50=1): Play/Pause, live progress, the 8-period
/// duration table, song number, and volume.
///
/// **V21-V28 are cumulative elapsed-time checkpoints, not per-period
/// durations** — confirmed by the user against the real Arduino sketch,
/// correcting an earlier misreading of the spec. Each purple box below is
/// one of these raw, directly-editable values (e.g. V23 is the total
/// elapsed time from cycle start through the end of Scene 2). The green
/// "duration of this phase alone" box next to it is never sent to the
/// Arduino — it's purely `V[i] - V[i-1]` computed locally for readability
/// (with V[-1] treated as 0 for the very first row).
class CycleProgrammingScreen extends ConsumerStatefulWidget {
  const CycleProgrammingScreen({super.key});

  @override
  ConsumerState<CycleProgrammingScreen> createState() =>
      _CycleProgrammingScreenState();
}

class _CycleProgrammingScreenState
    extends ConsumerState<CycleProgrammingScreen> {
  static const _pollInterval = Duration(milliseconds: 400);

  /// Builds the phase label list for a given scene count (1-4, V18):
  /// 'Escena 1', 'Transició a Escena 2', 'Escena 2', ... — with the final
  /// transition always closing the cycle back to Escena 1, whatever the
  /// scene count. Mirrors [CycleProgressBar]'s own `_stateLabels` (same
  /// wording), kept as its own copy here since that widget is keyed off V10
  /// (cycleState) while this screen derives the active phase locally (see
  /// the comment on `activePeriod` in build()).
  static List<String> _phaseNamesFor(int sceneCount) {
    final names = <String>[];
    for (var scene = 1; scene <= sceneCount; scene++) {
      names.add('Escena $scene');
      names.add('Transició a Escena ${scene < sceneCount ? scene + 1 : 1}');
    }
    return names;
  }

  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    // Deferred a frame: _poll() calls ModalRoute.of(context), which isn't
    // resolvable synchronously inside initState (see Scene/Channels, RGB
    // Wheel and Parameters for the same fix and the crash it avoids).
    WidgetsBinding.instance.addPostFrameCallback((_) => _poll());
    _pollTimer = Timer.periodic(_pollInterval, (_) => _poll());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  void _poll() {
    // Only the topmost route should poll — see Scene/Channels, RGB Wheel and
    // Parameters' _poll() for why: two screens polling at once can corrupt
    // the wire protocol badly enough to leave garbage stuck in Arduino state.
    if (!(ModalRoute.of(context)?.isCurrent ?? true)) return;

    ref.read(protocolProvider).requestAll([
      VIndex.playStop,
      VIndex.pause,
      VIndex.currentTime,
      VIndex.totalTime,
      VIndex.songNumber,
      VIndex.volume,
      VIndex.activeScenesCount,
      for (var i = 0; i < 8; i++) VIndex.periodDuration(i),
    ]);
  }

  Future<void> _editPeriod(int periodOffset, double current) async {
    final controller = TextEditingController(text: '${current.round()}');
    String? error;

    final result = await showDialog<int>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            void submit() {
              final parsed = int.tryParse(controller.text);
              if (parsed == null || parsed < 0) {
                setDialogState(() => error = 'Ha de ser 0 o més');
                return;
              }
              Navigator.of(context).pop(parsed);
            }

            return AlertDialog(
              title: const Text('Temps acumulat (segons)'),
              content: TextField(
                controller: controller,
                keyboardType: TextInputType.number,
                autofocus: true,
                decoration: InputDecoration(errorText: error),
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
      ref
          .read(appStateProvider.notifier)
          .setPeriodDuration(periodOffset, result.toDouble());
    }
  }

  @override
  Widget build(BuildContext context) {
    final isPlaying = ref.watch(appStateProvider.select((s) => s.isPlaying));
    final isPaused = ref.watch(appStateProvider.select((s) => s.isPaused));
    final currentTime =
        ref.watch(appStateProvider.select((s) => s.currentTime)) ?? 0;
    final totalTime =
        ref.watch(appStateProvider.select((s) => s.totalTime)) ?? 0;
    final songNumber = ref.watch(appStateProvider.select((s) => s.songNumber));
    final periods = [
      for (var i = 0; i < 8; i++)
        ref.watch(appStateProvider.select((s) => s.periodDuration(i))) ?? 0,
    ];
    final fraction = totalTime > 0
        ? (currentTime / totalTime).clamp(0.0, 1.0)
        : 0.0;

    // V18: only cycle through the scenes the user actually configured (1-4,
    // Paràmetres) — Arduino itself only ever advances through
    // NumeroEscenes*2 periods, so rows beyond that are stale/irrelevant.
    final sceneCount =
        (ref.watch(appStateProvider.select((s) => s.activeScenesCount))) ?? 4;
    final periodCount = sceneCount.clamp(1, 4) * 2;
    final phaseNames = _phaseNamesFor(sceneCount.clamp(1, 4));

    // V10 (cycleState) only reflects the main dial's Automàtic/Manual mode,
    // not this screen's own Play/Pause (V12/V13) — confirmed on real
    // hardware (V10 stayed 0 the whole time while V12=1 and V14 counted
    // up). So the active phase here is derived locally from where
    // currentTime falls among the cumulative checkpoints instead.
    int? activePeriod;
    if (isPlaying) {
      var previous = 0.0;
      for (var i = 0; i < periodCount; i++) {
        if (currentTime >= previous && currentTime < periods[i]) {
          activePeriod = i;
          break;
        }
        previous = periods[i];
      }
    }

    return AppScaffold(
      title: 'Programació Cicles',
      automaticallyImplyLeading: false,
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      GestureDetector(
                        onTap: () => ref
                            .read(appStateProvider.notifier)
                            .setPlaying(!isPlaying),
                        child: Container(
                          width: 64,
                          height: 40,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: isPlaying
                                ? Colors.green.shade600
                                : Colors.red.shade600,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.black45),
                          ),
                          child: Text(
                            isPlaying ? 'ON' : 'OFF',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'Play',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      if (isPlaying)
                        GestureDetector(
                          onTap: () => ref
                              .read(appStateProvider.notifier)
                              .setPaused(!isPaused),
                          child: Container(
                            width: 96,
                            height: 40,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: isPaused
                                  ? Colors.red.shade700
                                  : Colors.grey.shade300,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: isPaused
                                    ? Colors.red.shade900
                                    : Colors.grey.shade600,
                              ),
                            ),
                            child: Text(
                              'Pausa',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: isPaused
                                    ? Colors.white
                                    : Colors.grey.shade700,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Text(
                        'Transcorregut',
                        style: TextStyle(fontSize: 11),
                      ),
                      const Spacer(),
                      const Text('Total', style: TextStyle(fontSize: 11)),
                    ],
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: Stack(
                          children: [
                            Container(height: 32, color: Colors.blue.shade100),
                            FractionallySizedBox(
                              widthFactor: fraction,
                              child: Container(
                                height: 32,
                                color: Colors.blue.shade700,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        width: 70,
                        height: 32,
                        color: Colors.deepPurple.shade400,
                        alignment: Alignment.center,
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        // FittedBox instead of a fixed fontSize: a cycle
                        // running past 999s (totalTime 4+ digits) would
                        // otherwise clip inside this fixed-width box.
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            '${currentTime.round()}" / ${totalTime.round()}"',
                            maxLines: 1,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Temps Transició Escenes',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 2),
                  // Capçaleres de columna: sense elles, la caixa lila
                  // (moment en què s'acaba la fase, un valor acumulat des
                  // de l'inici del cicle) es confonia amb el "Transcorregut"
                  // de dalt, que és un altre valor acumulat similar però no
                  // el mateix.
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: Row(
                      children: [
                        Spacer(),
                        SizedBox(
                          width: 64,
                          child: Text(
                            'Acaba a',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 11),
                          ),
                        ),
                        SizedBox(width: 8),
                        SizedBox(
                          width: 64,
                          child: Text(
                            'Durada',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 11),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < periodCount; i++) ...[
                        _PeriodRow(
                          label: phaseNames[i],
                          // Progress-bar style: every phase up to and
                          // including the current one stays lit — both the
                          // green dot and the yellow highlight remain fixed
                          // as "already done", not just the exact current
                          // row (per the user: fent-ho així es veu d'un cop
                          // d'ull tot el recorregut fet, no només l'últim
                          // pas).
                          active: activePeriod != null && i <= activePeriod,
                          accumulated: periods[i],
                          duration: (periods[i] - (i == 0 ? 0 : periods[i - 1]))
                              .clamp(0, double.infinity),
                          onTap: () => _editPeriod(i, periods[i]),
                        ),
                        const SizedBox(height: 3),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
          // Volum sempre enganxat a baix (fora de l'scroll), just per sobre
          // de la fletxa de retorn — abans quedava al final del contingut
          // desplaçable i podia quedar amagat quan hi havia 4 escenes.
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: VolumeSlider(
              leading: Text(
                songNumber == null || songNumber == 0
                    ? 'Cançó: Off'
                    : 'Cançó: $songNumber',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
            child: Row(
              children: [
                FloatingActionButton(
                  heroTag: 'cycleProgrammingBack',
                  onPressed: () => Navigator.of(context).pop(),
                  tooltip: 'Tornar al menú principal',
                  child: const Icon(Icons.arrow_back),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PeriodRow extends StatelessWidget {
  const _PeriodRow({
    required this.label,
    required this.active,
    required this.accumulated,
    required this.duration,
    required this.onTap,
  });

  final String label;
  final bool active;
  final double accumulated;
  final double duration;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      // Franja de marge a marge (no un requadre ajustat al contingut) perquè
      // la fase en curs es distingeixi d'un cop d'ull sense dependre de
      // l'amplada variable del text.
      decoration: active
          ? BoxDecoration(
              color: Colors.amber.shade100,
              border: Border.symmetric(
                horizontal: BorderSide(
                  color: Colors.amber.shade700,
                  width: 1.5,
                ),
              ),
            )
          : null,
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
          Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: active ? Colors.green.shade600 : Colors.grey.shade400,
              border: Border.all(color: Colors.black45),
            ),
          ),
          const SizedBox(width: 16),
          InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: onTap,
            child: Container(
              width: 64,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.deepPurple.shade300,
                borderRadius: BorderRadius.circular(6),
              ),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  '${accumulated.round()}"',
                  maxLines: 1,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            width: 64,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.green.shade700,
              borderRadius: BorderRadius.circular(6),
            ),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                '${duration.round()}"',
                maxLines: 1,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
