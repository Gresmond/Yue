import 'dart:math';

import '../data/curriculum.dart';
import '../data/fsrs.dart';
import 'app_state.dart';

/// One thing on screen during a session.
sealed class Step {
  const Step();
}

class TeachRadical extends Step {
  const TeachRadical(this.radical);
  final Radical radical;
}

class TeachWord extends Step {
  const TeachWord(this.word);
  final Word word;
}

class TeachGrammar extends Step {
  const TeachGrammar(this.grammar);
  final Grammar grammar;
}

/// A step with a right answer, recorded the first time it's tried.
sealed class Check extends Step {
  const Check(this.card);
  final String card;
}

/// See the Chinese, choose its meaning: just after a word is taught.
class ChooseMeaning extends Check {
  ChooseMeaning(this.word, this.options) : super('wr:${word.w}');
  final Word word;
  final List<String> options;
}

/// See the Chinese, recall the meaning, and say how it went.
class RecallWord extends Check {
  RecallWord(this.word) : super('wr:${word.w}');
  final Word word;
}

class RecallRadical extends Check {
  RecallRadical(this.radical) : super('rad:${radical.r}');
  final Radical radical;
}

/// See the English, type the pinyin, then pick the characters.
class WriteWord extends Check {
  WriteWord(this.word, this.options) : super('ww:${word.w}');
  final Word word;
  final List<Word> options;
}

class ReadSentence extends Check {
  ReadSentence(this.sentence) : super('sr:${sentence.id}');
  final Sentence sentence;
}

/// See the English, put the words in order.
class BuildSentence extends Check {
  BuildSentence(this.sentence, this.tiles) : super('sb:${sentence.id}');
  final Sentence sentence;
  final List<String> tiles;
}

/// An unseen sentence, with a choice of translations: only in exams.
class ExamRead extends Check {
  ExamRead(this.sentence, this.options) : super('exam:${sentence.id}');
  final Sentence sentence;
  final List<String> options;
}

enum SessionKind { review, lesson, exam }

/// A run of steps. A wrong answer sends the step round again later, but only the
/// first try is recorded. Answers in an exam change no schedule.
class Session {
  Session._(this.state, this.kind, this.steps, {this.lesson, this.level}) : total = steps.length, litBefore = state.learnedChars.toSet(), startedAt = state.nowMs;

  final AppState state;
  final SessionKind kind;
  final List<Step> steps;
  final Lesson? lesson;
  final Level? level;
  final Set<String> litBefore;
  final int startedAt;
  int total, index = 0, right = 0, wrong = 0;

  /// Which steps have had their first try, and which of those were missed.
  final _tried = <Step>{};
  final missed = <Step>{};
  int attempt = 0;
  bool finished = false;

  Step get current => steps[index];
  int get answered => right + wrong;
  double get progress => total == 0 ? 1 : index / total;

  /// Records [rating], and if it was a miss sends the step round again.
  void answer(Rating rating, {int takenMs = 0}) {
    final step = current;
    if (step is! Check) return;
    final first = _tried.add(step);
    final ok = rating != Rating.again;
    if (first) {
      ok ? right++ : wrong++;
      if (!ok) missed.add(step);
      if (kind != SessionKind.exam) {
        // A word met for the first time is teaching, not a review.
        state.rate(step.card, rating, takenMs: takenMs, isReview: kind == SessionKind.review);
      }
    }
    if (!ok && kind != SessionKind.exam) {
      final at = min(index + 4, steps.length);
      steps.insert(at, step);
      total++;
    }
  }

  void next() {
    attempt++;
    if (index + 1 >= steps.length) {
      finished = true;
      if (lesson != null) state.finishLesson(lesson!);
      if (kind == SessionKind.exam) {
        state.finishExam(level!, score, missed.map(_missedCard).nonNulls);
      }
      return;
    }
    index++;
  }

  double get score => answered == 0 ? 0 : right / answered;

  /// What to bring back after a failed exam.
  String? _missedCard(Step s) => s is WriteWord ? 'ww:${s.word.w}' : null;

  // ---- Building.

  static Session review(AppState state, {int limit = 40}) {
    final random = Random();
    final ids = state.dueIds.take(limit).toList()..shuffle(random);
    final steps = <Step>[for (final id in ids) ?_stepFor(state, id, random)];
    return Session._(state, SessionKind.review, steps);
  }

  static Step? _stepFor(AppState state, String id, Random random) {
    final course = state.course;
    final key = id.substring(id.indexOf(':') + 1);
    if (id.startsWith('wr:')) return switch (course.words[key]) { final w? => RecallWord(w), _ => null };
    if (id.startsWith('ww:')) return switch (course.words[key]) { final w? => WriteWord(w, writeOptions(course, w, random)), _ => null };
    if (id.startsWith('rad:')) return switch (course.radicals[key]) { final r? => RecallRadical(r), _ => null };
    final s = course.sentences[key];
    if (s == null) return null;
    if (id.startsWith('sr:')) return ReadSentence(s);
    if (id.startsWith('sb:')) return BuildSentence(s, tilesFor(s, random));
    return null;
  }

