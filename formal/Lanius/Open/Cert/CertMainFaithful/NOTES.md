# CertMainFaithful

Notes (append only): attempts, dead ends, hints.

- 11-04: the one open leaf of CertNatSound. It needs Core's run of `main` (Lanius.Cert.prog) related
  to `check` loop by loop: reading stdin into the alloc'd buffer, `slice_from_raw_parts`, i32 index
  reads of the slice as `rd (wordsOf input)`, and each `while` as the fuel function of the same name
  in Lanius/Cert/Shallow.lean (plus `mix`/`hash_tree`, which change no code). No existing lemmas
  cover raw-slice reads in Core; a symbolic-evaluation layer for Core function bodies is the likely
  first step (a lemma per Core statement form, then one per check_mini function).
