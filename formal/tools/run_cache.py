"""Content-addressed caches for the difftests, under target/claude-work/cache.

A cached value is stored under a hash of everything it depends on, so it is
reused across runs and workdirs and never goes stale: laniusc's parse of a
file depends only on the file's bytes and laniusc's front end
(parser_digest), a laniusc build on the source, the binary and the stdlib.
Failures are never stored.
"""

import hashlib
import json
import os
import threading

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CACHE = os.path.join(ROOT, 'target/claude-work/cache')


class lean_lock:
    """Held while Lean builds or runs: this worktree's lock (no two builds of
    one checkout at once) and one of six machine-wide slots in the common git
    directory. Every Lean scope runs in work.slice (SLICE), and lake runs lean
    through target/claude-work/leanroot, whose bin/lean waits in
    target/claude-work/bin/memwait before each process starts.
    With LEAN_LOCK_HELD=1 the caller already holds them
    (`target/claude-work/bin/leanslot gate.py`), so a whole gate run waits
    once rather than at every step."""

    def __enter__(self):
        import fcntl
        import subprocess
        import time
        self.held = []
        if os.environ.get('LEAN_LOCK_HELD') == '1':
            return self
        os.environ.setdefault('LAKE_OVERRIDE_LEAN', '1')
        os.environ.setdefault('LEAN_SYSROOT', os.path.join(ROOT, 'target/claude-work/leanroot'))
        def git_dir(flag):
            out = subprocess.run(['git', 'rev-parse', flag], cwd=ROOT, capture_output=True, text=True).stdout.strip()
            return os.path.join(ROOT, out or '.git')
        own = open(os.path.join(git_dir('--git-dir'), 'lean-wt.lock'), 'a')
        fcntl.flock(own, fcntl.LOCK_EX)
        self.held.append(own)
        common = git_dir('--git-common-dir')
        while True:
            for i, name in enumerate(('lean.lock', 'lean.lock.2', 'lean.lock.3', 'lean.lock.4', 'lean.lock.5', 'lean.lock.6')):
                f = open(os.path.join(common, name), 'a')
                try:
                    fcntl.flock(f, fcntl.LOCK_EX | fcntl.LOCK_NB)
                except BlockingIOError:
                    f.close()
                    continue
                self.held.append(f)
                return self
            time.sleep(3)

    def __exit__(self, *exc):
        for f in reversed(self.held):
            f.close()


SLICE = '--slice=work.slice'


def lake_current(target, env):
    """Whether lake's target is built and current (`lake build --no-build`,
    which builds nothing), so that a caller need not wait for a Lean slot
    only to find the target up to date."""
    import subprocess
    return subprocess.run(['lake', 'build', '--no-build', target], cwd=FORMAL, env=env,
                          capture_output=True).returncode == 0


def available_gb():
    with open('/proc/meminfo') as f:
        for line in f:
            if line.startswith('MemAvailable:'):
                return int(line.split()[1]) // 1048576
    return 0


_digests = {}


def file_digest(path):
    """The sha256 of a file's bytes (memoised by path, mtime and size)."""
    st = os.stat(path)
    k = (os.path.abspath(path), st.st_mtime_ns, st.st_size)
    if k not in _digests:
        h = hashlib.sha256()
        with open(path, 'rb') as f:
            for block in iter(lambda: f.read(1 << 20), b''):
                h.update(block)
        _digests[k] = h.hexdigest()
    return _digests[k]


def tree_digest(top):
    """The sha256 of every file below a directory (but __pycache__), by relative path and bytes."""
    h = hashlib.sha256()
    for d, dirs, files in sorted(os.walk(top)):
        dirs[:] = sorted(x for x in dirs if x != '__pycache__')
        for name in sorted(files):
            path = os.path.join(d, name)
            h.update(os.path.relpath(path, top).encode() + b'\0' + file_digest(path).encode() + b'\0')
    return h.hexdigest()


def key(*parts):
    """A cache key: the sha256 of the parts (str or bytes), each length-prefixed."""
    h = hashlib.sha256()
    for p in parts:
        b = p.encode() if isinstance(p, str) else p
        h.update(len(b).to_bytes(8, 'little') + b)
    return h.hexdigest()


def path_of(kind, k, suffix):
    return os.path.join(CACHE, kind, k[:2], k + suffix)


def load(kind, k):
    """The JSON value stored under (kind, k), or None."""
    try:
        with open(path_of(kind, k, '.json')) as f:
            return json.load(f)
    except FileNotFoundError:
        return None


def store(kind, k, value):
    write_bytes(path_of(kind, k, '.json'), json.dumps(value).encode())


