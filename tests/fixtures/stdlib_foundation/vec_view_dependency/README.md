# Generic view construction through a nested Result factory

With the current GPU compiler, changing only `alloc::vec::Vec<T>.as_view` to
the following implementation makes `direct.lani` fail compilation with LNC0047:

```lanius
pub fn as_view(&self) -> core::slice::View<T> {
    return core::result::unwrap(core::slice::view(self.as_slice(), self.length));
}
```

The diagnostic says a replay argument has no complete GPU native layout.
The source location points into an imported module, rather than the operation
that needs the layout. The same failure occurs in `local.lani` and `main.lani`,
which forward a view through local and imported generic wrappers respectively.
This is not exclusively an imported-wrapper failure: the direct call fails too.

Larger programs that construct other views can compile the same original code.
That means a large passing fixture alone did not establish the minimal API use.
The heap migration also encountered this error; its smaller construction and
top-scores cases passed while its contracts/model/failure fixtures did not.

Production Vec now constructs `View { values, start: 0, length }` directly.
Its initialized length is already an owner invariant, so the fallible factory
adds no validation it needs. This avoids the compiler dependency without
changing bounds, allocation, ownership, or view semantics. No compiler code was
changed. On 2026-10-22, direct, local and imported controls compiled and exited
zero with this implementation. Direct and local controls are included in
`stdlib_alloc_vec_execution`.

Prepare a fresh isolated source root; the harness refuses to overwrite one:

```sh
timeout --kill-after=2s 10s python3 \
  tests/fixtures/stdlib_foundation/vec_view_dependency/prepare.py \
  target/stdlib-work/vec-view-nested --nested-factory
timeout --kill-after=2s 100s target/stdlib-build/debug/laniusc \
  tests/fixtures/stdlib_foundation/vec_view_dependency/direct.lani \
  --stdlib-root "$PWD/target/stdlib-work/vec-view-nested" \
  -o target/stdlib-work/vec-view-nested-program
```

Expect LNC0047 from the second command; do not run its output after a failed
compile. For the working control, prepare a different directory without
`--nested-factory`, compile any of the three entries against that directory,
then run the successfully compiled binary under a ten-second timeout.
`main.lani` needs the copied wrapper module installed by `prepare.py`.
