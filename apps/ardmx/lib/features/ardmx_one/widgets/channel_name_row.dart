import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/protocol/virtuino_update.dart';
import '../../../state/app_state.dart';
import '../../../state/providers.dart';

/// Editable name (V65-V67, up to 15 characters) for each of the 3 currently
/// selected DMX channels — sits directly below [ChannelNumberBar], one name
/// field per slot, lined up with its slider/number above via the same
/// horizontal padding.
///
/// Unlike the channel *value* (which polls continuously — see
/// [ArdmxOneScreen._poll]), a channel's *name* only changes when the app
/// explicitly writes it or when the selected channel group changes (the
/// arrows in [ChannelNumberBar]) — so each slot re-requests its name only
/// when [AppState.channelXNumber] changes, not on a timer, to avoid
/// clobbering in-progress typing with a stale poll reply.
class ChannelNameRow extends StatelessWidget {
  const ChannelNameRow({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Theme.of(context).colorScheme.primary,
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 10),
      child: const Row(
        children: [
          Expanded(child: _ChannelNameField(slot: 0)),
          SizedBox(width: 8),
          Expanded(child: _ChannelNameField(slot: 1)),
          SizedBox(width: 8),
          Expanded(child: _ChannelNameField(slot: 2)),
        ],
      ),
    );
  }
}

class _ChannelNameField extends ConsumerStatefulWidget {
  const _ChannelNameField({required this.slot});

  /// 0, 1 or 2 — position within the 3 currently selected channels, maps to
  /// wire index 65+slot and to `AppState.channelXNumber`.
  final int slot;

  @override
  ConsumerState<_ChannelNameField> createState() => _ChannelNameFieldState();
}

class _ChannelNameFieldState extends ConsumerState<_ChannelNameField> {
  static const _vIndexBase = 65;

  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  StreamSubscription<VirtuinoUpdate>? _subscription;

  int get _vIndex => _vIndexBase + widget.slot;

  @override
  void initState() {
    super.initState();
    _subscription = ref.read(protocolProvider).updates.listen((update) {
      // Ignore replies that arrive while the user is actively editing this
      // field, so a stale/echo reply never overwrites what they're typing.
      if (_focusNode.hasFocus) return;
      if (update is VirtuinoTUpdate && update.index == _vIndex) {
        _controller.text = update.text;
      }
    });
    _requestName();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _requestName() => ref.read(protocolProvider).requestT(_vIndex);

  void _submit(String text) =>
      ref.read(protocolProvider).writeText(_vIndex, text);

  int? _channelNumberOf(AppState state) => switch (widget.slot) {
    0 => state.channel1Number,
    1 => state.channel2Number,
    _ => state.channel3Number,
  };

  @override
  Widget build(BuildContext context) {
    // Re-request this slot's name whenever the channel it points to changes
    // (the user moved to a different group of 3 — see ChannelNumberBar's
    // arrows), not on a timer.
    ref.listen(appStateProvider, (previous, next) {
      if (previous != null &&
          _channelNumberOf(previous) != _channelNumberOf(next)) {
        _requestName();
      }
    });

    final onPrimary = Theme.of(context).colorScheme.onPrimary;
    return TextField(
      controller: _controller,
      focusNode: _focusNode,
      textAlign: TextAlign.center,
      maxLength: 15,
      style: TextStyle(color: onPrimary, fontSize: 14),
      decoration: InputDecoration(
        isDense: true,
        counterText: '',
        border: const OutlineInputBorder(),
        filled: true,
        fillColor: onPrimary.withValues(alpha: 0.14),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 8,
          vertical: 6,
        ),
      ),
      onSubmitted: _submit,
      onTapOutside: (_) {
        FocusManager.instance.primaryFocus?.unfocus();
        _submit(_controller.text);
      },
    );
  }
}
