"""Exact source/runtime authority for native-linked Lanius executables.

Allocation pairs reuse the historical opcode definition; unsized host service
calls require a whole exact runtime block from the authoritative literal table.
All instruction extents are checked. CRT/bootstrap/DSOs and arbitrary executable
gaps are excluded. The unchanged live ledger handles requested-byte ownership.
"""
import ast
import importlib.util
from pathlib import Path
import re
import struct


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


HERE = Path(__file__).resolve().parent
ELF = load("native_source_linked_elf_validator", HERE / "validate_linked_elf.py")
RUNTIME = load("native_source_historical_opcode_definition", HERE.parent / "stdlib_foundation/resolve/allocation_sites.py")
TABLES = HERE.parent / "stdlib_foundation/raw_host_width_tables.py"
SHADER = HERE.parents[2] / "shaders/codegen/lir/x86/runtime_abi.slang"


def literal_arrays(path):
    # Import only this existing pure literal decoder, not the assembly oracle's
    # top-level native tool invocations. No runtime-byte scanner is copied.
    definitions = [node for node in ast.parse(TABLES.read_text()).body
                   if isinstance(node, ast.FunctionDef) and node.name == "literal_bytes"]
    ELF.check(len(definitions) == 1, "missing shared runtime literal decoder")
    namespace = dict(re=re)
    exec(compile(ast.Module(body=definitions, type_ignores=[]), str(TABLES), "exec"), namespace)
    text = Path(path).read_text()
    records = list(re.finditer(r"static const uint (\w+)\[(\d+)\]\s*=\s*\{(.*?)\};", text, re.S))
    return text, {record[1]: namespace["literal_bytes"](record) for record in records}


def runtime_bytes():
    text, arrays = literal_arrays(SHADER)
    data = b"".join(arrays.values())
    length = re.findall(r"static const uint X86_RUNTIME_LENGTH = (\d+)u;", text)
    ELF.check(len(length) == 1 and len(data) == int(length[0]), "runtime literal extent mismatch")
    tail = RUNTIME.RUNTIME.replace(bytes.fromhex("41ba62000000"), bytes.fromhex("41ba22000000"))
    ELF.check(data.count(tail) == 1, "runtime table lacks unique shared allocation tail")
    return data


def crt_bytes():
    text, arrays = literal_arrays(SHADER.with_name("crt_entry.slang"))
    ELF.check(set(arrays) == {"crt_entry_bytes"}, "unsupported CRT literal table")
    data = arrays["crt_entry_bytes"]
    ELF.check(len(data) == 225 and "X86_CRT_ENTRY_CALL_OFFSET = 181u;" in text,
              "unsupported CRT entry profile")
    return data


