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
import '../widgets/common.dart';
import '../widgets/fade_through.dart';
import '../widgets/hover_fill.dart';
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
    SessionKind.exam => 'LEVEL ${s.level!.n} EXAM',
  };

  Widget _stepView() {
    final exam = s.kind == SessionKind.exam;
    void rate(Rating r, int ms) => s.answer(r, takenMs: ms);
    return switch (s.current) {
      TeachRadical(:final radical) => _TeachRadicalView(radical: radical, onNext: _advance),
      TeachWord(:final word) => _TeachWordView(word: word, onNext: _advance),
      TeachGrammar(:final grammar) => _TeachGrammarView(grammar: grammar, onNext: _advance),
      ChooseMeaning(:final word, :final options) => _ChooseView(
        prompt: _HanziPrompt(word.w),
        options: options,
        answer: word.en,
        reveal: word.py,
        onRated: rate,
        onNext: _advance,
      ),
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
      RecallRadical(:final radical) => _RecallView(
        prompt: _HanziPrompt(radical.r),
        kicker: 'What does this radical mean?',
        answer: Text(radical.en, style: displayStyle(22, context.palette.ink)),
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
  const _StepCard({required this.child, this.actions = const [], this.onKey});

  final Widget child;
  final List<Widget> actions;
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
                    if (widget.actions.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Wrap(alignment: WrapAlignment.center, spacing: 12, runSpacing: 12, children: widget.actions),
                    ],
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

class _TeachRadicalView extends StatelessWidget {
  const _TeachRadicalView({required this.radical, required this.onNext});
  final Radical radical;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final course = AppScope.read(context).course;
    final examples = [
      for (final c in course.chars.values)
        if (c.radical == radical.r || c.semantic == radical.r) c.c,
    ].take(5).join('  ');
    return _StepCard(
      onKey: (k) {
        if (!_isGo(k)) return KeyEventResult.ignored;
        onNext();
        return KeyEventResult.handled;
      },
      actions: [_Continue(onTap: onNext)],
      child: PixelColumn(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('NEW BUILDING BLOCK', style: capsLabel(p.inkMuted)),
          const SizedBox(height: 12),
          _HanziPrompt(radical.r),
          const SizedBox(height: 8),
          Text(radical.en, style: displayStyle(28, p.ink)),
          const SizedBox(height: 8),
          Text('Characters with this part often relate to it.', textAlign: TextAlign.center, style: bodyStyle(p.inkMuted)),
          if (examples.isNotEmpty) ...[const SizedBox(height: 16), Text(examples, style: zhStyle(22, p.ink))],
        ],
      ),
    );
  }
}

class _TeachWordView extends StatelessWidget {
  const _TeachWordView({required this.word, required this.onNext});
  final Word word;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final course = AppScope.read(context).course;
    final example = word.examples.map((id) => course.sentences[id]).nonNulls.firstOrNull;
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
          const SizedBox(height: 20),
          WordBreakdown(word: word),
          if (example != null) ...[
            const SizedBox(height: 20),
            Divider(height: 1, color: p.borderSoft),
            const SizedBox(height: 16),
            Text(example.zh, style: zhStyle(22, p.ink)),
            Text(example.en, style: bodyStyle(p.inkMuted, size: 14)),
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
  const _ChooseView({required this.prompt, required this.options, required this.answer, this.reveal, this.quiet = false, required this.onRated, required this.onNext});

  final Widget prompt;
  final List<String> options;
  final String answer;
  final String? reveal;

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
    final p = context.palette;
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
          if (widget.reveal != null) ...[
            const SizedBox(height: 4),
            Center(
              child: AnimatedOpacity(
                opacity: _picked == null ? 0 : 1,
                duration: Motion.click,
                child: Text(widget.reveal!, style: bodyStyle(p.accent, size: 18, weight: FontWeight.w600)),
              ),
            ),
          ],
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
        duration: context.themed(Motion.click),
        curve: Motion.clickCurve,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: switch (state) {
            _OptionState.right => Color.lerp(p.tile, p.done, 0.35),
            _OptionState.wrong => Color.lerp(p.tile, p.missed, 0.35),
            _ => hover ? p.empty : Colors.transparent,
          },
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: p.border),
        ),
        child: PixelRow(
          children: [
            SizedBox(width: 24, child: Text('$number', style: TextStyle(fontFamily: Fonts.taskTime, fontSize: 12, color: p.inkMuted))),
            Expanded(
              child: Text(label, style: bodyStyle(state == _OptionState.other ? p.inkMuted : p.ink, weight: FontWeight.w500, height: 1.3)),
            ),
          ],
        ),
      ),
    );
  }
}

class _RecallView extends StatefulWidget {
  const _RecallView({required this.prompt, required this.answer, this.kicker, required this.onRated, required this.onNext});