def load_file(kind, k):
    """The path of the file stored under (kind, k), or None."""
    p = path_of(kind, k, '.bin')
    return p if os.path.exists(p) else None


def store_file(kind, k, source):
    """Store a copy of the file at source; returns the stored path."""
    p = path_of(kind, k, '.bin')
    write_bytes(p, open(source, 'rb').read())
    os.chmod(p, 0o755)
    return p


def write_bytes(path, data):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    # Per thread too: two threads of one process may store the same key.
    tmp = f'{path}.{os.getpid()}.{threading.get_ident()}.tmp'
    with open(tmp, 'wb') as f:
        f.write(data)
    os.replace(tmp, path)


def no_core_dumps():
    """Stop this process and its children from dumping core. The tests trap
    on purpose, and with a core_pattern that pipes to a helper (Ubuntu's
    apport) each trap waits about a second for it; a core limit of 1, unlike
    0, makes the kernel skip the pipe."""
    import resource
    resource.setrlimit(resource.RLIMIT_CORE, (1, 1))


FORMAL = os.path.join(ROOT, 'formal')
OLEANS = os.path.join(FORMAL, '.lake/build/lib/lean')


def olean_digest(text):
    """A digest of the built .olean files (with their .private, .server and
    .ir parts) a Lean file's imports reach in formal/ (with the toolchain),
    or None when one is missing."""
    import re
    seen, todo = set(), re.findall(r'^(?:public\s+|meta\s+)*import\s+(?:all\s+)?(\S+)', text, re.M)
    h = hashlib.sha256(open(os.path.join(FORMAL, 'lean-toolchain'), 'rb').read())
    while todo:
        m = todo.pop()
        rel = m.replace('.', '/')
        source = os.path.join(FORMAL, rel + '.lean')
        if m in seen or not os.path.exists(source):
            continue  # a toolchain module (Std, Init), covered by lean-toolchain
        seen.add(m)
        olean = os.path.join(OLEANS, rel + '.olean')
        if not os.path.exists(olean):
            return None
        # A `module`'s bodies and compiled code are in the .olean.private
        # and .ir files beside its .olean, which holds only the interface.
        for part in (olean, olean + '.private', olean + '.server', os.path.join(OLEANS, rel + '.ir')):
            if os.path.exists(part):
                h.update(m.encode() + b'\0' + os.path.basename(part).encode() + b'\0' + file_digest(part).encode())
        todo += re.findall(r'^(?:public\s+|meta\s+)*import\s+(?:all\s+)?(\S+)', open(source).read(), re.M)
    return h.hexdigest()


def run_lean(lean_path, memory='6G', outputs=()):
    """`lake env lean` on a file, under a memory cap, cached by the file's text
    and the .olean files it imports (only a run that exits 0 is stored).
    outputs: files the run writes; they are stored with the entry and written
    back on a hit, so a hit never leaves another run's files in place.
    Returns an object with returncode, stdout and stderr."""
    import subprocess
    import types
    text = open(lean_path).read()
    digest = olean_digest(text)
    k = key(digest or '', text)
    hit = load('lean', k) if digest else None
    if hit is not None and outputs and 'files' not in hit:
        hit = None
    for path in outputs:
        if os.path.exists(path):
            os.remove(path)
    if hit is not None:
        for path, body in hit.get('files', {}).items():
            open(path, 'w').write(body)
        return types.SimpleNamespace(returncode=0, stdout=hit['stdout'], stderr='')
    env = dict(os.environ, PATH=os.path.expanduser('~/.elan/bin') + ':' + os.environ['PATH'])
    with lean_lock():
        run = subprocess.run(['systemd-run', '--user', '--scope', '--slice=work.slice', '-q', 'lake', 'env', 'lean', os.path.abspath(lean_path)], cwd=FORMAL,
                             env=env, capture_output=True, text=True)
    if run.returncode == 0 and digest:
        files = {path: open(path).read() for path in outputs if os.path.exists(path)}
        store('lean', k, dict(stdout=run.stdout, files=files) if outputs else dict(stdout=run.stdout))
    return run


