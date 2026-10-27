# Command hierarchy and generated help

Status: contract frozen; implementation and focused executable gates accepted
on the native Linux x86_64 profile below.
The full standard and extended library goal remains open.

## Intent and boundaries

Complete the command-routing and automatic-help gaps in `ext::cli` without a
second option lexer. The existing parser remains authoritative for spelling,
values, locations, ordering and sticky errors. The
[GNU argument conventions](https://sourceware.org/glibc/manual/2.24/html_node/Argument-Syntax.html)
provide the underlying syntax context; Lanius retains its explicit attached-only
optional values, exact long names and non-reordering event contract.

Use two optional pure Lanius modules: `ext::cli_commands` owns schema admission
and routing; `ext::cli_help` measures and renders plain help into caller storage.
Neither allocates, invokes a host service, prints, exits, expands response files
or performs shell splitting. Required operands, repetitions, conflicts, defaults
and help handling remain application policy, as in the existing flat parser.
Response files and shell completion remain separate CLI work.

## Frozen API

Names below are in `ext::cli_commands` unless qualified otherwise:

```lani
pub struct OptionSpec {
    spec: ext::cli::Spec, global: bool,
    value_name: core::slice::View<u8>, help: core::slice::View<u8>
}
pub struct Command {
    id: i32, parent: i32, name: core::slice::View<u8>,
    summary: core::slice::View<u8>, operands: core::slice::View<u8>,
    ordering: ext::cli::Ordering, options: core::slice::View<OptionSpec>
}
pub struct Selection { id: i32, at: ext::cli::Location }
pub struct ScopedOption { command: i32, occurrence: ext::cli::Occurrence }
pub struct ScopedOperand { command: i32, argument: ext::cli::Argument }
pub enum Event { Command(Selection), Option(ScopedOption), Operand(ScopedOperand) }
pub enum Error {
    Bounds, EmptySchema, InvalidCommand(i32), DuplicateCommand(i32),
    InvalidOption(i32,i32), DuplicateOption(i32,i32),
    ScratchTooSmall(u64), UnknownCommand(ext::cli::Location),
    Token(i32,ext::cli::Error), UnknownCommandId(i32),
    OutputTooSmall(u64), SizeOverflow
}
```

- `validate(commands:View<Command>) -> Result<u64,Error>` validates the entire
  hierarchy and returns the maximum visible option count across every node.
- `parser(arguments:View<View<u8>>, commands:View<Command>, scratch:View<ext::cli::Spec>)
  -> Result<Parser,Error>` admits the complete schema and scratch capacity before
  consuming arguments or changing scratch. `Parser.borrow()`, `current()->i32`
  and `next()->Result<Option<Event>,Error>` expose the resulting state.
- `ext::cli_help::help_len(commands:View<Command>, command_id:i32)
  -> Result<u64,Error>` validates and measures the complete output.
- `ext::cli_help::help_into(commands:View<Command>, command_id:i32, output:View<u8>)
  -> Result<i32,Error>` validates and measures before writing. Failure preserves
  the entire output; success preserves its unused tail and adds no NUL byte.

## Schema and state contracts

Node zero is the sole root and has parent -1. Every later parent is an earlier
node index, not a logical ID. IDs are nonnegative and globally unique; sibling
names are unique. Names and value labels start with an ASCII alphanumeric byte
and continue with ASCII alphanumerics, `-` or `_`. Names are nonempty.

Option spelling/id/arity validation uses the existing `ext::cli::parser` on a
private one-element stack schema and no arguments. Flag value labels must be
empty; Required/Optional labels must be nonempty. Summary, operands and option
help preserve arbitrary bytes except ASCII controls 0..31 and 127. They need
not be UTF-8. Other spellings retain the existing option grammar.

An active option scope contains all global options from every ancestor, in
root-to-parent order, then every current-node option in declaration order.
Duplicate IDs or enabled short/long spellings within any visible scope reject
the complete schema. Sibling scopes and invisible parent locals may reuse
spellings and option IDs. Schema errors identify declaration indices; option
events identify the declaring command's logical ID. Ordinary operands identify
the current command. Locations retain original argument and byte indices.

The first ordinary word in a scope selects an exact child if children exist;
an unmatched word then returns UnknownCommand. After the first actual operand,
no later word can select a child. Leaf words are ordinary operands, even when
they equal another command name. EOF imposes no required-child/operand policy.
No help spelling or ID is implicitly reserved.

An actual `--` permanently disables command and option recognition. A required
option value equal to `--` does not. Add a minimal explicit-terminator bit and
`explicitly_terminated()->bool` getter to the canonical flat Parser; only its
actual terminator branch sets the bit. On child selection preserve all global
argument indices and that bit, replace only option scope/ordering, and reset
the OptionsFirst stop caused by the selected command. Globals obey the current
node's ordering: OptionsFirst disables them after its first actual operand.
Errors are sticky; EOF is fused, with no later argument consumption.

Each live hierarchy parser exclusively borrows its scratch. Copies transfer
that authority and cannot independently fork over shared mutable scratch.
Keep argument/schema/name backing immutable and live. Scratch must not overlap
those inputs, and help output must not overlap any input or live scratch.
No runtime alias/reentrancy/lifetime enforcement is claimed. Views must have
valid physical backing; reject invalid logical starts/counts and arithmetic
overflow without claiming compiler physical-length projection.

## Help layout

Rendering is deterministic, unstyled and unwrapped. It copies admitted metadata
bytes unchanged. Both size accumulation and output capacity are checked.

1. `Usage: `, root-to-selected path separated by spaces, then ` [OPTIONS]` if
   the selected scope has options, ` [COMMAND]` if it has children, and the
   nonempty operands label. A node with children prefixes its operands caption
   with ` [-- ` and closes `]`; a leaf prefixes it with one space. End with LF.
2. Nonempty selected summary followed by LF.
3. If options exist, `\nOptions:\n`, then each visible option on its own line.
   Start with two spaces. Flag syntax is `-s` and/or `--long`; Required adds
   ` <VALUE>` to each enabled spelling; Optional short adds `[VALUE]` and long
   adds `[=VALUE]`. Join enabled aliases with `, `. Append four spaces plus
   nonempty help, then LF. Show inherited options in scope order.
4. If children exist, `\nCommands:\n`, then each direct child in declaration
   order: two spaces, name, four spaces plus nonempty summary, and LF.

Optional `[COMMAND]` is intentional: the parser does not enforce required
selection. The application may impose stricter arity after complete parsing.

## Implementation and executable acceptance

1. Admit the actual public modules with nested command selection, inherited
   globals, required/optional values and exact-size generated help.
2. Check unvisited invalid descendants, visible collisions, allowed out-of-scope
   reuse, maximum descendant scratch capacity, negative/nonzero view bounds,
   output atomicity/canaries, raw bytes and actual slice strides.
3. Compare curated command/action/event sequences against an independent
   routing model plus the canonical lexer contract. Cover sticky errors, EOF,
   command-looking values, terminators and per-scope ordering resets.
4. Verify the pure library contracts execute with all allocation attempts
   denied and no unexpected host effects. Do not create an irrelevant owner/OOM
   campaign for APIs that acquire no owners.
5. Migrate `kv_tool` command collection/help. Retain its data-store, path and
   publication owners; document the new `--` escape for dashed DB names.
   Use bounded argument/help storage, validate the whole CLI before effects,
   and check root/child help plus no-I/O errors. Reuse substantive store and
   atomic-publication gates; preserve their historical source scope.
6. Document finite target/evidence and remaining CLI/compiler dependencies;
   regenerate declaration references after the source freeze.

Commands remain below two minutes. Root serializes compiler/native gates.
The selected runtime target is Linux x86_64 CPU output from the GPU compiler,
with no claim of user-program GPU execution or another host target.

## Accepted evidence

The public parser/help smoke programs compile and execute. Both current
semantic Rust tests pass together in 10.10s after a separate 0.39s cached build:
30 schema mutations, six literal help goldens and 28 curated model sequences.
The final contract executable and both public smokes also exit zero with no
host calls between launch and final exit under full syscall observation and
allocation denial. No allocation attempt is reached in these pure programs.
The selected existing flat-parser regression passes separately in 6.04s.

The migrated `kv_tool` passes hierarchy66, roundtrips33 and publication31
direct group cases, with overlap, including 13 reached allocation failures and
15 I/O faults. All three final groups observe every syscall. These direct
application receipts are separate from Rust-libtest execution. Production
sources are frozen at flat parser `9f11981f...`, command router `6eb4db7a...`,
help renderer `a7198a2a...` and application `f07fd52f...`.

The [module guide](extended-cli-commands.md#verification-and-targets),
[semantic fixture guide](../tests/fixtures/extended/cli_commands/README.md) and
[application guide](extended-kv.md#current-application-receipts) own the exact
receipts and finite failure/target scope. A minimal nested-error-pattern
compiler failure and executable typed-match control are retained separately;
the public APIs need no compiler change. Response files and shell completion,
and the full standard and extended library goal, remain open.
