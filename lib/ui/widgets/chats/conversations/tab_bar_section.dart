import 'package:flutter/material.dart';
import 'package:wrytte/ui/widgets/global/navigation/wrytte_glass_tab_bar.dart';

class TabBarSection extends StatelessWidget {
  const TabBarSection({super.key, this.controller});

  final TabController? controller;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.transparent,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: WrytteGlassTabBar(
        controller: controller,
        tabs: const [
          Tab(text: 'Chats'),
          Tab(text: 'Channels'),
          Tab(text: 'Groups'),
        ],
      ),
    );
  }
}
