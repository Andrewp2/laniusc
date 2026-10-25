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

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CACHE = os.path.join(ROOT, 'target/claude-work/cache')

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
    tmp = f'{path}.{os.getpid()}.tmp'
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
    """A digest of the built .olean files a Lean file's imports reach in
    formal/ (with the toolchain), or None when one is missing."""
    import re
    seen, todo = set(), re.findall(r'^import\s+(\S+)', text, re.M)
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
        h.update(m.encode() + b'\0' + file_digest(olean).encode())
        todo += re.findall(r'^import\s+(\S+)', open(source).read(), re.M)
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
    run = subprocess.run(['systemd-run', '--user', '--scope', '-q', '-p', f'MemoryMax={memory}', '-p', 'MemorySwapMax=0',
                          'lake', 'env', 'lean', os.path.abspath(lean_path)], cwd=FORMAL, env=env,
                         capture_output=True, text=True)
    if run.returncode == 0 and digest:
        store('lean', k, dict(stdout=run.stdout))
    return run
