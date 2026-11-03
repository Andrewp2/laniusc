# PreCompileSourceV2

- 11-03 (leafB): replaces PreCompileSource (see its NOTES). The generated M-form lemmas (SelfPre/GenPC,
  PreCompileSource/NOTES.md) prove all the compile side's height (post) lemmas; at least 100 of the 456
  pre lemmas fail on numbers hb counts as 0. Plan: cost-free bounds on those numbers in terms of the
  program (not M plus cost), with value lemmas (`val_<T>_<f>`, SelfPre/CompileValues) for the small ones.
- 11-03 (leafB): GenPC is generated with `--compile` now (the compile side's hand proofs are kept apart
  from build_files'): `python3 -I tools/pre_certs.py --compile --ns Lanius.Faithful.SelfPre.Compile --base Lanius.Faithful.SelfPre.CompileValues Lanius/Faithful/GenB Lanius/Faithful/SelfPre/GenPC compile_source binary_words`.
  SelfP01 was 72-80 s because post_auto spent 3-16 s each on the byte encoders (prologue, slot_compare,
  store_at_bytes, store_word_bytes: one omega over every cost atom per cons cell); every encoder built
  from the u8 list primitives, le32 and le64 alone now takes the length proof (`auto_bytes`). With f14c's
  certificate speedup SelfP01 is 35 s, spread over its 400 lemmas (none over 1.3 s); SelfP02 9 s.
