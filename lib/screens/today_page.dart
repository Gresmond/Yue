import 'package:flutter/material.dart';

import '../state/app_state.dart';
import '../state/session.dart';
import '../theme/app_theme.dart';
import '../theme/pixels.dart';
import '../theme/tokens.dart';
import '../widgets/common.dart';
import '../widgets/the_page.dart';
import '../widgets/smooth_task_scroll.dart';
import '../widgets/tile.dart';
import 'shell.dart';

class TodayPage extends StatelessWidget {
  const TodayPage({super.key, required this.onStart, required this.onTab});
  final ValueChanged<Session> onStart;
  final ValueChanged<Section> onTab;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final wide = MediaQuery.sizeOf(context).width >= 980;
    final left = [_NextUp(onStart: onStart), const SizedBox(height: 16), _LevelCard(onTab: onTab), if (state.sentenceOfTheDay != null) ...[const SizedBox(height: 16), const _Sentence()]];
    final right = const _PageCard();
    return SizedBox.expand(
      child: SmoothTaskScroll(builder: (context, controller) => SingleChildScrollView(
      controller: controller,
      padding: const EdgeInsets.fromLTRB(32, 4, 32, 32),
      child: wide
          ? PixelRow(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 5, child: PixelColumn(crossAxisAlignment: CrossAxisAlignment.stretch, children: left)),
                const SizedBox(width: 16),
                Expanded(flex: 6, child: right),
              ],
            )
          : PixelColumn(crossAxisAlignment: CrossAxisAlignment.stretch, children: [...left, const SizedBox(height: 16), right]),
      )),
    );
  }
}

class _NextUp extends StatelessWidget {
  const _NextUp({required this.onStart});
  final ValueChanged<Session> onStart;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final state = AppScope.of(context);
    final due = state.dueCount;
    final lesson = state.nextLesson;
    final today = state.today;
    final String title, detail, action;
    var primary = true;
    final Session Function() make;
    if (due > 0) {
      final minutes = (due * 12 / 60).ceil();
      title = '$due to review';
      detail = 'About $minutes ${minutes == 1 ? 'minute' : 'minutes'}. These are the ones you were about to forget.';
      action = 'Start reviewing';
      make = () => Session.review(state);
    } else if (state.finishedCourse) {
      title = 'Course complete';
      detail = 'Every level passed. Read everything you can find.';
      action = '';
      make = () => Session.review(state);
    } else if (state.examReady) {
      title = 'Band ${state.level.band} exam';
      detail = 'Sentences you have never seen, from the whole band. Pass with 80% to move on.';
      action = 'Take the exam';
      make = () => Session.exam(state, state.level);
    } else if (lesson == null) {
      final l = state.level;
      final left = state.heldNeeded(l) - state.heldInLevel(l);
      title = 'Level ${l.n} is settling';
      detail = '$left more ${left == 1 ? 'word needs' : 'words need'} to hold through a review before ${state.course.isBandEnd(l) ? 'the band exam' : 'Level ${l.n + 1}'}. ${_nextReview(state)}';
      action = '';
      make = () => Session.review(state);
    } else if (!state.canLearnToday) {
      title = 'That’s enough new words';
      detail = state.minutesToday >= state.dailyMinutes
          ? 'You’ve reached your ${state.dailyMinutes} minutes for today. Letting these settle helps them stick.'
          : 'More new words now would push your reviews past ${state.dailyMinutes} minutes a day. New lessons return as your reviews get further apart.';
      action = 'One more anyway';
      primary = false;
      make = () => Session.forLesson(state, lesson);
    } else {
      final parts = [
        '${lesson.words.length} new words',
        if (lesson.grammar.isNotEmpty) '${lesson.grammar.length} grammar ${lesson.grammar.length == 1 ? 'point' : 'points'}',
      ];
      title = today.lessons > 0 ? 'One more lesson?' : (state.learned.isEmpty ? 'Your first lesson' : 'Next lesson');
      detail = '${parts.join(', ')}. About 10 minutes.';
      action = today.lessons > 0 ? 'Keep going' : 'Start lesson';
      make = () => Session.forLesson(state, lesson);
    }
    return Tile(
      child: PixelColumn(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text((today.complete ? 'Today is done' : 'Next up').toUpperCase(), style: capsLabel(today.complete ? p.accent : p.inkMuted)),
          const SizedBox(height: 8),
          Text(title, style: displayStyle(28, p.ink)),
          const SizedBox(height: 4),
          Text(detail, style: bodyStyle(p.inkMuted)),
          if (action.isNotEmpty) ...[
            const SizedBox(height: 16),
            PillButton(label: action, primary: primary, onTap: () => onStart(make())),
          ],
        ],
      ),
    );
  }

  String _nextReview(AppState state) {
    final at = state.nextDueMs;
    if (at == null) return '';
    final days = AppState.dayOf(DateTime.fromMillisecondsSinceEpoch(at)).difference(AppState.dayOf(state.now)).inDays;
    return days <= 0 ? 'More reviews come due later today.' : (days == 1 ? 'Your next reviews come tomorrow.' : 'Your next reviews come in $days days.');
  }
}

class _LevelCard extends StatelessWidget {
  const _LevelCard({required this.onTab});
  final ValueChanged<Section> onTab;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final state = AppScope.of(context);
    final l = state.level;
    final done = state.doneInLevel(l), total = l.lessons.length;
    final left = total - done;
    final held = state.heldInLevel(l), needed = state.heldNeeded(l);
    final goal = state.course.isBandEnd(l) ? 'the band exam' : 'Level ${l.n + 1}';
    return Tile(
      child: PixelColumn(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          TileHeader(title: 'Level ${l.n}', caption: '$done of $total lessons'),
          const SizedBox(height: 12),
          ProgressTrack(value: held / needed),
          const SizedBox(height: 12),
          Text(
            state.examReady
                ? 'Only the exam stands between you and ${l.n < state.course.levels.length ? 'Band ${l.band + 1}' : 'the end of the course'}.'
                : left == 0
                ? '$held of the $needed words needed have held through a review. Then, $goal.'
                : '$held of the $needed words needed have held through a review, with $left ${left == 1 ? 'lesson' : 'lessons'} to go before $goal.',
            style: bodyStyle(p.inkMuted),
          ),
        ],
      ),
    );
  }
}

class _Sentence extends StatelessWidget {
  const _Sentence();

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final s = AppScope.of(context).sentenceOfTheDay!;
    return Tile(
      child: PixelColumn(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('A REAL SENTENCE YOU CAN READ', style: capsLabel(p.inkMuted)),
          const SizedBox(height: 8),
          Text(s.zh, style: zhStyle(22, p.ink)),
          Text(s.en, style: bodyStyle(p.inkMuted, size: 14)),
        ],
      ),
    );
  }
}

class _PageCard extends StatelessWidget {
  const _PageCard();

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    return Tile(
      child: PixelColumn(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          TileHeader(title: 'The page', caption: '${(pageShare(state) * 100).round()}% lit'),
          const SizedBox(height: 4),
          Text('Real Chinese, written by native speakers. It fills in as you learn each character.', style: bodyStyle(context.palette.inkMuted, size: 14)),
          const SizedBox(height: 16),
          const ThePage(),
        ],
      ),
    );
  }
}
