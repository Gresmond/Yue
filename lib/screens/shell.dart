import 'package:flutter/material.dart';

import '../state/app_state.dart';
import '../state/session.dart';
import '../theme/app_theme.dart';
import '../theme/pixels.dart';
import '../theme/tokens.dart';
import '../widgets/app_dialog.dart';
import '../widgets/common.dart';
import '../widgets/fade_through.dart';
import '../widgets/glide_pill.dart';
import '../widgets/hover_fill.dart';
import '../widgets/rolling_number.dart';
import '../widgets/smooth_gradient.dart';
import '../widgets/sync_section.dart';
import 'path_page.dart';
import 'progress_page.dart';
import 'read_page.dart';
import 'session_screen.dart';
import 'today_page.dart';
import 'warm_up.dart';
import 'words_page.dart';

enum Section { today, path, read, words, progress }

/// The header and the pages under it, or a session filling the window.
class Shell extends StatefulWidget {
  const Shell({super.key});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  var _tab = Section.today;
  Session? _session;
  var _run = 0;

  void _start(Session s) => setState(() {
    _session = s;
    _run++;
  });

  void _close() {
    AppScope.read(context).openDay();
    setState(() => _session = null);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final session = _session;
    return Scaffold(
      backgroundColor: p.background,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: FadeThrough(
          child: session != null
              ? SessionScreen(key: ValueKey('session$_run'), session: session, onClose: _close, onAgain: _start)
              : PixelColumn(
                  key: const ValueKey('pages'),
                  children: [
                    _Header(tab: _tab, onTab: (t) => setState(() => _tab = t)),
                    Expanded(
                      child: FadeThrough(
                        child: KeyedSubtree(
                          key: ValueKey(_tab),
                          child: switch (_tab) {
                            Section.today => TodayPage(onStart: _start, onTab: (t) => setState(() => _tab = t)),
                            Section.path => PathPage(onStart: _start),
                            Section.read => const ReadPage(),
                            Section.words => const WordsPage(),
                            Section.progress => const ProgressPage(),
                          },
                        ),
                      ),
                    ),
                  ],
                ),
        ),
            ),
            if (WarmUp.enabled) const Positioned.fill(child: WarmUp()),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.tab, required this.onTab});
  final Section tab;
  final ValueChanged<Section> onTab;

  static const _names = {Section.today: 'Today', Section.path: 'Path', Section.read: 'Read', Section.words: 'Words', Section.progress: 'Progress'};

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final state = AppScope.of(context);
    final narrow = MediaQuery.sizeOf(context).width < 760;
    final now = state.now;
    const months = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
    const weekdays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    final (kicker, title) = switch (tab) {
      Section.today => (weekdays[now.weekday - 1], '${now.day} ${months[now.month - 1]}'),
      Section.path => ('Band ${state.level.band}', 'Level ${state.level.n}'),
      Section.read => ('Practice', 'Read'),
      Section.words => ('${state.learned.length} learned', 'Words'),
      Section.progress => ('So far', 'Progress'),
    };
    final tabs = _TabBar(tab: tab, names: _names, onTab: onTab);
    final titleBlock = FadeThrough(
      layoutBuilder: FadeThrough.pinTopLeft,
      child: PixelFit(
        key: ValueKey(title),
        child: PixelColumn(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(kicker, style: bodyStyle(p.inkMuted, size: 14, weight: FontWeight.w500, height: 1.2)),
            const SizedBox(height: 2),
            Text(title, style: TextStyle(fontFamily: Fonts.display, fontSize: 38, fontWeight: FontWeight.w600, letterSpacing: -0.6, height: 1.05, color: p.ink)),
          ],
        ),
      ),
    );
    final right = PixelRow(
      mainAxisSize: MainAxisSize.min,
      children: [
        const _StreakPill(),
        const SizedBox(width: 12),
        const _ThemeButton(),
      ],
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 20, 32, 12),
      child: narrow
          ? PixelColumn(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                PixelRow(children: [Expanded(child: titleBlock), right]),
                const SizedBox(height: 12),
                SingleChildScrollView(scrollDirection: Axis.horizontal, child: tabs),
              ],
            )
          : PixelRow(
              children: [
                Expanded(child: titleBlock),
                tabs,
                const SizedBox(width: 12),
                right,
              ],
            ),
    );
  }
}

class _TabBar extends StatefulWidget {
  const _TabBar({required this.tab, required this.names, required this.onTab});
  final Section tab;
  final Map<Section, String> names;
  final ValueChanged<Section> onTab;

  @override
  State<_TabBar> createState() => _TabBarState();
}

