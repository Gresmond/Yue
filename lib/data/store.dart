import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import 'fsrs.dart';

/// Everything you've done, in one SQLite file. Reviews are only ever added, so
/// the history can be replayed under a better scheduler or merged across devices.
class Store {
  Store._(this._db, this.folder);

  final Database _db;
  final String folder;

  static const _schema = 1;

  static Store open(String folder) {
    Directory(folder).createSync(recursive: true);
    final db = sqlite3.open(p.join(folder, 'yue.db'));
    db.execute('PRAGMA journal_mode = WAL');
    final store = Store._(db, folder);
    final version = db.select('PRAGMA user_version').first.values.first as int;
    if (version < 1) {
      db.execute('''
        CREATE TABLE cards(id TEXT PRIMARY KEY, stability REAL, difficulty REAL, last_ms INTEGER, due_ms INTEGER, reps INTEGER, lapses INTEGER);
        CREATE INDEX cards_due ON cards(due_ms);
        CREATE TABLE reviews(id INTEGER PRIMARY KEY, card TEXT, at_ms INTEGER, rating INTEGER, taken_ms INTEGER);
        CREATE INDEX reviews_at ON reviews(at_ms);
        CREATE TABLE lessons(id TEXT PRIMARY KEY, at_ms INTEGER);
        CREATE TABLE exams(id INTEGER PRIMARY KEY, level INTEGER, at_ms INTEGER, score REAL, passed INTEGER);
        CREATE TABLE days(date TEXT PRIMARY KEY, target INTEGER, reviews INTEGER DEFAULT 0, lessons INTEGER DEFAULT 0, complete INTEGER DEFAULT 0, frozen INTEGER DEFAULT 0);
        CREATE TABLE reads(id TEXT PRIMARY KEY, at_ms INTEGER);
        CREATE TABLE meta(key TEXT PRIMARY KEY, value TEXT);
      ''');
    }
    db.execute('PRAGMA user_version = $_schema');
    return store;
  }

  /// A dated copy, once a day, keeping the last 30.
  void backUp(String date) {
    final folder = Directory(p.join(this.folder, 'backups'))..createSync(recursive: true);
    final file = File(p.join(folder.path, 'yue-$date.db'));
    if (file.existsSync()) return;
    _db.execute('VACUUM INTO ?', [file.path]);
    final all = folder.listSync().whereType<File>().toList()..sort((a, b) => a.path.compareTo(b.path));
    for (final old in all.take(all.length > 30 ? all.length - 30 : 0)) {
      old.deleteSync();
    }
  }

  String? meta(String key) => _db.select('SELECT value FROM meta WHERE key = ?', [key]).firstOrNull?['value'] as String?;
  void setMeta(String key, String value) => _db.execute('INSERT OR REPLACE INTO meta VALUES(?, ?)', [key, value]);

  Map<String, Memory> cards() => {
    for (final r in _db.select('SELECT * FROM cards'))
      r['id'] as String: Memory(
        stability: r['stability'] as double,
        difficulty: r['difficulty'] as double,
        lastMs: r['last_ms'] as int,
        dueMs: r['due_ms'] as int,
        reps: r['reps'] as int,
        lapses: r['lapses'] as int,
      ),
  };

  void saveReview(String id, Memory m, Rating rating, int takenMs) {
    _db.execute('BEGIN');
    _db.execute('INSERT OR REPLACE INTO cards VALUES(?,?,?,?,?,?,?)', [id, m.stability, m.difficulty, m.lastMs, m.dueMs, m.reps, m.lapses]);
    _db.execute('INSERT INTO reviews(card, at_ms, rating, taken_ms) VALUES(?,?,?,?)', [id, m.lastMs, rating.value, takenMs]);
    _db.execute('COMMIT');
  }

  /// Brings a card due now, as a failed exam does for what you missed.
  void makeDue(String id, int nowMs) => _db.execute('UPDATE cards SET due_ms = ? WHERE id = ?', [nowMs, id]);

  Set<String> lessonsDone() => {for (final r in _db.select('SELECT id FROM lessons')) r['id'] as String};
  void finishLesson(String id, int nowMs) => _db.execute('INSERT OR IGNORE INTO lessons VALUES(?, ?)', [id, nowMs]);

  int levelsPassed() => (_db.select('SELECT MAX(level) m FROM exams WHERE passed = 1').first['m'] as int?) ?? 0;
  void saveExam(int level, int nowMs, double score, bool passed) =>
      _db.execute('INSERT INTO exams(level, at_ms, score, passed) VALUES(?,?,?,?)', [level, nowMs, score, passed ? 1 : 0]);

  Set<String> reads() => {for (final r in _db.select('SELECT id FROM reads')) r['id'] as String};
  void markRead(String id, int nowMs) => _db.execute('INSERT OR REPLACE INTO reads VALUES(?, ?)', [id, nowMs]);

  Map<String, DayRow> days() => {
    for (final r in _db.select('SELECT * FROM days'))
      r['date'] as String: DayRow(
        date: r['date'] as String,
        target: r['target'] as int,
        reviews: r['reviews'] as int,
        lessons: r['lessons'] as int,
        complete: r['complete'] == 1,
        frozen: r['frozen'] == 1,
      ),
  };

  void saveDay(DayRow d) => _db.execute('INSERT OR REPLACE INTO days VALUES(?,?,?,?,?,?)', [
    d.date, d.target, d.reviews, d.lessons, d.complete ? 1 : 0, d.frozen ? 1 : 0,
  ]);

  /// Recalled share of reviews (not first-time teaching) by day, for the last [days] days.
  List<(int at, int rating)> recentReviews(int sinceMs) => [
    for (final r in _db.select('SELECT at_ms, rating FROM reviews WHERE at_ms >= ? ORDER BY at_ms', [sinceMs]))
      (r['at_ms'] as int, r['rating'] as int),
  ];

  void close() => _db.close();
}

class DayRow {
  DayRow({required this.date, required this.target, this.reviews = 0, this.lessons = 0, this.complete = false, this.frozen = false});
  final String date;
  int target, reviews, lessons;
  bool complete, frozen;
}
