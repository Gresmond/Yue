import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../data/curriculum.dart';
import '../data/fsrs.dart';
import '../data/store.dart';
import '../data/sync_service.dart';
import '../theme/app_theme.dart';

/// Card ids: `wr:` reading a word, `ww:` writing one, `sr:` reading a sentence,
/// `sb:` building one. Older data may hold `rad:` cards for radicals, which are
/// now explained on word cards and no longer reviewed, and cards for sentences
/// the course has since dropped. Their history stays, but they never come due.
class AppState extends ChangeNotifier {
  AppState(this.store, this.course, {this.sync}) {
    store
      ..renamedWords = course.renamed
      ..renameOldCards();
    _load();
    openDay();
  }

  bool _inCourse(String id) {
    final key = id.substring(id.indexOf(':') + 1);
    if (id.startsWith('wr:') || id.startsWith('ww:')) return course.words.containsKey(key);
    if (id.startsWith('sr:') || id.startsWith('sb:')) return course.sentences.containsKey(key);
    return false;
  }

  void _load() {
    cards = store.cards()..removeWhere((id, _) => !_inCourse(id));
    _lessons = store.lessonsDone();
    _passed = store.levelsPassed();
    _reads = store.reads();
    days = store.days();
    themeName = store.meta('theme') ?? 'Solar Eclipse';
    Fonts.zh = store.meta('zh_font') ?? Fonts.zhKai;
    best = int.tryParse(store.meta('best_streak') ?? '') ?? 0;
    freezes = int.tryParse(store.meta('freezes') ?? '') ?? 0;
    dailyMinutes = int.tryParse(store.meta('daily_minutes') ?? '') ?? 20;
    _recount();
    _clearLevels();
  }

  /// Takes in what came from another device.
  void reload() {
    _load();
    openDay();
    _maybeCompleteDay();
    notifyListeners();
  }

  final Store store;
  final Curriculum course;

  /// Google sync, if it could start: Yue runs on its own without it.
  final SyncService? sync;
  late Map<String, Memory> cards;
  late Set<String> _lessons, _reads;
  late int _passed;
  late Map<String, DayRow> days;
  late String themeName;
  int best = 0, freezes = 0, dailyMinutes = 20;

  /// What's learned, kept up to date as cards are first reviewed.
  final Set<String> learned = {}, learnedChars = {};

  /// Days run from 4am, so a late night still counts as the same day.
  static DateTime dayOf(DateTime t) {
    final s = t.subtract(const Duration(hours: 4));
    return DateTime(s.year, s.month, s.day);
  }

