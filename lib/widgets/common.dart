import 'package:flutter/material.dart';

import '../data/curriculum.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/pixels.dart';
import '../theme/tokens.dart';
import 'fade_through.dart';
import 'hover_fill.dart';
import 'smooth_gradient.dart';

/// Chinese text in the chosen font. The sans font is variable, so it's told its weight.
TextStyle zhStyle(double size, Color color, {FontWeight weight = FontWeight.w400, double height = 1.35}) => TextStyle(
  fontFamily: Fonts.zh,
  fontFamilyFallback: Fonts.zhFallback,
  fontSize: size,
  fontWeight: weight,
  height: height,
  color: color,
  fontVariations: Fonts.zh == Fonts.zhSans ? [FontVariation('wght', weight.value.toDouble())] : null,
);

TextStyle displayStyle(double size, Color color) =>
    TextStyle(fontFamily: Fonts.display, fontSize: size, fontWeight: FontWeight.w600, letterSpacing: -0.2, height: 1.15, color: color);

TextStyle bodyStyle(Color color, {double size = 15, FontWeight weight = FontWeight.w400, double height = 1.45}) =>
    TextStyle(fontFamily: Fonts.body, fontSize: size, fontWeight: weight, height: height, color: color, fontFamilyFallback: Fonts.zhFallback);

/// The app's button: filled in the done colour when [primary], quiet otherwise.
class PillButton extends StatelessWidget {
  const PillButton({super.key, required this.label, required this.onTap, this.primary = false, this.hint, this.tone, this.expand = false});

  final String label;
  final VoidCallback? onTap;
  final bool primary, expand;

  /// The key that does the same, shown small beside the label.
  final String? hint;

  /// A fill in place of the usual one.
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final enabled = onTap != null;
    return Hoverable(
      onTap: onTap,
      builder: (hover) {
        final fill = tone ?? (primary ? p.done : p.tile);
        final ink = (primary || tone != null) ? p.onDone : p.ink;
        return AnimatedContainer(
          duration: context.themed(Motion.hover),
          curve: Motion.hoverCurve,
          constraints: const BoxConstraints(minHeight: 44),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          decoration: BoxDecoration(
            color: enabled ? (hover ? Color.lerp(fill, primary || tone != null ? p.ink : p.empty, 0.14) : fill) : fill.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: primary || tone != null ? p.border.withValues(alpha: 0) : p.border),
          ),
          child: PixelRow(
            mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(child: Text(label, textAlign: TextAlign.center, style: bodyStyle(ink, weight: FontWeight.w600, height: 1.2))),
              if (hint != null) ...[
                const SizedBox(width: 8),
                Text(hint!, style: TextStyle(fontFamily: Fonts.taskTime, fontSize: 12, color: ink.withValues(alpha: 0.65))),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// A bar that eases to [value], in the theme's gradient.
class ProgressTrack extends StatelessWidget {
  const ProgressTrack({super.key, required this.value, this.height = 8});

  final double value;
  final double height;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return LayoutBuilder(
      builder: (context, box) => TweenAnimationBuilder<double>(
        tween: Tween(end: value.clamp(0.0, 1.0)),
        duration: Motion.page,
        curve: Motion.morphCurve,
        builder: (context, v, _) {
          final width = pixelRound(box.maxWidth * v);
          return Container(
            height: height,
            decoration: BoxDecoration(color: p.empty, borderRadius: BorderRadius.circular(4)),
            alignment: Alignment.centerLeft,
            child: width < 1
                ? null
                : Container(
                    width: width < height ? height : width,
                    decoration: SmoothGradientDecoration(
                      borderRadius: BorderRadius.circular(4),
                      gradient: LinearGradient(colors: [p.gradient[1], p.gradient[2]]),
                    ),
                  ),
          );
        },
      ),
    );
  }
}

/// A big figure with its small-caps label.
class Stat extends StatelessWidget {
  const Stat({super.key, required this.value, required this.label, this.note});

  final Widget value;
  final String label;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return PixelColumn(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        DefaultTextStyle.merge(style: displayStyle(38, p.ink), child: value),
        const SizedBox(height: 4),
        Text(label.toUpperCase(), style: capsLabel(p.inkMuted)),
        if (note != null) ...[const SizedBox(height: 4), Text(note!, style: bodyStyle(p.inkMuted, size: 14))],
      ],
    );
  }
}

/// Chinese text whose words you can tap for their meaning. Words you've yet to learn
/// are underlined. [selected] and [onSelect] are held by whoever shows the meaning.
class TappableText extends StatelessWidget {
  const TappableText({super.key, required this.toks, required this.size, this.selected, this.onSelect, this.isKnown, this.alignCentre = false});

  final List<String> toks;
  final double size;
  final int? selected;
  final ValueChanged<int>? onSelect;
  final bool Function(String)? isKnown;
  final bool alignCentre;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final state = AppScope.read(context);
    final style = zhStyle(size, p.ink, height: 1.5);
    return Wrap(
      alignment: alignCentre ? WrapAlignment.center : WrapAlignment.start,
      children: [
        for (final (i, t) in toks.indexed)
          if (t.trim().isEmpty)
            SizedBox(width: size)
          else if (_isPunct(t))
            Text(t, style: style.copyWith(color: p.inkMuted))
          else
            Hoverable(
              onTap: onSelect == null ? null : () => onSelect!(i),
              builder: (hover) {
                final known = isKnown?.call(t) ?? state.isKnownToken(t);
                return AnimatedContainer(
                  duration: context.themed(Motion.hover),
                  curve: Motion.hoverCurve,
                  decoration: BoxDecoration(
                    color: selected == i ? p.other.withValues(alpha: 0.3) : (hover ? p.empty : p.empty.withValues(alpha: 0)),
                    borderRadius: BorderRadius.circular(4),
                    border: Border(bottom: BorderSide(color: p.accent.withValues(alpha: known ? 0 : 1), width: 2)),
                  ),
                  child: Text(t, style: style),
                );
              },
            ),
      ],
    );
  }

  static bool _isPunct(String t) => t.length == 1 && !RegExp(r'[一-鿿]').hasMatch(t);
}

/// The pinyin and meaning of a token, under text you can tap.
class GlossLine extends StatelessWidget {
  const GlossLine({super.key, required this.token, this.extra});

