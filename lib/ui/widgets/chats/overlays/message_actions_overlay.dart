import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wrytte/ui/theme/wrytte_visual_style.dart';
import 'package:wrytte/ui/widgets/global/surfaces/wrytte_glass_surface.dart';
import 'message_actions_anchor.dart';

export 'message_actions_anchor.dart';

void _softActionFeedback() {
  unawaited(HapticFeedback.selectionClick());
}

class MessageActionItem {
  final IconData? icon;
  final String? svgAsset;
  final double iconScale;
  final bool mirrorSvgHorizontally;
  final String label;
  final FutureOr<void> Function() onSelected;
  final List<MessageActionItem> submenu;
  final bool destructive;

  /// Selection is a visual hand-off: apply it under the lifted preview before
  /// that preview returns, so the bubble follows one direct path to its final
  /// checkbox-cleared position.
  final bool selectionAction;

  const MessageActionItem({
    this.icon,
    this.svgAsset,
    this.iconScale = 1,
    this.mirrorSvgHorizontally = false,
    required this.label,
    required this.onSelected,
    this.submenu = const [],
    this.destructive = false,
    this.selectionAction = false,
  }) : assert(
         icon == null || svgAsset == null,
         'Provide no more than one action icon source.',
       );
}

class MessageActionsOverlayResult {
  final MessageActionItem? action;
  final String? reaction;
  final bool actionAlreadyHandled;

  const MessageActionsOverlayResult.action(MessageActionItem this.action)
    : reaction = null,
      actionAlreadyHandled = false;

  const MessageActionsOverlayResult.handled(MessageActionItem this.action)
    : reaction = null,
      actionAlreadyHandled = true;

  const MessageActionsOverlayResult.reaction(String this.reaction)
    : action = null,
      actionAlreadyHandled = false;
}

/// Opens the Telegram-style message context surface.
///
/// Moves the real bubble above an unbroken full-screen blur. Its original slot
/// stays the same size, and its state is preserved on opening and dismissal.
Future<MessageActionsOverlayResult?> showTelegramMessageActionsOverlay({
  required BuildContext context,
  required MessageActionsAnchorState bubbleAnchor,
  required bool isMine,
  required List<MessageActionItem> actions,
}) async {
  if (actions.isEmpty) return null;

  final navigator = Navigator.of(context, rootNavigator: true);
  final selection = bubbleAnchor.lift();
  final route = _MessageActionsPopupRoute(
    selection: selection,
    isMine: isMine,
    actions: actions,
  );
  try {
    final result = await navigator.push(route);
    await route.completed;
    return result;
  } finally {
    selection.release();
    selection.dispose();
  }
}

class _MessageActionsPopupRoute
    extends RawDialogRoute<MessageActionsOverlayResult> {
  _MessageActionsPopupRoute({
    required this.selection,
    required bool isMine,
    required List<MessageActionItem> actions,
  }) : super(
         barrierDismissible: false,
         barrierColor: Colors.transparent,
         barrierLabel: 'Dismiss message actions',
         requestFocus: false,
         transitionDuration: const Duration(milliseconds: 190),
         pageBuilder: (context, animation, secondaryAnimation) =>
             _TelegramMessageActionsRoute(
               selection: selection,
               isMine: isMine,
               actions: actions,
               routeAnimation: animation,
             ),
         transitionBuilder: (context, animation, secondaryAnimation, child) =>
             child,
       );

  final MessageActionsSelection selection;

  // Hand the live subtree back in the same frame that the menu is removed.
  // This also applies to Android Back, not only to action/outside taps.
  @override
  Duration get reverseTransitionDuration => Duration.zero;

  @override
  bool didPop(MessageActionsOverlayResult? result) {
    final popped = super.didPop(result);
    if (popped) selection.release();
    return popped;
  }
}

class _TelegramMessageActionsRoute extends StatefulWidget {
  final MessageActionsSelection selection;
  final bool isMine;
  final List<MessageActionItem> actions;
  final Animation<double> routeAnimation;

  const _TelegramMessageActionsRoute({
    required this.selection,
    required this.isMine,
    required this.actions,
    required this.routeAnimation,
  });

  @override
  State<_TelegramMessageActionsRoute> createState() =>
      _TelegramMessageActionsRouteState();
}

