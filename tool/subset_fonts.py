#!/usr/bin/env python3
"""Cuts the Traditional fonts in data_src/fonts down to the characters the app
shows, into assets/fonts/chinese. Run after build_curriculum.py, from a venv with
tool/requirements.txt. A font falls back on the other for rare character parts,
so this fails only if a character has no glyph in either."""
import glob, gzip, json, os, re, sys
from fontTools import subset
from fontTools.ttLib import TTFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FONTS = {'NotoSansTC-VF.ttf': 'NotoSansTC.ttf', 'LXGWWenKaiTC-Regular.ttf': 'WenKaiTC.ttf', 'LXGWWenKaiTC-Medium.ttf': 'WenKaiTCMedium.ttf'}
# Everything that isn't plain Latin, which the app's other fonts draw.
HAN = re.compile(r'[⺀-⿿　-ヿ㐀-鿿豈-﫿＀-￯]')

with gzip.open(os.path.join(ROOT, 'assets', 'curriculum.json.gz'), 'rt', encoding='utf-8') as f:
    course = json.load(f)
course.pop('renamed')  # The old Simplified spellings, which are never shown.
for info in course['chars'].values(): info.pop('parts')  # Nor are these.
text = json.dumps(course, ensure_ascii=False)
for path in glob.glob(os.path.join(ROOT, 'lib', '**', '*.dart'), recursive=True):
    text += open(path, encoding='utf-8').read()
chars = sorted(set(HAN.findall(text)) - {'\u9fff'})  # The end of a character range in the code.
with open(os.path.join(ROOT, 'data_src', 'used_chars.txt'), 'w', encoding='utf-8') as f:
    f.write(''.join(chars))
print(len(chars), 'characters')

options = subset.Options(layout_features=['*'], hinting=False, notdef_outline=True, name_IDs=['*'])
missing = {}
for source, target in FONTS.items():
    font = TTFont(os.path.join(ROOT, 'data_src', 'fonts', source))
    have = font.getBestCmap()
    missing[source] = [c for c in chars if ord(c) not in have]
    maker = subset.Subsetter(options)
    maker.populate(text=''.join(chars))
    maker.subset(font)
    out = os.path.join(ROOT, 'assets', 'fonts', 'chinese', target)
    font.save(out)
    print(target, os.path.getsize(out), 'bytes')
for source, lost in missing.items():
    print(source, 'lacks', ''.join(lost))
# Old character parts the Traditional fonts don't have come from the full Simplified
# Kai, the last fallback.
nowhere = sorted(set.intersection(*map(set, missing.values())))
rare = TTFont(os.path.join(ROOT, 'data_src', 'fonts', 'WenKai.ttf'))
lost = [c for c in nowhere if ord(c) not in rare.getBestCmap()]
if lost: sys.exit(f'No glyph anywhere for: {lost}')
maker = subset.Subsetter(options)
maker.populate(text=''.join(nowhere))
maker.subset(rare)
rare.save(os.path.join(ROOT, 'assets', 'fonts', 'chinese', 'WenKaiRare.ttf'))
print('rare parts:', ''.join(nowhere))
