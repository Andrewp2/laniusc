# Capture-time source roots

`README.md`, `AFTER.md` and their hash manifests preserve separate captures.
They describe the stdlib snapshot used at capture time, not the current
production clone API. Their original source files and manifests are unchanged.

In particular, preserved `prepare.py` appends prototype String implementations
to a copied stdlib. Do not run it against a later stdlib that already supplies
those implementations. For historical experiments, use the captured stdlib
checkpoint `c3d055c4592d9383e06a83304b75d579f0161918` in an isolated checkout or
source root. The ordinary probe modules can use an extracted root:

```sh
mkdir -p target/stdlib-work/clone-admission-baseline
timeout --kill-after=2s 100s git archive \
  c3d055c4592d9383e06a83304b75d579f0161918 stdlib | \
  timeout --kill-after=2s 100s tar -x -C target/stdlib-work/clone-admission-baseline
```

Pass `--stdlib-root target/stdlib-work/clone-admission-baseline/stdlib` and
`--source-root tests/fixtures/stdlib_compiler_state/clone_admission` to the
current compiler. A current compiler is expected to repair some captured
failures; this does not recreate the old shader generation. The manifests
identify the captured binaries and sources when they remain available locally.

`closed-error-conflict.lani` preserves an additional exact control: its bound
fixes `String::Error`, while the receiving result claims `i64`. Before the
local result-contract repair it emitted an ELF; that invalid program was never
executed. The checked trace selected a local function and no dependency
library. Imported-only experimental changes therefore did not affect that
call. The final local repair rejects it with `LNC0006`.

The durable positive/negative regression is now
[`compiler_trait_return_context_execution.rs`](../../../compiler_trait_return_context_execution.rs),
with allocation-free fixtures independent of these prototype owners.
Production clone behavior has its own library tests. Historical admissions do
not replace those gates or establish arbitrary implementation forwarding.
