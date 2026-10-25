#!/usr/bin/env python3
"""Step 11, milestone M11a: the mini compiler's encoder, compiled by the
verified compiler itself, agrees with laniusc's build and with the Lean
definitions.

    python3 -I formal/tools/self_compile.py WORKDIR [--stage encode|program] [--count N] [--seed S] [--laniusc PATH]

Run from the repository root. All tests sit in one module that imports
`mini::compiler` (formal/lani/mini/compiler.lani), so each side compiles it
once. Test k is two entries, `w(2k)` returning a digest of some bytes
(acc * 31 + byte over u32, from 7) and `w(2k+1)` their count. With
`--stage encode` (M11a) the bytes are `encode_from` of a random list of
instructions; with `--stage program` (M11b) they are `compile_program`'s
image of a random mini IR program from mini_difftest.py (-1 for none).
Three ways:

  self       the front end (`frontEndFiles`, on laniusc's parse trees of the
             test module, compiler.lani and the stdlib modules it imports)
             and `compileSource`, run natively under oracle_difftest's stub;
  laniusc    the same test module built by laniusc;
  Lean       `#eval` of `encodeFrom` in Lanius/Mini/Compiler.lean (the
             extracted definitions), digested here.

All three must agree on every test. Prints a summary; exits nonzero on any
difference or if the verified compiler rejects a test.
"""

import argparse
import ctypes
import mmap
import os
import random
import re
import shutil
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import run_cache  # noqa: E402
import mini_difftest as md  # noqa: E402
import stdlib_oracle as so  # noqa: E402

M = 'mini::compiler::'
WORDS = ['S32', 'U64']
BINOPS = ['Add', 'Sub', 'Mul', 'And', 'Or', 'Xor', 'Shl', 'Shr', 'Sar']
CMPOPS = ['Eq', 'Ne', 'Lt', 'Le', 'Gt', 'Ge']
DIVOPS = ['SDiv', 'SRem', 'UDiv', 'URem']
WIDTHS = ['M32', 'M64']


class Native(so.Native):
    HEAP = 1 << 26

    def __init__(self):
        super().__init__()
        # Room for an image of many tests.
        self.code = mmap.mmap(-1, 1 << 26, prot=mmap.PROT_READ | mmap.PROT_WRITE | mmap.PROT_EXEC)
        self.base = ctypes.addressof(ctypes.c_char.from_buffer(self.code))


def lower_first(name):
    return name[:1].lower() + name[1:]


def gen_instr(rng, functions):
    """An instruction as (Lanius text, Lean text)."""
    slot = rng.randrange(40)
    k = rng.choice(['Imm', 'Load', 'Store', 'Neg', 'Op', 'Op', 'Cmp', 'Jmp', 'Jz', 'Call', 'Ret', 'Bump',
                    'LoadAt', 'StoreAt', 'LoadWordAt', 'StoreWordAt', 'Div'])
    if k == 'Imm':
        v = rng.choice([0, 1, 255, 65535, 2 ** 31 - 1, rng.randrange(2 ** 31)])
        return f'{M}Imm(({v} as u64) << {rng.choice([0, 8, 32])})', None, ('imm', v)
    if k in ('Load', 'Store', 'Jmp', 'Jz', 'StoreAt', 'Bump'):
        n = rng.randrange(60) if k != 'Bump' else rng.randrange(13)
        return f'{M}{k}({n})', f'(.{lower_first(k)} {n})', None
    if k in ('Neg', 'LoadAt'):
        return f'{M}Instr::{k}' if k == 'Neg' else f'{M}{k}', f'.{lower_first(k)}', None
    if k in ('Op', 'Cmp', 'Div'):
        ops = {'Op': BINOPS, 'Cmp': CMPOPS, 'Div': DIVOPS}[k]
        w, o = rng.choice(WORDS), rng.choice(ops)
        return (f'{M}{k}({M}{w}, {M}{o}, {slot})', f'(.{lower_first(k)} .{w.lower()} .{lower_first(o)} {slot})',
                None)
    if k == 'LoadWordAt':
        w = rng.choice(WIDTHS)
        return f'{M}LoadWordAt({M}{w})', f'(.loadWordAt .{w.lower()})', None
    if k == 'StoreWordAt':
        w = rng.choice(WIDTHS)
        return f'{M}StoreWordAt({M}{w}, {slot})', f'(.storeWordAt .{w.lower()} {slot})', None
    if k == 'Call':
        args = [rng.randrange(20) for _ in range(rng.randrange(4))]
        callee, target, count = rng.randrange(functions), rng.randrange(20), rng.randrange(1, 3)
        return (f'{M}Instr::Call({callee}, {usize_list(args)}, {target}, {count})',
                f'(.call {callee} {lean_list(args)} {target} {count})', None)
    sources = [rng.randrange(20) for _ in range(rng.randrange(1, 4))]
    return f'{M}Instr::Ret({usize_list(sources)})', f'(.ret {lean_list(sources)})', None


