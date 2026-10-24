# Fallible element-clone admission

These are isolated source-shape probes, not production APIs. No compiler,
proof, binding, production collection, or shared documentation was edited.
Recorded on 2026-10-23 at repository `c3d055c4592d9383e06a83304b75d579f0161918`.

## Proposed contract

`probe::protocol::TryClone<T,E>::try_clone_value(source:T)->Result<T,E>`
receives a read-only borrowed shallow descriptor. Success transfers an owner
independent of source and other successful clones. Failure releases that leaf's
partial result, preserves source, and transfers its exact E to the caller.

`Destroy<T>::destroy_value(owned:T)` explicitly consumes a valid memory owner.
It must finish without allocation, panic, or reportable failure. It is not
automatic Drop and does not cover file/socket owners with fallible close.

`probe::vec_clone::from_view<T,E>` validates logical View metadata, reserves the
entire outer Vec before any leaf, and clones in source order. On failure it
releases only initialized destination entries, then outer storage, and returns
`Failure::Element(zero_based_index,E)` unchanged. E's logical ownership passes
through that result; language-level descriptor copies do not create owners.
Physical source backing, lifetime, immutability and nonaliasing with mutable
owner metadata remain caller preconditions. Duplicate borrowed source handles
are permitted. `destroy_vec<T>(&Vec<T>)` requires only Destroy<T>, drains entries
and resets the outer owner. Neither helper was admitted in its general form.

## Results, kept distinct

| Probe | Result |
| --- | --- |
| `initial/main.lani` + initial imported helper | LNC0006 at helper's static `T::try_clone_value` result |
| `main.lani`, typed `borrowed:T` local | Same LNC0006 at `probe/vec_clone.lani:30` |
| `generic_return.lani`, only generic T/E static return | LNC0006 at line8; no Vec or View composition is needed |
| `direct.lani`, concrete String dispatch | Compiles; shared jump checker passes; native exit0, exact2maps/2frees |
| `fixed_error.lani`, generic T, concrete String::Error | Compiles; checker passes; native exit0, exact2maps/2frees |
| Copied stdlib `core::clone` + `alloc::clone` + ordinary String impl, full helper | Same LNC0006 at copied `alloc/clone.lani:30` |
| Copied stdlib fixed-error String control | Compiles; checker passes; native exit0, exact2maps/2frees |
| `pair_direct.lani`, concrete two-String Pair leaf | Compiles; checker passes; native exit0, exact3maps/3frees. Injected failure after left clone releases that temporary, preserves both source Strings, and transports tag102/phase1/u64 marker exactly |
| `pair_fixed.lani` + imported generic-T/concrete-OwnerFailure Vec helper | Compiles; checker passes; native SIGILL after two source mappings and outer192-byte mapping, before the first leaf clone allocation |

The Pair Vec failure is a preserved runtime composition failure, not a proven
compiler diagnosis. The general generic-E API is not admitted. Do not replace
it with per-type production specializations or weaken its error/cleanup law.
The successful controls do not establish composed prefix cleanup. The E used
here has tags, nested variants and a u64 marker, but no owned allocation; owned-E
lifetime remains a separate future acceptance case. Nonzero-start/strided views
and sibling independence checks in `main.lani` are intended coverage, not passing
execution evidence, because that full probe does not compile.

## Reproduce

From the repository root, replace ENTRY and OUTPUT with one named probe and a
fresh output. Every GPU invocation uses the shared lock:

```sh
timeout --kill-after=2s 100s flock -E 75 -w 35 \
  target/stdlib-work/library-gpu.lock timeout --kill-after=2s 60s \
  target/stdlib-build/debug/laniusc \
  tests/fixtures/stdlib_compiler_state/clone_admission/ENTRY.lani \
  --stdlib-root stdlib \
  --source-root tests/fixtures/stdlib_compiler_state/clone_admission -o OUTPUT
```

Never execute stale output after failed compilation. For a compiled output:

```sh
timeout --kill-after=2s 100s rustc --edition=2024 \
  tests/fixtures/stdlib_compiler_state/clone_admission/check.rs \
  -o target/stdlib-work/clone-admission/check
timeout --kill-after=2s 100s target/stdlib-work/clone-admission/check OUTPUT
timeout --kill-after=2s 5s strace -qq -e trace=mmap,munmap OUTPUT
```

`check.rs` calls the unchanged shared checker and provides only temporary-file
and bounded objdump subprocess utilities. Its check is not bypassed for native
acceptance. `prepare.py` creates a fresh copied stdlib and user root under
`target/stdlib-work/clone-admission`; it refuses to overwrite existing evidence.
It gives the prototype its intended `core::clone`/`alloc::clone` names and puts
the ordinary String impl inside the copied `alloc/string.lani`. Compile generated
`overlay-user/main.lani` or `fixed_error.lani` with those overlay root arguments.

Exact terminal logs, emitted controls and traces are under
`target/stdlib-work/clone-admission/`. `SHA256SUMS` pins fixture sources, compiler
binary and shared checker used for this admission. No failing-compilation test
has been added as a required permanent regression.
