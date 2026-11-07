import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yue/data/curriculum.dart';
import 'package:yue/data/store.dart';
import 'package:yue/main.dart';
import 'package:yue/screens/session_screen.dart';
import 'package:yue/screens/shell.dart';
import 'package:yue/state/app_state.dart';
import 'package:yue/state/session.dart';
import 'package:yue/theme/app_theme.dart';
import 'package:yue/widgets/app_dialog.dart';

/// Picks up [from] and lets go on [to], as a mouse would.
Future<void> dragOnto(WidgetTester t, Finder from, Finder to) async {
  final target = t.getCenter(to);
  final gesture = await t.startGesture(t.getCenter(from));
  await t.pump();
  await gesture.moveBy(const Offset(0, 20));
  await t.pump();
  await gesture.moveTo(target);
  await t.pump();
  await gesture.up();
  await t.pump();
}

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
      } else if (find.text('MATCH THE PAIRS').evaluate().isNotEmpty) {
        // Drag each character onto its meaning.
        final all = course.words.values.where((w) => find.text(w.w).evaluate().isNotEmpty && find.text(w.en).evaluate().isNotEmpty).toList();
        expect(all.length, greaterThan(1));
        for (final w in all) {
          await dragOnto(t, find.text(w.w), find.text(w.en));
          await t.pump(const Duration(milliseconds: 300));
        }
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
        await press(digits[0]);
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

  group('match by dragging', () {
    Future<(AppState, Session, MatchPairs)> open(WidgetTester t) async {
      t.view.physicalSize = const Size(1240, 860);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final course = Curriculum(jsonDecode(utf8.decode(gzip.decode(File('assets/curriculum.json.gz').readAsBytesSync()))));
      final dir = Directory.systemTemp.createTempSync('yue-ui');
      addTearDown(() => dir.deleteSync(recursive: true));
      final state = AppState(Store.open(dir.path), course);
      final s = Session.forLesson(state, state.nextLesson!);
      while (s.current is! MatchPairs) {
        s.next();
      }
      await t.pumpWidget(
        AppScope(
          state: state,
          child: MaterialApp(
            theme: themeNamed(state.themeName),
            home: Scaffold(body: SessionScreen(session: s, onClose: () {}, onAgain: (_) {})),
          ),
        ),
      );
      await t.pumpAndSettle();
      return (state, s, s.current as MatchPairs);
    }

    testWidgets('a meaning can be dragged onto its word, and glides beside it', (t) async {
      final (_, s, step) = await open(t);
      final word = step.words.first;
      await dragOnto(t, find.text(word.en), find.text(word.w));
      await t.pumpAndSettle();
      expect(t.getCenter(find.text(word.en)).dy, closeTo(t.getCenter(find.text(word.w)).dy, 1));
      expect(s.wrong, 0);
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 1));
    });

    testWidgets('a wrong drop stands: it can\'t be corrected, and the answer is shown', (t) async {
      final (_, s, step) = await open(t);
      final word = step.fresh.first;
      final other = step.words.firstWhere((w) => w != word);
      await dragOnto(t, find.text(word.w), find.text(other.en));
      expect(s.wrong, 1);
      // Nothing moves while the mistake shows, and the real answer doesn't count.
      await dragOnto(t, find.text(word.w), find.text(word.en));
      expect(step.missed, contains(word));
      await t.pump(const Duration(milliseconds: 700));
      await t.pumpAndSettle();
      expect(t.getCenter(find.text(word.en)).dy, closeTo(t.getCenter(find.text(word.w)).dy, 1));
      // Now it's out of play: dragging it does nothing, and it stays missed.
      await dragOnto(t, find.text(word.w), find.text(word.en));
      expect(step.missed, contains(word));
      expect(s.right, 0);
      // The others finish the round, which then waits to be moved on from.
      for (final w in step.words.where((w) => w != word)) {
        await dragOnto(t, find.text(w.w), find.text(w.en));
        await t.pump(const Duration(milliseconds: 300));
      }
      await t.pump(const Duration(seconds: 1));
      await t.pumpAndSettle();
      expect(find.text('Continue'), findsOneWidget);
      final before = s.index;
      await t.tap(find.text('Continue'));
      await t.pumpAndSettle();
      expect(s.index, before + 1);
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 1));
    });

    testWidgets('let go anywhere else and nothing is recorded', (t) async {
      final (_, s, step) = await open(t);
      final gesture = await t.startGesture(t.getCenter(find.text(step.words.first.w)));
      await t.pump();
      await gesture.moveBy(const Offset(0, -400));
      await t.pump();
      await gesture.up();
      await t.pumpAndSettle();
      expect(s.right + s.wrong, 0);
      expect(step.missed, isEmpty);
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 1));
    });

    testWidgets('the digits still match', (t) async {
      final (_, s, step) = await open(t);
      final word = step.fresh.first;
      await t.sendKeyEvent(const [LogicalKeyboardKey.digit1, LogicalKeyboardKey.digit2, LogicalKeyboardKey.digit3][step.words.indexOf(word)]);
      await t.pump();
      const keys = [LogicalKeyboardKey.digit1, LogicalKeyboardKey.digit2, LogicalKeyboardKey.digit3, LogicalKeyboardKey.digit4, LogicalKeyboardKey.digit5, LogicalKeyboardKey.digit6];
      await t.sendKeyEvent(keys[step.words.length + step.meanings.indexOf(word.en)]);
      await t.pumpAndSettle();
      expect(s.right, 1);
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 1));
    });
  });

  testWidgets('an AI sentence is read and moved on from, with nothing asked', (t) async {
    t.view.physicalSize = const Size(1240, 860);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final course = Curriculum(jsonDecode(utf8.decode(gzip.decode(File('assets/curriculum.json.gz').readAsBytesSync()))));
    final dir = Directory.systemTemp.createTempSync('yue-ui');
    addTearDown(() => dir.deleteSync(recursive: true));
    final state = AppState(Store.open(dir.path), course);
    final lesson = course.levels.expand((l) => l.lessons).firstWhere((l) => l.sentences.any((id) => course.sentences[id]!.ai));
    final s = Session.forLesson(state, lesson);
    while (s.current is! ReadAlong) {
      s.next();
    }
    final at = s.index;
    await t.pumpWidget(
      AppScope(
        state: state,
        child: MaterialApp(
          theme: themeNamed(state.themeName),
          home: Scaffold(body: SessionScreen(session: s, onClose: () {}, onAgain: (_) {})),
        ),
      ),
    );
    await t.pumpAndSettle();
    await t.tap(find.text('Show meaning'));
    await t.pumpAndSettle();
    expect(find.textContaining('AI-written'), findsOneWidget);
    expect(find.text('Understood'), findsNothing);
    await t.tap(find.text('Continue'));
    await t.pumpAndSettle();
    expect(s.index, at + 1);
    expect(s.answered, 0);
  });

  testWidgets('wrong pinyin gets no second try: the answer shows, and it comes round again', (t) async {
    t.view.physicalSize = const Size(1240, 860);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final course = Curriculum(jsonDecode(utf8.decode(gzip.decode(File('assets/curriculum.json.gz').readAsBytesSync()))));
    final dir = Directory.systemTemp.createTempSync('yue-ui');
    addTearDown(() => dir.deleteSync(recursive: true));
    final state = AppState(Store.open(dir.path), course);
    final s = Session.forLesson(state, state.nextLesson!);
    while (s.current is! WriteWord) {
      s.next();
    }
    final step = s.current as WriteWord;
    final steps = s.steps.length;
    await t.pumpWidget(
      AppScope(
        state: state,
        child: MaterialApp(
          theme: themeNamed(state.themeName),
          home: Scaffold(body: SessionScreen(session: s, onClose: () {}, onAgain: (_) {})),
        ),
      ),
    );
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField), 'qqqq');
    await t.testTextInput.receiveAction(TextInputAction.done);
    await t.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
    expect(find.text(step.word.w), findsOneWidget);
    expect(find.text('Continue'), findsOneWidget);
    expect(s.wrong, 1);
    expect(s.steps.length, steps + 1);
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 1));
  });

  testWidgets('a build tile can be dragged in, reordered, and dragged back', (t) async {
    t.view.physicalSize = const Size(1240, 860);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final course = Curriculum(jsonDecode(utf8.decode(gzip.decode(File('assets/curriculum.json.gz').readAsBytesSync()))));
    final dir = Directory.systemTemp.createTempSync('yue-ui');
    addTearDown(() => dir.deleteSync(recursive: true));
    final state = AppState(Store.open(dir.path), course);
    final s = Session.forLesson(state, state.nextLesson!);
    while (s.current is! BuildSentence) {
      s.next();
    }
    final step = s.current as BuildSentence;
    await t.pumpWidget(
      AppScope(
        state: state,
        child: MaterialApp(
          theme: themeNamed(state.themeName),
          home: Scaffold(body: SessionScreen(session: s, onClose: () {}, onAgain: (_) {})),
        ),
      ),
    );
    await t.pumpAndSettle();
    final tile = find.text(step.tiles.first).first;
    final start = t.getCenter(tile);
    final prompt = t.getCenter(find.text(step.sentence.en));
    // Between the prompt and the tray lies the sentence being built.
    final zone = Offset(start.dx, start.dy - 60);
    expect(zone.dy, greaterThan(prompt.dy));
    final gesture = await t.startGesture(start);
    await t.pump();
    await gesture.moveBy(const Offset(0, -20));
    await t.pump();
    await gesture.moveTo(zone);
    await t.pump();
    await t.pump();
    await gesture.up();
    await t.pumpAndSettle();
    expect(find.text(step.tiles.first), findsNWidgets(2), reason: 'placed, with its ghost in the tray');
    // Dragged back over the tray, it leaves the sentence.
    final back = await t.startGesture(t.getCenter(find.text(step.tiles.first).first));
    await t.pump();
    await back.moveBy(const Offset(0, 20));
    await t.pump();
    await back.moveTo(start);
    await t.pump();
    await back.up();
    await t.pumpAndSettle();
    expect(find.text(step.tiles.first), findsOneWidget);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 1));
  });

  testWidgets('every theme can be reached from the menu in a short window', (t) async {
    t.view.physicalSize = const Size(900, 500);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final course = Curriculum(jsonDecode(utf8.decode(gzip.decode(File('assets/curriculum.json.gz').readAsBytesSync()))));
    final dir = Directory.systemTemp.createTempSync('yue-ui');
    addTearDown(() => dir.deleteSync(recursive: true));
    final state = AppState(Store.open(dir.path), course);
    await t.pumpWidget(YueApp(state: state));
    await t.pumpAndSettle();
    await t.tap(find.byTooltip('Appearance'));
    await t.pumpAndSettle();
    final last = find.text(palettes.last.name);
    await t.drag(find.text(palettes.first.name), const Offset(0, -1000));
    await t.pumpAndSettle();
    expect(t.getCenter(last).dy, lessThan(500));
    await t.tap(last);
    await t.pumpAndSettle();
    expect(state.themeName, palettes.last.name);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 1));
  });

  testWidgets('daily study time can be changed, and is kept', (t) async {
    t.view.physicalSize = const Size(1240, 860);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final course = Curriculum(jsonDecode(utf8.decode(gzip.decode(File('assets/curriculum.json.gz').readAsBytesSync()))));
    final dir = Directory.systemTemp.createTempSync('yue-ui');
    addTearDown(() => dir.deleteSync(recursive: true));
    final state = AppState(Store.open(dir.path), course);
    await t.pumpWidget(YueApp(state: state));
    await t.pumpAndSettle();
    showAppDialog(context: t.element(find.text('Today')), builder: (_) => const SettingsDialog());
    await t.pumpAndSettle();
    expect(find.text('20 min'), findsOneWidget);
    await t.tap(find.text('40 min'));
    await t.pumpAndSettle();
    expect(state.dailyMinutes, 40);
    expect(AppState(state.store, course).dailyMinutes, 40);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 1));
  });
}
