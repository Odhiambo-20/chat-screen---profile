import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:wrytte/ui/core/themes/wrytte_theme.dart';
import 'package:wrytte/ui/core/widgets/wrytte_glass_surface.dart';

class ChatMediaEditorCaption extends StatelessWidget {
  const ChatMediaEditorCaption({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.enabled,
  });
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool enabled;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(21),
    child: BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
      child: WrytteGlassSurface(
        borderRadius: BorderRadius.circular(21),
        blur: 1,
        child: SizedBox(
          height: 50,
          child: TextField(
            controller: controller,
            focusNode: focusNode,
            enabled: enabled,
            expands: true,
            minLines: null,
            maxLines: null,
            textAlignVertical: TextAlignVertical.center,
            textInputAction: TextInputAction.done,
            cursorColor: WrytteColors.primary,
            cursorWidth: 1.5,
            style: const TextStyle(color: Colors.white, fontSize: 15),
            decoration: InputDecoration(
              isDense: true,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              hintText: 'Add a caption...',
              hintStyle: TextStyle(
                color: WrytteColors.textSecondary.withValues(alpha: .72),
                fontSize: 15,
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            ),
          ),
        ),
      ),
    ),
  );
}
