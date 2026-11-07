import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;

class Word {
  Word(Map<String, dynamic> j)
    : w = j['w'],
      py = j['py'],
      en = j['en'],
      band = j['band'],
      senses = (j['gl'] as List).cast<String>(),
      examples = (j['ex'] as List).cast<String>();
  final String w, py, en;
  final int band;
  final List<String> senses, examples;
}

class CharInfo {
  CharInfo(Map<String, dynamic> j)
    : c = j['c'],
      en = j['en'],
      radical = j['rad'],
      type = j['type'],
      hint = j['hint'],
      semantic = j['sem'],
      phonetic = j['pho'],
      share = (j['share'] as num).toDouble();
  final String c, en, radical, type, hint, semantic, phonetic;

  /// Its share of all the characters in the sentence library.
  final double share;
}

class Radical {
  Radical(Map<String, dynamic> j) : r = j['r'], en = j['en'], full = j['full'];
  final String r, en, full;
}

class Sentence {
  Sentence(Map<String, dynamic> j)
    : id = j['id'],
      zh = j['zh'],
      en = j['en'],
      toks = (j['toks'] as List).cast<String>(),
      level = j['lvl'],
      exam = j['exam'];
  final String id, zh, en;
  final List<String> toks;
  final int level;
  final bool exam;
}

class Grammar {
  Grammar(Map<String, dynamic> j)
    : id = j['id'],
      title = j['title'],
      short = j['short'],
      body = j['body'],
      examples = (j['ex'] as List).cast<String>();
  final String id, title, short, body;
  final List<String> examples;
}

class Lesson {
  Lesson(this.level, this.index, Map<String, dynamic> j)
    : words = (j['words'] as List).cast<String>(),
      radicals = ((j['rad'] ?? const []) as List).cast<String>(),
      grammar = ((j['grammar'] ?? const []) as List).cast<String>(),
      sentences = (j['sent'] as List).cast<String>();
  final int level, index;
  final List<String> words, radicals, grammar, sentences;
  String get id => '$level.$index';
}

class Level {
  Level(Map<String, dynamic> j)
    : n = j['n'],
      band = j['band'],
      exam = (j['exam'] as List).cast<String>(),
      readable = j['readable'],
      lessons = [
        for (final (i, l) in (j['lessons'] as List).indexed) Lesson(j['n'], i, l),
      ];
  final int n, band, readable;
  final List<String> exam;
  final List<Lesson> lessons;
}

class Passage {
  Passage(Map<String, dynamic> j)
    : title = j['title'],
      zh = j['zh'],
      en = j['en'],
      toks = (j['toks'] as List).cast<String>(),
      level = j['lvl'],
      extra = {
        for (final e in ((j['extra'] ?? const {}) as Map).entries) e.key as String: (e.value['py'] as String, e.value['en'] as String),
      };
  final String title, zh, en;
  final List<String> toks;
  final int level;

  /// Words outside the course's list, with their own pinyin and meaning.
  final Map<String, (String, String)> extra;
}

/// The whole course, read once from the bundled file. Built by
/// tool/build_curriculum.py from the HSK 3.0 list, CC-CEDICT, Make Me a Hanzi and
/// Tatoeba.
class Curriculum {
  Curriculum(Map<String, dynamic> j)
    : words = {for (final w in j['words']) w['w'] as String: Word(w)},
      chars = {for (final c in (j['chars'] as Map).values) c['c'] as String: CharInfo(c)},
      radicals = {for (final r in j['radicals']) r['r'] as String: Radical(r)},
      names = (j['names'] as Map).cast<String, String>(),
      sentences = {for (final s in j['sentences']) s['id'] as String: Sentence(s)},
      grammar = {for (final g in j['grammar']) g['id'] as String: Grammar(g)},
      levels = [for (final l in j['levels']) Level(l)],
      passages = [for (final p in j['passages']) Passage(p)],
      page = (j['page'] as List).cast<String>(),
      totalSentences = j['totalSentences'] {
    for (final w in words.values) {
      (byPinyin[toneless(w.py)] ??= []).add(w);
      for (final c in w.w.split('')) {
        (byChar[c] ??= []).add(w);
      }
    }
    for (final l in levels) {
      for (final s in l.lessons) {
        for (final w in s.words) {
          wordLevel[w] = l.n;
        }
      }
    }
  }

  final Map<String, Word> words;
  final Map<String, CharInfo> chars;
  final Map<String, Radical> radicals;
  final Map<String, String> names;
  final Map<String, Sentence> sentences;
  final Map<String, Grammar> grammar;
  final List<Level> levels;
  final List<Passage> passages;
  final List<String> page;
  final int totalSentences;
  final Map<String, List<Word>> byPinyin = {}, byChar = {};
  final Map<String, int> wordLevel = {};

  /// Bands for the road map: what each lets you do.
  static const bandGoals = {
    1: 'Greetings, family, numbers, food and daily routines.',
    2: 'Plans, reasons and short messages between friends.',
    3: 'Work, travel, health and opinions in simple terms.',
    4: 'Longer stories and everyday articles with some help.',
    5: 'News about familiar topics, and easy novels.',
    6: 'Most everyday writing, including longer texts on general topics.',
  };

  static Future<Curriculum> load() async {
    final data = await rootBundle.load('assets/curriculum.json.gz');
    final bytes = gzip.decode(data.buffer.asUint8List());
    return Curriculum(jsonDecode(utf8.decode(bytes)));
  }
}

const _marks = {
  'ā': 'a', 'á': 'a', 'ǎ': 'a', 'à': 'a', 'ē': 'e', 'é': 'e', 'ě': 'e', 'è': 'e', 'ī': 'i', 'í': 'i', 'ǐ': 'i', 'ì': 'i',
  'ō': 'o', 'ó': 'o', 'ǒ': 'o', 'ò': 'o', 'ū': 'u', 'ú': 'u', 'ǔ': 'u', 'ù': 'u', 'ǖ': 'v', 'ǘ': 'v', 'ǚ': 'v', 'ǜ': 'v', 'ü': 'v',
};

/// [pinyin] with no tone marks, numbers, spaces or capitals, so typed answers compare.
String toneless(String pinyin) {
  final out = StringBuffer();
  for (final c in pinyin.toLowerCase().split('')) {
    final mapped = _marks[c] ?? c;
    if (RegExp(r'[a-z]').hasMatch(mapped)) out.write(mapped);
  }
  return out.toString().replaceAll('uu', 'v');
}

/// Whether [typed] is [pinyin], allowing u for ü.
bool pinyinMatches(String typed, String pinyin) {
  final a = toneless(typed), b = toneless(pinyin);
  return a == b || a.replaceAll('v', 'u') == b.replaceAll('v', 'u');
}