  static String key(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  DateTime Function() clock = DateTime.now;
  DateTime get now => clock();
  int get nowMs => now.millisecondsSinceEpoch;
  String get todayKey => key(dayOf(now));

  void _recount() {
    learned.clear();
    learnedChars.clear();
    for (final id in cards.keys) {
      if (id.startsWith('wr:')) {
        final w = id.substring(3);
        learned.add(w);
        learnedChars.addAll(w.split(''));
      }
    }
  }

  /// Rolls the day over: sets today's target, and spends a saved streak freeze on
  /// any day missed since, if there's one to spend.
  void openDay() {
    final today = dayOf(now);
    final k = key(today);
    if (days.containsKey(k)) return;
    final completed = days.values.where((d) => d.complete || d.frozen).map((d) => d.date).toList()..sort();
    if (completed.isNotEmpty) {
      final last = DateTime.parse(completed.last);
      final missed = today.difference(last).inDays - 1;
      if (missed > 0 && missed <= freezes) {
        for (var i = 1; i <= missed; i++) {
          final d = DayRow(date: key(DateTime(last.year, last.month, last.day + i)), target: 0, frozen: true);
          days[d.date] = d;
          store.saveDay(d);
        }
        freezes -= missed;
        store.setMeta('freezes', '$freezes');
      }
    }
    final row = DayRow(date: k, target: math.min(30, dueCount));
    days[k] = row;
    store.saveDay(row);
    store.backUp(k);
  }

  DayRow get today => days[todayKey] ?? (DayRow(date: todayKey, target: 0));

  // ---- Streak.

  /// Whole days in a row, ending today or yesterday (today may still be to come).
  /// A frozen day keeps the run going without adding to it.
  int get streak {
    var d = dayOf(now);
    var count = 0;
    final t = days[key(d)];
    if (t == null || !(t.complete || t.frozen)) d = DateTime(d.year, d.month, d.day - 1);
    while (true) {
      final row = days[key(d)];
      if (row == null) return count;
      if (row.complete) {
        count++;
      } else if (!row.frozen) {
        return count;
      }
      d = DateTime(d.year, d.month, d.day - 1);
    }
  }

  void _maybeCompleteDay() {
    final d = today;
    if (d.complete) return;
    final enough = d.target > 0 ? d.reviews >= d.target : d.lessons > 0 || d.reviews >= 10;
    if (!enough) return;
    d.complete = true;
    store.saveDay(d);
    final s = streak;
    if (s > best) {
      best = s;
      store.setMeta('best_streak', '$best');
    }
    // A freeze for every full week, holding two at most.
    if (s > 0 && s % 7 == 0 && freezes < 2) {
      freezes++;
      store.setMeta('freezes', '$freezes');
    }
  }

  // ---- Reviewing.

  List<String> get dueIds {
    final t = nowMs;
    final due = [for (final e in cards.entries) if (e.value.dueMs <= t) e.key];
    due.sort((a, b) => cards[a]!.dueMs.compareTo(cards[b]!.dueMs));
    return due;
  }

  int get dueCount {
    final t = nowMs;
    return cards.values.where((m) => m.dueMs <= t).length;
  }

  void rate(String id, Rating rating, {int takenMs = 0, bool isReview = true}) {
    final at = nowMs;
    final m = Fsrs.review(cards[id], rating, at, fuzz: Fsrs.fuzzFor(id, at));
    cards[id] = m;
    store.saveReview(id, m, rating, takenMs);
    if (id.startsWith('wr:')) {
      final w = id.substring(3);
      learned.add(w);
      learnedChars.addAll(w.split(''));
    }
    if (isReview) {
      final d = today;
      d.reviews++;
      days[d.date] = d;
      store.saveDay(d);
    }
    _maybeCompleteDay();
    _clearLevels();
    notifyListeners();
  }

  // ---- Where you are in the course.

  /// The level you're working on.
  Level get level => course.levels[math.min(_passed, course.levels.length - 1)];
  int get passed => _passed;
  bool get finishedCourse => _passed >= course.levels.length;

  bool lessonDone(Lesson l) => _lessons.contains(l.id);

  /// The next lesson, or null when only the level's exam is left.
  Lesson? get nextLesson {
    for (final l in level.lessons) {
      if (!lessonDone(l)) return l;
    }
    return null;
  }

  int doneInLevel(Level l) => l.lessons.where(lessonDone).length;

  /// A level's words, and how many must be held for it to clear.
  int wordsInLevel(Level l) => l.lessons.fold(0, (sum, lesson) => sum + lesson.words.length);
  int heldNeeded(Level l) => (wordsInLevel(l) * holdShare).ceil();
  int heldInLevel(Level l) => l.lessons.expand((lesson) => lesson.words).where(isHeld).length;

  /// Every lesson done and enough of its words held: what a level asks of you.
  bool levelReady(Level l) => doneInLevel(l) == l.lessons.length && heldInLevel(l) >= heldNeeded(l);

  /// The last level of a band is ready, so all that's left is the band's exam.
  bool get examReady => !finishedCourse && course.isBandEnd(level) && levelReady(level);

  /// Moves past levels that are ready, except where a band's exam stands in the
  /// way. A level stays cleared even if some of its words later slip. Clearing
  /// is stored as a passed exam, so it reaches other devices in the same way.
  void _clearLevels() {
    while (!finishedCourse && !course.isBandEnd(level) && levelReady(level)) {
      store.saveExam(level.n, nowMs, 1, true);
      _passed = level.n;
    }
  }

  void finishLesson(Lesson l) {
    if (lessonDone(l)) return;
    store.finishLesson(l.id, nowMs);
    _lessons.add(l.id);
    final d = today;
    d.lessons++;
    days[d.date] = d;
    store.saveDay(d);
    _maybeCompleteDay();
    _clearLevels();
    notifyListeners();
  }

  void finishExam(Level l, double score, Iterable<String> missedCards) {
    final passed = score >= passMark;
    store.saveExam(l.n, nowMs, score, passed);
    if (passed && l.n > _passed) _passed = l.n;
    for (final id in missedCards) {
      if (cards.containsKey(id)) {
        store.makeDue(id, nowMs);
        final m = cards[id]!;
        cards[id] = Memory(stability: m.stability, difficulty: m.difficulty, lastMs: m.lastMs, dueMs: nowMs, reps: m.reps, lapses: m.lapses);
      }
    }
    notifyListeners();
  }

  static const passMark = 0.8, holdShare = 0.9;

  // ---- How much to take on.

  /// Rough costs: these only decide what to suggest, so they needn't be exact.
  static const lessonMinutes = 10, secondsPerReview = 12;

  /// The reviews a day your cards will ask for from here, each coming round
  /// about once per its interval.
  double get _reviewsPerDay => cards.values.fold(0.0, (sum, m) => sum + 1 / Fsrs.interval(m.stability));

  /// A lesson's words each bring a reading and a writing card, plus a few
  /// sentences, all starting on short intervals.
  double _lessonLoad(Lesson l) => (l.words.length * 2 + math.min(l.sentences.length * 1.5, 6)) / Fsrs.interval(Fsrs.w[Rating.good.value - 1]);

  /// Today's time so far.
  double get minutesToday => today.lessons * lessonMinutes + today.reviews * secondsPerReview / 60;

  /// Whether to suggest another new lesson: there's time left today, and the
  /// reviews it adds would still leave room for new words in the days ahead.
  bool get canLearnToday {
    final l = nextLesson;
    if (l == null || minutesToday >= dailyMinutes) return false;
    return (_reviewsPerDay + _lessonLoad(l)) * secondsPerReview / 60 <= dailyMinutes * 0.6;
  }

  void setDailyMinutes(int minutes) {
    dailyMinutes = minutes;
    store.setMeta('daily_minutes', '$minutes');
    notifyListeners();
  }

  // ---- What you can do now.

  /// Share of the running words in real sentences that you hold in memory.
  double get readingCoverage {
    var total = 0.0;
    for (final w in course.words.values) {
      if (isHeld(w.w)) total += w.share;
    }
    return total.clamp(0.0, 1.0);
  }

  /// Share of the characters in the sentence library that you've met.
  double get characterCoverage {
    var total = 0.0;
    for (final c in learnedChars) {
      total += course.chars[c]?.share ?? 0;
    }
    return total.clamp(0.0, 1.0);
  }

  bool isHeld(String word) => cards['wr:$word']?.held ?? false;
  bool isStrong(String word) => cards['wr:$word']?.strong ?? false;
  bool charStrong(String c) => (course.byChar[c] ?? const <Word>[]).any((w) => isStrong(w.w));

  /// How many days until you're through [band]'s words at your recent pace, if known.
  int? daysToBandEnd(int band) {
    final today = dayOf(now);
    final since = today.subtract(const Duration(days: 14));
    final window = days.values.map((d) => DateTime.parse(d.date)).where((d) => d.isAfter(since)).toList();
    final recent = days.values.where((d) => DateTime.parse(d.date).isAfter(since)).fold(0, (sum, d) => sum + d.lessons);
    if (recent == 0) return null;
    // Your pace over the days you've had, up to the last fortnight.
    final span = window.fold(1, (most, d) => math.max(most, today.difference(d).inDays + 1));
    final remaining = course.levels.where((l) => l.band == band).expand((l) => l.lessons).where((l) => !lessonDone(l)).length;
    return (remaining / (recent / span)).ceil();
  }

  // ---- Reading.

  bool passageOpen(Passage p) => p.level <= level.n;
  bool hasRead(String id) => _reads.contains(id);
  void markRead(String id) {
    store.markRead(id, nowMs);
    _reads.add(id);
    notifyListeners();
  }

  /// Share of a text's words you've learned.
  double coverage(List<String> toks) {
    var known = 0, total = 0;
    for (final t in toks) {
      if (t.length == 1 && !course.words.containsKey(t)) continue;
      total++;
      if (learned.contains(t) || course.names.containsKey(t)) known++;
    }
    return total == 0 ? 1 : known / total;
  }

  /// A real sentence you've become able to read, new each day.
  Sentence? get sentenceOfTheDay {
    final ready = [
      for (final s in course.sentences.values)
        if (!s.exam && !s.ai && s.zh.length >= 6 && s.toks.every((t) => isKnownToken(t))) s,
    ];
    if (ready.isEmpty) return null;
    ready.sort((a, b) => a.id.compareTo(b.id));
    return ready[todayKey.codeUnits.fold(0, (a, b) => a * 31 + b).abs() % ready.length];
  }

  bool isKnownToken(String t) =>
      learned.contains(t) || course.names.containsKey(t) || !course.words.containsKey(t);

  // ---- Appearance.

  void setTheme(String name) {
    themeName = name;
    store.setMeta('theme', name);
    notifyListeners();
  }

  /// When the next card comes due, if none is due now.
  int? get nextDueMs => cards.isEmpty ? null : cards.values.map((m) => m.dueMs).reduce(math.min);

  void setChineseFont(String font) {
    Fonts.zh = font;
    store.setMeta('zh_font', font);
    notifyListeners();
  }
}

class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState state, required super.child}) : super(notifier: state);

  static AppState of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;
  static AppState read(BuildContext context) => context.getInheritedWidgetOfExactType<AppScope>()!.notifier!;
}
