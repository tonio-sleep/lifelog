import os, re, sys, collections

ROOT = sys.argv[1] if len(sys.argv) > 1 else '/home/claude/work/lib'
PKG_OK = {'path', 'http', 'uuid', 'image', 'flutter', 'cryptography', 'flutter_riverpod', 'file_selector', 'geolocator', 'path_provider', 'intl', 'flutter_secure_storage'}

def strip_code(src):
    """Return (code_only, errors). Strings/comments blanked; ${...} kept as code."""
    out=[]; i=0; n=len(src); errs=[]
    stack=[]  # for interpolation: stack of ('interp', brace_depth) ; strings handled inline
    def scan_string(i, quote, triple, raw):
        # returns new i, and appends to out; handles interpolation recursively
        out.append(' '*(len(quote)))
        while i<n:
            c=src[i]
            if not raw and c=='\\':
                out.append('  '); i+=2; continue
            if src.startswith(quote,i):
                out.append(' '*len(quote)); return i+len(quote)
            if not triple and c=='\n':
                errs.append('newline in string near %d'%i); return i
            if not raw and c=='$' and i+1<n and src[i+1]=='{':
                out.append('  '); i+=2
                depth=1
                while i<n and depth>0:
                    d=src[i]
                    if d=='{': depth+=1; out.append(d); i+=1
                    elif d=='}':
                        depth-=1
                        if depth==0: out.append(' '); i+=1; break
                        out.append(d); i+=1
                    elif d in '\'"':
                        # nested string
                        tq = d*3 if src.startswith(d*3,i) else d
                        i=scan_string(i+len(tq)-len(tq)+ (0), tq, len(tq)==3, False) if False else nested(i)
                    else:
                        out.append(d); i+=1
                continue
            if not raw and c=='$' and i+1<n and (src[i+1].isalpha() or src[i+1]=='_'):
                out.append(' '); i+=1
                while i<n and (src[i].isalnum() or src[i]=='_'):
                    out.append(' '); i+=1
                continue
            out.append(' ' if c!='\n' else '\n'); i+=1
        errs.append('unterminated string'); return i
    def nested(i):
        d=src[i]
        tq = d*3 if src.startswith(d*3,i) else d
        return scan_string(i+len(tq), tq, len(tq)==3, False) if False else scan_str_at(i,tq)
    def scan_str_at(i,tq):
        # i points at opening quote
        return scan_string(i, tq, len(tq)==3, False) if False else _scan(i,tq,False)
    def _scan(i,tq,raw):
        # opening quote at i: scan_string expects i AFTER opening quote
        out.append('')
        return scan_string(i+len(tq), tq, len(tq)==3, raw)
    while i<n:
        c=src[i]
        if src.startswith('//',i):
            j=src.find('\n',i); j=n if j<0 else j
            out.append(' '*(j-i)); i=j; continue
        if src.startswith('/*',i):
            depth=1; j=i+2
            while j<n and depth>0:
                if src.startswith('/*',j): depth+=1; j+=2
                elif src.startswith('*/',j): depth-=1; j+=2
                else: j+=1
            seg=src[i:j]; out.append(re.sub(r'[^\n]',' ',seg)); i=j; continue
        raw=False
        if c=='r' and i+1<n and src[i+1] in '\'"' and (i==0 or not (src[i-1].isalnum() or src[i-1]=='_')):
            raw=True; i+=1; c=src[i]
        if c in '\'"':
            tq = c*3 if src.startswith(c*3,i) else c
            i=_scan(i,tq,raw); continue
        out.append(c); i+=1
    return ''.join(out), errs

def balance(code):
    pairs={')':'(',']':'[','}':'{'}; st=[]; errs=[]
    line=1
    for ch in code:
        if ch=='\n': line+=1
        if ch in '([{': st.append((ch,line))
        elif ch in ')]}':
            if not st or st[-1][0]!=pairs[ch]:
                errs.append('mismatched %s at line %d (open: %s)'%(ch,line,st[-1] if st else None)); return errs
            st.pop()
    if st: errs.append('unclosed %s'%(st[-3:],))
    return errs

files=[]
for d,_,fs in os.walk(ROOT):
    for f in fs:
        if f.endswith('.dart'): files.append(os.path.join(d,f))
