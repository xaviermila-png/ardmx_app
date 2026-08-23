import 'package:flutter/material.dart';

/// Compact (mini) RGB-wheel FAB — sized to sit alongside
/// [GlobalTransitionEditor]'s nav arrows in its header row (see
/// [GlobalTransitionEditor.trailing]) rather than taking its own row
/// underneath, which used to cost the channel sliders above ~80px of
/// vertical space they needed more.
class RgbWheelButton extends StatelessWidget {
  const RgbWheelButton({super.key, required this.heroTag, required this.onPressed});

  final String heroTag;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton(
      mini: true,
      heroTag: heroTag,
      onPressed: onPressed,
      tooltip: 'Configuració RGB (roda de color)',
      child: const SizedBox(
        width: 40,
        height: 40,
        child: Stack(
          alignment: Alignment.center,
          children: [
            ClipOval(
              child: Image(
                image: AssetImage('assets/imatges/RGB.png'),
                fit: BoxFit.cover,
                width: 40,
                height: 40,
              ),
            ),
            Text(
              'RGB',
              style: TextStyle(
                color: Colors.black,
                fontWeight: FontWeight.bold,
                fontSize: 9,
                shadows: [Shadow(blurRadius: 3, color: Colors.white)],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
