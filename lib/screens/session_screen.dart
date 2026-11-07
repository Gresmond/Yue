import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/curriculum.dart';
import '../data/fsrs.dart';
import '../state/app_state.dart';
import '../state/session.dart';
import '../theme/app_theme.dart';
import '../theme/pixels.dart';
import '../theme/tokens.dart';
import '../widgets/appear.dart';
import '../widgets/common.dart';
import '../widgets/fade_through.dart';
import '../widgets/feedback.dart';
import '../widgets/glide_wrap.dart';
import '../widgets/hover_fill.dart';
import '../widgets/task_motion.dart';
import '../widgets/tile.dart';
import 'session_end.dart';

/// A lesson, a review or an exam, filling the window.
class SessionScreen extends StatefulWidget {
  const SessionScreen({super.key, required this.session, required this.onClose, required this.onAgain});

  final Session session;
  final VoidCallback onClose;

  /// Starts whatever should follow: more reviews, the next lesson, an exam.
  final ValueChanged<Session> onAgain;

  @override
  State<SessionScreen> createState() => _SessionScreenState();
}

class _SessionScreenState extends State<SessionScreen> {
  Session get s => widget.session;

  void _advance() => setState(s.next);

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 20, 32, 24),
      child: PixelColumn(
        children: [
          PixelRow(
            children: [
              HeaderIconButton(icon: Icons.close_rounded, tooltip: 'Leave (your answers so far are kept)', onPressed: widget.onClose),
              const SizedBox(width: 12),
              Expanded(child: ProgressTrack(value: s.finished ? 1 : s.progress)),
              const SizedBox(width: 12),
              Text(_title, style: capsLabel(p.inkMuted)),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: FadeThrough(
              duration: Motion.morph,
              child: s.finished
                  ? SessionEnd(key: const ValueKey('end'), session: s, onClose: widget.onClose, onNext: widget.onAgain)
                  : KeyedSubtree(key: ValueKey(s.attempt), child: _stepView()),
            ),
          ),
        ],
      ),
    );
  }

  String get _title => switch (s.kind) {
    SessionKind.review => 'REVIEW',
    SessionKind.lesson => 'LESSON ${s.lesson!.index + 1}',
    SessionKind.exam => 'BAND ${s.level!.band} EXAM',
  };

  Widget _stepView() {
    final exam = s.kind == SessionKind.exam;
    void rate(Rating r, int ms) => s.answer(r, takenMs: ms);
    return switch (s.current) {
      TeachWord(:final word, :final example) => _TeachWordView(word: word, example: example, onNext: _advance),
      TeachGrammar(:final grammar) => _TeachGrammarView(grammar: grammar, onNext: _advance),
      final MatchPairs step => _MatchView(step: step, onAnswer: (word, correct, ms) => s.answerMatch(word, correct: correct, takenMs: ms), onNext: _advance),
      ExamRead(:final sentence, :final options) => _ChooseView(
        prompt: Text(sentence.zh, textAlign: TextAlign.center, style: zhStyle(28, context.palette.ink)),
        options: options,
        answer: sentence.en,
        quiet: true,
        onRated: rate,
        onNext: _advance,
      ),
      RecallWord(:final word) => _RecallView(
        prompt: _HanziPrompt(word.w),
        answer: _WordAnswer(word),
        onRated: rate,
        onNext: _advance,
      ),
      ReadSentence(:final sentence) => _ReadSentenceView(sentence: sentence, onRated: rate, onNext: _advance),
      WriteWord(:final word, :final options) => _WriteView(word: word, options: options, quiet: exam, onRated: rate, onNext: _advance),
      BuildSentence(:final sentence, :final tiles) => _BuildView(sentence: sentence, tiles: tiles, quiet: exam, onRated: rate, onNext: _advance),
    };
  }
}

/// The card a step sits on, centred, with its actions beneath. It takes the keyboard
/// for itself: autofocus alone wouldn't, as the last step still holds focus as it fades.
class _StepCard extends StatefulWidget {
  const _StepCard({required this.child, this.actions = const [], this.actionsKey, this.onKey});

  final Widget child;
  final List<Widget> actions;

  /// What the actions are for: on a change they fade through. By default, how many there are.
  final Object? actionsKey;
  final KeyEventResult Function(LogicalKeyboardKey)? onKey;

  @override
  State<_StepCard> createState() => _StepCardState();
}

class _StepCardState extends State<_StepCard> {
  final _focus = FocusNode();

