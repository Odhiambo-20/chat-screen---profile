part of '../../../screens/chats/chat_screen.dart';

class _CopyToast extends StatefulWidget {
  final String message;
  final String? iconAsset;
  final VoidCallback onDismissed;

  const _CopyToast({
    required this.message,
    required this.onDismissed,
    this.iconAsset,
  });

  @override
  State<_CopyToast> createState() => _CopyToastState();
}

class _CopyToastState extends State<_CopyToast>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;
  late final Animation<double> _scale;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
      reverseDuration: const Duration(milliseconds: 180),
    );
    _opacity = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0, 0.62, curve: Curves.easeOutCubic),
      reverseCurve: Curves.easeInCubic,
    );
    _scale = Tween<double>(begin: 0.92, end: 1).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeOutBack,
        reverseCurve: Curves.easeInCubic,
      ),
    );
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.32),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      ),
    );
    _play();
  }

  Future<void> _play() async {
    try {
      await _controller.forward();
      await Future<void>.delayed(const Duration(milliseconds: 1350));
      if (!mounted) return;
      await _controller.reverse();
      if (mounted) widget.onDismissed();
    } on TickerCanceled {
      // A newer copy toast replaced this one.
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: FadeTransition(
        opacity: _opacity,
        child: SlideTransition(
          position: _slide,
          child: ScaleTransition(
            scale: _scale,
            child: IntrinsicWidth(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(19),
                child: ColoredBox(
                  color: const Color(0xFF17191F).withValues(alpha: 0.94),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (widget.iconAsset != null) ...[
                          wrytteSvgAssetIcon(
                            assetPath: widget.iconAsset!,
                            canvas: 18,
                            scale: 1.15,
                            color: WrytteColors.primary,
                          ),
                          const SizedBox(width: 10),
                        ],
                        Flexible(
                          child: Text(
                            widget.message,
                            maxLines: 1,
                            softWrap: false,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Color(0xFFF7F8FA),
                              fontFamily: WrytteTypography.primaryFontFamily,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              height: 1.15,
                              decoration: TextDecoration.none,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