class _TabBarState extends State<_TabBar> {
  final _keys = {for (final t in Section.values) t: GlobalKey()};

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: p.tile.withValues(alpha: 0.8), borderRadius: BorderRadius.circular(24), border: Border.all(color: p.border)),
      child: GlidePill(
        target: _keys[widget.tab],
        color: p.done,
        child: PixelRow(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final t in Section.values)
              Hoverable(
                key: ValueKey(t),
                onTap: () => widget.onTab(t),
                // The selected background is the bar's gliding pill; a tab only
                // draws its hover shade, and its text eases as the pill arrives.
                builder: (hover) => AnimatedContainer(
                  key: _keys[t],
                  duration: context.themed(Motion.hover),
                  curve: Motion.hoverCurve,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(30),
                    color: t != widget.tab && hover ? p.empty : p.empty.withValues(alpha: 0),
                  ),
                  child: AnimatedDefaultTextStyle(
                    duration: context.themed(Motion.morph),
                    curve: Motion.morphCurve,
                    style: bodyStyle(t == widget.tab ? p.onDone : p.ink, weight: FontWeight.w600, height: 1.2),
                    child: Text(widget.names[t]!),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The streak, rolling up as a day is earned, in the accent colour once today counts.
class _StreakPill extends StatelessWidget {
  const _StreakPill();

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final state = AppScope.of(context);
    final done = state.today.complete;
    final style = TextStyle(fontFamily: Fonts.display, fontSize: 22, fontWeight: FontWeight.w600, color: done ? p.onDone : p.ink, height: 1.1);
    final freezes = state.freezes;
    return PixelTooltip(
      message: '${state.streak} day streak  ·  best ${state.best}${freezes > 0 ? '  ·  $freezes ${freezes == 1 ? 'freeze' : 'freezes'} saved' : ''}',
      child: AnimatedContainer(
        duration: context.themed(Motion.morph),
        curve: Motion.morphCurve,
        height: 46,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(color: done ? p.done : p.tile.withValues(alpha: 0.8), borderRadius: BorderRadius.circular(24), border: Border.all(color: done ? p.border.withValues(alpha: 0) : p.border)),
        child: PixelRow(
          mainAxisSize: MainAxisSize.min,
          children: [
            RollingNumber(value: state.streak, duration: Motion.page, style: style),
            const SizedBox(width: 6),
            Text(state.streak == 1 ? 'DAY' : 'DAYS', style: capsLabel(done ? p.onDone : p.inkMuted)),
          ],
        ),
      ),
    );
  }
}

class _ThemeButton extends StatelessWidget {
  const _ThemeButton();

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return PixelTooltip(
      message: 'Appearance and sync',
      child: Hoverable(
        onTap: () => showAppDialog(context: context, builder: (_) => const AppearanceDialog()),
        builder: (_) => Container(
          padding: const EdgeInsets.all(4),
          decoration: SmoothGradientDecoration(color: p.tile.withValues(alpha: 0.8), shape: BoxShape.circle, border: Border.all(color: p.border)),
          child: _Swatch(palette: p, size: 36),
        ),
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({required this.palette, required this.size});
  final Palette palette;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: SmoothGradientDecoration(
      shape: BoxShape.circle,
      border: Border.all(color: palette.tile, width: size * 0.08),
      gradient: SweepGradient(colors: [...palette.gradient, palette.gradient.first]),
    ),
  );
}

class AppearanceDialog extends StatelessWidget {
  const AppearanceDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final state = AppScope.of(context);
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: SingleChildScrollView(
          padding: dialogPadding,
          child: PixelColumn(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Appearance', style: displayStyle(28, p.ink)),
              const SizedBox(height: 16),
              Text('THEME', style: capsLabel(p.inkMuted)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final palette in palettes)
                    PixelTooltip(
                      message: palette.name,
                      child: Hoverable(
                        onTap: () => state.setTheme(palette.name),
                        builder: (_) => Container(
                          padding: const EdgeInsets.all(2),
                          decoration: SmoothGradientDecoration(shape: BoxShape.circle, border: Border.all(color: p.accent.withValues(alpha: palette.name == state.themeName ? 1 : 0), width: 2)),
                          child: _Swatch(palette: palette, size: 32),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              Text('CHINESE FONT', style: capsLabel(p.inkMuted)),
              const SizedBox(height: 8),
              PixelRow(
                children: [
                  for (final (name, font) in const [('Brush', Fonts.zhKai), ('Clean', Fonts.zhSans)]) ...[
                    Hoverable(
                      onTap: () => state.setChineseFont(font),
                      builder: (hover) => AnimatedContainer(
                        duration: context.themed(Motion.hover),
                        curve: Motion.hoverCurve,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: Fonts.zh == font ? p.empty : p.empty.withValues(alpha: hover ? 0.5 : 0),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Fonts.zh == font ? p.accent : p.border),
                        ),
                        child: PixelColumn(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('学习汉字', style: TextStyle(fontFamily: font, fontSize: 22, color: p.ink, height: 1.3, fontVariations: font == Fonts.zhSans ? const [FontVariation('wght', 400)] : null)),
                            Text(name, style: bodyStyle(p.inkMuted, size: 12)),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                ],
              ),
              const SizedBox(height: 20),
              if (state.sync case final sync?) ...[
                Text('GOOGLE SYNC', style: capsLabel(p.inkMuted)),
                const SizedBox(height: 8),
                SyncSection(sync: sync),
                const SizedBox(height: 20),
              ],
              Text('WHERE THE COURSE COMES FROM', style: capsLabel(p.inkMuted)),
              const SizedBox(height: 8),
              Text(
                'Words from the HSK 3.0 list, meanings from CC-CEDICT, character parts from Make Me a Hanzi. Sentences were written by native speakers on Tatoeba (CC BY). Reading passages labelled AI, grammar notes and some short meanings were written by AI, and passages are never tested.',
                style: bodyStyle(p.inkMuted, size: 14),
              ),
              const SizedBox(height: 12),
              Align(alignment: Alignment.centerRight, child: PillButton(label: 'Done', primary: true, onTap: () => Navigator.of(context).pop())),
            ],
          ),
        ),
      ),
    );
  }
}
