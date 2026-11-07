# Yue

Learn to read and write Mandarin. Built on Eclipse's design system.

- Course data: `python3 -I tool/build_curriculum.py` turns `data_src/` (downloads, not in git) and `content/` into `assets/curriculum.json.gz`.
- Sources: HSK 3.0 word list, CC-CEDICT (CC BY-SA), Make Me a Hanzi, Tatoeba sentences by native speakers (CC BY), FSRS-6 weights from py-fsrs.
- AI-written: `content/passages.json` (labelled in the app, never tested), `content/grammar.json` and `content/glosses.json`.

## Google sync

Progress syncs between devices through a hidden folder in your Google Drive. It needs a Google client:

1. In a Google Cloud project for Yue, enable the Google Drive API.
2. Under Google Auth Platform, make a Desktop client, with the `drive.appdata` scope.
3. Copy `lib/data/google_client.example.dart` to `lib/data/google_client.dart`, which git ignores, and fill it in.

