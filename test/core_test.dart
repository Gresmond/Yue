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
    void answerRight(Session s) {
      final step = s.current;
      if (step is Check) s.answer(Rating.good);
      if (step is MatchPairs) {
        for (final w in step.words) {
          s.answerMatch(w, correct: true);
        }
      }
    }

    void runAll(Session s) {
      while (!s.finished) {
        answerRight(s);
        s.next();
      }
    }

    /// Passes [days] days, reviewing everything due correctly each one.
    void reviewFor(AppState state, int days) {
      for (var d = 0; d < days; d++) {
        now = now.add(const Duration(days: 1));
        state.openDay();
        final s = Session.review(state, limit: 100000);
        if (s.steps.isNotEmpty) runAll(s);
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
        answerRight(s);
        s.next();
      }
      final card = (s.current as Check).card;
      final total = s.total;
      final wrongBefore = s.wrong;
      s.answer(Rating.again);
      expect(s.total, total + 1);
      expect(s.wrong, wrongBefore + 1);
      expect(state.cards[card], isNull, reason: 'it joins reviews only once answered correctly');
      s.next();
      while (s.current is! Check || (s.current as Check).card != card) {
        answerRight(s);
        s.next();
      }
      s.answer(Rating.good);
      expect(s.wrong, wrongBefore + 1);
      expect(state.cards[card]!.lapses, 0);
      expect(state.cards[card]!.reps, 1);
      expect(state.cards[card]!.stability, Fsrs.w[Rating.hard.value - 1]);
    });

    test('nothing is tested straight after its own card', () {
      for (final lesson in [course.levels.first.lessons.first, course.levels.last.lessons.last]) {
        final state = open();
        state.learned.addAll(course.words.keys.take(40));
        final steps = Session.forLesson(state, lesson).steps;
        for (var i = 0; i + 1 < steps.length; i++) {
          final (a, b) = (steps[i], steps[i + 1]);
          if (a is TeachWord && b is MatchPairs) expect(b.fresh, isNot(contains(a.word)));
        }
        final checked = steps.whereType<MatchPairs>().expand((m) => m.fresh).map((w) => w.w).toList();
        expect(checked..sort(), lesson.words.toList()..sort(), reason: 'every word is checked once');
      }
    });

    test('a first lesson shows only what it has taught, and no radicals', () {
      final state = open();
      final lesson = course.levels.first.lessons.first;
      final steps = Session.forLesson(state, lesson).steps;
      final taught = <String>{};
      for (final step in steps) {
        if (step is TeachWord) {
          taught.add(step.word.w);
          for (final t in step.example?.toks ?? const <String>[]) {
            if (course.words.containsKey(t) && !course.names.containsKey(t)) expect(taught, contains(t));
          }
        }
        if (step is MatchPairs) {
          for (final w in step.words) {
            expect(taught, contains(w.w), reason: 'a match holds only words already taught');
          }
        }
      }
    });

    test('a missed match joins reviews only when got right on a later check', () {
      final state = open();
      final s = Session.forLesson(state, state.nextLesson!);
      while (s.current is! MatchPairs) {
        s.next();
      }
      final first = s.current as MatchPairs;
      final word = first.fresh.first;
      s.answerMatch(word, correct: false);
      s.answerMatch(word, correct: true);
      expect(state.cards['wr:${word.w}'], isNull);
      final total = s.total;
      s.next();
      expect(s.total, total + 1);
      while (s.current is! MatchPairs || !(s.current as MatchPairs).fresh.contains(word)) {
        answerRight(s);
        s.next();
      }
      answerRight(s);
      expect(state.cards['wr:${word.w}']!.stability, Fsrs.w[Rating.hard.value - 1]);
      expect(s.wrong, 1);
    });

    test('doing a finished lesson again is practice: schedules stay put', () {
      final state = open();
      final lesson = state.nextLesson!;
      runAll(Session.forLesson(state, lesson));
      final before = {for (final e in state.cards.entries) e.key: e.value.reps};
      final lessons = state.today.lessons;
      runAll(Session.forLesson(state, lesson));
      expect({for (final e in state.cards.entries) e.key: e.value.reps}, before);
      expect(state.today.lessons, lessons);
    });

    test('old radical cards never come due', () {
      var state = open();
      state.store.saveReview('rad:亻', Fsrs.review(null, Rating.good, 0), Rating.good, 0);
      state = open();
      expect(state.cards.keys.where((id) => id.startsWith('rad:')), isEmpty);
      expect(state.dueCount, 0);
    });

    test('cards for things the course no longer has never come due', () {
      var state = open();
      state.store.saveReview('sr:gone', Fsrs.review(null, Rating.good, 0), Rating.good, 0);
      state.store.saveReview('wr:不在課程', Fsrs.review(null, Rating.good, 0), Rating.good, 0);
      state = open();
      expect(state.cards, isEmpty);
      expect(state.learned, isEmpty);
      expect(state.dueCount, 0);
    });

    test('no match holds two words with the same meaning, and every word gets one', () {
      final state = open();
      for (final l in state.course.levels) {
        for (final lesson in l.lessons) {
          final matches = Session.forLesson(state, lesson).steps.whereType<MatchPairs>().toList();
          for (final m in matches) {
            expect(m.meanings.toSet().length, m.meanings.length, reason: '${lesson.id}: ${m.meanings}');
          }
          expect(matches.expand((m) => m.fresh).map((w) => w.w).toList()..sort(), lesson.words.toList()..sort(), reason: lesson.id);
        }
      }
    });

    test('a level clears once its lessons are done and 90% of its words are held', () {
      final state = open();
      final level = state.level;
      for (final lesson in level.lessons) {
        runAll(Session.forLesson(state, lesson));
      }
      expect(state.nextLesson, isNull);
      expect(state.level.n, 1, reason: 'finishing every lesson isn\'t enough: nothing has held yet');
      reviewFor(state, 6);
      expect(state.heldInLevel(level), greaterThanOrEqualTo(state.heldNeeded(level)));
      expect(state.level.n, 2);
      expect(state.passed, 1);
      // A level stays cleared, including after a restart.
      expect(open().passed, 1);
    });

    test('a level with every word held still waits for its lessons', () {
      final state = open();
      final level = state.level;
      for (final lesson in level.lessons.take(level.lessons.length - 1)) {
        runAll(Session.forLesson(state, lesson));
      }
      reviewFor(state, 6);
      expect(state.heldInLevel(level), greaterThanOrEqualTo(state.heldNeeded(level)));
      expect(state.level.n, 1, reason: 'a lesson is still to do');
      runAll(Session.forLesson(state, level.lessons.last));
      expect(state.level.n, 2);
    });

    /// All of [level] held, and every level before it cleared.
    AppState reachExam(Level level) {
      final state = open();
      for (final l in state.course.levels.where((l) => l.n <= level.n)) {
        for (final lesson in l.lessons) {
          state.finishLesson(lesson);
          for (final w in lesson.words) {
            state.store.saveReview('wr:$w', Fsrs.review(null, Rating.easy, state.nowMs), Rating.easy, 0);
          }
        }
      }
      return open();
    }

    test('a band ends in an exam covering all of it: passing opens the next, failing doesn\'t', () {
      final last = course.levels.lastWhere((l) => l.band == 1);
      final state = reachExam(last);
      expect(state.level.n, last.n);
      expect(state.examReady, isTrue);
      final fail = Session.exam(state, last);
      expect(fail.steps.whereType<ExamRead>().length, 10);
      while (!fail.finished) {
        fail.answer(Rating.again);
        fail.next();
      }
      expect(state.level.n, last.n);
      final pass = Session.exam(state, last);
      final levels = course.levels.where((l) => l.band == 1).map((l) => l.n).toSet();
      expect(pass.steps.whereType<ExamRead>().every((e) => e.sentence.level <= last.n), isTrue);
      expect(levels.length, greaterThan(1));
      runAll(pass);
      expect(state.level.n, last.n + 1);
      expect(state.level.band, 2);
    });

    test('new lessons stop once today\'s time or the coming reviews are full', () {
      final state = open();
      expect(state.dailyMinutes, 20);
      expect(state.canLearnToday, isTrue);
      state.finishLesson(state.nextLesson!);
      expect(state.canLearnToday, isTrue);
      state.finishLesson(state.nextLesson!);
      expect(state.canLearnToday, isFalse, reason: 'two lessons fill 20 minutes');
      state.setDailyMinutes(40);
      expect(state.canLearnToday, isTrue);
      expect(open().dailyMinutes, 40);

      // A big pile of young cards: tomorrow still says no.
      for (var i = 0; i < 400; i++) {
        state.rate('wr:${course.words.keys.elementAt(i)}', Rating.good, isReview: false);
      }
      now = now.add(const Duration(days: 1));
      state.openDay();
      expect(state.minutesToday, 0);
      expect(state.canLearnToday, isFalse);
    });

    test('reading coverage counts only words held in memory', () {
      final state = open();
      expect(state.readingCoverage, 0);
      runAll(Session.forLesson(state, state.nextLesson!));
      expect(state.readingCoverage, 0, reason: 'just learned, not yet held');
      reviewFor(state, 6);
      expect(state.readingCoverage, greaterThan(0));
      expect(state.readingCoverage, lessThan(1));
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

