#!/usr/bin/env python3
"""Step 11, milestone M11c: the verified compiler compiled by itself.

    python3 -I formal/tools/self_host.py WORKDIR [--cases DIR] [--laniusc PATH] [--heap-log2 N]

Run from the repository root. `mini::selfhost` is formal/lani/mini/compiler.lani
followed by the body of formal/lani/mini/frontend.lani (after its prelude and
its copy of compiler.lani's types), so the front end's `SrcProgram` is the one
`compile_source` takes. The driver `w(input, words, output, room)` decodes
lexed files and their parse trees from an i32 slice, runs `front_end_files`
on `grammar()` and `compile_source`, and writes the entries and the image
into the output slice.

  self       Lean's `compileSource` of the driver and mini::selfhost (the
             self-built verified compiler), run natively on each test input;
  laniusc    the driver built by laniusc, fed the same input on stdin;
  Lean       `compileSource` of each test program.

The Lean side runs compiled, as `lake exe runAll` (Lanius/Tools/RunAll.lean):
`#eval` is too slow for the whole front end.

The test programs are the front end's hand-written cases (each case's files,
and its want.lani). All three must give the same entries and image bytes on
every test, or all must reject it. Prints a summary; exits nonzero on any
difference.
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
import threading

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import stdlib_oracle as so  # noqa: E402

S = 'mini::selfhost::'

DRIVER = f'''module app::main;
import core::option;
import mini::selfhost;

// The input: word 0 is the file count, word 1 + f the offset of file f's
// record (token count, token offset, prod count, prod offset, parent count,
// parent offset); a token is 4 words (kind, start, text length, text offset).
// The output: the entry count, the entries, the image length, the bytes;
// the result is the number of words written, or -1 when the program is
// rejected.
fn w(input: ptr, words: i32, output: ptr, room: i32) -> i32 {{
    let data: [i32] = slice_from_raw_parts(input, words);
    let out: [i32] = slice_from_raw_parts(output, room);
    return oracle_emit(out, oracle_run(data));
}}

fn oracle_run(data: [i32]) -> core::option::Option<{S}Binary> {{
    return match ({S}front_end_files({S}grammar(), oracle_files(data, 0, data[0] as usize))) {{
        None -> None,
        Some(program) -> {S}compile_source(program),
    }};
}}

fn oracle_emit(out: [i32], result: core::option::Option<{S}Binary>) -> i32 {{
    return match (result) {{
        None -> 0 - 1,
        Some(binary) -> oracle_put(out, binary),
    }};
}}

fn oracle_put(out: [i32], binary: {S}Binary) -> i32 {{
    let at: usize = oracle_write_usizes(out, 0, binary.entries);
    return oracle_write_bytes(out, at, binary.image) as i32;
}}

fn oracle_write_usizes(out: [i32], at: usize, xs: {S}List<usize>) -> usize {{
    out[at] = {S}length(xs) as i32;
    return oracle_fill_usizes(out, at + 1, xs);
}}

fn oracle_fill_usizes(out: [i32], at: usize, xs: {S}List<usize>) -> usize {{
    return match (xs) {{
        Nil -> at,
        Cons(x, rest) -> oracle_fill_usize(out, at, x, {S}unbox(rest)),
    }};
}}

fn oracle_fill_usize(out: [i32], at: usize, x: usize, rest: {S}List<usize>) -> usize {{
    out[at] = x as i32;
    return oracle_fill_usizes(out, at + 1, rest);
}}

fn oracle_write_bytes(out: [i32], at: usize, xs: {S}List<u8>) -> usize {{
    out[at] = {S}length(xs) as i32;
    return oracle_fill_bytes(out, at + 1, xs);
}}

fn oracle_fill_bytes(out: [i32], at: usize, xs: {S}List<u8>) -> usize {{
    return match (xs) {{
        Nil -> at,
        Cons(x, rest) -> oracle_fill_byte(out, at, x, {S}unbox(rest)),
    }};
}}

fn oracle_fill_byte(out: [i32], at: usize, x: u8, rest: {S}List<u8>) -> usize {{
    out[at] = x as i32;
    return oracle_fill_bytes(out, at + 1, rest);
}}

fn oracle_files(data: [i32], f: usize, count: usize) -> {S}List<{S}FileInput> {{
    if (f == count) {{
        return {S}empty();
    }}
    return {S}cons(oracle_file(data, data[1 + f] as usize), oracle_files(data, f + 1, count));
}}

fn oracle_file(data: [i32], o: usize) -> {S}FileInput {{
    return {S}FileInput {{
        tokens: oracle_tokens(data, data[o + 1] as usize, 0, data[o] as usize),
        prods: oracle_nums(data, data[o + 3] as usize, 0, data[o + 2] as usize),
        parents: oracle_nums(data, data[o + 5] as usize, 0, data[o + 4] as usize),
    }};
}}

fn oracle_tokens(data: [i32], base: usize, i: usize, count: usize) -> {S}List<{S}Token> {{
    if (i == count) {{
        return {S}empty();
    }}
    let at: usize = base + 4 * i;
    let token: {S}Token = {S}Token {{
        kind: data[at] as usize,
        start: data[at + 1] as usize,
        text: oracle_nums(data, data[at + 3] as usize, 0, data[at + 2] as usize),
    }};
    return {S}cons(token, oracle_tokens(data, base, i + 1, count));
}}

fn oracle_nums(data: [i32], base: usize, i: usize, count: usize) -> {S}List<usize> {{
    if (i == count) {{
        return {S}empty();
    }}
    // As u32 first: a parse tree's root has parent 2^32 - 1.
    return {S}cons((data[base + i] as u32) as usize, oracle_nums(data, base, i + 1, count));
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


def layout(files):
    """The driver's input words for files of (tokens, prods, parents)."""
    words = [len(files)] + [0] * len(files)
    for f, (tokens, prods, parents) in enumerate(files):
        record = len(words)
        words[1 + f] = record
        words += [0] * 6
        token_at = len(words)
        words += [0] * (4 * len(tokens))
        for i, (kind, start, text) in enumerate(tokens):
            words[token_at + 4 * i:token_at + 4 * i + 4] = [kind, start, len(text), len(words)]
            words += text
        prod_at = len(words)
        words += prods
        parent_at = len(words)
        words += parents
        words[record:record + 6] = [len(tokens), token_at, len(prods), prod_at, len(parents), parent_at]
    return words


