# PreCompileSource

- Not generated yet. `python3 -I tools/pre_certs.py Lanius/Faithful/GenB <outdir> compile_source` emits
  the M-form post and pre lemmas (as GenP does for build_files); the ones that fail become new statements
  under this one, their reduction this statement. Overrides and value lemmas: tools/pre_certs.py
  (OVERRIDES, PRE_HAND) and SelfPre/Values.lean. Type sizes are at most 2 ^ 22 only for the front end's
  output (the front end's weight check), hence the frontEndWords premise.
- 11-03 (leafB): generated, with root binary_words too, into SelfPre/GenPC (namespace
  `Lanius.Faithful.SelfPre.Compile`, since 4 cost models and 2 uposts are shared with build_files' GenP):
  `python3 -I tools/pre_certs.py --ns Lanius.Faithful.SelfPre.Compile --base Lanius.Faithful.SelfPre.CompileValues Lanius/Faithful/GenB Lanius/Faithful/SelfPre/GenPC compile_source binary_words`
  (from formal/). 40 uposts, 376 post groups, 252 pre groups, 8 modules.
  - Posts (SelfP00-02) all pass after: byte literals normalized (`UInt8.ofNat 72` vs `72`, Tactic
    `uint8_ofNat_lit`); `decide True && c` normalized (`decide_true`); hand proofs for the long byte lists
    (bump_bytes, frame_memory_bytes, sys_bytes: post_auto ~60-80 s each, then out of heartbeats; plain
    `omega` ~60 s too, it unfolds Cost_concat_of_u8 comparing atoms, so `omega_atoms`), link (post_auto
    split Inline.link's `if` again and again), SrcStmt.declare's ifEval/matchArm (nested matches: the
    leaf had the cost at `none` and the function at `some`).
  - Pres (SelfP03-07): at least 100 of 456 lemmas fail (Lean stopped reporting at 100), all
    `omega` budget: the compile side's numbers (slots, frame sizes, slot offsets, code sizes, counts,
    offsets) are values hb does not bound (it counts Nat as 0), e.g. `Pre_frame_size n x b` needs
    `x + 1 < 2 ^ 64`. These need value bounds (OVERRIDES on the callees plus value facts at the callers),
    not one open statement each.
- Not imported by LaniusOpen: GenPC SelfP01 alone takes 72 s of its own (cold chain over 2 minutes).
- 11-03 (leafB): replaced by `PreCompileSourceV2` (PreCompileWords.red2). The M-form premise
  `M + b <= 2 ^ 62` bounds a value by the potential plus the cost so far, which the budget (up to `2 ^ 61`
  in PreCompileWords) allows to be near `2 ^ 62`; the compile side multiplies and sums such values
  (`codeSize`, `14 * count`), so this statement is not provable that way. Left unused.
