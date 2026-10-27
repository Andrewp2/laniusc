# Command completion and the Bash adapter

Status: implemented with finite native Bash/KV execution receipts below.
The full standard and extended library goal remains open.

## Boundaries

`ext::cli_complete` uses the existing `ext::cli_commands` schema and canonical
`ext::cli` parser to inspect a cursor prefix and enumerate suggestions. It does
not parse a shell command string, allocate, read files, print or exit.
`ext::bash_words` separately decodes the supported literal Bash-word profile.
`ext::cli_bash` measures and encodes a versioned NUL-record reply in caller
storage. The native Bash script is an explicit host adapter.

The [frozen plan](library-completion-plan.md) owns the interfaces and transition
contract. [Command routing](extended-cli-commands.md) and
[response preprocessing](extended-cli-response.md) remain separate workflows.
A completion request does not run a response provider.

## Portable completion

`cli_complete::context(arguments, at, commands, scratch)` takes already separated
byte words without argv[0]. The cursor identifies a word and a byte position,
or the empty endpoint after the last word. Complete earlier words pass through
the canonical parser. Only the active prefix is examined; suffix bytes and later
words cannot change the context. A strict invalid completed token remains an
error. A required option awaiting a value is an explicit prefix state, rather
than a successful reinterpretation of strict `MissingValue`.

Context getters expose selected command, operand index, kind, prefix, stem,
replacement range and optional declaring-command/option identity. Kinds are
Command, Operand, LongOption, ShortOption and OptionValue. Actual `--`,
OptionsFirst stopping, inherited globals, disappearing ancestor-local options,
attached values and short clusters retain canonical semantics. Optional values
remain attached-only. An active `--` is a partial long name; a completed `--`
terminates recognition.

`Context.suggestions(values)` combines admitted schema spellings with caller
policy values. `Value` carries bytes and an append-space preference. A caption
such as `DB KEY_HEX` is not interpreted as executable operand policy. Child
commands and visible option aliases retain declaration order and literal byte
prefix matching. Long value-taking options include `=` and request no trailing
space. Caller values apply only to operand/value contexts.

`Suggestions.next(output)` writes a complete decoded prefix replacement into
caller storage and reports its byte count, identity, kind, replacement range
and spacing preference. It preserves output and position on bounds/capacity
errors, preserves the unused tail on success and fuses at exhaustion. Context
retains no scratch; scratch may be reused after construction. Keep all borrowed
schema, argument and value backing live and immutable. Output must not overlap
inputs. Physical backing, exclusivity and lifetimes remain caller obligations.

## Literal Bash-word profile

`bash_words::measure(word, mode)` and `decode_into(word, mode, output)` share
one traversal. `Mode::Complete` requires closed quotes and complete escapes;
`Prefix` permits an open quote and reports a dangling escape. `Shape` contains
decoded bytes, `Quote::{Unquoted,Single,Double}` and `incomplete_escape`.
Decode adds no NUL; full syntax and output capacity are admitted before writing.
Errors preserve output, and successful writes preserve its unused tail.

The profile supports concatenated bare, single-quoted and double-quoted pieces:

- Bare backslash quotes the next byte; backslash-LF removes both.
- Single-quoted non-NUL bytes are literal until the closing quote.
- In double quotes, backslash is removed only before `$`, backtick, double
  quote, backslash or LF. Before other bytes it remains part of the word.
- Empty quoted pieces count as word content. Non-UTF-8 bytes are preserved.
- NUL rejects everywhere. Unquoted SP, TAB and LF reject. CR, VT and FF remain
  literal bytes.
- Unquoted `| & ; ( ) < >` reject as operators. An initial unquoted `#` rejects;
  after any word part, including empty quotes, it is literal.
- Unquoted `$`, backtick, `* ? [ ] { } ~ !` reject as expansion syntax.
  Unescaped `$`, backtick and `!` also reject inside double quotes.
  Single quotes or permitted backslash forms can express literal bytes.

No command, variable, arithmetic, process, filename or history expansion runs.
This is a deliberate literal profile, not the response-file grammar or a full
Bash evaluator. An incomplete prefix escape produces no suggestions; an open
prefix quote remains eligible for completion. Complete-word syntax errors do
not become empty argv.

## Native KV policy

The KV query entry shares its exact existing root/six-child schema. Query mode
is selected before any response provider or Store/publication operation. It
uses the same checked startup SIGPIPE policy and explicitly releases captured
arguments, decoded words, candidate backing and reply storage on every path.
No implicit Drop or process-exit cleanup is assumed.

Completed `@path` directives make later argv unavailable without reading their
contents. Known earlier words are still checked; valid unavailable context
returns a None reply. Literal `@@` loses one leading `@` without I/O. An active
single `@` requests response-filename suggestions with an `@` stem. A selected
command's DB operand requests filenames; hexadecimal key/value positions do
not. Completion never opens response files or databases.

