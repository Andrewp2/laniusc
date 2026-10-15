#!/usr/bin/env python3
"""Per-thread local array bytes of SPIR-V compute kernels.

usage: tools/spv_local_bytes.py [--vars] [--min BYTES] PATH...

Each PATH is a .spv file or a directory searched for them (the release
artifacts are in target/laniusc-shader-artifacts/release/shaders). Prints
`<bytes> <path>` for every kernel with at least --min bytes (default 1),
largest first; --vars also lists the arrays behind each figure.

This is the same measure as `local_bytes` in crates/laniusc-shaders/spirv_size.rs,
which the shader build writes to inlined_sizes.txt and checks against
crates/laniusc-shaders/local_array_budget.txt. Use this script on single
modules outside the build (a slangc run in a scratch directory, an older
artifact tree). The rules:

- A local array is an OpVariable in Function or Private storage whose type is an
  array or a struct holding one.
- Only written arrays count: stored through an element pointer, given a whole
  store of a runtime value, copied into, passed to a call, or initialized with
  a runtime value. A table that only ever holds constants is not counted; the
  driver keeps it out of local memory (P9 measured 0 bytes for such tables).
- A function's arrays are live for the whole function: they add to those of
  the callee that needs the most, and sibling calls reuse the same space. The
  kernel's figure is that deepest call chain from its entry point plus its
  Private arrays.
- A helper call whose arguments are all constants (a table row constructor)
  counts as a constant.

The figure is what the kernel declares. The driver's own figure (measured by
`shader_dispatch_replay --memory-probe`) also includes register spills and
call frames, and leaves out small arrays it can keep in registers.
"""
import argparse
import pathlib
import struct
import sys

OP_NAME, OP_ENTRY_POINT, OP_FUNCTION, OP_FUNCTION_END, OP_FUNCTION_CALL = 5, 15, 54, 56, 57
OP_TYPE_BOOL, OP_TYPE_INT, OP_TYPE_FLOAT, OP_TYPE_VECTOR, OP_TYPE_MATRIX = 20, 21, 22, 23, 24
OP_TYPE_ARRAY, OP_TYPE_STRUCT, OP_TYPE_POINTER = 28, 30, 32
OP_CONSTANT_TRUE, OP_CONSTANT_FALSE, OP_CONSTANT, OP_CONSTANT_COMPOSITE, OP_CONSTANT_NULL = 41, 42, 43, 44, 46
OP_VARIABLE, OP_STORE, OP_COPY_MEMORY, OP_COPY_MEMORY_SIZED = 59, 62, 63, 64
POINTER_OPS = {65, 66, 67, 70, 83}  # access chains and OpCopyObject
OP_COMPOSITE_CONSTRUCT = 80
STORAGE_PRIVATE, STORAGE_FUNCTION = 6, 7


def literal_string(words):
    raw = b''.join(struct.pack('<I', w) for w in words)
    return raw.split(b'\0', 1)[0].decode('utf-8', 'replace')


