# Brief for verified-compiler agents (2026-11-02)

You work on the verified compiler: the compiler written in Lanius
(formal/lani/mini/frontend.lani, compiler.lani), extracted to Lean and
proved in formal/Lanius/Mini and formal/Lanius/Faithful. The plan is
formal/ROADMAP.md ("The full verified compiler", F1-F15); decisions are
in formal/SEMANTIC_DECISIONS.md; the trusted base is formal/TRUSTED_BASE.md.
The coordinator merges your branch into `lang` and pushes; you never push.

Where you work
- Your worktree is /home/andrew-peterson/code/laniusc-wt/<name>, on your own
  branch. Never touch the main checkout /home/andrew-peterson/code/laniusc.
- Keep notes under target/claude-work/<name>/ (RESUME.md current at every
  step, so a restart loses nothing). /tmp is wiped on reboot.

Proof rules (no exceptions)
- No sorry, native_decide, bv_decide, new axioms. `decide +kernel` is fine.
- Exhaustive matches only, no wildcard `_` arms in Lean (a wildcard's
  equation lemmas blow up). For mutual structural recursion use
  termination_by structural and hoist recursive calls before `cases`.
- Design decisions are yours: record each in SEMANTIC_DECISIONS.md (and in
  TRUSTED_BASE.md when a trusted definition changes). Don't ask the user.

How proofs are organised (11-03, formal/OPEN_STATEMENTS.md)
- Large proofs go through the open-statement graph: write the statements
  first (`def Lanius.Open.X : Prop`, with a docstring, never changed once on
  lang), reduce each to smaller ones with complete theorems, prove the leaves.
  `lv open status` shows what is open; claim a
  statement before working on it; log failed attempts in its NOTES.md.
- One statement per directory, so parallel agents never edit the same file.

Tools and machine (15 GB laptop, one GPU)
- One front door: target/claude-work/bin/lv (source formal/tools/lv; see
  formal/tools/README.md, "The front door"). Run it from your worktree:
  `lv check FILE.lean` (one file, errors whole), `lv build [TARGETS]`
  (default LaniusMini Lanius LaniusOpen), `lv gate` (quick tier; `lv gate
  --only STEP`), `lv regen [--resolve | --only trusted --trusted]`,
  `lv open status|check|claim|release`, `lv heavy ..`, `lv lcc ..`, `lv status`
  (who holds the slots), `lv cache` (finds truncated Lake outputs, as a full
  disk leaves them). `lv merge COMMIT` is the coordinator's (fast-forward only).
  lv takes the locks and slots, work.slice, memwait, the 1-byte core limit and
  cache pruning itself, and fails loudly (nonzero exit, the real errors, the
  log path). The old names (leanslot, lcheck, heavy, lcc, memwait, merge1,
  cacheprune, agentstatus) are aliases of it.
- Never run lake or lean bare (`lv lake ARGS` for other lake commands), never
  set LEAN_NUM_THREADS (deadlocks lake). Tests only through `lv gate`.
- Cargo and laniusc only through `lv heavy`; compile Lanius with `lv lcc`.
  One GPU job at a time (heavy queues).
- Memory: all work runs in work.slice (soft budget, nothing is killed) and
  every lean/laniusc/cargo start waits in memwait. Never add MemoryMax or any
  memory cap/kill of your own.
- No command, and no loop of commands, runs more than 5 minutes in total.
  Every lv command ends within 295 s, lock waits included, and never reruns
  itself; at its deadline `lv build` prints what was still compiling. If
  something needs longer, stop and find out why; don't rerun, chain or shard
  runs to beat the limit.
- Never run `ulimit -c 0` (shells start with a 1-byte core limit, which keeps
  Ubuntu's crash dialog away; 0 brings it back).
- No strace/gdb/valgrind; never pkill -f / pgrep -f; never kill another
  agent's processes; no sudo, no downloads.
- After .lani edits, rebuild the whole library (LaniusMini and the top
  modules), regenerate certificates, and keep `self-current`,
  `frontend-cases`, `extract` and `trusted` passing. A .lani must pass the
  self front end (name clashes with compiler.lani, outer-binder fields in
  nested arms). Front-end cases (formal/tools/frontend_cases/<case>/) need
  want.lani, expect.out (checked by hand against the source) or `reject`.

Merging origin/lang after .lani changes (11-03, formal/tools/README.md)
- Generated files (Gen, GenB, extracted parts) never conflict: the merge
  driver keeps ours and regen.py rewrites them. Procedure: `git merge
  --no-commit lang` (local lang: GitHub pushes may lag) in your branch;
  resolve .lani, proofs and TRUSTED_BASE prose by hand; `lv regen --resolve`;
  `lv build`; `lv regen --only trusted --trusted`; `lv gate`; commit. The
  coordinator's `lv merge` then fast-forwards lang to your branch, so it must
  contain local lang. Never hand-merge generated files.
- .lani changes to frontend.lani/compiler.lani land one at a time: tell the
  coordinator when one is ready and wait for your turn.

Committing and reporting
- Commit each working step on your branch with specific paths (`git add
  path...`, never .claude/); messages end with
  "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>".
- Say "the verified compiler", never "vc". Keep ROADMAP rows current.
- When you finish a piece, report in a few lines: commit, what is proved,
  gate result, what is left.
