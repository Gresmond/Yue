import 'dart:async';

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
      SessionKind.exam when passed => 'Band ${s.level!.band} passed',
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

    final Session? following = more > 0
        ? Session.review(state)
        : state.examReady
        ? Session.exam(state, state.level)
        : state.canLearnToday
        ? Session.forLesson(state, next!)
        : null;
    final followLabel = more > 0
        ? 'Review $more due'
        : state.examReady
        ? 'Take the Band ${state.level.band} exam'
        : 'Next lesson';

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
                        Stat(
                          value: PixelRow(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _RollUp(from: 0, to: (s.score * 100).round(), style: displayStyle(38, p.ink)),
                              Text('%', style: displayStyle(38, p.ink)),
                            ],
                          ),
                          label: exam ? 'Score' : 'First try',
                        ),
                        Stat(
                          value: _RollUp(from: before, to: after, style: displayStyle(38, p.ink)),
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
                          Text(reward.shownEn, style: bodyStyle(p.inkMuted)),
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
        if (passed) return 'You passed on sentences you had never seen, and all of Band ${s.level!.band} is behind you.';
        return 'You need ${(AppState.passMark * 100).round()}% and got ${(s.score * 100).round()}%. What you missed is back in your reviews, and the next exam uses different sentences.';
      case SessionKind.lesson:
        if (state.passed > s.passedBefore) return _clearedLine(state);
        final l = state.level;
        final left = l.lessons.length - state.doneInLevel(l);
        if (left > 0) return '$left ${left == 1 ? 'lesson' : 'lessons'} left in Level ${l.n}.';
        return 'That’s every lesson in Level ${l.n}. It clears once ${(AppState.holdShare * 100).round()}% of its words have held through a review.';
      case SessionKind.review:
        if (state.passed > s.passedBefore) return _clearedLine(state);
        return 'Each review pushes these further out, so they take less and less of your time.';
    }
  }

  String _clearedLine(AppState state) => 'Level ${state.passed} cleared: its words have held through your reviews.';
}

/// A number that starts at [from] and rolls to [to], once the page has faded in.
class _RollUp extends StatefulWidget {
  const _RollUp({required this.from, required this.to, required this.style});
  final int from, to;
  final TextStyle style;

  @override
  State<_RollUp> createState() => _RollUpState();
}

class _RollUpState extends State<_RollUp> {
  late int _value = widget.from;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(Motion.morph, () {
      if (mounted) setState(() => _value = widget.to);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RollingNumber(value: _value, duration: Motion.page, style: widget.style);
}
