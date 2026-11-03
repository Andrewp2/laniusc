# PreCompileSourceV2

- 11-03 (leafB): replaces PreCompileSource (see its NOTES). The generated M-form lemmas (SelfPre/GenPC,
  PreCompileSource/NOTES.md) prove all the compile side's height (post) lemmas; at least 100 of the 456
  pre lemmas fail on numbers hb counts as 0. Plan: cost-free bounds on those numbers in terms of the
  program (not M plus cost), with value lemmas (`val_<T>_<f>`, SelfPre/CompileValues) for the small ones.
