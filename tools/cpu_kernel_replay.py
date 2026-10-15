#!/usr/bin/env python3
"""Run one captured compute dispatch of a Lanius Slang kernel on the CPU.

usage:
  tools/cpu_kernel_replay.py check   CAPTURE [--source SRC]          CPU result vs the captured GPU result
  tools/cpu_kernel_replay.py compare CAPTURE [--a SRC] [--b SRC] [--kernel-b KEY]
                                                                     kernel A vs kernel B on the same inputs
  tools/cpu_kernel_replay.py run     CAPTURE [--source SRC] [--out DIR]
  tools/cpu_kernel_replay.py gdb     CAPTURE [--source SRC] [--break-dtid X[,Y,Z]] [-- GDB ARGS...]
  tools/cpu_kernel_replay.py build   KERNEL  [--source SRC]          only compile for the CPU

CAPTURE is a `LANIUS_DEBUG_CAPTURE_PASS` capture directory (see
docs/cpu-kernel-replay.md). The kernel comes from the capture's manifest unless
`--kernel KEY` (an artifact key such as type_checker/calls/03d_...) is given.
SRC selects the shader sources: `worktree` (default, this checkout's shaders/),
a git revision (HEAD, HEAD~1, stash@{0}, a sha) or a directory holding the
shader tree. `compare` defaults to --a HEAD --b worktree: your uncommitted
rewrite against the committed kernel.

Nothing here touches the GPU. slangc turns the kernel into C++ (with
tools/cpu_replay/lanius_cpu_shim.slang standing in for the atomics and
barriers its C++ backend lacks), g++ builds it with tools/cpu_replay into one
executable per source digest (cached under target/cpu-replay), and that runs
every workgroup of the captured dispatch.
"""
import argparse
import hashlib
import json
import os
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
TOOL_DIR = ROOT / "tools" / "cpu_replay"
CACHE = pathlib.Path(os.environ.get("LANIUS_CPU_REPLAY_CACHE", ROOT / "target" / "cpu-replay"))
SLANGC = os.environ.get("LANIUS_CPU_REPLAY_SLANGC", str(pathlib.Path.home() / ".local/bin/slangc"))
CXX = os.environ.get("CXX", "g++")
# Bump when the mirror rewrite, shim or build flags change meaning.
TOOL_VERSION = "1"

INTRINSICS = [
    "InterlockedAdd", "InterlockedAnd", "InterlockedOr", "InterlockedXor", "InterlockedMin",
    "InterlockedMax", "InterlockedExchange", "InterlockedCompareExchange", "InterlockedCompareStore",
    "GroupMemoryBarrierWithGroupSync", "DeviceMemoryBarrierWithGroupSync",
    "AllMemoryBarrierWithGroupSync", "GroupMemoryBarrier", "DeviceMemoryBarrier", "AllMemoryBarrier",
]
SHIM_IMPORT = "import lanius_cpu_shim; "


def log(message):
    print(f"cpu-replay: {message}", file=sys.stderr)


def fail(message):
    log(message)
    sys.exit(2)


def capped(command, memory):
    """Runs `command` under a systemd memory cap when systemd-run exists."""
    if shutil.which("systemd-run"):
        return ["systemd-run", "--user", "--scope", "-q", "-p", f"MemoryMax={memory}",
                "-p", "MemorySwapMax=0"] + command
    return command


def digest_bytes(*parts):
    h = hashlib.sha256()
    for part in parts:
        h.update(part if isinstance(part, bytes) else str(part).encode())
        h.update(b"\0")
    return h.hexdigest()[:16]


# ---------------------------------------------------------------- sources

