#!/usr/bin/env python3
"""Turns the downloaded data in data_src/ and the hand-written content/ into
assets/curriculum.json.gz. Run with python3 -I, as data_src holds downloads."""
import bz2, collections, gzip, json, os, random, re, sys, tarfile, csv, unicodedata

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, 'data_src')
LEVEL_WORDS, LESSON_WORDS = 80, 8
MAX_BAND = 6
NAMES = {'汤姆': 'Tom', '玛丽': 'Mary', '约翰': 'John', '杰克': 'Jack', '迈克': 'Mike', '比尔': 'Bill', '爱丽丝': 'Alice', '肯': 'Ken', '露西': 'Lucy', '鲍勃': 'Bob', '吉姆': 'Jim', '简': 'Jane', '戴安娜':'Diana', '东京':'Tokyo', '日本':'Japan', '美国':'America','英国':'Britain','法国':'France','北京':'Beijing','上海':'Shanghai','中国':'China','波士顿':'Boston','纽约':'New York','伦敦':'London','巴黎':'Paris','德国':'Germany','法语':'French','英语':'English','日语':'Japanese','中文':'Chinese','汉语':'Chinese'}
PUNCT = set('。！？，、：；“”‘’（）《》…—,.!?;:"\'()- 　·')
TONE = {'ā':'a1','á':'a2','ǎ':'a3','à':'a4','ē':'e1','é':'e2','ě':'e3','è':'e4','ī':'i1','í':'i2','ǐ':'i3','ì':'i4','ō':'o1','ó':'o2','ǒ':'o3','ò':'o4','ū':'u1','ú':'u2','ǔ':'u3','ù':'u4','ǖ':'v1','ǘ':'v2','ǚ':'v3','ǜ':'v4','ü':'v','ń':'n2','ň':'n3','ḿ':'m2'}
MARKS = {'a':'āáǎà','e':'ēéěè','i':'īíǐì','o':'ōóǒò','u':'ūúǔù','v':'ǖǘǚǜ'}

def numbered_to_marked(syl):
    m = re.match(r'^([a-zA-Z:]+)([1-5])$', syl)
    if not m: return syl
    s, t = m[1].lower().replace('u:', 'v'), int(m[2])
    if t == 5: return s.replace('v', 'ü')
    i = s.find('a') if 'a' in s else s.find('e') if 'e' in s else s.find('ou') if 'ou' in s else max((s.rfind(c) for c in 'iouv'), default=-1)
    if i < 0: return s
    return (s[:i] + MARKS[s[i]][t-1] + s[i+1:]).replace('v', 'ü')

def toneless(py):
    return ''.join(TONE.get(c, c)[0] if c in TONE else c for c in py).lower().replace(' ', '').replace("'", '').replace('·','')

def load_cedict():
    out = collections.defaultdict(list)
    with gzip.open(os.path.join(SRC, 'cedict_1_0_ts_utf-8_mdbg.txt.gz'), 'rt', encoding='utf-8') as f:
        for line in f:
            if line.startswith('#'): continue
            m = re.match(r'^(\S+) (\S+) \[([^\]]+)\] /(.+)/$', line.strip())
            if m: out[m[2]].append((m[3], m[4].split('/')))
    return out

def clean_gloss(senses):
    keep = []
    for s in senses:
        if re.match(r'^(variant of|old variant|see |CL:|surname |abbr\. for|used in |\(old\)|\(archaic\)|\(dialect\)|\(literary\)|\(Tw\)|Japanese|Taiwan pr|also pr|also written|erhua variant|\(bound form\) *$)', s, re.I): continue
        s = re.sub(r' *\(?CL:.*$', '', s)
        s = re.sub(r'\[[^\]]*\]', '', s)
        s = re.sub(r'[|][^ ]*', '', s)
        s = re.sub(r'\b[^\x00-\x7f]+\b', '', s) if re.search(r'[一-鿿]', s) else s
        s = re.sub(r'^\(bound form\) ', '', s)
        s = re.sub(r'^\(coll\.\) ', '', s)
        s = re.sub(r'\s+', ' ', s).strip(' ;,')
        if s and s not in keep: keep.append(s)
    return keep

def find_gloss(ced, w, numbered):
    rows = ced.get(w, [])
    match = [r for r in rows if numbered and r[0].lower().replace(' ','') == numbered.lower().replace(' ','')]
    rows = match or rows
    if any(r[0][0].islower() for r in rows):
        rows = [r for r in rows if r[0][0].islower()]
    gl = []
    for py, senses in rows:
        senses = [x for x in senses if not re.search(r'ethnic group|dynasty|short name for|\bprovince\b|erhua form|\(CL:', x)] or senses
        for g in clean_gloss(senses):
            if g not in gl: gl.append(g)
    return gl

