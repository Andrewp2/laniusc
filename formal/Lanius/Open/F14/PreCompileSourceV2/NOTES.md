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
- 11-03 (leafB), step 1 done: `tools/hb_gen.py --sum` generates `SelfPre/SZ.lean` (the total size `sz`,
  simp set `sz_simp` in `SelfPre/SZAttr.lean`; builds in 10 s). Without `--sum` HB.lean regenerates
  byte for byte the same. Command (from formal/): `python3 -I tools/hb_gen.py --sum
  Lanius/Faithful/SelfPre/SZ.lean Lanius/Mini/Compiler/Types.lean Lanius/Mini/Frontend/Types.lean`.
- 11-03 (leafB), step 2 stopped: `sz p <= A * (input words) + B` for the whole program is false, so
  FrontEndOutputSize was not written in that form.
  - Monomorphization copies a body once per instance, and `mono_loop` allows up to `files_fuel`
    (about `4 * (tokens + prods)`) instances. A source of size O(d + m) with g_i<T> calling
    g_{i+1}<A<T>> and g_{i+1}<B<T>> (A, B one-field structs, so weights stay about d) has 2^d instances
    of g_d, each a copy of g_d's body of size m. With d = 30 and m near 2^30 that is about 2^60 nodes
    from fewer than 2^31 words. The output is quadratic in the input, not linear.
  - Lowered types are shared from the type table (`closeTy`), so one use of a type of weight 2^22 adds
    up to 2^22 nodes to `sz p` at cost 1. `sz p <= Cost_front_end_words` is false for the same reason;
    `sz p <= 2 ^ 23 * Cost_front_end_words` is plausible but gives `sz p <= 2 ^ 84` under the root budget.
  - So V2 (at any budget, `hb p <= 2 ^ 48`) is probably false: such a p (height about 2^30) compiles to
    more than 2^64 bytes, and `link` sums `linkedSize` and lays out offsets before the `image_limit`
    check. PreCompileWords bounds the budget (front-end cost + b <= 2^61), and V2 drops that bound.
  - A sum measure has no generic post lemma `sz (F x) <= sz x + Cost_F`: sharing breaks it (a function
    that conses a parameter n times has size n * sz x at cost n). Heights (`hb`) and max-measures are
    not affected by sharing.
- 11-03 (leafB), what is true and is enough, by kind of number (proposal; not written as statements yet):
  - Type numbers (`SrcType.size`, `fieldOffset`, `k * size` in pickElement, `max` of sizes): at most the
    largest type weight in p. That is a max-measure `tw` (hb_gen max mode with SrcType counted as its
    weight), which sharing does not affect. The front-end fact is `tw p <= weightLimit`.
  - Per-function numbers (locals, temps, slots, frame sizes, a function's codeSize,
    `14 * args.length + ...`): at most about `2 ^ 22 * sz f` for the function f being compiled. The
    front-end fact is per function: `forall f in p.funcs, sz f <= A * W.length + B`. A body is read once
    per instance from one declaration, with types of weight <= 2^22 put in, so A is about 2^26. Each
    such bound is below 2^60.
  - Whole-program numbers (`linkedSize`, layout entries, `link_onto` offsets): at most `#funcs * max`
    with up to 2^33 functions, so neither the height nor a cost-free bound fits. There are two ways:
    (a) a budget-relative bound, which needs size-post lemmas for `compile_funcs` (its codes are built
    fresh) on top of PreCompileWords' budget; or (b) a small compiler change: check `image_limit` as
    `layout` and `linked_size` add up (or reject a Code larger than `image_limit` in `compile_func`),
    so every whole-program number stays below about 2^31 with no budget.
  - The front end's output has `statics = []` (`build_collected`), so statics adds nothing.
- 11-03 (leafB): unused. PreCompileWords.red3 uses PreCompileSourceV3 instead (V2 is probably false at
  any budget, see above). The compiler now checks the image limit as the sizes add up (`room_after`,
  SEMANTIC_DECISIONS "The image limit checked as the sizes add up"), so whole-program sums need no size
  lemmas. Per-function slot numbers come from `SrcStmt.depth` (FrontEndStmtDepth) and type sizes from
  `ts` (FrontEndTypeSlots).
