/// Named indices into the Arduino's `V[0..59]` float array and its three
/// text pins T61-T63. This is the single source of truth for the wire
/// protocol shape — nothing else in the app should use raw index literals.
///
/// The Arduino sketch (V4.15) is frozen: these indices and their meanings
/// must never change.
class VIndex {
  const VIndex._();

  static const int songNumber = 0;
  static const int channel1Value = 1;
  static const int channel2Value = 2;
  static const int channel3Value = 3;
  static const int channel1Number = 4;
  static const int channel2Number = 5;
  static const int channel3Number = 6;
  static const int channelGroupOrder = 7;
  static const int activeScene = 9;
  static const int cycleState = 10;
  static const int mainSelector = 11;
  static const int playStop = 12;
  static const int pause = 13;
  static const int currentTime = 14;
  static const int totalTime = 15;
  static const int volume = 16;
  static const int activeScenesCount = 18;

  /// Durations (seconds) of the 8 cycle periods: Scene1, Trans1-2, Scene2,
  /// Trans2-3, Scene3, Trans3-4, Scene4, Trans4-1. V21..V28 inclusive.
  static const int periodDurationsStart = 21;
  static const int periodDurationsCount = 8;

  static const int transitionModeChannel1 = 31;
  static const int transitionModeChannel2 = 32;
  static const int transitionModeChannel3 = 33;
  static const int sceneChangeOrder = 35;
  static const int maxChannels = 39;
  static const int activeChannelsCount = 40;
  static const int resetConfirm1 = 41;
  static const int resetConfirm2 = 42;
  static const int activeScreen = 50;

  /// V-index this array position corresponds to, for the 8 period durations.
  static int periodDuration(int periodOffset) =>
      periodDurationsStart + periodOffset;
}

class TIndex {
  const TIndex._();

  static const int playbackStatus = 61;
  static const int firmwareVersion = 62;
  static const int freeText = 63;
}

/// Screens the app can show, mapped to the V[50] value that must be written
/// when navigating to them (this actively triggers Arduino-side behavior,
/// e.g. `Escenes()`/`Cicle()` — it is not a passive mirror).
enum AppScreen {
  initial(0),
  cycleProgramming(1),
  mainMenu(3),
  parameters(4),
  sceneChannels(5),
  rgbWheel(8),
  credits(9);

  const AppScreen(this.vValue);
  final int vValue;
}

/// Positions of the main rotary dial (V[11]).
enum MainSelectorMode {
  automatic(1),
  manual(2),
  scene1(3),
  scene2(4),
  scene3(5),
  scene4(6),
  configuration(7);

  const MainSelectorMode(this.vValue);
  final int vValue;
}

/// Per-channel transition mode (V[31..33]).
enum TransitionMode {
  gradual(0),
  initial(1),
  finalMode(2);

  const TransitionMode(this.vValue);
  final int vValue;
}