ced = load_cedict()
# ---- HSK words.
seen, words = {}, []
with open(os.path.join(SRC, 'hsk30.csv'), encoding='utf-8') as f:
    for r in csv.DictReader(f):
        if r['Level'] == '7-9' or int(r['Level']) > MAX_BAND: continue
        w = r['Simplified'].strip()
        w = re.sub(r'[（(].*?[)）]', '', w).split('｜')[0].split('|')[0].strip()
        if not w or not re.fullmatch(r'[一-鿿]+', w): continue
        cm = re.search(r'\[([^\]]+)\]', r['CEDICT'] or '')
        num = cm[1] if cm else None
        py = ' '.join(numbered_to_marked(s) for s in num.split()) if num else r['Pinyin']
        gloss = find_gloss(ced, w, num)
        if not gloss: gloss = find_gloss(ced, w, None)
        if not gloss: continue
        if w in seen:
            e = seen[w]
            for g in gloss:
                if g not in e['gl']: e['gl'].append(g)
            continue
        e = dict(w=w, py=py.strip(), band=int(r['Level']), pos=r['POS'], gl=gloss)
        seen[w] = e; words.append(e)
overrides = json.load(open(os.path.join(ROOT, 'content', 'glosses.json'), encoding='utf-8'))
def short_gloss(gl):
    for g in gl:
        t = re.sub(r'\([^)]*\)', '', g).strip(' ;,')
        t = re.sub(r'\s+', ' ', t)
        if t and 'Note:' not in g:
            parts = [x.strip() for x in t.split(';') if x.strip()][:2]
            t = ', '.join(parts)
            return t if len(t) <= 44 else t[:44].rsplit(' ', 1)[0]
    return re.sub(r'[()]', '', gl[0])[:44]
for e in words:
    e['gl'] = [g for g in e['gl'] if 'Note:' not in g and 'Taiwan' not in g] or e['gl']
    e['en'] = overrides.get(e['w']) or short_gloss(e['gl'])
    e['gl'] = [re.sub(r' \(Taiwan pr\. *\)', '', g) for g in e['gl']]
vocab = set(seen)
print('HSK words', len(words), {b: sum(1 for w in words if w['band']==b) for b in range(1,7)})

# ---- Sentences written by native speakers, with an English translation.
native = set()
with tarfile.open(os.path.join(SRC, 'user_languages.tar.bz2')) as t:
    for line in t.extractfile(t.getmembers()[0]).read().decode('utf-8', 'replace').splitlines():
        p = line.split('\t')
        if len(p) >= 3 and p[0] == 'cmn' and p[1] == '5': native.add(p[2])
cmn = {}
with bz2.open(os.path.join(SRC, 'cmn_sentences_detailed.tsv.bz2'), 'rt', encoding='utf-8') as f:
    for line in f:
        p = line.rstrip('\n').split('\t')
        if len(p) >= 4: cmn[p[0]] = (p[2], p[3])
links = collections.defaultdict(list)
with bz2.open(os.path.join(SRC, 'cmn-eng_links.tsv.bz2'), 'rt', encoding='utf-8') as f:
    for line in f:
        a, b = line.split()
        links[a].append(b)
need = {b for bs in links.values() for b in bs}
eng = {}
with bz2.open(os.path.join(SRC, 'eng_sentences.tsv.bz2'), 'rt', encoding='utf-8') as f:
    for line in f:
        p = line.rstrip('\n').split('\t')
        if p[0] in need: eng[p[0]] = p[2]

def segment(text):
    """Fewest HSK words; a character or stretch outside the list fails."""
    n = len(text)
    best = [None] * (n + 1); best[n] = (0, [])
    for i in range(n - 1, -1, -1):
        if text[i] in PUNCT or text[i].isdigit():
            nxt = best[i+1]
            if nxt is not None: best[i] = (nxt[0], [text[i]] + nxt[1])
            continue
        for L in range(1, min(6, n - i) + 1):
            part = text[i:i+L]
            if (part in vocab or part in NAMES) and best[i+L] is not None:
                c = best[i+L][0] + 1
                if best[i] is None or c < best[i][0]: best[i] = (c, [part] + best[i+L][1])
    return best[0][1] if best[0] else None

