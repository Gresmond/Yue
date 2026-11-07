import 'dart:math';

import '../data/curriculum.dart';
import '../data/fsrs.dart';
import 'app_state.dart';

/// One thing on screen during a session.
sealed class Step {
  const Step();
}

class TeachWord extends Step {
  const TeachWord(this.word, {this.example});
  final Word word;

  /// A sentence whose every other word you already know, if there is one.
  final Sentence? example;
}

class TeachGrammar extends Step {
  const TeachGrammar(this.grammar);
  final Grammar grammar;
}

/// Match characters to their meanings: every word here has been taught, so
/// nothing on screen is unfamiliar. [fresh] are the words being checked for the
/// first time; the others are there for company and aren't recorded.
class MatchPairs extends Step {
  MatchPairs(this.words, this.meanings, this.fresh);
  final List<Word> words;
  final List<String> meanings;
  final Set<Word> fresh;

  /// Fresh words that had a wrong match here, to be checked again later.
  final missed = <Word>{};
}

/// An AI-written sentence to read: nothing to answer, and it never joins reviews.
class ReadAlong extends Step {
  const ReadAlong(this.sentence);
  final Sentence sentence;
}

/// A step with a right answer, recorded the first time it's tried.
sealed class Check extends Step {
  const Check(this.card);
  final String card;
}

/// See the Chinese, recall the meaning, and say how it went.
class RecallWord extends Check {
  RecallWord(this.word) : super('wr:${word.w}');
  final Word word;
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

/// A run of steps. A wrong answer sends the step round again later, and only the
/// first try counts towards the score. In a lesson, something joins your reviews
/// once you've answered it correctly, as Hard if it took more than one try. A
/// lesson done before is practice, and like an exam it changes no schedule.
class Session {
  Session._(this.state, this.kind, this.steps, {this.lesson, this.level, this.practice = false})
    : total = steps.length,
      litBefore = state.learnedChars.toSet(),
      startedAt = state.nowMs,
      passedBefore = state.passed;

  final AppState state;
  final SessionKind kind;
  final List<Step> steps;
  final Lesson? lesson;
  final Level? level;
  final Set<String> litBefore;
  final int startedAt, passedBefore;
  final bool practice;
  int total, index = 0, right = 0, wrong = 0;

  /// Which steps have had their first try, and which of those were missed.
  final _tried = <Step>{};
  final missed = <Step>{};

