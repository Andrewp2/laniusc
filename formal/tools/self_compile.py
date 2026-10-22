#!/usr/bin/env python3
"""Step 11, milestone M11a: the mini compiler's encoder, compiled by the
verified compiler itself, agrees with laniusc's build and with the Lean
definitions.

    python3 -I formal/tools/self_compile.py WORKDIR [--count N] [--seed S] [--laniusc PATH]

Run from the repository root. Each test is an entry `w() -> i32` in a module
that imports `mini::compiler` (formal/lani/mini/compiler.lani) and encodes a
random list of instructions with `encode_from`; the entry returns a digest of
the bytes (acc * 31 + byte over u32, from 7) and a second entry returns their
count. Three ways:

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
import os
import random
import re
import shutil
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
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


def test_text(t, part):
    """The test module: the digest (part 0) or the count (part 1) of the bytes."""
    entries = usize_list(t['entries'])
    place = f'{M}Place {{ body: {t["body"]}, slots: {t["slots"]}, entries: {entries} }}'
    call = f'{M}encode_from({place}, {t["pc"]}, {lani_instr_list(t["instrs"])})'
    if part == 0:
        helper = ['fn oracle_helper(xs: mini::compiler::List<u8>, acc: u32) -> u32 {',
                  '    return match (xs) {',
                  '        Nil -> acc,',
                  '        Cons(b, rest) -> oracle_helper(mini::compiler::unbox(rest), acc * 31 + (b as u32)),',
                  '    };', '}']
        body = f'    return oracle_helper({call}, 7) as i32;'
    else:
        helper = ['fn oracle_helper(xs: mini::compiler::List<u8>) -> i32 {',
                  '    return mini::compiler::length(xs) as i32;', '}']
        body = f'    return oracle_helper({call});'
    none = ['fn oracle_flag() -> mini::compiler::List<usize> {', '    return mini::compiler::empty();', '}']
    # `w` comes first: the native run calls the first root's entry.
    lines = ['module app::main;', 'import mini::compiler;', '', 'fn w() -> i32 {', body, '}', ''] + \
        helper + [''] + none
    return '\n'.join(lines) + '\n'


def lean_test(t):
    place = f'{{ body := {t["body"]}, slots := {t["slots"]}, entries := {lean_list(t["entries"])} }}'
    return f'encodeFrom {place} {t["pc"]} [{", ".join(lean_instr(i) for i in t["instrs"])}]'


# M11b: compile_program on mini_difftest's random programs.
PROGRAM_HELPERS = md.LANI_HEAD.split('fn put(')[0].split('import std::io_byte;\n')[1].strip().split('\n')


def program_text(funcs, part):
    """The digest (part 0) or the count (part 1) of compile_program's image;
    -1 for none."""
    fs = 'no_funcs()'
    for p, r, l, b in reversed(funcs):
        fs = f'{M}cons(func({p}, {r}, {l}, {md.lani_stmt(b)}), {fs})'
    if part == 0:
        digest_lines = ['fn oracle_digest(xs: mini::compiler::List<u8>, acc: u32) -> u32 {',
                        '    return match (xs) {',
                        '        Nil -> acc,',
                        '        Cons(b, rest) -> oracle_digest(mini::compiler::unbox(rest), acc * 31 + (b as u32)),',
                        '    };', '}', '']
        some = 'oracle_digest(binary.image, 7) as i32'
    else:
        digest_lines, some = [], f'{M}length(binary.image) as i32'
    lines = ['module app::main;', 'import core::option;', 'import mini::compiler;', '',
             'fn w() -> i32 {', f'    return oracle_helper({M}compile_program(prog()));', '}', '',
             f'fn oracle_helper(result: core::option::Option<{M}Binary>) -> i32 {{',
             '    return match (result) {', f'        Some(binary) -> {some},', '        None -> 0 - 1,', '    };', '}',
             ''] + digest_lines + \
        [f'fn prog() -> {M}Program {{ return {M}Program {{ funcs: {fs} }}; }}', ''] + PROGRAM_HELPERS
    return '\n'.join(lines) + '\n'


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
    parser = argparse.ArgumentParser()
    parser.add_argument('workdir')
    parser.add_argument('--count', type=int, default=20)
    parser.add_argument('--seed', type=int, default=1)
    parser.add_argument('--chunk', type=int, default=40)
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
            tree = so.parse_tree(args.laniusc, base + '.lani', files_dir)
            if tree is not None:
                open(base + '.prods', 'w').write(' '.join(map(str, tree[0])))
                open(base + '.parents', 'w').write(' '.join(map(str, tree[1])))
            parsed[base] = tree is not None
        return parsed[base]

    dep_bases = []
    for dep in deps:
        b = os.path.join(files_dir, dep.replace('::', '__'))
        shutil.copy(mods[dep].path, b + '.lani')
        if not parse(b):
            raise SystemExit(f'laniusc does not parse {dep}')
        dep_bases.append(b)

    if args.stage == 'encode':
        tests = [gen_test(rng) for _ in range(args.count)]
        text, lean_text = test_text, lambda t: f'toString (({lean_test(t)}).map (·.toNat))'
    else:
        tests = [md.gen_program(rng, rng.random() < 0.2) for _ in range(args.count)]
        text, lean_text = program_text, lean_program
    programs = []
    for k, t in enumerate(tests):
        for part in (0, 1):
            base = os.path.join(workdir, f'p{len(programs)}')
            open(base + '.lani', 'w').write(text(t, part))
            programs.append(dict(test=k, part=part, base=base))
    manifest = []
    for j, p in enumerate(programs):
        if not parse(p['base']):
            raise SystemExit(f'laniusc does not parse {p["base"]}.lani')
        manifest.append(f'p{j} ' + ' '.join([p['base']] + dep_bases))
    open(os.path.join(workdir, 'manifest.txt'), 'w').write('\n'.join(manifest) + '\n')

    # Lean: the front end and compileSource on each program, and the
    # extracted encoder on each test.
    lean_path = os.path.join(workdir, 'self_compile.lean')
    expected = '\n'.join(f'#eval IO.println ("t{k} " ++ ({lean_text(t)}))' for k, t in enumerate(tests))
    open(lean_path, 'w').write(so.LEAN + f'\n#eval runAll "{os.path.join(workdir, "manifest.txt")}"\n\n'
                               + expected + '\n')
    env = dict(os.environ, PATH=os.path.expanduser('~/.elan/bin') + ':' + os.environ['PATH'])
    lean = subprocess.run(['systemd-run', '--user', '--scope', '-q', '-p', 'MemoryMax=8G', '-p', 'MemorySwapMax=0',
                           'lake', 'env', 'lean', lean_path], cwd='formal', env=env, capture_output=True, text=True)
    if lean.returncode != 0:
        raise SystemExit('lean failed:\n' + lean.stdout[-4000:] + lean.stderr[-4000:])
    status, want = {}, {}
    for line in lean.stdout.strip().split('\n'):
        name, rest = line.split(' ', 1)
        if name.startswith('p'):
            status[int(name[1:])] = rest
        else:
            want[int(name[1:])] = None if rest == 'none' else [int(x) for x in re.findall(r'\d+', rest)]

    problems = []
    native = Native()
    for j, p in enumerate(programs):
        s = status.get(j, 'missing')
        if not s.startswith('image'):
            problems.append(f'test {p["test"]} part {p["part"]}: the verified compiler: {s.split(" ")[0]}')
            p['self'] = None
            continue
        entries_s, image_s = re.match(r'image \[(.*?)\] \[(.*?)\]$', s).groups()
        native.load([int(x) for x in entries_s.split(',')], bytes(int(x) for x in image_s.split(',')), 0)
        p['self'] = so.native_call(native, [], [])

    # laniusc: every program in harness binaries (stdlib_oracle's harness).
    for p in programs:
        p['wparams'] = []
    results = []
    for start in range(0, len(programs), args.chunk):
        chunk = programs[start:start + args.chunk]
        for p in chunk:
            p['calls'], p['native'] = [[]], [p['self'] if p['self'] is not None else 0]
        results += so.laniusc_chunk(args, workdir, chunk, start, mods)

    agree = 0
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
