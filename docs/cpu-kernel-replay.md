# CPU kernel replay

`tools/cpu_kernel_replay.py` reruns one compute dispatch of a Slang kernel on
the CPU. It takes inputs captured from a real GPU run, and you can step
through it in gdb. Use it to check a kernel rewrite without the GPU: capture
the kernel's inputs once, then rerun the old and new kernels on the CPU as
often as you like.

Nothing in the tool touches the GPU, so it needs neither `heavy` nor a cargo
build. A run does three things:

1. slangc turns the kernel into C++ (`-target cpp`).
2. g++ builds that C++ together with `tools/cpu_replay/` into one executable
   per shader-source digest, cached under `target/cpu-replay/`.
3. The executable runs every workgroup of the captured dispatch.

A build takes 1–4 s, including the 20k lines of C++ of the 03d walker, and
replays take milliseconds. Both compiles run under a `systemd-run` memory cap
(`--memory`, default 4G). Any change to the shader tree invalidates the cached
builds.

## 1. Capture a dispatch (GPU, once)

Run the one-shot CLI, not the daemon, through `heavy`:

```sh
heavy env LANIUS_DEBUG_CAPTURE_PASS=type_checker/calls/03d_bind_method_receiver_environment \
          LANIUS_DEBUG_CAPTURE_DIR=$SCRATCH/cap-03d \
          target/release/laniusc --emit x86_64 --stdlib-root stdlib -o $SCRATCH/p10.elf \
          tests/fixtures/generics_matrix/p10_generic_method.lani
```

These variables control the capture:

- `LANIUS_DEBUG_CAPTURE_PASS` names what to capture. It can be either of these:
  - a kernel's artifact key: `type_checker/calls/03d_...`, `parser/tokens/to/kinds`.
  - an operation label, as `LANIUS_DEBUG_OPERATION_LOG=1` prints it.
- `LANIUS_DEBUG_CAPTURE_INDEX=k` (default 0) picks the k-th matching dispatch.
  Use it for a later call-inference round or a later scan level.
- `LANIUS_DEBUG_CAPTURE_DIR` (default `lanius-capture`) is where the capture
  goes. Use your own scratch directory.

The selected dispatch is recorded in a compute pass of its own. Every buffer
range it binds is copied twice: right before the dispatch (the inputs) and
right after it (the GPU outputs). For an indirect dispatch, its arguments are
copied too. The capture is written when the compile ends, even when the
compile fails, and stderr shows `[lanius-capture] ... wrote dispatch #k of
KERNEL`. The capture directory holds:

```
manifest.json      kernel, label, dispatch_index, thread_group_size,
                   groups (decoded from the indirect args when indirect),
                   indirect, dispatched, post, dynamic_offsets, bindings[]
NNN_name.bin       input bytes of binding NNN (uniforms included)
post/NNN_name.bin  the GPU's bytes after the dispatch
```

Captures are small: p10's 03d capture is 31 MB for 107 bindings, and most
kernels are under 2 MB. Keep them in your scratch directory and reuse them
across rewrites. To capture several kernels in one `heavy` hold, run one
compile per kernel; each takes 1–4 s with a warm pipeline cache.

`LANIUS_DEBUG_OPERATION_LIMIT=N` works together with the capture, for hang
debugging. The first matching dispatch that the limit drops is captured with
its inputs only, `"post": false`.

## 2. Check, compare, run

```sh
# CPU result vs the captured GPU result (validates the replay itself).
python3 tools/cpu_kernel_replay.py check $SCRATCH/cap-03d

# Kernel A vs kernel B on the same captured inputs. The default is
# --a HEAD --b worktree: your uncommitted rewrite against the committed kernel.
python3 tools/cpu_kernel_replay.py compare $SCRATCH/cap-03d
python3 tools/cpu_kernel_replay.py compare $SCRATCH/cap-03d --a generics-gpu --b HEAD

# Keep the outputs: one NAME.bin per writable parameter.
python3 tools/cpu_kernel_replay.py run $SCRATCH/cap-03d --out $SCRATCH/out
```

Where the kernel sources come from (`--source`, `--a`, `--b`):

- `worktree`: this checkout's `shaders/`.
- any git revision (it is extracted with `git archive` and cached).
- a directory that holds the shader tree.

Other options:

- `--kernel KEY` replays a different kernel than the captured one.
- `--kernel-b KEY` names kernel B when the rewrite renamed it.
- `--groups X,Y,Z` overrides the dispatch size.
- `--zero NAME=BYTES` zero-fills a parameter the capture lacks.

