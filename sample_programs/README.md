# Sample Programs

This directory contains small source-level examples for the current alpha
language slice. Each top-level `*.lani` file should have a sibling `*.stdout` file with
the expected stdout bytes for the same basename.

These examples are documentation and smoke-test fixtures. They are not
performance evidence, language-conformance proof, or a claim that every sample
currently runs on every backend. Promote a sample into an acceptance gate only
when the gate names the exact target, command, expected output, and unsupported
features it is meant to cover.

Current fixture contract:

- Keep sample sources small and readable for external users.
- Keep expected stdout deterministic and newline-explicit.
- Add every sample to `MANIFEST.tsv` with the language slice it demonstrates.
- Do not use a sample as evidence for packages, imports, stdlib execution,
  x86 support, or performance unless a behavior-facing test or measured
  artifact explicitly validates that claim.
- If a sample demonstrates a source-level helper that is frontend-only today,
  say so in the test or docs that promote it.

The `library/` directory holds application examples whose arguments, binary
output or additional source roots require dedicated execution tests. Each has
documented commands, target support and failure cases; the top-level fixed-input
manifest runner does not discover subdirectories. See [library/README.md](library/README.md).