  /// Lesson steps now answered correctly, and words matched, with those that took
  /// more than one try.
  final _settled = <Step>{};
  final _matchTried = <Word>{}, _matchMissed = <Word>{};
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
      if (kind == SessionKind.review) state.rate(step.card, rating, takenMs: takenMs);
    }
    if (kind == SessionKind.lesson && !practice && ok && _settled.add(step)) {
      // A word met for the first time is teaching, not a review.
      state.rate(step.card, missed.contains(step) ? Rating.hard : rating, takenMs: takenMs, isReview: false);
    }
    if (!ok && kind != SessionKind.exam) {
      final at = min(index + 4, steps.length);
      steps.insert(at, step);
      total++;
    }
  }

  /// Records an attempt to match [word] in the current [MatchPairs].
  void answerMatch(Word word, {required bool correct, int takenMs = 0}) {
    final step = current;
    if (step is! MatchPairs || !step.fresh.contains(word)) return;
    if (_matchTried.add(word)) correct ? right++ : wrong++;
    if (!correct) {
      step.missed.add(word);
      _matchMissed.add(word);
    } else if (!step.missed.contains(word) && !practice) {
      state.rate('wr:${word.w}', _matchMissed.contains(word) ? Rating.hard : Rating.good, takenMs: takenMs, isReview: false);
    }
  }

  void next() {
    attempt++;
    // Anything missed in a match is checked again a little later.
    if (current case final MatchPairs step when step.missed.isNotEmpty) {
      final known = steps.take(index + 1).whereType<MatchPairs>().expand((s) => s.words).where((w) => !step.missed.contains(w)).toSet().toList();
      steps.insert(min(index + 4, steps.length), _match(state, step.missed.toList(), known, Random()));
      total++;
    }
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
    final s = course.sentences[key];
    if (s == null) return null;
    if (id.startsWith('sr:')) return ReadSentence(s);
    if (id.startsWith('sb:')) return BuildSentence(s, tilesFor(s, random));
    return null;
  }

  static Session forLesson(AppState state, Lesson lesson) {
    final course = state.course;
    final random = Random();
    final words = [for (final w in lesson.words) ?course.words[w]];
    final steps = _introduce(state, words, random);
    for (final g in lesson.grammar) {
      if (course.grammar[g] case final grammar?) steps.add(TeachGrammar(grammar));
    }
    steps.addAll((words.toList()..shuffle(random)).map((w) => WriteWord(w, writeOptions(course, w, random))));
    final sentences = [for (final id in lesson.sentences) ?course.sentences[id]];
    for (final s in sentences) {
      steps.add(s.ai ? ReadAlong(s) : ReadSentence(s));
    }
    for (final s in sentences.where((s) => !s.ai && _buildable(s)).take(2)) {
      steps.add(BuildSentence(s, tilesFor(s, random)));
    }
    return Session._(state, SessionKind.lesson, steps, lesson: lesson, practice: state.lessonDone(lesson));
  }

  /// Teaches [words] a few at a time, each followed by a match. The word taught
  /// last is held back for the next match, so nothing is asked straight after
  /// its own card, when answering would only need you to look back a second.
  static List<Step> _introduce(AppState state, List<Word> words, Random random) {
    const batch = 4;
    final steps = <Step>[];
    final taught = <String>{};
    final waiting = <Word>[], met = <Word>[];
    void check({Word? holding}) {
      // Two words with one meaning can't be told apart in a match: the later
      // one waits for the next.
      final meanings = <String>{};
      final fresh = waiting.where((w) => w != holding && meanings.add(w.en)).toList();
      if (fresh.isEmpty) return;
      steps.add(_match(state, fresh, met, random));
      met.addAll(fresh);
      waiting.removeWhere(fresh.contains);
    }

    for (final word in words) {
      taught.add(word.w);
      steps.add(TeachWord(word, example: _readableExample(state, word, taught)));
      waiting.add(word);
      if (waiting.length >= batch) check(holding: word);
    }
    if (words.isEmpty) return steps;
    while (waiting.length > 1) {
      check(holding: words.last);
    }
    // With nothing else to match, something familiar sits between the last card
    // and its check.
    if (steps.last is TeachWord) {
      final company = _match(state, const [], met, random);
      if (company.words.length > 1) steps.add(company);
    }
    check();
    return steps;
  }

  /// [fresh] words with others you've met, three or so pairs in all, to match.
  static MatchPairs _match(AppState state, List<Word> fresh, List<Word> met, Random random) {
    const pairs = 3;
    final earlier = [for (final w in state.learned) ?state.course.words[w]]..shuffle(random);
    final words = fresh.toList();
    for (final other in [...met.toList()..shuffle(random), ...earlier]) {
      if (words.length >= pairs) break;
      if (words.every((w) => w.en != other.en)) words.add(other);
    }
    words.shuffle(random);
    return MatchPairs(words, words.map((w) => w.en).toList()..shuffle(random), fresh.toSet());
  }

  /// The first of [word]'s sentences with no word you haven't met, counting
  /// what this lesson has [taught] so far. A name counts as met: it has a gloss.
  static Sentence? _readableExample(AppState state, Word word, Set<String> taught) {
    for (final id in word.examples) {
      final s = state.course.sentences[id];
      if (s != null && s.toks.every((t) => taught.contains(t) || state.isKnownToken(t))) return s;
    }
    return null;
  }

  /// Ten unseen sentences to read, four to build, six words to write, from all
  /// of the band that [level] ends.
  static Session exam(AppState state, Level level) {
    final course = state.course;
    final random = Random();
    final band = course.levels.where((l) => l.band == level.band).toList();
    final pool = [for (final id in band.expand((l) => l.exam).toSet()) ?course.sentences[id]]..shuffle(random);
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
    final words = [for (final l in band) for (final lesson in l.lessons) for (final w in lesson.words) ?course.words[w]]..shuffle(random);
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
