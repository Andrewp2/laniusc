#!/usr/bin/env python3
"""Step 11, milestone M11c: the verified compiler compiled by itself.

    python3 -I formal/tools/self_host.py WORKDIR [--cases DIR | --no-cases] [--fixpoint]
        [--laniusc PATH] [--heap-log2 N] [--stack-log2 N] [--memory-max SIZE]

Run from the repository root. `mini::selfhost` is formal/lani/mini/compiler.lani
followed by the body of formal/lani/mini/frontend.lani (after its prelude and
its copy of compiler.lani's types), so the front end's `SrcProgram` is the one
`compile_source` takes. The driver `w(input, words, output, room)` decodes
source files and their parse trees from an i32 slice, lexes each file with
`lex_source`, runs `front_end_files` on `grammar()` and `compile_source`, and
writes the entries and the image into the output slice.

  self       Lean's `compileSource` of the driver and mini::selfhost (the
             self-built verified compiler), run natively on each test input;
  laniusc    the driver built by laniusc, fed the same input on stdin;
  Lean       `compileSource` of each test program.

The Lean side runs compiled, as `lake exe runAll` (Lanius/Tools/RunAll.lean):
`#eval` is too slow for the whole front end.

The test programs are the front end's hand-written cases (each case's files,
and its want.lani). All three must give the same entries and image bytes on
every test, or all must reject it. With --fixpoint the last test is the
self-built compiler's own source: it must give exactly Lean's result, whose
image is the self-built compiler's own image. laniusc's build is run on it
too but not counted: laniusc's runtime allocator maps fresh pages for every
allocation, and this run makes on the order of 10^8 of them.

The self-built compiler's runs happen in one child process under a memory
cap (--memory-max), each run in a fork with a fresh heap and stack backed by
sparse, unlinked files in WORKDIR/native, so the cap bounds the memory held,
not the memory used: on its own source the compiler (whose bump allocator
never frees) allocates about 7 GiB and recurses over ten million calls deep.
Prints a summary; exits nonzero on any difference.
"""

import argparse
import ctypes
import mmap
import os
import re
import shutil
import signal
import subprocess
import sys
import time
import threading

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import run_cache  # noqa: E402
import stdlib_oracle as so  # noqa: E402

S = 'mini::selfhost::'

DRIVER = f'''module app::main;
import core::option;
import mini::selfhost;

// The input words, as front_end_words reads them (formal/lani/mini/frontend.lani):
// the file count, then each file's counted bytes, productions and parents.
// The output words, as compile_words gives
// them: the entry count, the entries, the image length, the bytes. The
// result is the number of words written, or -1 when the program is
// rejected. Everything but reading the input and writing the output is pure
// selfhost code, whose Lean meaning is its extraction (roadmap V1).
fn w(input: ptr, words: i32, output: ptr, room: i32) -> i32 {{
    let data: [i32] = slice_from_raw_parts(input, words);
    let out: [i32] = slice_from_raw_parts(output, room);
    let read: {S}List<i32> = oracle_read(data, 0, words as usize, {S}empty());
    return oracle_put(out, {S}compile_words({S}front_end_words({S}grammar(), read)));
}}

// data[lo..hi] in front of tail. Each call halves the range, so the
// recursion is as deep as log2 of the input's length.
fn oracle_read(data: [i32], lo: usize, hi: usize, tail: {S}List<i32>) -> {S}List<i32> {{
    if (hi - lo > 1) {{
        let mid: usize = lo + (hi - lo) / 2;
        let right: {S}List<i32> = oracle_read(data, mid, hi, tail);
        return oracle_read(data, lo, mid, right);
    }}
    if (hi > lo) {{
        return {S}cons(data[lo], tail);
    }}
    return tail;
}}

fn oracle_put(out: [i32], result: core::option::Option<{S}List<i32>>) -> i32 {{
    return match (result) {{
        None -> 0 - 1,
        Some(ws) -> oracle_write(out, 0, ws) as i32,
    }};
}}

fn oracle_write(out: [i32], at: usize, ws: {S}List<i32>) -> usize {{
    return match (ws) {{
        Nil -> at,
        Cons(x, rest) -> oracle_write_one(out, at, x, {S}unbox(rest)),
    }};
}}

// The rest first, then this word: every box is read before the first
// write, so the writes cannot change a list still to be read.
fn oracle_write_one(out: [i32], at: usize, x: i32, rest: {S}List<i32>) -> usize {{
    let written: usize = oracle_write(out, at + 1, rest);
    out[at] = x;
    return written;
}}
'''

