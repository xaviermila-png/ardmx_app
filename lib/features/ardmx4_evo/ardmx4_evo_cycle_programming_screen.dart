import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/v_map.dart';
import '../../state/providers.dart';
import '../../widgets/app_scaffold.dart';
import '../main_menu/widgets/volume_slider.dart';

/// Cycle Programming screen for the ARDMX4 EVO tree — near-duplicate of the
/// Mega's own [CycleProgrammingScreen] (same V10-V28/V50 protocol, ported
/// verbatim into the EVO firmware), kept as its own copy per the project's
/// separate-navigation-per-product decision.
class Ardmx4EvoCycleProgrammingScreen extends ConsumerStatefulWidget {
  const Ardmx4EvoCycleProgrammingScreen({super.key});

  @override
  ConsumerState<Ardmx4EvoCycleProgrammingScreen> createState() =>
      _Ardmx4EvoCycleProgrammingScreenState();
}

class _Ardmx4EvoCycleProgrammingScreenState
    extends ConsumerState<Ardmx4EvoCycleProgrammingScreen> {
  static const _pollInterval = Duration(milliseconds: 400);

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

    final sceneCount =
        (ref.watch(appStateProvider.select((s) => s.activeScenesCount))) ?? 4;
    final periodCount = sceneCount.clamp(1, 4) * 2;
    final phaseNames = _phaseNamesFor(sceneCount.clamp(1, 4));

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
                        child: Text(
                          '${currentTime.round()}" / ${totalTime.round()}"',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
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
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 2, 16, 0),
            child: VolumeSlider(
              titleFontSize: 14,
              titleAlignment: Alignment.bottomRight,
              leadingAlignment: Alignment.bottomLeft,
              titleRowHeight: 20,
              thumbSize: 30,
              leading: Text(
                songNumber == null || songNumber == 0
                    ? 'Cançó: Off'
                    : 'Cançó: $songNumber',
                style: const TextStyle(
                  fontSize: 14,
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
                  heroTag: 'ardmx4EvoCycleProgrammingBack',
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
      // Only a top border (not top+bottom): consecutive active rows used to
      // each draw their own bottom+top border, showing as two close-together
      // orange lines between phases — a single top border per row shows one
      // line at each boundary instead, and saves a bit of vertical space.
      decoration: active
          ? BoxDecoration(
              color: Colors.amber.shade100,
              border: Border(
                top: BorderSide(color: Colors.amber.shade700, width: 1.5),
              ),
            )
          : null,
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
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
              child: Text(
                '${accumulated.round()}"',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
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
            child: Text(
              '${duration.round()}"',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
