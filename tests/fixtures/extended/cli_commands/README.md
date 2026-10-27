# Command hierarchy and generated help verification

Status: both current semantic tests passed together in 10.10s. The current
contract program also passed a separate all-syscall trace with mmap denied.
Two direct public smoke admissions passed separately. This finite increment is
accepted; the overall standard and extended library goal remains open.

## Contract and oracle

All probes import the actual `ext::cli`, `ext::cli_commands` and `ext::cli_help`.
The schema separates logical IDs (40,17,91,6) from parent indices (-1,0,1,0).
Root globals and a middle ancestor global are inherited; invisible parent
locals and sibling scopes legally reuse option identities and spellings.
Schema, argument, token, scratch and help-output views exercise nonzero starts;
options and records use actual native element strides. No substitute lexer or
router is implemented in Lanius.

`model.py` supplies 28 curated lexical event/location expectations. It does not
parse option strings. A separate small command-parent/visibility/current-state
model checks each expected sequence before comparing every byte of the native
binary event stream. The cases cover:

- Empty/root/branch/leaf EOF without application operand requirements.
- Exact child routing, inherited globals and legal same-ID local reuse, with
  the actual declaring-command ID.
- Required values swallowing command words or `--`, attached-only optional
  values, short bundles, empty attached values and raw NUL/255 operands.
- Actual `--` disabling routing, OptionsFirst resetting after selection, and
  the current command's ordering controlling inherited options.
- Original logical argument and byte positions, including failures inside a
  short bundle and attached long values.
- Unknown child/options, missing/unexpected values, sticky repeated errors and
  fused EOF. The native probe repeats terminal calls before its final frame.
- The actual command ID carried by `Error::Token`, asserted against the current
  command before serialization; this field is also retained on repeated errors.

`contracts.lani` emits nothing on success. It checks 30 explicit schema
mutations through validation, parser construction and both help entrances,
plus malformed logical views, all-scope scratch capacity and admission order.
Sentinel checks compare every scratch field, and failed help calls preserve the
entire output. Physical backing validity remains the caller's obligation; no
forged physical element count or alias detector is claimed.

The six literal help goldens are root, branch, leaf, sibling, a bare single-node
schema and one node with six single-alias options. The branch golden contains
raw byte 255. Together they check inherited option order, all arities with both
aliases and with only short/long enabled, child order, captions and omitted
sections, exact measured/written lengths, exact/oversized/zero/short output,
unknown IDs, logical bounds, no NUL and unchanged unused bytes. Invalid schema
precedes ID lookup, malformed token descriptors and output mutation. The added
single-alias golden is 105 literal bytes, exercising Flag/Required/Optional
spellings with the opposite alias disabled.

Two independent live parsers are interleaved using separate scratch storage.
This is not a shared-scratch fork or reentrancy guarantee. Schema/argument/name
backing stays live and immutable during parsing; output never overlaps inputs
or scratch. Required operands, help handling, repetitions and application
policy remain outside these parser contracts.

## Finite gates

Root serializes compiler and native work. Each command stays below two minutes;
these fixtures do not require broad CLI or library reruns.

```text
cargo test --test extended_cli_commands_execution --no-run
hierarchy_schema_scratch_and_generated_help_contracts_execute
hierarchy_routes_match_curated_scope_and_location_sequences
```

The first test compiles and executes `contracts.lani`, requiring empty stdout
and stderr and status 0. The second compiles `model.lani`; its Python peer sends
all 28 bounded binary records in one process, requiring status 0, empty stderr
and the exact whole output with no ignored suffix. The Rust transfer path
validates the emitted ELF through the established `TempArtifact` machinery.
Native process deadlines are five and 25 seconds respectively; the Python
child's deadline is 15 seconds. Neither direct smoke is redundantly registered
and rerun through this Rust test driver.

CPU-only check (no Lanius compiler or native execution):

