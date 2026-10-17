import 'package:flutter/material.dart';

/// Small widgets shared by the Stance-styled screens.

/// Stance's `CircularIconButton`: a 44 dp circle at 5 % white. Without
/// [onPressed] it is only the visual (e.g. as a menu button's child).
class CircleIconButton extends StatelessWidget {
  const CircleIconButton(
      {super.key, required this.icon, this.onPressed, this.tooltip});

  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final circle = Container(
      width: 44,
      height: 44,
      decoration: const BoxDecoration(
          shape: BoxShape.circle, color: Color(0x0DFFFFFF)),
      child: Icon(icon, color: Colors.white),
    );
    if (onPressed == null) return circle;
    return Tooltip(
      message: tooltip ?? '',
      child: InkWell(
          customBorder: const CircleBorder(), onTap: onPressed, child: circle),
    );
  }
}
