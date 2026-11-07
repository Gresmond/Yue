import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:math' show Random;

import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import 'fsrs.dart';

part 'store_sync.dart';

/// Everything you've done, in one SQLite file. Reviews are only ever added, so
/// the history can be replayed under a better scheduler or merged across devices.
class Store {
  Store._(this._db, this.folder);

  final Database _db;
  final String folder;

  /// Words' old spellings to their current ones, from the course.
  Map<String, String> renamedWords = const {};

  static const _schema = 2;

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
    if (version < 2) {
      // For sync. A row's origin is the device it came from: none if it was
      // made here.
      db.execute('''
        BEGIN;
        ALTER TABLE reviews ADD COLUMN origin TEXT;
        ALTER TABLE lessons ADD COLUMN origin TEXT;
        ALTER TABLE exams ADD COLUMN origin TEXT;
        ALTER TABLE reads ADD COLUMN origin TEXT;
        CREATE INDEX reviews_card ON reviews(card, at_ms);
        CREATE TABLE dues(card TEXT, at_ms INTEGER, origin TEXT);
        CREATE INDEX dues_card ON dues(card, at_ms);
        CREATE TABLE day_others(date TEXT, machine TEXT, reviews INTEGER, lessons INTEGER, PRIMARY KEY(date, machine));
        CREATE TABLE sync_meta(key TEXT PRIMARY KEY, value TEXT, ts INTEGER, origin TEXT);
        CREATE TABLE sync_dirty(date TEXT PRIMARY KEY, n INTEGER);
        CREATE TABLE sync_seen(file TEXT PRIMARY KEY, stamp TEXT);
        PRAGMA user_version = 2;
        COMMIT;
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
  void setMeta(String key, String value) {
    _db.execute('INSERT OR REPLACE INTO meta VALUES(?, ?)', [key, value]);
    if (!_syncedMeta.contains(key)) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    _db.execute('INSERT OR REPLACE INTO sync_meta(key, value, ts) VALUES(?, ?, ?)', [key, value, now]);
    _markUnsent(_dateOf(now));
  }

  /// The change file a moment belongs in. By UTC, the same on every device.
  static String _dateOf(int ms) => DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true).toIso8601String().substring(0, 10);

  void _markUnsent(String date) => _db.execute('INSERT INTO sync_dirty VALUES(?, 1) ON CONFLICT(date) DO UPDATE SET n = n + 1', [date]);

  T _transaction<T>(T Function() action) {
    _db.execute('BEGIN');
    try {
      final result = action();
      _db.execute('COMMIT');
      return result;
    } catch (_) {
      _db.execute('ROLLBACK');
      rethrow;
    }
  }

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
    _markUnsent(_dateOf(m.lastMs));
    _db.execute('COMMIT');
  }

  /// Brings a card due now, as a failed exam does for what you missed.
  void makeDue(String id, int nowMs) {
    _db.execute('UPDATE cards SET due_ms = ? WHERE id = ?', [nowMs, id]);
    _db.execute('INSERT INTO dues(card, at_ms) VALUES(?, ?)', [id, nowMs]);
    _markUnsent(_dateOf(nowMs));
  }

  Set<String> lessonsDone() => {for (final r in _db.select('SELECT id FROM lessons')) r['id'] as String};
  void finishLesson(String id, int nowMs) {
    _db.execute('INSERT OR IGNORE INTO lessons(id, at_ms) VALUES(?, ?)', [id, nowMs]);
    _markUnsent(_dateOf(nowMs));
  }

  int levelsPassed() => (_db.select('SELECT MAX(level) m FROM exams WHERE passed = 1').first['m'] as int?) ?? 0;
  void saveExam(int level, int nowMs, double score, bool passed) {
    _db.execute('INSERT INTO exams(level, at_ms, score, passed) VALUES(?,?,?,?)', [level, nowMs, score, passed ? 1 : 0]);
    _markUnsent(_dateOf(nowMs));
  }

  Set<String> reads() => {for (final r in _db.select('SELECT id FROM reads')) r['id'] as String};
  void markRead(String id, int nowMs) {
    _db.execute('INSERT OR REPLACE INTO reads(id, at_ms) VALUES(?, ?)', [id, nowMs]);
    _markUnsent(_dateOf(nowMs));
  }

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

  void saveDay(DayRow d) {
    _db.execute('INSERT OR REPLACE INTO days VALUES(?,?,?,?,?,?)', [
      d.date, d.target, d.reviews, d.lessons, d.complete ? 1 : 0, d.frozen ? 1 : 0,
    ]);
    _markUnsent(d.date);
  }

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