raw, stats = [], collections.Counter()
seen_zh = set()
for sid, (zh, owner) in cmn.items():
    stats['all'] += 1
    if owner not in native: stats['not native'] += 1; continue
    if sid not in links: stats['no english'] += 1; continue
    if re.search(r'[A-Za-z]', zh) or re.search(r'([\u4e00-\u9fff])\1\1|的的|了了|是是', zh) or not 3 <= len(zh) <= 28 or zh in seen_zh: stats['form'] += 1; continue
    ens = [eng[b] for b in links[sid] if b in eng and len(eng[b].split()) <= 16]
    if not ens: stats['english too long'] += 1; continue
    toks = segment(zh)
    if toks is None: stats['outside list'] += 1; continue
    seen_zh.add(zh)
    raw.append(dict(id=sid, zh=zh, en=min(ens, key=len), toks=toks))
print('sentences', len(raw), dict(stats))

# ---- Order: frequency in those sentences, with a few first words pinned.
freq = collections.Counter(t for s in raw for t in s['toks'] if t in vocab)
PIN = ['我','你','他','好','是','不','吗','人','很','学生','老师','的','有','这','那','什么','中国','爱','吃','喝']
pin = {w: i for i, w in enumerate(PIN)}
hanzi = {}
with open(os.path.join(SRC, 'dictionary.txt'), encoding='utf-8') as f:
    for line in f:
        d = json.loads(line); hanzi[d['character']] = d
words.sort(key=lambda e: (e['band'], pin.get(e['w'], 999), -freq[e['w']], e['w']))

def lead_radical(w):
    d = hanzi.get(w[0]); return d['radical'] if d else w[0]

levels, by_word = [], {}
i = 0
for band in range(1, MAX_BAND + 1):
    pool = [w for w in words if w['band'] == band]
    for start in range(0, len(pool), LEVEL_WORDS):
        chunk = pool[start:start+LEVEL_WORDS]
        n = len(levels) + 1
        if len(chunk) < LEVEL_WORDS // 2 and levels and levels[-1]['band'] == band:
            levels[-1]['words'] += chunk; continue
        levels.append(dict(n=n, band=band, words=chunk))
for lv in levels:
    # Words sharing a radical sit together, as grouping helps beginners.
    groups = collections.defaultdict(list)
    for w in lv['words']: groups[lead_radical(w['w'])].append(w)
    ordered = [w for k in sorted(groups, key=lambda k: (-len(groups[k]), min(lv['words'].index(x) for x in groups[k]))) for w in groups[k]]
    if lv['n'] == 1: ordered.sort(key=lambda e: pin.get(e['w'], 999))
    lv['lessons'] = [dict(words=[w['w'] for w in ordered[j:j+LESSON_WORDS]]) for j in range(0, len(ordered), LESSON_WORDS)]
    for li, l in enumerate(lv['lessons']):
        for w in l['words']: by_word[w] = (lv['n'], li)
    del lv['words']

# ---- When each sentence becomes readable.
for s in raw:
    pos = [by_word.get(t) for t in s['toks'] if t in vocab]
    s['at'] = max(pos) if pos else (1, 0)
    s['lvl'] = s['at'][0]
raw.sort(key=lambda s: (s['at'], len(s['zh'])))

