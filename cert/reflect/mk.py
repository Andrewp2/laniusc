import sys, json, os
sys.path.insert(0, '/home/andrew-peterson/code/laniusc-wt/cert/formal/cert')
import gen, certlib
src = '/home/andrew-peterson/code/laniusc/target/claude-work/cert/lean/distinct.jsonl'
start, n, out = int(sys.argv[1]), int(sys.argv[2]), sys.argv[3]
obls = [json.loads(l) for l in open(src)][start:start + n]
tmp = out + '.cert'
lines = ['import Lanius.Cert.Shallow', 'set_option maxRecDepth 100000', 'set_option profiler true',
         'namespace ReflectBench', 'open Lanius.Cert']
for i, o in enumerate(obls):
    c = certlib.Cert(); gen.signature(c); ar = gen.Arith(c)
    atoms = set()
    hyps = [(gen.term(ar, a, atoms), gen.term(ar, b, atoms)) for a, b in o['hyps']]
    l = gen.term(ar, o['goal'][0], atoms); r = gen.term(ar, o['goal'][1], atoms)
    c.theorem('t', max(atoms) + 1 if atoms else 0, [ar.le(a, b) for a, b in hyps], ar.le(l, r), ar.obligation(hyps, l, r))
    c.write(tmp)
    w = list(certlib.read(tmp))
    lines.append(f'def w{i} : List Int := [{", ".join(map(str, w))}]')
    lines.append(f'theorem c{i} : check {len(w) + 1} w{i} = 0 := by decide +kernel')
open(out, 'w').write('\n'.join(lines) + '\nend ReflectBench\n')
print(out, n)