  static Session forLesson(AppState state, Lesson lesson) {
    final course = state.course;
    final random = Random();
    final steps = <Step>[];
    for (final r in lesson.radicals) {
      if (course.radicals[r] case final radical?) {
        steps.add(TeachRadical(radical));
        steps.add(RecallRadical(radical));
      }
    }
    final words = [for (final w in lesson.words) ?course.words[w]];
    // Three at a time: meet them, then choose each one's meaning.
    for (var i = 0; i < words.length; i += 3) {
      final group = words.sublist(i, min(i + 3, words.length));
      steps.addAll(group.map(TeachWord.new));
      steps.addAll(
        (group.toList()..shuffle(random)).map((w) => ChooseMeaning(w, meaningOptions(state, w, random))),
      );
    }
    for (final g in lesson.grammar) {
      if (course.grammar[g] case final grammar?) steps.add(TeachGrammar(grammar));
    }
    steps.addAll((words.toList()..shuffle(random)).map((w) => WriteWord(w, writeOptions(course, w, random))));
    final sentences = [for (final id in lesson.sentences) ?course.sentences[id]];
    for (final s in sentences) {
      steps.add(ReadSentence(s));
    }
    for (final s in sentences.where(_buildable).take(2)) {
      steps.add(BuildSentence(s, tilesFor(s, random)));
    }
    return Session._(state, SessionKind.lesson, steps, lesson: lesson);
  }

  /// Ten unseen sentences to read, four to build, six words to write.
  static Session exam(AppState state, Level level) {
    final course = state.course;
    final random = Random();
    final pool = [for (final id in level.exam) ?course.sentences[id]]..shuffle(random);
    final steps = <Step>[];
    final translations = [for (final s in course.sentences.values) if (s.exam && s.level <= level.n) s.en];
    final reading = pool.take(10).toList();
    for (final s in reading) {
      final wrong = (translations.where((e) => e != s.en).toList()..shuffle(random)).take(3);
      steps.add(ExamRead(s, [s.en, ...wrong]..shuffle(random)));
    }
    final builds = pool.skip(reading.length).where(_buildable).take(4).toList();
    if (builds.length < 4) builds.addAll(reading.where(_buildable).take(4 - builds.length));
    for (final s in builds) {
      steps.add(BuildSentence(s, tilesFor(s, random)));
    }
    final words = [for (final l in level.lessons) for (final w in l.words) ?course.words[w]]..shuffle(random);
    for (final w in words.take(6)) {
      steps.add(WriteWord(w, writeOptions(course, w, random)));
    }
    return Session._(state, SessionKind.exam, steps, level: level);
  }

  static bool _buildable(Sentence s) {
    final n = _tileTokens(s).length;
    return n >= 2 && n <= 9;
  }

  static List<String> _tileTokens(Sentence s) => s.toks.where((t) => RegExp(r'[一-鿿0-9]').hasMatch(t)).toList();

  static List<String> tilesFor(Sentence s, Random random) {
    final tiles = _tileTokens(s);
    final answer = tiles.join();
    // Never start with them already in order.
    for (var i = 0; i < 8; i++) {
      tiles.shuffle(random);
      if (tiles.join() != answer) break;
    }
    return tiles;
  }

  static String buildAnswer(Sentence s) => _tileTokens(s).join();

  static List<String> meaningOptions(AppState state, Word word, Random random) {
    final course = state.course;
    final pool = [
      for (final other in course.words.values)
        if (other.band == word.band && other.w != word.w && other.en != word.en) other.en,
    ]..shuffle(random);
    return [word.en, ...pool.take(3)]..shuffle(random);
  }

  /// The right word among ones that sound the same or share a character,
  /// as on a real Chinese keyboard.
  static List<Word> writeOptions(Curriculum course, Word word, Random random) {
    final out = <Word>{word};
    final same = (course.byPinyin[toneless(word.py)] ?? const <Word>[]).toList()..shuffle(random);
    out.addAll(same.take(3));
    for (final c in word.w.split('')) {
      if (out.length >= 6) break;
      final shares = (course.byChar[c] ?? const <Word>[]).where((w) => w.w.length == word.w.length).toList()..shuffle(random);
      out.addAll(shares.take(2));
    }
    // Then words that look alike: the same radical at the start.
    if (out.length < 6) {
      final rad = course.chars[word.w[0]]?.radical;
      final alike = course.words.values.where((w) => w.w.length == word.w.length && course.chars[w.w[0]]?.radical == rad && w.band <= word.band + 1).toList()..shuffle(random);
      out.addAll(alike.take(6 - out.length));
    }
    // A word with no near neighbours still gets a real choice.
    if (out.length < 6) {
      final rest = course.words.values.where((w) => w.w.length == word.w.length && w.band == word.band).toList()..shuffle(random);
      out.addAll(rest.take(6 - out.length));
    }
    if (out.length < 4) {
      final rest = course.words.values.where((w) => w.band == word.band).toList()..shuffle(random);
      out.addAll(rest.take(4 - out.length));
    }
    final list = out.take(6).toList();
    if (!list.contains(word)) list[0] = word;
    return list..shuffle(random);
  }
}