def lani_digest(entry, roots):
    """A digest of the source files a laniusc build of entry reads: entry and,
    transitively, every file an `import a::b::c;` in one of them can resolve
    to in a root (a/b/c.lani for the module, a/b.lani for an item of it),
    each as its bytes or as absent (by root index and relative path, so
    copies of the same roots agree). laniusc reads only that closure of an
    entry's imports (its source-root loader), so this is the key a build
    needs instead of a digest of every root; the import lines are found
    anywhere in the text, comments too, so the set over-approximates."""
    import re
    roots = [os.path.abspath(r) for r in roots]
    h = hashlib.sha256()
    seen, todo = set(), [('entry', os.path.abspath(entry))]
    while todo:
        label, path = todo.pop()
        if label in seen:
            continue
        seen.add(label)
        h.update(label.encode() + b'\0' + file_digest(path).encode() + b'\0')
        text = open(path, encoding='utf-8', errors='replace').read()
        bare = re.sub(r'//[^\n]*|/\*.*?\*/', ' ', text, flags=re.S)
        names = set()
        for t in (text, bare):
            names.update(re.sub(r'\s', '', m) for m in re.findall(r'\bimport\s+(\w+(?:\s*::\s*\w+)*)\s*;', t))
        for name in sorted(names):
            parts = name.split('::')
            for rel in sorted({'/'.join(parts) + '.lani', '/'.join(parts[:-1]) + '.lani'} - {'.lani'}):
                for i, r in enumerate(roots):
                    candidate = os.path.join(r, rel)
                    if os.path.isfile(candidate):
                        todo.append((f'{i}:{rel}', candidate))
                    else:
                        h.update(f'absent {i}:{rel}\0'.encode())
    return h.hexdigest()


# The parts of a laniusc build its parser's output depends on: the kernels
# of the front end (under the artifact root the binary loads them from at
# run time) and the host code that drives them, with the grammar tables
# built into the binary.
FRONT_KERNELS = ('lexer', 'parser', 'scan', 'radix', 'readback')
FRONT_SOURCES = ('/crates/laniusc-compiler/src/lexer/', '/crates/laniusc-compiler/src/parser/',
                 '/crates/laniusc-compiler/src/gpu/', '/crates/laniusc-compiler/src/shader_artifacts.rs',
                 '/tables/', '/Cargo.lock')
_parser_digests = {}


def parser_digest(laniusc):
    """What laniusc's parse trees and tokens depend on, so that a rebuild
    that leaves the front end alone keeps the stored parses: the bytes of
    the front end's kernels (FRONT_KERNELS: .spv and .reflect.json) in the
    artifact root the binary reads (LANIUS_SHADER_ARTIFACT_ROOT, else its
    build's), and of the front end's sources (FRONT_SOURCES: lexer, parser
    and GPU runtime code, the grammar tables, the locked crates) as the
    build's dep-info (laniusc.d) lists them. The sources are taken only
    when none is newer than the binary, so they are what it was built from,
    and that digest is stored under the binary's: a checkout edited since
    the build (a merge before the rebuild) finds it there. Without either
    (or for a binary without dep-info, such as a pin's wrapper) the digest
    is the whole binary's, as before."""
    real = os.path.realpath(laniusc)
    st = os.stat(real)
    memo = (real, st.st_mtime_ns, st.st_size, os.environ.get('LANIUS_SHADER_ARTIFACT_ROOT'))
    if memo not in _parser_digests:
        binary = file_digest(real)
        sources = front_sources_digest(real, st)
        k = key('front-sources', binary)
        if sources is None:
            hit = load('front', k)
            sources = hit['sources'] if hit else None
        elif load('front', k) is None:
            store('front', k, dict(sources=sources))
        kernels = front_kernels_digest(real) if sources else None
        _parser_digests[memo] = ('front ' + key(sources, kernels)) if kernels else 'binary ' + binary
    return _parser_digests[memo]


def front_sources_digest(real, st):
    """The digest of the front end's sources the binary real was built from
    (parser_digest), or None when its dep-info is missing or a source is
    newer than it."""
    dep = real + '.d'
    try:
        if abs(os.stat(dep).st_mtime_ns - st.st_mtime_ns) > 60 * 10**9:
            return None
        with open(real, 'rb') as f:
            if f.read(4) != b'\x7fELF':
                return None
        text = open(dep).read()
    except OSError:
        return None
    # dep-info: "target: dep dep ..." (a space in a path is escaped as "\ ")
    deps = text.split(':', 1)[1].replace('\\ ', '\0').split() if ':' in text else []
    deps = sorted({d.replace('\0', ' ') for d in deps})
    front = [d for d in deps if any(m in d if m.endswith('/') else d.endswith(m) for m in FRONT_SOURCES)]
    if not any(d.endswith('/parse_tables.bin') for d in front) or not any('/src/parser/' in d for d in front):
        return None
    h = hashlib.sha256(b'front sources 1\0')
    for d in front:
        if not os.path.isfile(d):
            continue
        if os.stat(d).st_mtime_ns > st.st_mtime_ns:
            return None
        rel = d[d.index('/crates/'):] if '/crates/' in d else d[d.rindex('/tables/'):] if '/tables/' in d else os.path.basename(d)
        h.update(f'{rel}\0{file_digest(d)}\0'.encode())
    return h.hexdigest()