def measure(path):
    """Returns (bytes, [(bytes, function name, variable name)]) or None.

    The list holds the arrays that make up the figure: those of the functions
    on the deepest call chain, and the Private ones.
    """
    data = pathlib.Path(path).read_bytes()
    if len(data) < 20:
        return None
    words = struct.unpack('<%dI' % (len(data) // 4), data[:len(data) // 4 * 4])
    if words[0] != 0x07230203:
        return None
    names, callees, entries = {}, {}, []
    types, pointers, integers, constants = {}, {}, {}, set()
    arrays, roots = {}, {}
    current = None
    at = 5
    while at < len(words):
        count, op = words[at] >> 16, words[at] & 0xffff
        if count == 0 or at + count > len(words):
            raise ValueError(f'{path}: malformed SPIR-V instruction at word {at}')
        ops = words[at + 1:at + count]
        if op == OP_NAME and len(ops) >= 2:
            names[ops[0]] = literal_string(ops[1:])
        elif op == OP_ENTRY_POINT and len(ops) >= 2:
            entries.append(ops[1])
        elif op == OP_FUNCTION:
            current = ops[1]
            callees[current] = []
        elif op == OP_FUNCTION_END:
            current = None
        elif op == OP_FUNCTION_CALL and len(ops) >= 3:
            if current is not None:
                callees[current].append(ops[2])
            for argument in ops[3:]:
                root = roots.get(argument)
                if root is not None:
                    arrays[root]['written'] = True
            # A constructor of constants (a table row built by a helper) folds
            # to a constant once inlined.
            if len(ops) > 3 and all(argument in constants for argument in ops[3:]):
                constants.add(ops[1])
        elif op == OP_TYPE_BOOL and ops:
            types[ops[0]] = (4, False)
        elif op in (OP_TYPE_INT, OP_TYPE_FLOAT) and len(ops) >= 2:
            types[ops[0]] = ((ops[1] + 7) // 8, False)
        elif op in (OP_TYPE_VECTOR, OP_TYPE_MATRIX) and len(ops) >= 3:
            element, array = types.get(ops[1], (4, False))
            types[ops[0]] = (element * ops[2], array)
        elif op == OP_TYPE_ARRAY and len(ops) >= 3:
            element = types.get(ops[1], (4, False))[0]
            types[ops[0]] = (element * integers.get(ops[2], 0), True)
        elif op == OP_TYPE_STRUCT and ops:
            members = [types.get(m, (4, False)) for m in ops[1:]]
            types[ops[0]] = (sum(m[0] for m in members), any(m[1] for m in members))
        elif op == OP_TYPE_POINTER and len(ops) >= 3:
            pointers[ops[0]] = (ops[1], ops[2])
        elif op == OP_CONSTANT and len(ops) >= 3:
            integers[ops[1]] = ops[2]
            constants.add(ops[1])
        elif op in (OP_CONSTANT_TRUE, OP_CONSTANT_FALSE, OP_CONSTANT_COMPOSITE, OP_CONSTANT_NULL) and len(ops) >= 2:
            constants.add(ops[1])
        elif op == OP_COMPOSITE_CONSTRUCT and len(ops) >= 2:
            if all(part in constants for part in ops[2:]):
                constants.add(ops[1])
        elif op == OP_VARIABLE and len(ops) >= 3:
            storage, pointee = pointers.get(ops[0], (None, None))
            if storage in (STORAGE_FUNCTION, STORAGE_PRIVATE) and types.get(pointee, (0, False))[1]:
                arrays[ops[1]] = {
                    'bytes': types[pointee][0],
                    'function': current if storage == STORAGE_FUNCTION else None,
                    'written': len(ops) >= 4 and ops[3] not in constants,
                }
                roots[ops[1]] = ops[1]
        elif op in POINTER_OPS and len(ops) >= 3:
            if ops[2] in roots:
                roots[ops[1]] = roots[ops[2]]
        elif op == OP_STORE and len(ops) >= 2:
            if not (ops[0] in arrays and ops[1] in constants):
                root = roots.get(ops[0])
                if root is not None:
                    arrays[root]['written'] = True
        elif op in (OP_COPY_MEMORY, OP_COPY_MEMORY_SIZED) and ops:
            root = roots.get(ops[0])
            if root is not None:
                arrays[root]['written'] = True
        at += count

    own = {f: 0 for f in callees}
    private = 0
    for array in arrays.values():
        if array['written']:
            if array['function'] in own:
                own[array['function']] += array['bytes']
            else:
                private += array['bytes']
    inlined = {}

    def total(f, stack=()):
        if f in inlined:
            return inlined[f]
        if f in stack:
            raise ValueError(f'{path}: recursive call through {names.get(f, f)}')
        inlined[f] = own.get(f, 0) + max((total(c, stack + (f,)) for c in callees.get(f, ())), default=0)
        return inlined[f]

    best = max(entries, key=total, default=None)
    # The deepest call chain from the widest entry point.
    chain = []
    f = best
    while f is not None:
        chain.append(f)
        f = max(callees.get(f, ()), key=total, default=None)
    detail = []
    for var, array in arrays.items():
        if array['written'] and (array['function'] is None or array['function'] in chain):
            where = 'Private' if array['function'] is None else names.get(array['function'], f"%{array['function']}")
            detail.append((array['bytes'], where, names.get(var, f'%{var}')))
    detail.sort(key=lambda d: -d[0])
    return (total(best) if best is not None else 0) + private, detail


def main():
    parser = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    parser.add_argument('paths', nargs='+')
    parser.add_argument('--min', type=int, default=1)
    parser.add_argument('--vars', action='store_true')
    args = parser.parse_args()
    files = []
    for p in map(pathlib.Path, args.paths):
        files += sorted(p.rglob('*.spv')) if p.is_dir() else [p]
    rows = []
    for f in files:
        result = measure(f)
        if result is not None and result[0] >= args.min:
            rows.append((result[0], str(f), result[1]))
    rows.sort(key=lambda r: (-r[0], r[1]))
    for b, f, detail in rows:
        print(b, f)
        if args.vars:
            for size, function, var in detail:
                print(f'    {size:6d}  {function}: {var}')
    print(f'{len(rows)} of {len(files)} modules have at least {args.min} local bytes', file=sys.stderr)


if __name__ == '__main__':
    main()
