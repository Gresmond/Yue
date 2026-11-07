import 'dart:async';

import 'package:flutter/material.dart';

import '../state/app_state.dart';
import '../theme/app_theme.dart';
import 'common.dart';

/// One page of real Chinese, there from the first day. Characters you've met light
/// up in the accent colour and ones you hold strongly turn to full ink, so the page
/// slowly becomes readable. Each character sits in a square of its own.
class ThePage extends StatefulWidget {
  const ThePage({super.key, this.cell = 28, this.litBefore});

  final double cell;

  /// Characters already lit before now: the rest light one by one when it appears.
  final Set<String>? litBefore;

  @override
  State<ThePage> createState() => _ThePageState();
}

class _ThePageState extends State<ThePage> {
  Timer? _timer;
  late final Set<String>? _shown = widget.litBefore?.toSet();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final before = widget.litBefore;
    if (before == null || _timer != null) return;
    final fresh = AppScope.read(context).learnedChars.difference(before).toList();
    if (fresh.isEmpty) return;
    final gap = Duration(milliseconds: (1400 / fresh.length).clamp(30, 140).round());
    var i = 0;
    _timer = Timer.periodic(gap, (t) {
      if (i >= fresh.length) {
        t.cancel();
        return;
      }
      setState(() => _shown!.add(fresh[i++]));
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final p = context.palette;
    final text = state.course.page.map((id) => state.course.sentences[id]?.zh ?? '').join();
    final lit = _shown ?? state.learnedChars;
    final cell = widget.cell;
    final size = cell > 26 ? 22.0 : 16.0;
    return Wrap(
      children: [
        for (final c in text.split(''))
          SizedBox.square(
            dimension: cell,
            child: Center(
              child: AnimatedDefaultTextStyle(
                duration: context.themed(Motion.page),
                curve: Motion.morphCurve,
                style: zhStyle(
                  size,
                  !state.course.chars.containsKey(c)
                      ? p.inkMuted.withValues(alpha: 0.5)
                      : !lit.contains(c)
                      ? p.ink.withValues(alpha: 0.13)
                      : state.charStrong(c)
                      ? p.ink
                      : p.accent,
                  height: 1,
                ),
                child: Text(c),
              ),
            ),
          ),
      ],
    );
  }
}

/// How much of the page you can read.
double pageShare(AppState state) {
  final text = state.course.page.map((id) => state.course.sentences[id]?.zh ?? '').join().split('');
  final chars = text.where(state.course.chars.containsKey).toList();
  if (chars.isEmpty) return 0;
  return chars.where(state.learnedChars.contains).length / chars.length;
}
