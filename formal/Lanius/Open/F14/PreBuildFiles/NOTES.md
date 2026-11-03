# PreBuildFiles

- 11-03 (f14c): every generated lemma under it passes except the let_first step (PreStepLetFirst).
  Its reduction: GenP/SelfP07 taking `Lanius.Open.PreStepLetFirst` for that step.
- 11-03 (f14c): the reduction PreBuildFiles.red1 (h : PreStepLetFirst) is `pre_build_files` with GenP/SelfP07
  taking this statement for the let_first step; not added yet, because a Red file importing GenP puts the
  whole GenP chain (about 4 minutes fresh) into the gate's LaniusOpen build.
