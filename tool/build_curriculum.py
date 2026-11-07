#!/usr/bin/env python3
"""Turns the downloaded data in data_src/ and the hand-written content/ into
assets/curriculum.json.gz, in Traditional characters as written in Taiwan. Run
with -I, as data_src holds downloads, from a venv with tool/requirements.txt."""
import bz2, collections, gzip, hashlib, json, os, random, re, sys, tarfile, csv, unicodedata
import opencc

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, 'data_src')
LEVEL_WORDS, LESSON_WORDS = 80, 8
MAX_BAND = 6
NAMES = {'湯姆': 'Tom', '瑪麗': 'Mary', '瑪莉': 'Mary', '約翰': 'John', '傑克': 'Jack', '邁克': 'Mike', '麥克': 'Mike', '比爾': 'Bill', '愛麗絲': 'Alice', '肯': 'Ken', '露西': 'Lucy', '鮑勃': 'Bob', '鮑伯': 'Bob', '吉姆': 'Jim', '簡': 'Jane', '戴安娜':'Diana', '東京':'Tokyo', '日本':'Japan', '美國':'America','英國':'Britain','法國':'France','北京':'Beijing','上海':'Shanghai','中國':'China','臺灣':'Taiwan','臺北':'Taipei','波士頓':'Boston','紐約':'New York','倫敦':'London','巴黎':'Paris','德國':'Germany','法語':'French','英語':'English','日語':'Japanese','中文':'Chinese','漢語':'Chinese'}
PUNCT = set('。！？，、：；“”‘’（）《》〈〉「」『』…—～．,.!?;:"\'()- 　·・')
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
    """Entries by Traditional form, and by Simplified for what the first misses."""
    out, by_simp = collections.defaultdict(list), collections.defaultdict(list)
    with gzip.open(os.path.join(SRC, 'cedict_1_0_ts_utf-8_mdbg.txt.gz'), 'rt', encoding='utf-8') as f:
        for line in f:
            if line.startswith('#'): continue
            m = re.match(r'^(\S+) (\S+) \[([^\]]+)\] /(.+)/$', line.strip())
            if m:
                out[m[1]].append((m[3], m[4].split('/')))
                by_simp[m[2]].append((m[1], m[3], m[4].split('/')))
    return out, by_simp

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

ced, ced_simp = load_cedict()
# ---- HSK words, under the file's Traditional form. Each form is a word of its
# own, so 干 becomes 乾 and 幹, in the HSK band each belongs to.
# Where Taiwan's standard form isn't the file's first choice.
TW_FORM = {'于':'於','尝':'嘗','占':'佔','台':'臺','上台':'上臺','上周':'上週','世界杯':'世界盃','鲜艳':'鮮豔','借鉴':'借鑑','咨询':'諮詢','面向':'面向','小伙子':'小夥子','大伙儿':'大夥兒','伙伴':'夥伴','回复':'回覆','抽烟':'抽菸','吸烟':'吸菸'}
# The file numbers homographs: 面1 is 面, face, and 面2 is 麵, noodles.
def first_form(s):
    return re.sub(r'[（(].*?[)）]|\d$', '', s.strip()).split('｜')[0].split('|')[0].strip()
def all_forms(s):
    return [x.strip() for x in re.sub(r'[（(].*?[)）]|\d$', '', s.strip()).replace('｜', '|').split('|') if x.strip()]
seen, words, renamed, spellings = {}, [], {}, {}
with open(os.path.join(SRC, 'hsk30.csv'), encoding='utf-8') as f:
    for r in csv.DictReader(f):
        if r['Level'] == '7-9' or int(r['Level']) > MAX_BAND: continue
        simp = first_form(r['Simplified'])
        if not simp or not re.fullmatch(r'[一-鿿]+', simp): continue
        # Only this row's first spelling: 爸爸|爸 is two lengths of one word.
        # A numbered row's Traditional column just repeats the number; CC-CEDICT's is right.
        numbered = re.search(r'\d$', r['Simplified'].strip())
        forms = [r['CEDICT'].split('|')[0]] if numbered else [x for x in all_forms(r['Traditional']) if len(x) == len(simp)]
        w = TW_FORM.get(simp) or forms[0]
        cm = re.search(r'\[([^\]]+)\]', r['CEDICT'] or '')
        num = cm[1] if cm else None
        py = ' '.join(numbered_to_marked(s) for s in num.split()) if num else r['Pinyin']
        gloss = []
        for form in [w] + [x for x in forms if x != w]:
            gloss += [g for g in find_gloss(ced, form, num) if g not in gloss]
        if not gloss:
            rows = ced_simp.get(simp, [])
            gloss = find_gloss({simp: [x[1:] for x in rows if x[0] in forms or not forms]}, simp, None) or find_gloss({simp: [x[1:] for x in rows]}, simp, None)
        if not gloss: continue
        renamed.setdefault(simp, w)
        spellings.setdefault(w, set()).update(forms + [simp])
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
taiwan = json.load(open(os.path.join(ROOT, 'content', 'taiwan_words.json'), encoding='utf-8'))
for w in taiwan:
    if w in seen: seen[w]['tw'] = taiwan[w]
    else: print('TAIWAN NOTE for a word not in the list', w)
