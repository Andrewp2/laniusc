# Command-line completion

Status: implemented and accepted on the documented native Linux x86_64,
Bash 5.2 and bash-completion 2.11 profile. Portable completion, literal decoding,
reply framing, native application queries and real terminal insertion pass
focused executable checks.
The full standard and extended library goal remains open.

## Purpose and boundaries

Complete the existing CLI roadmap through the admitted command schema and its
canonical token parser. Reuse strict command routing, option arity, inheritance,
ordering and terminator behavior. Add an explicit prefix operation to that
parser rather than treating a strict MissingValue failure as successful parsing.
Keep portable context/candidates, literal shell-word decoding, reply framing and
the Bash host adapter separate. No compiler, runtime, ABI or proof change is
planned.

The first real adapter targets the installed Bash 5.2 and bash-completion 2.11.
Other shells need their own tested adapters. Bash's COMP_WORDS uses
COMP_WORDBREAKS; it is not an execution-ready argv vector. Use the established
`_get_comp_words_by_ref -n '=:@'` helper for word-break reassembly and cursor
extraction, followed by the explicit literal-word decoder below. Do not eval
user input or substitute response-file quoting rules for Bash quoting.

Source context is the [Bash completion contract](https://www.gnu.org/software/bash/manual/html_node/Programmable-Completion-Builtins.html),
[Bash variables](https://www.gnu.org/software/bash/manual/html_node/Bash-Variables.html),
the installed Bash built-in help and the
[bash-completion 2.11 source](https://github.com/scop/bash-completion/blob/2.11/bash_completion).
The primary online Bash pages were unavailable during this continuation;
installed manual/help and actual Bash behavior remain acceptance requirements.

## Portable context and candidates

`ext::cli_complete` provides:

- `context(arguments:View<View<u8>>, at:cli::Location,
  commands:View<cli_commands::Command>, scratch:View<cli::Spec>)
  -> Result<Context,Error>`.
- Context getters for selected command, operand index, completion kind, active
  decoded prefix and replacement range. Kind distinguishes ordinary command/
  operand words, long option names, short option names and option values. A
  value context identifies the declaring command and option IDs.
- `Context.suggestions(values:View<Value>) -> Result<Suggestions,Error>`, where
  `Value { bytes:View<u8>, append_space:bool }` is caller-selected policy data.
- `Suggestions.borrow()` and
  `Suggestions.next(output:View<u8>) -> Result<Option<Suggestion>,Error>`.
  A suggestion reports written bytes, command/option identity, candidate kind,
  trailing-space policy and the active replacement range.

Arguments exclude argv[0]. `at.argument` ranges through argument count; the
endpoint represents a new empty word and requires byte zero. Otherwise byte
may range through the active word length. Only words before the active word
are complete input; only the active prefix through byte is examined. Suffix
bytes and later words cannot change results. Reject invalid logical ranges,
NUL in the consumed words/prefix and invalid complete tokens explicitly.

Complete words pass through canonical routing. A trailing required option
creates an explicit pending-value context. Optional values remain attached-only.
Actual --, a required value equal to --, OptionsFirst, command-looking values,
inherited globals and disappearing parent-local options retain parser semantics.
The active -- is an unfinished long-name prefix until it becomes a complete
word. Attached long values and short clusters share canonical lookup/arity
classification. Do not create a second lexer in the completion module.

Schema candidates preserve declaration order and spelling aliases. They are
filtered by the literal byte prefix. Caller values apply only to operand/value
contexts, never to a node still requiring a child command. Repetition remains
application policy. No captions are interpreted as validators or providers.
Candidates are complete decoded prefix replacements; suffix bytes after the
cursor remain outside the portable operation.

`Replacement { at:cli::Location, length:i32 }` always identifies the whole
active prefix: argument is the cursor argument, byte is zero and length is the
cursor byte. For `--format=j|suffix`, prefix is `j`, stem is `--format=`, and a
value suggestion writes `--format=json`; it does not write only `json`.
Context getters are `borrow`, `command`, `operand_index`, `kind`, `prefix`,
`stem`, `replacement` and `option`. `Suggestion.bytes` is the written count;
its other fields are command, option, kind, append_space and replacement.

Long Required/Optional suggestions append `=` and do not append a space;
flag names append a space. Initial `-` offers both aliases, short then long
per declaration; `--` offers long aliases. A known short value option creates
OptionValue even with an empty remainder. A known flag-only cluster offers
itself first to finish, then short continuations in declaration order. Unknown
final short bytes may have no matches; an unknown byte before further cluster
bytes is an error. Empty ordinary words offer children before visible options;
caller values are considered only in operand/value contexts. Suppress trailing
space when the cursor precedes an active-word suffix.

All three APIs borrow storage, allocate nothing and perform no host calls.
After context creation scratch may be reused; Context must not retain it.
Keep schema/argument/value backing immutable and live. Output must be disjoint
from inputs. Candidate iteration is fused; output bounds/capacity errors leave
both output and position unchanged. Successful writes preserve unused tails.
Copying Suggestions forks a position over immutable borrowed data.

## Literal Bash words

`ext::bash_words` provides `Mode { Complete, Prefix }`,
`Quote { Unquoted, Single, Double }`,
`Shape { bytes:i32, quote:Quote, incomplete_escape:bool }`,
`measure(word,mode)->Result<Shape,Error>` and
`decode_into(word,mode,output)->Result<Shape,Error>`.

Support concatenated bare/single-quoted/double-quoted literals. Bare backslash
quotes the next byte; backslash-LF removes both. Inside double quotes remove
backslash only before $, backtick, double quote, backslash or LF; retain other
backslashes. Single-quoted bytes are literal. Preserve empty words, non-UTF-8,
quoted whitespace and quoted metacharacters. Reject NUL everywhere.

Unquoted whitespace/operators and unescaped expansion syntax are unsupported,
with byte-local errors. This includes $, backticks, glob/brace syntax, tilde and
history expansion; the guide must enumerate exact admitted bytes. Quoted or
escaped literal spellings remain available. Prefix mode permits an open quote;
a dangling prefix escape reports incomplete_escape, producing no suggestions.
Complete mode rejects open quotes and trailing escapes. No command, variable,
arithmetic, process or filename expansion runs in the decoder.

One traversal serves measure/write. Full syntax, ranges and capacity are checked
before any output write. Preserve output on error and unused tails on success;
signed-stride and nonzero-start views retain logical indexing. Add no NUL.

The exact bare whitespace set is SP/TAB/LF; CR/VT/FF remain literal. Bare
`|&;()<>` and initial `#` are Operator errors; # after a word part is literal.
Bare `$`, backtick and `*?[]{}~!` are Expansion errors, including isolated
closers as a documented conservative profile. In double quotes only unescaped
$, backtick and ! are rejected; backslash-! retains both bytes as Bash does.
Single quotes admit every non-NUL byte except their closing quote.

## Reply framing and Bash adapter

`ext::cli_bash` provides a pure measured reply encoder over borrowed data.
Reply includes mode (Candidates, Files or None), append_space, stem, prefix and
a counted view of raw candidate words. It also carries `quote` (the decoder
state before Readline's replaceable fragment), `continuation` (state at the
old cursor) and `trim` (the decoded unchanged prefix before that fragment).
Its NUL-delimited records are:

1. `lanius-completion-1`;
2. `candidates`, `files` or `none`;
3. `space` or `nospace`;
4. quote: `unquoted`, `single` or `double`;
5. continuation: the same three spellings;
6. trim;
7. stem;
8. prefix;
9. decimal candidate count;
10. exactly that many candidates;
11. `end`.

Files/None carry no candidates. Candidates/None carry empty stem/prefix.
None also carries empty trim. Space and quote states are accepted in every
mode; the encoder transports them without applying insertion policy.
Files asks the shell to enumerate literal filename-prefix matches and prepend
stem. Input ranges, modes, NUL and full output capacity are preflighted. Encoding
has no allocation/I/O and preserves all output on failure.

A shared Bash script registers opted-in programs implementing the reserved
`--lanius-complete-bash END TRIM PREFIX COMPLETE_WORD...` query. It requires the helper
above, preserves bytes in arrays and reads NUL records without command
substitution. Capture child exit status and validate the entire frame before
publishing COMPREPLY; partial output and nonzero exits cannot publish replies.
Bound record count/bytes and avoid changing the user's shell options.

Run the helper under the caller's original locale: its COMP_POINT indexing is
locale-sensitive. The callback's second argument is Readline's raw replaceable
fragment. Require that fragment to be a literal suffix of the reassembled cur;
TRIM is the raw prefix before it. END is one when cur equals the full active
word and zero otherwise. The query validates TRIM as a raw prefix of PREFIX,
decodes both in Prefix mode and rejects an incomplete TRIM escape. It supplies
the decoded trim and both quote states in the reply. END zero suppresses space.
After candidate generation require the raw logical candidate to preserve trim,
then remove it before insertion. Candidates that cannot preserve the existing
Readline prefix cannot be inserted by this callback.

The adapter uses noquote and performs literal insertion quoting itself. It
encodes within an existing Single/Double quote state, or uses single-quoted
pieces outside quotes, preserving logical bytes and the continuation state.
Safe bare ASCII may remain bare. It uses nospace for continuations and ordinary
unquoted insertion. A finishing quoted completion omits a manually appended
space and enables Readline's native spacing: Bash 5.2 otherwise appends a stray
quote after that manual space, even with noquote. Actual terminal experiments
establish this exception. When an encoded fragment starts with the active
initial quote, the adapter repeats that quote once: Bash consumes one leading
matching quote even with noquote. Fresh-directory tests execute filenames
beginning with an apostrophe or history-sensitive bang to check that transition.

The adapter does not set filenames: Bash 5.2 otherwise adds filename semantics
to command names, while ordinary raw replies split spaces. Actual PTY tests
must establish quote/suffix transitions, not just frame bytes.

Filename completion must preserve embedded LF and literal glob characters;
newline-delimited compgen output cannot establish that. A subprocess may use
quoted-prefix Bash globbing into an array with an explicit option profile,
then the same framing. This host glob's internal enumeration time/memory lies
outside the Lanius encoder caps and must be documented. Relative filename
candidates starting - or @ gain ./ before stem is prepended, so insertion does
not become an option or response-file directive. The adapter adds directory /
explicitly and suppresses their trailing space. Verify actual insertion,
directory suffix and spacing in PTY tests.

## Real application and acceptance

KV uses its exact existing seven-node schema. Query handling precedes response
preprocessing; completion never loads a response file or database. Completed
response directives report unavailable context explicitly. Literal @@ is
unescaped without I/O. DB positions request filename candidates; hex positions
do not. Keep the existing store/publication workflow and owner outcomes.

Acceptance requires independent context/transition models and pure contracts
for normal/edge cases, inherited scopes, both ordering modes, strict complete
errors, pending/attached values, short clusters, cursor suffix independence,
byte prefixes, output canaries, range/capacity failures and signed strides.
Add real Bash function and PTY tests for word breaks, quotes, spaces, LF,
non-UTF-8, metacharacters and cursor insertion. Run the public pure programs
under no-allocation/no-host observation and the real application with exact
reply/output/failure/cleanup checks. Keep every command below two minutes and
serialize compiler/native runs. No supported API claim precedes its runtime
acceptance; document failed attempts and remaining dependencies separately.

## Current evidence

The direct portable contract program passes full syscall tracing under mmap
denial with only launch/final exit and no attempted allocation. One registered
Rust model test passes 67 curated contexts in 6.76s. The selected existing flat
parser test and both hierarchy/help tests also pass on the new parser sources.
The revised decoder/framing contract program passes the same pure observation;
its independent model executes 389 commands in one native process. The direct
programs are not additional passing Rust libtests.

The direct public prefix-parser smoke also compiles and passes the pure
observation, including strict MissingValue versus explicit pending state,
inherited option identity, location, getters and repeated EOF.

Native KV query semantics pass 18 cases and three no-file/read traces. Sixteen
allocation cases include all 13 reached source allocation failures and three
baselines. Twelve output cases include three baselines and nine fault/recovery
controls, with explicit source release checked before exit. The existing
response-backed application group passes its 55 cases, including 18 reached
source allocation failures, on the completion-enabled application. These group
counts overlap and are not added to earlier application revisions.

The final Bash adapter `f7934bc9...` passes 51 function cases under two option
profiles, all 26 baseline PTY cases and two additional fresh-directory leading-
quote transition cases. Its unchanged process-substitution watchdog separately
passes both missing/failed-sleep controls, including child cleanup while the
test shell remains held before exit. The real terminal gates exposed and drove
fixes for open-quote insertion, background-job terminal restoration and a
leading-quote transition; fixture word-break setup and Unicode cursor-unit
corrections retain exact argv and byte checks. Exact source identities and
receipts belong to the module/fixture guides.

Acceptance covers this finite native profile. Other shells/platforms, arbitrary
Bash expansion, host glob memory/time bounds and user-program GPU execution are
not established. No compiler, runtime, ABI or proof change was needed. The full
standard and extended library goal remains open.
