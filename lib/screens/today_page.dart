import 'package:flutter/material.dart';

import '../state/app_state.dart';
import '../state/session.dart';
import '../theme/app_theme.dart';
import '../theme/pixels.dart';
import '../theme/tokens.dart';
import '../widgets/common.dart';
import '../widgets/the_page.dart';
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
      child: SingleChildScrollView(
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
      ),
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
    } else if (lesson != null) {
      final parts = [
        '${lesson.words.length} new words',
        if (lesson.radicals.isNotEmpty) '${lesson.radicals.length} building ${lesson.radicals.length == 1 ? 'block' : 'blocks'}',
        if (lesson.grammar.isNotEmpty) '${lesson.grammar.length} grammar ${lesson.grammar.length == 1 ? 'point' : 'points'}',
      ];
      title = today.lessons > 0 ? 'One more lesson?' : (state.learned.isEmpty ? 'Your first lesson' : 'Next lesson');
      detail = '${parts.join(', ')}. About 10 minutes.';
      action = today.lessons > 0 ? 'Keep going' : 'Start lesson';
      make = () => Session.forLesson(state, lesson);
    } else {
      title = 'Level ${state.level.n} exam';
      detail = 'Sentences you have never seen. Pass with 80% to move up.';
      action = 'Take the exam';
      make = () => Session.exam(state, state.level);
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
            PillButton(label: action, primary: true, onTap: () => onStart(make())),
          ],
        ],
      ),
    );
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
    return Tile(
      child: PixelColumn(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          TileHeader(title: 'Level ${l.n}', caption: '$done of $total lessons'),
          const SizedBox(height: 12),
          ProgressTrack(value: state.levelProgress(l)),
          const SizedBox(height: 12),
          Text(
            left == 0 ? 'Only the exam stands between you and Level ${l.n + 1}.' : '$left ${left == 1 ? 'lesson' : 'lessons'} from the exam, and from ${l.readable - state.readableSentences} more real sentences you could read.',
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