```text
python3 -B tests/fixtures/extended/cli_commands/model.py --self-test
cli-commands model CPU controls=13
```

The 13 controls include record/count invariants, rejected byte-stream variants
and invalid scope/parent expectations. They are separate from native acceptance.
Four original single-case negatives compared against the all-case baseline and
rejected by length. The corrected helper compares each changed final-tag byte
against its own same-length case. Comments claim only missing/trailing bytes,
magic-byte and final-tag changes. The corrected CPU controls ran once and
passed; they do not claim independent mutations of every serialized field.

## Current frozen files and acceptance

| File | SHA256 |
| --- | --- |
| `contracts.lani` | `6cd4fffe50fc9a3f1356cc70862f8d723fa005069fb0416055ed9b1112f63ea9` |
| `model.lani` | `699fcdc55491cf5727b0eaae439f242da616406160e234ed1411a59dca47a3df` |
| `model.py` | `373a3bc943dd0f789956ee782214a5b0187bd0753c0f5fa07d7372520c15b448` |
| `tests/extended_cli_commands_execution.rs` | `447cf624d78526b9a699488b5b1c2e9cfb28b41393213a27913691b9add70ca7` |

The executed contract source was `401559646bd423cd5fc1cfffa63fdd39354f8ee67e77af95c2dd8d6c125bd712`.
The sole post-verification source change removes four spaces from each of the
otherwise empty lines 160 and 162. Restoring those spaces reconstructs the
executed bytes; all tokens, statements and assertions are unchanged.

`target/stdlib-work/cli-commands-semantic-owner-aliases.log` records both current
Rust semantic tests passing together in 10.10s after a 0.39s cached build. All 28
routing records and the current contract's six goldens/30 schema mutations ran.
The test binary is `extended_cli_commands_execution-26ed138724515bec`.

| Retained native executable | ELF SHA256 |
| --- | --- |
| `/tmp/cli_commands_native_model_lani_516010_0` | `5bc43f50ea50ac3f3e258777d4f6ef7e09b1634a3d2dda6a19ab86ffbfc84c3a` |
| `/tmp/cli_commands_native_contracts_lani_516010_2` | `157d150c12ea1f5cabf64586dd7fe256fcbfa82a52d65f314dc11ade787aab4a` |

Accepted production SHA256:

- `ext::cli`: `9f11981f1292bea61c3c571ff86b0fcdba52259c8e626886e4e6b322557a17cd`.
- `ext::cli_commands`: `6eb4db7ad6f63768a3fe96c6aee6dec55560f8d098efe7a5dbbbfff5e7cb536f`.
- `ext::cli_help`: `a7198a2a18f6dcac549fb08c5735af538689b76f53b0be4e942798227ec9f60a`.

Application roundtrips and publication faults have separate receipts in the KV
fixtures. Supported execution evidence here is Linux x86_64 CPU programs
emitted by the GPU compiler. User-program GPU execution, another host target,
general compiler correctness and the whole library are not established.

## Direct public admissions and pure-program traces

The direct parser and help public smokes compiled and executed with exit 0.
Their narrower public-binding scope is separate from the semantic tests above.
All following logs are under `target/stdlib-work/`:

| Admission | Compile log | Native log |
| --- | --- | --- |
| Parser smoke | `cli-commands-public-smoke-qualified.log` | `cli-commands-public-smoke-native-first.log` |
| Help smoke | `cli-commands-help-smoke-explicit-errors.log` | `cli-commands-help-smoke-native-first.log` |

| Smoke | Source SHA256 | ELF SHA256 |
| --- | --- | --- |
| `smoke.lani` | `6a0e7f9f35ad4a781cd81cd40e5b2794c1ae6c166c2b167631010daae108c8fe` | `e1698fe7a7e90b62097abaa2e393550ba2f6ccec7cb105990edb2e8c4c51a1e6` |
| `help_smoke.lani` | `aada787fd286350063f316c37824f4f92b9a2f9b94e0e56bba1c254bde1315f2` | `6900173ea5552a8cecac24dbf8cae188ed4b7522df9dcc6bd677b5c7eef98d77` |

