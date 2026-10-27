# Portable completion verification

Status: the frozen pure contract compiled/executed successfully, including an
all-syscall trace with mmap denied. The 67-case model passed its first focused
Rust gate. The direct public prefix smoke also compiled and executed under
no-host tracing. Current acceptance is two direct pure programs plus one Rust
model test; the Rust contract registration was filtered out. Shell adapters, Bash
decoding and the real application retain separate acceptance. The overall
standard and extended library goal remains open.

## Contract and finite model

Both probes import the actual `ext::cli_complete`, canonical `ext::cli` and
`ext::cli_commands`. The schema has logical IDs 40/17/91/6 and parent indices
-1/0/1/0. It includes root and middle-ancestor globals, disappearing parent-local
options, legal reused local option IDs and Flag/Required/Optional arities.
Profiles use both Intermixed and OptionsFirst, including reset after selection.

`model.py` does not parse command lines. Complete-word transitions and active
contexts are authored explicitly. A separate literal schema/value catalog
supplies candidates filtered with byte-prefix comparisons. The reference uses
neither the producer's parser state nor its candidate ordinal/rendering machinery.
One native process receives 67 bounded binary records, 13 of them errors. No
production binary transport, JSON or other library implementation is added.

The cases check:

- Selection and operand index, active versus completed command words, child
  routing and no implicit required-operand policy.
- Ancestor/global identity, scope ordering and local-option disappearance.
- Pending Required values, command-looking values, actual `--` versus a
  required value equal to `--`, and attached-only Optional values.
- Long names and added `=` for value-taking names, initial `-`/`--`, complete
  flag-cluster finish and ordered short continuations, unknown final shorts
  and strict errors for earlier unknown shorts.
- Declaring-command/option identities, candidate kinds, caller spacing flags,
  repeated policy values and raw non-UTF-8 byte prefixes.
- Whole active-prefix replacement ranges and full stem+candidate output bytes.
- Cursor suffix and later-word independence, including ignored NULs. Candidate
  spacing is intentionally suppressed when the cursor is inside a word.
- Canonical complete-token/active-prefix failures, exact locations, NUL and
  cursor bounds.

After every successful Context construction the native model overwrites all
construction scratch before asking for suggestions. Context must retain no
scratch lease. Each iterator is copied, and both independent positions are
advanced against native negative-stride and packed positive-stride output.
Every candidate's bytes, identities, kind, spacing and replacement range are
compared, and output prefixes/tails remain canaries. EOF is repeated and fused.
All argument/schema/value backing remains live and immutable until its last use.

## Pure contract program

`contracts.lani` is a stack-backed, empty-output program. Its direct executable
checks all public Context getters and all three APIs. It checks:

- Eight literal root suggestions: direct children first, then short/long aliases
  in declaration order. Values are not offered in a command-selection context.
- OutputTooSmall and logical output bounds preserving the entire buffer and
  iterator position, followed by exact-capacity retry and independent forks.
- Real negative and positive output strides, nonzero starts and unused tails.
- Scratch reuse after Context creation, schema admission and maximum-scope
  scratch capacity before malformed completed words, and logical input bounds.
- Full caller-Value admission, invalid nested ranges and exact ValueNul location.
- Attached values producing full `--config=...` replacements with literal prefix
  filtering, identities and caller-selected spacing.
- An empty value succeeding in a zero-capacity output, then fused EOF.
- Six single-alias Flag/Required/Optional candidates with the opposite spelling
  disabled, including exact bytes and spacing.

Physical backing validity, immutable input lifetimes and disjoint output remain
caller preconditions. Native record and byte-array layouts, packed output,
nonzero views and byte validation exercise actual strides; no forged physical
length or runtime alias detector is claimed. This is portable API verification,
not shell-word decoding, filesystem enumeration or Readline insertion behavior.

## Bounded gates and CPU checks

Root serializes compiler/native work. The Rust driver validates emitted x86_64
ELFs through the existing TempArtifact path. Its two registrations are:

```text
completion_context_candidate_atomicity_strides_and_forks_execute
completion_contexts_and_candidates_match_finite_transition_catalog_model
```

Driver: `tests/extended_cli_complete_execution.rs`. Build only that driver with
`cargo test --test extended_cli_complete_execution --no-run`. The contract
registration requires status 0 and empty stdout/stderr with a five-second native
deadline. The model uses a 15-second child deadline and a 25-second parent
process deadline, comparing the complete binary receipt with no ignored suffix.
Its success line is `cli-complete model cases=67`. Root need not repeat the
already accepted direct contract just to produce a different launcher receipt.
Every root command must stay below two minutes; no broad old test rerun is needed.

CPU-only check, without compiling or executing Lanius:

```text
python3 -B tests/fixtures/extended/cli_complete/model.py --self-test
cli-complete model CPU controls passed
```

Controls check unique cases/fixed record lengths, same-case byte mutation
rejection, raw-prefix candidates and suffix/later-word relations. A first
CPU-only relation mistakenly paired `--con` with `--ver`; the author corrected
that helper to compare matching `--ver` prefixes before freezing. No Lanius
source or expected runtime behavior changed to appease that helper mistake.
Untracked source/driver files were checked explicitly for trailing whitespace.

## Frozen files

