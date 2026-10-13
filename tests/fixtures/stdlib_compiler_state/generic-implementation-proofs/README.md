# Conditional and blanket implementation evidence

`verification.json` indexes 19 distinct selected tests. Eight tests use the final
build for this checkpoint: five native execution/rejection tests, two retained
owner tests, and one direct GPU matcher test containing 32 cases. Three proof
packet tests and eight host replay tests were run on earlier integration builds.
Each run records its own binary hash and deduplicated source/shader manifests.
No cross-build equivalence is inferred from a shared test name.

Native success means the GPU compiler emitted an x86_64 Linux ELF and the test
executed it, checking its result. Negative cases check diagnostics before any
ELF returns. GPU cases check the physical device's output. The method-boundary
case intentionally verifies an unfinished feature remains an explicit rejection.
These tests do not establish user-program GPU execution or complete generics.

The eight final-build tests cover nested and imported conditional implementations,
blanket heads, arrays at distinct lengths, overlap/missing/cyclic proof rejection,
exact declaration ownership, lexical shadowing, and the matcher state machine.
The earlier proof tests cover caller-owned imported selection, symbolic proof
forwarding with separate replay occurrences, and corrupted pending proof records.
The host tests check replay provenance, immutable ordinary siblings, omitted
template emission, and native call ownership.

`pipelines/` retains the unsuccessful combined matcher probe as well as successful
family probes and shader validation. Individual pipeline preparation populated
the driver cache before executable tests. These records cannot establish cold
end-to-end compilation or current large-workload performance. Test and build
commands were bounded below two minutes.

Reproduction entrypoints are in `tests/compiler_generic_types_execution.rs`
(`generic_marker_`), compiler library `gpu::owned_constraint_tests`, and the
compiler's `x86_codegen::tests` owner-retention tests. Exact filters and commands
are in the run records; absolute scratch and binary paths describe this machine's
recorded runs rather than a required project layout.
