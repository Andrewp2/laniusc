# Buffered constructor-result chain capture

Status (2026-10-27): still open, and a missing inference feature rather than a wrong result. `with_capacity<T>` binds `T` only through its return type, and the receiving `Vec<u8>` context belongs to the outer `.unwrap()` call. Passing it down needs the method's self pattern (`Result<T,E>`) to project that context onto the inner call's declared result. The receiver-context pass (`calls/03a4b`) does not do that projection yet. The diagnostic now comes from `calls/03a7_validate_required_generics` (slot 0).

`original.lani` is an exact captured copy of the complete buffered composition
fixture before its explicit Result-local adjustment. It is not a newly executed
minimal reduction. Its historical pending-admission header is intentionally
unchanged, as are its real nested `Reader<Reader<_>>` and `Writer<Writer<_>>`
operations. `original.sha256` records the exact bytes:

`8e3695c10cb3951d3fb3ddc37917191ce4b908b005317e46b042340199b66582`.

At compiler checkpoint `59612b3431d7b0cdff16a6faecf881f62a675503`, compilation of
the original fixture failed with `LNC0006` at line 10:

```lanius
let target: alloc::vec::Vec<u8> = alloc::vec::with_capacity(7).unwrap();
```

The diagnostic reported an unknown value type where generic parameter 0 was
expected. The captured log is
`target/stdlib-work/buffered-admission/composition.log` (failed gate, 3.46 s).
No native execution occurred for that failed compilation.

The accepted control remains the ordinary executable fixture at
`tests/fixtures/stdlib_foundation/buffered/composition.lani`. Its only behavioral
source adjustment was to materialize the constructor Result before unwrapping:

```lanius
let allocated: core::result::Result<alloc::vec::Vec<u8>,alloc::vec::Error> =
    alloc::vec::with_capacity(7);
let target: alloc::vec::Vec<u8> = allocated.unwrap();
```

The control passed compilation, the strict ELF/jump checker, native execution,
and the exact allocation/release oracle in 5.77 s. Its log is
`target/stdlib-work/buffered-admission/composition-typed-local.log`.

This records a constructor-chain result-context inference boundary for the
return-only `T` of `with_capacity<T>`. It does not remove or specialize the
generic buffered implementations, and it is separate from their admitted
imported/nested implementation routing. No compiler fix for this chain is
claimed. This captured path itself has not been executed as a separate test.