The reserved query is:

```text
kv-tool --lanius-complete-bash END TRIM PREFIX COMPLETE_WORD...
```

Words exclude the executable. END is exactly `0` or `1`, indicating whether the
cursor reaches the end of the active lexical word. PREFIX is its raw lexical
prefix through the cursor. TRIM is the raw lexical prefix that Readline will
retain before the replacement fragment; it must be a literal prefix of PREFIX.
Both use Prefix decoding. TRIM cannot end in an incomplete escape. Its decoded
bytes and quote state, plus PREFIX's quote state, describe the insertion
boundary. END0 suppresses trailing-space requests. Completed words use Complete
decoding. Suffix bytes are not submitted as complete input.

The snapshot admits at most 12 transport arguments and 262,144 raw bytes.
Ordinary dispatch explicitly retains its eight-word limit before provider use.
Queries admit eight complete words, 4,096 decoded bytes per word/trim, and
32,768 decoded bytes including trim, prefix and complete words. They admit at
most 32 candidates and 4,096 bytes per candidate. The complete encoded reply
is capped at 32,768 bytes, with at most 64 writes of at most 1,024 bytes including
EINTR and partial progress. These are requested storage/call bounds, not RSS or
host wall-time guarantees.

Invalid query syntax or limits return 2, ordinary output failure 3 and
allocation failure 4. Unsupported context can return a valid None frame with
status zero. Reply bytes are staged before delivery; output failure can expose
a confirmed prefix, which the adapter must reject. Existing database operations
and publication status 6/7/8 preserve their separate contracts.

## Bash host boundary

The target is Bash 5.2 with bash-completion 2.11. Source bash-completion, then
`extended/shell/lanius-completion.bash`, and explicitly opt in a program with
`lanius_completion_register PROGRAM`. Merely sourcing the script registers no
program. Missing helper support rejects registration.

The adapter calls `_get_comp_words_by_ref -n '=:@'` under the caller's locale;
only subsequent framing uses byte-oriented `LC_ALL=C`. The helper's
COMP_WORDBREAKS reassembly does not change Readline's actual replacement
fragment. The adapter and query metadata must account for that fragment before
publishing candidates; no global COMP_WORDBREAKS mutation is permitted.

The wire fields are NUL-terminated records in this exact order: magic
`lanius-completion-1`, mode (`candidates`, `files`, `none`), spacing (`space`,
`nospace`), initial quote, continuation quote, decoded trim, stem, prefix,
decimal candidate count, that many complete candidate words, and `end`.
Quote fields are `unquoted`, `single` or `double`. Files/None contain no
candidates; Candidates/None have empty stem/prefix, and None has empty trim.
`cli_bash::measure` and `encode_into` preflight all ranges, NUL constraints,
mode consistency and full output capacity before writing.

NUL records go directly through bounded reads into arrays, without command
substitution, eval or newline-based compgen transport. Reads cap each record at
4,096 bytes, count at 32 and total at 32,768 bytes; record reads and the final
child-status wait are bounded. The status wait uses the host `sleep` command
as a deadline job. The adapter admits every record, exact count, terminal
marker, EOF and successful child status before assigning COMPREPLY. Partial,
oversized, trailing or nonzero-exit replies cannot publish candidates. An explicit
PID wait retrieves saved producer status on Bash 5.2. A process-substitution
watchdog owns and reaps its sleep child; cancellation also reaps that child, and
any uncancelled sleep failure terminates the producer. Parent interactive jobs
are not used for the timer, avoiding terminal-mode changes during completion.

Every candidate must begin with decoded trim. The adapter removes that prefix
and encodes the fragment inside the initial lexical quote state. Single-quoted
apostrophes use explicit close/escaped-apostrophe/reopen transitions. Double
quotes escape backslash, double quote, dollar and backtick; an exclamation mark
uses a temporary single-quoted piece rather than `\!`, which would retain a
backslash. Unquoted unsafe bytes use single-quoted pieces. Nonempty safe ASCII
fragments can remain bare when both quote states are Unquoted. Continuation
restores the required suffix quote state. When an insertion begins with the
active initial quote byte, Bash consumes that byte while matching the retained
opening quote. The adapter supplies that consumed byte separately so an immediate
apostrophe or exclamation-mark quote transition remains intact. Logical candidate
bytes are not changed.

`noquote` is always enabled. A finishing candidate in an initially quoted state
lets Readline close the quote and add its separator with native spacing. Adding
an explicit space there makes Bash 5.2 append a stray quote. Other supported
states use `nospace` and explicit separators. Filename interpretation and default
fallbacks are disabled. Thus a command such as `put` does not gain a slash merely
because cwd contains a directory named put. The receipt table records actual
Readline insertion, not an inference from generated candidate bytes.

