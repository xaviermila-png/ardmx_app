import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/v_map.dart';
import '../../core/protocol/virtuino_update.dart';
import '../../state/providers.dart';
import '../system_config/config_json.dart';
import 'curve_math.dart';
import 'widgets/channel_legend.dart';
import 'widgets/cycle_chart_painter.dart';

const _pageSize = 12;

const _channelColors = [
  Colors.red,
  Colors.green,
  Colors.blue,
  Colors.orange,
  Colors.purple,
  Colors.teal,
  Colors.pink,
  Colors.amber,
  Colors.cyan,
  Colors.indigo,
  Colors.lime,
  Colors.brown,
];

/// Graphical visualizer of the 4-scene/4-transition cycle model, reusing
/// its data (V71 per-channel bulk, V09/V10/V14/V18/V21-28 cycle state,
/// V12/V13 playback) rather than inventing a parallel one. Shared by the
/// ARDMX One v2 and ARDMX EVO trees — [channelCountVIndex] is the one
/// per-product difference (V08 vs [VIndex.activeChannelsCount], same
/// distinction [ExportImportSection] already makes).
///
/// Not reachable from an ARDMX One v1 device — this screen isn't wired
/// into that tree's routes/menus at all (v1 has no scenes/transitions
/// model for it to visualize), so no extra runtime gating is needed here.
///
/// Forces landscape on entry and restores portrait on exit (see
/// [initState]/[dispose]) — the chart wants all the width it can get.
/// Reuses [AppScreen.cycleProgramming] as this screen's own V50 mirror
/// value (see [AppRoutes.screenForRoute]): that's the same gate the
/// firmware's `Cicle()`/`GestioCicles()` already runs under, and Play/
/// Pausa (V12/V13) only get processed while it's open — no new firmware
/// screen id needed for playback control to work from here too.
class SimulacioScreen extends ConsumerStatefulWidget {
  const SimulacioScreen({super.key, required this.channelCountVIndex});

  final int channelCountVIndex;

  @override
  ConsumerState<SimulacioScreen> createState() => _SimulacioScreenState();
}

class _SimulacioScreenState extends ConsumerState<SimulacioScreen> {
  static const _pollInterval = Duration(milliseconds: 400);
  static const _roundTripTimeout = Duration(milliseconds: 800);

