import '../core/constants/v_map.dart';

/// The full remote-controllable state of the Arduino, mirroring the wire
/// protocol 1:1: the raw `V[0..59]` array plus the three text pins.
///
/// Modeled as a flat array rather than per-screen DTOs because several
/// screens share the exact same V-indices (e.g. Scene/Channels and the RGB
/// Wheel both read/write V1-V3) — a screen-shaped model would risk the two
/// falling out of sync. Named getters below provide readable access without
/// duplicating storage.
class AppState {
  const AppState({required this.v, this.t61, this.t62, this.t63});

  factory AppState.initial() => AppState(v: List<double?>.filled(60, null));

  /// Raw V[0..59] array. `null` means "not yet received from the Arduino".
  final List<double?> v;
  final String? t61;
  final String? t62;
  final String? t63;

  double? valueAt(int index) => v[index];
  int? intAt(int index) => v[index]?.round();

  int? get selectedScreen => intAt(VIndex.activeScreen);
  int? get mainSelector => intAt(VIndex.mainSelector);
  int? get activeScene => intAt(VIndex.activeScene);
  int? get activeScenesCount => intAt(VIndex.activeScenesCount);
  int? get cycleState => intAt(VIndex.cycleState);
  int? get songNumber => intAt(VIndex.songNumber);
  int? get volume => intAt(VIndex.volume);
  bool get isPlaying => intAt(VIndex.playStop) == 1;
  bool get isPaused => intAt(VIndex.pause) == 1;
  double? get currentTime => v[VIndex.currentTime];
  double? get totalTime => v[VIndex.totalTime];

  double? get channel1Value => v[VIndex.channel1Value];
  double? get channel2Value => v[VIndex.channel2Value];
  double? get channel3Value => v[VIndex.channel3Value];
  int? get channel1Number => intAt(VIndex.channel1Number);
  int? get channel2Number => intAt(VIndex.channel2Number);
  int? get channel3Number => intAt(VIndex.channel3Number);

  int? get transitionModeChannel1 => intAt(VIndex.transitionModeChannel1);
  int? get transitionModeChannel2 => intAt(VIndex.transitionModeChannel2);
  int? get transitionModeChannel3 => intAt(VIndex.transitionModeChannel3);

  int? get maxChannels => intAt(VIndex.maxChannels);
  int? get activeChannelsCount => intAt(VIndex.activeChannelsCount);

  /// Duration (seconds) of cycle period [periodOffset] (0..7), see
  /// [VIndex.periodDuration].
  double? periodDuration(int periodOffset) =>
      v[VIndex.periodDuration(periodOffset)];

  AppState copyWithV(int index, double value) {
    final newV = List<double?>.of(v);
    newV[index] = value;
    return AppState(v: newV, t61: t61, t62: t62, t63: t63);
  }

  AppState copyWithT(int index, String text) {
    switch (index) {
      case TIndex.playbackStatus:
        return AppState(v: v, t61: text, t62: t62, t63: t63);
      case TIndex.firmwareVersion:
        return AppState(v: v, t61: t61, t62: text, t63: t63);
      case TIndex.freeText:
        return AppState(v: v, t61: t61, t62: t62, t63: text);
      default:
        return this;
    }
  }
}
