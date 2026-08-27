/// Named indices into the Arduino's `V[0..59]` float array and its three
/// text pins T61-T63, plus the handful of text-bulk indices (≥70) that
/// diverge per product (ARDMX4/One/EVO each give a different meaning to
/// indices in that range — see each product's own firmware `main.cpp` for
/// the exact V71/V72 payload format used there). This is the single source
/// of truth for the wire protocol shape — nothing else in the app should
/// use raw index literals.
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

  static const int sceneChangeOrder = 35;
  static const int maxChannels = 39;
  static const int activeChannelsCount = 40;
  static const int resetConfirm1 = 41;
  static const int resetConfirm2 = 42;
  static const int activeScreen = 50;

  /// Bulk query/assign of ONE channel's complete state — its 4 scene values,
  /// its own 4 transitions (type + salt%, per-channel, not shared with other
  /// channels), and its name — ARDMX One v2 and EVO only. Query `"N"`;
  /// assign `"N|v1|v2|v3|v4|t1|s1|t2|s2|t3|s3|t4|s4|nom"`
  /// (t=[TransitionType] index, s=0-100); reply (both) the same
  /// `"v1|v2|v3|v4|t1|s1|t2|s2|t3|s3|t4|s4|nom"` format. Writes are atomic —
  /// there is no partial-field update, the whole blob is always sent.
  static const int channelBulk4Scene = 71;

  /// Bulk query/assign of ONE event's complete state (0-9) — a one-shot
  /// sound (advertise) and/or a channel forced to 255 at a given moment of
  /// the cycle, for a given duration — ARDMX EVO only (see
  /// `handleEventBulk()`/`GestioEvents()` in ardmx4-evo-firmware's
  /// main.cpp). Query `"N"`; assign `"N|moment|durada|pista|canal"`
  /// (moment/durada in seconds, pista=0 or canal=0 meaning "not set");
  /// reply (both) the same `"moment|durada|pista|canal"` format. Same
  /// atomic-write shape as [channelBulk4Scene].
  static const int eventBulk = 77;

  /// Fires event N (0-9) immediately, ignoring its configured "moment" —
  /// the "Provar" button on the Events screen. Write-only, no query; reply
  /// is always `"OK"`.
  static const int eventTestTrigger = 78;

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

/// Type of a channel's own transition between two consecutive scenes (one
/// of V71's `t` fields) — per-channel, not shared: two channels can use
/// different types (and, for [salt], different percentages) during the
/// same scene-to-scene transition. Only [salt] uses a percentage (the
/// point in time, 0-100, where the instant jump happens); the rest ignore
/// it.
enum TransitionType {
  lineal(0),
  salt(1),
  easeIn(2),
  easeOut(3);

  const TransitionType(this.vValue);
  final int vValue;
}