  final String? token;
  final Map<String, (String, String)>? extra;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final course = AppScope.read(context).course;
    final t = token;
    final word = t == null ? null : course.words[t];
    final name = t == null ? null : course.names[t];
    final other = t == null ? null : extra?[t];
    final (String py, String en) = word != null
        ? (word.py, word.en)
        : name != null
        ? ('', '$name (name)')
        : other ?? ('', t == null ? 'Tap a word for its meaning.' : '');
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 28),
      child: FadeThrough(
        duration: Motion.morph,
        layoutBuilder: FadeThrough.aligned(Alignment.centerLeft),
        child: Align(
          key: ValueKey(t),
          alignment: Alignment.centerLeft,
          child: Text.rich(
            TextSpan(
              children: [
                if (t != null) TextSpan(text: '$t  ', style: zhStyle(18, p.ink)),
                if (py.isNotEmpty) TextSpan(text: '$py  ', style: bodyStyle(p.accent, weight: FontWeight.w600)),
                TextSpan(text: en, style: bodyStyle(t == null ? p.inkMuted : p.ink)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// How a word is built: each character's parts, where the data says.
class WordBreakdown extends StatelessWidget {
  const WordBreakdown({super.key, required this.word});

  final Word word;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final course = AppScope.read(context).course;
    return PixelColumn(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      spacing: 12,
      children: [
        for (final c in word.w.split(''))
          if (course.chars[c] case final info?)
            PixelRow(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: 44, child: Text(c, style: zhStyle(28, p.ink, height: 1.1))),
                Expanded(
                  child: PixelColumn(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (info.en.isNotEmpty) Text(info.en, style: bodyStyle(p.ink, size: 14)),
                      if (_explain(course, info) case final why?) Text(why, style: bodyStyle(p.inkMuted, size: 14)),
                    ],
                  ),
                ),
              ],
            ),
      ],
    );
  }

  static String? _explain(Curriculum course, CharInfo c) {
    final meaning = c.semantic.isNotEmpty ? course.radicals[c.semantic]?.en ?? '' : '';
    if (c.type == 'pictophonetic' && c.semantic.isNotEmpty && c.phonetic.isNotEmpty) {
      return '${c.semantic}${meaning.isEmpty ? '' : ' ($meaning)'} hints at the meaning, ${c.phonetic} at the sound.';
    }
    if (c.hint.isNotEmpty) return c.hint;
    final r = course.radicals[c.radical];
    if (r != null && c.radical != c.c) return 'Radical: ${r.r} (${r.en}).';
    return null;
  }
}

/// A rounded chip with a small-caps label.
class CapsChip extends StatelessWidget {
  const CapsChip(this.label, {super.key, this.tone});

  final String label;
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: tone?.withValues(alpha: 0.2) ?? p.empty.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: p.borderSoft),
      ),
      child: PixelFit(child: Text(label.toUpperCase(), style: capsLabel(p.inkMuted))),
    );
  }
}