# laniusc's build adds a main that reads the input words from stdin (the
# word count, the output room, then the words) and writes the result and
# the output words, 4 bytes each, little-endian.
LANIUSC_MAIN = '''
fn oracle_byte() -> i32 {
    return std::io_byte::read_stdin_byte_or(0, 0);
}

fn oracle_read32() -> i32 {
    let a: i32 = oracle_byte();
    let b: i32 = oracle_byte();
    let c: i32 = oracle_byte();
    let d: i32 = oracle_byte();
    return a | (b << 8) | (c << 16) | (d << 24);
}

fn oracle_out(value: i32) -> i32 {
    let written: bool = std::io_byte::write_stdout_byte(value & 255);
    return 0;
}

fn oracle_put32(value: i32) -> i32 {
    oracle_out(value);
    oracle_out(value >> 8);
    oracle_out(value >> 16);
    oracle_out(value >> 24);
    return 0;
}

fn main() -> i32 {
    let words: usize = oracle_read32() as usize;
    let room: usize = oracle_read32() as usize;
    let input: ptr = alloc::allocator::alloc(words * 4 + 4, 4);
    let data: [i32] = slice_from_raw_parts(input, words);
    let i: usize = 0;
    while (i < words) {
        data[i] = oracle_read32();
        i = i + 1;
    }
    let output: ptr = alloc::allocator::alloc(room * 4 + 4, 4);
    let n: i32 = w(input, words as i32, output, room as i32);
    oracle_put32(n);
    let out: [i32] = slice_from_raw_parts(output, room);
    let j: i32 = 0;
    while (j < n) {
        oracle_put32(out[j as usize]);
        j = j + 1;
    }
    return 0;
}
'''

def selfhost_text():
    compiler = open('formal/lani/mini/compiler.lani').read()
    assert 'module mini::compiler;' in compiler
    frontend = open('formal/lani/mini/frontend.lani').read()
    body = frontend.split('// extract: external end\n', 1)[1]
    return compiler.replace('module mini::compiler;', 'module mini::selfhost;', 1) + '\n' + body


def layout(bases):
    """The driver's input words (`filesWords` in Lanius/Mini/TextWords.lean)
    for the files BASE.lani with their trees BASE.prods and BASE.parents."""
    words = [len(bases)]
    for base in bases:
        source = open(base + '.lani', 'rb').read()
        words += [len(source)] + list(source)
        for ext in ('.prods', '.parents'):
            nums = [int(x) for x in open(base + ext).read().split()]
            words += [len(nums)] + nums
    return words


def expected_words(status):
    """compileSource's result as the driver writes it, or None when rejected."""
    if not status.startswith('image'):
        return None
    entries_s, image_s = re.match(r'image \[(.*?)\] \[(.*?)\]$', status).groups()
    entries = [int(x) for x in entries_s.split(',')] if entries_s else []
    image = [int(x) for x in image_s.split(',')] if image_s else []
    return [len(entries)] + entries + [len(image)] + image


def backed(path, size):
    """size bytes of zeros, shared with a sparse file that is already
    unlinked: the kernel can write the pages out to it instead of keeping
    them all in memory. The self-built compiler's bump allocator never frees,
    and compiling itself it allocates about 8.5 GiB and recurses more than
    ten million calls deep (a list walk over its own 11 MB image)."""
    fd = os.open(path, os.O_RDWR | os.O_CREAT | os.O_TRUNC, 0o600)
    try:
        os.ftruncate(fd, size)
        m = mmap.mmap(fd, size, flags=mmap.MAP_SHARED, prot=mmap.PROT_READ | mmap.PROT_WRITE)
    finally:
        os.close(fd)
        os.unlink(path)
    return m, ctypes.addressof(ctypes.c_char.from_buffer(m))


