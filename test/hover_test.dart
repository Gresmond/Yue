import 'dart:convert';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yue/data/curriculum.dart';
import 'package:yue/data/store.dart';
import 'package:yue/main.dart';
import 'package:yue/state/app_state.dart';
import 'package:yue/theme/app_theme.dart';
import 'package:yue/widgets/hover_fill.dart';

/// What [over] shows through [tint].
Color _shown(Color tint, Color over) => Color.alphaBlend(tint, over);

void main() {
  // Easing a colour from Colors.transparent, which is transparent black, dips
  // through a darker shade on the way: the flicker as the pointer crosses rows.
  testWidgets('a row under the pointer eases straight to its tint', (t) async {
    t.view.physicalSize = const Size(1240, 860);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final course = Curriculum(jsonDecode(utf8.decode(gzip.decode(File('assets/curriculum.json.gz').readAsBytesSync()))));
    final dir = Directory.systemTemp.createTempSync('yue-hover');
    addTearDown(() => dir.deleteSync(recursive: true));
    await t.pumpWidget(YueApp(state: AppState(Store.open(dir.path), course)));
    await t.pumpAndSettle();
    await t.tap(find.text('Words'));
    await t.pumpAndSettle();
    await t.tap(find.text('All'));
    await t.pumpAndSettle();

    Color? tint(Finder row) => (t.widget<DecoratedBox>(find.descendant(of: row, matching: find.byType(DecoratedBox)).first).decoration as BoxDecoration).color;

    final rows = find.descendant(of: find.descendant(of: find.byType(ListView), matching: find.byType(Hoverable)), matching: find.byType(AnimatedContainer));
    final row = rows.evaluate().map((e) => find.byElementPredicate((c) => c == e)).firstWhere((r) => tint(r)?.a == 0);
    final background = t.element(row).palette.background;

    final mouse = await t.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    await t.pump();

    final rest = _shown(tint(row)!, background);
    await mouse.moveTo(t.getCenter(row));
    final seen = <Color>[];
    for (var i = 0; i < 20; i++) {
      await t.pump(const Duration(milliseconds: 8));
      seen.add(_shown(tint(row)!, background));
    }
    final end = seen.last;
    expect(end, isNot(rest));

    double low(double a, double b) => (a < b ? a : b) - 0.004;
    double high(double a, double b) => (a > b ? a : b) + 0.004;
    for (final c in seen) {
      expect(c.r, inInclusiveRange(low(rest.r, end.r), high(rest.r, end.r)));
      expect(c.g, inInclusiveRange(low(rest.g, end.g), high(rest.g, end.g)));
      expect(c.b, inInclusiveRange(low(rest.b, end.b), high(rest.b, end.b)));
    }
  });
}
