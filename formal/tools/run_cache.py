"""Content-addressed caches for the difftests, under target/claude-work/cache.

A cached value is stored under a hash of everything it depends on, so it is
reused across runs and workdirs and never goes stale: laniusc's parse of a
file depends only on the file's bytes and the laniusc binary (its shaders
and parse tables are built into it), a laniusc build on the source, the
binary and the stdlib. Failures are never stored.
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
    directory, those after the first taken only while 5 GB are available. Every Lean
    scope runs in lean.slice (SLICE), which caps all of them together.
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
        def git_dir(flag):
            out = subprocess.run(['git', 'rev-parse', flag], cwd=ROOT, capture_output=True, text=True).stdout.strip()
            return os.path.join(ROOT, out or '.git')
        own = open(os.path.join(git_dir('--git-dir'), 'lean-wt.lock'), 'a')
        fcntl.flock(own, fcntl.LOCK_EX)
        self.held.append(own)
        common = git_dir('--git-common-dir')
        while True:
            for i, name in enumerate(('lean.lock', 'lean.lock.2', 'lean.lock.3', 'lean.lock.4', 'lean.lock.5', 'lean.lock.6')):
                if i and available_gb() < 5:
                    continue
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


SLICE = '--slice=lean.slice'


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


def run_lean(lean_path, memory='6G'):
    """`lake env lean` on a file, under a memory cap, cached by the file's text
    and the .olean files it imports (only a run that exits 0 is stored).
    Returns an object with returncode, stdout and stderr."""
    import subprocess
    import types
    text = open(lean_path).read()
    digest = olean_digest(text)
    k = key(digest or '', text)
    hit = load('lean', k) if digest else None
    if hit is not None:
        return types.SimpleNamespace(returncode=0, stdout=hit['stdout'], stderr='')
    env = dict(os.environ, PATH=os.path.expanduser('~/.elan/bin') + ':' + os.environ['PATH'])
    with lean_lock():
        run = subprocess.run(['systemd-run', '--user', '--scope', '--slice=lean.slice', '-q', '-p', f'MemoryMax={memory}', '-p',
                              'MemorySwapMax=0', 'lake', 'env', 'lean', os.path.abspath(lean_path)], cwd=FORMAL,
                             env=env, capture_output=True, text=True)
    if run.returncode == 0 and digest:
        store('lean', k, dict(stdout=run.stdout))
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