def _partition(inspected, source_ranges, runtime_ranges, crt=None):
    """Account for every image syscall, with exact dormant entry exceptions."""
    image, loads = inspected["image"], inspected["loads"]
    instructions, ends = inspected["runtime_instructions"], inspected["runtime_instruction_ends"]
    bridge = crt_bytes() if crt is None else crt
    ELF.check(len(bridge) == 225 and bridge[181:186] == b"\xe8\0\0\0\0",
              "unsupported exact CRT bridge")
    wrapper = bytes.fromhex("4989e7e80000000089c7b83c0000000f05")
    source = [(name, address, size) for name, address, size in inspected["functions"]
              if re.fullmatch(r"__lanius_\d+_\d+_\d+", name)]

    def contents(address, size):
        matches = [segment for segment in loads if segment[1] & 1 and address >= segment[3]
                   and size <= segment[5] and address - segment[3] <= segment[5] - size]
        ELF.check(len(matches) == 1, "entry/bridge lacks unique executable file backing")
        segment = matches[0]
        offset = segment[2] + address - segment[3]
        return image[offset:offset + size]

    def continuous(start, end):
        cursor = start
        while cursor < end:
            ELF.check(cursor in instructions and cursor in ends and cursor < ends[cursor] <= end,
                      "entry/bridge instruction extent is not contiguous")
            cursor = ends[cursor]
        ELF.check(cursor == end, "entry/bridge instruction extends past exact bytes")

    def target(data, start, call):
        return start + call + 5 + struct.unpack_from("<i", data, call + 1)[0]

    wrappers = []
    expression = re.escape(wrapper[:4]) + b".{4}" + re.escape(wrapper[8:])
    for segment in loads:
        if not segment[1] & 1:
            continue
        code = image[segment[2]:segment[2] + segment[5]]
        for found in re.finditer(expression, code, re.S):
            raw = segment[3] + found.start()
            continuous(raw, raw + len(wrapper))
            ELF.check(not any(raw < address + size and address < raw + len(wrapper) for _, address, size in inspected["symbols"] if size > 0),
                      "raw entry overlaps a sized function")
            wrappers.append((raw, target(found[0], raw, 3)))
    bootstrap, used, mains = {}, set(), []
    for runtime_start, runtime_end in runtime_ranges:
        crt_start = runtime_end
        actual_crt = contents(crt_start, len(bridge))
        entry_target = target(actual_crt, crt_start, 181)
        candidates = [(raw, destination) for raw, destination in wrappers if destination == entry_target]
        ELF.check(len(candidates) == 1 and candidates[0][0] not in used,
                  "runtime bridge lacks unique paired raw entry")
        raw = candidates[0][0]
        used.add(raw)
        ELF.check(actual_crt[:182] == bridge[:182] and actual_crt[186:] == bridge[186:],
                  "unrecognized CRT bootstrap bridge")
        continuous(crt_start, crt_start + len(bridge))
        aliases = [(name, address, size) for name, address, size in inspected["symbols"]
                   if size > 0 and crt_start < address + size and address < crt_start + len(bridge)]
        if aliases:
            ELF.check(aliases == [("main", crt_start, len(bridge))], "CRT bridge overlaps another sized symbol")
            ELF.check(entry_target in {address for _, address, _ in source}, "main bridge does not call its sized source entry")
            mains.append(crt_start)
        else:
            # Library objects retain an inert raw entry/CRT trailer whose
            # unsigned missing-entry offset points at raw+16. It is not a
            # callable source entry or permission to execute arbitrary bytes.
            ELF.check(entry_target == raw + 16, "unsupported dormant library entry target")
        for position, name in ((15, "entry-exit"),):
            address = raw + position
            ELF.check(instructions.get(address, (None,))[0] == "syscall", "raw exit lacks exact syscall boundary")
            bootstrap[address + 2] = name
        for position, name in ((129, "bootstrap-mmap"), (199, "bootstrap-munmap")):
            address = crt_start + position
            ELF.check(instructions.get(address, (None,))[0] == "syscall", "CRT syscall lacks exact boundary")
            bootstrap[address + 2] = name
    ELF.check(len(mains) == 1 and used == {raw for raw, _ in wrappers}, "missing unique main or unpaired source unit")
    source_sites = {address + 2 for address, operation in instructions.items() if operation[0] == "syscall"
                    and any(low <= address < high for low, high in source_ranges)}
    ELF.check(all(any(low <= site < high for low, high in source_ranges) for site in source_sites),
              "source syscall post-IP escapes source/runtime authority")
    image_sites = {address + 2 for address, operation in instructions.items() if operation[0] == "syscall"}
    ELF.check(image_sites == source_sites | set(bootstrap), "unknown unsized image syscall outside source/runtime/bootstrap")
    ELF.check(not source_sites & set(bootstrap), "ambiguous source/bootstrap syscall authority")
    return source_sites, bootstrap


class RuntimePairs(list):
    pass


