"""The verified compiler's compileSource, Lean's (runAll) against laniusc's
native build of it (self_host.py's laniusc_driver), on each program: a trap
in the native build where Lean compiles or rejects is a usize overflow (or
other trap) in the front end's or compiler's Lanius source.

    python3 -I formal/tools/native_front.py DRIVER FILE.lani...

Run from the repository root. DRIVER is self_host.py's WORKDIR/laniusc_driver;
VBIN names the directory of runAll and srcDump (formal/.lake/build/bin).
A program that imports nothing is compiled alone, in about a second; one that
imports takes the fuzz programs' stdlib modules too (about 4 s), and a whole
fuzz program runs the native build past its 3 GB cap.
"""
import sys, os, shutil, subprocess, resource, time
sys.path.insert(0, 'formal/tools')
import fuzz_oracle as f, stdlib_oracle as so, run_cache, self_host as sh
B = os.environ.get('VBIN', 'formal/.lake/build/bin'); so.RUN_ALL = run_cache.RUN_ALL = B + '/runAll'; so.SRC_DUMP = B + '/srcDump'
driver = sys.argv[1]
w = os.path.abspath('target/claude-work/native_front'); shutil.rmtree(w, ignore_errors=True); os.makedirs(w)
v = f.Verified(type('A', (), {})(), w)
paths = sys.argv[2:]
texts = [open(p).read() for p in paths]
outs = v.compile(texts, 'n')
bases = [[os.path.join(w, f'n{k}')] + (v.deps if 'import ' in texts[k] else []) for k in range(len(texts))]
manifest = os.path.join(w, 'lean.txt')
open(manifest, 'w').write(''.join(f'compile t{k} {" ".join(b)}\n' for k, b in enumerate(bases)
                                  if os.path.exists(b[0] + '.prods') and os.path.getsize(b[0] + '.prods')))
lean = subprocess.run([so.RUN_ALL, manifest], capture_output=True, text=True, timeout=240)
status = dict(l.split(' ', 1) for l in lean.stdout.split('\n') if ' ' in l)
room = 1 << 22
def lim():
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
    resource.setrlimit(resource.RLIMIT_STACK, (4 << 30, 4 << 30))
for k, p in enumerate(paths):
    name = os.path.basename(p)
    if f't{k}' not in status:
        print(f'{name}: no tree ({outs[k][0]})'); continue
    want = sh.expected_words(status[f't{k}'])
    words = sh.layout(bases[k])
    t0 = time.time()
    data = b''.join((x & 0xffffffff).to_bytes(4, 'little') for x in [len(words), room] + words)
    try:
        run = subprocess.run(['systemd-run', '--user', '--scope', '-q', '-p', 'MemoryHigh=3G', '-p', 'MemorySwapMax=infinity', driver], input=data, capture_output=True, timeout=60, preexec_fn=lim)
        got = sh.decode(run.stdout) if run.returncode == 0 else f'exit {run.returncode} {run.stderr[-200:]!r}'
    except subprocess.TimeoutExpired:
        got = 'timeout'
    lw = 'rejects' if want is None else f'{len(want)} words'
    nw = got if not isinstance(got, list) else f'{len(got)} words'
    same = (got == want) or (got is None and want is None)
    print(flush=True, end='')
    print(f'{name}: {time.time() - t0:.1f} s: Lean {lw}; native {"rejects" if got is None else nw}{"" if same else "   <-- DIFFERS"}')
