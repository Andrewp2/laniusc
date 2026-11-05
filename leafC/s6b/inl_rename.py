import re,sys
for path in ['layout.lani','homes.lani','stmts.lani']:
    s=open(path).read()
    out=[];pos=0
    for m in re.finditer(r'// extract: inline\nfn (\w+)\(([^)]*)\)([^\n]*)\n(.*?\n)\}\n', s, re.S):
        name, params, rest, body = m.groups()
        pre=''.join(w[0] for w in name.split('_'))+'_'
        pnames=[p.split(':')[0].strip() for p in params.split(',') if p.strip()]
        binders=set(re.findall(r'(?:Some|Cons)\((\w+)(?:, (\w+))?\) ->', body)) 
        bn=set()
        for a,b in binders:
            bn.add(a); 
            if b: bn.add(b)
        names=set(pnames)|bn
        names={n for n in names if not n.startswith(pre)}
        def ren(text, sig):
            for n in sorted(names, key=len, reverse=True):
                if sig: text=re.sub(r'(?<![.\w])'+n+r'\b', pre+n, text)
                else: text=re.sub(r'(?<![.\w])'+n+r'\b(?!\s*:(?!:))', pre+n, text)
            return text
        new=f'// extract: inline\nfn {name}({ren(params,True)}){rest}\n{ren(body,False)}}}\n'
        out.append(s[pos:m.start()]); out.append(new); pos=m.end()
        print(path, name, pre, sorted(names))
    out.append(s[pos:])
    open(path,'w').write(''.join(out))