class _TelegramMessageActionsRouteState
    extends State<_TelegramMessageActionsRoute> {
  static const _primaryReactions = ['❤️', '👍', '👎', '🔥', '🥰', '👏'];
  static const _secondaryReactions = ['😂', '😮', '😢', '🎉', '🤔', '🙏'];

  late CurvedAnimation _appearance;
  late List<MessageActionItem> _visibleActions;
  bool _showingSubmenu = false;
  bool _showSecondaryReactions = false;

  @override
  void initState() {
    super.initState();
    _visibleActions = widget.actions;
    _appearance = CurvedAnimation(
      parent: widget.routeAnimation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
  }

  @override
  void didUpdateWidget(covariant _TelegramMessageActionsRoute oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.routeAnimation != widget.routeAnimation) {
      _appearance.dispose();
      _appearance = CurvedAnimation(
        parent: widget.routeAnimation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
    }
  }

  @override
  void dispose() {
    _appearance.dispose();
    super.dispose();
  }

  void _dismiss([MessageActionsOverlayResult? result]) {
    Navigator.of(context, rootNavigator: true).pop(result);
  }

  Future<void> _selectAction(MessageActionItem action) async {
    _softActionFeedback();
    if (action.submenu.isNotEmpty) {
      if (_showingSubmenu) return;
      setState(() {
        _showingSubmenu = true;
        _visibleActions = List.unmodifiable(action.submenu);
      });
      return;
    }
    if (action.selectionAction) {
      // Put the real row into selection mode while the lifted snapshot still
      // covers it. Incoming rows now occupy their final +38 px position before
      // this snapshot travels back, avoiding the old down-then-right motion.
      await Future<void>.sync(action.onSelected);
      if (!mounted) return;
      setState(() => _selectionExit = true);
      await Future<void>.delayed(const Duration(milliseconds: 150));
      if (!mounted) return;
      _dismiss(MessageActionsOverlayResult.handled(action));
      return;
    }
    _dismiss(MessageActionsOverlayResult.action(action));
  }

  bool _selectionExit = false;

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final size = mediaQuery.size;
    final safeViewport = Rect.fromLTRB(
      mediaQuery.padding.left + 8,
      mediaQuery.padding.top + 8,
      size.width - mediaQuery.padding.right - 8,
      size.height -
          math.max(mediaQuery.padding.bottom, mediaQuery.viewInsets.bottom) -
          8,
    );
    final geometry = _OverlayGeometry.resolve(
      safeViewport: safeViewport,
      bubbleRect: widget.selection.rect,
      isMine: widget.isMine,
      actionCount: widget.actions.length,
    );
    // Keep the lifted bubble in place while the menu changes into its compact
    // choices. Only the menu resizes; the original group layout stays anchored.
    var actionsRect = geometry.actionsRect;
    if (_showingSubmenu) {
      final width = _MessageActionsSurface.widthFor(
        context,
        actions: _visibleActions,
        availableWidth: safeViewport.width,
      );
      final left =
          (widget.isMine ? actionsRect.right - width : actionsRect.left)
              .clamp(safeViewport.left, safeViewport.right - width)
              .toDouble();
      actionsRect = Rect.fromLTWH(
        left,
        actionsRect.top,
        width,
        math.min(
          _visibleActions.length * _MessageActionRow.height +
              _MessageActionsSurface.verticalPadding * 2,
          safeViewport.bottom - actionsRect.top,
        ),
      );
    }

    return Material(
      type: MaterialType.transparency,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Semantics(
            button: true,
            label: 'Dismiss message actions',
            child: GestureDetector(
              key: const ValueKey('message-actions-scrim'),
              behavior: HitTestBehavior.opaque,
              onTap: _dismiss,
              child: const _MessageActionsBackdrop(),
            ),
          ),
          AnimatedBuilder(
            animation: _appearance,
            builder: (context, child) {
              final shownRect = Rect.lerp(
                widget.selection.rect,
                geometry.bubbleRect,
                _appearance.value,
              )!;
              final finalRect = widget.selection.rect.translate(
                widget.isMine ? 0 : 38,
                0,
              );
              return AnimatedPositioned.fromRect(
                duration: const Duration(milliseconds: 150),
                curve: Curves.easeOutCubic,
                rect: _selectionExit ? finalRect : shownRect,
                child: child!,
              );
            },
            child: IgnorePointer(
              child: FittedBox(
                key: const ValueKey('message-actions-selected-bubble'),
                fit: BoxFit.contain,
                alignment: Alignment.topLeft,
                child: widget.selection.buildPreview(),
              ),
            ),
          ),
          Positioned.fromRect(
            rect: geometry.reactionsRect,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 110),
              opacity: _selectionExit ? 0 : 1,
              child: _ContextSurfaceTransition(
                animation: _appearance,
                alignment: widget.isMine
                    ? Alignment.bottomRight
                    : Alignment.bottomLeft,
                child: IgnorePointer(
                  ignoring: _showingSubmenu,
                  child: AnimatedOpacity(
                    key: const ValueKey('message-actions-reaction-stage'),
                    duration: const Duration(milliseconds: 160),
                    curve: Curves.easeOutCubic,
                    opacity: _showingSubmenu ? 0 : 1,
                    child: AnimatedScale(
                      duration: const Duration(milliseconds: 180),
                      curve: Curves.easeOutCubic,
                      scale: _showingSubmenu ? 0.92 : 1,
                      alignment: widget.isMine
                          ? Alignment.bottomRight
                          : Alignment.bottomLeft,
                      child: _ReactionsSurface(
                        reactions: _showSecondaryReactions
                            ? _secondaryReactions
                            : _primaryReactions,
                        showingSecondary: _showSecondaryReactions,
                        onReaction: (reaction) {
                          _softActionFeedback();
                          _dismiss(
                            MessageActionsOverlayResult.reaction(reaction),
                          );
                        },
                        onMore: () {
                          _softActionFeedback();
                          setState(
                            () => _showSecondaryReactions =
                                !_showSecondaryReactions,
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          AnimatedPositioned.fromRect(
            duration: const Duration(milliseconds: 190),
            curve: Curves.easeOutCubic,
            rect: actionsRect,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 110),
              opacity: _selectionExit ? 0 : 1,
              child: _ContextSurfaceTransition(
                animation: _appearance,
                alignment: widget.isMine
                    ? Alignment.topRight
                    : Alignment.topLeft,
                child: _MessageActionsSurface(
                  actions: _visibleActions,
                  onSelected: _selectAction,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageActionsBackdrop extends StatelessWidget {
  const _MessageActionsBackdrop();

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      key: const ValueKey('message-actions-full-backdrop'),
      child: BackdropFilter(
        key: const ValueKey('message-actions-backdrop-filter'),
        filter: ui.ImageFilter.blur(
          sigmaX: 9,
          sigmaY: 9,
          tileMode: TileMode.clamp,
        ),
        blendMode: BlendMode.srcOver,
        child: ColoredBox(color: Colors.black.withValues(alpha: 0.36)),
      ),
    );
  }
}

class _OverlayGeometry {
  static const double _reactionHeight = 54;
  static const double _bubbleGap = 8;

  final Rect bubbleRect;
  final Rect reactionsRect;
  final Rect actionsRect;

  const _OverlayGeometry({
    required this.bubbleRect,
    required this.reactionsRect,
    required this.actionsRect,
  });

  factory _OverlayGeometry.resolve({
    required Rect safeViewport,
    required Rect bubbleRect,
    required bool isMine,
    required int actionCount,
  }) {
    final menuWidth = safeViewport.width <= 228
        ? safeViewport.width
        : (safeViewport.width * 0.638).clamp(228.0, 262.0).toDouble();
    final reactionsWidth = safeViewport.width <= 232
        ? safeViewport.width
        : (safeViewport.width * 0.72).clamp(232.0, 306.0).toDouble();
    final naturalMenuHeight =
        actionCount * _MessageActionRow.height +
        _MessageActionsSurface.verticalPadding * 2;
    // Always keep reactions ABOVE the actual bubble and actions below it.
    // For tall media, scroll the actions first; only shrink the preview when
    // necessary to leave at least two action rows on a short viewport.
    final contentBudget = math.max(
      1.0,
      safeViewport.height - _reactionHeight - _bubbleGap * 2,
    );
    final minimumMenuHeight = math.min(
      naturalMenuHeight,
      math.min(102.0, contentBudget * 0.45),
    );
    final previewScale = math.min(
      1.0,
      math.min(
        safeViewport.width / bubbleRect.width,
        (contentBudget - minimumMenuHeight) / bubbleRect.height,
      ),
    );
    final previewSize = bubbleRect.size * previewScale;
    final menuHeight = math.min(
      math.min(naturalMenuHeight, 380.0),
      contentBudget - previewSize.height,
    );
    final groupHeight =
        _reactionHeight + _bubbleGap * 2 + previewSize.height + menuHeight;
    final groupTop = (bubbleRect.top - _reactionHeight - _bubbleGap)
        .clamp(
          safeViewport.top,
          math.max(safeViewport.top, safeViewport.bottom - groupHeight),
        )
        .toDouble();
    final previewLeft =
        (isMine ? bubbleRect.right - previewSize.width : bubbleRect.left)
            .clamp(safeViewport.left, safeViewport.right - previewSize.width)
            .toDouble();
    final previewRect = Rect.fromLTWH(
      previewLeft,
      groupTop + _reactionHeight + _bubbleGap,
      previewSize.width,
      previewSize.height,
    );
    final menuLeft = (isMine ? previewRect.right - menuWidth : previewRect.left)
        .clamp(safeViewport.left, safeViewport.right - menuWidth)
        .toDouble();
    final reactionsLeft =
        (isMine ? previewRect.right - reactionsWidth : previewRect.left)
            .clamp(safeViewport.left, safeViewport.right - reactionsWidth)
            .toDouble();
    final reactionsRect = Rect.fromLTWH(
      reactionsLeft,
      groupTop,
      reactionsWidth,
      _reactionHeight,
    );
    final actionsRect = Rect.fromLTWH(
      menuLeft,
      previewRect.bottom + _bubbleGap,
      menuWidth,
      menuHeight,
    );
    return _OverlayGeometry(
      bubbleRect: previewRect,
      reactionsRect: reactionsRect,
      actionsRect: actionsRect,
    );
  }
}

class _ContextSurfaceTransition extends StatelessWidget {
  final Animation<double> animation;
  final Alignment alignment;
  final Widget child;

  const _ContextSurfaceTransition({
    required this.animation,
    required this.alignment,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: animation,
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.94, end: 1).animate(animation),
        alignment: alignment,
        child: child,
      ),
    );
  }
}

class _ReactionsSurface extends StatelessWidget {
  final List<String> reactions;
  final bool showingSecondary;
  final ValueChanged<String> onReaction;
  final VoidCallback onMore;

  const _ReactionsSurface({
    required this.reactions,
    required this.showingSecondary,
    required this.onReaction,
    required this.onMore,
  });

  @override
  Widget build(BuildContext context) {
    return WrytteGlassSurface(
      key: const ValueKey('message-actions-reactions'),
      borderRadius: BorderRadius.circular(27),
      blur: 18,
      child: Material(
        type: MaterialType.transparency,
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(6, 4, 5, 4),
          child: Row(
            children: [
              for (final reaction in reactions)
                Expanded(
                  child: Semantics(
                    button: true,
                    label: 'React with $reaction',
                    child: InkResponse(
                      key: ValueKey('message-reaction-$reaction'),
                      onTap: () => onReaction(reaction),
                      containedInkWell: true,
                      highlightShape: BoxShape.circle,
                      radius: 21,
                      child: SizedBox.square(
                        dimension: 42,
                        child: Center(
                          child: Text(
                            reaction,
                            style: const TextStyle(fontSize: 23, height: 1),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              const SizedBox(width: 2),
              Semantics(
                button: true,
                label: showingSecondary
                    ? 'Show common reactions'
                    : 'Show more reactions',
                child: InkResponse(
                  key: const ValueKey('message-actions-more-reactions'),
                  onTap: onMore,
                  containedInkWell: true,
                  highlightShape: BoxShape.circle,
                  radius: 21,
                  child: Container(
                    width: 40,
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.075),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.055),
                        width: 0.7,
                      ),
                    ),
                    child: Icon(
                      showingSecondary
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      size: 23,
                      color: WrytteVisualTokens.iconColor,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MessageActionsSurface extends StatelessWidget {
  static const double verticalPadding = 12;

  final List<MessageActionItem> actions;
  final ValueChanged<MessageActionItem> onSelected;

  const _MessageActionsSurface({
    required this.actions,
    required this.onSelected,
  });

  static double widthFor(
    BuildContext context, {
    required List<MessageActionItem> actions,
    required double availableWidth,
  }) {
    var width = math.min(
      (MediaQuery.sizeOf(context).width * .638).clamp(228.0, 262.0).toDouble(),
      availableWidth,
    );
    for (final action in actions) {
      final painter = TextPainter(
        text: TextSpan(text: action.label, style: _MessageActionRow.labelStyle),
        maxLines: 1,
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
        locale: Localizations.maybeLocaleOf(context),
      )..layout();
      final hasIcon = _showsIcon(action);
      width = math.max(
        width,
        _MessageActionRow.padding.horizontal +
            (hasIcon
                ? _MessageActionRow.iconWidth + _MessageActionRow.iconGap
                : 0) +
            painter.width.ceilToDouble(),
      );
      painter.dispose();
    }
    return math.min(width, availableWidth);
  }

  static bool _showsIcon(MessageActionItem action) =>
      action.icon != null || action.svgAsset != null;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final requestedRadius = constraints.maxWidth * .19;
        final radius = math.min(requestedRadius, constraints.maxHeight * .44);
        final shape = RoundedSuperellipseBorder(
          borderRadius: BorderRadius.circular(radius),
        );
        return ClipPath.shape(
          key: const ValueKey('message-actions-surface'),
          shape: shape,
          clipBehavior: Clip.antiAlias,
          child: WrytteGlassSurface(
            borderRadius: BorderRadius.zero,
            blur: 18,
            child: Material(
              type: MaterialType.transparency,
              shape: shape,
              clipBehavior: Clip.antiAlias,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 170),
                reverseDuration: const Duration(milliseconds: 130),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                layoutBuilder: (currentChild, previousChildren) => Stack(
                  alignment: Alignment.topLeft,
                  children: [
                    for (final child in previousChildren)
                      IgnorePointer(child: child),
                    if (currentChild != null) currentChild,
                  ],
                ),
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0.035, 0),
                      end: Offset.zero,
                    ).animate(animation),
                    child: child,
                  ),
                ),
                child: KeyedSubtree(
                  key: ObjectKey(actions),
                  child: ListView.builder(
                    key: const ValueKey('message-actions-scroll'),
                    padding: const EdgeInsets.symmetric(
                      vertical: verticalPadding,
                    ),
                    physics: const ClampingScrollPhysics(),
                    itemCount: actions.length,
                    itemBuilder: (context, index) {
                      final action = actions[index];
                      return _MessageActionRow(
                        action: action,
                        onTap: () => onSelected(action),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _MessageActionRow extends StatelessWidget {
  static const double height = 42;
  static const double iconWidth = 20;
  static const double iconGap = 9;
  static const padding = EdgeInsetsDirectional.fromSTEB(22, 0, 22, 0);
  static const labelStyle = TextStyle(
    inherit: false,
    fontFamily: WrytteTypography.primaryFontFamily,
    fontSize: 15,
    fontWeight: FontWeight.w500,
    height: 1,
    letterSpacing: 0,
  );

  final MessageActionItem action;
  final VoidCallback onTap;

  const _MessageActionRow({required this.action, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = action.destructive ? WrytteColors.destructive : Colors.white;
    final hasIcon = _MessageActionsSurface._showsIcon(action);

    return SizedBox(
      height: height,
      child: InkWell(
        key: ValueKey('message-action-${action.label}'),
        onTap: onTap,
        child: Padding(
          padding: padding,
          child: Row(
            children: [
              if (hasIcon) ...[
                SizedBox(
                  key: ValueKey('message-action-icon-slot-${action.label}'),
                  width: iconWidth,
                  child: Center(child: _buildIcon(color)),
                ),
                const SizedBox(width: iconGap),
              ],
              Expanded(
                child: Text(
                  action.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: labelStyle.copyWith(color: color),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildIcon(Color color) {
    if (action.svgAsset == null) {
      return Icon(action.icon!, size: 19, color: color);
    }

    final icon = wrytteSvgAssetIcon(
      assetPath: action.svgAsset!,
      canvas: 19,
      scale: action.iconScale,
      color: color,
    );
    return action.mirrorSvgHorizontally
        ? Transform.flip(flipX: true, child: icon)
        : icon;
  }
}