class Native:
    """The self-built image in executable memory. Each run forks; the child
    maps a fresh heap and a fresh stack, both backed by files under `scratch`
    (see backed), and the stub switches to that stack for the call. The heap
    is laid out as `selfCompiler_outcome` (Lanius/Faithful/SelfCompiler.lean)
    takes it: the input words from offset 4 (`selfInput`), the output view
    after them (`selfOutput`), and the cursor 4 bytes past it (`selfNext`)."""

    def __init__(self, entries, image, heap_size, stack_size, scratch):
        private = mmap.MAP_PRIVATE | mmap.MAP_ANONYMOUS
        self.code = mmap.mmap(-1, len(image) + 4096, flags=private,
                              prot=mmap.PROT_READ | mmap.PROT_WRITE | mmap.PROT_EXEC)
        self.base = ctypes.addressof(ctypes.c_char.from_buffer(self.code))
        self.code[0:len(image)] = bytes(image)
        self.entries, self.at = entries, len(image)
        self.heap_size, self.stack_size, self.scratch = heap_size, stack_size, scratch

    def stub(self, heap_base, stack_top, cursor, limit, stack_limit):
        # push rbx, r12, r13, r14, r15; mov rbx, rsp; mov rsp, stack_top; r12 =
        # the heap, r13 = the cursor, r14 = the limit, r15 = the stack
        # limit; the four arguments just below rsp; call w; mov rsp, rbx;
        # pop r15, r14, r13, r12, rbx; ret
        stub = bytes([0x53, 0x41, 0x54, 0x41, 0x55, 0x41, 0x56, 0x41, 0x57, 0x48, 0x89, 0xE3])
        stub += bytes([0x48, 0xBC]) + stack_top.to_bytes(8, 'little')
        stub += bytes([0x49, 0xBC]) + heap_base.to_bytes(8, 'little')
        stub += bytes([0x49, 0xBD]) + cursor.to_bytes(8, 'little')
        stub += bytes([0x49, 0xBE]) + limit.to_bytes(8, 'little')
        stub += bytes([0x49, 0xBF]) + stack_limit.to_bytes(8, 'little')
        for k in range(4):
            stub += so.ARG_STORES[k] + bytes([(256 - (8 * k + 24)) & 0xff])
        rel = self.entries[0] - (self.at + len(stub) + 5)
        stub += b'\xe8' + (rel & 0xffffffff).to_bytes(4, 'little')
        stub += bytes([0x48, 0x89, 0xDC, 0x41, 0x5F, 0x41, 0x5E, 0x41, 0x5D, 0x41, 0x5C, 0x5B, 0xC3])
        self.code[self.at:self.at + len(stub)] = stub
        return ctypes.CFUNCTYPE(ctypes.c_uint64, *([ctypes.c_uint64] * 4))(self.base + self.at)

    def run(self, words, room, timeout):
        """The driver's output words, None when it rejects, or 'trap (SIG...)'
        or 'timeout'; and the child's peak resident memory in KiB."""
        r, w = os.pipe()
        pid = os.fork()
        if pid == 0:
            os.close(r)
            signal.signal(signal.SIGINT, signal.SIG_DFL)
            signal.alarm(timeout)
            heap, heap_base = backed(os.path.join(self.scratch, f'heap.{os.getpid()}'), self.heap_size)
            stack, stack_base = backed(os.path.join(self.scratch, f'stack.{os.getpid()}'), self.stack_size)
            in_at = 4
            out_at = in_at + 4 * len(words)
            heap[in_at:in_at + 4 * len(words)] = b''.join((x & 0xffffffff).to_bytes(4, 'little') for x in words)
            fn = self.stub(heap_base, stack_base + self.stack_size - 64, out_at + 4 * room + 4, self.heap_size - 4096,
                           stack_base + 4096)
            n = fn(in_at, len(words), out_at, room) & 0xffffffff
            n = n - 2 ** 32 if n >= 2 ** 31 else n
            payload = n.to_bytes(4, 'little', signed=True)
            if n > 0:
                payload += bytes(heap[out_at:out_at + 4 * n])
            os.write(w, len(payload).to_bytes(8, 'little'))
            view = memoryview(payload)
            while view:
                view = view[os.write(w, view):]
            os._exit(0)
        os.close(w)
        chunks = []
        while True:
            chunk = os.read(r, 1 << 20)
            if not chunk:
                break
            chunks.append(chunk)
        os.close(r)
        _, status, usage = os.wait4(pid, 0)
        if os.WIFSIGNALED(status):
            sig = os.WTERMSIG(status)
            return ('timeout' if sig == signal.SIGALRM else f'trap ({signal.Signals(sig).name})'), usage.ru_maxrss
        return decode(b''.join(chunks)[8:]), usage.ru_maxrss


def words_file(path, words):
    open(path, 'wb').write(b''.join((x & 0xffffffff).to_bytes(4, 'little') for x in words))