def resolve_source(spec):
    """Returns the shader root directory for a --source/--a/--b value."""
    if spec in (None, "", "worktree", "."):
        return ROOT / "shaders"
    path = pathlib.Path(spec)
    if path.is_dir():
        return path / "shaders" if (path / "shaders").is_dir() and not any(path.glob("*.slang")) else path
    sha = subprocess.run(["git", "-C", str(ROOT), "rev-parse", "--verify", "--quiet", f"{spec}^{{commit}}"],
                         capture_output=True, text=True).stdout.strip()
    if not sha:
        fail(f"--source {spec!r} is neither a directory nor a git revision")
    dest = CACHE / "revs" / sha
    if not (dest / ".complete").exists():
        tmp = pathlib.Path(tempfile.mkdtemp(prefix="rev-", dir=CACHE.mkdir(parents=True, exist_ok=True) or CACHE))
        archive = subprocess.run(["git", "-C", str(ROOT), "archive", sha, "shaders"], capture_output=True)
        if archive.returncode != 0:
            fail(f"git archive {sha} shaders: {archive.stderr.decode().strip()}")
        subprocess.run(["tar", "-x", "-C", str(tmp)], input=archive.stdout, check=True)
        (tmp / ".complete").write_text(spec + "\n")
        if dest.exists():
            shutil.rmtree(dest)
        dest.parent.mkdir(parents=True, exist_ok=True)
        tmp.rename(dest)
    return dest / "shaders"


def rewrite_for_cpu(text):
    """Puts `import lanius_cpu_shim;` on the first line that can take it, so
    every line keeps its number (debug info and diagnostics stay exact)."""
    lines = text.split("\n")
    in_block_comment = False
    for index, line in enumerate(lines):
        stripped = line.strip()
        continued = index > 0 and lines[index - 1].rstrip().endswith("\\")
        starts_in_comment = in_block_comment
        # Crude block-comment tracking; good enough for this tree.
        position = 0
        while True:
            if in_block_comment:
                end = line.find("*/", position)
                if end < 0:
                    break
                in_block_comment, position = False, end + 2
            else:
                start = line.find("/*", position)
                line_comment = line.find("//", position)
                if start < 0 or (0 <= line_comment < start):
                    break
                in_block_comment, position = True, start + 2
        if (starts_in_comment or continued or stripped.startswith("#")
                or re.match(r"(module|implementing)\s+[\w.]+\s*;", stripped)):
            continue
        lines[index] = SHIM_IMPORT + line
        return "\n".join(lines)
    return text + "\n" + SHIM_IMPORT + "\n"


def mirror_tree(shader_root):
    """Copies the shader tree with the shim imported into every file."""
    files = sorted(shader_root.rglob("*.slang"))
    if not files:
        fail(f"no .slang files under {shader_root}")
    shim = (TOOL_DIR / "lanius_cpu_shim.slang").read_bytes()
    h = hashlib.sha256()
    h.update(TOOL_VERSION.encode() + shim)
    contents = []
    for path in files:
        data = path.read_bytes()
        relative = path.relative_to(shader_root).as_posix()
        h.update(relative.encode() + b"\0" + data + b"\0")
        contents.append((relative, data))
    digest = h.hexdigest()[:16]
    dest = CACHE / "mirrors" / digest
    if (dest / ".complete").exists():
        return dest, digest
    tmp = pathlib.Path(tempfile.mkdtemp(prefix="mirror-", dir=CACHE.mkdir(parents=True, exist_ok=True) or CACHE))
    for relative, data in contents:
        target = tmp / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(rewrite_for_cpu(data.decode()))
    (tmp / "lanius_cpu_shim.slang").write_bytes(shim)
    (tmp / ".source").write_text(str(shader_root) + "\n")
    (tmp / ".complete").write_text("")
    if dest.exists():
        shutil.rmtree(dest)
    dest.parent.mkdir(parents=True, exist_ok=True)
    tmp.rename(dest)
    return dest, digest


# ---------------------------------------------------------------- build

def kernel_source(mirror, kernel):
    path = mirror / f"{kernel}.slang"
    if not path.exists():
        fail(f"kernel {kernel!r} has no source {kernel}.slang in the shader tree")
    return path


