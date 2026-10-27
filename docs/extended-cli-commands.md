# Command hierarchies and generated help

Status: implemented, with focused executable acceptance on Linux x86_64.
The complete standard and extended library goal remains open.

`ext::cli_commands` adds command routing to the existing
[option parser](extended-cli.md). `ext::cli_help` measures and renders help from
the same schema. Both are optional Lanius modules loaded through the `extended`
source root. They acquire no owners, allocate no storage and access no host
services. Applications capture argument bytes, provide scratch and output
storage, interpret events, enforce application requirements and perform I/O.

## Schema and option scopes

`Command` contains a stable nonnegative `id`, `parent` declaration index, name,
summary, operands caption, option ordering and `View<OptionSpec>`. Node zero is
the root with parent -1. Every other parent precedes its child. Command IDs are
globally unique; sibling names are exact and unique. There are no aliases,
abbreviations, case folding or environment-dependent spellings.

`OptionSpec` contains the canonical `ext::cli::Spec`, a `global` bit, a value
label and help bytes. The current scope contains all globals from every
ancestor in path order, then all current-node options. Parent locals disappear
after selection. Visible option IDs and enabled spellings cannot collide;
siblings and invisible parent locals may reuse them. IDs for commands and
options belong to separate namespaces.

Names and value labels use ASCII alphanumerics, `-` and `_`, beginning with an
alphanumeric byte. Flag labels are empty; Required/Optional labels are not.
Summary, operands and help reject bytes 0..31 and 127 and preserve all other
bytes unchanged. They need not be UTF-8. Option names retain the canonical
flat parser grammar. The operands caption describes application policy; the
library does not derive arity or validate values from that text.

## Public operations

| API | Contract |
| --- | --- |
| `cli_commands::validate(commands) -> Result<u64,Error>` | Validate every declaration and visible scope; return the largest required option scratch capacity across all descendants. |
| `cli_commands::parser(arguments, commands, scratch) -> Result<Parser,Error>` | Validate the whole schema and capacity before consuming arguments or modifying scratch. |
| `Parser.current() -> i32` | Return the selected command's logical ID, initially the root ID. |
| `Parser.borrow()` | Borrow the same parser for composition; create no independent state. |
| `Parser.next() -> Result<Option<Event>,Error>` | Emit selected commands, scoped options and scoped operands, preserving original locations. |
| `cli_help::help_len(commands, command_id) -> Result<u64,Error>` | Validate the whole schema and measure complete help with checked size arithmetic. |
| `cli_help::help_into(commands, command_id, output) -> Result<i32,Error>` | Validate and measure before writing; return bytes written, preserve the unused tail and append no NUL. All errors preserve the complete output. |

`Event::Command(Selection)` carries the selected ID and original argument
location. `Event::Option(ScopedOption)` carries the declaring command ID and
the unchanged canonical Occurrence, including attached/separate value locations.
`Event::Operand(ScopedOperand)` carries the current command ID and Argument.
Raw operand/value bytes, including empty views, are not normalized.

The first ordinary word selects an exact child when children exist; an unknown
word there fails. Once an actual operand is emitted, subsequent words cannot
select a command. Leaf words are operands even if they equal another command.
EOF requires neither a selected child nor any operands; applications decide
required counts, defaults, repetitions, conflicts and help policy.

Actual `--` permanently ends both option and command recognition. A required
value equal to `--` is ordinary value data. The flat parser's new
`explicitly_terminated()` getter distinguishes this from OptionsFirst stopping
at an operand. Selecting a child opens its option scope and its ordering policy
without resetting the argument cursor or explicit terminator. Inherited globals
obey the selected node's ordering: OptionsFirst stops recognizing them after
its first real operand.

Errors are sticky and EOF is fused. Schema errors identify declaration indices;
`Token(command_id, error)` preserves the canonical lexer error and scope.
`UnknownCommand` preserves the argument location. `ScratchTooSmall` reports the
maximum required capacity, including unvisited branches. `UnknownCommandId`,
`OutputTooSmall(required)` and `SizeOverflow` describe help failures. Invalid
logical view bounds report Bounds; valid physical backing remains a caller
precondition. Exact error variants are in the [contract plan](library-cli-commands-plan.md).