def read_words(path):
    data = open(path, 'rb').read()
    return [int.from_bytes(data[i:i + 4], 'little', signed=True) for i in range(0, len(data), 4)]


def native_batch(batch, heap_log2, stack_log2, room, timeout):
    """Run the self-built image (batch/self.image, batch/self.entries) on
    each batch/inK.words, writing batch/outK: a status line, then the
    output words. Run under a memory cap (see main)."""
    run_cache.no_core_dumps()
    image = open(os.path.join(batch, 'self.image'), 'rb').read()
    entries = [int(x) for x in open(os.path.join(batch, 'self.entries')).read().split()]
    native = Native(entries, image, 1 << heap_log2, 1 << stack_log2, batch)
    k = 0
    while os.path.exists(os.path.join(batch, f'in{k}.words')):
        began = time.time()
        got, rss = native.run(read_words(os.path.join(batch, f'in{k}.words')), room, timeout)
        with open(os.path.join(batch, f'out{k}'), 'wb') as f:
            status = 'words' if isinstance(got, list) else 'rejected' if got is None else got
            f.write(f'{status} {time.time() - began:.1f} {rss}\n'.encode())
            if isinstance(got, list):
                f.write(b''.join((x & 0xffffffff).to_bytes(4, 'little') for x in got))
        k += 1


def read_out(path):
    data = open(path, 'rb').read()
    line, rest = data.split(b'\n', 1)
    status, seconds, rss = line.decode().split(' ')
    got = {'words': None, 'rejected': None}.get(status, status)
    if status == 'words':
        got = [int.from_bytes(rest[i:i + 4], 'little', signed=True) for i in range(0, len(rest), 4)]
    return got, float(seconds), int(rss)


def decode(data):
    n = int.from_bytes(data[0:4], 'little', signed=True)
    if n < 0:
        return None
    return [int.from_bytes(data[4 + 4 * i:8 + 4 * i], 'little', signed=True) for i in range(n)]