def parse_generated(cpp_text, reflection):
    """Finds GlobalParams fields (in reflection order) and the thread entry."""
    entry = re.search(r"void (\w+)_Thread\(ComputeThreadVaryingInput\* varyingInput", cpp_text)
    if not entry:
        fail("generated C++ has no _Thread entry point")
    params = sorted((p for p in reflection["parameters"] if p["binding"].get("kind") == "uniform"),
                    key=lambda p: p["binding"]["offset"])
    struct = re.search(r"struct (GlobalParams_\d+)\n\{\n(.*?)\n\};", cpp_text, re.S)
    fields = []
    if struct:
        for line in struct.group(2).split("\n"):
            line = line.strip()
            if line.endswith(";"):
                fields.append(re.search(r"(\w+)\s*;$", line).group(1))
    if len(fields) != len(params):
        fail(f"GlobalParams has {len(fields)} fields but reflection lists {len(params)} parameters")
    slots = []
    for field, param in zip(fields, params):
        if not re.fullmatch(re.escape(param["name"]) + r"_\d+", field):
            fail(f"GlobalParams field {field} does not match parameter {param['name']}")
        ty = param["type"]
        writable = ty.get("kind") == "resource" and ty.get("access") == "readWrite"
        slots.append({"name": param["name"], "field": field, "writable": writable, "type": ty})
    return entry.group(1), (struct.group(1) if struct else None), slots


def binder_source(entry, struct, slots, numthreads, uses_barriers):
    names = ", ".join(json.dumps(slot["name"]) for slot in slots)
    binds = "\n".join(f"    lanius_bind_slot(globals.{slot['field']}, slots[{i}]);"
                      for i, slot in enumerate(slots))
    globals_decl = f"    static {struct} globals;\n{binds}\n    return &globals;" if struct else "    return nullptr;"
    return f"""
// ---- appended by tools/cpu_kernel_replay.py ----
#include "lanius_cpu_binder.h"
extern "C" const uint32_t lanius_kernel_numthreads[3] = {{{numthreads[0]}u, {numthreads[1]}u, {numthreads[2]}u}};
extern "C" const int lanius_kernel_uses_barriers = {1 if uses_barriers else 0};
extern "C" const uint32_t lanius_kernel_slot_count = {len(slots)};
extern "C" const char* const lanius_kernel_slot_names[] = {{{names + ", " if names else ""}nullptr}};
extern "C" void* lanius_kernel_bind(const LaniusSlot* slots)
{{
    (void)slots;
{globals_decl}
}}
extern "C" void lanius_kernel_thread(const LaniusThreadInput* input, void* globals)
{{
    {entry}_Thread((ComputeThreadVaryingInput*)input, nullptr, globals);
}}
"""


def cxx_flags(debug, sanitize):
    flags = ["-std=c++17", "-g", "-fwrapv", "-fno-strict-aliasing", "-ffp-contract=off", "-w",
             "-I", str(TOOL_DIR)]
    flags += ["-O0", "-g3"] if debug else ["-O1"]
    if sanitize:
        flags += ["-fsanitize=undefined", "-fno-sanitize-recover=undefined"]
    return flags


