import 'package:flutter/material.dart';

import '../state/app_state.dart';
import '../state/session.dart';
import '../theme/app_theme.dart';
import '../theme/pixels.dart';
import '../theme/tokens.dart';
import '../widgets/common.dart';
import '../widgets/rolling_number.dart';
import '../widgets/the_page.dart';
import '../widgets/tile.dart';

/// What the session changed: what you can now do, not points.
class SessionEnd extends StatelessWidget {
  const SessionEnd({super.key, required this.session, required this.onClose, required this.onNext});

  final Session session;
  final VoidCallback onClose;
  final ValueChanged<Session> onNext;

  static const _milestones = [10, 25, 50, 100, 150, 200, 300, 500, 750, 1000, 1500];

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final state = AppScope.of(context);
    final s = session;
    final exam = s.kind == SessionKind.exam;
    final passed = exam && s.score >= AppState.passMark;
    final title = switch (s.kind) {
      SessionKind.exam when passed => 'Level ${s.level!.n} passed',
      SessionKind.exam => 'Not quite yet',
      SessionKind.lesson => 'Lesson done',
      SessionKind.review => state.dueCount == 0 ? 'All caught up' : 'Good work',
    };
    final before = s.litBefore.length, after = state.learnedChars.length;
    final milestone = _milestones.where((m) => before < m && after >= m).lastOrNull;
    // The fullest sentence the lesson opened up, without a name in it if there's a choice.
    final opened = s.lesson?.sentences.map((id) => state.course.sentences[id]).nonNulls.toList() ?? const [];
    final reward = (opened.toList()..sort((a, b) {
          final names = (a.toks.any(state.course.names.containsKey) ? 1 : 0) - (b.toks.any(state.course.names.containsKey) ? 1 : 0);
          return names != 0 ? names : b.zh.length - a.zh.length;
        })).firstOrNull;
    final next = state.nextLesson;
    final more = state.dueCount;

    final Session? following = state.finishedCourse
        ? null
        : more > 0 && s.kind != SessionKind.review
        ? Session.review(state)
        : s.kind == SessionKind.review && more > 0
        ? Session.review(state)
        : next != null
        ? Session.forLesson(state, next)
        : Session.exam(state, state.level);
    final followLabel = more > 0
        ? 'Review $more due'
        : next != null
        ? 'Next lesson'
        : 'Take the Level ${state.level.n} exam';

    return LayoutBuilder(
      builder: (context, box) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: box.maxHeight),
          child: Align(
            alignment: const PixelCentre(),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: PixelColumn(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(title, textAlign: TextAlign.center, style: displayStyle(38, p.ink)),
                  const SizedBox(height: 8),
                  Text(_subtitle(state, passed), textAlign: TextAlign.center, style: bodyStyle(p.inkMuted)),
                  const SizedBox(height: 24),
                  Tile(
                    child: PixelRow(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Stat(value: Text('${(s.score * 100).round()}%'), label: exam ? 'Score' : 'First try'),
                        Stat(
                          value: RollingNumber(value: after, duration: Motion.page, style: displayStyle(38, p.ink)),
                          label: 'Characters',
                          note: after > before ? '+${after - before} new' : null,
                        ),
                        Stat(
                          value: RollingNumber(value: state.streak, duration: Motion.page, style: displayStyle(38, p.ink)),
                          label: 'Day streak',
                          note: state.today.complete ? 'Today counts' : null,
                        ),
                      ],
                    ),
                  ),
                  if (milestone != null) ...[
                    const SizedBox(height: 12),
                    Tile(
                      child: Text('$milestone characters. A real part of written Chinese is now yours.', textAlign: TextAlign.center, style: displayStyle(18, p.ink)),
                    ),
                  ],
                  if (reward != null) ...[
                    const SizedBox(height: 12),
                    Tile(
                      child: PixelColumn(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('YOU CAN NOW READ THIS', style: capsLabel(p.inkMuted)),
                          const SizedBox(height: 8),
                          Text(reward.zh, style: zhStyle(28, p.ink)),
                          Text(reward.en, style: bodyStyle(p.inkMuted)),
                        ],
                      ),
                    ),
                  ],
                  if (passed || after > before) ...[
                    const SizedBox(height: 12),
                    Tile(
                      child: PixelColumn(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('THE PAGE  ·  ${(pageShare(state) * 100).round()}% LIT', style: capsLabel(p.inkMuted)),
                          const SizedBox(height: 12),
                          ThePage(cell: 22, litBefore: s.litBefore),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      PillButton(label: 'Done for now', primary: following == null, onTap: onClose),
                      if (following != null) PillButton(label: followLabel, primary: true, onTap: () => onNext(following)),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _subtitle(AppState state, bool passed) {
    final s = session;
    switch (s.kind) {
      case SessionKind.exam:
        if (passed) {
          final before = s.level!.n > 1 ? state.course.levels[s.level!.n - 2].readable : 0;
          return 'You passed on sentences you had never seen. ${s.level!.readable - before} more real sentences are now within reach.';
        }
        return 'You need ${(AppState.passMark * 100).round()}% and got ${(s.score * 100).round()}%. What you missed is back in your reviews, and the next exam uses different sentences.';
      case SessionKind.lesson:
        final l = state.level;
        final left = l.lessons.length - state.doneInLevel(l);
        return left == 0 ? 'Level ${l.n} is ready for its exam.' : '$left ${left == 1 ? 'lesson' : 'lessons'} until the Level ${l.n} exam.';
      case SessionKind.review:
        return 'Each review pushes these further out, so they take less and less of your time.';
    }
  }
}
