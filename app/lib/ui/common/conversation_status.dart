import 'package:dsh_client/dsh_client.dart';
import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../theme/app_icons.dart';
import 'status_dot.dart';

/// The status of the latest turn, shared by the header and the drawer.
enum ConversationStatus {
  running(StatusTone.busy),
  stopping(StatusTone.busy, AppIcons.stop),
  waitingApproval(StatusTone.warn, AppIcons.askFirst),
  waitingAnswer(StatusTone.warn, AppIcons.question),
  completed(StatusTone.ok, AppIcons.done),
  stopped(StatusTone.idle, AppIcons.stopGenerating),
  error(StatusTone.error, AppIcons.error),
  outputLimit(StatusTone.warn, AppIcons.outputLimit),
  blocked(StatusTone.warn, AppIcons.blocked),
  interrupted(StatusTone.idle, AppIcons.restart);

  const ConversationStatus(this.tone, [this.icon]);
  final StatusTone tone;
  final IconData? icon;

  static ConversationStatus? fromOutcome(TurnOutcomeKind? kind) => switch (kind) {
    TurnOutcomeKind.completed => completed,
    TurnOutcomeKind.stopped => stopped,
    TurnOutcomeKind.error => error,
    TurnOutcomeKind.outputLimit => outputLimit,
    TurnOutcomeKind.blocked => blocked,
    TurnOutcomeKind.interrupted => interrupted,
    null => null,
  };

  String label(L10n l10n) => switch (this) {
    running => l10n.conversationRunning,
    stopping => l10n.commonStopping,
    waitingApproval => l10n.commonWaitingApproval,
    waitingAnswer => l10n.commonWaitingAnswer,
    completed => l10n.conversationCompleted,
    stopped => l10n.commonStopped,
    error => l10n.conversationError,
    outputLimit => l10n.conversationOutputLimit,
    blocked => l10n.conversationBlocked,
    interrupted => l10n.chatInterrupted,
  };

  Widget glyph({required double size, bool animated = true}) =>
      _ConversationStatusGlyph(status: this, size: size, animated: animated);
}

class _ConversationStatusGlyph extends StatelessWidget {
  const _ConversationStatusGlyph({required this.status, required this.size, required this.animated});

  final ConversationStatus status;
  final double size;
  final bool animated;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: Center(
      child: switch (status.icon) {
        final icon? => Icon(icon, color: StatusDot.colorFor(context, status.tone), size: size),
        null => StatusDot(tone: status.tone, size: size * 0.6, animated: animated),
      },
    ),
  );
}