def build(kernel, source_spec, debug=False, sanitize=False, memory="4G"):
    """Returns (executable, build info) for `kernel` from `source_spec`."""
    shader_root = resolve_source(source_spec)
    mirror, tree_digest = mirror_tree(shader_root)
    source = kernel_source(mirror, kernel)
    runtime = b"".join((TOOL_DIR / name).read_bytes() for name in
                       ("lanius_cpu_runtime.h", "lanius_cpu_binder.h", "lanius_cpu_abi.h", "lanius_cpu_main.cpp"))
    flags = cxx_flags(debug, sanitize)
    key = digest_bytes(TOOL_VERSION, tree_digest, kernel, SLANGC, CXX, " ".join(flags), runtime)
    out = CACHE / "builds" / f"{kernel.replace('/', '__')}-{key}"
    exe = out / "replay"
    info_path = out / "build.json"
    if exe.exists() and info_path.exists():
        return exe, json.loads(info_path.read_text())
    out.mkdir(parents=True, exist_ok=True)
    include_dirs = [mirror] + [mirror / sub for sub in ("lexer", "parser", "type_checker", "codegen")]
    command = [SLANGC, "-target", "cpp", "-O0", "-entry", "main", "-stage", "compute",
               "-reflection-json", str(out / "kernel.cpu.json"), "-o", str(out / "kernel.cpp")]
    for directory in include_dirs:
        command += ["-I", str(directory)]
    command += [f"-D{name}=lanius_cpu_{name}" for name in INTRINSICS]
    command += ["-Dgroupshared=__global", str(source)]
    log(f"slangc -target cpp {kernel} ({shader_root})")
    result = subprocess.run(capped(command, "1500M"), capture_output=True, text=True)
    diagnostics = (result.stdout + result.stderr).replace(str(mirror), str(shader_root))
    diagnostics = "\n".join(line for line in diagnostics.splitlines()
                            if "entry point 'main' is not allowed" not in line)
    if result.returncode != 0:
        fail(f"slangc failed for {kernel}:\n{diagnostics}")
    if diagnostics.strip():
        log(diagnostics)
    cpp = (out / "kernel.cpp").read_text()
    reflection = json.loads((out / "kernel.cpu.json").read_text())
    entry, struct, slots = parse_generated(cpp, reflection)
    numthreads = reflection["entryPoints"][0].get("threadGroupSize", [1, 1, 1])
    uses_barriers = "lanius_group_barrier()" in cpp
    full = out / "kernel_full.cpp"
    full.write_text('#include "lanius_cpu_runtime.h"\n#include "kernel.cpp"\n'
                    + binder_source(entry, struct, slots, numthreads, uses_barriers))
    log(f"{CXX} {' '.join(flags[-2:] if debug else flags[-1:])} kernel ({len(cpp.splitlines())} lines of C++)")
    compile_kernel = [CXX] + flags + ["-I", str(out), "-c", str(full), "-o", str(out / "kernel.o")]
    compile_main = [CXX] + flags + ["-c", str(TOOL_DIR / "lanius_cpu_main.cpp"), "-o", str(out / "main.o")]
    for step in (compile_kernel, compile_main):
        result = subprocess.run(capped(step, memory), capture_output=True, text=True)
        if result.returncode != 0:
            fail(f"C++ compile failed:\n{' '.join(step)}\n{result.stdout}{result.stderr}")
    link = [CXX] + flags + [str(out / "kernel.o"), str(out / "main.o"), "-o", str(exe)]
    result = subprocess.run(link, capture_output=True, text=True)
    if result.returncode != 0:
        fail(f"link failed:\n{result.stderr}")
    info = {"kernel": kernel, "source": str(shader_root), "mirror": str(mirror), "slots": slots,
            "numthreads": numthreads, "uses_barriers": uses_barriers, "debug": debug}
    info_path.write_text(json.dumps(info, indent=1))
    return exe, info


# ---------------------------------------------------------------- capture

def load_capture(capture):
    capture = pathlib.Path(capture)
    manifest_path = capture / "manifest.json"
    if not manifest_path.exists():
        fail(f"{capture} has no manifest.json")
    return capture, json.loads(manifest_path.read_text())


def capture_kernel(manifest, override):
    if override:
        return override
    kernel = manifest.get("kernel")
    if not kernel:
        fail("the capture names no kernel; pass --kernel KEY")
    return kernel


def parse_extra(values):
    extra = {}
    for value in values or []:
        name, _, size = value.partition("=")
        if not size:
            fail(f"--zero wants NAME=BYTES, got {value!r}")
        extra[name] = int(size)
    return extra


def write_plan(info, capture, manifest, out_dir, groups=None, break_dtid=None, zero=None):
    bindings = {binding["name"]: binding for binding in manifest["bindings"]}
    groups = groups or manifest["groups"]
    lines = [f"groups {groups[0]} {groups[1]} {groups[2]}", f"out {out_dir}"]
    if break_dtid:
        lines.append("break " + " ".join(str(v) for v in break_dtid))
    missing = []
    for slot in info["slots"]:
        name = slot["name"]
        binding = bindings.get(name)
        if binding:
            path, size = capture / binding["file"], binding["bytes"]
        elif zero and name in zero:
            path, size = "-", zero[name]
        else:
            missing.append(name)
            continue
        out_file = f"{name}.bin" if slot["writable"] else "-"
        lines.append(f"slot {name} {1 if slot['writable'] else 0} {size} {out_file} {path}")
    if missing:
        fail(f"the capture has no binding for kernel parameter(s) {', '.join(missing)}; "
             "pass --zero NAME=BYTES to zero-fill them")
    unused = sorted(set(bindings) - {slot["name"] for slot in info["slots"]})
    if unused:
        log(f"ignoring captured bindings the kernel does not declare: {', '.join(unused)}")
    out_dir.mkdir(parents=True, exist_ok=True)
    plan = out_dir / "plan.txt"
    plan.write_text("\n".join(lines) + "\n")
    return plan


