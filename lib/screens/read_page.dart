import 'package:flutter/material.dart';

import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/pixels.dart';
import '../theme/tokens.dart';
import '../widgets/common.dart';
import '../widgets/fade_through.dart';
import '../widgets/hover_fill.dart';
import '../widgets/tile.dart';

/// Reading for its own sake: nothing here is tested. Sentence sets are written by
/// native speakers; passages are written by AI and labelled.
class ReadPage extends StatefulWidget {
  const ReadPage({super.key});

  @override
  State<ReadPage> createState() => _ReadPageState();
}

class _Text {
  _Text({required this.id, required this.title, required this.zh, required this.toks, required this.en, this.extra = const {}, required this.ai});
  final String id, title, zh, en;
  final List<String> toks;
  final Map<String, (String, String)> extra;
  final bool ai;
}

class _ReadPageState extends State<ReadPage> {
  _Text? _open;

  /// Up to eight sentences you can read from this level and the ones before.
  _Text _sentenceSet(AppState state, int level) {
    final course = state.course;
    final sentences = [
      for (final s in course.sentences.values)
        if (s.level == level && !s.exam && s.zh.length >= 6) s,
    ]..sort((a, b) => a.id.compareTo(b.id));
    final chosen = sentences.take(8);
    return _Text(
      id: 'set:$level',
      title: 'Sentences, level $level',
      zh: chosen.map((s) => s.zh).join(),
      toks: [for (final s in chosen) ...s.toks],
      en: chosen.map((s) => s.en).join(' '),
      ai: false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final open = _open;
    return FadeThrough(
      child: open != null
          ? SizedBox.expand(key: ValueKey(open.id), child: _Reader(text: open, onClose: () => setState(() => _open = null)))
          : _List(key: const ValueKey('list'), onOpen: (t) => setState(() => _open = t), sets: [
              for (var l = state.level.n; l >= 1 && l > state.level.n - 4; l--)
                if (l < state.level.n || state.doneInLevel(state.level) > 0) _sentenceSet(state, l),
            ]),
    );
  }
}

class _List extends StatelessWidget {
  const _List({super.key, required this.onOpen, required this.sets});
  final ValueChanged<_Text> onOpen;
  final List<_Text> sets;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final state = AppScope.of(context);
    final open = state.course.passages.where(state.passageOpen).toList();
    final locked = state.course.passages.where((x) => !state.passageOpen(x)).toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(32, 4, 32, 32),
      children: [
        Tile(
          child: PixelColumn(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              const TileHeader(title: 'Written by native speakers'),
              const SizedBox(height: 4),
              Text('Real sentences at your level. Tap any word for its meaning.', style: bodyStyle(p.inkMuted)),
              const SizedBox(height: 12),
              if (sets.isEmpty) Text('Finish your first lesson to unlock these.', style: bodyStyle(p.inkMuted)),
              for (final t in sets) _Row(title: t.title, percent: state.coverage(t.toks), done: state.hasRead(t.id), onTap: () => onOpen(t)),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Tile(
          child: PixelColumn(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              TileHeader(title: 'Short passages', badge: const CapsChip('AI-written')),
              const SizedBox(height: 4),
              Text('Written by AI and not checked by a native speaker, so the odd phrase may sound unnatural. They are extra practice and are never tested.', style: bodyStyle(p.inkMuted)),
              const SizedBox(height: 12),
              for (final x in open)
                _Row(
                  title: x.title,
                  percent: state.coverage(x.toks),
                  done: state.hasRead('p:${x.title}'),
                  onTap: () => onOpen(_Text(id: 'p:${x.title}', title: x.title, zh: x.zh, toks: x.toks, en: x.en, extra: x.extra, ai: true)),
                ),
              for (final x in locked) _Row(title: x.title, lockedAt: x.level),
            ],
          ),
        ),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.title, this.percent, this.done = false, this.onTap, this.lockedAt});
  final String title;
  final double? percent;
  final bool done;
  final VoidCallback? onTap;
  final int? lockedAt;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Hoverable(
      onTap: onTap,
      builder: (hover) => AnimatedContainer(
        duration: context.themed(Motion.hover),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(color: hover && onTap != null ? p.empty : Colors.transparent, borderRadius: BorderRadius.circular(12)),
        child: PixelRow(
          children: [
            Expanded(child: Text(title, style: bodyStyle(lockedAt != null ? p.inkMuted : p.ink, weight: FontWeight.w500))),
            if (done) ...[const CapsChip('Read'), const SizedBox(width: 8)],
            Text(lockedAt != null ? 'Level $lockedAt' : '${((percent ?? 0) * 100).round()}% known', style: bodyStyle(p.inkMuted, size: 14)),
          ],
        ),
      ),
    );
  }
}

class _Reader extends StatefulWidget {
  const _Reader({required this.text, required this.onClose});
  final _Text text;
  final VoidCallback onClose;

  @override
  State<_Reader> createState() => _ReaderState();
}

class _ReaderState extends State<_Reader> {
  int? _selected;
  bool _translation = false;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final state = AppScope.read(context);
    final t = widget.text;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(32, 4, 32, 32),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Tile(
            child: PixelColumn(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                TileHeader(
                  title: t.title,
                  badge: t.ai ? const CapsChip('AI-written') : null,
                  trailingAtEnd: true,
                  trailing: HeaderIconButton(icon: Icons.close_rounded, tooltip: 'Back', onPressed: widget.onClose),
                ),
                const SizedBox(height: 16),
                TappableText(toks: t.toks, size: 28, selected: _selected, onSelect: (i) => setState(() => _selected = i), isKnown: (w) => state.learned.contains(w) || state.course.names.containsKey(w)),
                const SizedBox(height: 12),
                Divider(height: 1, color: p.borderSoft),
                const SizedBox(height: 12),
                GlossLine(token: _selected == null ? null : t.toks[_selected!], extra: t.extra),
                if (_translation) ...[const SizedBox(height: 12), Text(t.en, style: bodyStyle(p.inkMuted))],
                const SizedBox(height: 16),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    PillButton(label: _translation ? 'Hide translation' : 'Show translation', onTap: () => setState(() => _translation = !_translation)),
                    PillButton(
                      label: 'I read this',
                      primary: true,
                      onTap: () {
                        state.markRead(t.id);
                        widget.onClose();
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
