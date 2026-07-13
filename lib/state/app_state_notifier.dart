import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/bluetooth/bluetooth_connection_state.dart';
import '../core/constants/v_map.dart';
import '../core/protocol/virtuino_update.dart';
import 'app_state.dart';
import 'providers.dart';

/// Applies incoming Arduino updates to [AppState] and exposes
/// intention-revealing write methods so the rest of the app never touches
/// raw V-indices directly.
///
/// Writes are applied to local state optimistically (before the Arduino's
/// own echo arrives) so sliders and toggles feel responsive; the eventual
/// echo is a harmless overwrite with the same value.
class AppStateNotifier extends Notifier<AppState> {
  StreamSubscription<VirtuinoUpdate>? _subscription;

  // The wire protocol has no request/response correlation (see class doc on
  // VirtuinoProtocol) — every incoming frame is applied as a broadcast
  // update regardless of which request (if any) it answers. That means a
  // poll request sent just *before* a local write can have its reply arrive
  // just *after* it, carrying the pre-write value and visibly clobbering
  // our fresh optimistic one for a frame (confirmed on hardware: dragging a
  // channel slider would flash back to the old value for a few hundred ms
  // before the next poll cycle corrected it). Track our own recent writes
  // and ignore a contradicting echo for a short window, long enough to
  // absorb one stale in-flight poll reply without blocking real updates
  // (e.g. a scene's own live color animation) for long.
  static const _echoGuard = Duration(milliseconds: 600);
  final Map<int, ({double value, DateTime at})> _recentWrites = {};

  @override
  AppState build() {
    final protocol = ref.watch(protocolProvider);
    _subscription = protocol.updates.listen(_onUpdate);
    ref.onDispose(() => _subscription?.cancel());

    // Text pins (e.g. T62, the firmware version) only reply when explicitly
    // asked — pull a snapshot right after every fresh connection.
    ref.listen(bluetoothConnectionServiceProvider, (previous, next) {
      final wasConnected =
          previous?.status == BluetoothConnectionStatus.connected;
      final isConnected = next.status == BluetoothConnectionStatus.connected;
      if (!wasConnected && isConnected) {
        requestInitialSnapshot();
      }
      if (wasConnected && !isConnected) {
        // The firmware version belongs to whichever device we were just
        // talking to — stale once disconnected, so don't keep showing it.
        state = AppState(v: state.v, t61: state.t61, t63: state.t63);
      }
    });

    return AppState.initial();
  }

  void _onUpdate(VirtuinoUpdate update) {
    switch (update) {
      case VirtuinoVUpdate(:final index, :final value):
        if (index >= 0 && index < state.v.length) {
          final recent = _recentWrites[index];
          if (recent != null &&
              value != recent.value &&
              DateTime.now().difference(recent.at) < _echoGuard) {
            break;
          }
          state = state.copyWithV(index, value);
        }
      case VirtuinoTUpdate(:final index, :final text):
        state = state.copyWithT(index, text);
    }
  }

  void _writeAndApply(int index, double value) {
    ref.read(protocolProvider).writeV(index, value);
    _recentWrites[index] = (value: value, at: DateTime.now());
    state = state.copyWithV(index, value);
  }

  void _writeBatchAndApply(Map<int, double> values) {
    ref.read(protocolProvider).writeBatch(values);
    final now = DateTime.now();
    var next = state;
    for (final entry in values.entries) {
      _recentWrites[entry.key] = (value: entry.value, at: now);
      next = next.copyWithV(entry.key, entry.value);
    }
    state = next;
  }

  void setScreen(AppScreen screen) =>
      _writeAndApply(VIndex.activeScreen, screen.vValue.toDouble());

  void selectMainMode(MainSelectorMode mode) =>
      _writeAndApply(VIndex.mainSelector, mode.vValue.toDouble());

  void setVolume(int volume) =>
      _writeAndApply(VIndex.volume, volume.toDouble());

  void advanceChannelGroup(int direction) =>
      _writeAndApply(VIndex.channelGroupOrder, direction.toDouble());

  void changeScene(int direction) =>
      _writeAndApply(VIndex.sceneChangeOrder, direction.toDouble());

  /// Sets the 3 visible channel colors (R/G/B, 0-255) in a single batched
  /// write.
  void setChannelColors({
    required double channel1,
    required double channel2,
    required double channel3,
  }) => _writeBatchAndApply({
    VIndex.channel1Value: channel1,
    VIndex.channel2Value: channel2,
    VIndex.channel3Value: channel3,
  });

  void setTransitionModes({
    required TransitionMode channel1,
    required TransitionMode channel2,
    required TransitionMode channel3,
  }) => _writeBatchAndApply({
    VIndex.transitionModeChannel1: channel1.vValue.toDouble(),
    VIndex.transitionModeChannel2: channel2.vValue.toDouble(),
    VIndex.transitionModeChannel3: channel3.vValue.toDouble(),
  });

  void setPlaying(bool playing) =>
      _writeAndApply(VIndex.playStop, playing ? 1 : 0);

  void setPaused(bool paused) =>
      _writeAndApply(VIndex.pause, paused ? 1 : 0);

  void setSongNumber(int song) =>
      _writeAndApply(VIndex.songNumber, song.toDouble());

  void setActiveScenesCount(int count) =>
      _writeAndApply(VIndex.activeScenesCount, count.toDouble());

  void setActiveChannelsCount(int count) =>
      _writeAndApply(VIndex.activeChannelsCount, count.toDouble());

  void setPeriodDuration(int periodOffset, double seconds) =>
      _writeAndApply(VIndex.periodDuration(periodOffset), seconds);

  void requestInitialSnapshot() {
    final protocol = ref.read(protocolProvider);
    protocol.requestAll([
      VIndex.activeScreen,
      VIndex.mainSelector,
      VIndex.activeScene,
      VIndex.volume,
      VIndex.channel1Value,
      VIndex.channel2Value,
      VIndex.channel3Value,
    ]);
    protocol.requestT(TIndex.firmwareVersion);
  }
}