def run(exe, plan, timeout, memory):
    result = subprocess.run(capped([str(exe), str(plan)], memory), capture_output=True, text=True,
                            timeout=timeout)
    sys.stderr.write(result.stderr)
    if result.returncode != 0:
        fail(f"replay exited with {result.returncode} (rerun under gdb: tools/cpu_kernel_replay.py gdb ...)")
    return json.loads(result.stdout.strip().splitlines()[-1])


def replay(args, source, label, kernel=None):
    capture, manifest = load_capture(args.capture)
    kernel = kernel or capture_kernel(manifest, args.kernel)
    exe, info = build(kernel, source, debug=args.debug, sanitize=args.sanitize, memory=args.memory)
    out_dir = pathlib.Path(args.out) if getattr(args, "out", None) and label == "run" else \
        CACHE / "runs" / f"{capture.resolve().name}-{label}-{exe.parent.name}"
    if out_dir.exists():
        shutil.rmtree(out_dir)
    plan = write_plan(info, capture, manifest, out_dir, groups=parse_groups(args.groups),
                      zero=parse_extra(args.zero))
    stats = run(exe, plan, args.timeout, args.memory)
    stats["kernel"] = kernel
    stats["out"] = str(out_dir)
    return info, out_dir, stats


def parse_groups(value):
    if not value:
        return None
    parts = [int(v) for v in value.split(",")]
    return (parts + [1, 1])[:3]


# ---------------------------------------------------------------- compare

