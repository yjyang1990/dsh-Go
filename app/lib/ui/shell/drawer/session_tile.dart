// The drawer's conversation row and section label.

import 'package:flutter/material.dart';

import '../../../l10n/l10n.dart';
import '../../common/conversation_status.dart';
import '../../theme/app_icons.dart';
import '../../theme/theme.dart';
import '../sessions_drawer.dart' show sessionSelectionColor;

/// One conversation row: 44 high, the highlight on the 10 line, the title on
/// the 20 line (plus [indent] inside a folder). A trailing status shows the
/// latest turn, with a separate unread dot. In multi-select a check slides
/// in before the title.
class SessionTile extends StatelessWidget {
  const SessionTile({
    super.key,
    required this.title,
    required this.status,
    required this.current,
    required this.onTap,
    required this.onLongPress,
    this.lastKnown = false,
    this.unread = false,
    this.pinned = false,
    this.indent = 0,
    this.selecting = false,
    this.selected = false,
  });

  final String title;
  final ConversationStatus? status;

  /// The open conversation (soft fill; ignored while selecting).
  final bool current;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final bool lastKnown;
  final bool unread;

  /// Shown as a small pin (inside folders; elsewhere 置顶 says it).
  final bool pinned;

  /// Content inset from the 20 line (folder members: [folderIndent]).
  final double indent;
  final bool selecting;
  final bool selected;

  static const height = 44.0;

  /// A folder's glyph (20) plus its gap (10): members' titles line up with
  /// the folder's name.
  static const folderIndent = 30.0;

  /// Width of the check slot while selecting (a 20 circle and a 10 gap).
  static const checkSlot = 30.0;

  /// Size of the quiet markers at the end of the row.
  static const dot = 7.0;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final colors = DshColors.of(context);
    final shape = Squircle.border(AppShape.md);
    final highlighted = selecting ? selected : current;
    final statusLabel = status?.label(l10n);
    final displayStatus = lastKnown && statusLabel != null ? l10n.conversationLastKnown(statusLabel) : statusLabel;
    final label = [
      title,
      ?displayStatus,
      if (unread) l10n.shellUnread,
      if (pinned) l10n.shellPinned,
    ].join(l10n.shellSemanticsSeparator);
    return Semantics(
      selected: highlighted,
      checked: selecting ? selected : null,
      label: label,
      button: true,
      onTap: onTap,
      onLongPress: onLongPress,
      excludeSemantics: true,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          customBorder: shape,
          // Ink (not a container's decoration), so the splash draws over the
          // fill; the fill fades in and out.
          child: TweenAnimationBuilder<double>(
            tween: Tween(end: highlighted ? 1 : 0),
            duration: AppMotion.of(context, AppMotion.quick),
            curve: AppMotion.std,
            builder: (context, t, child) {
              final fill = sessionSelectionColor(context);
              return Ink(
                decoration: ShapeDecoration(
                  color: fill.withValues(alpha: fill.a * t),
                  shape: shape,
                ),
                height: height,
                padding: EdgeInsets.only(left: 10 + indent, right: 10),
                child: child,
              );
            },
            child: LayoutBuilder(
              builder: (context, constraints) => Row(
                children: [
                  _CheckSlot(selecting: selecting, selected: selected),
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontSize: 15,
                        height: 1.4,
                        color: scheme.onSurface,
                        fontWeight: current && !selecting ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                  ),
                  if (pinned) ...[
                    const SizedBox(width: 8),
                    Icon(AppIcons.pinActive, size: 14, color: colors.textTertiary),
                  ],
                  if (unread) ...[
                    const SizedBox(width: 8),
                    _UnreadDot(key: const ValueKey('unread'), color: scheme.onSurfaceVariant),
                  ],
                  if (status case final status?)
                    ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: constraints.maxWidth * 0.58),
                      child: Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            status.glyph(size: 12, animated: false),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                displayStatus!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _UnreadDot extends StatelessWidget {
  const _UnreadDot({super.key, required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: SessionTile.dot,
    height: SessionTile.dot,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}

/// The check that slides in before the title while selecting: a 20 ring,
/// filled with ink and a tick once chosen (ink, not the brand colour — the
/// drawer keeps one primary element).
class _CheckSlot extends StatelessWidget {
  const _CheckSlot({required this.selecting, required this.selected});

  final bool selecting;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return TweenAnimationBuilder<double>(
      tween: Tween(end: selecting ? 1 : 0),
      duration: AppMotion.of(context, AppMotion.standard),
      curve: AppMotion.std,
      builder: (context, t, child) {
        if (t == 0) return const SizedBox.shrink();
        return SizedBox(
          width: SessionTile.checkSlot * t,
          child: ClipRect(
            child: OverflowBox(
              alignment: Alignment.centerLeft,
              minWidth: SessionTile.checkSlot,
              maxWidth: SessionTile.checkSlot,
              child: Opacity(opacity: t, child: child),
            ),
          ),
        );
      },
      child: Align(
        alignment: Alignment.centerLeft,
        child: AnimatedSwitcher(
          duration: AppMotion.of(context, AppMotion.quick),
          child: selected
              ? DecoratedBox(
                  key: const ValueKey('on'),
                  decoration: ShapeDecoration(color: scheme.onSurface, shape: const CircleBorder()),
                  child: SizedBox.square(
                    dimension: 20,
                    child: Icon(AppIcons.selected, size: 14, color: scheme.surface),
                  ),
                )
              : DecoratedBox(
                  key: const ValueKey('off'),
                  decoration: ShapeDecoration(
                    shape: CircleBorder(
                      side: BorderSide(color: scheme.onSurfaceVariant.withValues(alpha: 0.55), width: 1.5),
                    ),
                  ),
                  child: const SizedBox.square(dimension: 20),
                ),
        ),
      ),
    );
  }
}

/// A section label in the drawer list: small, faint, on the 20 line.
class DrawerEyebrow extends StatelessWidget {
  const DrawerEyebrow(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 16, 10, 6),
      child: Semantics(
        header: true,
        child: Text(text, style: AppType.eyebrow(color: DshColors.of(context).textTertiary)),
      ),
    );
  }
}
