import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';
import 'package:yue/data/curriculum.dart';
import 'package:yue/data/fsrs.dart';
import 'package:yue/data/google_drive.dart';
import 'package:yue/data/store.dart';
import 'package:yue/data/sync_service.dart';
import 'package:yue/main.dart';
import 'package:yue/state/app_state.dart';

/// Stands in for one Google account's hidden folder.
class FakeDrive implements SyncDrive {
  final files = <String, ({String name, List<int> bytes, int version})>{};
  var _next = 0;
  DriveError? failWith;

  @override
  Future<List<DriveFile>> list() async {
    if (failWith case final e?) throw e;
    return [for (final MapEntry(key: id, :value) in files.entries) DriveFile(id: id, name: value.name, modified: '${value.version}')];
  }

  @override
  Future<List<int>> download(String id) async => files[id]!.bytes;

  @override
  Future<DriveFile> upload(String name, List<int> bytes, {String? id}) async {
    if (id != null && !files.containsKey(id)) throw const DriveError('gone', notFound: true);
    final key = id ?? 'f${_next++}';
    final version = (files[key]?.version ?? 0) + 1;
    files[key] = (name: name, bytes: bytes, version: version);
    return DriveFile(id: key, name: name, modified: '$version');
  }

  void put(String name, Object json) {
    files['f${_next++}'] = (name: name, bytes: utf8.encode(jsonEncode(json)), version: 1);
  }
}