def element_layout(ty):
    """(stride, [(word offset, field name)]) for a structured buffer type."""
    result = ty.get("resultType") or ty.get("elementType") or {}

    def size_of(t):
        kind = t.get("kind")
        if kind == "scalar":
            return 8 if "64" in t.get("scalarType", "") else 4
        if kind == "vector":
            return size_of(t["elementType"]) * t["elementCount"]
        if kind == "struct":
            end = 0
            for field in t["fields"]:
                end = max(end, field["binding"]["offset"] + size_of(field["type"]))
            return end
        if kind == "array":
            return size_of(t["elementType"]) * t.get("elementCount", 1)
        return 4
    fields = []
    if result.get("kind") == "struct":
        for field in result["fields"]:
            words = max(1, size_of(field["type"]) // 4)
            for word in range(words):
                suffix = f"[{word}]" if words > 1 else ""
                fields.append((field["binding"]["offset"] // 4 + word, field["name"] + suffix))
    elif result.get("kind") == "vector":
        fields = [(i, "xyzw"[i]) for i in range(result["elementCount"])]
    return max(4, size_of(result)) if result else 4, dict(fields)


def describe_word(word, layout):
    stride, fields = layout
    words = stride // 4
    if words <= 1:
        return f"[{word}]"
    return f"[{word // words}].{fields.get(word % words, word % words)}"


def replay_outputs(out_dir, slots):
    """{parameter name: output file} of a CPU replay."""
    return {slot["name"]: out_dir / f"{slot['name']}.bin" for slot in slots if slot["writable"]}


def gpu_outputs(capture, manifest):
    """{parameter name: output file} of the GPU dispatch in a capture."""
    return {binding["name"]: capture / binding["post_file"]
            for binding in manifest["bindings"] if binding.get("post_file")}


def compare_buffers(left_files, right_files, slots, left_name, right_name, max_diffs):
    differing = 0
    for slot in slots:
        if not slot["writable"]:
            continue
        name = slot["name"]
        left, right = left_files.get(name), right_files.get(name)
        left = left if left and left.exists() else None
        right = right if right and right.exists() else None
        if not left or not right:
            print(f"  {name}: missing on the {'left' if not left else 'right'} side")
            differing += 1
            continue
        a, b = left.read_bytes(), right.read_bytes()
        if a == b:
            print(f"  {name}: equal ({len(a)} bytes)")
            continue
        differing += 1
        words = min(len(a), len(b)) // 4
        layout = element_layout(slot["type"])
        diffs = [i for i in range(words) if a[i * 4:i * 4 + 4] != b[i * 4:i * 4 + 4]]
        size_note = "" if len(a) == len(b) else f", sizes {len(a)} vs {len(b)}"
        print(f"  {name}: {len(diffs)} of {words} words differ{size_note}")
        for i in diffs[:max_diffs]:
            va = int.from_bytes(a[i * 4:i * 4 + 4], "little")
            vb = int.from_bytes(b[i * 4:i * 4 + 4], "little")
            print(f"    {name}{describe_word(i, layout)}: {left_name}=0x{va:08x} ({va}) {right_name}=0x{vb:08x} ({vb})")
        if len(diffs) > max_diffs:
            print(f"    ... {len(diffs) - max_diffs} more")
    return differing


def print_stats(label, stats):
    oob = f", {stats['out_of_bounds']} out-of-bounds accesses" if stats["out_of_bounds"] else ""
    divergent = f", {stats['divergent_barriers']} divergent barriers" if stats["divergent_barriers"] else ""
    mode = "fibers" if stats["fibers"] else "direct"
    print(f"{label}: {stats['kernel']} groups {stats['groups']} x {stats['numthreads']} ({mode}) "
          f"in {stats['elapsed_ms']:.0f} ms{oob}{divergent}; outputs in {stats['out']}")


def command_run(args):
    info, out_dir, stats = replay(args, args.source, "run")
    print_stats("run", stats)
    return 0


def command_check(args):
    capture, manifest = load_capture(args.capture)
    if not manifest.get("post"):
        fail("this capture has no GPU outputs (post/); it was captured with "
             "LANIUS_DEBUG_OPERATION_LIMIT or by an older compiler")
    info, out_dir, stats = replay(args, args.source, "check")
    print_stats("cpu", stats)
    print(f"cpu vs gpu ({capture / 'post'}):")
    differing = compare_buffers(replay_outputs(out_dir, info["slots"]), gpu_outputs(capture, manifest),
                                info["slots"], "cpu", "gpu", args.max_diffs)
    changed = gpu_changed_words(capture, manifest)
    print(f"the GPU dispatch changed {sum(changed.values())} words in {len(changed)} buffer(s)"
          + ("" if changed else " (it did no work or rewrote the values already there; a dispatch that "
                                "changes data, see LANIUS_DEBUG_CAPTURE_INDEX, makes a stronger check)"))
    print("MATCH" if not differing else f"MISMATCH in {differing} buffer(s)")
    return 1 if differing else 0


def gpu_changed_words(capture, manifest):
    """{binding name: words the GPU dispatch changed} for a capture."""
    changed = {}
    for binding in manifest["bindings"]:
        if binding.get("post_file"):
            count = words_changed(capture / binding["file"], capture / binding["post_file"])
            if count:
                changed[binding["name"]] = count
    return changed


def command_compare(args):
    info_a, out_a, stats_a = replay(args, args.a, "a")
    info_b, out_b, stats_b = replay(args, args.b, "b", kernel=args.kernel_b)
    print_stats(f"a ({args.a})", stats_a)
    print_stats(f"b ({args.b})", stats_b)
    names_b = {slot["name"] for slot in info_b["slots"]}
    shared = [slot for slot in info_a["slots"] if slot["name"] in names_b]
    for slot in info_a["slots"] + info_b["slots"]:
        if slot["writable"] and slot not in shared and slot["name"] not in {s["name"] for s in shared}:
            print(f"  {slot['name']}: only one kernel writes it")
    print("a vs b:")
    differing = compare_buffers(replay_outputs(out_a, shared), replay_outputs(out_b, shared), shared,
                                "a", "b", args.max_diffs)
    capture, manifest = load_capture(args.capture)
    inputs = {binding["name"]: capture / binding["file"] for binding in manifest["bindings"]}
    changed = sum(words_changed(inputs.get(name), path) for name, path in replay_outputs(out_a, shared).items())
    print(f"kernel a changed {changed} words of its inputs"
          + ("" if changed else " (no work on this capture: SAME OUTPUTS proves little)"))
    print("SAME OUTPUTS" if not differing else f"DIFFERENT in {differing} buffer(s)")
    return 1 if differing else 0


def words_changed(before, after):
    if not before or not before.exists() or not after.exists():
        return 0
    a, b = before.read_bytes(), after.read_bytes()
    return sum(1 for i in range(0, min(len(a), len(b)), 4) if a[i:i + 4] != b[i:i + 4])


def command_build(args):
    exe, info = build(args.kernel, args.source, debug=args.debug, sanitize=args.sanitize, memory=args.memory)
    print(exe)
    return 0


def command_gdb(args):
    args.debug = True
    capture, manifest = load_capture(args.capture)
    kernel = capture_kernel(manifest, args.kernel)
    exe, info = build(kernel, args.source, debug=True, sanitize=args.sanitize, memory=args.memory)
    out_dir = CACHE / "runs" / f"{capture.resolve().name}-gdb-{exe.parent.name}"
    break_dtid = None
    if args.break_dtid:
        break_dtid = ([int(v) for v in args.break_dtid.split(",")] + [0, 0])[:3]
    plan = write_plan(info, capture, manifest, out_dir, groups=parse_groups(args.groups),
                      break_dtid=break_dtid, zero=parse_extra(args.zero))
    gdb = ["gdb", "-q", "-ex", f"set substitute-path {info['mirror']} {info['source']}",
           "-ex", "handle SIGSEGV stop print"]
    if break_dtid:
        gdb += ["-ex", "break lanius_cpu_break"]
    command = gdb + args.gdb_args + ["--args", str(exe), str(plan)]
    print(" ".join(f"'{part}'" if " " in part else part for part in command), file=sys.stderr)
    os.execvp("gdb", command)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)

    def common(p, capture=True):
        if capture:
            p.add_argument("capture", help="capture directory (manifest.json)")
            p.add_argument("--kernel", help="artifact key, default: the capture's kernel")
            p.add_argument("--groups", help="X[,Y,Z] workgroups instead of the captured dispatch size")
            p.add_argument("--zero", action="append", metavar="NAME=BYTES",
                           help="zero-fill a kernel parameter the capture lacks (repeatable)")
            p.add_argument("--timeout", type=float, default=600, help="seconds per replay")
            p.add_argument("--max-diffs", type=int, default=8, help="differing words to print per buffer")
        p.add_argument("--debug", action="store_true", help="build -O0 -g3 instead of -O1 -g")
        p.add_argument("--sanitize", action="store_true", help="build with UBSan (shift/overflow/...)")
        p.add_argument("--memory", default="4G", help="memory cap for the C++ compile and the replay")

    p = sub.add_parser("check", help="CPU result vs the captured GPU result")
    common(p)
    p.add_argument("--source", default="worktree")
    p.set_defaults(func=command_check)
    p = sub.add_parser("compare", help="kernel A vs kernel B on the same captured inputs")
    common(p)
    p.add_argument("--a", default="HEAD", help="source of kernel A (default HEAD)")
    p.add_argument("--b", default="worktree", help="source of kernel B (default worktree)")
    p.add_argument("--kernel-b", help="artifact key of kernel B when it differs from kernel A's")
    p.set_defaults(func=command_compare)
    p = sub.add_parser("run", help="replay and keep the outputs")
    common(p)
    p.add_argument("--source", default="worktree")
    p.add_argument("--out", help="output directory")
    p.set_defaults(func=command_run)
    p = sub.add_parser("gdb", help="replay under gdb (-O0 build)")
    common(p)
    p.add_argument("--source", default="worktree")
    p.add_argument("--break-dtid", help="X[,Y,Z]: stop in lanius_cpu_break before that dispatch thread runs")
    p.set_defaults(func=command_gdb)
    p = sub.add_parser("build", help="only compile a kernel for the CPU")
    p.add_argument("kernel", help="artifact key, e.g. type_checker/calls/01a_clear_entrypoints")
    p.add_argument("--source", default="worktree")
    common(p, capture=False)
    p.set_defaults(func=command_build)
    # Everything after `--` goes to gdb.
    argv = sys.argv[1:]
    at = argv.index("--") if "--" in argv else len(argv)
    args = parser.parse_args(argv[:at])
    args.gdb_args = argv[at + 1:]
    if args.gdb_args and args.command != "gdb":
        parser.error("arguments after -- are only for the gdb command")
    sys.exit(args.func(args))


if __name__ == "__main__":
    main()