files.sort()
codes={}; problems=collections.defaultdict(list)
for f in files:
    src=open(f).read()
    code,errs=strip_code(src)
    codes[f]=(src,code)
    for e in errs: problems[f].append('SCAN: '+e)
    for e in balance(code): problems[f].append('BALANCE: '+e)

# imports / exports
imp_re=re.compile(r"^\s*(import|export)\s+'([^']+)'([^;]*);",re.M)
imports={}; exports={}
for f in files:
    src=codes[f][0]; imports[f]=[]; exports[f]=[]
    for m in imp_re.finditer(src):
        kind,path,rest=m.groups()
        if path.startswith('dart:'): continue
        if path.startswith('package:'):
            pkg=path.split(':')[1].split('/')[0]
            if pkg not in PKG_OK: problems[f].append('IMPORT: unknown package %s'%pkg)
            continue
        target=os.path.normpath(os.path.join(os.path.dirname(f),path))
        if not os.path.exists(target): problems[f].append('IMPORT: missing file %s'%path); continue
        (imports if kind=='import' else exports)[f].append(target)
        if kind=='export': imports[f].append(target)

# top-level declarations
decl_re=re.compile(r'^(?:abstract\s+|sealed\s+|final\s+|base\s+|interface\s+)*(?:class|enum|mixin|extension\s+type)\s+([A-Za-z_]\w*)|^typedef\s+([A-Za-z_]\w*)|^(?:const|final)\s+(?:[\w<>?,\s()]+?\s+)?([A-Za-z_]\w*)\s*=|^(?:[\w<>?,.()]+\s+)+([a-zA-Z_]\w*)\s*(?:<[^>]*>)?\(',re.M)
defs=collections.defaultdict(set)  # name -> files
file_defs={}
for f in files:
    code=codes[f][1]; names=set()
    for line in code.split('\n'):
        if line and not line[0].isspace():
            m=re.match(r'^(?:abstract\s+|sealed\s+|final\s+|base\s+)*(?:class|enum|mixin)\s+(\w+)',line)
            if m: names.add(m.group(1))
            m=re.match(r'^typedef\s+(\w+)',line)
            if m: names.add(m.group(1))
            m=re.match(r'^(?:const|final)\s+(?:[\w<>?,.\s]+?\s+)?(\w+)\s*=',line)
            if m: names.add(m.group(1))
            m=re.match(r'^(?:Future<[^>]*>|Future|void|bool|int|double|String|Widget|Color|IconData|IconAndColor|List<[^>]*>|Map<[^>]*>|Set<[^>]*>|[A-Z]\w*\??|\([^)]*\)\??)\s+(\w+)\s*(?:<[^>]*>)?\(',line)
            if m and not m.group(1).startswith('_'): names.add(m.group(1))
            m=re.match(r'^extension\s+(\w+)',line)
            if m: names.add(m.group(1))
    file_defs[f]=names
    for nme in names:
        if not nme.startswith('_'): defs[nme].add(f)

def reachable(f):
    seen=set(); st=[f]
    # file's own + direct imports + their exports (transitively)
    res={f}
    def add_exports(g):
        for e in exports.get(g,[]):
            if e not in res: res.add(e); add_exports(e)
    for g in imports[f]:
        res.add(g); add_exports(g)
    return res

tok=re.compile(r'(?<![\w.$])([A-Za-z_]\w*)')
for f in files:
    code=codes[f][1]; reach=reachable(f)
    used=set(tok.findall(code))
    for nme in used:
        if nme in defs and nme not in file_defs[f]:
            if not (defs[nme] & reach):
                # could be a local variable shadowing e.g. 'text' - only flag Capitalized or known function names
                if nme[0].isupper() or nme in {'guard','showSnack','confirm','showLifelogSheet','revealAt','formatGap','sourceStyle','moodColor','trackerIcon','trackerColor','momentForDay','showMediaViewer','mediaHeroTag','habitValueLabel','habitPrimaryAction','habitSecondaryAction','showQuickAdd','runQuickAdd','pickAndLogHabit','importMediaForDay','createJournalEntry','openJournalEntry','showTrackerEditor','showTrackerLogDialog','showVisitEditor','showPlaceEditor','showTimelineEventEditor','showManualScrobbleDialog','syncLastfmRecent','dayGlowColors','greetingFor','askMediaDetails','trackerTypeIcon','tabularFigures'}:
                    problems[f].append('NOT-IMPORTED: %s (defined in %s)'%(nme,[os.path.relpath(x,ROOT) for x in defs[nme]]))

