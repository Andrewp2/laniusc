# Recursive text search through `std::walk`

`sample_programs/library/text_grep.lani` uses [`std::walk`](stdlib-directory-cursor.md)
for recursive traversal. The application retains one displayed-path buffer and,
when `--gitignore` is enabled, a stack of rule counts. The cursor owns directory
readers, descent decisions, metadata checks, and cleanup. The former `Level`,
`Run.levels`, and `close_levels` implementation has been removed.

## Search behavior

The cursor emits entries in filesystem order and descends depth first. Grep
reconstructs each displayed path from the operand prefix and the cursor's
relative path. An implicit `.` operand has no displayed prefix; an explicit
operand retains its spelling, including a trailing slash.

Directory entries are filtered before `descend`. `--exclude-dir` applies first.
With `--gitignore`, `.git` directories and ignored directories are pruned.
File include/exclude rules retain their existing last-match precedence;
Git ignore rules can still exclude a file admitted by an include rule.

On `Enter`, grep records the current rule count and reads `.gitignore` relative
to the directory's borrowed descriptor. On `Leave`, it restores that count.
Sibling directories and later operands therefore do not inherit a departed
subtree's rules. Cancellation does not require synthetic `Leave` events:
grep restores the root rule count after explicitly closing the cursor.

The root is opened as `operand + "/."`, preserving command-line directory
symlink following. Descendant symlinks and special files are skipped. Regular
files are opened with `no_follow` relative to `Item.parent_fd`; the displayed
path is never used to reopen a descendant. No cursor mutation occurs while an
entry's borrowed name or descriptor is being used.

## Limits and failures

Root counts as one of the 512 active directories. A directory entry at depth
512 receives the existing per-path resource-limit diagnostic and is pruned
before an open is scheduled. Later siblings remain searchable. Total entries
and traversal work use the largest `u64` budgets, and the relative path uses
the largest `i32` byte limit; the CLI adds no smaller aggregate traversal
limit. These counters are finite and overflow is an explicit resource failure.
The existing root-open path limit still applies.

Recoverable metadata, child-open, identity-check, directory-read, and
file-read failures report a path, continue traversal, and produce final status
2. Directory-close faults now follow that same visible path-error behavior;
the old application silently discarded them. A close consumes the descriptor
once and is never retried. Failure to read `.gitignore` reports the file and
adds none of its rules; a missing or unopenable `.gitignore` retains the
existing behavior of adding no rules.

Allocation failure terminates the search with status 4. Output failure
terminates it with status 3. Fatal cursor resource exhaustion terminates the
current traversal with an explicit resource-limit diagnostic. Every path
after successful cursor construction calls `close`, including cancellation.
Cleanup preserves an earlier fatal error and cannot turn it into success.

## Focused executable checks

`tests/extended_text_grep_recursive_execution.rs` compiles the real application
through the GPU compiler and links a Linux x86-64 native executable. Its small
oracle in `tests/fixtures/extended/text_grep_walk/oracle.py` provides two gates:

- `recursive_text_grep_preserves_gnu_order_filters_symlinks_and_git_scopes`
  compares exact stdout bytes and status with GNU grep for implicit and explicit
  operands, root symlinks, skipped descendant links and FIFOs, counts, line
  numbers, include/exclude precedence, empty files, and raw-byte filenames.
  Git's own file selection supplies the ignore oracle; a separate filesystem
  DFS preserves directory order. Nested negation, sibling scope restoration,
  independent operands, and the recoverable 512-directory boundary are checked.
- `recursive_text_grep_recovers_child_faults_and_releases_owners_on_fatal_errors`
  injects reached metadata, child-open, directory-read, file-read, ignore-read,
  directory-close, and stdout-write failures. It verifies later-file recovery,
  prune-before-open, and fatal output behavior. Selected reached allocation
  failures cover construction, opened root/child ownership, and file-output
  setup. The existing native symbol/runtime verifier identifies source
  allocations; the shared ownership ledger checks full-width addresses and
  matching releases. Source descriptor generations must each receive one
  close, including cancellation. Injected close errors check consumption and
  non-retry, not a claim that a skipped kernel close released its descriptor.

Each oracle subprocess has a six-second deadline; each complete oracle is
limited to 70 seconds by its Rust gate. The broad historical recursive oracle
is not part of these gates. No Python or Rust code implements library behavior.

Both native gates passed: **35 finite cases**, comprising 23 behavior
comparisons and 12 fault-check runs. The latter include a clean baseline,
seven reached I/O failures, and four reached allocation denials. Source owners
balanced, and recoverable child failures preserved sibling search.

The receipts are
[`text-grep-walk-compare-final.log`](../target/stdlib-work/text-grep-walk-compare-final.log)
for the 23 comparisons (8.87 seconds), and
[`text-grep-walk-acceptance.log`](../target/stdlib-work/text-grep-walk-acceptance.log)
for the 12 fault runs. The latter is a 14.63-second mixed invocation: its fault
selector passed, while its initial comparison selector failed because the
oracle assumed creation order at the depth boundary. The final comparison
uses GNU grep's filesystem order, excluding the pruned file, and passed.

These are focused Linux x86-64 receipts, not an exhaustive allocation-failure
sweep, race test, performance claim, or formal proof. They exercise GPU
compilation to native x86-64, not traversal inside a GPU kernel; other targets
remain unverified. Run one selector at a time with the repository's shared
GPU test lock and an outer command deadline below two minutes.
