part of '../../../screens/chats/chat_screen.dart';

extension _ChatMessageActionTile on _ChatScreenState {
  Widget _messageActionTile({
    IconData? icon,
    String? svgAsset,
    double iconScale = 1,
    bool mirrorSvgHorizontally = false,
    required String label,
    required VoidCallback? onTap,
    bool destructive = false,
  }) {
    assert((icon == null) != (svgAsset == null));
    final color = destructive ? WrytteColors.destructive : Colors.white;
    Widget leading =
        svgAsset != null
            ? wrytteSvgAssetIcon(
              assetPath: svgAsset,
              canvas: 22,
              scale: iconScale,
              color: color,
            )
            : Icon(icon!, color: color);
    if (mirrorSvgHorizontally) {
      leading = Transform.flip(flipX: true, child: leading);
    }
    return ListTile(
      dense: true,
      visualDensity: const VisualDensity(horizontal: -1, vertical: -1),
      contentPadding: const EdgeInsetsDirectional.only(start: 20, end: 14),
      minLeadingWidth: 23,
      horizontalTitleGap: 18,
      leading: leading,
      title: Text(
        label,
        style: TextStyle(
          color: color,
          fontFamily: WrytteTypography.primaryFontFamily,
          fontSize: 16,
          fontWeight: FontWeight.w400,
        ),
      ),
      onTap: onTap,
    );
  }
}