| File | SHA256 |
| --- | --- |
| `prefix_smoke.lani` | `4802575df887ef5f4a9426d3f3ff630a4ee79402f8f471a375cd7aea5d669c15` |
| `contracts.lani` | `9281ca337f330a9f41debc1d26c63f6cca26f70a609736dd1be8a9f15f38946e` |
| `model.lani` | `d29b47e103c2ac11c961ac8b62e1731bee9fc3d3bb75aa27872727c2a6def011` |
| `model.py` | `a69b17007c413b6b03c2f671acec55a3e38f3321a77b50296f0c1ebc1cd23e90` |
| `tests/extended_cli_complete_execution.rs` | `7b9989105095c037d555c518bcbe8b343ce8a9779dca16278f59db551ed2a1a6` |

## Actual direct-program receipt

Root reports direct CLI compilation exit 0 for the frozen `9281ca33` contract:
`target/stdlib-work/completion-core-contracts-compile-first.log`. The retained
program then exited 0 with empty output under all-syscall tracing and all mmap
calls denied. `completion-core-contracts-no-host.trace` contains only successful
launch `execve(...)=0` and final raw `exit(0)=?`; its matching process log is
empty. No allocation was attempted, so no injected OOM recovery is established.
This finite observation is separate from a Rust test-runner pass.
The retained direct executable is
`target/stdlib-work/completion-core-contracts.elf`, ELF SHA256
`0e326060bf6c2f74ea690dd7aced44351f75035748ee2422d6f608dca7ca67ac`.

The direct program binds completion source
`f863a063f846a34c6fcc989ec97b59733c77ea7022a1e6c925276e7c5ac2667d`
and the accompanying canonical parser changes. The selected existing flat-parser
regression passed separately in
`target/stdlib-work/completion-flat-parser-regression-first.log`. Both existing
hierarchy tests also passed together in 9.91s in
`completion-hierarchy-regressions-first.log`, after the shared flat/hierarchy
regression driver build in 4.90s recorded in
`completion-parser-regressions-build-first.log`. These are targeted regressions
for the canonical parser extension, not an all-parser-suite claim. Independent
fixture review is not claimed without a separate receipt. No successful type
check alone establishes working behavior.

Executed target evidence is Linux x86_64 CPU code emitted by the GPU compiler.
No user-program GPU execution, other host target, Bash adapter, filesystem
provider, completion subprocess or real application acceptance follows from
this direct portable-program receipt.

## Direct public prefix-boundary receipt

`prefix_smoke.lani` calls the actual flat `cli::prefix_parser` and scoped
`Parser.pending_required` APIs directly. It distinguishes strict sticky
`MissingValue` at argument 0, byte 2 from explicit prefix pending state; checks
the returned complete Spec and Location, repeated fused EOF, and pending-value
classification of an active `--raw` word. The scoped case selects logical
command 709 while preserving inherited-global declaring command 101, option
741 and the exact short-option location at argument 1, byte 1. It checks the
scoped pending getter, selected command, operand index, child-selection status,
options-ended status and returned scoped Prefix identity.

Compilation exits zero with an empty log in
`target/stdlib-work/completion-prefix-smoke-compile-first.log`. The retained
`completion-prefix-smoke.elf` exits zero with empty output; its full
`completion-prefix-smoke-no-host.trace` contains only successful `execve` and
raw `exit(0)`. The matching `.log` is empty. All mmap calls were configured to
fail, but none was attempted: this proves no allocation attempt in this finite
program, not OOM recovery. ELF SHA256 is
`9e1ccb26150542a8c6a01224f15a8229b121774ccedefd8d3581bd5a3f7d4c3d`.

Production sources remain the canonical hashes listed below. This is a direct
public-wrapper and returned-record execution receipt, separate from the Context
model and any Rust libtest execution. It adds no shell/PTY or host-target claim.

## Actual first model receipt

`target/stdlib-work/completion-core-model-first.log` records
`completion_contexts_and_candidates_match_finite_transition_catalog_model`
passing on its first attempt in 6.76s: one Rust test passed and the contract
registration was filtered out. All 67 records ran in one native model process
and matched the exact expected receipt. The test command's cached Cargo step
was 0.19s. The separate driver build was 1.88s in
`completion-core-driver-build-first.log`; none of these durations is combined
with the separate contract or parser-regression receipts. The test binary is
`extended_cli_complete_execution-8ac8f63121265362`.

The retained model executable is `/tmp/cli_complete_native_model_lani_601820_0`,
ELF SHA256 `dfea64f0e5444dd4e7c506fdde47b70b6631840cf8183c68e721b4ef3c709d9e`.
The frozen source hashes above are unchanged; no compiler/fixture correction
or assertion weakening was needed. Root performed all compiler/native runs;
the fixture author performed only source/static work and CPU model checks.

Canonical production sources:

- `ext::cli`: `b47aae7274d69b161ffd0a1138781cff8bf5fcdf33d88ddd493c86ddb4cb689c`.
- `ext::cli_commands`: `5dae984290283ab6ba4aa6e4cdd529e706ceea6fc017cc65767818934b239888`.
- `ext::cli_complete`: `f863a063f846a34c6fcc989ec97b59733c77ea7022a1e6c925276e7c5ac2667d`.

The model deliberately performs stdin/stdout framing and is not included in the
pure no-host claim. Actual shell/PTY adapters, file enumeration, application
queries and Bash decoding remain separate; no coverage for them is inferred
from portable Context/candidate execution.