for e in words:
    e['gl'] = [g for g in e['gl'] if 'Note:' not in g and 'Taiwan' not in g] or e['gl']
    e['en'] = overrides.get(e['w']) or short_gloss(e['gl'])
    e['gl'] = [re.sub(r' \(Taiwan pr\. *\)', '', g) for g in e['gl']]
vocab = set(seen)
renamed = {a: b for a, b in renamed.items() if a != b}
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

# ---- Sentences in one spelling. Tatoeba has them in both scripts: a Simplified
# one with a human Traditional twin takes the twin's characters, and the rest go
# through OpenCC's phrase tables, checked with content/trad_fixes.json.
to_tw, to_simp, to_tw_std = opencc.OpenCC('s2tw'), opencc.OpenCC('t2s'), opencc.OpenCC('t2tw')
VARIANTS = {'着':'著','箇':'個','裏':'裡','爲':'為','説':'說','衆':'眾','羣':'群','眞':'真','麪':'麵','絶':'絕','脱':'脫','閲':'閱','衞':'衛','户':'戶','温':'溫','溼':'濕','妳':'你','牠':'它','台':'臺','颳':'刮','銹':'鏽','鷄':'雞','綫':'線','啓':'啟','擡':'抬','祕':'秘','牀':'床','喫':'吃','佈':'布'}
SPELL = {'甚麼':'什麼','計畫':'計劃','瞭解':'了解','臺風':'颱風','週圍':'周圍','週到':'周到'}
for w, forms in spellings.items():
    simp_rows = [s for s in forms if len(s) > 1]
    for s in simp_rows:
        for form in {to_tw.convert(s)} | {x[0] for x in ced_simp.get(s, []) if x[0] != w and toneless(''.join(numbered_to_marked(q) for q in x[1].split())) == toneless(seen[w]['py'])} | set(simp_rows):
            if form != w and len(form) == len(w) and form not in vocab and re.fullmatch(r'[一-鿿]+', form) and to_simp.convert(form) == to_simp.convert(w): SPELL[form] = w
SPELL = {a: b for a, b in SPELL.items() if a != b and a not in vocab}
spell_re = re.compile('|'.join(sorted(map(re.escape, SPELL), key=len, reverse=True)))
week_re = re.compile(r'(?<=[一二三五六七八九十兩幾每上下這本個])周(?![圍到全])')
def standard(text):
    """[text] in Traditional, spelled as the word list spells it."""
    text = to_tw_std.convert(text)
    text = ''.join(VARIANTS.get(c, c) for c in text)
    text = spell_re.sub(lambda m: SPELL[m[0]], text)
    return week_re.sub('週', text)

unreachable = [w for w in vocab if standard(w) != w]
if unreachable: print('WORDS NO SENTENCE CAN REACH', [(w, standard(w)) for w in unreachable])

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

# Fixes after reading what OpenCC made of the sentences that came through it:
# an id's corrected text, or nothing to drop it.
fixes = json.load(open(os.path.join(ROOT, 'content', 'trad_fixes.json'), encoding='utf-8'))
twins = {}
for sid, (zh, owner) in cmn.items():
    if owner in native and to_simp.convert(zh) != zh: twins.setdefault(to_simp.convert(zh), zh)