Root reused the current contract ELF and both smoke ELFs under `strace` with
`trace=all` and `inject=mmap:error=ENOMEM:when=1+`. Each exited 0 with empty stdout
and stderr. Every trace contains exactly the launching `execve(...)=0` and
final raw `exit(0)=?`: no mmap was reached to inject, and no other host-service
syscall was attempted during these finite programs. This is not injected-OOM
recovery evidence or a proof about every possible schema.

| Program | Trace and empty process log, under `target/stdlib-work/` |
| --- | --- |
| Current six-golden contract (40155964) | `cli-commands-contracts-aliases-no-host.trace`, `cli-commands-contracts-aliases-no-host.log` |
| Direct parser smoke | `cli-commands-public-smoke-no-host.trace`, `cli-commands-public-smoke-no-host.log` |
| Direct help smoke | `cli-commands-help-smoke-no-host.trace`, `cli-commands-help-smoke-no-host.log` |

The routing model uses intentional stdin/stdout and was not rerun for a pure
program claim. Compiler initialization outside these native programs is not
included. No extra GPU compile or unrelated library run was needed for these
retained-ELF observations.

## Earlier attempts and verification corrections

`cli-commands-semantic-first.log` records the first driver build (2.13s) and
both tests failing before native execution (mixed duration 5.92s, zero passes).
`model.lani:85` and `contracts.lani:74` reported LNC0005 because importing
`core::slice::View` did not import module functions. Adding `import core::slice;`
to both fixtures changed no body or assertion. No production bug was inferred.

The import-only retry passed both tests together in 8.93s after a 0.20s cached
build: `cli-commands-semantic-import-retry.log`. This is a historical receipt,
separate from the current 10.10s receipt. Its source hashes were:

- Model: `48be1d019743065dc095f11c36ac3cf6e385738dd4d7106f8a0802d1f9c2a740`.
- Contract: `3512ab72a975db34bb616016816f1b1309058faf015f575f08d08aed8aa2220b`.
- Python: `93fe4bdd79c28de5afdde2dac6551b25756860c2978765824a5a4d42cc618891`.

The earlier model ELF `/tmp/cli_commands_native_model_lani_510274_0` was
`75ea647ed2ff3516bc5ad8f8130eab6b7252ed3ef907fe4e7f9e2a2d568f18e0`;
the earlier contract ELF `/tmp/cli_commands_native_contracts_lani_510274_2` was
`d5a4f0422f9ea7e05cd2c844712da0fb7ae73fe27404b914f227d57405f06382`.
The earlier contract's equivalent pure trace is
`cli-commands-contracts-no-host.trace` with empty `...-no-host.log`. Neither old
contract acceptance nor 8.93s timing is substituted for the final strengthened
fixtures. These are repeated gate receipts, not additional independent cases.

Independent read-only review found that the original error frame serialized
`parser.current()` without comparing the actual Token command ID. The current
model asserts that retained ID first, while leaving wire expectations unchanged.
UnknownCommand has no carried command ID and is excluded. The review was
independent of the fixture author, not independent of the production author.
The single-alias golden and corrected same-case CPU comparisons then closed the
remaining concrete review limits; no production change was justified.

The parser public smoke's first pre-native failure used an unqualified leaf
module call (`slice::view`); qualification corrected that fixture. The help
smoke's initial LNC0057 arose from unnecessary nested Result/error assertions.
Typed Error extraction and a single Error match preserve those exact assertions
and admit the same consumer. The confirmed compiler-state reduction is in
`tests/fixtures/stdlib_compiler_state/cli_help_nested_error/README.md`; it does
not demonstrate a production help or buffer-preservation failure. No general
nested-pattern restriction or common cause with other diagnostics is claimed.
