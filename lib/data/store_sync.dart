part of 'store.dart';

/// Settings that follow you between devices. The others stay on this one.
const _syncedMeta = {'theme', 'zh_font', 'freezes', 'best_streak'};

/// What sync needs of the store. Each device writes only its own change files,
/// one per day, so no file is ever written in two places:
///
/// - Reviews, exams, due dates, lessons and reads are only ever added, so
///   merging them is taking the ones not here yet.
/// - A card's memory is worked out again from all its history, the same way
///   on every device.
/// - A day's counts are kept per device and added up, so two devices never
///   overwrite each other's.
/// - A setting goes with its latest change.
extension StoreSync on Store {
  /// This device's id. It lives with the data, so a device whose data is lost
  /// comes back as a new one and never overwrites its old files.
  String get machine {
    final had = meta('sync_machine');
    if (had != null) return had;
    final random = Random.secure();
    final id = List.generate(8, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
    _db.execute('INSERT OR REPLACE INTO meta VALUES(?, ?)', ['sync_machine', id]);
    return id;
  }

  bool get hasUnsent => _db.select('SELECT 1 FROM sync_dirty LIMIT 1').isNotEmpty;

  /// The days with changes to send, each with a count that moves on when it
  /// changes again.
  List<(String, int)> unsentDays() => [
    for (final r in _db.select('SELECT date, n FROM sync_dirty ORDER BY date')) (r['date'] as String, r['n'] as int),
  ];

  /// [date]'s file went up as it was at [n].
  void markSent(String date, int n) => _db.execute('DELETE FROM sync_dirty WHERE date = ? AND n = ?', [date, n]);

  /// Everything made on this device is to be sent: for turning sync on.
  void markAllUnsent() {
    final now = DateTime.now().millisecondsSinceEpoch;
    _transaction(() {
      for (final key in _syncedMeta) {
        // A setting from before sync loses to any made since.
        _db.execute('INSERT OR IGNORE INTO sync_meta(key, value, ts) SELECT key, value, 1 FROM meta WHERE key = ?', [key]);
      }
      final dates = {
        for (final (table, column) in const [('reviews', 'at_ms'), ('dues', 'at_ms'), ('lessons', 'at_ms'), ('exams', 'at_ms'), ('reads', 'at_ms'), ('sync_meta', 'ts')])
          for (final r in _db.select('SELECT DISTINCT date($column / 1000, \'unixepoch\') d FROM $table WHERE origin IS NULL')) r['d'] as String,
        for (final r in _db.select('SELECT date FROM days')) r['date'] as String,
      };
      dates.forEach(_markUnsent);
      if (dates.isEmpty) _markUnsent(Store._dateOf(now));
    });
  }

  /// Moving to another Google account: everything here becomes this device's
  /// own, to send there, and it joins as a new device.
  void adoptEverything() => _transaction(() {
    for (final table in const ['reviews', 'dues', 'lessons', 'exams', 'reads', 'sync_meta']) {
      _db.execute('UPDATE $table SET origin = NULL');
    }
    _db.execute('DELETE FROM day_others');
    _db.execute('DELETE FROM sync_seen');
    _db.execute("DELETE FROM meta WHERE key = 'sync_machine'");
  });

  /// [date]'s change file: what this device itself did.
  String changeFile(String date, String name) {
    final day = DateTime.parse('${date}T00:00:00Z').millisecondsSinceEpoch;
    final args = [day, day + 86400000];
    List<List<Object?>> rows(String sql, List<Object?> args) => [for (final r in _db.select(sql, args)) r.values];
    final row = _db.select('SELECT * FROM days WHERE date = ?', [date]).firstOrNull;
    final others = _db.select('SELECT COALESCE(SUM(reviews), 0) r, COALESCE(SUM(lessons), 0) l FROM day_others WHERE date = ?', [date]).first;
    return jsonEncode({
      'version': 1,
      'name': name,
      'reviews': rows('SELECT card, at_ms, rating, taken_ms FROM reviews WHERE origin IS NULL AND at_ms >= ? AND at_ms < ?', args),
      'dues': rows('SELECT card, at_ms FROM dues WHERE origin IS NULL AND at_ms >= ? AND at_ms < ?', args),
      'lessons': rows('SELECT id, at_ms FROM lessons WHERE origin IS NULL AND at_ms >= ? AND at_ms < ?', args),
      'exams': rows('SELECT level, at_ms, score, passed FROM exams WHERE origin IS NULL AND at_ms >= ? AND at_ms < ?', args),
      'reads': rows('SELECT id, at_ms FROM reads WHERE origin IS NULL AND at_ms >= ? AND at_ms < ?', args),
      'meta': rows('SELECT key, value, ts FROM sync_meta WHERE origin IS NULL AND ts >= ? AND ts < ?', args),
      if (row != null)
        'day': [
          row['target'],
          math.max(0, (row['reviews'] as int) - (others['r'] as int)),
          math.max(0, (row['lessons'] as int) - (others['l'] as int)),
          row['complete'],
          row['frozen'],
        ],
    });
  }

  String? seenStamp(String file) => _db.select('SELECT stamp FROM sync_seen WHERE file = ?', [file]).firstOrNull?['stamp'] as String?;

  /// Takes in [who]'s change file for [date], all of it or, if any of it can't
  /// be read, none. Adds the cards whose history grew to [touched], and returns
  /// whether anything here changed.
  bool mergeFile(String who, String date, String file, String stamp, Map<String, dynamic> json, Set<String> touched) => _transaction(() {
    var changed = false;
    bool insert(String sql, List<Object?> args) {
      _db.execute(sql, args);
      final added = _db.updatedRows > 0;
      changed |= added;
      return added;
    }

    for (final r in json['reviews'] as List? ?? const []) {
      final [String card, int at, int rating, int taken] = r as List<dynamic>;
      if (!Rating.values.any((v) => v.value == rating)) throw FormatException('Not a rating: $rating');
      if (insert(
        'INSERT INTO reviews(card, at_ms, rating, taken_ms, origin) SELECT ?1, ?2, ?3, ?4, ?5 WHERE NOT EXISTS (SELECT 1 FROM reviews WHERE card = ?1 AND at_ms = ?2)',
        [card, at, rating, taken, who],
      )) {
        touched.add(card);
      }
    }
    for (final r in json['dues'] as List? ?? const []) {
      final [String card, int at] = r as List<dynamic>;
      if (insert('INSERT INTO dues(card, at_ms, origin) SELECT ?1, ?2, ?3 WHERE NOT EXISTS (SELECT 1 FROM dues WHERE card = ?1 AND at_ms = ?2)', [card, at, who])) touched.add(card);
    }
    for (final r in json['lessons'] as List? ?? const []) {
      final [String id, int at] = r as List<dynamic>;
      insert('INSERT OR IGNORE INTO lessons(id, at_ms, origin) VALUES(?, ?, ?)', [id, at, who]);
    }
    for (final r in json['reads'] as List? ?? const []) {
      final [String id, int at] = r as List<dynamic>;
      insert('INSERT OR IGNORE INTO reads(id, at_ms, origin) VALUES(?, ?, ?)', [id, at, who]);
    }
    for (final r in json['exams'] as List? ?? const []) {
      final e = r as List;
      final (level, at, score, passed) = (e[0] as int, e[1] as int, (e[2] as num).toDouble(), e[3] as int);
      insert(
        'INSERT INTO exams(level, at_ms, score, passed, origin) SELECT ?1, ?2, ?3, ?4, ?5 WHERE NOT EXISTS (SELECT 1 FROM exams WHERE level = ?1 AND at_ms = ?2)',
        [level, at, score, passed, who],
      );
    }
    for (final r in json['meta'] as List? ?? const []) {
      final [String key, String value, int ts] = r as List<dynamic>;
      changed |= _mergeMeta(key, value, ts, who);
    }
    if (json['day'] case final List d) changed |= _mergeDay(date, who, d[0] as int, d[1] as int, d[2] as int, d[3] as int, d[4] as int);
    _db.execute('INSERT OR REPLACE INTO sync_seen VALUES(?, ?)', [file, stamp]);
    return changed;
  });

  /// The latest change wins. The best streak only ever goes up.
  bool _mergeMeta(String key, String value, int ts, String who) {
    if (!_syncedMeta.contains(key)) return false;
    final had = _db.select('SELECT ts, origin FROM sync_meta WHERE key = ?', [key]).firstOrNull;
    if (had != null) {
      final hadTs = had['ts'] as int;
      if (ts < hadTs || (ts == hadTs && who.compareTo(had['origin'] as String? ?? '') <= 0)) return false;
    }
    final v = key == 'best_streak' ? '${math.max(int.tryParse(value) ?? 0, int.tryParse(meta(key) ?? '') ?? 0)}' : value;
    _db.execute('INSERT OR REPLACE INTO sync_meta(key, value, ts, origin) VALUES(?, ?, ?, ?)', [key, v, ts, who]);
    _db.execute('INSERT OR REPLACE INTO meta VALUES(?, ?)', [key, v]);
    return true;
  }

  bool _mergeDay(String date, String who, int target, int reviews, int lessons, int complete, int frozen) {
    final was = _db.select('SELECT reviews, lessons FROM day_others WHERE date = ? AND machine = ?', [date, who]).firstOrNull;
    final row = _db.select('SELECT * FROM days WHERE date = ?', [date]).firstOrNull;
    final newlyDone = row != null && row['complete'] == 0 && complete == 1;
    final next = [
      math.max(target, row?['target'] as int? ?? 0),
      (row?['reviews'] as int? ?? 0) + reviews - (was?['reviews'] as int? ?? 0),
      (row?['lessons'] as int? ?? 0) + lessons - (was?['lessons'] as int? ?? 0),
      complete | (row?['complete'] as int? ?? 0),
      frozen | (row?['frozen'] as int? ?? 0),
    ];
    _db.execute('INSERT OR REPLACE INTO day_others VALUES(?, ?, ?, ?)', [date, who, reviews, lessons]);
    final same = row != null && next[0] == row['target'] && next[1] == row['reviews'] && next[2] == row['lessons'] && next[3] == row['complete'] && next[4] == row['frozen'];
    if (same) return false;
    _db.execute('INSERT OR REPLACE INTO days VALUES(?,?,?,?,?,?)', [date, ...next]);
    // A freeze spent on a day that was really kept, on another device: it
    // comes back.
    if (newlyDone && row['frozen'] == 1) {
      setMeta('freezes', '${math.min(2, (int.tryParse(meta('freezes') ?? '') ?? 0) + 1)}');
    }
    return true;
  }

  /// Works out [ids]' memories again from all their history, so every device
  /// reaches the same answer whichever order it heard things in.
  void replay(Iterable<String> ids) => _transaction(() {
    for (final id in ids) {
      final events = _db.select(
        'SELECT at_ms, rating, 0 kind FROM reviews WHERE card = ?1 UNION ALL SELECT at_ms, NULL, 1 kind FROM dues WHERE card = ?1 ORDER BY at_ms, kind',
        [id],
      );
      Memory? m;
      for (final e in events) {
        final at = e['at_ms'] as int;
        if (e['rating'] case final int r) {
          m = Fsrs.review(m, Rating.values.firstWhere((v) => v.value == r), at, fuzz: Fsrs.fuzzFor(id, at));
        } else if (m != null) {
          m = Memory(stability: m.stability, difficulty: m.difficulty, lastMs: m.lastMs, dueMs: at, reps: m.reps, lapses: m.lapses);
        }
      }
      if (m != null) _db.execute('INSERT OR REPLACE INTO cards VALUES(?,?,?,?,?,?,?)', [id, m.stability, m.difficulty, m.lastMs, m.dueMs, m.reps, m.lapses]);
    }
  });
}
