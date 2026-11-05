"""metasplit.py FILE..: in a module that mixes metaprograms and theorems, wrap each run of metaprogram declarations
(def, partial def, abbrev, initialize, register_option, syntax, elab/macro rules, ...) in `public meta section` ..
`end`, leaving theorems in the public section; adds `public meta import Lean` after `public import Lean`."""
import re,sys
META=re.compile(r'(partial def|def|abbrev|initialize|builtin_initialize|register_option|register_simp_attr|syntax|elab_rules|macro_rules|macro|elab|declare_syntax_cat|structure|inductive|instance|unsafe def|opaque)\b')
OBJ=re.compile(r'(theorem|lemma)\b')
MODS=re.compile(r'((@\[[^\]]*\]\s*)|private |protected |noncomputable |scoped |local )*')
BARRIER=re.compile(r'(namespace|end|section|open|set_option|variable|universe|attribute|#)\b')
for p in sys.argv[1:]:
    ls=open(p).read().split('\n')
    # header end: the `@[expose] public section` line
    h=next(i for i,l in enumerate(ls) if l.startswith('@[expose] public section'))
    out=ls[:h+1]; state='obj'; pend=[]  # pend: docstring/attribute/open-in prefix lines
    i=h+1; indoc=False
    def flush_to(kind):
        global state
        if kind=='meta' and state!='meta': out.append('public meta section'); state='meta'
        if kind in ('obj','barrier') and state=='meta': out.append('end'); state='obj'
    while i<len(ls):
        l=ls[i]
        if l.startswith('/--'):
            # docstring: collect until -/
            j=i
            while '-/' not in ls[j]: j+=1
            pend+=ls[i:j+1]; i=j+1; continue
        if l.startswith('/-') and not l.startswith('/--'):
            j=i
            while '-/' not in ls[j]: j+=1
            (pend if pend else out).extend(ls[i:j+1]); i=j+1; continue
        if l.startswith('--') or l.strip()=='' or l[:1] in ' \t)}]|' or re.match(r'(where|termination_by|decreasing_by|deriving|with)\b',l):
            (pend if pend else out).append(l); i+=1; continue
        if re.match(r'(open|set_option) .* in\s*$',l) or re.match(r'@\[[^\]]*\]\s*$',l):
            pend.append(l); i+=1; continue
        rest=MODS.sub('',l,count=1)
        kind='meta' if META.match(rest) else 'obj' if OBJ.match(rest) else 'barrier' if BARRIER.match(rest) else 'obj'
        flush_to(kind); out+=pend; pend=[]; out.append(l); i+=1
    if state=='meta':
        # close before the file's trailing `end NS` lines if any
        k=len(out)
        while k>0 and (out[k-1].strip()=='' or out[k-1].startswith('end ')): k-=1
        out[k:k]=['end']
    out+=pend
    t='\n'.join(out)
    if 'public meta import Lean' not in t: t=t.replace('public import Lean\n','public import Lean\npublic meta import Lean\n',1)
    open(p,'w').write(t)