  final Widget prompt, answer;
  final String? kicker;
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
          Center(child: Text((widget.kicker ?? 'What does this mean?').toUpperCase(), style: capsLabel(p.inkMuted))),
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
          _Reveal(shown: _shown, child: Text(s.en, textAlign: TextAlign.center, style: displayStyle(18, p.ink))),
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

class _WriteViewState extends State<_WriteView> with _Timed {
  final _field = TextEditingController();
  final _focus = FocusNode();
  var _stage = _WriteStage.typing;
  var _tries = 0;
  String? _picked;
  bool _shake = false;

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
    _tries++;
    if (_tries >= 2) {
      widget.onRated(Rating.again, taken);
      if (widget.quiet) return widget.onNext();
      setState(() => _stage = _WriteStage.revealed);
    } else {
      setState(() => _shake = true);
      _focus.requestFocus();
    }
  }

  void _pick(Word w) {
    if (_stage != _WriteStage.picking) return;
    _picked = w.w;
    final right = w.w == widget.word.w;
    widget.onRated(right ? (_tries > 0 ? Rating.hard : Rating.good) : Rating.again, taken);
    if (widget.quiet) return widget.onNext();
    setState(() => _stage = right ? _WriteStage.done : _WriteStage.revealed);
    if (right) {
      Timer(const Duration(milliseconds: 500), () {
        if (mounted) widget.onNext();
      });
    }
  }

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
          if (_stage == _WriteStage.typing) ...[
            TextField(
              controller: _field,
              focusNode: _focus,
              textAlign: TextAlign.center,
              autocorrect: false,
              enableSuggestions: false,
              style: bodyStyle(p.ink, size: 22),
              onChanged: (_) {
                if (_shake) setState(() => _shake = false);
              },
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                hintText: 'type the pinyin, tones optional',
                hintStyle: bodyStyle(p.inkMuted, size: 15),
                filled: true,
                fillColor: p.empty.withValues(alpha: 0.5),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: _shake ? p.missed : p.border)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: _shake ? p.missed : p.accent, width: 2)),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _shake ? 'Not quite. One more try.' : '${word.w.length} ${word.w.length == 1 ? 'character' : 'characters'}. Press Enter to check.',
              textAlign: TextAlign.center,
              style: bodyStyle(_shake ? p.missedInk : p.inkMuted, size: 14),
            ),
          ] else if (_stage == _WriteStage.picking || _stage == _WriteStage.done || _picked != null) ...[
            Center(child: Text(word.py, style: bodyStyle(p.accent, size: 18, weight: FontWeight.w600))),
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
                    right: _stage != _WriteStage.picking && w.w == word.w,
                    wrong: _picked == w.w && w.w != word.w,
                    onTap: () => _pick(w),
                  ),
              ],
            ),
          ] else ...[
            Center(child: Text(word.w, style: zhStyle(56, p.ink, height: 1.2))),
            Center(child: Text(word.py, style: bodyStyle(p.accent, size: 18, weight: FontWeight.w600))),
          ],
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
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Hoverable(
      onTap: onTap,
      builder: (hover) => AnimatedContainer(
        duration: context.themed(Motion.click),
        curve: Motion.clickCurve,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        decoration: BoxDecoration(
          color: right
              ? Color.lerp(p.tile, p.done, 0.35)
              : wrong
              ? Color.lerp(p.tile, p.missed, 0.35)
              : hover
              ? p.empty
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: p.border),
        ),
        child: PixelColumn(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(word, style: zhStyle(28, p.ink, height: 1.2)),
            Text('$number', style: TextStyle(fontFamily: Fonts.taskTime, fontSize: 12, color: p.inkMuted)),
          ],
        ),
      ),
    );
  }
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

class _BuildViewState extends State<_BuildView> with _Timed {
  final _placed = <int>[];
  bool? _right;

  bool get _full => _placed.length == widget.tiles.length;

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

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final s = widget.sentence;
    return _StepCard(
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
          Text(s.en, textAlign: TextAlign.center, style: displayStyle(22, p.ink)),
          const SizedBox(height: 20),
          Container(
            constraints: const BoxConstraints(minHeight: 60),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: _right == null ? p.empty.withValues(alpha: 0.5) : Color.lerp(p.tile, _right! ? p.done : p.missed, 0.25),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: p.borderSoft),
            ),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                for (final i in _placed)
                  _Tile(text: widget.tiles[i], onTap: _right == null ? () => setState(() => _placed.remove(i)) : null),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (_right == false) ...[
            Text(s.zh, textAlign: TextAlign.center, style: zhStyle(22, p.ink)),
          ] else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                for (final (i, t) in widget.tiles.indexed)
                  Opacity(
                    opacity: _placed.contains(i) ? 0.2 : 1,
                    child: _Tile(text: t, onTap: _placed.contains(i) || _right != null ? null : () => setState(() => _placed.add(i))),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.text, required this.onTap});
  final String text;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Hoverable(
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
