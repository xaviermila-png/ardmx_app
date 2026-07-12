/// A single decoded state change coming from the Arduino, either a numeric
/// `V[index]` update or a text `T[index]` update.
sealed class VirtuinoUpdate {
  const VirtuinoUpdate();
}

class VirtuinoVUpdate extends VirtuinoUpdate {
  const VirtuinoVUpdate(this.index, this.value);

  final int index;
  final double value;

  @override
  String toString() => 'V$index=$value';
}

class VirtuinoTUpdate extends VirtuinoUpdate {
  const VirtuinoTUpdate(this.index, this.text);

  final int index;
  final String text;

  @override
  String toString() => 'T$index=$text';
}