# named-arg check for project widgets/functions
def split_params(block):
    parts=[];d=0;cur=''
    for ch in block:
        if ch in '([{': d+=1
        if ch in ')]}' : d-=1
        if ch==',' and d==0: parts.append(cur); cur=''
        else: cur+=ch
    if cur.strip(): parts.append(cur)
    return parts
sigs={}
cons_re=re.compile(r'\bconst\s+(\w+)\(\{|^\s+(\w+)\(\{',re.M)
for f in files:
    code=codes[f][1]
    for m in re.finditer(r'(?:const\s+)?\b([A-Z]\w*)\(\s*\{',code):
        cls=m.group(1)
        # must be a constructor: class declared in this file
        if cls not in file_defs[f]: continue
        i=m.end()-1; depth=0; j=i
        while j<len(code):
            if code[j] in '({[': depth+=1
            elif code[j] in ')}]':
                depth-=1
                if depth==0: break
            j+=1
        block=code[i+1:j]
        names=set()
        for p in split_params(block):
            p=p.strip()
            mm=re.search(r'this\.(\w+)',p) or re.search(r'super\.(\w+)',p)
            if mm: names.add(mm.group(1)); continue
            mm=re.search(r'(\w+)\s*(?:=.*)?$',p)
            if mm: names.add(mm.group(1))
        sigs.setdefault(cls,set()).update(names)
    # top-level functions with named params
    for m in re.finditer(r'^(?:Future<[^>]*>|Future|void|bool|Widget|String|[A-Z]\w*\??|\([^)]*\)\??)\s+(\w+)\s*(?:<[^>]*>)?\([^{;]*?\{',code,re.M):
        pass
for f in files:
    code=codes[f][1]
    for cls,names in sigs.items():
        for m in re.finditer(r'(?<![\w.])%s\('%re.escape(cls),code):
            if code[max(0,m.start()-6):m.start()].strip().endswith('class'): continue
            i=m.end()-1; depth=0; j=i
            while j<len(code):
                if code[j] in '({[': depth+=1
                elif code[j] in ')}]':
                    depth-=1
                    if depth==0: break
                j+=1
            args=code[i+1:j]
            for p in split_params(args):
                mm=re.match(r'\s*([a-z]\w*)\s*:',p)
                if mm and mm.group(1) not in names and f in [ff for ff in files] and cls not in file_defs.get(f,()) :
                    ln=code[:m.start()].count('\n')+1
                    problems[f].append('ARG: %s(%s:) not a declared param (line %d); declared=%s'%(cls,mm.group(1),ln,sorted(names)))

bad=0
for f in files:
    if problems[f]:
        bad+=len(problems[f])
        print('==',os.path.relpath(f,ROOT))
        for p in sorted(set(problems[f])): print('  ',p)
print('\nfiles:',len(files),'problems:',bad)

# ---- unused relative imports (analyzer warning)
print('\nUNUSED IMPORTS:')
def exported_names(g,seen=None):
    seen=seen or set()
    if g in seen: return set()
    seen.add(g)
    names=set(n for n in file_defs.get(g,()) if not n.startswith('_'))
    for e in exports.get(g,[]): names|=exported_names(e,seen)
    return names
cnt=0
for f in files:
    code=codes[f][1]; used=set(tok.findall(code))|set(re.findall(r'\.(\w+)',code))
    src=codes[f][0]
    for m in imp_re.finditer(src):
        kind,path,rest=m.groups()
        if kind!='import' or path.startswith(('dart:','package:')): continue
        target=os.path.normpath(os.path.join(os.path.dirname(f),path))
        names=exported_names(target)
        if names and not (names & used):
            print('  ',os.path.relpath(f,ROOT),'->',path); cnt+=1
print('unused:',cnt)