Files replies enumerate in an isolated Bash subprocess with an explicit glob
option profile. A quoted literal prefix followed by the one intended wildcard
preserves literal glob metacharacters, embedded LF and raw bytes in arrays.
Relative matches beginning `-` or `@` gain `./` before any response stem is
prepended. Directories request a slash and continued completion. If this
required escape changes text Readline has already retained, the candidate is
discarded; the adapter does not insert an incorrect or unsafe path. For example,
a custom `@` word break can retain `@@` in a position where the safe `./@name`
candidate cannot replace it. Enter a replaceable literal path prefix such as
`./@` instead. No response-specific escape alias is invented by the generic
adapter. If candidate spacing preferences differ, it conservatively suppresses
automatic continuation spacing for the set.

Bash globbing may enumerate the complete matching namespace before applying the
reply caps. Its internal allocations and enumeration time are host behavior
outside Lanius's source-storage/work bounds. It can inspect filesystem names;
this is separate from the no-file-access native KV query. The subprocess's
option changes do not change the user's shell options.

## Verification and target scope

The current adapter source is SHA-256 `f7934bc9...`; the KV source is
`9a83795a...`. The direct host gates below reuse the admitted
`target/stdlib-work/completion-kv.elf`; no compiler or native ELF rebuild was
performed during the insertion fixes. Each invocation held
`target/stdlib-work/library-gpu.lock` and had a 100-second outer bound.

| Log under `target/stdlib-work/` | Accepted direct scope |
| --- | --- |
| `completion-bash-pty-quote-retry20.log` | 26 real PTY cases, C.UTF-8 locale; exact executed argv, cursor suffixes, quotes, word breaks, LF/raw bytes, literal metacharacters, directories and history-enabled exclamation mark |
| `completion-bash-pty-quote-retry21-function.log` | 51 function cases across two option profiles; exact framing/status rejection and no partial replies |
| `completion-bash-pty-quote-retry19-boundary.log` | Two fresh-cwd PTY cases: empty initial single quote with a first-byte apostrophe, and empty initial double quote with a first-byte exclamation mark/history enabled; exact executed argv |
| `completion-bash-pty-quote-retry14-deadline.log` | Failed/missing sleep, two cases; held shells show all producer/watchdog/sleep children gone before exit |

These are direct Python-driven Bash/native process receipts, not passing Rust
libtests. The deadline receipt uses source `8a1fc69f...`; subsequent edits changed
only lexical insertion, preserving the reviewed watchdog and frame/status code.
The registered shell driver separately built with `--no-run` in 1.75 seconds
(`completion-shell-final-driver-build-first.log`), producing
`extended_cli_completion_shell_execution-b8ec75491de93e95`. That is build
admission, with no additional native cases or Rust-libtest execution.

| Frozen identity | SHA-256 |
| --- | --- |
| Bash adapter | `f7934bc9a9a7c024abc7cab2063c39e8a7a2af33e802d9924615c86b1f747f06` |
| KV application source | `9a83795a50c4b5a8ea6e11edcb4835d7b15e7735c92166864d15eb2edecec0d8` |
| Reused KV ELF | `bcd80b7c400d26cd5cc67f6760aa81c4775bd59376a048061b23be273a3f413f` |

The script targets the tested Bash 5.2 and bash-completion 2.11 host
boundary. KV is native Linux x86_64 CPU output from the GPU compiler; this does
not establish user GPU-kernel execution or another host/shell. Portable module
models and pure contracts retain their separate receipts. Historical KV
response/Store/publication campaigns retain their own source revisions; the
shell gates do not rerun those operations.

Earlier real adapter defects were corrected rather than accommodated in the
oracle: Bash 5.2 `wait -n` could miss saved producer status; a failed timer could
leave a producer wait unbounded; canceling an interactive background timer job
could leave the terminal in cooked mode; inserting a closing quote plus space
before Readline's own quote handling split or left an unfinished argument; and
Readline's consumption of a leading matching quote damaged a first-byte quote
transition. The final PID wait, owned process-substitution timer, in-state quote
handling and leading-quote compensation address those paths. The final deadline
and PTY receipts above cover them.

Separate fixture corrections preserved executed argv and case counts. A custom
word-break profile now expands/saves the original dynamic default before adding
`@`, then restores it exactly. The UTF-8 suffix check expects the explicit quoted
prefix, and cursor checks use C.UTF-8 character positions rather than UTF-8 byte
counts. The separate empty-quote/first-transition gate retains exact native argv
rather than accepting a backslash or another filename. No support is inferred
for arbitrary Bash expansions, other shells or targets.
