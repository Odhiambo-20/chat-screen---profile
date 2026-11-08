import 'package:flutter/material.dart';
import 'package:wrytte/ui/widgets/global/navigation/wrytte_glass_tab_bar.dart';

/// Profile tab layout backed by the application-wide glass tab component.
class ProfileTabBarSection extends StatelessWidget {
  const ProfileTabBarSection({
    super.key,
    required this.controller,
    required this.tabs,
  });

  final TabController controller;
  final List<String> tabs;

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final centred = tabs.length <= 2;
    final containerWidth = centred ? screenWidth * 0.6 : screenWidth;
    final padding =
        centred
            ? const EdgeInsets.symmetric(vertical: 6)
            : const EdgeInsets.symmetric(horizontal: 16, vertical: 6);

    final tabBar = WrytteGlassTabBar(
      controller: controller,
      tabs: tabs.map((label) => Tab(text: label)).toList(growable: false),
    );

    return Container(
      color: Colors.transparent,
      padding: padding,
      child:
          centred
              ? Center(child: SizedBox(width: containerWidth, child: tabBar))
              : tabBar,
    );
  }
}
