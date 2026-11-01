# Three-way merge

`ext::merge3` merges two edited versions of a common base with the diff3
algorithm. It can refine conflicts the way git does, and it writes conflict
markers in merge or diff3 style. `sample_programs/library/seq_merge.lani` is a
`git merge-file` / `diff3 -m` style tool built on it. Import with
`--source-root extended --stdlib-root stdlib`. The module builds on the
[generic diff engine](extended-seqdiff.md).

## API

`merge3(o, a, b, level, limits)` is generic over `T: Eq<T> + Hash<T>`; `o` is
the base, `a` ours, `b` theirs. `merge_lines(o, a, b, level, limits)`
specializes it to `ext::seqdiff::Line` and adds git's conflict rejoining. Both
return `Merge`, with `len()`, `chunk(i) -> Option<Chunk>`, `conflict_count()`
and `destroy()`.

`Chunk { kind, o0, o1, a0, a1, b0, b1 }` covers half-open ranges of the three
sequences. Its `kind` is one of:

| kind | meaning | merged content |
| ---: | --- | --- |
| 0 | unchanged in both sides | ours (= base = theirs) |
| 1 | changed only in ours | ours |
| 2 | changed only in theirs | theirs |
| 3 | same change in both sides | ours (= theirs) |
| 4 | conflict | markers |
| 5 | lines both sides share inside a refined conflict | ours (= theirs) |

**Algorithm.** The engine computes linear-space Myers matchings for base→ours
and base→theirs. It then walks the base, emitting maximal runs where all three
sequences stay matched in step as unchanged chunks. At any other point, it
advances to the next base line that is matched in both sides, and classifies
the chunk in between by comparing contents. A side equal to the base takes the
other side; two equal sides make a shared change; anything else is a conflict.
Insertions at the same base position on both sides, and changes with no shared
base line between them, therefore conflict, as in GNU diff3 and git.

`Level` selects git's merge levels:

- `Eager` resolves identical changes only. This is git's level for diff3-style
  output.
- `Zealous` also diffs each conflict's two sides. Shared lines become kind-5
  chunks and the differing runs become separate conflicts; a conflict with an
  empty side is left whole. It then rejoins conflicts separated only by shared
  or unchanged lines when that gap is at most three lines long. Gap lines then
  appear on both sides of the joined conflict.
- `ZealousAlnum` (git merge-file's default) additionally rejoins conflicts whose
  gap has no ASCII letter or digit.

The rejoin step runs in `merge_lines`. The generic `merge3` stops after
refinement.

`write_merge(o, a, b, merge, labels, format)` renders line merges.
`Labels { ours, base, theirs }` are copied after the marker character and a
space, and an empty label prints the bare marker. `Format { style,
gnu_identical, max_output }` takes `Style::Merge`
(`<<<<<<<` ours, `=======`, theirs, `>>>>>>>`) or `Style::Diff3` (adds
`|||||||` base). Use `Eager` with diff3 style, as git does; refined conflict
pieces keep their whole original base range. `gnu_identical` prints a kind-3
chunk the way GNU `diff3 -m` does: `<<<<<<< base`, the base lines, `=======`,
the change, `>>>>>>> theirs`. A conflict side whose last line lacks LF gets one
before the next marker, like git (GNU diff3 joins the marker to the line
instead).

Errors are `InvalidOptions`, `Bounds`, `ItemLimit`, `WorkLimit`,
`OutputLimit` and `AllocationFailed`. Diff limits come from
`ext::seqdiff::Limits`.

## Tool

```sh
seq-merge [--diff3] [--gnu] [--eager|--zealous|--alnum] [-L OURS -L BASE -L THEIRS] OURS BASE THEIRS
```

The merge goes to stdout. The default is merge style at `--alnum`, matching
`git merge-file -p`. `--diff3` selects diff3 style at `--eager`, matching
`git merge-file -p --diff3`. `--gnu` adds the GNU identical-change form and
counts those chunks as conflicts, matching `diff3 -m`. Labels default to the
file names. Exit status is 0 for a clean merge, 1 for conflicts and 2 for
errors.

## Verification

`tests/extended_merge3_execution.rs` runs
`tests/fixtures/extended/merge3_contracts.lani`. The fixture checks generic
`i32` chunk kinds, all marker forms, zealous splitting, the GNU form and
missing final LF handling. The same test then runs
`tests/fixtures/extended/merge3_oracle.py` over 600 triples. Each triple has a
base and two independently edited sides, a 25% chance of one shared edit, and a
15% chance that ours equals the base. Sizes range from 0 to 50 lines. Each
triple is checked three ways, on exact output bytes and on clean/conflict
status. Independent properties (a side equal to the base yields the other side;
clean merges carry no markers) are also checked.

Receipt for 4,000 triples (seed 20261031, 57 s, run directly on the compiled
tool):

| group (2,000 triples each) | git merge-file | git merge-file --diff3 | diff3 -m |
| --- | ---: | ---: | ---: |
| distinct lines: identical output and status | 2,000 (829 conflicted) | 2,000 (829 conflicted) | 2,000 (904 conflicted) |
| repeated lines: identical output and status | 1,800 (559 conflicted) | 1,787 (546 conflicted) | 1,788 (616 conflicted) |
| repeated lines: different | 200 | 213 | 212 |

The properties hold for all 4,000 triples. With only a few repeated line
values, several minimal base→side diffs exist. git (xdiff preprocessing and
heuristics) and GNU diff pick alignments differently from this Myers
implementation, which moves chunk boundaries. The inspected differences are of
this kind. Distinct-line triples have one alignment, and the oracle fails on
any disagreement there.

Verified execution is x86_64 Linux output from the GPU compiler. Other targets
have not been verified.