## Storage and help output

Each live hierarchy parser has exclusive scratch. Shallow copies cannot fork
independently over that storage. Keep argument/schema/backing bytes immutable
and alive, and keep scratch disjoint from them. Help output must also be
disjoint from all inputs and live scratch. No runtime alias, reentrancy or
lifetime enforcement is supplied. The original flat Parser's independent
position-copy contract remains separate.

Help is deterministic and uses the selected command path, visible options and
direct child list. It emits no styles or automatic line wrapping. Optional
child selection appears as `[COMMAND]`; a parent operands caption appears as
`[-- OPERANDS]`, matching the explicit escape needed to bypass child routing.
Short/long Required and Optional syntax reflects the actual parser grammar.
The [layout contract](library-cli-commands-plan.md#help-layout) defines the exact
byte format. Rendering uses one shared layout for measurement and writing.

Pairwise schema conflict checks and ancestor walks perform upfront work over
the complete finite schema. Parsing retains the canonical option lookup cost
plus command/owner lookup. Storage is fixed parser metadata plus caller scratch
for the largest visible option scope. Sources and metadata must have valid
backing throughout their use.

## Verification and targets

The actual public parser and help smoke programs compile and exit zero. Both
current semantic Rust tests pass together in 10.10s, separately from a 0.39s
cached test-profile build. They execute 30 schema mutations, six literal help
goldens and 28 curated routing/event/location sequences in one model process.
The tests check scope ownership, sticky errors, fused EOF, actual strides,
nonzero view starts, scratch admission and unchanged output on errors. The
[fixture guide](../tests/fixtures/extended/cli_commands/README.md) records exact
source identities, oracle limits and earlier attempts.

| Gate | Accepted finite result | Receipt under `target/stdlib-work/` |
| --- | --- | --- |
| Current semantic tests | Both registered tests pass | `cli-commands-semantic-owner-aliases.log` |
| Existing flat-parser regression | One selected executable test passes in 6.04s, after a separate 2.32s build; seven other tests were filtered out | `cli-commands-flat-parser-regression-first.log` |
| Pure contract and public smokes | All exit zero with empty output; full syscall traces contain only launch and final raw exit, with all mmap attempts configured to fail | `cli-commands-contracts-aliases-no-host.{trace,log}`, `cli-commands-{public-smoke,help-smoke}-no-host.{trace,log}` |
| Migrated real application | Three direct groups pass 130 overlapping group cases: hierarchy66, roundtrips33, publication31, including 13 reached allocation failures and 15 I/O faults | `cli-commands-kv-{hierarchy,roundtrips,publication}-all-syscalls.log` |

The pure programs make no allocation attempt, so the denial configuration does
not establish OOM recovery. The model intentionally uses stdin/stdout transport.
Application receipts observe every syscall and retain their own owner/failure
contracts; they are not three passing Rust libtests. See the
[KV application guide](extended-kv.md#current-application-receipts).

Accepted production SHA256 values are `9f11981f...` for the flat parser,
`6eb4db7a...` for command routing and `a7198a2a...` for help. The application is
`f07fd52f...`. Runtime evidence is native Linux x86_64 CPU output from the GPU
compiler. Importing these modules establishes no user-program GPU execution or
other host support. Public APIs in this increment contain no silent no-op
implementation.

A separate [minimal compiler reproduction](../tests/fixtures/stdlib_compiler_state/cli_help_nested_error/README.md)
shows LNC0057 for two nested Result/local-error assertion patterns. A typed
outer error extraction followed by an inner Error match compiles and executes
the same payload assertions. This dependency does not block the public APIs;
no compiler cause or general nested-pattern restriction is established.

Response files, shell completion and richer application validation remain on
the [library roadmap](library-roadmap.md). Compiler dependencies remain in the
[dependency ledger](library-dependencies.md); this increment changes no
compiler IR, ABI, extraction, proof or runtime implementation.