  Timer? _pollTimer;
  int _page = 0;
  int? _totalChannels;
  bool _loadingPage = false;
  List<ChannelConfigEntry?> _pageChannels = List.filled(_pageSize, null);
  List<bool> _visible = List.filled(_pageSize, true);

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    WidgetsBinding.instance.addPostFrameCallback((_) => _poll());
    _pollTimer = Timer.periodic(_pollInterval, (_) => _poll());
    _loadPage();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    super.dispose();
  }

  void _poll() {
    if (!(ModalRoute.of(context)?.isCurrent ?? true)) return;
    ref.read(protocolProvider).requestAll([
      VIndex.playStop,
      VIndex.pause,
      VIndex.currentTime,
      VIndex.totalTime,
      VIndex.activeScenesCount,
      widget.channelCountVIndex,
      for (var i = 0; i < 8; i++) VIndex.periodDuration(i),
    ]);
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

  Future<String?> _channelRoundTrip(String payload) async {
    final protocol = ref.read(protocolProvider);
    for (var attempt = 0; attempt < 3; attempt++) {
      final completer = Completer<String?>();
      late final StreamSubscription<VirtuinoUpdate> sub;
      sub = protocol.updates.listen((update) {
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
      await sub.cancel();
      if (reply != null) return reply;
    }
    return null;
  }

  ChannelConfigEntry? _parseChannel(int number, String? reply) {
    if (reply == null) return null;
    final parts = reply.split('|');
    if (parts.length < 13) return null;
    return ChannelConfigEntry(
      number: number,
      valors: [for (var i = 0; i < 4; i++) int.tryParse(parts[i]) ?? 0],
      transicions: [
        for (var i = 0; i < 4; i++)
          TransicioConfigEntry(
            tipus: int.tryParse(parts[4 + i * 2]) ?? 0,
            saltPercent: int.tryParse(parts[4 + i * 2 + 1]) ?? 0,
          ),
      ],
      name: parts.sublist(12).join('|'),
    );
  }

  /// Fetches this page's up to 12 channels' full V71 state, sequentially
  /// (one round trip in flight at a time — same reasoning as
  /// `ExportImportSection`'s channel loop: safe given the wire protocol has
  /// no request/response correlation). A page load is a one-off action
  /// (button tap), not a hot loop, so this being a bit slow is an
  /// acceptable trade — the chart itself doesn't re-fetch on every poll
  /// tick, only when the page changes.
  Future<void> _loadPage() async {
    setState(() => _loadingPage = true);
    try {
      final totalChannels = (await _readValue(widget.channelCountVIndex))
          ?.round();
      if (totalChannels != null && totalChannels > 0) {
        _totalChannels = totalChannels;
      }
      final firstChannel = _page * _pageSize + 1;
      final lastChannel = ((_totalChannels ?? firstChannel + _pageSize - 1))
          .clamp(0, firstChannel + _pageSize - 1);
      final next = List<ChannelConfigEntry?>.filled(_pageSize, null);
      for (var slot = 0; slot < _pageSize; slot++) {
        final channel = firstChannel + slot;
        if (channel > lastChannel) break;
        next[slot] = _parseChannel(
          channel,
          await _channelRoundTrip('$channel'),
        );
      }
      if (!mounted) return;
      setState(() {
        _pageChannels = next;
        _visible = List.filled(_pageSize, true);
      });
    } finally {
      if (mounted) setState(() => _loadingPage = false);
    }
  }

  void _changePage(int delta) {
    final totalChannels = _totalChannels;
    if (totalChannels == null) return;
    final totalPages = (totalChannels / _pageSize).ceil().clamp(1, 1 << 30);
    final next = (_page + delta).clamp(0, totalPages - 1);
    if (next == _page) return;
    setState(() => _page = next);
    _loadPage();
  }

  List<double> _periodBoundaries(int periodCount, List<double> periodes) {
    final boundaries = <double>[0];
    final total = periodCount > 0 && periodes[periodCount - 1] > 0
        ? periodes[periodCount - 1]
        : 1.0;
    for (var i = 0; i < periodCount; i++) {
      boundaries.add((periodes[i] / total).clamp(0.0, 1.0));
    }
    return boundaries;
  }

  List<Offset> _buildChannelPoints(
    ChannelConfigEntry entry,
    int sceneCount,
    List<double> boundaries,
  ) {
    final points = <Offset>[];
    final periodCount = sceneCount * 2;
    for (var i = 0; i < periodCount; i++) {
      final segStart = boundaries[i];
      final segEnd = boundaries[i + 1];
      final escenaIndex = i ~/ 2;
      if (i.isEven) {
        final v = entry.valors[escenaIndex] / 255.0;
        points.add(Offset(segStart, v));
        points.add(Offset(segEnd, v));
      } else {
        final v0 = entry.valors[escenaIndex];
        final v1 = entry.valors[(escenaIndex + 1) % sceneCount];
        final tr = entry.transicions[escenaIndex];
        const samples = 24;
        for (var s = 0; s <= samples; s++) {
          final tPerMille = (1000 * s / samples).round();
          final value = interpolarCanal(
            v0,
            v1,
            tPerMille,
            tr.tipus,
            tr.saltPercent,
          );
          final localT = s / samples;
          points.add(Offset(segStart + (segEnd - segStart) * localT, value / 255.0));
        }
      }
    }
    return points;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isPlaying = ref.watch(appStateProvider.select((s) => s.isPlaying));
    final isPaused = ref.watch(appStateProvider.select((s) => s.isPaused));
    final currentTime =
        ref.watch(appStateProvider.select((s) => s.currentTime)) ?? 0;
    final totalTime =
        ref.watch(appStateProvider.select((s) => s.totalTime)) ?? 0;
    final sceneCount =
        (ref.watch(appStateProvider.select((s) => s.activeScenesCount)) ?? 4)
            .clamp(1, 4);
    final periodes = [
      for (var i = 0; i < 8; i++)
        ref.watch(appStateProvider.select((s) => s.periodDuration(i))) ?? 0,
    ];

    final periodCount = sceneCount * 2;
    final boundaries = _periodBoundaries(periodCount, periodes);
    final boundaryLabels = [
      '0s',
      for (var i = 0; i < periodCount; i++) '${periodes[i].round()}s',
    ];

    final curves = [
      for (var slot = 0; slot < _pageSize; slot++)
        if (_pageChannels[slot] != null)
          ChannelCurve(
            color: _channelColors[slot],
            points: _buildChannelPoints(
              _pageChannels[slot]!,
              sceneCount,
              boundaries,
            ),
            visible: _visible[slot],
          ),
    ];

    final livePosition = isPlaying && totalTime > 0
        ? (currentTime / totalTime).clamp(0.0, 1.0)
        : null;

    final firstChannel = _page * _pageSize + 1;
    final lastChannel = firstChannel +
        _pageChannels.where((c) => c != null).length -
        1;
    final totalChannels = _totalChannels;
    final totalPages = totalChannels != null
        ? (totalChannels / _pageSize).ceil()
        : 1;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) Navigator.of(context).pop();
      },
      child: Scaffold(
        backgroundColor: scheme.surface,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Column(
              children: [
                _TopBar(
                  isPlaying: isPlaying,
                  isPaused: isPaused,
                  currentTime: currentTime,
                  totalTime: totalTime,
                  onPlayPause: () {
                    final notifier = ref.read(appStateProvider.notifier);
                    if (!isPlaying) {
                      notifier.setPlaying(true);
                    } else if (isPaused) {
                      notifier.setPaused(false);
                    } else {
                      notifier.setPaused(true);
                    }
                  },
                  onStop: () =>
                      ref.read(appStateProvider.notifier).setPlaying(false),
                  onBack: () => Navigator.of(context).pop(),
                  rangeLabel: totalChannels == null
                      ? '$firstChannel-$lastChannel'
                      : '$firstChannel-${lastChannel.clamp(firstChannel, totalChannels)}',
                  canGoBack: _page > 0,
                  canGoForward: _page < totalPages - 1,
                  onPrevPage: () => _changePage(-1),
                  onNextPage: () => _changePage(1),
                  loading: _loadingPage,
                ),
                const SizedBox(height: 4),
                Expanded(
                  child: CustomPaint(
                    painter: CycleChartPainter(
                      curves: curves,
                      periodBoundaries: boundaries,
                      boundaryLabels: boundaryLabels,
                      livePosition: livePosition,
                      onSurfaceColor: scheme.onSurface,
                      gridColor: scheme.onSurfaceVariant,
                    ),
                    child: const SizedBox.expand(),
                  ),
                ),
                const SizedBox(height: 4),
                SizedBox(
                  // 2 rows now (6 columns, see ChannelLegend), not 3 — 56
                  // still clipped the 2nd row on real hardware (its actual
                  // row height, from crossAxisCount+childAspectRatio, came
                  // out a bit taller than that), 68 has margin to spare.
                  height: 68,
                  child: ChannelLegend(
                    entries: [
                      for (var slot = 0; slot < _pageSize; slot++)
                        LegendEntry(
                          color: _channelColors[slot],
                          label: _pageChannels[slot] == null
                              ? ''
                              : (_pageChannels[slot]!.name.isEmpty
                                  ? 'Canal ${_pageChannels[slot]!.number}'
                                  : _pageChannels[slot]!.name),
                          visible: _visible[slot],
                        ),
                    ],
                    onToggle: (slot) {
                      if (_pageChannels[slot] == null) return;
                      setState(() => _visible[slot] = !_visible[slot]);
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.isPlaying,
    required this.isPaused,
    required this.currentTime,
    required this.totalTime,
    required this.onPlayPause,
    required this.onStop,
    required this.onBack,
    required this.rangeLabel,
    required this.canGoBack,
    required this.canGoForward,
    required this.onPrevPage,
    required this.onNextPage,
    required this.loading,
  });

  final bool isPlaying;
  final bool isPaused;

  /// Elapsed/total cycle time (s) — same V14/V15 the Cycle Programming
  /// screen already shows, displayed the same way ("N\" / M\"").
  final double currentTime;
  final double totalTime;

  final VoidCallback onPlayPause;
  final VoidCallback onStop;
  final VoidCallback onBack;
  final String rangeLabel;
  final bool canGoBack;
  final bool canGoForward;
  final VoidCallback onPrevPage;
  final VoidCallback onNextPage;
  final bool loading;

  String get _statusText {
    if (!isPlaying) return 'Aturat';
    return isPaused ? 'Pausa' : 'Reproduint';
  }

  @override
  Widget build(BuildContext context) {
    final showPlay = !isPlaying || isPaused;
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: onBack,
          tooltip: 'Enrere',
          visualDensity: VisualDensity.compact,
        ),
        const SizedBox(width: 16),
        _CircleIconButton(
          icon: showPlay ? Icons.play_arrow : Icons.pause,
          onPressed: onPlayPause,
          tooltip: showPlay ? 'Play' : 'Pausa',
          backgroundColor: scheme.primaryContainer,
          foregroundColor: scheme.onPrimaryContainer,
        ),
        const SizedBox(width: 6),
        _CircleIconButton(
          icon: Icons.stop,
          onPressed: onStop,
          tooltip: 'Stop',
          backgroundColor: scheme.errorContainer,
          foregroundColor: scheme.onErrorContainer,
        ),
        Expanded(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Simulació — $_statusText',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              ),
              if (loading) ...[
                const SizedBox(width: 8),
                const SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: 8),
        Container(
          width: 60,
          height: 28,
          decoration: BoxDecoration(
            color: scheme.primary,
            borderRadius: BorderRadius.circular(6),
          ),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              '${currentTime.round()}" / ${totalTime.round()}"',
              maxLines: 1,
              style: TextStyle(
                color: scheme.onPrimary,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ),
        ),
        const SizedBox(width: 4),
        _CircleIconButton(
          icon: Icons.arrow_back_ios_new,
          iconSize: 14,
          onPressed: canGoBack ? onPrevPage : null,
          tooltip: 'Grup de canals anterior',
          backgroundColor: scheme.secondaryContainer,
          foregroundColor: scheme.onSecondaryContainer,
        ),
        SizedBox(
          width: 56,
          child: Text(
            rangeLabel,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
          ),
        ),
        _CircleIconButton(
          icon: Icons.arrow_forward_ios,
          iconSize: 14,
          onPressed: canGoForward ? onNextPage : null,
          tooltip: 'Grup de canals següent',
          backgroundColor: scheme.secondaryContainer,
          foregroundColor: scheme.onSecondaryContainer,
        ),
      ],
    );
  }
}

/// A circular-background icon button — Play/Pausa, Stop and the page
/// arrows all get this treatment so they stand out against the plain back
/// arrow, which stays a bare [IconButton] (it's not a chart control).
class _CircleIconButton extends StatelessWidget {
  const _CircleIconButton({
    required this.icon,
    required this.onPressed,
    required this.tooltip,
    required this.backgroundColor,
    required this.foregroundColor,
    this.iconSize,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String tooltip;
  final Color backgroundColor;
  final Color foregroundColor;
  final double? iconSize;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon, size: iconSize),
      onPressed: onPressed,
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      style: IconButton.styleFrom(
        shape: const CircleBorder(),
        backgroundColor: backgroundColor,
        foregroundColor: foregroundColor,
        // Flat colors don't dim themselves when onPressed is null (the
        // page-nav arrows at the first/last group) — needs explicit
        // disabled colors or a disabled button would look identical to an
        // enabled one, just unresponsive.
        disabledBackgroundColor: backgroundColor.withValues(alpha: 0.3),
        disabledForegroundColor: foregroundColor.withValues(alpha: 0.38),
      ),
    );
  }
}
