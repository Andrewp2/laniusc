# Regenerating f6v after a merge of origin/lang (11-03, merge of e51443e05)

Every command in order, from the rfront worktree root
(/home/andrew-peterson/code/laniusc-wt/rfront), with its wall time and exit
code. `LS=target/claude-work/bin/leanslot` is
/home/andrew-peterson/code/laniusc/target/claude-work/bin/leanslot; `F6=`
/home/andrew-peterson/code/laniusc/target/claude-work/f6v. `lb` is f6v/bin/lb
(one leanslot `lake build` pass of at most 288 s from formal/; repeat until rc=0).
Hand steps (conflict resolution) are marked as such.

- `git merge --no-commit origin/lang > /home/andrew-peterson/code/laniusc/target/claude-work/f6v/scratch/merge3.log 2>&1` (0 s, rc=1)
- HAND: 9 proof files (SelfCompiler, ArrayCall, SourceCorrect, SourceOutcome, SourceStops, TextCorrect, TextWords, TypeSound, Validate) conflicted only in their `import all Lanius.Mini.Compiler.P.*` lines: keep the union of both sides (a python re.subn over the conflict block), `git add` them. (~1 min)
- HAND: TRUSTED_BASE.md's hash paragraph: lang's paragraph with a new "last change" merge entry (hash MERGEHASH, filled in after trusted_check) followed by f6v's own entries (S2, S3/S4), lang's former "last change" renamed "The change before". (python, ~3 min of reading)
- `for f in $(git diff --name-only --diff-filter=U); do git checkout --theirs -- $f; git add $f; done` (every remaining conflict is a generated file: Gen 145, GenB 7, GenP; <1 s)
- `/home/andrew-peterson/code/laniusc/target/claude-work/f6v/bin/lb extract` (4 s, rc=0)
- `HEAVY_PRIORITY=1 timeout 298 /home/andrew-peterson/code/laniusc/target/claude-work/bin/leanslot timeout 295 python3 -I formal/tools/lani_extract.py frontend > /home/andrew-peterson/code/laniusc/target/claude-work/f6v/scratch/ext_frontend.log 2>&1` (8 s, rc=0)
- `HEAVY_PRIORITY=1 timeout 298 /home/andrew-peterson/code/laniusc/target/claude-work/bin/leanslot timeout 295 python3 -I formal/tools/lani_extract.py compiler > /home/andrew-peterson/code/laniusc/target/claude-work/f6v/scratch/ext_compiler.log 2>&1` (3 s, rc=0)
- `N=40 /home/andrew-peterson/code/laniusc/target/claude-work/f6v/bin/lb LaniusMini Lanius.Mini.FrontLex` (174 s, rc=0)
- HAND: the union kept `import all Lanius.Mini.Compiler.P.imageLimit`, a part lang's compiler.lani no longer has (the build stops at "unknown module"): `grep -rln "import all Lanius.Mini.Compiler.P.imageLimit$" Lanius | xargs sed -i '/.../d'` (<1 s). Better rule for the tool: after extraction, drop any `import all ...P.X` whose P/X.lean does not exist.
- `N=40 /home/andrew-peterson/code/laniusc/target/claude-work/f6v/bin/lb LaniusMini Lanius.Mini.FrontLex` (101 s, rc=0)
- `HEAVY_PRIORITY=1 timeout 298 /home/andrew-peterson/code/laniusc/target/claude-work/bin/leanslot timeout 290 python3 -I /home/andrew-peterson/code/laniusc/target/claude-work/f6v/regen_gen.py /home/andrew-peterson/code/laniusc/target/claude-work/f6v/faithful 2>&1 | tail -1 | cut -c1-120` (13 s, rc=0)
- `HEAVY_PRIORITY=1 timeout 298 /home/andrew-peterson/code/laniusc/target/claude-work/bin/leanslot timeout 290 python3 -I /home/andrew-peterson/code/laniusc/target/claude-work/f6v/regen_gen.py /home/andrew-peterson/code/laniusc/target/claude-work/f6v/faithful 2>&1 | tail -1 | cut -c1-120` (8 s, rc=0)
- `HEAVY_PRIORITY=1 timeout 298 /home/andrew-peterson/code/laniusc/target/claude-work/bin/leanslot timeout 290 python3 -I /home/andrew-peterson/code/laniusc/target/claude-work/f6v/regen_gen.py /home/andrew-peterson/code/laniusc/target/claude-work/f6v/faithful 2>&1 | tail -1 | cut -c1-120` (7 s, rc=0)
- `HEAVY_PRIORITY=1 timeout 298 /home/andrew-peterson/code/laniusc/target/claude-work/bin/leanslot timeout 290 python3 -I /home/andrew-peterson/code/laniusc/target/claude-work/f6v/regen_gen.py /home/andrew-peterson/code/laniusc/target/claude-work/f6v/faithful term 2>&1 | tail -1 | cut -c1-120` (12 s, rc=0)
- `HEAVY_PRIORITY=1 timeout 298 /home/andrew-peterson/code/laniusc/target/claude-work/bin/leanslot timeout 290 python3 -I formal/tools/budget_certs.py /home/andrew-peterson/code/laniusc/target/claude-work/f6v/faithful/Self.lean formal/Lanius/Faithful/GenB front_end_words grammar compile_words 2>&1 | tail -1` (1 s, rc=0)
- `cd formal && HEAVY_PRIORITY=1 timeout 298 /home/andrew-peterson/code/laniusc/target/claude-work/bin/leanslot timeout 290 python3 -I tools/hb_gen.py  Lanius/Faithful/SelfPre/HB.lean Lanius/Mini/Compiler/Types.lean Lanius/Mini/Frontend/Types.lean 2>&1 | tail -1` (0 s, rc=0)
- `cd formal && HEAVY_PRIORITY=1 timeout 298 /home/andrew-peterson/code/laniusc/target/claude-work/bin/leanslot timeout 290 python3 -I tools/hb_gen.py --sum Lanius/Faithful/SelfPre/SZ.lean Lanius/Mini/Compiler/Types.lean Lanius/Mini/Frontend/Types.lean 2>&1 | tail -1` (0 s, rc=0)
- `cd formal && HEAVY_PRIORITY=1 timeout 298 /home/andrew-peterson/code/laniusc/target/claude-work/bin/leanslot timeout 290 python3 -I tools/hb_gen.py --slots Lanius/Faithful/SelfPre/TS.lean Lanius/Mini/Compiler/Types.lean Lanius/Mini/Frontend/Types.lean 2>&1 | tail -1` (0 s, rc=0)
- `cd formal && HEAVY_PRIORITY=1 timeout 298 /home/andrew-peterson/code/laniusc/target/claude-work/bin/leanslot timeout 290 python3 -I tools/hb_gen.py --nums Lanius/Faithful/SelfPre/NB.lean Lanius/Mini/Compiler/Types.lean Lanius/Mini/Frontend/Types.lean 2>&1 | tail -1` (0 s, rc=0)
- `cd formal && HEAVY_PRIORITY=1 timeout 298 /home/andrew-peterson/code/laniusc/target/claude-work/bin/leanslot timeout 290 python3 -I tools/pre_certs.py Lanius/Faithful/GenB Lanius/Faithful/SelfPre/GenP build_files 2>&1 | tail -1` (0 s, rc=0)
- `/home/andrew-peterson/code/laniusc/target/claude-work/f6v/bin/lb Lanius.Faithful.SelfBounded Lanius.Faithful.SelfPre Lanius.Faithful.SelfPre.GenP.SelfP02 LaniusOpen` (288 s, rc=0)
- `/home/andrew-peterson/code/laniusc/target/claude-work/f6v/bin/lb Lanius.Faithful.SelfBounded Lanius.Faithful.SelfPre Lanius.Faithful.SelfPre.GenP.SelfP02 LaniusOpen` (288 s, rc=0)
- `/home/andrew-peterson/code/laniusc/target/claude-work/f6v/bin/lb Lanius.Faithful.SelfBounded Lanius.Faithful.SelfPre Lanius.Faithful.SelfPre.GenP.SelfP02 LaniusOpen` (230 s, rc=0)
- `/home/andrew-peterson/code/laniusc/target/claude-work/f6v/bin/lb runAll extract floatTest x86ModelTest srcDump topAxioms LaniusMini Lanius.Mini.FrontLex Lanius.Mini.MutPilotCorrect Lanius.Machines.SqliteStatementCorrect Lanius.Machines.TlsLifecycleCorrect Lanius.Machines.RunLowering Lanius.Faithful.SelfBounded Lanius.Faithful.SelfPre LaniusOpen Lanius` (5 s, rc=0)
- `HEAVY_PRIORITY=1 timeout 298 /home/andrew-peterson/code/laniusc/target/claude-work/bin/leanslot timeout 290 python3 -I formal/tools/trusted_check.py /home/andrew-peterson/code/laniusc/target/claude-work/f6v/scratch/tc3 2>&1 | tail -3` (12 s, rc=0)
- HAND: put the hash trusted_check printed into TRUSTED_BASE.md (header line `definitions `HASH` (N constants)` and the merge entry): `sed -i` (<1 s)
- `HEAVY_PRIORITY=1 timeout 298 /home/andrew-peterson/code/laniusc/target/claude-work/bin/leanslot timeout 295 python3 -I formal/tools/gate.py --tier quick --jobs 2 > /home/andrew-peterson/code/laniusc/target/claude-work/f6v/scratch/gate.log 2>&1` (124 s, rc=0)
- `git add -u formal && git commit -q -m 'Merge origin/lang (e51443e05) into f6v

Proof files: union of the P-part imports (imageLimit, gone on lang, dropped).
TRUSTED_BASE: merge entry over f6v S2/S3/S4 and lang (leafB code check,
F5 S1-S4), hash 3e2d79cbfea12073 (4810 constants). Generated files
regenerated: P parts, Gen, term, GenB, HB, SZ, TS, NB, GenP. Quick gate 25/25.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>'` (1 s, rc=0)

## Notes for one regeneration command

- Order matters: extract exe first (`lb extract`), then `lani_extract.py frontend`, then `compiler` (the extract exe
  imports the Frontend P parts; a stale part with a missing match arm stops it: in the first merge round I had to
  hand-patch two arms of P/variantIn.lean before extraction could run).
- After extraction: drop `import all ...P.X` lines whose `P/X.lean` no longer exists (union-resolved import blocks).
- `regen_gen.py WORKDIR` must run until it prints `gen changed: 0` (usually 3 runs: the 2nd changes SelfNeeds.lean only,
  because SelfNeeds' import closure reads the real Gen dir).
- `pre_certs.py` names its modules after OUTDIR, so write straight into `formal/Lanius/Faithful/SelfPre/GenP`
  (a scratch OUTDIR gives wrong module names). hb_gen has four modes: (none) HB, --sum SZ, --slots TS, --nums NB.
- GenPC (compile side) is not imported by anything; I left it as lang's.
- Builds: each `lb` pass is capped at 288 s; repeat until rc=0 (3 passes for the Faithful/Open set after a merge).
  "cannot allocate memory" while starting lean is machine-wide pressure: just rerun.
- The trusted hash can only be filled in after the trusted check; then the gate.
