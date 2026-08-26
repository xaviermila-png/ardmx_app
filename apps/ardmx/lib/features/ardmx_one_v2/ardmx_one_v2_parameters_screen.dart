import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/v_map.dart';
import '../../core/protocol/virtuino_update.dart';
import '../../routing/app_router.dart';
import '../../state/providers.dart';
import '../../widgets/app_scaffold.dart';

/// Parameters screen for the ARDMX One v2 tree (V50=4): pessebre name and
/// descripció (V68/V69, compact fields pinned at the top, same as the
/// ARDMX EVO tree's own [ArdmxEvoParametersScreen]) and number of active
/// scenes (V18, also shared with EVO). No "Cançó a reproduir" section (no
/// DFPlayer on this hardware). "Canals gestionables" reuses ARDMX One v1's
/// own V08 mechanism verbatim (see `_NumeroCanalsSection` below) rather
/// than EVO's V39/V40 — V08 already works and there was no reason to move
/// it. The Bluetooth name, factory reset and export/import live one level
/// deeper in "Configuració del sistema" (reached via its own button).
class ArdmxOneV2ParametersScreen extends ConsumerStatefulWidget {
  const ArdmxOneV2ParametersScreen({super.key});

  @override
  ConsumerState<ArdmxOneV2ParametersScreen> createState() =>
      _ArdmxOneV2ParametersScreenState();
}

class _ArdmxOneV2ParametersScreenState
    extends ConsumerState<ArdmxOneV2ParametersScreen> {
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
    ref.read(protocolProvider).requestAll([VIndex.activeScenesCount]);
  }

  @override
  Widget build(BuildContext context) {
    final scenesCount = ref.watch(
      appStateProvider.select((s) => s.activeScenesCount),
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
                        showSelectedIcon: false,
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
                  const _Section(
                    title: 'Canals gestionables',
                    child: _NumeroCanalsField(),
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
                  heroTag: 'ardmxOneV2SystemConfig',
                  onPressed: () => Navigator.of(
                    context,
                  ).pushNamed(AppRoutes.ardmxOneV2SystemConfig),
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

/// V08 — active channel count, ARDMX One's own mechanism since firmware v1
/// (see `ardmx_one_config_screen.dart`'s identical field, unchanged there),
/// reused verbatim rather than adopting EVO's V39/V40.
class _NumeroCanalsField extends ConsumerStatefulWidget {
  const _NumeroCanalsField();

  @override
  ConsumerState<_NumeroCanalsField> createState() =>
      _NumeroCanalsFieldState();
}

class _NumeroCanalsFieldState extends ConsumerState<_NumeroCanalsField> {
  static const _numeroCanalsVIndex = 8;

  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  StreamSubscription<VirtuinoUpdate>? _subscription;
  String? _error;

  @override
  void initState() {
    super.initState();
    _subscription = ref.read(protocolProvider).updates.listen((update) {
      if (update is VirtuinoVUpdate && update.index == _numeroCanalsVIndex) {
        setState(() {
          _controller.text = update.value.round().toString();
          _error = null;
        });
      }
    });
    // Commits on losing focus for ANY reason, not just onTapOutside below —
    // jumping directly from "Descripció" (above) straight into this field
    // does NOT fire either field's onTapOutside: Flutter groups sibling
    // TextFields into the same implicit TextFieldTapRegion, so a tap
    // landing on one doesn't count as "outside" the other.
    _focusNode.addListener(() {
      if (!_focusNode.hasFocus) _submit(_controller.text);
    });
    ref.read(protocolProvider).requestV(_numeroCanalsVIndex);
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  int? _validate(String raw) {
    final value = int.tryParse(raw);
    if (value == null || value < 1 || value > 512 || value % 3 != 0) {
      setState(() {
        _error = 'Ha de ser un múltiple de 3, entre 1 i 510 (p.ex. 48, 51, 54...)';
      });
      return null;
    }
    setState(() => _error = null);
    return value;
  }

  void _onChanged(String raw) => _validate(raw);

  void _submit(String raw) {
    final value = _validate(raw);
    if (value != null) {
      ref.read(protocolProvider).writeV(_numeroCanalsVIndex, value);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 150,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            border: Border.all(
              color: Theme.of(context).colorScheme.primary,
              width: 2.5,
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(width: 20),
              Flexible(
                child: TextField(
                  controller: _controller,
                  focusNode: _focusNode,
                  textAlign: TextAlign.center,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                  onChanged: _onChanged,
                  onSubmitted: _submit,
                  onTapOutside: (_) {
                    FocusManager.instance.primaryFocus?.unfocus();
                    _submit(_controller.text);
                  },
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.edit,
                size: 16,
                color: Theme.of(context).colorScheme.primary,
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Múltiple de 3, màxim 510',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12),
        ),
        if (_error != null) ...[
          const SizedBox(height: 4),
          Text(
            _error!,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.error,
            ),
          ),
        ],
      ],
    );
  }
}

/// Free-text field backed by a single wire text index (V68 nom del
/// pessebre, V69 descripció) — same "confirm on losing focus" pattern used
/// throughout this app.
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
  final _focusNode = FocusNode();
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
    // Commits on losing focus for ANY reason, not just onTapOutside below —
    // jumping directly to a sibling field (Descripció, or Canals
    // gestionables below) does NOT fire onTapOutside: Flutter groups
    // sibling TextFields into the same implicit TextFieldTapRegion, so a
    // tap landing on one doesn't count as "outside" the other.
    _focusNode.addListener(() {
      if (!_focusNode.hasFocus) _submit(_controller.text);
    });
    ref.read(protocolProvider).requestT(widget.vIndex);
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _submit(String text) =>
      ref.read(protocolProvider).writeText(widget.vIndex, text);

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
            focusNode: _focusNode,
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
