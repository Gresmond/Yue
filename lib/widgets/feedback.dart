import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'appear.dart';
import 'hover_fill.dart';
import 'mark.dart';

/// Something small you press, which lifts under the pointer and dips as it's
/// pressed, by as much as Eclipse's ritual squares do.
class Pressable extends StatefulWidget {
  const Pressable({super.key, this.onTap, this.cursor, this.interactive, required this.builder});

  final VoidCallback? onTap;
  final MouseCursor? cursor;

  /// Whether it lifts and dips; by default, whether it can be tapped.
  final bool? interactive;
  final Widget Function(bool hover) builder;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _pressed = false;

  void _press(bool pressed) {
    // A tile can be taken away while it's held, as a dragged one is.
    if (mounted && pressed != _pressed) setState(() => _pressed = pressed);
  }

  @override
  Widget build(BuildContext context) {
    final on = widget.interactive ?? widget.onTap != null;
    return Listener(
      onPointerDown: on ? (_) => _press(true) : null,
      onPointerUp: (_) => _press(false),
      onPointerCancel: (_) => _press(false),
      child: Hoverable(
        onTap: widget.onTap,
        cursor: widget.cursor,
        builder: (hover) => PressScale(hover: on && hover, pressed: on && _pressed, lift: 1.04, dip: 0.91, child: widget.builder(hover)),
      ),
    );
  }
}

/// [child], until there's a verdict: then a tick or a cross grows in over it,
/// from 60%, with Eclipse's mark. It stays what it was as it fades back out.
class VerdictMark extends StatefulWidget {
  const VerdictMark({super.key, required this.right, required this.child, this.size = 22, this.alignment = Alignment.centerLeft});

  /// Null until decided.
  final bool? right;
  final double size;
  final Alignment alignment;
  final Widget child;

  @override
  State<VerdictMark> createState() => _VerdictMarkState();
}

class _VerdictMarkState extends State<VerdictMark> {
  late bool _last = widget.right ?? true;

  @override
  void didUpdateWidget(VerdictMark old) {
    super.didUpdateWidget(old);
    _last = widget.right ?? _last;
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return TweenAnimationBuilder<double>(
      tween: Tween(end: widget.right == null ? 0 : 1),
      duration: Motion.click,
      curve: Motion.clickCurve,
      child: widget.child,
      builder: (context, amount, child) => Stack(
        alignment: widget.alignment,
        children: [
          Opacity(opacity: 1 - amount, child: child),
          CustomPaint(
            size: Size.square(widget.size),
            painter: _MarkPainter(
              icon: _last ? Icons.check_rounded : Icons.close_rounded,
              color: _last ? Color.lerp(p.done, p.ink, 0.3)! : p.missedInk,
              amount: amount,
            ),
          ),
        ],
      ),
    );
  }
}

class _MarkPainter extends CustomPainter {
  const _MarkPainter({required this.icon, required this.color, required this.amount});

  final IconData icon;
  final Color color;
  final double amount;

  @override
  void paint(Canvas canvas, Size size) => paintMark(canvas, size.center(Offset.zero), icon, size.width, color, amount);

  @override
  bool shouldRepaint(_MarkPainter old) => old.icon != icon || old.color != color || old.amount != amount;
}

/// What [builder] makes, opening its room and fading in while [open], and
/// closing and fading out when not. Nothing is built while it's shut.
class Unfold extends StatefulWidget {
  const Unfold({super.key, required this.open, required this.builder});

  final bool open;
  final WidgetBuilder builder;

  @override
  State<Unfold> createState() => _UnfoldState();
}

class _UnfoldState extends State<Unfold> {
  late bool _present = widget.open;

  // Open from the start, it's simply there.
  late final bool _animate = !widget.open;

  @override
  void didUpdateWidget(Unfold old) {
    super.didUpdateWidget(old);
    if (widget.open) _present = true;
  }

  @override
  Widget build(BuildContext context) {
    if (!_present) return const SizedBox(width: double.infinity);
    return Appear(
      animate: _animate,
      shown: widget.open,
      onHidden: () => setState(() => _present = false),
      child: Builder(builder: widget.builder),
    );
  }
}