  void _takeFocus() {
    if (widget.onKey == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void initState() {
    super.initState();
    _takeFocus();
  }

  @override
  void didUpdateWidget(_StepCard old) {
    super.didUpdateWidget(old);
    if (old.onKey == null) _takeFocus();
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focus,
      onKeyEvent: (node, event) {
        final onKey = widget.onKey;
        return onKey != null && event is KeyDownEvent ? onKey(event.logicalKey) : KeyEventResult.ignored;
      },
      child: LayoutBuilder(
        builder: (context, box) => SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: box.maxHeight),
            child: Align(
              alignment: const PixelCentre(),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: PixelColumn(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Tile(padding: const EdgeInsets.all(32), child: widget.child),
                    FadeThrough(
                      duration: Motion.morph,
                      child: KeyedSubtree(
                        key: ValueKey(widget.actionsKey ?? widget.actions.length),
                        child: widget.actions.isEmpty
                            ? const SizedBox(width: double.infinity)
                            : Padding(
                                padding: const EdgeInsets.only(top: 16),
                                child: Wrap(alignment: WrapAlignment.center, spacing: 12, runSpacing: 12, children: widget.actions),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

bool _isGo(LogicalKeyboardKey k) => k == LogicalKeyboardKey.space || k == LogicalKeyboardKey.enter || k == LogicalKeyboardKey.numpadEnter;

const _digits = [
  LogicalKeyboardKey.digit1, LogicalKeyboardKey.digit2, LogicalKeyboardKey.digit3, LogicalKeyboardKey.digit4,
  LogicalKeyboardKey.digit5, LogicalKeyboardKey.digit6, LogicalKeyboardKey.digit7, LogicalKeyboardKey.digit8, LogicalKeyboardKey.digit9,
];

class _HanziPrompt extends StatelessWidget {
  const _HanziPrompt(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Center(
    child: Text(text, textAlign: TextAlign.center, style: zhStyle(88, context.palette.ink, height: 1.15)),
  );
}

class _WordAnswer extends StatelessWidget {
  const _WordAnswer(this.word);
  final Word word;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return PixelColumn(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(word.py, style: bodyStyle(p.accent, size: 18, weight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text(word.en, textAlign: TextAlign.center, style: displayStyle(22, p.ink)),
      ],
    );
  }
}

class _Continue extends StatelessWidget {
  const _Continue({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => PillButton(label: 'Continue', primary: true, hint: 'space', onTap: onTap);
}

// ---- Teaching.

class _TeachWordView extends StatefulWidget {
  const _TeachWordView({required this.word, required this.example, required this.onNext});
  final Word word;
  final Sentence? example;
  final VoidCallback onNext;

  @override
  State<_TeachWordView> createState() => _TeachWordViewState();
}

class _TeachWordViewState extends State<_TeachWordView> {
  int? _selected;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final word = widget.word;
    final example = widget.example;
    final onNext = widget.onNext;
    return _StepCard(
      onKey: (k) {
        if (!_isGo(k)) return KeyEventResult.ignored;
        onNext();
        return KeyEventResult.handled;
      },
      actions: [_Continue(onTap: onNext)],
      child: PixelColumn(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(child: Text('NEW WORD', style: capsLabel(p.inkMuted))),
          const SizedBox(height: 8),
          _HanziPrompt(word.w),
          _WordAnswer(word),
          if (word.senses.length > 1) ...[
            const SizedBox(height: 8),
            Text(word.senses.take(3).join('  ·  '), textAlign: TextAlign.center, style: bodyStyle(p.inkMuted, size: 14)),
          ],
          if (word.taiwan case final taiwan?) ...[
            const SizedBox(height: 4),
            Text('In Taiwan: $taiwan', textAlign: TextAlign.center, style: bodyStyle(p.inkMuted, size: 14)),
          ],
          const SizedBox(height: 20),
          WordBreakdown(word: word),
          if (example != null) ...[
            const SizedBox(height: 20),
            Divider(height: 1, color: p.borderSoft),
            const SizedBox(height: 16),
            TappableText(toks: example.toks, size: 22, isKnown: (_) => true, selected: _selected, onSelect: (i) => setState(() => _selected = i)),
            GlossLine(token: _selected == null ? null : example.toks[_selected!]),
            Text(example.shownEn, style: bodyStyle(p.inkMuted, size: 14)),
          ],
        ],
      ),
    );
  }
}

class _TeachGrammarView extends StatelessWidget {
  const _TeachGrammarView({required this.grammar, required this.onNext});
  final Grammar grammar;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final course = AppScope.read(context).course;
    final examples = grammar.examples.map((id) => course.sentences[id]).nonNulls.take(3);
    return _StepCard(
      onKey: (k) {
        if (!_isGo(k)) return KeyEventResult.ignored;
        onNext();
        return KeyEventResult.handled;
      },
      actions: [_Continue(onTap: onNext)],
      child: PixelColumn(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('GRAMMAR', style: capsLabel(p.inkMuted)),
          const SizedBox(height: 8),
          Text(grammar.title, style: displayStyle(28, p.ink).copyWith(fontFamilyFallback: Fonts.zhFallback)),
          const SizedBox(height: 4),
          Text(grammar.short, style: bodyStyle(p.accent, weight: FontWeight.w600)),
          const SizedBox(height: 12),
          Text(grammar.body, style: bodyStyle(p.ink)),
          const SizedBox(height: 20),
          for (final s in examples) ...[
            Text(s.zh, style: zhStyle(22, p.ink)),
            Text(s.en, style: bodyStyle(p.inkMuted, size: 14)),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}

// ---- Answering.

mixin _Timed<T extends StatefulWidget> on State<T> {
  final _clock = Stopwatch()..start();
  int get taken => _clock.elapsedMilliseconds;
}

class _ChooseView extends StatefulWidget {
  const _ChooseView({required this.prompt, required this.options, required this.answer, this.quiet = false, required this.onRated, required this.onNext});

  final Widget prompt;
  final List<String> options;
  final String answer;

  /// An exam: no telling what was right.
  final bool quiet;
  final void Function(Rating, int) onRated;
  final VoidCallback onNext;

  @override
  State<_ChooseView> createState() => _ChooseViewState();
}

class _ChooseViewState extends State<_ChooseView> with _Timed {
  String? _picked;

  void _pick(String option) {
    if (_picked != null) return;
    setState(() => _picked = option);
    widget.onRated(option == widget.answer ? Rating.good : Rating.again, taken);
    if (widget.quiet) {
      widget.onNext();
    } else if (option == widget.answer) {
      Timer(const Duration(milliseconds: 500), () {
        if (mounted) widget.onNext();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final wrongChosen = _picked != null && _picked != widget.answer;
    return _StepCard(
      onKey: (k) {
        if (_picked != null) {
          if (wrongChosen && _isGo(k)) {
            widget.onNext();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        }
        final i = _digits.indexOf(k);
        if (i < 0 || i >= widget.options.length) return KeyEventResult.ignored;
        _pick(widget.options[i]);
        return KeyEventResult.handled;
      },
      actions: [if (wrongChosen) _Continue(onTap: widget.onNext)],
      child: PixelColumn(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          widget.prompt,
          const SizedBox(height: 20),
          for (final (i, o) in widget.options.indexed) ...[
            _OptionRow(
              label: o,
              number: i + 1,
              state: _picked == null
                  ? _OptionState.open
                  : o == widget.answer
                  ? _OptionState.right
                  : o == _picked
                  ? _OptionState.wrong
                  : _OptionState.other,
              onTap: () => _pick(o),
            ),
            if (i < widget.options.length - 1) const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}

enum _OptionState { open, right, wrong, other }

class _OptionRow extends StatelessWidget {
  const _OptionRow({required this.label, required this.number, required this.state, required this.onTap});

  final String label;
  final int number;
  final _OptionState state;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Hoverable(
      onTap: state == _OptionState.open ? onTap : null,
      builder: (hover) => AnimatedContainer(
        duration: context.themed(state == _OptionState.open ? Motion.hover : Motion.click),
        curve: Motion.clickCurve,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: switch (state) {
            _OptionState.right => Color.lerp(p.tile, p.done, 0.35),
            _OptionState.wrong => Color.lerp(p.tile, p.missed, 0.35),
            _ => hover ? p.empty : p.empty.withValues(alpha: 0),
          },
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: p.border),
        ),
        child: PixelRow(
          children: [
            SizedBox(
              width: 24,
              child: VerdictMark(
                right: switch (state) { _OptionState.right => true, _OptionState.wrong => false, _ => null },
                child: Text('$number', style: TextStyle(fontFamily: Fonts.taskTime, fontSize: 12, color: p.inkMuted)),
              ),
            ),
            Expanded(
              child: Text(label, style: bodyStyle(state == _OptionState.other ? p.inkMuted : p.ink, weight: FontWeight.w500, height: 1.3)),
            ),
          ],
        ),
      ),
    );
  }
}

/// One card being dragged in a match: a word or a meaning.
class _MatchDrag {
  const _MatchDrag({this.word, this.meaning});
  final Word? word;
  final int? meaning;
}

/// Characters on the left, meanings on the right: drag either onto its partner.
/// A right match glides the meaning beside its character. A wrong one is a
/// mistake that stands, as in a test: both cards show it for a moment, then the
/// real meaning comes beside the word, and that pair is out of play. Let go
/// anywhere else and nothing happens, as in Eclipse. The digits pick too,
/// counting down the left and then the right.
class _MatchView extends StatefulWidget {
  const _MatchView({required this.step, required this.onAnswer, required this.onNext});
  final MatchPairs step;
  final void Function(Word, bool, int) onAnswer;
  final VoidCallback onNext;

  @override
  State<_MatchView> createState() => _MatchViewState();
}

class _MatchViewState extends State<_MatchView> with _Timed {
  /// How long a mistake shows before its answer comes.
  static const _hold = Duration(milliseconds: 600);

  /// Long enough for the last meaning to land, and be seen.
  static const _landed = Duration(milliseconds: 500);

  /// Which meaning is on each row, by its place in the step's meanings.
  late final _rows = List.generate(widget.step.words.length, (i) => i);
  final _matched = <Word>{}, _locked = <Word>{};

  /// What the digits have picked so far.
  Word? _word;
  int? _meaning;

  /// The mistake being shown. Nothing can be moved until it's gone.
  Word? _wrongWord;
  int? _wrongMeaning;
  _MatchDrag? _dragged;
  Timer? _settle;

  bool get _holding => _wrongWord != null;
  bool get _finished => _matched.length + _locked.length == widget.step.words.length;
  bool get _missedAny => _locked.isNotEmpty;
  bool _settled(Word w) => _matched.contains(w) || _locked.contains(w);
  int _meaningOf(Word w) => widget.step.meanings.indexOf(w.en);
  Word _owner(int meaning) => widget.step.words.firstWhere((w) => w.en == widget.step.meanings[meaning]);

  @override
  void dispose() {
    _settle?.cancel();
    super.dispose();
  }

  void _pickWord(Word w) {
    if (_holding || _settled(w)) return;
    setState(() => _word = w);
    _tryPicked();
  }

  void _pickMeaning(int m) {
    if (_holding || _settled(_owner(m))) return;
    setState(() => _meaning = m);
    _tryPicked();
  }

  void _tryPicked() {
    final word = _word, meaning = _meaning;
    if (word != null && meaning != null) _submit(word, meaning);
  }

  void _submit(Word word, int meaning) {
    if (_holding || _settled(word)) return;
    final correct = word.en == widget.step.meanings[meaning];
    widget.onAnswer(word, correct, taken);
    setState(() {
      _word = _meaning = null;
      if (correct) {
        _matched.add(word);
        _bringBeside(word);
      } else {
        _wrongWord = word;
        _wrongMeaning = meaning;
      }
    });
    if (correct) return _maybeFinish();
    _settle = Timer(_hold, () {
      if (!mounted) return;
      setState(() {
        _wrongWord = _wrongMeaning = null;
        _locked.add(word);
        _bringBeside(word);
      });
      _maybeFinish();
    });
  }

  /// Swaps [word]'s meaning onto its row. Whatever was there can't be settled,
  /// as settled meanings are all on their own words' rows.
  void _bringBeside(Word word) {
    final row = widget.step.words.indexOf(word), from = _rows.indexOf(_meaningOf(word));
    final there = _rows[row];
    _rows[row] = _rows[from];
    _rows[from] = there;
  }

  /// With nothing missed the step moves itself on. A miss waits for Continue.
  void _maybeFinish() {
    if (!_finished || _missedAny) return;
    _settle?.cancel();
    _settle = Timer(_landed, () {
      if (mounted) widget.onNext();
    });
  }

  double _rowHeight(BuildContext context, double wordWidth, double meaningWidth) {
    final p = context.palette;
    final scaler = MediaQuery.textScalerOf(context);
    const across = 64.0, down = 24.0, least = 60.0;
    double measure(String text, TextStyle style, double width) {
      final painter = TextPainter(text: TextSpan(text: text, style: style), textDirection: TextDirection.ltr, textScaler: scaler)
        ..layout(maxWidth: width - across);
      final height = painter.height;
      painter.dispose();
      return height + down;
    }

    final step = widget.step;
    var tallest = least;
    for (final w in step.words) {
      final h = measure(w.w, zhStyle(28, p.ink, height: 1.2), wordWidth);
      if (h > tallest) tallest = h;
    }
    for (final m in step.meanings) {
      final h = measure(m, bodyStyle(p.ink, weight: FontWeight.w500, height: 1.3), meaningWidth);
      if (h > tallest) tallest = h;
    }
    return tallest.ceilToDouble();
  }

  bool _isDragged(_MatchDrag d) => _dragged != null && _dragged!.word == d.word && _dragged!.meaning == d.meaning;

  Widget _card({
    required _MatchDrag data,
    required int number,
    required bool selected,
    required bool right,
    required bool wrong,
    required double width,
    required double height,
    required Widget label,
  }) {
    final p = context.palette;
    final open = !_holding && !right && !wrong;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: SizedBox(
        height: height,
        child: DragTarget<_MatchDrag>(
          onWillAcceptWithDetails: (d) => open && (data.word != null ? d.data.meaning != null : d.data.word != null),
          onAcceptWithDetails: (d) => _submit(data.word ?? d.data.word!, data.meaning ?? d.data.meaning!),
          builder: (context, candidates, _) => Draggable<_MatchDrag>(
            data: data,
            maxSimultaneousDrags: open ? 1 : 0,
            onDragStarted: () => setState(() => _dragged = data),
            onDragEnd: (_) => setState(() => _dragged = null),
            feedback: Material(
              color: p.tile.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                width: width,
                height: height,
                child: Padding(
                  padding: const EdgeInsets.only(left: 40, right: 16),
                  child: Align(alignment: Alignment.centerLeft, child: label),
                ),
              ),
            ),
            child: AnimatedOpacity(
              opacity: _isDragged(data) ? 0.3 : 1,
              duration: Motion.hover,
              curve: Motion.hoverCurve,
              child: _MatchTile(number: number, selected: selected, right: right, wrong: wrong, over: candidates.isNotEmpty, grabbable: open, child: label),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final step = widget.step;
    final n = step.words.length;
    return _StepCard(
      onKey: (k) {
        if (_finished && _missedAny) {
          if (!_isGo(k)) return KeyEventResult.ignored;
          widget.onNext();
          return KeyEventResult.handled;
        }
        final i = _digits.indexOf(k);
        if (i < 0 || i >= n * 2) return KeyEventResult.ignored;
        i < n ? _pickWord(step.words[i]) : _pickMeaning(_rows[i - n]);
        return KeyEventResult.handled;
      },
      actions: [if (_finished && _missedAny) _Continue(onTap: widget.onNext)],
      child: PixelColumn(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(child: Text('MATCH THE PAIRS', style: capsLabel(p.inkMuted))),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, box) {
              final wordWidth = (box.maxWidth - 12) * 2 / 5, meaningWidth = (box.maxWidth - 12) * 3 / 5;
              final height = _rowHeight(context, wordWidth, meaningWidth);
              return PixelRow(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 2,
                    child: PixelColumn(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final (row, word) in step.words.indexed)
                          _card(
                            data: _MatchDrag(word: word),
                            number: row + 1,
                            selected: _word == word,
                            right: _matched.contains(word),
                            wrong: _locked.contains(word) || _wrongWord == word,
                            width: wordWidth,
                            height: height,
                            label: Text(word.w, style: zhStyle(28, p.ink, height: 1.2)),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 3,
                    child: GlidingColumn(
                      children: [
                        for (final (row, meaning) in _rows.indexed)
                          KeyedSubtree(
                            key: ValueKey(meaning),
                            child: _card(
                              data: _MatchDrag(meaning: meaning),
                              number: n + row + 1,
                              selected: _meaning == meaning,
                              right: _matched.contains(_owner(meaning)),
                              wrong: _locked.contains(_owner(meaning)) || _wrongMeaning == meaning,
                              width: meaningWidth,
                              height: height,
                              label: Text(step.meanings[meaning], style: bodyStyle(p.ink, weight: FontWeight.w500, height: 1.3)),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _MatchTile extends StatelessWidget {
  const _MatchTile({required this.number, required this.selected, required this.right, required this.wrong, required this.over, required this.grabbable, required this.child});
  final int number;
  final bool selected, right, wrong, over, grabbable;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Hoverable(
      cursor: grabbable ? SystemMouseCursors.grab : MouseCursor.defer,
      behavior: HitTestBehavior.opaque,
      builder: (hover) => AnimatedContainer(
        duration: context.themed(Motion.click),
        curve: Motion.clickCurve,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        alignment: Alignment.centerLeft,
        decoration: BoxDecoration(
          color: right
              ? Color.lerp(p.tile, p.done, 0.35)
              : wrong
              ? Color.lerp(p.tile, p.missed, 0.35)
              : over
              // As a day a task is dragged over lights up.
              ? p.accent.withValues(alpha: 0.16)
              : selected
              ? p.empty
              : p.empty.withValues(alpha: hover && grabbable ? 1 : 0),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: selected ? p.accent : p.border, width: selected ? 2 : 1),
        ),
        child: PixelRow(
          children: [
            SizedBox(
              width: 24,
              child: VerdictMark(
                right: right ? true : (wrong ? false : null),
                child: Text('$number', style: TextStyle(fontFamily: Fonts.taskTime, fontSize: 12, color: p.inkMuted)),
              ),
            ),
            Expanded(child: child),
          ],
        ),
      ),
    );
  }
}

class _RecallView extends StatefulWidget {
  const _RecallView({required this.prompt, required this.answer, required this.onRated, required this.onNext});

  final Widget prompt, answer;
  final void Function(Rating, int) onRated;
  final VoidCallback onNext;

  @override
  State<_RecallView> createState() => _RecallViewState();
}

class _RecallViewState extends State<_RecallView> with _Timed {
  bool _shown = false;

  void _rate(Rating r) {
    widget.onRated(r, taken);
    widget.onNext();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return _StepCard(
      onKey: (k) {
        if (!_shown) {
          if (!_isGo(k)) return KeyEventResult.ignored;
          setState(() => _shown = true);
          return KeyEventResult.handled;
        }
        final r = switch (_digits.indexOf(k)) { 0 => Rating.again, 1 => Rating.hard, 2 => Rating.good, _ => _isGo(k) ? Rating.good : null };
        if (r == null) return KeyEventResult.ignored;
        _rate(r);
        return KeyEventResult.handled;
      },
      actions: _shown
          ? [
              PillButton(label: 'Forgot', hint: '1', tone: p.missed, onTap: () => _rate(Rating.again)),
              PillButton(label: 'Hard', hint: '2', onTap: () => _rate(Rating.hard)),
              PillButton(label: 'Knew it', hint: '3', primary: true, onTap: () => _rate(Rating.good)),
            ]
          : [PillButton(label: 'Show answer', hint: 'space', primary: true, onTap: () => setState(() => _shown = true))],
      child: PixelColumn(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(child: Text('WHAT DOES THIS MEAN?', style: capsLabel(p.inkMuted))),
          const SizedBox(height: 8),
          widget.prompt,
          const SizedBox(height: 8),
          _Reveal(shown: _shown, child: Center(child: widget.answer)),
        ],
      ),
    );
  }
}

/// Keeps its room and fades its child in, so nothing above moves on reveal.
class _Reveal extends StatelessWidget {
  const _Reveal({required this.shown, required this.child});
  final bool shown;
  final Widget child;

  @override
  Widget build(BuildContext context) => AnimatedOpacity(opacity: shown ? 1 : 0, duration: Motion.click, curve: Motion.clickCurve, child: child);
}

class _ReadSentenceView extends StatefulWidget {
  const _ReadSentenceView({required this.sentence, required this.onRated, required this.onNext});
  final Sentence sentence;
  final void Function(Rating, int) onRated;
  final VoidCallback onNext;

  @override
  State<_ReadSentenceView> createState() => _ReadSentenceViewState();
}

class _ReadSentenceViewState extends State<_ReadSentenceView> with _Timed {
  bool _shown = false;
  int? _selected;

  void _rate(Rating r) {
    widget.onRated(r, taken);
    widget.onNext();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final s = widget.sentence;
    return _StepCard(
      onKey: (k) {
        if (!_shown) {
          if (!_isGo(k)) return KeyEventResult.ignored;
          setState(() => _shown = true);
          return KeyEventResult.handled;
        }
        final r = switch (_digits.indexOf(k)) { 0 => Rating.again, 1 => Rating.hard, 2 => Rating.good, _ => _isGo(k) ? Rating.good : null };
        if (r == null) return KeyEventResult.ignored;
        _rate(r);
        return KeyEventResult.handled;
      },
      actions: _shown
          ? [
              PillButton(label: 'Didn’t get it', hint: '1', tone: p.missed, onTap: () => _rate(Rating.again)),
              PillButton(label: 'Partly', hint: '2', onTap: () => _rate(Rating.hard)),
              PillButton(label: 'Understood', hint: '3', primary: true, onTap: () => _rate(Rating.good)),
            ]
          : [PillButton(label: 'Show meaning', hint: 'space', primary: true, onTap: () => setState(() => _shown = true))],
      child: PixelColumn(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(child: Text('READ THIS', style: capsLabel(p.inkMuted))),
          const SizedBox(height: 16),
          TappableText(toks: s.toks, size: 28, selected: _selected, alignCentre: true, onSelect: (i) => setState(() => _selected = i)),
          const SizedBox(height: 12),
          GlossLine(token: _selected == null ? null : s.toks[_selected!]),
          const SizedBox(height: 12),
          _Reveal(shown: _shown, child: Text(s.shownEn, textAlign: TextAlign.center, style: displayStyle(18, p.ink))),
        ],
      ),
    );
  }
}

class _WriteView extends StatefulWidget {
  const _WriteView({required this.word, required this.options, this.quiet = false, required this.onRated, required this.onNext});
  final Word word;
  final List<Word> options;
  final bool quiet;
  final void Function(Rating, int) onRated;
  final VoidCallback onNext;

  @override
  State<_WriteView> createState() => _WriteViewState();
}

enum _WriteStage { typing, picking, revealed, done }

/// One go at the pinyin, as in a test: a miss shows the answer at once, and the
/// word comes round again later.
class _WriteViewState extends State<_WriteView> with _Timed {
  final _field = TextEditingController();
  final _focus = FocusNode();
  var _stage = _WriteStage.typing;
  String? _picked;

  /// What was typed, when it was wrong.
  String? _attempt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _field.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _submit() {
    if (_field.text.trim().isEmpty) return;
    if (pinyinMatches(_field.text, widget.word.py)) {
      setState(() => _stage = _WriteStage.picking);
      return;
    }
    widget.onRated(Rating.again, taken);
    if (widget.quiet) return widget.onNext();
    setState(() {
      _attempt = _field.text.trim();
      _stage = _WriteStage.revealed;
    });
  }

  void _pick(Word w) {
    if (_stage != _WriteStage.picking) return;
    _picked = w.w;
    final right = w.w == widget.word.w;
    widget.onRated(right ? Rating.good : Rating.again, taken);
    if (widget.quiet) return widget.onNext();
    setState(() => _stage = right ? _WriteStage.done : _WriteStage.revealed);
    if (right) {
      Timer(const Duration(milliseconds: 500), () {
        if (mounted) widget.onNext();
      });
    }
  }

  Widget _typing(Palette p) => PixelColumn(
    key: const ValueKey('typing'),
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      TextField(
        controller: _field,
        focusNode: _focus,
        textAlign: TextAlign.center,
        autocorrect: false,
        enableSuggestions: false,
        style: bodyStyle(p.ink, size: 22),
        onSubmitted: (_) => _submit(),
        decoration: InputDecoration(
          hintText: 'type the pinyin, tones optional',
          hintStyle: bodyStyle(p.inkMuted, size: 15),
          filled: true,
          fillColor: p.empty.withValues(alpha: 0.5),
          hoverColor: Colors.transparent,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: p.border)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: p.accent, width: 2)),
        ),
      ),
      const SizedBox(height: 8),
      Text(
        '${widget.word.w.length} ${widget.word.w.length == 1 ? 'character' : 'characters'}. Press Enter to check.',
        textAlign: TextAlign.center,
        style: bodyStyle(p.inkMuted, size: 14),
      ),
    ],
  );

  Widget _choosing(Palette p) => PixelColumn(
    key: const ValueKey('choosing'),
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Center(child: Text(widget.word.py, style: bodyStyle(p.accent, size: 18, weight: FontWeight.w600))),
      const SizedBox(height: 12),
      Text('Which is right?', textAlign: TextAlign.center, style: bodyStyle(p.inkMuted, size: 14)),
      const SizedBox(height: 12),
      Wrap(
        alignment: WrapAlignment.center,
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final (i, w) in widget.options.indexed)
            _CharacterChoice(
              word: w.w,
              number: i + 1,
              right: _stage != _WriteStage.picking && w.w == widget.word.w,
              wrong: _picked == w.w && w.w != widget.word.w,
              onTap: _stage == _WriteStage.picking ? () => _pick(w) : null,
            ),
        ],
      ),
    ],
  );

  /// The answer, under what was typed: it stays on screen, to be looked at.
  Widget _answer(Palette p) => Container(
    key: const ValueKey('answer'),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(color: Color.lerp(p.tile, p.missed, 0.2), borderRadius: BorderRadius.circular(16)),
    child: PixelColumn(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_attempt case final attempt?)
          Center(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: 'You wrote  ', style: bodyStyle(p.inkMuted, size: 14)),
                  TextSpan(text: attempt, style: bodyStyle(p.missedInk, size: 15, weight: FontWeight.w600).copyWith(decoration: TextDecoration.lineThrough, decorationColor: p.missedInk)),
                ],
              ),
            ),
          ),
        const SizedBox(height: 8),
        Center(child: Text(widget.word.w, style: zhStyle(38, p.ink, height: 1.2))),
        Center(child: Text(widget.word.py, style: bodyStyle(p.accent, size: 18, weight: FontWeight.w600))),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final word = widget.word;
    return _StepCard(
      onKey: _stage == _WriteStage.typing
          ? null
          : (k) {
              if (_stage == _WriteStage.picking) {
                final i = _digits.indexOf(k);
                if (i < 0 || i >= widget.options.length) return KeyEventResult.ignored;
                _pick(widget.options[i]);
                return KeyEventResult.handled;
              }
              if (_stage == _WriteStage.revealed && _isGo(k)) {
                widget.onNext();
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            },
      actions: [if (_stage == _WriteStage.revealed) _Continue(onTap: widget.onNext)],
      child: PixelColumn(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(child: Text('WRITE THIS', style: capsLabel(p.inkMuted))),
          const SizedBox(height: 12),
          Text(word.en, textAlign: TextAlign.center, style: displayStyle(28, p.ink)),
          const SizedBox(height: 20),
          FadeThrough(
            duration: Motion.morph,
            child: _stage == _WriteStage.typing
                ? _typing(p)
                : _attempt != null
                ? _answer(p)
                : _choosing(p),
          ),
        ],
      ),
    );
  }
}

class _CharacterChoice extends StatelessWidget {
  const _CharacterChoice({required this.word, required this.number, required this.right, required this.wrong, required this.onTap});
  final String word;
  final int number;
  final bool right, wrong;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Pressable(
      onTap: onTap,
      builder: (hover) => AnimatedContainer(
        duration: context.themed(right || wrong ? Motion.click : Motion.hover),
        curve: Motion.clickCurve,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        decoration: BoxDecoration(
          color: right
              ? Color.lerp(p.tile, p.done, 0.35)
              : wrong
              ? Color.lerp(p.tile, p.missed, 0.35)
              : hover && onTap != null
              ? p.empty
              : p.empty.withValues(alpha: 0),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: p.border),
        ),
        child: PixelColumn(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(word, style: zhStyle(28, p.ink, height: 1.2)),
            SizedBox(
              height: 18,
              child: VerdictMark(
                right: right ? true : (wrong ? false : null),
                size: 18,
                alignment: Alignment.center,
                child: Text('$number', style: TextStyle(fontFamily: Fonts.taskTime, fontSize: 12, color: p.inkMuted)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A tile being dragged, and where on it the pointer took hold.
class _TileDrag {
  _TileDrag(this.index);
  final int index;
  Offset grab = Offset.zero;
}

class _BuildView extends StatefulWidget {
  const _BuildView({required this.sentence, required this.tiles, this.quiet = false, required this.onRated, required this.onNext});
  final Sentence sentence;
  final List<String> tiles;
  final bool quiet;
  final void Function(Rating, int) onRated;
  final VoidCallback onNext;

  @override
  State<_BuildView> createState() => _BuildViewState();
}

/// Tiles are clicked or dragged into place. As in Eclipse's lists, the others
/// glide aside as one passes over them, and it stays where it was last shown
/// when let go. Dragged back over the tray, it leaves the sentence.
class _BuildViewState extends State<_BuildView> with _Timed {
  final _placed = <int>[];
  bool? _right;
  int? _dragging;

  bool get _full => _placed.length == widget.tiles.length;
  bool get _open => _right == null;

  void _check() {
    if (!_full || _right != null) return;
    final built = _placed.map((i) => widget.tiles[i]).join();
    final right = built == Session.buildAnswer(widget.sentence);
    if (widget.quiet) {
      widget.onRated(right ? Rating.good : Rating.again, taken);
      widget.onNext();
      return;
    }
    if (right) widget.onRated(Rating.good, taken);
    setState(() => _right = right);
  }

  void _settle(Rating rating) {
    if (_right == false) widget.onRated(rating, taken);
    widget.onNext();
  }

  /// Moves [drag] to just before or after the placed tile [over], as the
  /// pointer is on its first or second half.
  void _placeBeside(_TileDrag drag, int over, DragTargetDetails<_TileDrag> details, RenderBox box) {
    if (drag.index == over) return;
    final after = box.globalToLocal(details.offset + drag.grab).dx > box.size.width / 2;
    final next = [..._placed]..remove(drag.index);
    next.insert(next.indexOf(over) + (after ? 1 : 0), drag.index);
    if (next.join(',') != _placed.join(',')) {
      setState(() {
        _placed
          ..clear()
          ..addAll(next);
      });
    }
  }

  Widget _draggable(int i, {required double dim, required VoidCallback? onTap}) {
    final p = context.palette;
    final drag = _TileDrag(i);
    final canDrag = onTap != null;
    return Draggable<_TileDrag>(
      data: drag,
      maxSimultaneousDrags: canDrag ? 1 : 0,
      dragAnchorStrategy: (draggable, context, position) => drag.grab = childDragAnchorStrategy(draggable, context, position),
      onDragStarted: () => setState(() => _dragging = i),
      feedback: Material(
        color: p.tile.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Text(widget.tiles[i], style: zhStyle(22, p.ink)),
        ),
      ),
      child: AnimatedOpacity(
        opacity: dim,
        duration: Motion.hover,
        curve: Motion.hoverCurve,
        child: _Tile(text: widget.tiles[i], onTap: onTap),
      ),
    );
  }

  Widget _placedTile(int i) {
    BuildContext? here;
    return DragTarget<_TileDrag>(
      key: ValueKey(i),
      onWillAcceptWithDetails: (_) => _open,
      onMove: (details) {
        final box = here?.findRenderObject();
        if (box is RenderBox && box.hasSize) _placeBeside(details.data, i, details, box);
      },
      builder: (context, _, _) {
        here = context;
        return Appear(
          animate: true,
          animateSize: false,
          child: _draggable(i, dim: _dragging == i ? 0.3 : 1, onTap: _open ? () => setState(() => _placed.remove(i)) : null),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final s = widget.sentence;
    return Listener(
      // A placed tile dragged back to the tray is gone by the time it's let go,
      // and can't say so itself.
      onPointerUp: (_) => _endDrag(),
      onPointerCancel: (_) => _endDrag(),
      child: _StepCard(
        actionsKey: _right,
        onKey: (k) {
          if (_right == null) {
            if (k == LogicalKeyboardKey.backspace && _placed.isNotEmpty) {
              setState(_placed.removeLast);
              return KeyEventResult.handled;
            }
            final i = _digits.indexOf(k);
            if (i >= 0) {
              final open = [for (var t = 0; t < widget.tiles.length; t++) if (!_placed.contains(t)) t];
              if (i < open.length) setState(() => _placed.add(open[i]));
              return KeyEventResult.handled;
            }
            if (_isGo(k)) _check();
            return KeyEventResult.handled;
          }
          if (_isGo(k)) {
            _settle(Rating.again);
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        actions: _right == null
            ? [PillButton(label: 'Check', hint: 'enter', primary: true, onTap: _full ? _check : null)]
            : _right!
            ? [_Continue(onTap: widget.onNext)]
            : [
                // More than one order can be right, and the app knows only one.
                PillButton(label: 'Mine was fine too', onTap: () => _settle(Rating.hard)),
                _Continue(onTap: () => _settle(Rating.again)),
              ],
        child: PixelColumn(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(child: Text('BUILD THIS', style: capsLabel(p.inkMuted))),
            const SizedBox(height: 12),
            Text(s.shownEn, textAlign: TextAlign.center, style: displayStyle(22, p.ink)),
            const SizedBox(height: 20),
            DragTarget<_TileDrag>(
              onWillAcceptWithDetails: (_) => _open,
              // Over the sentence but no tile in it, a new one goes on the end.
              onMove: (details) {
                if (!_placed.contains(details.data.index)) setState(() => _placed.add(details.data.index));
              },
              builder: (context, candidates, _) => AnimatedContainer(
                duration: context.themed(Motion.hover),
                curve: Motion.hoverCurve,
                constraints: const BoxConstraints(minHeight: 60),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _right != null
                      ? Color.lerp(p.tile, _right! ? p.done : p.missed, 0.25)
                      : candidates.isNotEmpty
                      ? p.accent.withValues(alpha: 0.16)
                      : p.empty.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: p.borderSoft),
                ),
                child: Center(
                  child: GlideWrap(
                    spacing: 8,
                    runSpacing: 8,
                    alignment: WrapAlignment.center,
                    children: [for (final i in _placed) _placedTile(i)],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            FadeThrough(
              duration: Motion.morph,
              child: _right == false
                  ? Text(key: const ValueKey('answer'), s.zh, textAlign: TextAlign.center, style: zhStyle(22, p.ink))
                  : DragTarget<_TileDrag>(
                      key: const ValueKey('tray'),
                      onWillAcceptWithDetails: (details) {
                        if (!_open) return false;
                        if (_placed.contains(details.data.index)) setState(() => _placed.remove(details.data.index));
                        return true;
                      },
                      builder: (context, _, _) => ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 44, minWidth: double.infinity),
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          alignment: WrapAlignment.center,
                          children: [
                            for (final (i, _) in widget.tiles.indexed)
                              _placed.contains(i)
                                  ? AnimatedOpacity(
                                      opacity: 0.2,
                                      duration: Motion.hover,
                                      curve: Motion.hoverCurve,
                                      child: _draggable(i, dim: 1, onTap: null),
                                    )
                                  : _draggable(i, dim: _dragging == i ? 0.3 : 1, onTap: _right != null ? null : () => setState(() => _placed.add(i))),
                          ],
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  void _endDrag() {
    if (_dragging != null) setState(() => _dragging = null);
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.text, required this.onTap});
  final String text;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Pressable(
      onTap: onTap,
      builder: (hover) => AnimatedContainer(
        duration: context.themed(Motion.hover),
        curve: Motion.hoverCurve,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: hover && onTap != null ? p.empty : p.tile,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: p.border),
        ),
        child: Text(text, style: zhStyle(22, p.ink)),
      ),
    );
  }
}
