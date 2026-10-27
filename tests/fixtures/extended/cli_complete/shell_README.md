# Bash integration boundary

Status: the direct native query group, 51 Bash function cases, two additive
failed/missing-deadline-helper cases, the 26-case PTY baseline and two separate
leading-transition PTY cases are accepted. This is separate from portable
completion/codec and application allocation/output-owner acceptance.

## Current acceptance

These are direct Python oracle receipts on native Linux x86-64 with Bash 5.2,
bash-completion 2.11 and `C.UTF-8`. Logs are under `target/stdlib-work/`.
Earlier partial attempts and repeated cases are not added to these counts.

| Group | Accepted scope | Receipt |
| --- | --- | --- |
| Native KV query | 18 cases plus 3 traces requiring no `%file`/`read` after `execve` | `completion-kv-query-diagnostic-retry.log` |
| Bash function | 51 cases across 2 shell-option profiles on final adapter | `completion-bash-pty-quote-retry21-function.log` |
| Failed/missing timer | 2 cases, both pre-exit child groups empty | `completion-bash-pty-quote-retry14-deadline.log` |
| PTY baseline | 26 cases, exact executed argv and cursor/suffix checks | `completion-bash-pty-quote-retry20.log` |
| Leading transitions | 2 cases in 2 fresh single-file directories | `completion-bash-pty-quote-retry19-boundary.log` |

The final adapter is `f7934bc9`; the deadline receipt used `8a1fc69f` with the
same unchanged watchdog component. The remaining three shell groups passed
on the final adapter. Query mode uses the unchanged admitted KV ELF. Exact
SHA-256 provenance:

```text
adapter f7934bc9a9a7c024abc7cab2063c39e8a7a2af33e802d9924615c86b1f747f06
oracle  011f3120ac1ca8b699be1d4f5cf409b88153df852a9a60b74b743e2b8bac8cb6
driver  4932798f9e6759bd092daa265f5fe609e73b995657c649b15be01b322291a8eb
KV      9a83795a50c4b5a8ea6e11edcb4835d7b15e7735c92166864d15eb2edecec0d8
ELF     bcd80b7c400d26cd5cc67f6760aa81c4775bd59376a048061b23be273a3f413f
```

`completion-shell-final-driver-build-first.log` records the final registered
driver building with `--no-run` in 1.75 seconds, producing
`extended_cli_completion_shell_execution-b8ec75491de93e95`. This is build
admission; the direct Python acceptance above is not a passing Rust libtest
receipt. The native ELF was emitted by the GPU compiler and executes on the
host CPU; this establishes no user GPU-kernel or other-shell support.

## Earlier attempts and corrections

`completion-kv-compile-first.log` records successful compilation of frozen KV
source `9a83795a` to `target/stdlib-work/completion-kv.elf`.
`completion-kv-query-first.log` records the initial harness failure: status 2 for
invalid completed `--unknown` correctly emitted the existing exact diagnostic
`kv-tool: invalid input or resource limit\n`, while the oracle incorrectly
required empty stderr. The oracle now requires that diagnostic for status 2
and empty stderr for status 0. No production source was changed for this
correction; the first thirteen cases are not added to any later full-group
acceptance count. The independent read-only harness review found no further
material issue in its reviewed scope; it did not execute tests or review the
separate application owner ledger.

`completion-kv-query-diagnostic-retry.log` records all 18 native query cases
and three no-file-access traces passing after that fixture correction.
`completion-bash-function-first.log` records all 51 function cases passing on
adapter `07fe6cb4`. These are direct Python oracle receipts against the admitted
KV ELF, not passing Rust libtest claims. A later static review found the
watchdog's failed/missing `sleep` path could leave a stalled producer waiting;
adapter `aa195edc` changes that branch to fail closed. The prior 51 cases are
pre-delta evidence, not acceptance of this new path.

`completion-bash-deadline-first.log` records both targeted deadline cases
passing on adapter `3231a0fd`, including both pre-exit empty-child-group barriers.
`completion-bash-app-drivers-build-first.log` records the combined three Rust
drivers building with `--no-run` in 3.56 seconds, including shell driver
`61bca319`; this is build admission, not Rust test execution. The later one-line
PTY expected-count update to 26 is not included in that build receipt.

