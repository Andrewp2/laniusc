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
- 11-03 (leafB), analysis before a proof:
  - Height does not bound the compile side's numbers. Sums over lists (`codeSize`, `linkedSize`, layout
    offsets, `14 * args.length` summed over calls) are bounded by the total size of the code, which
    heights bound only through products (`hb L * hb args`, past `2 ^ 64` already at heights `2 ^ 33`); and
    compiled code's height is not bounded by the program's height (an expression tree of height h gives
    up to 2 ^ h instructions). So `hb p <= 2 ^ 48` alone is not enough; the bound wanted is on the total
    size (a sum measure `sz`, every node counted once) of p, through cost-free size lemmas
    `sz (f x) <= A * sz x + B`.
  - The growth factor comes from the front end's type weights (<= 2 ^ 22): `pickElement` expands one
    `array[i]` into `count` copies of `slotVars (base + k * size) size` with `k < count < 2 ^ 31` and
    `count * size` within the array type's weight. So the code is at most about `2 ^ 22 * c * sz p`; with
    `sz p` below about `2 ^ 31` words' worth, every size stays below `2 ^ 60`.
  - Without the weight bound the statement would be false within the budget: about `2 ^ 58` instructions
    (a few hundred array accesses with `count * size` near `2 ^ 53`) make `codeSize` pass `2 ^ 64` while
    the budget (`2 ^ 61`) still runs.
  - Plan: hb_gen sum mode for `sz`; a FrontEndOutputSize statement (`sz p` bounded, weights <= 2 ^ 22 in
    every type of p); a pre_certs mode for the size lemmas; V2's reduction from them plus the M-form
    lemmas run at a K small enough for the sizes. Not started.
