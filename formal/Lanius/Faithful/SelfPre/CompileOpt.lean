import Lanius.Open.F14.OptimizeKeepsNumbers.Proof

/-! # The optimizer's numbers, for the compile side's pre lemmas (F14)

`compile_optimized` compiles `optimizeProgram p`, which no post bounds; the
Mini compile's pre lemmas need its numbers (`nb`) and temporaries
(`funcsTemps`) below `2 ^ 62`. The proved leaf `OptimizeKeepsNumbers` gives
both from `p`'s. `Tactic.valueFacts` finds `val_optimizeProgram` by name. GenPC's
pre modules import this one (`pre_certs.py`, `COMPILE_PRE_IMPORTS`). -/

namespace Lanius.Faithful.SelfPre

open Lanius.Mini

theorem val_optimizeProgram (p : Program) :
    nb (optimizeProgram p) ≤ nb p ∧ funcsTemps (optimizeProgram p).funcs ≤ funcsTemps p.funcs :=
  Lanius.Open.OptimizeKeepsNumbers.proof p

end Lanius.Faithful.SelfPre
