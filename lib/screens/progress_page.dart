import 'package:flutter/material.dart';

import '../data/fsrs.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/pixels.dart';
import '../widgets/common.dart';
import '../widgets/rolling_number.dart';
import '../widgets/the_page.dart';
import '../widgets/tile.dart';

class ProgressPage extends StatelessWidget {
  const ProgressPage({super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final state = AppScope.of(context);
    final style = displayStyle(38, p.ink);
    final strong = state.cards.entries.where((e) => e.key.startsWith('wr:') && e.value.strong).length;
    return ListView(
      padding: const EdgeInsets.fromLTRB(32, 4, 32, 32),
      children: [
        Tile(
          child: Wrap(
            spacing: 40,
            runSpacing: 24,
            children: [
              Stat(value: RollingNumber(value: state.learnedChars.length, style: style), label: 'Characters', note: '${(state.characterCoverage * 100).round()}% of the library’s text'),
              Stat(value: RollingNumber(value: state.learned.length, style: style), label: 'Words', note: '$strong held strongly'),
              Stat(value: RollingNumber(value: state.readableSentences, style: style), label: 'Readable sentences', note: 'of ${state.course.totalSentences}'),
              Stat(value: RollingNumber(value: state.streak, style: style), label: 'Day streak', note: 'Best ${state.best}'),
              Stat(value: RollingNumber(value: state.passed, style: style), label: 'Levels passed', note: 'of ${state.course.levels.length}'),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const _Calendar(),
        const SizedBox(height: 16),
        const _Recall(),
        const SizedBox(height: 16),
        Tile(
          child: PixelColumn(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              TileHeader(title: 'The page', caption: '${(pageShare(state) * 100).round()}% lit'),
              const SizedBox(height: 16),
              const ThePage(),
            ],
          ),
        ),
      ],
    );
  }
}

/// Your recent weeks, as many as fit, a square a day: filled when the day counted.
class _Calendar extends StatelessWidget {
  const _Calendar();

  static const _cell = 12.0, _gap = 4.0;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final state = AppScope.of(context);
    final today = AppState.dayOf(state.now);
    return Tile(
      child: PixelColumn(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          TileHeader(title: 'Your days', caption: '${state.days.values.where((d) => d.complete).length} counted'),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, box) {
              final weeks = ((box.maxWidth + _gap) / (_cell + _gap)).floor();
              final monday = today.subtract(Duration(days: today.weekday - 1));
              return PixelRow(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  for (var w = weeks - 1; w >= 0; w--)
                    PixelColumn(
                      mainAxisSize: MainAxisSize.min,
                      spacing: _gap,
                      children: [
                        for (var day = 0; day < 7; day++) _square(p, state, DateTime(monday.year, monday.month, monday.day - w * 7 + day), today),
                      ],
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _square(Palette p, AppState state, DateTime d, DateTime today) {
    final row = state.days[AppState.key(d)];
    final future = d.isAfter(today);
    final colour = future ? p.empty.withValues(alpha: 0.35) : (row?.complete == true ? p.done : (row?.frozen == true ? p.other : p.empty));
    return PixelTooltip(
      message: future ? '' : '${d.day}/${d.month}${row == null ? '' : '  ·  ${row.reviews} reviews, ${row.lessons} lessons'}${row?.frozen == true ? '  ·  freeze used' : ''}',
      child: Container(width: _cell, height: _cell, decoration: BoxDecoration(color: colour, borderRadius: BorderRadius.circular(4))),
    );
  }
}

/// How often you've actually recalled things, and what's coming due.
class _Recall extends StatelessWidget {
  const _Recall();

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final state = AppScope.of(context);
    final since = state.nowMs - 30 * 86400000;
    final reviews = state.store.recentReviews(since);
    final right = reviews.where((r) => r.$2 > Rating.again.value).length;
    final tomorrowEnd = state.nowMs + 86400000;
    final weekEnd = state.nowMs + 7 * 86400000;
    final dueTomorrow = state.cards.values.where((m) => m.dueMs <= tomorrowEnd).length;
    final dueWeek = state.cards.values.where((m) => m.dueMs <= weekEnd).length;
    final share = reviews.isEmpty ? 0.0 : right / reviews.length;
    return Tile(
      child: PixelColumn(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          const TileHeader(title: 'Memory'),
          const SizedBox(height: 4),
          Text(
            reviews.isEmpty
                ? 'Your recall rate appears here after your first reviews. The scheduler aims for about 90%.'
                : 'You recalled ${(share * 100).round()}% of ${reviews.length} answers in the last 30 days. The scheduler aims for about 90%, because easier would waste your time and harder would be discouraging.',
            style: bodyStyle(p.inkMuted),
          ),
          const SizedBox(height: 12),
          ProgressTrack(value: share),
          const SizedBox(height: 12),
          Text('$dueTomorrow due by tomorrow  ·  $dueWeek due within a week', style: bodyStyle(p.inkMuted, size: 14)),
        ],
      ),
    );
  }
}
