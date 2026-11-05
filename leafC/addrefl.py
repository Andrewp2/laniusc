"""Add `.ref` arms next to `.str` arms of SrcType matches in Lean files (F5 S1). argv: files"""
import re, sys
for path in sys.argv[1:]:
    lines = open(path).read().split('\n')
    out = []; n = 0
    for i, line in enumerate(lines):
        m = re.match(r'^(\s*)\| \.str((?:,[^=]*)?) => (.*)$', line)
        nxt = lines[i + 1] if i + 1 < len(lines) else ''
        cont = len(nxt) - len(nxt.lstrip()) > len(m.group(1)) if m else False
        if m and cont:
            out.append(line); print('MULTILINE', path, i + 1); continue
        if m and ' | ' not in line.split('=>')[0][len(m.group(1))+2:]:
            out.append(line)
            out.append(line.replace('| .str', '| .ref _', 1)); n += 1
            continue
        if re.search(r'\| \.str =>', line) and re.search(r'\|.*\| \.str =>', line):
            line = line.replace('| .str =>', '| .str | .ref _ =>'); n += 1
        elif re.search(r'(^|\s)\| str\b( [a-z_]+)? =>', line) or re.search(r'\| str =>', line):
            line = re.sub(r'\| str =>', '| str | ref =>', line); n += 1
        out.append(line)
    if n:
        open(path, 'w').write('\n'.join(out)); print(n, path)
