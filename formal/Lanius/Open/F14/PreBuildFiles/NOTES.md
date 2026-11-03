# PreBuildFiles

- 11-03 (f14c): every generated lemma under it passes except the let_first step (PreStepLetFirst).
  Its reduction: GenP/SelfP07 taking `Lanius.Open.PreStepLetFirst` for that step.
- 11-03 (f14c): the reduction PreBuildFiles.red1 (h : PreStepLetFirst) is `pre_build_files` with GenP/SelfP07
  taking this statement for the let_first step; not added yet, because a Red file importing GenP puts the
  whole GenP chain (about 4 minutes fresh) into the gate's LaniusOpen build.
- 11-03 (f14c): proved in GenP at e2a80029c (linear certificates in pre_auto): `SelfPre.pre_step_let_first` is this
  statement and `SelfPre.pre_build_files` gives PreBuildFiles. Proof.lean (and PreBuildFiles.red1) wait until GenP
  is in the gate's build (cold chain about 4 minutes on 11-03, SelfP07 115 s alone).
- 11-03 (f14c): Proof.lean added: `SelfPre.pre_build_files` (GenP/SelfP02). GenP's chain now builds in about
  2 minutes cold at load 8 (one module per kind, faster pre_auto); the gate builds it through LaniusOpen.
