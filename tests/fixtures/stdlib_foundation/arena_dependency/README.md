# Arena compiler boundaries

These are diagnostic fixtures, outside the production standard-library root.
They do not implement an alternative production arena.

## Pointer alignment capability

`pointer_cast.lani` reduces a desired pointer-to-integer projection to one cast.
On 2026-10-23 it reports:

```text
error[LNC0072]: invalid cast
cannot cast `ptr` as `usize`
```

The current arena therefore supports raw alignments 1, 2, 4 and 8, using
8-aligned backing and relative offsets. All current native typed layouts fit
that contract. Larger powers of two return `UnsupportedAlignment`. Arbitrary
over-alignment would need an explicit alignment/address capability; assuming
host page alignment is not a portable replacement.

```sh
timeout --kill-after=2s 100s env \
  CARGO_TARGET_DIR="$PWD/target/stdlib-build" \
  LANIUS_GPU_CODEGEN_TEST_TIMEOUT_MS=90000 \
  target/stdlib-build/debug/laniusc --emit x86_64 --stdlib-root stdlib \
  tests/fixtures/stdlib_foundation/arena_dependency/pointer_cast.lani \
  -o target/stdlib-work/arena-pointer-cast
```

## Nominal allocation result inside a generic copy

`entry.lani` calls only `copy_slice<u8>` on three native-array bytes. It compiles
and exits zero against the **current production arena**, independently of
other typed instantiations. That is a runtime test in
`tests/stdlib_arena_execution.rs`.

The two 32-line provider variants isolate an additional compiler composition
boundary. Each is installed as `alloc/arena.lani` in a private copy of the
standard-library root; they share the same caller and the same generic typed
storage/copy loop:

- `provider_block.lani`: the allocation helper reads a nominal chunk header
  and returns `Result<Block, Error>`. Compilation reports `LNC0047` at the
  imported allocator module, with the detail below.
- `provider_pointer.lani`: the helper returns `Result<ptr, Error>` and the
  generic copy consumes that pointer. It compiles and exits zero.

```text
error[LNC0047]: type-check execution failed
generic type instantiation reached a compiler boundary
a replay argument has no complete GPU native layout; its defining nominal
payloads or a retained checked width witness are required
```

This reports an observed source-shape difference, not an established compiler
root cause. A local generic caller using the current production `Block` wrapper
also executes, so the evidence does not show that every generic use of `Block`
fails. Production keeps its shared internal allocation boundary primitive,
wraps public raw blocks separately and uses the same general native layout
helpers for every typed allocation. No primitive specialization or pointer
reinterpretation is used.

To prepare a fresh private root for either provider, run from the repository:

```sh
python3 - <<'PY'
from pathlib import Path
import shutil
root = Path.cwd()
destination = root / 'target/stdlib-work/arena-provider-stdlib'
shutil.copytree(root / 'stdlib', destination)
shutil.copyfile(
    root / 'tests/fixtures/stdlib_foundation/arena_dependency/provider_block.lani',
    destination / 'alloc/arena.lani',
)
PY
```

Use `provider_pointer.lani` instead for the positive control. `copytree` requires
a fresh destination. Then compile the unchanged entry:

```sh
timeout --kill-after=2s 100s env \
  CARGO_TARGET_DIR="$PWD/target/stdlib-build" \
  LANIUS_GPU_CODEGEN_TEST_TIMEOUT_MS=90000 \
  target/stdlib-build/debug/laniusc --emit x86_64 \
  --stdlib-root target/stdlib-work/arena-provider-stdlib \
  tests/fixtures/stdlib_foundation/arena_dependency/entry.lani \
  -o target/stdlib-work/arena-provider-entry
```

On the positive control, `timeout 10s target/stdlib-work/arena-provider-entry`
exits zero. The negative fixture is evidence of remaining compiler work, not
a gate that requires the compiler to remain broken. Current typed arena APIs
have their own successful runtime tests.