def lani_list(items):
    """A Lanius list expression; the empty list is the oracle_flag() helper."""
    text = None
    for x in reversed(items):
        text = f'{M}single({x})' if text is None else f'{M}cons({x}, {text})'
    return text or 'oracle_flag()'


def usize_list(xs):
    return lani_list([f'({x} as usize)' for x in xs])


def lean_list(xs):
    return '[' + ', '.join(str(x) for x in xs) + ']'


def gen_test(rng):
    functions = rng.randint(1, 4)
    entries = sorted(rng.randrange(1000) for _ in range(functions))
    instrs = [gen_instr(rng, functions) for _ in range(rng.randint(1, 6))]
    return dict(body=rng.randrange(500), slots=rng.randrange(1, 40), entries=entries,
                pc=rng.randrange(200), instrs=instrs)


def lani_instr_list(instrs):
    text = None
    for lani, _, _ in reversed(instrs):
        text = f'{M}single({lani})' if text is None else f'{M}cons({lani}, {text})'
    return text


def lean_instr(i):
    lani, lean, imm = i
    if imm is not None:
        shift = int(re.search(r'<< (\d+)\)$', lani).group(1))
        return f'(.imm (BitVec.ofNat 64 {(imm[1] << shift) % 2 ** 64}))'
    return lean


DIGEST = ['fn oracle_digest(xs: mini::compiler::List<u8>, acc: u32) -> u32 {',
          '    return match (xs) {',
          '        Nil -> acc,',
          '        Cons(b, rest) -> oracle_digest(mini::compiler::unbox(rest), acc * 31 + (b as u32)),',
          '    };', '}', '']


def encode_parts(k, t):
    """Test k's two entries, the digest and the count of the bytes, and the
    functions they share."""
    entries = usize_list(t['entries'])
    place = f'{M}Place {{ body: {t["body"]}, slots: {t["slots"]}, entries: {entries} }}'
    call = f'{M}encode_from({place}, {t["pc"]}, {lani_instr_list(t["instrs"])})'
    return ([f'    return oracle_digest(oracle_bytes{k}(), 7) as i32;', f'    return {M}length(oracle_bytes{k}()) as i32;'],
            [f'fn oracle_bytes{k}() -> {M}List<u8> {{', f'    return {call};', '}', ''])


ENCODE_HELPERS = DIGEST + ['fn oracle_flag() -> mini::compiler::List<usize> {', '    return mini::compiler::empty();', '}']


def lean_test(t):
    place = f'{{ body := {t["body"]}, slots := {t["slots"]}, entries := {lean_list(t["entries"])} }}'
    return f'encodeFrom {place} {t["pc"]} [{", ".join(lean_instr(i) for i in t["instrs"])}]'


# M11b: compile_program on mini_difftest's random programs.
PROGRAM_HELPERS = md.LANI_HEAD.split('fn put(')[0].split('import std::io_byte;\n')[1].strip().split('\n')


def program_parts(k, funcs):
    """Test k's two entries, the digest and the count of compile_program's
    image (-1 for none), and its program."""
    fs = 'no_funcs()'
    for p, r, l, b in reversed(funcs):
        fs = f'{M}cons(func({p}, {r}, {l}, {md.lani_stmt(b)}), {fs})'
    run = f'{M}compile_program(oracle_prog{k}())'
    return ([f'    return oracle_digest_of({run});', f'    return oracle_count_of({run});'],
            [f'fn oracle_prog{k}() -> {M}Program {{ return {M}Program {{ funcs: {fs} }}; }}', ''])


