# Checked layout direct contracts

The direct executable gate passed on its first run: one registered test in
4.68 seconds, recorded in `target/stdlib-work/layout-direct-first.log`.
Root ran the compiler, Cargo and native commands.

`contracts.lani` has four finite scenario functions and directly calls all
eight public layout functions plus MAX_SIZE. Literal expectations distinguish
unpadded size, padded size, array stride and record-field offset; this suite
does not rely on roundtrips or compiler-native record layout.

Coverage includes zero size with alignment 2^63, exact MAX_SIZE boundaries,
large power-of-two alignment, array count zero retaining stride, count
usize::MAX with zero stride, product/domain overflow and a product that would
wrap below MAX_SIZE without admission. Padding checks oversized offsets even
when required padding is zero and rejects an addition that would wrap.

Forged and mutated public Layout values are revalidated. Tests require
alignment-before-size precedence within a value, left-before-right admission
for extend and input-before-requested-alignment admission for align_to.
An extend case has offset+size within MAX_SIZE but fails final alignment
rounding. Invalid inputs and valid transforms preserve caller copies.

The accepted gate compiled genuine x86_64 ELF, applied the shared jump checks
and executed one native process containing all four scenario functions. Its
full syscall trace contained exactly one process entry and one exit, with no
heap, I/O or other host effects. Arithmetic-valid huge layouts make no
allocation-availability claim. Executed target scope is Linux x86_64 CPU
output from the GPU compiler; device execution and formal correctness are
unclaimed.

The fixture and production sources were unchanged for this receipt:

| Source | SHA-256 |
| --- | --- |
| `contracts.lani` | `c27abb3ef64ea1876dd7d17b6bf956803c9147ff5adf28da3c9ae7755542cdb5` |
| `stdlib/core/layout.lani` | `d6e302727f3b865711f3904c7139efd0afdaa82fd438778124ddf23b0334c5a4` |

```text
cargo test --test stdlib_layout_execution checked_layout_arithmetic_executes_literal_boundaries_without_host_effects -- --exact
```
