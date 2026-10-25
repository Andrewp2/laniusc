# Generic owned set dependencies

Revalidated on 2026-10-23 at `8cb1af7b65f098ef3f394e66f1891cf01d30dc22`
on `codex/stdlib`, using the Linux x86_64 native compiler. Both generic
`Set<T>` wrappers fail to compile. The direct map controls compile and exit zero.

| Entry | Shape | Result |
| --- | --- | --- |
| `hash_wrapper.lani` | `Set<T>` contains `HashMap<T, Unit>`; forwards insertion through `&self` | LNC0047, exit 1 |
| `tree_wrapper.lani` | `Set<T>` contains `TreeMap<T, Unit>`; forwards insertion through `&self` | LNC0047, exit 1 |
| `../../stdlib_foundation/owned_sets_hash_map_control.lani` | Direct `HashMap<i16, Unit>` insertion, membership, destruction | Native exit 0 |
| `../../stdlib_foundation/owned_sets_tree_map_control.lani` | Direct `TreeMap<i16, Unit>` insertion, membership, destruction | Native exit 0 |

The hash wrapper has 21 lines and the tree wrapper has 20; each client has ten
lines. `Unit` is a private empty record. The controls use the same marker shape
and key type. These results show that direct maps support the key and marker;
they do not identify the precise compiler stage that loses the generic layout.

Both wrappers emit this exact diagnostic; the absolute root depends on checkout
location:

```text
error[LNC0047]: type-check execution failed
 --> /home/andrew-peterson/code/laniusc/target/stdlib-work/owned-sets-revalidation/stdlib/alloc/allocator.lani:3:1
  |
3 | module alloc::allocator;
  | ^^^^^^ generic type instantiation reached a compiler boundary
     = note: a replay argument has no complete GPU native layout; its defining nominal payloads or a retained checked width witness are required
```

Build and stage the probes as **stdlib** dependencies. Loading the wrapper
through a user source root changes the experiment.

```sh
timeout 100s env \
  CARGO_TARGET_DIR=/home/andrew-peterson/code/laniusc/target/stdlib-build \
  CARGO_INCREMENTAL=0 CARGO_PROFILE_DEV_DEBUG=0 CARGO_PROFILE_TEST_DEBUG=0 \
  LANIUS_GPU_CODEGEN_TEST_TIMEOUT_MS=90000 cargo build --bin laniusc
mkdir -p target/stdlib-work/owned-sets-revalidation/stdlib/alloc
cp -r stdlib/core target/stdlib-work/owned-sets-revalidation/stdlib/
cp stdlib/alloc/allocator.lani stdlib/alloc/hash_map.lani \
  stdlib/alloc/tree_map.lani target/stdlib-work/owned-sets-revalidation/stdlib/alloc/
cp tests/fixtures/stdlib_compiler_state/owned_sets/alloc/*.lani \
  target/stdlib-work/owned-sets-revalidation/stdlib/alloc/
cp target/stdlib-build/debug/laniusc \
  target/stdlib-work/owned-sets-revalidation/laniusc-8cb1af7b
timeout --kill-after=2s 100s \
  target/stdlib-work/owned-sets-revalidation/laniusc-8cb1af7b \
  tests/fixtures/stdlib_compiler_state/owned_sets/hash_wrapper.lani \
  --stdlib-root target/stdlib-work/owned-sets-revalidation/stdlib \
  -o target/stdlib-work/owned-sets-revalidation/hash_wrapper
timeout --kill-after=2s 100s \
  target/stdlib-work/owned-sets-revalidation/laniusc-8cb1af7b \
  tests/fixtures/stdlib_compiler_state/owned_sets/tree_wrapper.lani \
  --stdlib-root target/stdlib-work/owned-sets-revalidation/stdlib \
  -o target/stdlib-work/owned-sets-revalidation/tree_wrapper
timeout 100s env \
  CARGO_TARGET_DIR=/home/andrew-peterson/code/laniusc/target/stdlib-build \
  CARGO_INCREMENTAL=0 CARGO_PROFILE_DEV_DEBUG=0 CARGO_PROFILE_TEST_DEBUG=0 \
  LANIUS_GPU_CODEGEN_TEST_TIMEOUT_MS=90000 \
  cargo test --test stdlib_owned_sets_execution -- --test-threads=1
```

The final two wrapper runs used a compiler snapshot with SHA-256
`662b2ffeeb8b773bcfc57942ca4abc20f1533c856e0c466d3ed2a2953e32d9af`.
The control test passed: one test, two native programs, zero failures. The
initial rebuild also reproduced the same failure with binary SHA-256
`9f49f5c114c8ec7fe0b5cfcd2ab3e5ccb93d9088ecfdb083306825128ad4f765`.

Source SHA-256 values, paths relative to the repository:

```text
da5bae48bb27c037d3b258ce8bd968a6ff5e1f4839cb5b11a7804b603cfdd9a1  stdlib/alloc/hash_map.lani
9b1d3c353657e8c2737e2f5df3467aeb011a55be5a260214a4ad21e6228a4c61  stdlib/alloc/tree_map.lani
c4b52d3c32b07edae30ee329f1cb85cffb6e442ff9fddd85828cca91df48e8ce  tests/fixtures/stdlib_compiler_state/owned_sets/alloc/probe_hash_set.lani
829a954d88210373c6ec513459e048d61dc2372381e2841d8fb0b90cb1143043  tests/fixtures/stdlib_compiler_state/owned_sets/alloc/probe_tree_set.lani
aede13a0d285401c76d91ebefec1ded8fe8582402c560eebb9b3a0374f834f19  tests/fixtures/stdlib_compiler_state/owned_sets/hash_wrapper.lani
0b7eb35f4f1fb54c7e3f23f85ff43546ace409a3a7df9c7dc7eb1a269eb32fa2  tests/fixtures/stdlib_compiler_state/owned_sets/tree_wrapper.lani
b8909b90cbbc127c5e34b16c0341c162caa667f62dfb556aac25394b2c1507bb  tests/fixtures/stdlib_foundation/owned_sets_hash_map_control.lani
83283ba7aa25ea60aeafe34177afb235d579ce3ed2bba1becf00f17bba48a8f0  tests/fixtures/stdlib_foundation/owned_sets_tree_map_control.lani
```

These failing fixtures record compiler dependencies; the passing test asserts
only the direct map controls. It does not require the compiler to keep rejecting
the wrappers. Once the wrappers compile, implement and execute the set contracts
described in [the owned sets status](../../../../docs/stdlib-owned-sets.md).