PROGRAM_HELPERS = DIGEST + [
    f'fn oracle_digest_of(result: core::option::Option<{M}Binary>) -> i32 {{',
    '    return match (result) {', '        Some(binary) -> oracle_digest(binary.image, 7) as i32,', '        None -> 0 - 1,',
    '    };', '}', '',
    f'fn oracle_count_of(result: core::option::Option<{M}Binary>) -> i32 {{',
    '    return match (result) {', f'        Some(binary) -> {M}length(binary.image) as i32,', '        None -> 0 - 1,',
    '    };', '}', ''] + md.LANI_HEAD.split('fn put(')[0].split('import std::io_byte;\n')[1].strip().split('\n')


def module_text(tests, parts, helpers, imports):
    """One module holding every test: entries w0, w1, ... first (their ids are
    their positions), then the shared helpers and each test's data."""
    lines = ['module app::main;'] + [f'import {m};' for m in imports] + ['']
    data = []
    for k, t in enumerate(tests):
        bodies, extra = parts(k, t)
        for part, body in enumerate(bodies):
            lines += [f'fn w{2 * k + part}() -> i32 {{', body, '}', '']
        data += extra
    return '\n'.join(lines + helpers + [''] + data) + '\n'


def lean_program(funcs):
    fs = ', '.join(f'{{ params := {p}, results := {r}, locals := {l}, body := {md.lean_stmt(b)} }}'
                   for p, r, l, b in funcs)
    return (f'match compileProgram {{ funcs := [{fs}] }} with | none => "none" '
            f'| some b => toString (b.image.map (·.toNat))')


def digest(bs):
    acc = 7
    for b in bs:
        acc = (acc * 31 + b) % 2 ** 32
    return acc - 2 ** 32 if acc >= 2 ** 31 else acc