void main() {
  final course = Curriculum(jsonDecode(utf8.decode(gzip.decode(File('assets/curriculum.json.gz').readAsBytesSync()))));
  final base = DateTime(2026, 11, 2, 12);

  /// A device signed in to [drive] as [account].
  Future<(AppState, SyncService)> device(FakeDrive drive, {String account = 'me@example.com', String? folder}) async {
    final dir = folder ?? Directory.systemTemp.createTempSync('yue-sync').path;
    addTearDown(() {
      if (folder == null) Directory(dir).deleteSync(recursive: true);
    });
    final store = Store.open(dir);
    addTearDown(store.close);
    late AppState state;
    final sync = SyncService.load(
      store,
      connect: (_) => drive,
      signIn: ({cancel}) async => GoogleAccount(email: account, refreshToken: 'token-$account'),
      name: 'test',
    );
    addTearDown(sync.dispose);
    state = AppState(store, course, sync: sync)..clock = () => base;
    sync.onIncoming = state.reload;
    return (state, sync);
  }

  test('a device signing in with progress merges it with what’s in Drive', () async {
    final drive = FakeDrive();
    final (a, syncA) = await device(drive);
    final (b, syncB) = await device(drive);
    a.rate('wr:一', Rating.good);
    b.rate('wr:二', Rating.good);
    a.finishLesson(course.levels.first.lessons.first);
    b.markRead('passage');

    await syncA.turnOn();
    await syncB.turnOn();
    await syncA.run();

    for (final s in [a, b]) {
      expect(s.cards.keys, containsAll(['wr:一', 'wr:二']));
      expect(s.lessonDone(course.levels.first.lessons.first), isTrue);
      expect(s.hasRead('passage'), isTrue);
      expect(s.learned, containsAll(['一', '二']));
    }
    expect(syncA.error, isNull);
    expect(syncB.error, isNull);
  });

  test('one card reviewed apart reaches the same memory on both devices', () async {
    final drive = FakeDrive();
    final (a, syncA) = await device(drive);
    final (b, syncB) = await device(drive);
    await syncA.turnOn();
    await syncB.turnOn();

    a.clock = () => base;
    a.rate('wr:三', Rating.good);
    b.clock = () => base.add(const Duration(days: 3));
    b.rate('wr:三', Rating.again);
    await syncA.run();
    await syncB.run();
    await syncA.run();

    final (ma, mb) = (a.cards['wr:三']!, b.cards['wr:三']!);
    expect(ma.reps, 2);
    expect(ma.lapses, 1);
    expect((ma.stability, ma.difficulty, ma.lastMs, ma.dueMs), (mb.stability, mb.difficulty, mb.lastMs, mb.dueMs));
  });

  test('an exam’s missed card stays due on the other device', () async {
    final drive = FakeDrive();
    final (a, syncA) = await device(drive);
    final (b, syncB) = await device(drive);
    await syncA.turnOn();
    await syncB.turnOn();
    a.rate('wr:四', Rating.easy);
    a.finishExam(course.levels.first, 0.5, ['wr:四']);
    await syncA.run();
    await syncB.run();
    expect(b.cards['wr:四']!.dueMs, a.cards['wr:四']!.dueMs);
    expect(b.cards['wr:四']!.dueMs, base.millisecondsSinceEpoch);
  });

  test('a day’s counts add up across devices, however many rounds run', () async {
    final drive = FakeDrive();
    final (a, syncA) = await device(drive);
    final (b, syncB) = await device(drive);
    await syncA.turnOn();
    await syncB.turnOn();
    a.rate('wr:五', Rating.good);
    a.rate('wr:六', Rating.good);
    b.rate('wr:七', Rating.good);
    for (var i = 0; i < 3; i++) {
      await syncA.run();
      await syncB.run();
    }
    expect(a.today.reviews, 3);
    expect(b.today.reviews, 3);
    b.clock = () => base.add(const Duration(minutes: 1));
    b.rate('wr:八', Rating.good);
    await syncB.run();
    await syncA.run();
    expect(a.today.reviews, 4);
    expect(b.today.reviews, 4);
  });

  test('the latest setting wins; the best streak only goes up', () async {
    final drive = FakeDrive();
    final (a, syncA) = await device(drive);
    final (b, syncB) = await device(drive);
    await syncA.turnOn();
    await syncB.turnOn();
    b.setTheme('Sunrise');
    await syncB.run();
    await syncA.run();
    expect(a.themeName, 'Sunrise');

    drive.put('other_2026-11-02.json', {
      'version': 1,
      'meta': [
        ['best_streak', '12', 9999999999999],
        ['sync_machine', 'stolen', 9999999999999],
      ],
    });
    await syncA.run();
    expect(a.best, 12);
    expect(a.store.machine, isNot('stolen'));
  });

  test('a freeze spent on a day another device kept comes back', () async {
    final drive = FakeDrive();
    final (a, syncA) = await device(drive);
    await syncA.turnOn();
    final date = AppState.key(AppState.dayOf(base).subtract(const Duration(days: 1)));
    a.store.saveDay(DayRow(date: date, target: 0, frozen: true));
    a.store.setMeta('freezes', '0');
    drive.put('other_$date.json', {
      'version': 1,
      'day': [0, 10, 0, 1, 0],
    });
    await syncA.run();
    expect(a.freezes, 1);
    expect(a.days[date]!.complete, isTrue);
  });

  test('a file that can’t be read changes nothing and is tried again', () async {
    final drive = FakeDrive();
    final (a, syncA) = await device(drive);
    await syncA.turnOn();
    drive.put('bad_2026-11-02.json', {
      'version': 1,
      'lessons': [['good-lesson', 1]],
      'reviews': [['wr:九', 'not a time', 3, 0]],
    });
    await syncA.run();
    expect(a.lessonDone(course.levels.first.lessons.first), isFalse);
    expect(a.store.lessonsDone(), isNot(contains('good-lesson')));
    expect(syncA.error, contains('couldn’t be read'));

    final id = drive.files.entries.firstWhere((e) => e.value.name.startsWith('bad_')).key;
    drive.files[id] = (name: 'bad_2026-11-02.json', bytes: utf8.encode(jsonEncode({'version': 1, 'lessons': [['good-lesson', 1]]})), version: 2);
    await syncA.run();
    expect(a.store.lessonsDone(), contains('good-lesson'));
    expect(syncA.error, isNull);
  });

  test('a newer file format is left until this device updates', () async {
    final drive = FakeDrive();
    final (a, syncA) = await device(drive);
    await syncA.turnOn();
    drive.put('newer_2026-11-02.json', {'version': 2, 'lessons': [['from-the-future', 1]]});
    await syncA.run();
    expect(a.store.lessonsDone(), isNot(contains('from-the-future')));
    expect(syncA.error, contains('newer version'));
  });

  test('other files in the folder, and names reaching outside it, are ignored', () async {
    final drive = FakeDrive();
    final (a, syncA) = await device(drive);
    await syncA.turnOn();
    drive.put('../../evil_2026-11-02.json', {'version': 1, 'lessons': [['x', 1]]});
    drive.put('notes.txt', {'version': 1, 'lessons': [['x', 1]]});
    await syncA.run();
    expect(a.store.lessonsDone(), isNot(contains('x')));
    expect(syncA.error, isNull);
  });

  test('being signed out by Google stops sync and says so', () async {
    final drive = FakeDrive();
    final (_, syncA) = await device(drive);
    await syncA.turnOn();
    drive.failWith = const DriveError('Google signed Yue out. Sign in again.', signedOut: true);
    await syncA.run();
    expect(syncA.isOn, isFalse);
    expect(syncA.error, contains('signed Yue out'));
  });

  test('a failed round keeps the changes to send next time', () async {
    final drive = FakeDrive();
    final (a, syncA) = await device(drive);
    final (b, syncB) = await device(drive);
    await syncA.turnOn();
    await syncB.turnOn();
    drive.failWith = const DriveError('offline', unreachable: true);
    a.rate('wr:十', Rating.good);
    await syncA.run();
    expect(syncA.error, 'offline');
    expect(a.store.hasUnsent, isTrue);
    drive.failWith = null;
    await syncA.run();
    expect(a.store.hasUnsent, isFalse);
    await syncB.run();
    expect(b.cards, contains('wr:十'));
  });

  test('moving to another account takes everything here with it', () async {
    final first = FakeDrive(), second = FakeDrive();
    final (a, syncA) = await device(first);
    final (b, syncB) = await device(first);
    await syncA.turnOn();
    await syncB.turnOn();
    b.rate('wr:天', Rating.good);
    await syncB.run();
    await syncA.run();
    await syncA.turnOff();

    final dir = a.store.folder;
    final before = a.store.machine;
    final moved = SyncService.load(a.store, connect: (_) => second, signIn: ({cancel}) async => const GoogleAccount(email: 'new@example.com', refreshToken: 'x', id: 'someone-else'), name: 'test');
    addTearDown(moved.dispose);
    await moved.turnOn();
    expect(a.store.machine, isNot(before));
    expect(dir, isNotEmpty);

    final (c, syncC) = await device(second, account: 'new@example.com');
    await syncC.turnOn();
    expect(c.cards, contains('wr:天'));
  });

  test('signing out and back in merges again, without doubling anything', () async {
    final drive = FakeDrive();
    final (a, syncA) = await device(drive);
    final (b, syncB) = await device(drive);
    await syncA.turnOn();
    await syncB.turnOn();
    a.rate('wr:地', Rating.good);
    await syncA.run();
    await syncB.run();
    await syncB.turnOff();
    await syncB.turnOn();
    await syncB.run();
    expect(b.cards['wr:地']!.reps, 1);
    expect(b.today.reviews, 1);
  });

  test('a database from before sync keeps everything, and sends it', () async {
    final dir = Directory.systemTemp.createTempSync('yue-v1');
    addTearDown(() => dir.deleteSync(recursive: true));
    final db = sqlite3.open(p.join(dir.path, 'yue.db'));
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
      INSERT INTO cards VALUES('wr:老', 5.0, 5.0, 1000, 2000, 1, 0);
      INSERT INTO reviews(card, at_ms, rating, taken_ms) VALUES('wr:老', 1000, 3, 500);
      INSERT INTO lessons VALUES('old-lesson', 1000);
      INSERT INTO reads VALUES('old-read', 1000);
      INSERT INTO exams(level, at_ms, score, passed) VALUES(1, 1000, 0.9, 1);
      INSERT INTO days VALUES('2020-01-01', 5, 7, 1, 1, 0);
      INSERT INTO meta VALUES('theme', 'Sunset');
      PRAGMA user_version = 1;
    ''');
    db.close();

    final drive = FakeDrive();
    final (old, syncOld) = await device(drive, folder: dir.path);
    expect(old.cards['wr:老']!.stability, 5.0);
    expect(old.store.lessonsDone(), contains('old-lesson'));
    expect(old.passed, 1);
    expect(old.themeName, 'Sunset');
    await syncOld.turnOn();

    final (fresh, syncFresh) = await device(drive);
    await syncFresh.turnOn();
    expect(fresh.cards, contains('wr:老'));
    expect(fresh.store.lessonsDone(), contains('old-lesson'));
    expect(fresh.hasRead('old-read'), isTrue);
    expect(fresh.passed, 1);
    expect(fresh.days['2020-01-01']!.reviews, 7);
    expect(fresh.themeName, 'Sunset');
  });

  testWidgets('Settings offers sign-in, fits a short window, and says when it can’t', (t) async {
    t.view.physicalSize = const Size(750, 500);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final dir = Directory.systemTemp.createTempSync('yue-sync-ui');
    addTearDown(() => dir.deleteSync(recursive: true));
    final store = Store.open(dir.path);
    addTearDown(store.close);
    final sync = SyncService.load(store, signIn: ({cancel}) async => throw const DriveError('Google sync is not set up in this build of Yue.'));
    await t.pumpWidget(YueApp(state: AppState(store, course, sync: sync)));
    await t.pumpAndSettle();
    await t.tap(find.byTooltip('Settings and sync'));
    await t.pumpAndSettle();
    final button = find.text('Sign in with Google');
    await t.ensureVisible(button);
    await t.pumpAndSettle();
    await t.tap(button);
    await t.pumpAndSettle();
    expect(find.text('Google sync is not set up in this build of Yue.'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
}