Initial PTY execution exposed real quoted insertion failures, including split
arguments for an open single-quoted filename; those attempts are not accepted.
The later `completion-bash-pty-quote-retry6-context.log` isolates a separate
fixture error after that bridge correction: `COMP_WORDBREAKS+='@'` produced only
`@`, dropping the original whitespace separators. The captured words were
`kv-test put ./`, `@`, `lit`, so the helper could not recover the command argv.
The fixture now saves the expanded original, appends `@` through explicit
assignment, and restores the exact original. Every query and executed-argv
assertion is retained. The previously suggested terminal-readiness race was
not established; no sleep or termios workaround was added.

`completion-bash-pty-quote-retry13.log` reached the UTF-8 middle-cursor case and
exposed another fixture expectation error: the actual line was
`kv-test put 'café-file'TAIL`, correctly quoting the non-ASCII prefix. The
fixture had required its unquoted spelling. It now requires that exact quoted
line and cursor character position 23 immediately before `TAIL`; the expected
executed argument remains exactly `café-fileTAIL`. This correction preserves
all 26 cases and does not establish full PTY acceptance by itself.

`completion-bash-pty-quote-retry15.log` reached the final unchanged Unicode
line with exact expected bytes `kv-test put café-file z`, then failed because
the fixture compared its cursor against 24 bytes. Under the declared
`C.UTF-8` locale Bash reports 23 characters. The unchanged-line assertion now
requires the exact bytes and character count; all 26 cases and executed-argv
assertions remain intact. This failure did not establish full PTY acceptance.

`completion-bash-pty-quote-retry16.log` records all 26 baseline PTY cases
passing on adapter `8a1fc69f` and oracle `79a571a0`. Earlier partial attempts
are not added to that count. The adapter's process-substitution watchdog
correction also addressed a separately reproduced interactive job-control
failure; no terminal-readiness workaround was added to the oracle.

## Fixtures

`tests/extended_cli_completion_shell_execution.rs` compiles the actual
`sample_programs/library/kv_tool.lani` with the standard and extended source
roots. Its shared ELF writer validates function jump boundaries. A single
process caches that ELF across the query/function/PTY groups; the separate
deadline group requires no KV compilation:

- `reserved_query_frames_do_not_load_response_files_or_database`: exact native
  frames/statuses, strict complete words, literal response escapes, prefix
  syntax and bounded words. Three additional `strace` invocations require no
  `%file` or `read` calls after the successful `execve`. This observes the native
  query only; Bash filename enumeration is a separate intentional host service.
- `bash_function_rejects_partial_frames_and_preserves_parent_options`: actual
  installed helper and production adapter, literal file matches, missing helper
  or program, invalid/truncated/oversized frames and nonzero producer status.
  Parent `set`, `shopt` and `IFS` snapshots must remain identical under two option
  profiles. These direct callback cases use an explicit test-only `compopt`
  recorder because the builtin requires a Readline completion context; they do
  not establish Readline quoting or spacing behavior.
- `failed_or_missing_deadline_helper_reaps_stalled_producer_before_reply`:
  a test-only producer sends a complete valid frame, closes stdout and stalls.
  A PATH-isolated timer executable exits 7, or `sleep` is missing entirely.
  The callback must finish within a finite timeout, reject replies and reap
  its producer/watchdog/timer children. The shell then waits for an explicit
  host ACK: `/proc` must show only that held shell in its fresh process group,
  and the known producer/sleeper PIDs must already be gone. Exit cleanup or the
  harness's failure-only process-group kill cannot satisfy this barrier.
- `readline_inserts_literal_binary_filenames_and_preserves_cursor_suffix`:
  actual interactive Bash with a controlling PTY, installed helper and adapter.
  A test-only executable proxy forwards reserved queries unchanged to the actual
  native ELF. Ordinary execution reports Bash-parsed argv on a private pipe,
  allowing completion insertion to be checked without opening a database.
  A fixed `bind -x` observer reports edited line/cursor data without evaluating
  that line. The actual completed line is executed normally by Bash.
