import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:yue/data/curriculum.dart';
import 'package:yue/data/fsrs.dart';
import 'package:yue/data/store.dart';
import 'package:yue/state/app_state.dart';

/// The characters a TrueType font has glyphs for, from its format 12 or 4 map.
Set<int> fontCharacters(String path) {
  final data = ByteData.sublistView(File(path).readAsBytesSync());
  final tables = data.getUint16(4);
  var cmap = 0;
  for (var i = 0; i < tables; i++) {
    final at = 12 + i * 16;
    if (String.fromCharCodes(data.buffer.asUint8List(data.offsetInBytes + at, 4)) == 'cmap') cmap = data.getUint32(at + 8);
  }
  final out = <int>{};
  for (var i = 0; i < data.getUint16(cmap + 2); i++) {
    final map = cmap + data.getUint32(cmap + 8 + i * 8);
    if (data.getUint16(map) == 12) {
      for (var g = 0; g < data.getUint32(map + 12); g++) {
        final group = map + 16 + g * 12;
        for (var c = data.getUint32(group); c <= data.getUint32(group + 4); c++) {
          out.add(c);
        }
      }
    } else if (data.getUint16(map) == 4) {
      final segments = data.getUint16(map + 6) ~/ 2;
      for (var s = 0; s < segments; s++) {
        final end = data.getUint16(map + 14 + s * 2), start = data.getUint16(map + 16 + segments * 2 + s * 2);
        for (var c = start; c <= end && c != 0xffff; c++) {
          out.add(c);
        }
      }
    }
  }
  return out;
}

void main() {
  late Curriculum course;
  late Map<String, dynamic> json;

  setUpAll(() {
    json = jsonDecode(utf8.decode(gzip.decode(File('assets/curriculum.json.gz').readAsBytesSync())));
    course = Curriculum(json);
  });

  Iterable<String> shown() sync* {
    for (final w in course.words.values) {
      yield w.w;
    }
    for (final s in course.sentences.values) {
      yield s.zh;
    }
    for (final p in course.passages) {
      yield p.zh;
    }
    for (final g in course.grammar.values) {
      yield '${g.title} ${g.short} ${g.body}';
    }
    yield* course.names.keys;
  }

  test('nothing a learner reads is in Simplified', () {
    const simplified = '这们学吗说时国爱对发头间见语门车马东书买卖钱电话饭师习气开关长还过让认识读写听问题';
    for (final text in shown()) {
      for (final c in simplified.split('')) {
        expect(text.contains(c), isFalse, reason: '$c in $text');
      }
    }
  });

  test('one Simplified word with two Traditional forms is two words, each in its band', () {
    for (final (form, band) in const [('乾', 1), ('幹', 1), ('只', 2), ('隻', 3), ('喂', 2), ('餵', 4), ('系', 3), ('繫', 4), ('划', 4), ('劃', 4), ('面', 2), ('麵', 2), ('稱', 2)]) {
      expect(course.words[form]?.band, band, reason: form);
    }
  });

  test('lesson ids keep their words', () {
    expect(course.levels.length, 66);
    expect(course.levels.first.lessons.first.words, ['我', '你', '他', '好', '是', '不', '嗎', '人']);
    expect(course.levels.expand((l) => l.lessons).length, 666);
    for (final l in course.levels) {
      for (final s in l.lessons) {
        for (final w in s.words) {
          expect(course.words[w]!.band, l.band, reason: w);
        }
      }
    }
  });

  test('a word card shows only sentences of words already known', () {
    final lessonOf = {
      for (final (n, l) in course.levels.indexed)
        for (final (i, s) in l.lessons.indexed)
          for (final w in s.words) w: (n * 1000) + i,
    };
    for (final w in course.words.values) {
      for (final id in w.examples) {
        for (final t in course.sentences[id]!.toks) {
          if (lessonOf[t] case final at?) expect(at, lessThanOrEqualTo(lessonOf[w.w]!), reason: '$t in ${w.w}: $id');
        }
      }
    }
  });

  test('exams use only people\'s sentences that no lesson shows', () {
    final taught = <String>{
      for (final w in course.words.values) ...w.examples,
      for (final g in course.grammar.values) ...g.examples,
      for (final l in course.levels)
        for (final s in l.lessons) ...s.sentences,
    };
    for (final l in course.levels) {
      for (final id in l.exam) {
        expect(course.sentences[id]!.ai, isFalse, reason: id);
        expect(taught, isNot(contains(id)));
      }
    }
  });

  test('beginner bands have a reading step in every lesson and an example on every card', () {
    for (final l in course.levels.where((l) => l.band <= 2)) {
      for (final s in l.lessons) {
        expect(s.sentences, isNotEmpty, reason: s.id);
      }
    }
    // 子 is only ever part of a longer word.
    expect(course.words.values.where((w) => w.band <= 2 && w.examples.isEmpty).map((w) => w.w), ['子']);
  });

  test('the page is written by people', () {
    for (final id in course.page) {
      expect(course.sentences[id]!.ai, isFalse, reason: id);
    }
  });

  test('the fonts draw every character', () {
    final chars = <int>{};
    for (final text in shown()) {
      chars.addAll(text.runes.where((c) => c >= 0x3400 && c <= 0x9fff));
    }
    for (final c in course.chars.values) {
      chars.addAll('${c.c}${c.hint}${c.semantic}${c.phonetic}${c.radical}'.runes.where((c) => c >= 0x3400 && c <= 0x9fff));
    }
    final kai = fontCharacters('assets/fonts/chinese/WenKaiTC.ttf'), medium = fontCharacters('assets/fonts/chinese/WenKaiTCMedium.ttf');
    final sans = fontCharacters('assets/fonts/chinese/NotoSansTC.ttf'), rare = fontCharacters('assets/fonts/chinese/WenKaiRare.ttf');
    for (final c in chars) {
      final char = String.fromCharCode(c);
      expect(kai.contains(c) || sans.contains(c) || rare.contains(c), isTrue, reason: char);
      expect(medium.contains(c) || sans.contains(c) || rare.contains(c), isTrue, reason: char);
    }
    for (final text in [for (final w in course.words.values) w.w, for (final s in course.sentences.values) s.zh]) {
      for (final c in text.runes.where((c) => c >= 0x3400 && c <= 0x9fff)) {
        expect(kai.contains(c) && sans.contains(c), isTrue, reason: String.fromCharCode(c));
      }
    }
  });

  group('progress from the Simplified course', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('yue-test'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('moves to the word\'s new spelling', () {
      final old = Store.open(dir.path);
      old.saveReview('wr:吗', Fsrs.review(null, Rating.good, 1000), Rating.good, 0);
      old.saveReview('wr:我', Fsrs.review(null, Rating.good, 1000), Rating.good, 0);
      final state = AppState(Store.open(dir.path), course);
      expect(state.cards.keys, containsAll(['wr:嗎', 'wr:我']));
      expect(state.cards, isNot(contains('wr:吗')));
      expect(state.cards['wr:嗎']!.reps, 1);
      expect(state.learned, contains('嗎'));
    });

    test('still moves when it arrives from a device that hasn\'t updated', () {
      final store = Store.open(dir.path)..renamedWords = course.renamed;
      final touched = <String>{};
      store.mergeFile('other', '2026-11-07', 'file', 'stamp', {
        'reviews': [['wr:吗', 1000, Rating.good.value, 0]],
      }, touched);
      store.replay(touched);
      expect(touched, {'wr:嗎'});
      expect(store.cards().keys, ['wr:嗎']);
    });
  });
}
