import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wrytte/ui/core/themes/wrytte_theme.dart';
import 'package:wrytte/ui/core/widgets/wrytte_glass_surface.dart';

class ChatMediaEditorHeader extends StatelessWidget {
  const ChatMediaEditorHeader({
    super.key,
    required this.onBack,
    this.showSelectionControl = true,
    this.selected = false,
    this.onSelectionChanged,
  });

  final VoidCallback onBack;
  final bool showSelectionControl;
  final bool selected;
  final ValueChanged<bool>? onSelectionChanged;
  static const double contentHeight = 64;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.viewPaddingOf(context).top;
    return SizedBox(
      height: top + contentHeight,
      child: Padding(
        padding: EdgeInsetsDirectional.only(start: 13, end: 13, top: top + 6),
        child: Stack(
          children: [
            Align(
              alignment: AlignmentDirectional.topStart,
              child: WrytteGlassSurface(
                borderRadius: BorderRadius.circular(23),
                blur: 20,
                color: const Color(0xFF1B1E24),
                child: Material(
                  type: MaterialType.transparency,
                  shape: const CircleBorder(),
                  clipBehavior: Clip.antiAlias,
                  child: SizedBox.square(
                    dimension: 46,
                    child: InkResponse(
                      onTap: () {
                        unawaited(HapticFeedback.selectionClick());
                        onBack();
                      },
                      containedInkWell: true,
                      highlightShape: BoxShape.circle,
                      child: const Center(
                        child: Icon(
                          Icons.arrow_back_ios_new_rounded,
                          size: 27,
                          color: WrytteColors.textPrimary,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (showSelectionControl)
              Align(
                alignment: AlignmentDirectional.topEnd,
                child: GestureDetector(
                  onTap: () => onSelectionChanged?.call(!selected),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    width: 34,
                    height: 34,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: selected
                          ? WrytteColors.primary
                          : Colors.transparent,
                      shape: BoxShape.circle,
                      border: selected
                          ? null
                          : Border.all(color: Colors.white, width: 1.6),
                    ),
                    child: selected
                        ? const Text(
                            '1',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          )
                        : null,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