The exit status is 0 on a match, 1 on a difference, and 2 on a tool error. A
difference lists each differing buffer with word indices, decoded as element
and field names from the reflection, for example `call_env[12].type_id: a=...
b=...`.

Both commands also print how many words the dispatch changed:

- `check`: "the GPU dispatch changed N words".
- `compare`: "kernel a changed N words of its inputs".

On small probes, many type-checker dispatches change nothing, because they
only rewrite values an earlier round already published. A match on such a
capture proves less, so pick a dispatch that changes data
(`LANIUS_DEBUG_CAPTURE_INDEX`, another probe). Another option is to clear the
kernel's outputs in a copy of the capture (see Validation).

### How to verify a kernel rewrite without the GPU

1. Before editing, capture the kernel on one or two probes that exercise it,
   with one `heavy` hold for all captures. If the kernel runs more than once,
   capture both a small and a large instance (for example `@0` and the last
   index).
2. Run `check` on each capture once. It should print `MATCH`. If it does not,
   see Limits; the replay may not model the kernel.
3. Edit the kernel. After each edit, run `compare CAPTURE` (HEAD vs worktree)
   on all captures. `SAME OUTPUTS` means your kernel writes exactly the bytes
   the old one writes on those inputs. A difference names the buffer, the
   element and the field.
4. If the rewrite changes the binding set, pass the following:
   - `--zero NAME=BYTES` for buffers the capture does not have.
   - `--kernel-b` for a renamed kernel.

   If a new input needs real data from another pass, recapture with the new
   compiler.
5. Use the GPU only at the milestone: one matrix gate run.

`compare` checks every writable buffer the two kernels share, in full, so a
stray scatter outside a kernel's own range shows up too. Kernels that
read-modify-write their outputs are handled correctly, because both sides
start from the captured pre-dispatch bytes.

## 3. Debug a kernel in gdb

```sh
python3 tools/cpu_kernel_replay.py gdb $SCRATCH/cap-03d --break-dtid 37
```

This builds `-O0 -g3`, maps the mirrored sources back to `shaders/`, and
starts gdb on the replay. `#line` directives in the generated C++ point at the
`.slang` files, so the following work on Slang source lines:

- `break shaders/type_checker/calls/03d_bind_method_receiver_environment.slang:120`
- `list`
- `step`

Generated variable names carry `_0`/`_1` suffixes; `info locals` shows them.

- `--break-dtid X[,Y,Z]` stops in `lanius_cpu_break()` right before that
  dispatch thread runs. Then `break FILE.slang:LINE` and `continue`.
- Conditional breakpoints use the globals `lanius_cpu_dtid[3]`,
  `lanius_cpu_group[3]`, `lanius_cpu_thread[3]` and `lanius_cpu_invocation`,
  for example `break foo.slang:88 if lanius_cpu_dtid[0] == 4711`.
- Shader parameters are reached through `kernelContext_0`, which every
  generated function has:
  - `p *kernelContext_0.globalParams_0` lists every binding with its data
    pointer and element count.
  - `p kernelContext_0.globalParams_0->exscan_inblock_0.data[299]` prints one
    element.
  - `p *kernelContext_0.globalParams_0->sc_stream_0.data@8` prints the first
    8 elements.
  - `p *kernelContext_0.globalParams_0->gParams_0` prints a uniform block.

  Slang appends `_0` to the names.
- To run gdb non-interactively, put gdb arguments after `--`:
  `... gdb CAP --break-dtid 5 -- -batch -ex run -ex bt -ex 'info locals'`.
- `--sanitize` adds UBSan, which reports shifts by 32 or more and similar UB.
  Signed overflow is not reported, because it wraps under `-fwrapv`, as on
  the GPU. It works with check/run/compare too.

An out-of-bounds buffer access is reported with the invocation and buffer
name, and then reads zero or drops the write, as robust buffer access does on
the GPU. The first 10 such accesses are reported; `LANIUS_CPU_OOB_REPORTS`
changes the limit. A crash or hang in the replay is a kernel bug or a replay
limit; rerun it under `gdb`. Each invocation of a barrier kernel gets its own
stack, 8 MiB by default (`LANIUS_CPU_STACK_MB`); kernels without barriers run
on the main stack.

## Limits

- The replay is x86-64 Linux only, because the fiber switch is hand-written
  asm.
