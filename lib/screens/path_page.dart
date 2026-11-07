import 'package:flutter/material.dart';

import '../data/curriculum.dart';
import '../state/app_state.dart';
import '../state/session.dart';
import '../theme/app_theme.dart';
import '../theme/pixels.dart';
import '../theme/tokens.dart';
import '../widgets/common.dart';
import '../widgets/feedback.dart';
import '../widgets/smooth_task_scroll.dart';
import '../widgets/tile.dart';

/// The whole road: bands, what each lets you do, and every level along the way.
class PathPage extends StatelessWidget {
  const PathPage({super.key, required this.onStart});
  final ValueChanged<Session> onStart;

  /// Published graded readers worth buying once you reach them, by words known.
  /// Sizes are from memory of the series and approximate.
  static const _readers = {300: 'Chinese Breeze, level 1', 500: 'Chinese Breeze, level 2', 750: 'Chinese Breeze, level 3', 1100: 'Chinese Breeze, level 4'};

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final state = AppScope.of(context);
    final bands = <int, List<Level>>{};
    for (final l in state.course.levels) {
      (bands[l.band] ??= []).add(l);
    }
    final reader = _readers.entries.where((e) => state.learned.length < e.key).firstOrNull;
    return SmoothTaskScroll(builder: (context, controller) => ListView(
      controller: controller,
      padding: const EdgeInsets.fromLTRB(32, 4, 32, 32),
      children: [
        if (reader != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Tile(
              child: PixelColumn(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('YOUR NEXT REAL BOOK', style: capsLabel(p.inkMuted)),
                  const SizedBox(height: 8),
                  Text(reader.value, style: displayStyle(22, p.ink)),
                  const SizedBox(height: 4),
                  Text('A published story for learners, at about ${reader.key} words. You know ${state.learned.length}.', style: bodyStyle(p.inkMuted)),
                  const SizedBox(height: 12),
                  ProgressTrack(value: state.learned.length / reader.key),
                ],
              ),
            ),
          ),
        for (final band in bands.entries) ...[
          _BandCard(band: band.key, levels: band.value, onStart: onStart),
          const SizedBox(height: 16),
        ],
      ],
    ));
  }
}

class _BandCard extends StatelessWidget {
  const _BandCard({required this.band, required this.levels, required this.onStart});
  final int band;
  final List<Level> levels;
  final ValueChanged<Session> onStart;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final state = AppScope.of(context);
    final words = levels.expand((l) => l.lessons).expand((l) => l.words).length;
    final current = state.level;
    final eta = current.band == band ? state.daysToBandEnd(band) : null;
    return Tile(
      child: PixelColumn(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          TileHeader(title: 'Band $band', caption: '$words words', trailingAtEnd: true, trailing: eta == null ? null : Text('about $eta days at your pace', style: bodyStyle(p.inkMuted, size: 14))),
          const SizedBox(height: 4),
          Text(Curriculum.bandGoals[band] ?? '', style: bodyStyle(p.inkMuted)),
          const SizedBox(height: 16),
          for (final l in levels) ...[
            _LevelRow(level: l, onStart: onStart),
            if (l != levels.last) const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}

class _LevelRow extends StatelessWidget {
  const _LevelRow({required this.level, required this.onStart});
  final Level level;
  final ValueChanged<Session> onStart;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final state = AppScope.of(context);
    final passed = level.n <= state.passed;
    final current = level.n == state.level.n && !passed;
    final bandEnd = state.course.isBandEnd(level);
    return PixelRow(
      children: [
        SizedBox(
          width: 88,
          child: Text('Level ${level.n}', style: bodyStyle(passed || current ? p.ink : p.inkMuted, weight: FontWeight.w600, height: 1.2)),
        ),
        Expanded(
          child: Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              for (final l in level.lessons)
                _LessonDot(
                  lesson: l,
                  state: state.lessonDone(l) || passed ? _Dot.done : (current && state.nextLesson == l ? _Dot.next : _Dot.locked),
                  onTap: current && state.nextLesson == l ? () => onStart(Session.forLesson(state, l)) : (state.lessonDone(l) ? () => onStart(Session.forLesson(state, l)) : null),
                ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        if (passed)
          const CapsChip('Passed')
        else if (current && state.examReady)
          PillButton(label: 'Take exam', primary: true, onTap: () => onStart(Session.exam(state, level)))
        else if (current)
          Text('${state.heldInLevel(level)} of ${state.heldNeeded(level)} held', style: bodyStyle(p.inkMuted, size: 12))
        else if (bandEnd)
          Text('Band exam', style: bodyStyle(p.inkMuted, size: 12)),
      ],
    );
  }
}

enum _Dot { done, next, locked }

class _LessonDot extends StatelessWidget {
  const _LessonDot({required this.lesson, required this.state, required this.onTap});
  final Lesson lesson;
  final _Dot state;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return PixelTooltip(
      message: lesson.words.join('  '),
      child: Pressable(
        onTap: onTap,
        builder: (hover) => AnimatedContainer(
          duration: context.themed(Motion.hover),
          curve: Motion.hoverCurve,
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            color: switch (state) {
              _Dot.done => p.done,
              _Dot.next => hover ? p.done : p.today,
              _Dot.locked => p.empty,
            },
            borderRadius: BorderRadius.circular(4),
            border: state == _Dot.locked ? Border.all(color: p.borderSoft) : null,
          ),
        ),
      ),
    );
  }
}
