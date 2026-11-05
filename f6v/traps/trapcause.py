import re, sys
D = '/home/andrew-peterson/code/laniusc-wt/rfront/stdlib/core/'
def w32(x): x &= 0xffffffff; return x - (1 << 32) if x >> 31 else x
def u32(x): return x & 0xffffffff
def rem(a, b):  # truncated
    q = abs(a) // abs(b); q = q if (a >= 0) == (b >= 0) else -q
    return a - b * q
def chunkfn(src, name):
    m = re.search(r'fn %s\(index: i32\) -> \[u8\] \{' % name, src)
    body = src[m.end():]
    toks = re.findall(r'if \(index < (\d+)\)|(else)|string_data_ptr\(text\), (\d+)\)|(\{)|(\})', body)
    pos = [0]
    def node():
        # parse a block's content until matching '}' : either if/else or a return
        t = toks[pos[0]]
        if t[0]:
            n = int(t[0]); pos[0] += 1
            assert toks[pos[0]][3]; pos[0] += 1
            a = node(); assert toks[pos[0]][4]; pos[0] += 1
            assert toks[pos[0]][1]; pos[0] += 1
            assert toks[pos[0]][3]; pos[0] += 1
            b = node(); assert toks[pos[0]][4]; pos[0] += 1
            return ('if', n, a, b)
        assert t[2], t; pos[0] += 1
        return ('len', int(t[2]))
    tree = node()
    def length(i):
        t = tree
        while t[0] == 'if': t = t[2] if i < t[1] else t[3]
        return t[1]
    return length
def hex_(length, start, width, what):
    idx = 0
    while idx < width:
        k = w32(start + idx)
        if not (0 <= k < length):
            return 'bounds: %s[%d] (start %d + %d), length %d' % (what, k, start, idx, length)
        idx += 1
    return None
srcs = {m: open(D + 'unicode_%s_data.lani' % m).read() for m in ('case', 'fold', 'turkic', 'properties')}
N = {'case': (133, 30), 'fold': (160, 25), 'turkic': (160, 25)}
for line in open(sys.argv[1]):
    if not line.startswith('TRAPCALL'): continue
    label = line.split()[1]; args = [int(x) for x in re.search(r'\[([-0-9, ]*)\]', line).group(1).split(',')]
    mod = label.split('unicode_')[1].split('_data')[0]
    if mod in N:
        index, offset, width = args; n, w = N[mod]
        length = chunkfn(srcs[mod], 'chunk')(index)
        start = w32(w32(rem(index, n) * w) + offset)
        cause = hex_(length, start, width, 'chunk(%d)' % index)
    else:
        value = u32(args[0]); block = w32(value >> 7)
        cause = hex_(chunkfn(srcs[mod], 'first')(block), w32(rem(block, 1333) * 3), 3, 'first(%d)' % block)
        if cause is None: cause = 'passes first (not modelled further)'
    print(label, args, '->', cause, '| native', line.split()[-3], 'laniusc', line.split()[-1])
