import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'task_motion.dart';

/// A [Wrap] whose keyed children glide to their new places when the order or
/// membership changes, on the same timing as Eclipse's reordered tasks. Like
/// those, the movement is paint-only: they're laid out once, at their new
/// places, and only drawn somewhere else.
class GlideWrap extends StatefulWidget {
  const GlideWrap({super.key, this.spacing = 0, this.runSpacing = 0, this.alignment = WrapAlignment.start, required this.children});

  final double spacing, runSpacing;
  final WrapAlignment alignment;
  final List<Widget> children;

  @override
  State<GlideWrap> createState() => _GlideWrapState();
}

class _GlideWrapState extends State<GlideWrap> with SingleTickerProviderStateMixin {
  late final _motion = ReorderMotion(this);

  @override
  void didUpdateWidget(GlideWrap old) {
    super.didUpdateWidget(old);
    final before = old.children.map((c) => c.key).toList(), after = widget.children.map((c) => c.key).toList();
    if (!listEquals(before, after)) {
      _motion.generation++;
      _motion.controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: widget.spacing,
    runSpacing: widget.runSpacing,
    alignment: widget.alignment,
    children: [
      for (final child in widget.children) _GlideBox(key: child.key, progress: _motion.progress, generation: _motion.generation, child: child),
    ],
  );
}

class _GlideBox extends SingleChildRenderObjectWidget {
  const _GlideBox({super.key, required this.progress, required this.generation, required super.child});

  final Animation<double> progress;
  final int generation;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderGlideBox(progress, generation);

  @override
  void updateRenderObject(BuildContext context, _RenderGlideBox renderObject) => renderObject.generation = generation;
}

class _RenderGlideBox extends RenderProxyBox {
  _RenderGlideBox(this.progress, this.generation);

  final Animation<double> progress;
  int generation;
  int? _paintedGeneration;
  Offset? _painted, _from;
  Offset _translation = Offset.zero;

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    progress.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    progress.removeListener(markNeedsPaint);
    super.detach();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final target = localToGlobal(Offset.zero);
    if (_paintedGeneration != generation) {
      // A new one starts in place; a moved one from where it was last drawn.
      _from = _painted ?? target;
      _paintedGeneration = generation;
    }
    final at = progress.value >= 1 ? target : Offset.lerp(_from, target, progress.value)!;
    _painted = at;
    _translation = at - target;
    final child = this.child;
    if (child != null) context.paintChild(child, offset + _translation);
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    transform.translateByDouble(_translation.dx, _translation.dy, 0, 1);
  }

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) => result.addWithPaintOffset(
    offset: _translation,
    position: position,
    hitTest: (result, transformed) => super.hitTest(result, position: transformed),
  );
}
