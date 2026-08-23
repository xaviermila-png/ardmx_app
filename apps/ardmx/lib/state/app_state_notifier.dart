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

  /// Like [_writeAndApply], but deliberately skips the echo-guard: use this
  /// when the Arduino may legitimately recalculate and send back a
  /// *different* authoritative value in response to this exact write (e.g.
  /// clamping/re-deriving other cycle checkpoints). The normal echo-guard
  /// would otherwise mistake that genuine correction for a stale in-flight
  /// poll reply and discard it, permanently showing our own uncorrected
  /// guess until the next edit.
  void _writeAndApplyTrustEcho(int index, double value) {
    ref.read(protocolProvider).writeV(index, value);
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
      _writeAndApplyTrustEcho(VIndex.periodDuration(periodOffset), seconds);

  /// Arms/disarms the "Inicialitzar variables" reset (V41). Arming alone
  /// does nothing destructive — [confirmReset] is the actual trigger.
  void setResetArmed(bool armed) =>
      _writeAndApply(VIndex.resetConfirm1, armed ? 1 : 0);

  /// Actually triggers the variable reset. Deliberately sends **only** V42=1
  /// over the wire — V41 is left as whatever [setResetArmed] already set it
  /// to (1) and is never explicitly cleared from here.
  ///
  /// The firmware's trigger condition is `V41==1 && V42==1` evaluated on its
  /// own polling loop, not on either write individually. Originally this
  /// method also sent V41=0 in the same batch (to visibly snap the dial back
  /// to OFF) — but that meant two separate frames went out (V42=1, then
  /// V41=0), and depending on Bluetooth timing the firmware could process
  /// both before its loop ever saw them true *simultaneously*, so the reset
  /// silently never fired. Confirmed on real hardware (ARDMX EVO): the same
  /// user action would sometimes reset fine and sometimes hang forever with
  /// no observable cause, purely depending on which frame the firmware's
  /// loop happened to land between. Not writing V41=0 at all removes the
  /// race: V41 stays 1 (already fully processed well before this write is
  /// even sent) until the firmware's own reset code clears both V41 and V42
  /// to 0 once it completes — which is also the real completion signal the
  /// UI is waiting for.
  ///
  /// The dial still visibly snaps to OFF immediately: local state is updated
  /// optimistically for both indices without putting V41 on the wire. Uses
  /// the trust-echo write for V42 since the firmware's own V42=0 correction
  /// is expected to land soon after and must not be swallowed by the
  /// echo-guard (see [_writeAndApplyTrustEcho]).
  void confirmReset() {
    _writeAndApplyTrustEcho(VIndex.resetConfirm2, 1);
    state = state.copyWithV(VIndex.resetConfirm1, 0);
  }

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
