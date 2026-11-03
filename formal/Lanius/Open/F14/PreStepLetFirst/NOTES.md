# PreStepLetFirst

- 11-03 (f14c): `pre_auto` on the generated step (GenP/SelfP07, scratch:
  `f14c/tools/scratch.py 07 pre_step_let_first --debug`) works steadily for ~68 s (about 2,000 premise
  instantiations over Pre_let_first's if-chain of let forms) and hits maxHeartbeats 1000000; no single
  slow step. Options: a PRE_HAND entry in tools/pre_certs.py that splits the top-level `if`s and runs
  `pre_auto n, M` per branch (each under its own heartbeats), or caching hbFacts across sibling goals.
  Raising heartbeats alone would put P07 near 3-4 minutes.
- 11-03 (f14c): a separate root for now. Its parent is PreBuildFiles (through `pre_build_files`), but that
  reduction would import GenP/SelfP07, and the gate builds all of LaniusOpen: the GenP chain (about 4 minutes
  cold) stays out of the quick gate until it builds well under 2 minutes. Then PreBuildFiles.red1 is added.
- 11-03 (f14c): proved in GenP at e2a80029c (linear certificates in pre_auto): `SelfPre.pre_step_let_first` is this
  statement and `SelfPre.pre_build_files` gives PreBuildFiles. Proof.lean (and PreBuildFiles.red1) wait until GenP
  is in the gate's build (cold chain about 4 minutes on 11-03, SelfP07 115 s alone).
- 11-03 (f14c): Proof.lean added (c60c8ce17 layout: GenP/SelfP02 holds every precondition lemma). Why it took
  ~70 s: Pre_let_first's if-chain of let forms gives 374 leaf goals (closeArith splits the Lean side's `&&`s
  too), each asking ~13 premises of ~6 facts; the sibling goals' facts are fresh hypotheses, so the premise
  cache missed (1,940 stale of 3,974 lookups) and every fact was re-simped. Fixed in the tactic, no split
  needed: reuse across siblings by hypothesis type, cached fact normal forms, subtraction chains without
  search (omega calls 239 -> 68). The step now takes about 15 s of tactic time.
