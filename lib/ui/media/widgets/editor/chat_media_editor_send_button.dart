import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:wrytte/ui/core/themes/wrytte_theme.dart';
import 'package:wrytte/ui/core/widgets/wrytte_svg_icon.dart';

class ChatMediaEditorSendButton extends StatelessWidget {
  const ChatMediaEditorSendButton({
    super.key,
    required this.onPressed,
    required this.busy,
  });
  final VoidCallback? onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: onPressed,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      width: 42,
      height: 42,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: WrytteColors.primary.withValues(alpha: busy ? .7 : 1),
        shape: BoxShape.circle,
      ),
      child: busy
          ? const SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : Transform.rotate(
              angle: math.pi / 4,
              child: const WrytteSvgIcon(
                asset: 'assets/svg/Send icon .svg',
                size: 25,
                color: Colors.white,
              ),
            ),
    ),
  );
}