- Execution is sequential and deterministic:
  - groups run x-major, then y, then z;
  - within a group, threads run in index order, each up to its next barrier;
  - atomics are plain read-modify-writes.

  Results that depend on atomic ordering can therefore differ from the GPU.
  Examples are the slot an `InterlockedAdd` allocator hands out, and which
  writer wins a race. `check` shows such differences; `compare` of two
  kernels on the CPU is still exact and deterministic.
- Any wait on another invocation hangs: spin locks, or cross-group flags
  ("decoupled look-back"). `--timeout` (default 600 s) bounds a run.
- Wave and subgroup intrinsics, textures, and float `NaN`/denormal corner
  cases are not modeled. No current kernel uses waves or textures.
- Barriers inside divergent control flow are undefined on the GPU. The replay
  ends the phase anyway and counts `divergent_barriers`.
- Integer division by zero raises SIGFPE on the CPU; on the GPU it returns
  garbage. Shifts by 32 or more are UB in C++; `--sanitize` reports them.
- groupshared memory becomes C++ globals. They start at zero and keep the
  previous workgroup's values. On the GPU, groupshared memory is undefined
  at the start of a group, so a kernel that reads it before writing it is
  buggy on both.
- Only the dispatch paths in `gpu/passes_core.rs`, `gpu/operations` and the
  `ComputePassBatch` and Pass helpers capture. These cover the
  type checker, compiler-graph operations, parser passes and x86
  codegen/link. Hand-rolled dispatches in `scans.rs`, `syntax.rs`, the lexer
  passes, `lowering.rs` and `control.rs` do not. A capture of one of those
  ends with "no dispatch captured (0 dispatches ...)".
- Bindings whose buffer lacks COPY_SRC are skipped with a warning. The replay
  then needs `--zero` for them.
- The daemon does not write captures; use the one-shot CLI.
- slangc 2026.2 (`~/.local/bin/slangc`) is used; override it with
  `LANIUS_CPU_REPLAY_SLANGC`. Its C++ backend lacks atomics other than add, and
  group barriers. `tools/cpu_replay/lanius_cpu_shim.slang` provides them: the
  tool imports it into a mirror of the shader tree and renames the intrinsics
  with `-D`. The shader sources stay unchanged and line numbers are preserved.

## Validation (2026-10-14, RTX 3070 laptop, probe p10_generic_method)

`check` printed MATCH, meaning the CPU output equals the GPU output
byte for byte, on all of these kernels:

| kernel | kind | GPU changed |
|---|---|---|
| type_checker/names/00_mark_lexemes | per-thread | 46 words |
| type_checker/calls/01a_clear_entrypoints | per-thread clear | 0 |
| parser/brackets/01_scan_inblock | groupshared scan, barriers (fibers) | 511 words |
| type_checker/names/hash/01_insert | atomic compare-exchange hash insert, 18 groups | 78 words |
| codegen/x86/link/symbol_partition_insert | atomics | 2 words |
| parser/tokens/to/kinds | 4.7k lines of C++, barriers | 94 words |
| type_checker/calls/03e_materialize_return_types | walker, 23k lines of C++ | 4 words |
| type_checker/calls/03d_bind_method_receiver_environment | walker, 20k lines, 107 bindings | 0 (dispatches #0–5) |
| type_checker/calls/03k_project_argument_contexts | the largest kernel (600k inlined) | 0 |

On p10, 03d only republishes bindings that already exist. Two checks show
that the replay still runs its real path:

- In gdb, call 37 (`s.top()`) reaches `publish_receiver_bindings` with the
  inferred `T = i32`.
- With `call_context_arg_mask` and `call_context_ref_tag` zeroed in a copy of
  the capture, the CPU re-derives both words and matches the GPU's state.

`build` succeeded for 30 kernels sampled across every directory (1–5 s each).

## Files

- `crates/laniusc-compiler/src/gpu/dispatch_capture.rs`: the capture.
- `tools/cpu_kernel_replay.py`: the driver (build cache, plans, comparison, gdb).
- `tools/cpu_replay/lanius_cpu_main.cpp`: the runner (workgroups, fibers,
  barriers, bounds reports).
- `tools/cpu_replay/lanius_cpu_runtime.h`: atomics, barrier hooks and the
  bounds-check overrides included ahead of the generated kernel.
- `tools/cpu_replay/lanius_cpu_binder.h` and `lanius_cpu_abi.h`: binding
  captured bytes to Slang's C++ parameter structs.
- `tools/cpu_replay/lanius_cpu_shim.slang`: CPU-only intrinsic stand-ins.
- `src/bin/shader_dispatch_replay.rs` and `crates/vk-hang-probe` replay the
  same captures on the GPU.