def front_kernels_digest(real):
    """The digest of the front end's kernels in the artifact root the binary
    real loads (parser_digest), or None when there are none."""
    profile = os.path.basename(os.path.dirname(real))
    shaders = os.environ.get('LANIUS_SHADER_ARTIFACT_ROOT') or os.path.join(
        os.path.dirname(os.path.dirname(real)), 'laniusc-shader-artifacts', profile, 'shaders')
    h = hashlib.sha256(b'front kernels 1\0')
    count = 0
    for top in FRONT_KERNELS:
        for d, dirs, files in sorted(os.walk(os.path.join(shaders, top))):
            dirs.sort()
            for name in sorted(files):
                if name.endswith(('.spv', '.reflect.json')):
                    path = os.path.join(d, name)
                    h.update(f'{os.path.relpath(path, shaders)}\0{file_digest(path)}\0'.encode())
                    count += 1
    return h.hexdigest() if count else None


# Callbacks that release heavy's GPU lane (a resident parse server holds
# it): laniusc_build calls them first, as lcc and heavy queue for the lane.
GPU_RELEASE = []


def release_gpu():
    for release in GPU_RELEASE:
        release()


LCC = os.path.join(ROOT, 'target/claude-work/bin/lcc')
LCC_LANIUSC = '/home/andrew-peterson/code/laniusc/target/release/laniusc'


def lcc_argv(laniusc, entry, exe, roots):
    """The command that builds exe from entry through lcc, the client of one
    resident laniusc daemon shared by every checkout (a warm compile takes
    tens of milliseconds, a one-shot laniusc seconds of GPU start-up), or
    None when lcc is missing, builds another laniusc binary, or would be
    given more than one source root besides the stdlib (roots[-1])."""
    if not os.path.exists(LCC) or len(roots) > 2 or not os.path.exists(LCC_LANIUSC):
        return None
    if os.path.realpath(laniusc) != os.path.realpath(LCC_LANIUSC):
        return None
    return [LCC, '--stdlib-root', roots[-1]] + [a for r in roots[:-1] for a in ('--source-root', r)] + ['-o', exe, entry]


def laniusc_build(argv, laniusc, entry, exe, roots):
    """Build exe from entry with these source roots (the stdlib last), unless
    a build with the same laniusc binary and sources is stored: through lcc
    when it can (lcc_argv), else (or when lcc fails) by argv, a one-shot
    laniusc command. The stored binary's path and None, or None and the
    command's result when it fails."""
    import subprocess
    k = key('build', file_digest(laniusc), lani_digest(entry, roots))
    hit = load_file('build', k)
    if hit is not None:
        return hit, None
    release_gpu()
    if os.path.exists(exe):
        os.remove(exe)
    fast = lcc_argv(laniusc, entry, exe, roots)
    run = subprocess.run(fast, capture_output=True, text=True) if fast else None
    if run is None or (run.returncode != 0 and 'LNC' not in run.stderr) or (run.returncode == 0 and not os.path.exists(exe)):
        # lcc itself failed (not laniusc's diagnostic): the one-shot command
        if os.path.exists(exe):
            os.remove(exe)
        run = subprocess.run(argv, capture_output=True, text=True)
    if run.returncode != 0 or not os.path.exists(exe):
        return None, run
    return store_file('build', k, exe), None


RUN_ALL = os.path.join(FORMAL, '.lake/build/bin/runAll')


def run_all(manifest, prefix=(), timeout=None):
    """runAll (prefix, such as a systemd-run cap, before it) on a manifest,
    its stdout cached by runAll's binary and each line with the bytes of the
    files its bases name (BASE.lani, .prods, .parents); a manifest with an
    `elf` line, which writes a file, is always run. Returns an object with
    returncode, stdout and stderr (only a run that exits 0 is stored)."""
    import subprocess
    import types
    lines = [line for line in open(manifest).read().split('\n') if line]
    parts = [file_digest(RUN_ALL)]
    cacheable = True
    for line in lines:
        words = line.split(' ')
        if words[0] not in ('compile', 'dump', 'diag', 'validate', 'names'):
            cacheable = False
            break
        parts.append(line)
        for b in words[2:]:
            for suffix in ('.lani', '.prods', '.parents'):
                parts.append(file_digest(b + suffix) if os.path.exists(b + suffix) else 'absent')
    k = key(*parts) if cacheable else None
    hit = load('run_all', k) if k else None
    if hit is not None:
        return types.SimpleNamespace(returncode=0, stdout=hit['stdout'], stderr='')
    run = subprocess.run([*prefix, RUN_ALL, manifest], capture_output=True, text=True, timeout=timeout)
    if run.returncode == 0 and k:
        store('run_all', k, dict(stdout=run.stdout))
    return run
