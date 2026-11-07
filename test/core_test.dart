import 'dart:convert';
import 'dart:math';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yue/data/curriculum.dart';
import 'package:yue/data/fsrs.dart';
import 'package:yue/data/store.dart';
import 'package:yue/state/app_state.dart';
import 'package:yue/state/session.dart';

void main() {
  late Curriculum course;
  late Directory dir;
  late DateTime now;

  setUpAll(() {
    course = Curriculum(jsonDecode(utf8.decode(gzip.decode(File('assets/curriculum.json.gz').readAsBytesSync()))));
  });
  setUp(() {
    dir = Directory.systemTemp.createTempSync('yue-test');
    now = DateTime(2026, 11, 7, 12);
  });
  tearDown(() => dir.deleteSync(recursive: true));

  AppState open() => AppState(Store.open(dir.path), course)..clock = (() => now);

  group('FSRS', () {
    test('matches py-fsrs for a new card', () {
      final m = Fsrs.review(null, Rating.good, 0);
      expect(m.stability, 2.3065);
      expect(m.difficulty, closeTo(2.118104, 0.0001));
      expect(Fsrs.interval(m.stability), 2);
    });
    test('recall is 90% when a card reaches its stability', () {
      expect(Fsrs.recall(10, 10), closeTo(0.9, 0.0001));
    });
    test('a forgotten card comes back soon, a known one later', () {
      final m = Fsrs.review(null, Rating.good, 0);
      final later = 10 * 86400000;
      final good = Fsrs.review(m, Rating.good, later);
      final again = Fsrs.review(m, Rating.again, later);
      expect(good.stability, greaterThan(m.stability));
      expect(again.dueMs, later + Fsrs.relearnMs);
      expect(again.lapses, 1);
    });
  });

  group('Pinyin', () {
    test('tones, spaces, case and ü are forgiven', () {
      expect(pinyinMatches('nihao', 'nǐ hǎo'), isTrue);
      expect(pinyinMatches('Ni3 Hao3', 'nǐ hǎo'), isTrue);
      expect(pinyinMatches('lv', 'lǜ'), isTrue);
      expect(pinyinMatches('lu', 'lǜ'), isTrue);
      expect(pinyinMatches('nihau', 'nǐ hǎo'), isFalse);
    });
  });

  group('Course', () {
    test('every lesson refers to things that exist', () {
      for (final l in course.levels) {
        for (final lesson in l.lessons) {
          expect(lesson.words.every(course.words.containsKey), isTrue);
          expect(lesson.sentences.every(course.sentences.containsKey), isTrue);
          expect(lesson.grammar.every(course.grammar.containsKey), isTrue);
          expect(lesson.radicals.every(course.radicals.containsKey), isTrue);
        }
        expect(l.exam.every(course.sentences.containsKey), isTrue);
        expect(l.exam.length, greaterThanOrEqualTo(12));
      }
    });
    test('no lesson shows an exam sentence, and a lesson\'s sentences use only known words', () {
      final known = <String>{};
      for (final l in course.levels) {
        for (final lesson in l.lessons) {
          known.addAll(lesson.words);
          for (final id in lesson.sentences) {
            final s = course.sentences[id]!;
            expect(s.exam, isFalse);
            for (final t in s.toks) {
              if (course.words.containsKey(t)) expect(known, contains(t), reason: s.zh);
            }
          }
        }
      }
    });
    test('AI passages are the only AI text, and never tested', () {
      expect(course.passages, isNotEmpty);
      final passageText = course.passages.map((p) => p.zh).toSet();
      expect(course.sentences.values.where((s) => passageText.contains(s.zh)), isEmpty);
    });
  });

  group('Sessions', () {
    void runAll(Session s) {
      while (!s.finished) {
        if (s.current is Check) s.answer(Rating.good);
        s.next();
      }
    }

    test('a first lesson teaches, schedules and completes', () {
      final state = open();
      final lesson = state.nextLesson!;
      runAll(Session.forLesson(state, lesson));
      expect(state.lessonDone(lesson), isTrue);
      expect(state.learned, containsAll(lesson.words));
      expect(state.cards['ww:${lesson.words.first}'], isNotNull);
      expect(state.today.complete, isTrue);
      expect(state.streak, 1);
    });

    test('a miss comes round again but is recorded once', () {
      final state = open();
      final lesson = state.nextLesson!;
      final s = Session.forLesson(state, lesson);
      while (s.current is! Check) {
        s.next();
      }
      final card = (s.current as Check).card;
      final total = s.total;
      s.answer(Rating.again);
      expect(s.total, total + 1);
      expect(s.wrong, 1);
      s.next();
      while (s.current is! Check || (s.current as Check).card != card) {
        if (s.current is Check) s.answer(Rating.good);
        s.next();
      }
      s.answer(Rating.good);
      expect(s.right + s.wrong, greaterThan(1));
      expect(state.cards[card]!.lapses, 1);
      expect(state.cards[card]!.reps, 1);
    });

    test('passing the exam opens the next level, failing doesn\'t', () {
      final state = open();
      final level = state.level;
      for (final l in level.lessons) {
        state.finishLesson(l);
      }
      expect(state.nextLesson, isNull);
      final fail = Session.exam(state, level);
      expect(fail.steps.whereType<ExamRead>().length, 10);
      while (!fail.finished) {
        fail.answer(Rating.again);
        fail.next();
      }
      expect(state.level.n, 1);
      final pass = Session.exam(state, level);
      runAll(pass);
      expect(state.level.n, 2);
      expect(state.passed, 1);
    });

    test('exam sentences aren\'t reused as distractor-free giveaways', () {
      final state = open();
      final s = Session.exam(state, state.level);
      for (final step in s.steps.whereType<ExamRead>()) {
        expect(step.options, contains(step.sentence.en));
        expect(step.options.toSet().length, 4);
      }
    });

    test('write options always hold the answer', () {
      final r = Session.review(open());
      expect(r.steps, isEmpty);
      for (final w in course.words.values.take(300)) {
        final options = Session.writeOptions(course, w, _seeded);
        expect(options, contains(w));
        expect(options.length, greaterThan(1));
      }
    });
  });

  group('Streak', () {
    test('runs across days, survives a freeze, breaks without one', () {
      final state = open();
      void earnDay() {
        state.openDay();
        state.finishLesson(state.nextLesson!);
      }

      for (var i = 0; i < 7; i++) {
        earnDay();
        now = now.add(const Duration(days: 1));
      }
      expect(state.streak, 7);
      expect(state.freezes, 1);
      now = now.add(const Duration(days: 1));
      state.openDay();
      expect(state.freezes, 0);
      expect(state.streak, 7);
      now = now.add(const Duration(days: 2));
      state.openDay();
      expect(state.streak, 0);
      expect(state.best, 7);
    });

    test('a late night counts as the day before', () {
      expect(AppState.key(AppState.dayOf(DateTime(2026, 11, 8, 3))), '2026-11-07');
      expect(AppState.key(AppState.dayOf(DateTime(2026, 11, 8, 5))), '2026-11-08');
    });
  });
}

final _seeded = Random(7);

