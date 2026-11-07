import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'google_drive.dart';
import 'store.dart';

/// Runs sync: copies this device's change files up to Yue's hidden folder in
/// the Google Drive signed in to, and takes in everyone else's. Signing in on a
/// device that already has progress merges it with what's there.
///
/// The sign-in lives beside the data, as sync.json.
class SyncService extends ChangeNotifier {
  SyncService._(this.store, this._file, this._config, this._connect, this._signIn, this._name);

  /// [connect] and [signIn] stand in for Google in tests, [name] for this
  /// device's name.
  static SyncService load(
    Store store, {
    SyncDrive Function(String refreshToken)? connect,
    Future<GoogleAccount> Function({Future<void>? cancel})? signIn,
    String? name,
  }) {
    final file = File(p.join(store.folder, 'sync.json'));
    var config = <String, dynamic>{};
    try {
      if (file.existsSync()) config = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    } on Object {
      // Damaged: sign in again.
    }
    return SyncService._(
      store,
      file,
      config,
      connect ?? AppDataFolder.new,
      signIn ?? signInWithGoogle,
      name ?? (Platform.isAndroid ? 'Phone' : Platform.localHostname),
    );
  }

  final Store store;
  final File _file;
  final Map<String, dynamic> _config;
  final SyncDrive Function(String refreshToken) _connect;
  final Future<GoogleAccount> Function({Future<void>? cancel}) _signIn;
  final String _name;

  /// Called after a round brought something in from another device.
  VoidCallback? onIncoming;

  bool get isOn => _config['refresh'] is String;
  String? get email => isOn ? _config['email'] as String? : null;

  bool busy = false;
  DateTime? lastSynced;
  String? error;

  SyncDrive? _drive;
  Timer? _timer;
  Future<void>? _running;
  var _lastFull = DateTime.fromMillisecondsSinceEpoch(0);

  Map<String, dynamic> get _ids => (_config['ids'] ??= <String, dynamic>{}) as Map<String, dynamic>;

  Future<void> _save() => _file.writeAsString(jsonEncode(_config));

  /// Looks every half minute: syncs at once when something changed here, and
  /// every few minutes regardless, to hear from the other devices.
  void start() {
    _timer?.cancel();
    if (!isOn) return;
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (store.hasUnsent || DateTime.now().difference(_lastFull) > const Duration(minutes: 3)) unawaited(run());
    });
  }

  /// For when the window comes back: shows the latest from elsewhere.
  void refresh() {
    if (isOn && DateTime.now().difference(_lastFull) > const Duration(seconds: 20)) unawaited(run());
  }

  /// For when the window goes to the back: you may be switching devices.
  void sendChanges() {
    if (isOn && store.hasUnsent) unawaited(run());
  }

  /// Opens Google's sign-in in the browser, waits for it, and starts syncing.
  /// Stops waiting when [cancel] completes.
  Future<void> turnOn({Future<void>? cancel}) async {
    final account = await _signIn(cancel: cancel);
    final before = _config['accountId'] as String?;
    if (before != null && before != account.identity) {
      store.adoptEverything();
      _config.remove('ids');
    }
    store.markAllUnsent();
    _config
      ..['email'] = account.email
      ..['accountId'] = account.identity
      ..['refresh'] = account.refreshToken;
    _drive = null;
    error = null;
    await _save();
    notifyListeners();
    start();
    await run();
  }

  /// Stops syncing and forgets the sign-in. What's in Drive stays, and so does
  /// everything here. [error] says why, when it wasn't asked for.
  Future<void> turnOff({String? error}) async {
    _timer?.cancel();
    _drive = null;
    _config
      ..remove('refresh')
      ..remove('email');
    await _save();
    this.error = error;
    notifyListeners();
  }

  /// One round: everyone else's changes in, ours up.
  Future<void> run() {
    if (!isOn) return Future.value();
    return _running ??= _round().whenComplete(() => _running = null);
  }

  Future<void> _round() async {
    _lastFull = DateTime.now();
    busy = true;
    notifyListeners();
    try {
      final drive = _drive ??= _connect(_config['refresh'] as String);
      final files = await drive.list();
      final problem = await _pull(drive, files);
      await _push(drive, files);
      lastSynced = DateTime.now();
      error = problem;
    } on DriveError catch (e) {
      if (e.signedOut) {
        await turnOff(error: e.message);
      } else {
        error = e.message;
      }
    } catch (e) {
      error = '$e';
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  /// A file in Drive's name, like a1b2c3d4e5f6a7b8_2026-10-24.json, as the
  /// device it's from and its day; null for any other name.
  static final _fileName = RegExp(r'^([A-Za-z0-9-]+)_(\d{4}-\d{2}-\d{2})\.json$');

  /// Takes in every other device's file that's new or changed. A file that
  /// can't be taken in stops only itself, and is tried again next round.
  /// Returns what to say about any that couldn't.
  Future<String?> _pull(SyncDrive drive, List<DriveFile> files) async {
    final me = store.machine, touched = <String>{};
    var changed = false, unread = false, newer = false;
    for (final f in files) {
      final match = _fileName.firstMatch(f.name);
      if (match == null || match[1] == me || store.seenStamp(f.id) == f.modified) continue;
      final bytes = await drive.download(f.id);
      try {
        final json = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
        if (json['version'] != 1) {
          newer = true;
          continue;
        }
        changed |= store.mergeFile(match[1]!, match[2]!, f.id, f.modified, json, touched);
      } on Object catch (e) {
        if (e is DriveError) rethrow;
        unread = true;
      }
    }
    if (touched.isNotEmpty) store.replay(touched);
    if (changed) onIncoming?.call();
    if (newer) return 'Another device has a newer version of Yue. Update this one to get its progress.';
    return unread ? 'Some progress from another device couldn’t be read. It’ll be tried again.' : null;
  }

  /// Sends this device's changed days. A file made here is remembered, so one
  /// Drive doesn't list yet isn't made twice.
  Future<void> _push(SyncDrive drive, List<DriveFile> files) async {
    final me = store.machine;
    final there = {for (final f in files) f.name: f.id};
    for (final (date, n) in store.unsentDays()) {
      final name = '${me}_$date.json';
      final bytes = utf8.encode(store.changeFile(date, _name));
      final id = there[name] ?? _ids[name] as String?;
      DriveFile made;
      try {
        made = await drive.upload(name, bytes, id: id);
      } on DriveError catch (e) {
        if (!e.notFound || id == null) rethrow;
        made = await drive.upload(name, bytes); // deleted from Drive: made again
      }
      _ids[name] = made.id;
      await _save();
      store.markSent(date, n);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
