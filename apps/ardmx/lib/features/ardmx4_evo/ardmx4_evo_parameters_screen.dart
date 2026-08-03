import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/v_map.dart';
import '../../core/protocol/virtuino_update.dart';
import '../../routing/app_router.dart';
import '../../state/providers.dart';
import '../../widgets/app_scaffold.dart';

/// Parameters screen for the ARDMX4 EVO tree (V50=4): pessebre name and
/// descripció (V68/V69, compact fields pinned at the top), number of active
/// scenes, song to play, and number of manageable channels — same V0/V18/
/// V39/V40 protocol as the Mega's own [ParametersScreen]. The Bluetooth
/// name, factory reset and export/import live one level deeper in
/// "Configuració del sistema" (reached via its own button).
class Ardmx4EvoParametersScreen extends ConsumerStatefulWidget {
  const Ardmx4EvoParametersScreen({super.key});

  @override
  ConsumerState<Ardmx4EvoParametersScreen> createState() =>
      _Ardmx4EvoParametersScreenState();
}

class _Ardmx4EvoParametersScreenState
    extends ConsumerState<Ardmx4EvoParametersScreen> {
  static const _pollInterval = Duration(milliseconds: 400);

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
      VIndex.activeScenesCount,
      VIndex.songNumber,
      VIndex.activeChannelsCount,
      VIndex.maxChannels,
    ]);
  }

  Future<void> _editChannelsCount(int current, int max) async {
    final controller = TextEditingController(text: '$current');
    String? error;

    final result = await showDialog<int>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            void submit() {
              final parsed = int.tryParse(controller.text);
              if (parsed == null || parsed < 0 || parsed > max) {
                setDialogState(() => error = 'Ha de ser entre 0 i $max');
                return;
              }
              if (parsed % 3 != 0) {
                setDialogState(() => error = 'Ha de ser múltiple de 3');
                return;
              }
              Navigator.of(context).pop(parsed);
            }

            return AlertDialog(
              title: const Text('Canals gestionables'),
              content: TextField(
                controller: controller,
                keyboardType: TextInputType.number,
                autofocus: true,
                decoration: InputDecoration(
                  errorText: error,
                  helperText: 'Múltiple de 3, entre 0 i $max',
                ),
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
      ref.read(appStateProvider.notifier).setActiveChannelsCount(result);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scenesCount = ref.watch(
      appStateProvider.select((s) => s.activeScenesCount),
    );
    final songNumber = ref.watch(appStateProvider.select((s) => s.songNumber));
    final channelsCount = ref.watch(
      appStateProvider.select((s) => s.activeChannelsCount),
    );
    final maxChannels = ref.watch(
      appStateProvider.select((s) => s.maxChannels),
    );

    return AppScaffold(
      title: 'Paràmetres',
      onBack: () => Navigator.of(context).pop(),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _CompactTextField(
                    title: 'Nom del pessebre',
                    vIndex: 68,
                    maxLength: 32,
                  ),
                  const SizedBox(height: 6),
                  const _CompactTextField(
                    title: 'Descripció',
                    vIndex: 69,
                    maxLength: 128,
                  ),
                  const SizedBox(height: 8),
                  _Section(
                    title: "Nombre d'escenes",
                    child: SizedBox(
                      width: double.infinity,
                      child: SegmentedButton<int>(
                        segments: [
                          for (var n = 1; n <= 4; n++)
                            ButtonSegment(value: n, label: Text('$n')),
                        ],
                        selected: scenesCount != null ? {scenesCount} : const {},
                        emptySelectionAllowed: true,
                        onSelectionChanged: (selection) => ref
                            .read(appStateProvider.notifier)
                            .setActiveScenesCount(selection.first),
                        style: SegmentedButton.styleFrom(
                          selectedBackgroundColor: Theme.of(
                            context,
                          ).colorScheme.primaryContainer,
                          selectedForegroundColor: Theme.of(
                            context,
                          ).colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  _Section(
                    title: 'Cançó a reproduir',
                    child: SizedBox(
                      width: double.infinity,
                      child: SegmentedButton<int>(
                        segments: [
                          const ButtonSegment(value: 0, label: Text('Off')),
                          for (var n = 1; n <= 4; n++)
                            ButtonSegment(value: n, label: Text('$n')),
                        ],
                        selected: songNumber != null ? {songNumber} : const {},
                        emptySelectionAllowed: true,
                        onSelectionChanged: (selection) => ref
                            .read(appStateProvider.notifier)
                            .setSongNumber(selection.first),
                        style: SegmentedButton.styleFrom(
                          selectedBackgroundColor: Theme.of(
                            context,
                          ).colorScheme.primaryContainer,
                          selectedForegroundColor: Theme.of(
                            context,
                          ).colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  _Section(
                    title: 'Canals gestionables',
                    child: Column(
                      children: [
                        Text(
                          'Màxim nombre de canals: ${maxChannels ?? 510}',
                          style: const TextStyle(fontSize: 14),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          '(ha de ser múltiple de 3)',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 13),
                        ),
                        const SizedBox(height: 6),
                        Center(
                          child: InkWell(
                            borderRadius: BorderRadius.circular(8),
                            onTap: () => _editChannelsCount(
                              channelsCount ?? 0,
                              maxChannels ?? 510,
                            ),
                            child: Container(
                              width: 90,
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.primary,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                '${channelsCount ?? '—'}',
                                style: TextStyle(
                                  fontSize: 26,
                                  fontWeight: FontWeight.bold,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onPrimary,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                FloatingActionButton(
                  heroTag: 'ardmx4EvoSystemConfig',
                  onPressed: () => Navigator.of(
                    context,
                  ).pushNamed(AppRoutes.ardmx4EvoSystemConfig),
                  tooltip: 'Configuració del sistema',
                  child: const Icon(Icons.build),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Free-text field backed by a single wire text index (V68 nom del
/// pessebre, V69 descripció) — same "confirm on losing focus" pattern as
/// ARDMX One's own `_EditableTextSection`. Sized compactly (small text,
/// single/double line) to fit pinned at the top of this screen alongside
/// the day-to-day controls below.
class _CompactTextField extends ConsumerStatefulWidget {
  const _CompactTextField({
    required this.title,
    required this.vIndex,
    required this.maxLength,
  });

  final String title;
  final int vIndex;
  final int maxLength;

  @override
  ConsumerState<_CompactTextField> createState() => _CompactTextFieldState();
}

class _CompactTextFieldState extends ConsumerState<_CompactTextField> {
  final _controller = TextEditingController();
  StreamSubscription<VirtuinoUpdate>? _subscription;
  int _length = 0;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      if (_controller.text.length != _length) {
        setState(() => _length = _controller.text.length);
      }
    });
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
    // Same look as _Section, but built as one piece (not wrapped in it) so
    // the live character counter can sit at the top-right of the title row
    // instead of the TextField's own default bottom-right position — the
    // user found the default position wasted the space recovered by
    // compacting these fields.
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
          Stack(
            alignment: Alignment.center,
            children: [
              Text(
                widget.title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Align(
                alignment: Alignment.topRight,
                child: Text(
                  '$_length/${widget.maxLength}',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _controller,
            textAlign: TextAlign.left,
            style: const TextStyle(fontSize: 16),
            minLines: widget.maxLength > 40 ? 4 : 1,
            maxLines: widget.maxLength > 40 ? 4 : 1,
            textInputAction: TextInputAction.done,
            maxLength: widget.maxLength,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              isDense: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              counterText: '',
            ),
            onSubmitted: _submit,
            onTapOutside: (_) {
              FocusManager.instance.primaryFocus?.unfocus();
              _submit(_controller.text);
            },
          ),
        ],
      ),
    );
  }
}

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
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          child,
        ],
      ),
    );
  }
}
