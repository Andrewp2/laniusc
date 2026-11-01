# Multi-file patches

`ext::patchset` reads whole patches the way GNU `patch` and `git apply` do and
supplies the pieces both tools need beyond single-hunk application: git
extended headers, reversal, GNU's reversed-patch check, git's hunk placement and
the `git apply --3way` merge fallback. `sample_programs/library/seq_patch.lani`
(`seq-patch`) uses it to patch directory trees. Import with
`--source-root extended --stdlib-root stdlib`. It builds on
[`ext::unidiff`](extended-seqdiff.md) for hunks and fuzzy application and on
[`ext::merge3`](extended-merge3.md) for merging.

## API

`parse(text, strip, max_files, max_lines) -> Result<PatchSet, Error>` splits a
patch into file sections. A section is either a `diff --git` header with its
extended header lines, or a plain `---`/`+++` pair as `diff -u` and `diff -ruN`
write it. Text outside sections is skipped: mail headers, `Index:` and
`Only in` lines, and format-patch signatures. `strip` removes leading path
components the way `-p` does. Repeated slashes count once, and a name with
fewer components keeps its last one. Rename and copy lines carry no `a/`/`b/`
prefix, so one component less is stripped from them, as git does. Quoted
names (`"a/caf\303\251"`) are decoded. An unquoted `diff --git a/X b/Y` line
with spaces is split where both halves name the same path. `max_lines` bounds
each hunk.

`PatchSet` has `len()`, `get(i) -> Option<FilePatch>`, `old_name(i)`,
`new_name(i)` and `destroy()`. A `FilePatch` has these fields:

| field | meaning |
| --- | --- |
| `kind` | `Modify`, `Create` (`new file mode` or `--- /dev/null`), `Delete`, `Rename`, `Copy` |
| `binary` | `Text`, `Literal` (a `GIT binary patch` section) or `Marker` (`Binary files A and B differ`) |
| `git` | the section started with `diff --git` |
| `old_mode`, `new_mode` | values of the mode lines, such as `0o100755`; 0 when absent |
| `patch` | the section's `ext::unidiff::Patch`; it is empty for mode-only, rename-only and binary sections |
| `old_start`/`old_length`, `new_start`/`new_length` | name ranges in `PatchSet.names`; created files have an empty old name and deleted files an empty new name |

`Error` is `InvalidInput`, `Malformed` (a bad hunk, or a section without
names), `FileLimit`, `LineLimit` or `AllocationFailed`.

`reverse(patch)` returns the patch that undoes an `ext::unidiff::Patch`. Sides,
counts and line kinds are swapped, and line bytes are shared with the input.
`reverse_file(file)` also swaps names, modes, and creation with deletion. It is
how `patch -R` and `git apply -R` read a section. Destroy the result's `patch`.

`direction(base, patch, options) -> Result<Direction, ApplyError>` is GNU
patch's reversed-patch check. For each fuzz level from 0 to `max_fuzz`, it
tries the first hunk forward and then reversed, and the first placement found
decides. The result is `Forward`, `Reversed` or `Neither`.

`apply_git(base, patch, options)` places hunks the way `git apply` does:

- Hunks apply in order, each to the result of the previous ones.
- Context must match exactly, so `max_fuzz` and `max_offset` are ignored.
- Each hunk is searched from its new-side line outward: the line itself, then
  +1, -1, +2, -2 and so on.
- A hunk whose old side starts at line 0 or 1 must match at the top of the
  file. A hunk without trailing context must match at the end.

Application stops at the first hunk that does not apply. That hunk's report
carries its old start line, which git prints in `error: patch failed: F:L`, and
the output is empty. The result is an `ext::unidiff::Applied`.

