# formal/tools

The generators, checkers and difftests of the verified compiler. Each script's
docstring says what it does; tests run only through `gate.py`.

## The front door: `lv`

`formal/tools/lv` runs everything that needs the machine's shared locks and
limits; it replaces leanslot, lcheck, heavy, lcc, memwait, merge1 and
cacheprune, and is the way to run gate.py, regen.py and open_graph.py. Run it
from your worktree (it works on that worktree's `formal/`); the installed
copy is `target/claude-work/bin/lv`.

| command | does | was |
|---|---|---|
| `lv check FILE.lean..` | `lake env lean FILE` in the small lane, 280 s; prints each error whole (warnings counted; `--all` prints them) | lcheck, leanp |
| `lv build [TARGET..]` | `lake build` (default `LaniusMini Lanius LaniusOpen`) under a Lean slot; skips the slot when the targets are current; errors whole plus the failed modules; at the deadline it prints the modules still compiling (and those waiting for a lean process slot) and stops: it never reruns itself | leanslot + lake, lb |
| `lv gate [ARGS]` | gate.py (default `--tier quick --jobs 2`) under one slot for the whole run, 295 s; a failed step's error lines from its output.txt | leanslot + gate.py |
| `lv regen [ARGS]` | regen.py the same way (`--resolve`, `--only trusted --trusted`, `--check`) | leanslot + regen.py |
| `lv open ARGS` | open_graph.py (`status`, `check`, `claim NAME --agent WHO`, `release NAME`) | |
| `lv merge COMMIT` | coordinator only, main checkout on lang: fast-forward only (refuses a COMMIT that lacks local lang: merge lang into the branch and gate there first), quick gate, push with a 60 s limit (a failed push leaves local lang ahead, exit 0), prune and check the cache | merge1 |
| `lv lake ARGS` / `lv slot CMD..` | any other lake command, or any command, holding a Lean slot | leanslot |
| `lv heavy ..` / `lv lcc ..` | the GPU lane and the resident compiler (lv.d/heavy, lv.d/lcc, unchanged) | heavy, lcc |
| `lv memwait`, `lv prune`, `lv status` | the memory rule, Lake cache pruning, who holds which lock | memwait, cacheprune, agentstatus |
| `lv cache` | checks every Lake output (the shared cache and this worktree's build) for truncation and quarantines damaged ones | regen/badolean.py |

Rules it keeps: one lock per worktree and one of three machine-wide Lean
slots for builds and tools; every scope in `work.slice` (soft memory budget,
nothing killed for memory); memwait before each lean (through
`target/claude-work/leanroot/bin/lean`, which also caps lean processes at
six), heavy job and single-file check; a core limit of exactly 1 byte (0
brings apport back); `LEAN_NUM_THREADS` unset for lake. Stale Lake cache
artifacts are pruned at most every six hours by build/gate/regen, and after
each merge.

Damaged outputs: when the disk fills, Lean leaves truncated or empty oleans
(and .ir, .ilean, .c) that Lake caches and every later import segfaults on.
After each build, gate and regen, lv checks the outputs written since it
started (each full prune checks them all): an olean's root object (its header
points at it) must end exactly at the end of the file, an .ilean must end
with `}`, a .c with `#endif`. A damaged file goes to
`target/claude-work/lv/badcache/`, with the cache mappings that name it, and
every worktree build file that is the same file is deleted with its module's
trace, so the next `lv build` rebuilds the module; the command then fails.

One deadline: every lv command ends within 295 s of its start, lock and slot
waits included (exit 75 if the waits leave under 20 s, 124 if the deadline
stopped the work), and nothing is ever rerun automatically. Don't loop lv
commands either: the 5-minute rule is for the whole task, so a build that
needs longer is a problem to report, not to retry.

Failures are loud: the exit code is nonzero (124 when the time limit
stopped it), the error messages are printed whole, and the full log's path
is printed (`target/claude-work/lv/` in the worktree). A build stopped at the
deadline keeps what finished.

`lv install` (from a checkout that has this lv) copies it to
`target/claude-work/lv/`, links `target/claude-work/bin/lv` to it, turns the
old wrappers in `target/claude-work/bin` into one-line aliases (the originals
are kept in `bin/pre-lv/`; `lv uninstall` puts them back) and links
`leanroot/bin/lean` to `lv.d/lean`. The installed copy runs any worktree's
`formal/tools`, so worktrees made before lv still work.

## Regenerating the generated files: `regen.py`

After any change to `formal/lani/mini/*.lani` (or to a generator), one command
rewrites every generated Lean file, in dependency order, and reports each
stage's time and changed files:

    lv regen

| stage   | writes                                                    | tool                                  |
|---------|-----------------------------------------------------------|---------------------------------------|
| extract | `Lanius/Mini/{Compiler,Frontend,Extract}{,.lean,/Types.lean,/P/}`, `Lanius/Machines/SqliteStatement*`, import blocks | `lani_extract.py` |
| dump    | the self program's dump (work directory only)             | `lake build srcDump`, `faithful_dump.py` |
| gen     | `Lanius/Faithful/Gen/` but `SelfTerm*`                    | `faithful_certs.py`, `faithful_pure.py` |
| genb    | `Lanius/Faithful/GenB/`                                   | `budget_certs.py`                     |
| term    | `Lanius/Faithful/Gen/SelfTerm*.lean`                      | `term_gen.lean` (builds `Gen.SelfProg`) |
| hb      | `Lanius/Faithful/SelfPre/{HB,SZ,TS,NB}.lean`              | `hb_gen.py` (four modes)              |
| pre     | `Lanius/Faithful/SelfPre/GenP/`, `GenPC/` (only the modules checked in) | `pre_certs.py`          |
| trusted | the definitions hash in `TRUSTED_BASE.md` (`--trusted` only) | `trusted_check.py`                 |

A stage whose inputs and outputs are as a run of it left them is skipped
(`--force` runs it anyway); `--only gen,genb` runs some stages. `--check` writes
nothing and fails when a generated file differs from what regen.py would write:
the gate's `regen-current` step (quick tier, about 20-60 s). One run is
enough: there is no "run Gen until nothing changes". The building of the
library is not part of it: regen needs only `srcDump` and `Gen.SelfProg`.

## Merging without conflicts in generated files

`formal/.gitattributes` gives the generated files the merge driver
`lanius-generated` (keep ours, never a conflict; `regen.py` rewrites them) and
every other Lean file `lanius-lean` (git's merge, but a conflict between import
lines at the top of a file takes both sides' lines). The drivers are
`merge_driver.py`. Git needs them defined in the repository's config. Run these
once, from any checkout; they write the shared `.git/config`, so every worktree
gets them:

    git config merge.lanius-generated.name 'generated Lean file: keep ours, formal/tools/regen.py rewrites it'
    git config merge.lanius-generated.driver 'f=formal/tools/merge_driver.py; if [ -f "$f" ]; then python3 -I "$f" generated %O %A %B %L %P; else git merge-file -L ours -L base -L theirs %A %O %B; fi'
    git config merge.lanius-lean.name 'Lean file: conflicting top-of-file imports take both sides'
    git config merge.lanius-lean.driver 'f=formal/tools/merge_driver.py; if [ -f "$f" ]; then python3 -I "$f" lean %O %A %B %L %P; else git merge-file -L ours -L base -L theirs %A %O %B; fi'

Without them, git merges these files as plain text, as before.

The merge procedure (from the worktree root):

1. `git merge --no-commit origin/lang`. Generated files keep ours and are
   listed in `lanius-regen-stale` in the worktree's git directory. A file whose only conflicts were
   top-of-file imports is merged cleanly.
2. Resolve what is left by hand: sources (`.lani`), proofs, and
   `TRUSTED_BASE.md`'s last-change paragraph (the hash comes in step 5).
   `git add` them.
3. `lv regen --resolve`:
   settles the generated files git still lists as unmerged (a side that
   deleted one), regenerates everything from the merged sources, drops the
   imports of extracted parts that no longer exist from the files the merge
   unioned, and stages (`git add`) the generated files.
4. Build: `lv build`, repeated until it exits 0 (124 is a pass cut short at
   the limit). Most of this is the rebuild the
   change causes, not regen: see "Where a regeneration's time goes" below.
5. `lv regen --only trusted --trusted`:
   writes the new definitions hash into `TRUSTED_BASE.md`; say in its
   last-change sentence what the merge combined.
6. The quick gate: `lv gate`.
7. `git commit`.

## Where a regeneration's time goes (11-03, measured)

regen.py itself: about 8 s when nothing changed, 25-45 s after a one-function
change (extract 13-21 s, mostly the CPU parser's tree of the changed file;
dump 6-20 s; gen 2.5 s; genb 1.5 s; term 1-8 s; hb 0.1 s; pre 1 s), plus the
`srcDump` rebuild, 1-240 s: `Lanius.Tools.SrcDump` imports `Mini.FrontLex`,
which `public import`s `Lanius.Mini.Compiler`, so a change to an `@[expose]`d
extracted part (every `Inline.*`) rebuilds FrontLex and SrcDump.

The old 30 minutes were the Lean builds. Renaming one local of `room_after`
in compiler.lani rebuilt 362 modules, about 7100 s of lean time, three
288-s build passes:

- 3600 s: all 75 `GenB/SelfBProof*` parts, though one model (`Pre_room_after`,
  used by one part) changed. GenB's files are not modules, `SelfBModel0`
  imports `Gen.SelfCert` (so any change to the self program reaches it), the
  model parts form a chain, and every proof part imports the last statement
  part, so any change rebuilds every budget proof, then GenP (60-85 s each)
  and Open/F14.
- 1500 s: 93 `Faithful/Gen` modules.
- 760 s: 72 `Open/F5` modules, and 24 `Lanius.Mini` proofs (Source, LowerEval,
  TypeSound, ..), which `import all` the changed part `Compiler.P.linkedSize`
  (Source without using it) and so rebuild, with what imports them.

Making the builds narrower means changing those layouts (budget_certs.py's
parts as modules with hidden bodies, bucketed per function like Gen's; the
proofs' `import all` lists cut to the parts they unfold), not the generators'
speed.