def main():
    run_cache.no_core_dumps()
    parser = argparse.ArgumentParser()
    parser.add_argument('workdir')
    parser.add_argument('--cases', default='formal/tools/frontend_cases')
    parser.add_argument('--laniusc', default='target/release/laniusc')
    parser.add_argument('--heap-log2', type=int, default=36,
                        help='heap size (file-backed and sparse, so only what is used is written)')
    parser.add_argument('--stack-log2', type=int, default=33)
    parser.add_argument('--memory-max', default='4G', help='memory cap of the native runs')
    parser.add_argument('--no-cases', action='store_true', help='skip the hand-written cases')
    parser.add_argument('--native-batch', action='store_true', help=argparse.SUPPRESS)
    parser.add_argument('--timeout', type=int, default=600)
    parser.add_argument('--fixpoint', action='store_true',
                        help='also give the self-built compiler its own source, which must give its own image')
    args = parser.parse_args()
    if args.native_batch:
        native_batch(args.workdir, args.heap_log2, args.stack_log2, 1 << 24, args.timeout)
        return 0
    workdir = os.path.abspath(args.workdir)
    os.makedirs(workdir, exist_ok=True)

    root = os.path.join(workdir, 'root')
    shutil.rmtree(root, ignore_errors=True)
    shutil.copytree('stdlib', root)
    os.makedirs(os.path.join(root, 'mini'))
    open(os.path.join(root, 'mini', 'selfhost.lani'), 'w').write(selfhost_text())
    # laniusc builds mini::selfhost from a source root: as a library unit
    # under the stdlib root it rejects some generic instances (LNC0017).
    source_root = os.path.join(workdir, 'src')
    os.makedirs(os.path.join(source_root, 'mini'), exist_ok=True)
    shutil.copy(os.path.join(root, 'mini', 'selfhost.lani'), os.path.join(source_root, 'mini', 'selfhost.lani'))
    so.STDLIB = root
    mods = so.load_modules()
    files_dir = os.path.join(workdir, 'files')
    os.makedirs(files_dir, exist_ok=True)

    began = time.time()
    so.build_run_all()

    def parse(base):
        return so.parse_checked(args.laniusc, base, files_dir)

    # The self-built compiler: the driver, mini::selfhost and its imports.
    driver = os.path.join(files_dir, 'driver')
    open(driver + '.lani', 'w').write(DRIVER)
    if not parse(driver):
        raise SystemExit('laniusc does not parse the driver')
    self_bases = [driver]
    for dep in so.closure(mods, 'mini::selfhost'):
        b = os.path.join(files_dir, dep.replace('::', '__'))
        shutil.copy(mods[dep].path, b + '.lani')
        if not parse(b):
            raise SystemExit(f'laniusc does not parse {dep}')
        self_bases.append(b)

    # The tests: each case's files, and its want.lani.
    tests = []
    for case in [] if args.no_cases else sorted(os.listdir(args.cases)):
        src = os.path.join(args.cases, case)
        if not os.path.isdir(src):
            continue
        names = sorted(n for n in os.listdir(src) if n.endswith('.lani') and n not in ('main.lani', 'want.lani'))
        groups = [('got', ['main.lani'] + names)]
        if os.path.exists(os.path.join(src, 'want.lani')):
            groups.append(('want', ['want.lani']))
        for kind, names in groups:
            bases = []
            for name in names:
                b = os.path.join(workdir, 'cases', f'{case}_{kind}_{name[:-5]}')
                os.makedirs(os.path.dirname(b), exist_ok=True)
                shutil.copy(os.path.join(src, name), b + '.lani')
                if parse(b):
                    bases.append(b)
                else:
                    bases = None
                    break
            if bases is not None:
                tests.append(dict(name=f'{case}/{kind}', bases=bases))

    if args.fixpoint:
        tests.append(dict(name='the verified compiler itself', bases=self_bases, fixpoint=True))
    manifest = [f'compile self {" ".join(self_bases)}']
    for k, t in enumerate(tests):
        manifest.append(f'compile t{k} {" ".join(t["bases"])}')
    manifest_path = os.path.join(workdir, 'manifest.txt')
    open(manifest_path, 'w').write('\n'.join(manifest) + '\n')
    print(f'time: parse {time.time() - began:.0f} s', file=sys.stderr, flush=True)
    began = time.time()
    lean = subprocess.run(['systemd-run', '--user', '--scope', '-q', '-p', 'MemoryMax=10G', '-p', 'MemorySwapMax=0',
                           so.RUN_ALL, manifest_path], capture_output=True, text=True)
    print(f'time: runAll {time.time() - began:.0f} s', file=sys.stderr, flush=True)
    began = time.time()
    if lean.returncode != 0:
        raise SystemExit('runAll failed:\n' + lean.stdout[-4000:] + lean.stderr[-4000:])
    status = {}
    for line in lean.stdout.split('\n'):
        if line:
            name, rest = line.split(' ', 1)
            status[name] = rest
    self_status = status.get('self', 'missing')
    if not self_status.startswith('image'):
        raise SystemExit(f'the verified compiler does not compile itself: {self_status}')
    self_words = expected_words(self_status)
    entries = self_words[1:1 + self_words[0]]
    image = self_words[2 + self_words[0]:]
    print(f'self-built verified compiler: {len(image)} bytes, {len(entries)} functions')
    open(os.path.join(workdir, 'self.image'), 'wb').write(bytes(image))

    room = 1 << 24  # output words: the fixpoint image is about 11M bytes

    # laniusc's build of the same driver.
    imports = 'import alloc::allocator;\nimport std::io_byte;\n'
    exe = os.path.join(workdir, 'laniusc_driver')
    text = DRIVER.replace('import mini::selfhost;\n', 'import mini::selfhost;\n' + imports, 1) + LANIUSC_MAIN
    open(exe + '.lani', 'w').write(text)
    if os.path.exists(exe):
        os.remove(exe)
    build = subprocess.run(['systemd-run', '--user', '--scope', '-q', '-p', 'MemoryMax=8G', '-p', 'MemorySwapMax=0',
                            so.HEAVY, '-t', '30', args.laniusc, '--stdlib-root', 'stdlib', '--source-root',
                            source_root, '-o', exe, exe + '.lani'],
                           capture_output=True, text=True)
    if build.returncode != 0 or not os.path.exists(exe):
        raise SystemExit('laniusc does not build the driver:\n' + build.stdout[-2000:] + build.stderr[-2000:])
    print(f'time: laniusc build {time.time() - began:.0f} s', file=sys.stderr, flush=True)
    began = time.time()

    # The self-built compiler on every test, in one process under a memory
    # cap: its heap and stack are file-backed, so the cap bounds the memory
    # it holds, not what it allocates.
    batch = os.path.join(workdir, 'native')
    shutil.rmtree(batch, ignore_errors=True)
    os.makedirs(batch)
    open(os.path.join(batch, 'self.image'), 'wb').write(bytes(image))
    open(os.path.join(batch, 'self.entries'), 'w').write(' '.join(map(str, entries)) + '\n')
    runnable = list(range(len(tests)))
    for k, t in enumerate(tests):
        words_file(os.path.join(batch, f'in{k}.words'), layout(t['bases']))
    subprocess.run(['systemd-run', '--user', '--scope', '-q', '-p', f'MemoryMax={args.memory_max}',
                    '-p', 'MemorySwapMax=0', sys.executable, '-I', os.path.abspath(__file__), batch,
                    '--native-batch', '--heap-log2', str(args.heap_log2), '--stack-log2', str(args.stack_log2),
                    '--timeout', str(args.timeout)], check=True)
    selfs = {k: read_out(os.path.join(batch, f'out{j}')) for j, k in enumerate(runnable)}
    print(f'time: self-built runs {time.time() - began:.0f} s', file=sys.stderr, flush=True)
    began = time.time()

    problems, agree, notes = [], 0, []
    for k, t in enumerate(tests):
        want = expected_words(status.get(f't{k}', 'missing'))
        got_self, seconds, rss = selfs[k]
        words = read_words(os.path.join(batch, f'in{runnable.index(k)}.words'))
        stdin = b''.join((x & 0xffffffff).to_bytes(4, 'little') for x in [len(words), room] + words)
        show = lambda v: v if not isinstance(v, list) else f'{len(v)} words'  # noqa: E731
        if t.get('fixpoint'):
            image_words = want[2 + want[0]:] if isinstance(want, list) else None
            print(f'fixpoint: the self-built verified compiler on its own source: {show(got_self)} in {seconds:.0f} s '
                  f'(peak resident {rss >> 10} MiB), Lean {show(want)}; '
                  f'its own image: {image_words == list(image)}')
            # laniusc's build on the same input. Its runtime allocator maps
            # fresh pages for every allocation (one mmap each), and this run
            # makes on the order of 10^8 allocations, so it cannot finish; it
            # is run under a cap and reported, not counted.
            got_laniusc = run_laniusc(exe, stdin, args.timeout, args.memory_max, 1 << args.stack_log2)
            notes.append(f'{t["name"]}: laniusc {show(got_laniusc)} (not counted: laniusc\'s runtime maps a fresh '
                         f'page for every allocation)')
            if got_self == want and image_words == list(image):
                agree += 1
            else:
                problems.append(f'{t["name"]}: Lean {show(want)}, self {show(got_self)}'
                                + ('' if not (isinstance(want, list) and isinstance(got_self, list)) or want == got_self
                                   else ' (self differs from Lean)'))
            continue
        got_laniusc = run_laniusc(exe, stdin, args.timeout, None, None)
        if got_self == want and got_laniusc == want:
            agree += 1
        else:
            problems.append(f'{t["name"]}: Lean {show(want)}, self {show(got_self)}, laniusc {show(got_laniusc)}'
                            + ('' if not (isinstance(want, list) and isinstance(got_self, list)) or want == got_self
                               else ' (self differs from Lean)'))
    print(f'time: laniusc runs {time.time() - began:.0f} s', file=sys.stderr, flush=True)
    for line in notes + problems:
        print(line)
    accepted = sum(1 for k in range(len(tests)) if expected_words(status.get(f't{k}', '')) is not None)
    print(f'{len(tests)} programs ({accepted} compiled, {len(tests) - accepted} rejected): {agree} agree, '
          f'{len(problems)} problems')
    return 1 if problems else 0


def run_laniusc(exe, stdin, timeout, memory_max, stack):
    """laniusc's build of the driver on stdin: its output words, None when it
    rejects, 'exit N' or 'timeout'. With memory_max, under that cap and with
    a stack limit of `stack` bytes."""
    argv = [exe]
    preexec = None
    if memory_max is not None:
        argv = ['systemd-run', '--user', '--scope', '-q', '-p', f'MemoryMax={memory_max}', '-p', 'MemorySwapMax=0',
                exe]

        def preexec():
            import resource
            resource.setrlimit(resource.RLIMIT_STACK, (stack, stack))
    try:
        run = subprocess.run(argv, input=stdin, capture_output=True, timeout=timeout, preexec_fn=preexec)
        return decode(run.stdout) if run.returncode == 0 else f'exit {run.returncode}'
    except subprocess.TimeoutExpired:
        return 'timeout'


if __name__ == '__main__':
    sys.exit(main())