# ---- Exams keep sentences no lesson shows.
random.seed(1729)
exams = collections.defaultdict(list)
per = collections.defaultdict(list)
for s in raw: per[s['lvl']].append(s)
for lv in levels:
    # Newest first, so each exam tests this level; earlier levels' spares fill gaps.
    own = per[lv['n']][:]; random.shuffle(own)
    take = own[:16] if len(own) >= 32 else own[:len(own)//2]
    lv['exam'] = [s['id'] for s in take]
    for s in take: s['exam'] = True
for i, lv in enumerate(levels):
    # A late level's rare words may have no sentences: draw on the nearest exams before it.
    j = i - 1
    while len(lv['exam']) < 12 and j >= 0:
        lv['exam'] += [x for x in levels[j]['exam'] if x not in lv['exam']][:12 - len(lv['exam'])]
        j -= 1

# ---- Grammar, each placed where it first has enough sentences.
grammar = json.load(open(os.path.join(ROOT, 'content', 'grammar.json'), encoding='utf-8'))
for s in raw: s['joined'] = ' '.join(s['toks'])
placed = {}
cursor = (1, 0)
for g in grammar:
    r = re.compile(g['re'])
    hits = [s for s in raw if not s.get('exam') and r.search(s['joined'])]
    g['count'] = len(hits)
    hits.sort(key=lambda s: s['at'])
    if len(hits) < 3: g['at'] = None; print('grammar skipped', g['id'], len(hits)); continue
    at = max(hits[2]['at'], cursor)
    cursor = at if at > cursor else cursor
    lv = levels[at[0]-1]
    if at[1] >= len(lv['lessons']): at = (at[0], len(lv['lessons'])-1)
    usable = sorted([s for s in hits if s['at'] <= at], key=lambda s: (len(s['zh']) < 5, s['at'], abs(len(s['zh']) - 9)))[:6]
    if len(usable) < 3: usable = hits[:6]
    g['at'] = at
    g['ex'] = [s['id'] for s in usable]
    for s in usable: s['used'] = True
    lv['lessons'][at[1]].setdefault('grammar', []).append(g['id'])
    # Spread them out: a later pattern starts at least a lesson on.
    nl = at[1] + 1
    cursor = (at[0], nl) if nl < len(lv['lessons']) else (at[0] + 1, 0)

# ---- Each lesson's sentences, and the reward: one you can now read.
for lv in levels:
    for li, l in enumerate(lv['lessons']):
        fresh = [s for s in per[lv['n']] if s['at'] == (lv['n'], li) and not s.get('exam')]
        fresh.sort(key=lambda s: (s.get('used', False), len(s['zh']) < 5, abs(len(s['zh']) - 10)))
        l['sent'] = [s['id'] for s in fresh[:4]]
        for s in fresh[:4]: s['used'] = True
    lv['readable'] = sum(1 for s in raw if s['lvl'] <= lv['n'])

# ---- Radicals, taught in the first lesson that uses them.
rad_rows = json.load(open(os.path.join(ROOT, 'content', 'radicals.json'), encoding='utf-8'))
rad = {r[0]: dict(r=r[0], en=r[1], full=r[2]) for r in rad_rows}
ALT = {'人':'亻','水':'氵','心':'忄','手':'扌','言':'讠','金':'钅','食':'饣','刀':'刂','衣':'衤','示':'礻','犬':'犭','火':'火','糸':'纟','阜':'阝','邑':'阝','足':'足','辵':'辶'}
def char_info(c):
    d = hanzi.get(c, {})
    parts = [p for p in re.findall(r'[⺀-鿿]', d.get('decomposition', '')) if p != '？' and not '⿰' <= p <= '⿿']
    e = d.get('etymology') or {}
    return dict(c=c, py=[numbered_to_marked(x) if re.search(r'\d', x) else x for x in d.get('pinyin', [])], en=d.get('definition', ''), rad=d.get('radical', ''), parts=parts, type=e.get('type', ''), hint=e.get('hint', ''), sem=e.get('semantic', ''), pho=e.get('phonetic', ''))
chars, taught = {}, set()
def component_radicals(c):
    out = []
    d = hanzi.get(c)
    if not d: return out
    for p in [d.get('radical')] + re.findall(r'[⺀-鿿]', d.get('decomposition', '')):
        if p and p in rad and p not in out: out.append(p)
    return out
for lv in levels:
    for l in lv['lessons']:
        new = []
        for w in l['words']:
            for c in w:
                chars.setdefault(c, char_info(c))
                for r in component_radicals(c):
                    if r not in taught and r not in new and len(new) < 3: new.append(r)
        taught.update(new)
        if new: l['rad'] = new

def segment_loose(text):
    n = len(text); best = [None] * (n + 1); best[n] = (0, [])
    for i in range(n - 1, -1, -1):
        for L in range(1, min(6, n - i) + 1):
            part = text[i:i+L]
            known = part in vocab or part in NAMES
            if L > 1 and not known and part not in ced: continue
            cost = 1 if known else 3 if L > 1 else 4
            c = best[i+L][0] + cost
            if best[i] is None or c < best[i][0]: best[i] = (c, [part] + best[i+L][1])
    return best[0][1]

# ---- Reading passages (AI, labelled, never tested) and their levels.
passages = []
ppath = os.path.join(ROOT, 'content', 'passages.json')
if os.path.exists(ppath):
    for p in json.load(open(ppath, encoding='utf-8')):
        toks = segment_loose(p['zh'])
        extra = {}
        for t in toks:
            if t in vocab or t in NAMES or t in PUNCT or t.isdigit(): continue
            g = find_gloss(ced, t, None)
            rows = ced.get(t)
            extra[t] = dict(py=' '.join(numbered_to_marked(x) for x in rows[0][0].split()) if rows else '', en=short_gloss(g) if g else '')
            for c in t: chars.setdefault(c, char_info(c))
        ats = sorted(by_word[t] for t in toks if t in by_word)
        need = ats[int(len(ats) * 0.97) - 1] if ats else (1, 0)
        passages.append(dict(title=p['title'], zh=p['zh'], en=p['en'], toks=toks, lvl=need[0], ai=True, extra=extra))
        print('passage', p['title'], 'outside list:', list(extra))
    passages.sort(key=lambda p: p['lvl'])
    print('passages', [(p['title'], p['lvl']) for p in passages])

# ---- The page: real sentences you grow into, easiest first, chosen by hand.
curated = os.path.join(ROOT, 'content', 'page.txt')
bytext = {s['zh']: s for s in raw}
page = []
if os.path.exists(curated):
    for line in open(curated, encoding='utf-8'):
        line = line.strip()
        if line and line in bytext: page.append(bytext[line])
        elif line: print('PAGE missing', line)
for b in range(1, 7):
    band_levels = {lv['n'] for lv in levels if lv['band'] == b}
    pool = [x for x in raw if x['lvl'] in band_levels and 8 <= len(x['zh']) <= 22 and not x.get('exam')]
    random.Random(b).shuffle(pool)
    print('CAND', b, ' | '.join(x['zh'] for x in pool[:45]))

# ---- Sentence-coverage numbers per word, for the character total.
char_freq = collections.Counter(c for s in raw for c in s['zh'] if c in chars)
total_chars = sum(char_freq.values())
for c, inf in chars.items(): inf['share'] = round(char_freq[c] / total_chars, 6)

keep = [s for s in raw if s.get('used') or s.get('exam') or s in page]
used_ids = {s['id'] for s in keep}
# Extra sentences for example use, a few per word.
by_tok = collections.defaultdict(list)
def has_name(s): return any(t in NAMES and t not in vocab for t in s['toks'])
for s in sorted(raw, key=lambda s: (has_name(s), len(s['zh']) < 5, abs(len(s['zh']) - 9))):
    if s.get('exam'): continue
    for t in set(s['toks']):
        if t in vocab and len(by_tok[t]) < 3 and s['at'] <= by_word[t]: by_tok[t].append(s)
for t, ss in by_tok.items():
    for s in ss:
        if s['id'] not in used_ids: used_ids.add(s['id']); keep.append(s)
for w in words:
    w['ex'] = [s['id'] for s in by_tok.get(w['w'], [])]
    w['gl'] = w['gl'][:4]
for g in grammar: g.pop('re'); g.pop('count', None)
out = dict(
    version=1,
    words=words, chars=chars, radicals=list(rad.values()), names=NAMES,
    levels=[dict(n=l['n'], band=l['band'], lessons=l['lessons'], exam=l['exam'], readable=l['readable']) for l in levels],
    grammar=[g for g in grammar if g.get('at')],
    sentences=[dict(id=s['id'], zh=s['zh'], en=s['en'], toks=s['toks'], lvl=s['lvl'], exam=bool(s.get('exam'))) for s in keep],
    passages=passages, page=[s['id'] for s in page], totalSentences=len(raw),
)
def curly(t):
    t = re.sub(r'(^|[\s(])"', lambda m: m[1] + '\u201c', t)
    t = t.replace('"', '\u201d')
    t = re.sub(r"(^|[\s(])'", lambda m: m[1] + '\u2018', t)
    return t.replace("'", '\u2019')
for x in out['sentences'] + out['passages']: x['en'] = curly(x['en'])
for x in out['grammar']:
    for k in ('title', 'short', 'body'): x[k] = curly(x[k])
for x in out['words']:
    x['en'] = curly(x['en']); x['gl'] = [curly(g) for g in x['gl']]
blob = json.dumps(out, ensure_ascii=False, separators=(',', ':')).encode('utf-8')
os.makedirs(os.path.join(ROOT, 'assets'), exist_ok=True)
with gzip.open(os.path.join(ROOT, 'assets', 'curriculum.json.gz'), 'wb', 9) as f: f.write(blob)
print('levels', len(levels), 'chars', len(chars), 'kept sentences', len(keep), 'grammar', len(out['grammar']), 'bytes', len(blob))
# Report for checking.
print('exam sizes', [len(l['exam']) for l in out['levels']])
print('words sample', [(w['w'], w['en']) for w in words[20:70]])
ids = {s['id']: s for s in out['sentences']}
