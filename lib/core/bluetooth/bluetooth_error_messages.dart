/// Translates raw platform/plugin error strings (from
/// [BluetoothConnectionState.lastError]) into short, user-friendly Catalan
/// messages. The raw message stays available for diagnostics (e.g. the
/// debug screen, or a tooltip) — this is only for what's shown to the end
/// user by default.
String friendlyBluetoothError(String? raw) {
  if (raw == null) return "No s'ha pogut connectar.";
  final lower = raw.toLowerCase();

  if (lower.contains('read failed') || lower.contains('timeout')) {
    return "No s'ha pogut connectar: comprova que el dispositiu estigui "
        "engegat i a l'abast.";
  }
  if (lower.contains('permission')) {
    return 'Permís de Bluetooth denegat.';
  }
  if (lower.contains('already connected')) {
    return 'Ja hi ha una connexió en curs amb aquest dispositiu.';
  }
  if (lower.contains('closed') || lower.contains('ondone')) {
    return "S'ha perdut la connexió amb el dispositiu.";
  }
  if (lower.contains('couldnotconnect') ||
      lower.contains('returned null') ||
      lower.contains('could not connect')) {
    return "No s'ha pogut connectar amb el dispositiu.";
  }
  return "No s'ha pogut connectar.";
}