def parse_dump(line):
    tokens_s, prods_s, parents_s = line.split('|')
    tokens = []
    for t in tokens_s.split(' ') if tokens_s else []:
        kind, start, text = t.split(':')
        tokens.append((int(kind), int(start), [int(x) for x in text.split('.')] if text else []))
    nums = lambda s: [int(x) for x in s.split(' ')] if s else []  # noqa: E731
    return tokens, nums(prods_s), nums(parents_s)


def expected_words(status):
    """compileSource's result as the driver writes it, or None when rejected."""
    if not status.startswith('image'):
        return None
    entries_s, image_s = re.match(r'image \[(.*?)\] \[(.*?)\]$', status).groups()
    entries = [int(x) for x in entries_s.split(',')] if entries_s else []
    image = [int(x) for x in image_s.split(',')] if image_s else []
    return [len(entries)] + entries + [len(image)] + image


class Native:
    """The self-built image in executable memory, with a private heap so that
    every forked run starts from zeros. The input and output slices sit at
    the top of the heap, above the limit."""

    def __init__(self, code_size, heap_size):
        private = mmap.MAP_PRIVATE | mmap.MAP_ANONYMOUS
        self.code = mmap.mmap(-1, code_size, flags=private, prot=mmap.PROT_READ | mmap.PROT_WRITE | mmap.PROT_EXEC)
        self.base = ctypes.addressof(ctypes.c_char.from_buffer(self.code))
        self.heap_size = heap_size
        self.heap = mmap.mmap(-1, heap_size, flags=private, prot=mmap.PROT_READ | mmap.PROT_WRITE)
        self.heap_base = ctypes.addressof(ctypes.c_char.from_buffer(self.heap))

    def load(self, entries, image, limit):
        self.code[0:len(image)] = bytes(image)
        at = len(image)
        stub = bytes([0x41, 0x54, 0x41, 0x55, 0x41, 0x56])
        stub += bytes([0x49, 0xBC]) + self.heap_base.to_bytes(8, 'little')
        stub += bytes([0x49, 0xBD]) + (1).to_bytes(8, 'little')
        stub += bytes([0x49, 0xBE]) + limit.to_bytes(8, 'little')
        for k in range(4):
            stub += so.ARG_STORES[k] + bytes([(256 - (8 * k + 24)) & 0xff])
        rel = entries[0] - (at + len(stub) + 5)
        stub += b'\xe8' + (rel & 0xffffffff).to_bytes(4, 'little')
        stub += bytes([0x41, 0x5E, 0x41, 0x5D, 0x41, 0x5C, 0xC3])
        self.code[at:at + len(stub)] = stub
        self.fn = ctypes.CFUNCTYPE(ctypes.c_uint64, *([ctypes.c_uint64] * 4))(self.base + at)

    def run(self, words, room, timeout):
        """The driver's output words, None when it rejects, or 'trap'/'timeout'."""
        in_at = self.heap_size - 4 * (len(words) + room) - 4096
        out_at = in_at + 4 * len(words) + 64
        r, w = os.pipe()
        pid = os.fork()
        if pid == 0:
            os.close(r)
            signal.alarm(timeout)
            self.heap[in_at:in_at + 4 * len(words)] = b''.join(x.to_bytes(4, 'little') for x in words)
            result = []

            def call():
                result.append(self.fn(in_at, len(words), out_at, room))
            threading.stack_size(1 << 30)
            t = threading.Thread(target=call)
            t.start()
            t.join()
            n = result[0] & 0xffffffff
            n = n - 2 ** 32 if n >= 2 ** 31 else n
            payload = n.to_bytes(4, 'little', signed=True)
            if n > 0:
                payload += bytes(self.heap[out_at:out_at + 4 * n])
            os.write(w, len(payload).to_bytes(8, 'little'))
            view = memoryview(payload)
            while view:
                view = view[os.write(w, view):]
            os._exit(0)
        os.close(w)
        data = b''
        while True:
            chunk = os.read(r, 1 << 20)
            if not chunk:
                break
            data += chunk
        os.close(r)
        _, status = os.waitpid(pid, 0)
        if os.WIFSIGNALED(status):
            return 'timeout' if os.WTERMSIG(status) == signal.SIGALRM else 'trap'
        return decode(data[8:])


