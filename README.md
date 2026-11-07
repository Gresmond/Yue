# Yue

Learn to read and write Mandarin. Built on Eclipse's design system.

- The course is in Traditional characters as written in Taiwan, teaching HSK vocabulary, with the usual Taiwan word noted where it differs (`content/taiwan_words.json`).
- Course data, from a venv with `tool/requirements.txt`: `python -I tool/build_curriculum.py` turns `data_src/` (downloads, not in git) and `content/` into `assets/curriculum.json.gz`. Then `python -I tool/subset_fonts.py` cuts the fonts down to the characters it uses.
- `content/lessons.json` fixes which words each lesson teaches, so lesson ids keep their meaning when the sentences change.
- Sources: HSK 3.0 word list, CC-CEDICT (CC BY-SA), Make Me a Hanzi, Tatoeba sentences by native speakers (CC BY), OpenCC's conversion tables (Apache 2.0), FSRS-6 weights from py-fsrs. Noto Sans TC and LXGW WenKai TC, plus a few rare character parts from LXGW WenKai (all SIL Open Font License).
- AI-written: `content/ai_sentences.tsv` (beginner example sentences, labelled in the app, never tested), `content/passages.json` (labelled in the app, never tested), `content/grammar.json`, `content/glosses.json`, `content/taiwan_words.json` and `content/char_fixes.json`.

## Google sync

Progress syncs between devices through a hidden folder in your Google Drive. It needs a Google client:

1. In a Google Cloud project for Yue, enable the Google Drive API.
2. Under Google Auth Platform, make a Desktop client, with the `drive.appdata` scope.
3. Copy `lib/data/google_client.example.dart` to `lib/data/google_client.dart`, which git ignores, and fill it in.