- `readline_leading_quote_transitions_preserve_first_filename_byte`: the
  separate `boundary` mode uses two fresh working directories with exactly
  one filename each, moving the test proxy to a separate PATH directory before
  completion. An empty active single quote must preserve a filename whose
  first byte is an apostrophe; an empty active double quote with real `set -H`
  must preserve a filename whose first byte is `!`. Both require exact executed
  argv, and the second restores the prior history flag afterward. These cases
  do not rerun or change the 26-case baseline.

The query signature is `--lanius-complete-bash END TRIM PREFIX COMPLETE_WORD...`.
`END` distinguishes the end of the active word from an interior cursor; `TRIM`
is the raw prefix Readline retains before the callback fragment. The native
frame carries initial quote, continuation quote and decoded trim before file
policy/candidate records. The test proxy records these actual query arguments.

The PTY cases select filenames with spaces, quotes, LF, non-UTF-8 bytes,
metacharacters and injection-looking text; literal escaped glob prefixes;
`=`, `:`, response `@`/literal `@@`; directory slash/space policy; schema
candidates whose name is also a directory; and cursor suffixes. UTF-8 middle
cursor cases run under `C.UTF-8`, separately from raw invalid-UTF-8 filenames.
The adapter explicitly quotes fragments under `compopt noquote` and generally
uses `nospace` with explicit directory slash/space. A finishing initial quote
uses the tested Readline closing-quote/space path. Function-only quoting examples use literal
expected fragments; PTY cases verify the actual Bash parse of the inserted
line. No shell-specific quoting string is used as the oracle when the durable
contract is the final argv bytes.

The original 25 cases run before an additive open-double-quote `bang!name`
case with real `set -H`. That case must execute the exact filename bytes,
without a retained backslash or history expansion; the prior history flag
is restored afterward. The baseline group has 26 cases; its full passing retry
is recorded above.

With a custom `@` word break, an already-retained `@@` cannot be rewritten to
the protective `./@` filename prefix. The adapter must leave that completion
unavailable; it must not insert a different argument. The paired `./@` prefix
case remains usable. This is an explicit finite insertion constraint.

The host filename glob's internal enumeration cost is outside Lanius's output
caps. The fixture uses bounded temporary directories and finite per-process and
per-record waits; it does not claim to bound arbitrary filesystem enumeration.
The signal and malformed-frame producers are test programs, not production
protocol/parser implementations.

## Reproduction commands

Run each root command with its usual outer timeout below 100 seconds; no broad
workspace test run is needed:

```sh
cargo test --test extended_cli_completion_shell_execution reserved_query_frames_do_not_load_response_files_or_database -- --exact --nocapture
cargo test --test extended_cli_completion_shell_execution bash_function_rejects_partial_frames_and_preserves_parent_options -- --exact --nocapture
cargo test --test extended_cli_completion_shell_execution failed_or_missing_deadline_helper_reaps_stalled_producer_before_reply -- --exact --nocapture
cargo test --test extended_cli_completion_shell_execution readline_inserts_literal_binary_filenames_and_preserves_cursor_suffix -- --exact --nocapture
cargo test --test extended_cli_completion_shell_execution readline_leading_quote_transitions_preserve_first_filename_byte -- --exact --nocapture
```

For reuse of an already admitted exact KV ELF, each oracle group accepts
`python3 -B shell_oracle.py query|function|pty KV_ELF ADAPTER`. The targeted
gate is `python3 -B shell_oracle.py deadline - ADAPTER`, with no app rebuild.
The additive leading-transition gate is
`python3 -B shell_oracle.py boundary KV_ELF ADAPTER`, also reusing the admitted ELF.
Do not count direct Python invocations
as a Cargo-test receipt. Preserve the exact source/ELF/script hashes with any
new runtime results.

`python3 -B shell_oracle.py --self-test` performs data-only frame-validator
controls. It starts no Bash, native ELF, compiler or PTY and cannot establish
shell acceptance. Runtime support is limited to the host/version/locale actually
accepted by root; no other shell or GPU kernel support is claimed.