def _profile(inspected, runtime=None):
    image, loads = inspected["image"], inspected["loads"]
    instructions, ends = inspected["runtime_instructions"], inspected["runtime_instruction_ends"]
    current = runtime_bytes() if runtime is None else runtime
    old_flags, new_flags = bytes.fromhex("41ba62000000"), bytes.fromhex("41ba22000000")
    ELF.check(RUNTIME.RUNTIME.count(old_flags) == 1 and len(RUNTIME.SYSCALLS) == 2,
              "unsupported shared allocation opcode definition")
    tail = RUNTIME.RUNTIME.replace(old_flags, new_flags)
    ELF.check(current.count(tail) == 1, "runtime lacks unique exact allocation tail")
    tail_offset = current.index(tail)
    # The only historical variant changes the independently checked allocation
    # flag immediate. Every other byte, including all host thunks, must match.
    variants = ((current, 0x22), (current[:tail_offset] + RUNTIME.RUNTIME + current[tail_offset + len(tail):], 0x62))
    pairs, flags, helpers = set(), {}, []

    def executable(address, size):
        return size > 0 and any(segment[1] & 1 and address >= segment[3] and size <= segment[5]
                               and address - segment[3] <= segment[5] - size for segment in loads)

    functions = [(name, start, size) for name, start, size in inspected["functions"]
                 if re.fullmatch(r"__lanius_\d+_\d+_\d+", name)]
    ELF.check(functions, "missing sized Lanius source function authority")
    for name, start, size in functions:
        ELF.check(executable(start, size) and start in instructions,
                  f"{name}: invalid source function range")
    for segment in loads:
        _, permission, offset, start, _, size, memory, _ = segment
        ELF.check(0 <= offset <= len(image) and 0 <= size <= len(image) - offset and size <= memory,
                  "invalid allocation executable segment")
        ELF.check(permission & 3 != 3, "allocation segment is writable and executable")
        if not permission & 1:
            continue
        code = image[offset:offset + size]
        for pattern, mmap_flags in variants:
            at = code.find(pattern)
            while at >= 0:
                address, end = start + at, start + at + len(pattern)
                ELF.check(executable(address, len(pattern)), "runtime outside executable file bytes")
                ELF.check(not any(length > 0 and address < symbol + length and symbol < end
                                  for _, symbol, length in inspected["symbols"]),
                          "runtime overlaps a sized source/CRT function")
                cursor, covered = address, set()
                while cursor < end:
                    ELF.check(cursor in instructions and cursor in ends,
                              "runtime start/interior is not an instruction boundary")
                    covered.add(cursor)
                    following = ends[cursor]
                    ELF.check(cursor < following <= end, "runtime instruction crosses exact extent")
                    cursor = following
                ELF.check(cursor == end and covered == {point for point in instructions if address <= point < end},
                          "runtime instruction coverage is not contiguous")
                syscall_sites = tuple(address + tail_offset + position for position in RUNTIME.SYSCALLS)
                ELF.check(all(instructions.get(site, (None,))[0] == "syscall" for site in syscall_sites),
                          "allocation helper syscall is not an instruction boundary")
                pair = tuple(site + 2 for site in syscall_sites)
                ELF.check(pair[0] not in flags or flags[pair[0]] == mmap_flags, "ambiguous allocation flags")
                pairs.add(pair)
                flags[pair[0]] = mmap_flags
                helpers.append((address, end))
                at = code.find(pattern, at + 1)
    ELF.check(pairs, "no exact supported native runtime block")
    result = RuntimePairs(sorted(pairs))
    result.mmap_flags = flags
    result.executable_ranges = sorted(set((start, start + size) for _, start, size in functions) | set(helpers))
    result.source_syscall_sites, result.bootstrap_sites = _partition(inspected, result.executable_ranges, helpers)
    result.image_ranges = [(start, start + size) for _, permission, _, start, _, size, _, _ in loads if permission & 1]
    return result, []


def verified_sites(executable, directory=None):
    return _profile(ELF.inspect(Path(executable)))


def classify(profile, post_ip):
    """Never silently classify an unverified executable-image site as native."""
    pairs, named = profile
    ELF.check(not named, "native source authority cannot use named fallback")
    if post_ip in pairs.source_syscall_sites:
        return "source"
    if post_ip in pairs.bootstrap_sites:
        return pairs.bootstrap_sites[post_ip]
    ELF.check(not any(low <= post_ip < high or low <= post_ip - 2 < high for low, high in pairs.image_ranges),
              "observed unverified executable-image syscall post-IP")
    return "native"