def main():
    run_cache.no_core_dumps()
    parser = argparse.ArgumentParser()
    parser.add_argument('workdir')
    parser.add_argument('--count', type=int, default=20)
    parser.add_argument('--seed', type=int, default=1)
    parser.add_argument('--laniusc', default='target/release/laniusc')
    parser.add_argument('--stage', choices=['encode', 'program'], default='encode',
                        help='M11a: encode_from on random instructions; M11b: compile_program on random programs')
    args = parser.parse_args()
    rng = random.Random(args.seed)
    workdir = os.path.abspath(args.workdir)
    os.makedirs(workdir, exist_ok=True)

    # A stdlib root that also holds mini/compiler.lani, for laniusc and the scan.
    root = os.path.join(workdir, 'root')
    shutil.rmtree(root, ignore_errors=True)
    shutil.copytree('stdlib', root)
    os.makedirs(os.path.join(root, 'mini'))
    shutil.copy('formal/lani/mini/compiler.lani', os.path.join(root, 'mini', 'compiler.lani'))
    so.STDLIB = root
    mods = so.load_modules()
    deps = so.closure(mods, 'mini::compiler')
    files_dir = os.path.join(workdir, 'files')
    os.makedirs(files_dir, exist_ok=True)

    parsed = {}

    def parse(base):
        if base not in parsed:
            parsed[base] = so.parse_checked(args.laniusc, base, files_dir)
        return parsed[base]

    so.build_run_all()
    dep_bases = []
    for dep in deps:
        b = os.path.join(files_dir, dep.replace('::', '__'))
        shutil.copy(mods[dep].path, b + '.lani')
        if not parse(b):
            raise SystemExit(f'laniusc does not parse {dep}')
        dep_bases.append(b)

    if args.stage == 'encode':
        tests = [gen_test(rng) for _ in range(args.count)]
        parts, helpers, imports = encode_parts, ENCODE_HELPERS, ['mini::compiler']
        lean_text = lambda t: f'toString (({lean_test(t)}).map (·.toNat))'  # noqa: E731
    else:
        tests = [md.gen_program(rng, rng.random() < 0.2) for _ in range(args.count)]
        parts, helpers, imports = program_parts, PROGRAM_HELPERS, ['core::option', 'mini::compiler']
        lean_text = lean_program
    base = os.path.join(workdir, 'tests')
    text = module_text(tests, parts, helpers, imports)
    open(base + '.lani', 'w').write(text)
    if not parse(base):
        raise SystemExit(f'laniusc does not parse {base}.lani')
    open(os.path.join(workdir, 'manifest.txt'), 'w').write(' '.join(['compile', 'tests', base] + dep_bases) + '\n')

    # The front end and compileSource on the module, once (the compiled
    # runAll), and the extracted definitions on each test (Lean).
    run = subprocess.run([so.RUN_ALL, os.path.join(workdir, 'manifest.txt')], capture_output=True, text=True)
    status = run.stdout.strip().split(' ', 1)[1] if run.returncode == 0 and ' ' in run.stdout.strip() else None
    lean_path = os.path.join(workdir, 'self_compile.lean')
    expected = '\n'.join(f'#eval IO.println ("t{k} " ++ ({lean_text(t)}))' for k, t in enumerate(tests))
    open(lean_path, 'w').write('import Lanius.Mini.FrontLex\nopen Lanius.Mini\n\n' + expected + '\n')
    lean = run_cache.run_lean(lean_path, memory='8G')
    if lean.returncode != 0:
        raise SystemExit('lean failed:\n' + lean.stdout[-4000:] + lean.stderr[-4000:])
    want = {}
    for line in lean.stdout.strip().split('\n'):
        name, rest = line.split(' ', 1)
        want[int(name[1:])] = None if rest == 'none' else [int(x) for x in re.findall(r'\d+', rest)]
    if status is None or not status.startswith('image'):
        raise SystemExit(f'the verified compiler: {status}')

    entries_s, image_s = re.match(r'image \[(.*?)\] \[(.*?)\]$', status).groups()
    entries = [int(x) for x in entries_s.split(',')]
    image = bytes(int(x) for x in image_s.split(','))
    print(f'the verified compiler: {len(image)} image bytes, {len(entries)} functions')
    native = Native()
    programs = [dict(test=k, part=part) for k in range(len(tests)) for part in (0, 1)]
    for j, p in enumerate(programs):
        native.load(entries[j:], image, 0)
        p['self'] = so.native_call(native, [], [])

    # laniusc: the same module, with a main that writes each entry's result.
    harness = text.replace('module app::main;\n', 'module app::main;\nimport std::io_byte;\n', 1)
    harness += '\n'.join(so.oracle.LANI_HEAD.split('\n', 4)[4].split('\n')) + '\nfn main() -> i32 {\n'
    harness += ''.join(f'    put32(w{j}());\n' for j in range(len(programs))) + '    return 0;\n}\n'
    # mini::compiler from a source root: as a library unit under the stdlib
    # root, laniusc rejects some of its generic instances (LNC0017).
    exe = os.path.join(workdir, 'harness')
    open(exe + '.lani', 'w').write(harness)
    if os.path.exists(exe):
        os.remove(exe)
    build = subprocess.run(['systemd-run', '--user', '--scope', '-q', '-p', 'MemoryMax=6G', '-p', 'MemorySwapMax=0',
                            so.HEAVY, '-t', '20', args.laniusc, '--stdlib-root', 'stdlib', '--source-root', 'formal/lani',
                            '-o', exe, exe + '.lani'], capture_output=True, text=True)
    if build.returncode != 0 or not os.path.exists(exe):
        raise SystemExit('laniusc rejects the harness:\n' + build.stdout[-2000:] + build.stderr[-2000:])
    data = subprocess.run([exe], capture_output=True, timeout=600).stdout
    results = [[so.oracle.i32(int.from_bytes(data[4 * j:4 * j + 4], 'little')) if 4 * j + 4 <= len(data)
                else 'missing'] for j in range(len(programs))]

    problems, agree = [], 0
    for p, got in zip(programs, results):
        bs = want[p['test']]
        lean_value = -1 if bs is None else digest(bs) if p['part'] == 0 else len(bs)
        have = got[0]
        if p['self'] == lean_value and have == lean_value:
            agree += 1
        else:
            problems.append(f'test {p["test"]} part {p["part"]}: Lean {lean_value}, self {p["self"]}, laniusc {have}')
    for line in problems:
        print(line)
    total_bytes = sum(len(b) for b in want.values() if b is not None)
    print(f'{len(tests)} tests ({len(programs)} programs, {total_bytes} encoded bytes): {agree} agree three ways, '
          f'{len(problems)} problems')
    return 1 if problems else 0


if __name__ == '__main__':
    sys.exit(main())