`three_way(ours, base, patch, options) -> Result<Merged, ApplyError>` performs
`git apply --3way` for one file. It applies the patch to the preimage `base`
(git's blob named by the `index` line). If that succeeds, it merges the result
into `ours` with the zealous level and xdiff alignment, using the markers
`<<<<<<< ours` and `>>>>>>> theirs`. `Merged { output, applied, conflicts }`
has `applied` false when the patch does not apply to the preimage; git then
falls back to direct application.

## seq-patch

```sh
seq-patch [-p N] [-F N] [-t | -N | -f] [-R] -i PATCH          # GNU patch semantics
seq-patch --git [-p N] [-R] -i PATCH                          # git apply semantics
seq-patch --3way --base-dir DIR [-p N] [-R] -i PATCH          # git apply --3way
seq-patch [-F N] [--max-offset N] BASE PATCH                  # one file to stdout
```

Tree modes patch files below the current directory. `-p` defaults to 1. Exit
status 0 means everything applied, 1 that some hunk or file failed or a merge
left conflicts, and 2 a usage error, malformed patch, limit or I/O error.

**GNU mode** handles each file on its own and prints GNU's messages to stdout.
Hunks are placed with `ext::unidiff::apply`: offset search, fuzz up to `-F`
(default 2) and GNU's anchoring rules. Rejected hunks are reported and dropped,
and the rest of the file is still written. No `.rej` files are written, as with
`patch -r -`.

- **Reversed patches.** Unless `-f` is given, each text file's first hunk is
  checked with `direction`. With `-t` (the default), a reversed patch is
  reported as `Reversed (or previously applied) patch detected!  Assuming
  -R.` and applied reversed. The modes of its old side are then set too.
  `-N`, and `-R` without `-t`, skip that file with `N out of N hunks ignored`,
  as non-interactive GNU `patch` does. Under `-R` the check reports
  `Unreversed patch detected!`. Creating an existing file, or deleting a
  missing one, gets the same three-way choice with GNU's wording. A creation
  never applies to a non-empty file.
- **Names.** When both names of a rename or copy exist, GNU's name choice is
  reproduced: the names are compared in patch order on path components, then
  on length. A chosen new name means the change is already done, so that file
  is patched in place (`patching file B (already renamed from A)`). When the
  two minimums come from different names, the file is refused with
  `Cannot rename file without two valid file names`.
- **Renames and copies** read their source as it was before the patch, even
  when an earlier section of the same patch modified it. Every write is
  therefore planned first and done at the end. Renamed and copied files keep
  their source's mode unless a mode line says otherwise. Explicit modes are set
  exactly (`0755`, `0644`). Deleting the last file of a directory removes the
  empty directories above it.
- **Binary sections** are refused per file: `File F: git binary diffs are not
  supported.` for `GIT binary patch`, or `binary files differ; the patch
  carries no data to apply` for a marker. The other files are still patched,
  and the exit status is 1.

**Git mode** (`--git`) prints git's messages to stderr and writes nothing
unless every file applies (`error: patch failed: F:L`, `F: patch does not
apply`, `already exists in working directory`, `No such file or directory`,
`removal patch leaves file contents`). Modes keep only the executable bit, so
files become 0755 or 0644. Binary sections fail the whole patch:
`cannot apply binary patch to 'F' without full index line` for a marker,
`binary patches are not supported` for a literal.

**Three-way mode** (`--3way --base-dir DIR`) follows `git apply --3way` in git
2.43. For each modified, renamed or copied text file, it first runs
`three_way` with `DIR/OLDNAME` as the preimage and prints `Applied patch to 'F'
cleanly.` or `with conflicts.`, followed by `U F` at the end. Only if that is
impossible does it print `Falling back to direct application...` and apply
directly. A creation whose file exists is merged with an empty base, and so is
a rename or copy whose new name exists (`Performing three-way merge...`). A
pure rename onto an existing file does not apply. Conflicts leave markers in
the file and make the exit status 1.

### Differences from the reference tools

- git looks the preimage up by the `index` line's blob id. `seq-patch` reads it
  from `--base-dir` and does not check the id.
- `git apply` can apply `GIT binary patch` literals and deltas. `seq-patch`
  refuses every binary section, with the errors above.
- There is no `-d`, `-o`, `--dry-run`, `.rej` output, interactive prompt or
  whitespace handling (`--ignore-whitespace`, `-l`).
- GNU's `Hunk #N succeeded at L` messages use the same wording, but the oracle
  compares only trees and exit status.

## Verification

`tests/extended_patchset_execution.rs` builds two programs.
`tests/fixtures/extended/patchset_contracts.lani` checks the API contracts:

- every header form and both binary forms, quoted names, `-p0`/`-p1`
  stripping, and file-limit and malformed-input errors;
- reversal of a creation;
- git placement order and both anchors, and the rejected old start line;
- all three `direction` outcomes;
- clean and conflicting `three_way` merges, and a preimage that does not apply.

`tests/fixtures/extended/patchset_oracle.py SEQ_PATCH WORKDIR [CASES] [SEED]`
builds random repositories. Each has 2-6 files, some in nested directories,
some executable and some without a final newline. The target tree adds edits,
renames with and without edits, copies, mode changes, created and deleted
files. The patch is the output of `git diff --cached -M` (sometimes `-C`), and
every eleventh case adds a binary file. The patch is applied to seven kinds of
starting tree:

- `clean`: the base tree.
- `shifted`: lines inserted or deleted away from the hunks.
- `fuzzed`: one context line changed.
- `conflict`: one deleted line changed.
- `random`: random edits.
- `reversed`: the target tree.
- `partial`: the target for some names and the base for the others.

Every run compares the resulting tree (contents, executable bits, directories)
and the exit status with:

- GNU patch 2.7.6 with `-t`, `-N` and `-f`, plus `-R` and `-R -t` on the clean,
  reversed and partial trees;
- `git apply`, and `git apply -R` on the reversed and partial trees;
- `git apply --3way`, with the base committed and the starting tree staged.

Binary cases give GNU a `GIT binary patch` and git a `Binary files differ`
marker. They also check that `seq-patch --git` refuses the literal patch
atomically.

| run (300 cases each) | comparisons | disagreements |
| --- | ---: | ---: |
| seed 1 | 1,841 | 0 |
| seed 2 | 1,841 | 0 |
| seed 3 | 1,836 | 0 |

In seed 2, the reference tools exit 1 in 98 GNU `-t`, 180 `git apply` and 137
`git apply --3way` runs, 50 of the last leaving conflict markers. Each seed
refuses 27 literal binary patches. The seqdiff oracle
(`seqdiff_oracle.py`, 1,000 pairs) still passes with the hunk-start rule added
to `ext::unidiff::apply` for this work: GNU never places a hunk, including
fuzzed-away leading context, before line 1.
