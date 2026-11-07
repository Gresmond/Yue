import 'package:flutter/material.dart';

import '../data/curriculum.dart';
import '../data/fsrs.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/pixels.dart';
import '../theme/tokens.dart';
import '../widgets/common.dart';
import '../widgets/hover_fill.dart';

/// Every word in the course: find one by Chinese, pinyin or English, and see how
/// well you hold it.
class WordsPage extends StatefulWidget {
  const WordsPage({super.key});

  @override
  State<WordsPage> createState() => _WordsPageState();
}

class _WordsPageState extends State<WordsPage> {
  var _query = '';
  var _filter = 'Learned';
  String? _open;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final state = AppScope.of(context);
    final q = _query.trim().toLowerCase();
    final words = state.course.words.values.where((w) {
      if (_filter == 'Learned' && q.isEmpty && !state.learned.contains(w.w)) return false;
      if (_filter == 'Weak' && !(state.learned.contains(w.w) && Fsrs.recallAt(state.cards['wr:${w.w}']!, state.nowMs) < 0.85)) return false;
      if (q.isEmpty) return true;
      return w.w.contains(q) || toneless(w.py).contains(toneless(q).isEmpty ? q : toneless(q)) || w.en.toLowerCase().contains(q);
    }).toList();
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 4, 32, 0),
      child: PixelColumn(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PixelRow(
            children: [
              Expanded(
                child: TextField(
                  onChanged: (v) => setState(() => _query = v),
                  style: bodyStyle(p.ink),
                  decoration: InputDecoration(
                    hintText: 'Search all 5,307 words by Chinese, pinyin or English',
                    hintStyle: bodyStyle(p.inkMuted),
                    isDense: true,
                    filled: true,
                    fillColor: p.tile,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide(color: p.border)),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide(color: p.accent)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              for (final f in const ['Learned', 'Weak', 'All']) ...[
                PillButton(label: f, primary: f == _filter, onTap: () => setState(() => _filter = f)),
                if (f != 'All') const SizedBox(width: 8),
              ],
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: words.isEmpty
                ? Center(child: Text(_filter == 'Weak' ? 'Nothing weak right now.' : 'No words here yet.', style: bodyStyle(p.inkMuted)))
                : ListView.builder(
                    padding: const EdgeInsets.only(bottom: 32),
                    itemCount: words.length,
                    itemBuilder: (context, i) => _WordRow(
                      word: words[i],
                      open: _open == words[i].w,
                      onTap: () => setState(() => _open = _open == words[i].w ? null : words[i].w),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _WordRow extends StatelessWidget {
  const _WordRow({required this.word, required this.open, required this.onTap});
  final Word word;
  final bool open;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final state = AppScope.read(context);
    final memory = state.cards['wr:${word.w}'];
    final recall = memory == null ? null : Fsrs.recallAt(memory, state.nowMs);
    return Hoverable(
      onTap: onTap,
      builder: (hover) => AnimatedContainer(
        duration: context.themed(Motion.hover),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        margin: const EdgeInsets.only(bottom: 4),
        decoration: BoxDecoration(color: hover || open ? p.tile : Colors.transparent, borderRadius: BorderRadius.circular(12)),
        child: PixelColumn(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            PixelRow(
              children: [
                SizedBox(width: 120, child: Text(word.w, style: zhStyle(22, memory == null ? p.inkMuted : p.ink, height: 1.2))),
                SizedBox(width: 140, child: Text(word.py, overflow: TextOverflow.ellipsis, style: bodyStyle(p.accent, size: 14, weight: FontWeight.w600))),
                Expanded(child: Text(word.en, overflow: TextOverflow.ellipsis, style: bodyStyle(p.ink, size: 14))),
                const SizedBox(width: 12),
                SizedBox(width: 72, child: recall == null ? Text('Level ${state.course.wordLevel[word.w] ?? ''}', textAlign: TextAlign.end, style: bodyStyle(p.inkMuted, size: 12)) : ProgressTrack(value: recall, height: 4)),
              ],
            ),
            if (open) ...[
              const SizedBox(height: 12),
              Text(word.senses.join('  ·  '), style: bodyStyle(p.inkMuted, size: 14)),
              const SizedBox(height: 12),
              WordBreakdown(word: word),
              for (final s in word.examples.map((id) => state.course.sentences[id]).nonNulls.take(2)) ...[
                const SizedBox(height: 12),
                Text(s.zh, style: zhStyle(18, p.ink)),
                Text(s.en, style: bodyStyle(p.inkMuted, size: 14)),
              ],
              const SizedBox(height: 4),
            ],
          ],
        ),
      ),
    );
  }
}
