/// Direct Dart port of `interpolar()` in both firmwares' `main.cpp` — same
/// integer-math formulas, not reinvented. [tPerMille] is progress through
/// the transition, 0-1000 (per-mille, matching the firmware's `t_pct`).
/// [tipus] is a raw `TransitionType.vValue` (0=Lineal, 1=Salt, 2=Ease In,
/// 3=Ease Out).
int interpolarCanal(
  int v0,
  int v1,
  int tPerMille,
  int tipus,
  int saltPercent,
) {
  switch (tipus) {
    case 1: // SALT
      return tPerMille < saltPercent * 10 ? v0 : v1;
    case 3: // EASE_OUT: ràpid al principi, s'alenteix al final
      final inv = 1000 - tPerMille;
      final f = 1000 - (inv * inv) ~/ 1000;
      return v0 + ((v1 - v0) * f) ~/ 1000;
    case 2: // EASE_IN: lent al principi, accelera al final
      final f = (tPerMille * tPerMille) ~/ 1000;
      return v0 + ((v1 - v0) * f) ~/ 1000;
    default: // LINEAL
      return v0 + ((v1 - v0) * tPerMille) ~/ 1000;
  }
}