raw, stats = [], collections.Counter()
seen_zh = set()
for sid, (zh, owner) in cmn.items():
    stats['all'] += 1
    if owner not in native: stats['not native'] += 1; continue
    human = to_simp.convert(zh) != zh or zh in twins
    zh = fixes[sid] if sid in fixes else standard(twins[zh] if zh in twins else zh if to_simp.convert(zh) != zh else to_tw.convert(zh))
    if not zh: stats['dropped by hand'] += 1; continue
    if sid not in links: stats['no english'] += 1; continue
    if re.search(r'[A-Za-z]', zh) or re.search(r'([\u4e00-\u9fff])\1\1|的的|了了|是是', zh) or not 3 <= len(zh) <= 28 or zh in seen_zh: stats['form'] += 1; continue
    ens = [eng[b] for b in links[sid] if b in eng and len(eng[b].split()) <= 16]
    if not ens: stats['english too long'] += 1; continue
    toks = segment(zh)
    if toks is None: stats['outside list'] += 1; continue
    seen_zh.add(zh)
    raw.append(dict(id=sid, zh=zh, en=min(ens, key=len), toks=toks, machine=not human))
print('sentences', len(raw), dict(stats))

# ---- Lessons, as in content/lessons.json: lesson ids and what they teach stay
# put however the sentence library changes.
freq = collections.Counter(t for s in raw for t in s['toks'] if t in vocab)
hanzi = {}
with open(os.path.join(SRC, 'dictionary.txt'), encoding='utf-8') as f:
    for line in f:
        d = json.loads(line); hanzi[d['character']] = d
words.sort(key=lambda e: (e['band'], -freq[e['w']], e['w']))
frozen = json.load(open(os.path.join(ROOT, 'content', 'lessons.json'), encoding='utf-8'))
levels, by_word = [], {}
for i, lv in enumerate(frozen):
    levels.append(dict(n=i + 1, band=lv['band'], lessons=[dict(words=w) for w in lv['lessons']]))
    for li, ws in enumerate(lv['lessons']):
        for w in ws:
            if w in by_word: sys.exit(f'{w} is in two lessons')
            if seen[w]['band'] != lv['band']: sys.exit(f'{w} is out of band in level {i + 1}')
            by_word[w] = (i + 1, li)
if set(by_word) != vocab: sys.exit(f'lessons.json and the word list differ: {sorted(set(by_word) ^ vocab)}')

# ---- AI-written sentences for beginner words no real sentence covers. They come
# after the frequency counts, and are never in an exam or a grammar note.
ai_path = os.path.join(ROOT, 'content', 'ai_sentences.tsv')
for line in open(ai_path, encoding='utf-8'):
    zh, en = line.rstrip('\n').split('\t')
    toks = segment(standard(zh))
    if toks is None: print('AI SENTENCE outside the list', zh); continue
    if standard(zh) in seen_zh: continue
    seen_zh.add(standard(zh))
    raw.append(dict(id='ai' + hashlib.md5(zh.encode()).hexdigest()[:10], zh=standard(zh), en=en, toks=toks, machine=True, ai=True))

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
for s in raw:
    if not s.get('ai'): per[s['lvl']].append(s)
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
    hits = [s for s in raw if not s.get('exam') and not s.get('ai') and r.search(s['joined'])]
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
        fresh = [s for s in raw if s['at'] == (lv['n'], li) and not s.get('exam')]
        fresh.sort(key=lambda s: (bool(s.get('ai')), s.get('used', False), s['machine'], len(s['zh']) < 5, abs(len(s['zh']) - 10)))
        l['sent'] = [s['id'] for s in fresh[:4]]
        for s in fresh[:4]: s['used'] = True

# ---- Radicals, which explain a character on its word's card.
rad_rows = json.load(open(os.path.join(ROOT, 'content', 'radicals.json'), encoding='utf-8'))
rad = {r[0]: dict(r=r[0], en=r[1], full=r[2]) for r in rad_rows}
# Make Me a Hanzi's Traditional entries often borrow the Simplified one's text,
# so its meaning is checked against CC-CEDICT and its words spelled in Traditional.
# Characters that are real parts of a Traditional form (亲 in 新, 开 in 開) stay.
TRAD_TEXT = str.maketrans({'电':'電','飞':'飛','来':'來','阴':'陰','云':'雲','术':'術','条':'條','务':'務','吴':'吳','黄':'黃','贝':'貝','鸟':'鳥','麦':'麥','张':'張','尔':'爾','众':'眾','杀':'殺','乡':'鄉','启':'啟','刍':'芻','内':'內','竞':'競','苋':'莧','册':'冊','买':'買','户':'戶','巩':'鞏'})
char_fixes = json.load(open(os.path.join(ROOT, 'content', 'char_fixes.json'), encoding='utf-8'))
def char_meaning(c, en):
    if to_simp.convert(c) == c or c not in ced: return en
    senses = ' '.join(g.lower() for _, gl in ced[c] for g in gl)
    known = set(re.findall(r'[a-z]{3,}', senses))
    kept = [part.strip() for part in re.split(r';', en) if set(re.findall(r'[a-z]{3,}', part.lower())) & known]
    if kept: return '; '.join(kept)
    return short_gloss(find_gloss(ced, c, None) or [en])
