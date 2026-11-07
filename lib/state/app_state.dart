import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../data/curriculum.dart';
import '../data/fsrs.dart';
import '../data/store.dart';
import '../theme/app_theme.dart';

/// Card ids: `wr:` reading a word, `ww:` writing one, `rad:` a radical,
/// `sr:` reading a sentence, `sb:` building one.
class AppState extends ChangeNotifier {
  AppState(this.store, this.course) {
    cards = store.cards();
    _lessons = store.lessonsDone();
    _passed = store.levelsPassed();
    _reads = store.reads();
    days = store.days();
    themeName = store.meta('theme') ?? 'Solar Eclipse';
    Fonts.zh = store.meta('zh_font') ?? Fonts.zhKai;
    best = int.tryParse(store.meta('best_streak') ?? '') ?? 0;
    freezes = int.tryParse(store.meta('freezes') ?? '') ?? 0;
    _recount();
    openDay();
  }

  final Store store;
  final Curriculum course;
  late Map<String, Memory> cards;
  late Set<String> _lessons, _reads;
  late int _passed;
  late Map<String, DayRow> days;
  late String themeName;
  int best = 0, freezes = 0;

  /// What's learned, kept up to date as cards are first reviewed.
  final Set<String> learned = {}, learnedChars = {};
  final Random2 _random = Random2();

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
    final m = Fsrs.review(cards[id], rating, nowMs, fuzz: _random.next());
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
  double levelProgress(Level l) => l.lessons.isEmpty ? 0 : doneInLevel(l) / l.lessons.length;

  void finishLesson(Lesson l) {
    store.finishLesson(l.id, nowMs);
    _lessons.add(l.id);
    final d = today;
    d.lessons++;
    days[d.date] = d;
    store.saveDay(d);
    _maybeCompleteDay();
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

  static const passMark = 0.8;

  // ---- What you can do now.

  /// Share of the sentence library you could read word for word.
  int get readableSentences => _readableInProgress;
  int get _readableInProgress {
    final l = level;
    final before = l.n > 1 ? course.levels[l.n - 2].readable : 0;
    return before + ((l.readable - before) * levelProgress(l)).round();
  }

  /// Share of the characters in the sentence library that you've met.
  double get characterCoverage {
    var total = 0.0;
    for (final c in learnedChars) {
      total += course.chars[c]?.share ?? 0;
    }
    return total.clamp(0.0, 1.0);
  }

  bool isStrong(String word) => cards['wr:$word']?.strong ?? false;
  bool charStrong(String c) => (course.byChar[c] ?? const <Word>[]).any((w) => isStrong(w.w));

  /// How many days until you're through [band]'s words at your recent pace, if known.
  int? daysToBandEnd(int band) {
    final since = dayOf(now).subtract(const Duration(days: 14));
    final recent = days.values.where((d) => DateTime.parse(d.date).isAfter(since)).fold(0, (sum, d) => sum + d.lessons);
    if (recent == 0) return null;
    final remaining = course.levels.where((l) => l.band == band).expand((l) => l.lessons).where((l) => !lessonDone(l)).length;
    return (remaining / (recent / 14)).ceil();
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
        if (!s.exam && s.zh.length >= 6 && s.toks.every((t) => isKnownToken(t))) s,
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

  void setChineseFont(String font) {
    Fonts.zh = font;
    store.setMeta('zh_font', font);
    notifyListeners();
  }
}

class Random2 {
  final _r = math.Random();
  double next() => _r.nextDouble();
}

class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState state, required super.child}) : super(notifier: state);

  static AppState of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;
  static AppState read(BuildContext context) => context.getInheritedWidgetOfExactType<AppScope>()!.notifier!;
}
