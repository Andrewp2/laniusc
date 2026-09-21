# Lanius formal foundation

The old proof forest has been deliberately removed. The reset deletes 315,049
tracked Lean lines; the surviving `formal/Lanius` tree, including the
replacement architecture, is 20,810 lines.

The retained foundation defines Lanius and Core syntax and semantics, an
independent mathematical lexer, the artifact/deep-embedding boundary, and x86
machine encodings and semantics. It does not yet prove the parser, extractor,
compiler, or x86 backend end to end.

## Current proof gate

The replacement proof covers artifact function IDs 0 through 7:

- five primitive byte predicates;
- `classify_start`;
- `scan_identifier_end`;
- `scan_whitespace_end`.

These are the actual quoted Core functions. The scanner proofs are total,
prove exact maximal-prefix results, preserve the caller frame and source, and
check all bounds and signed-i32 increments. Their public contracts hide fuel
and evaluator bookkeeping.

The functions contain 103 nonblank executable Lanius lines. A conservative
classification counts about 594 program-specific Lean lines (5.77x) and 2,831
reusable lines. The whole matched replacement scope is 3,425 lines.

Measured on September 19, 2026:

- focused scanner theorem: 1.30 seconds;
- clean connected build: 25.27 seconds;
- cached connected build: 0.45 seconds.

The connected proof contains no `sorry`, custom axioms, or `native_decide`.
Public theorem audits report only Lean's standard axioms.

Source-byte provenance is proved, but source-to-Core generation is not. The
artifact/exporter boundary therefore remains explicitly untrusted.

## Build

```sh
cd formal
lake build +Lanius
```

## Scaling rule

Each new family must prove the actual quoted program and the total contract its
caller needs, keep program-specific code near 5x source, check in seconds after
shared infrastructure is built, and reuse the existing semantic families.
Shared infrastructure is counted separately and must not grow linearly with
each new function.

See `PROOF_ARCHITECTURE.md` for the trust boundary, measurements, and restart
plan.
