import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yue/data/curriculum.dart';
import 'package:yue/data/store.dart';
import 'package:yue/main.dart';
import 'package:yue/state/app_state.dart';
import 'package:yue/state/session.dart';

void main() {
  testWidgets('a whole first lesson works from the keyboard and mouse', (t) async {
    t.view.physicalSize = const Size(1240, 860);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final course = Curriculum(jsonDecode(utf8.decode(gzip.decode(File('assets/curriculum.json.gz').readAsBytesSync()))));
    final dir = Directory.systemTemp.createTempSync('yue-ui');
    addTearDown(() => dir.deleteSync(recursive: true));
    final state = AppState(Store.open(dir.path), course);
    final lesson = state.nextLesson!;
    await t.pumpWidget(YueApp(state: state));
    await t.pumpAndSettle();

    await t.tap(find.text('Start lesson'));
    await t.pumpAndSettle();

    const digits = [LogicalKeyboardKey.digit1, LogicalKeyboardKey.digit2, LogicalKeyboardKey.digit3, LogicalKeyboardKey.digit4, LogicalKeyboardKey.digit5, LogicalKeyboardKey.digit6];
    Future<void> press(LogicalKeyboardKey k) async {
      await t.sendKeyEvent(k);
      await t.pump(const Duration(milliseconds: 600));
      await t.pumpAndSettle();
    }

    for (var guard = 0; guard < 200 && find.text('Lesson done').evaluate().isEmpty; guard++) {
      if (find.text('Continue').evaluate().isNotEmpty) {
        await press(LogicalKeyboardKey.space);
      } else if (find.text('Show answer').evaluate().isNotEmpty || find.text('Show meaning').evaluate().isNotEmpty) {
        await press(LogicalKeyboardKey.space);
      } else if (find.text('Knew it').evaluate().isNotEmpty || find.text('Understood').evaluate().isNotEmpty) {
        await press(LogicalKeyboardKey.digit3);
      } else if (find.byType(TextField).evaluate().isNotEmpty) {
        // The English on screen tells us the word.
        final word = lesson.words.map((w) => course.words[w]!).firstWhere((w) => find.text(w.en).evaluate().isNotEmpty);
        await t.enterText(find.byType(TextField), word.py);
        await t.testTextInput.receiveAction(TextInputAction.done);
        await t.pumpAndSettle();
        expect(find.text('Which is right?'), findsOneWidget);
        await t.tap(find.text(word.w).first);
        await t.pump(const Duration(milliseconds: 600));
        await t.pumpAndSettle();
      } else if (find.text('Check').evaluate().isNotEmpty) {
        // Place every tile, right or wrong, then accept the outcome.
        for (var i = 0; i < 12; i++) {
          await t.sendKeyEvent(digits[0]);
          await t.pump();
        }
        await press(LogicalKeyboardKey.enter);
        if (find.text('Mine was fine too').evaluate().isNotEmpty) await t.tap(find.text('Mine was fine too'));
        await t.pumpAndSettle();
      } else {
        // A choice of meanings: take the right one.
        final session = lesson.words.map((w) => course.words[w]!).where((w) => find.text(w.en).evaluate().isNotEmpty && find.text(w.w).evaluate().isNotEmpty);
        if (session.isNotEmpty) {
          await t.tap(find.text(session.first.en));
          await t.pump(const Duration(milliseconds: 600));
          await t.pumpAndSettle();
        } else {
          await press(digits[0]);
        }
      }
    }
    expect(find.text('Lesson done'), findsOneWidget);
    expect(state.lessonDone(lesson), isTrue);
    expect(state.streak, 1);
    expect(find.text('YOU CAN NOW READ THIS'), findsOneWidget);
    expect(t.takeException(), isNull);
    await t.tap(find.text('Done for now'));
    await t.pumpAndSettle();
    expect(find.text('Today'), findsOneWidget);
    // Sessions stay usable when built directly too.
    expect(Session.review(state).steps, isEmpty);
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 1));
  });
}
