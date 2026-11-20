import 'package:material_ui/material_ui.dart';

/// Small fixed-size progress indicator that sits inside a button (as its
/// label or icon) while the button's action is in flight.
class ButtonSpinner extends StatelessWidget {
  const ButtonSpinner({super.key, this.size = 18});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: const CircularProgressIndicator(strokeWidth: 2),
    );
  }
}