def decode(data):
    n = int.from_bytes(data[0:4], 'little', signed=True)
    if n < 0:
        return None
    return [int.from_bytes(data[4 + 4 * i:8 + 4 * i], 'little', signed=True) for i in range(n)]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('workdir')
    parser.add_argument('--cases', default='formal/tools/frontend_cases')
    parser.add_argument('--laniusc', default='target/release/laniusc')
    parser.add_argument('--heap-log2', type=int, default=32)
    parser.add_argument('--timeout', type=int, default=600)
    parser.add_argument('--fixpoint', action='store_true',
                        help='also give the self-built compiler its own source, which must give its own image')
    args = parser.parse_args()
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

    def parse(base):
        tree = so.parse_tree(args.laniusc, base + '.lani', files_dir)
        if tree is None:
            return False
        open(base + '.prods', 'w').write(' '.join(map(str, tree[0])))
        open(base + '.parents', 'w').write(' '.join(map(str, tree[1])))
        return True

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
    for case in sorted(os.listdir(args.cases)):
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
        tests.append(dict(name='the verified compiler itself', bases=self_bases))
    manifest = [f'compile self {" ".join(self_bases)}']
    for k, t in enumerate(tests):
        manifest += [f'compile t{k} {" ".join(t["bases"])}', f'dump in{k} {" ".join(t["bases"])}']
    manifest_path = os.path.join(workdir, 'manifest.txt')
    open(manifest_path, 'w').write('\n'.join(manifest) + '\n')
    env = dict(os.environ, PATH=os.path.expanduser('~/.elan/bin') + ':' + os.environ['PATH'])
    built = subprocess.run(['systemd-run', '--user', '--scope', '-q', '-p', 'MemoryMax=6G', '-p', 'MemorySwapMax=0',
                            'lake', 'build', 'runAll'], cwd='formal', env=env, capture_output=True, text=True)
    if built.returncode != 0:
        raise SystemExit('lake build runAll failed:\n' + built.stdout[-4000:] + built.stderr[-4000:])
    lean = subprocess.run(['systemd-run', '--user', '--scope', '-q', '-p', 'MemoryMax=10G', '-p', 'MemorySwapMax=0',
                           'formal/.lake/build/bin/runAll', manifest_path], env=env, capture_output=True, text=True)
    if lean.returncode != 0:
        raise SystemExit('runAll failed:\n' + lean.stdout[-4000:] + lean.stderr[-4000:])
    status, inputs = {}, {}
    for line in lean.stdout.split('\n'):
        if not line:
            continue
        name, rest = line.split(' ', 1)
        if name.startswith('in'):
            k = int(name[2:])
            if rest == 'nolex':
                inputs[k] = None
            elif inputs.get(k, []) is not None:
                inputs.setdefault(k, []).append(parse_dump(rest[5:]))
        else:
            status[name] = rest
    self_status = status.get('self', 'missing')
    if not self_status.startswith('image'):
        raise SystemExit(f'the verified compiler does not compile itself: {self_status}')
    self_words = expected_words(self_status)
    entries = self_words[1:1 + self_words[0]]
    image = self_words[2 + self_words[0]:]
    print(f'self-built verified compiler: {len(image)} bytes, {len(entries)} functions')
    open(os.path.join(workdir, 'self.image'), 'wb').write(bytes(image))

    heap_size = 1 << args.heap_log2
    native = Native(max(1 << 22, len(image) + 4096), heap_size)
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

    problems, agree = [], 0
    for k, t in enumerate(tests):
        want = expected_words(status.get(f't{k}', 'missing'))
        if inputs.get(k) is None:
            problems.append(f'{t["name"]}: the Lean lexer rejects it')
            continue
        words = layout(inputs[k])
        native.load(entries, image, heap_size - 4 * (len(words) + room) - 8192)
        got_self = native.run(words, room, args.timeout)
        stdin = b''.join(x.to_bytes(4, 'little') for x in [len(words), room] + words)
        try:
            run = subprocess.run([exe], input=stdin, capture_output=True, timeout=args.timeout)
            got_laniusc = decode(run.stdout) if run.returncode == 0 else f'exit {run.returncode}'
        except subprocess.TimeoutExpired:
            got_laniusc = 'timeout'
        if got_self == want and got_laniusc == want:
            agree += 1
        else:
            show = lambda v: v if not isinstance(v, list) else f'{len(v)} words'  # noqa: E731
            problems.append(f'{t["name"]}: Lean {show(want)}, self {show(got_self)}, laniusc {show(got_laniusc)}'
                            + ('' if not (isinstance(want, list) and isinstance(got_self, list)) or want == got_self
                               else ' (self differs from Lean)'))
    for line in problems:
        print(line)
    accepted = sum(1 for k in range(len(tests)) if expected_words(status.get(f't{k}', '')) is not None)
    print(f'{len(tests)} programs ({accepted} compiled, {len(tests) - accepted} rejected): {agree} agree three ways, '
          f'{len(problems)} problems')
    return 1 if problems else 0


if __name__ == '__main__':
    sys.exit(main())