def char_info(c):
    d = hanzi.get(c, {})
    parts = [p for p in re.findall(r'[⺀-鿿]', d.get('decomposition', '')) if p != '？' and not '⿰' <= p <= '⿿']
    e = d.get('etymology') or {}
    info = dict(c=c, py=[numbered_to_marked(x) if re.search(r'\d', x) else x for x in d.get('pinyin', [])], en=char_meaning(c, d.get('definition', '')), rad=d.get('radical', '').translate(TRAD_TEXT), parts=parts, type=e.get('type', ''), hint=e.get('hint', '').translate(TRAD_TEXT), sem=e.get('semantic', '').translate(TRAD_TEXT), pho=e.get('phonetic', '').translate(TRAD_TEXT))
    return {**info, **char_fixes.get(c, {})}
chars = {}
for lv in levels:
    for l in lv['lessons']:
        for w in l['words']:
            for c in w:
                chars.setdefault(c, char_info(c))

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
    pool = [x for x in raw if x['lvl'] in band_levels and 8 <= len(x['zh']) <= 22 and not x.get('exam') and not x.get('ai')]
    random.Random(b).shuffle(pool)
    print('CAND', b, ' | '.join(x['zh'] for x in pool[:45]))

# ---- Sentence-coverage numbers per word, for the character total.
char_freq = collections.Counter(c for s in raw if not s.get('ai') for c in s['zh'] if c in chars)
total_chars = sum(char_freq.values())
for c, inf in chars.items(): inf['share'] = round(char_freq[c] / total_chars, 6)
# And each word's share of the running words, for how much of real text you can read.
total_toks = sum(freq.values())
for w in words: w['share'] = round(freq[w['w']] / total_toks, 6)

keep = [s for s in raw if s.get('used') or s.get('exam') or s in page]
used_ids = {s['id'] for s in keep}
# Extra sentences for example use, a few per word.
by_tok = collections.defaultdict(list)
def has_name(s): return any(t in NAMES and t not in vocab for t in s['toks'])
for s in sorted(raw, key=lambda s: (bool(s.get('ai')), has_name(s), s['machine'], len(s['zh']) < 5, abs(len(s['zh']) - 9))):
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
    version=2,
    words=words, chars=chars, radicals=list(rad.values()), names=NAMES, renamed=renamed,
    levels=[dict(n=l['n'], band=l['band'], lessons=l['lessons'], exam=l['exam']) for l in levels],
    grammar=[g for g in grammar if g.get('at')],
    sentences=[dict(id=s['id'], zh=s['zh'], en=s['en'], toks=s['toks'], lvl=s['lvl'], exam=bool(s.get('exam')), **({'ai': True} if s.get('ai') else {})) for s in keep],
    passages=passages, page=[s['id'] for s in page],
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

# ---- The sentence gap, and what came through OpenCC for checking.
def gap(label, have):
    print(label, {b: sum(1 for w in words if w['band'] == b and not have(w)) for b in range(1, 7)})
in_any = {t for s in raw for t in s['toks']}
gap('no library sentence', lambda w: w['w'] in in_any)
gap('no example on the card', lambda w: w['ex'])
print('lessons with no reading step', {b: (sum(1 for l in out['levels'] if l['band'] == b for x in l['lessons'] if not x['sent']), sum(len(l['lessons']) for l in out['levels'] if l['band'] == b)) for b in range(1, 7)})
print('kept through OpenCC', sum(1 for s in keep if s['machine'] and not s.get('ai')), 'AI', sum(1 for s in keep if s.get('ai')), 'of', len(keep))
print('AI sentences on no card or lesson', [s['zh'] for s in raw if s.get('ai') and s not in keep])
with open(os.environ.get('YUE_REVIEW', os.devnull), 'w', encoding='utf-8') as f:
    for s in keep:
        if s['machine']: f.write(f"{s['id']}\t{s['zh']}\t{s['en']}\n")
def leftover(x):
    return collections.Counter(c for c in json.dumps(x, ensure_ascii=False) if '一' <= c <= '鿿' and to_tw.convert(c) != c).most_common(60)
for k in out:
    if k != 'renamed': print('still convertible in', k, leftover(out[k]))
