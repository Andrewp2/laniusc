import Lanius.Open.F14.OptimizeKeepsNumbers.Proof
import Lanius.Open.F14.CompileFuncSlotsV2.Stmt

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

/-- The compiled functions fit their frames (`codesSlack`, SelfPre/CompileSlots) and their
instructions' numbers are the functions' or at most `2 ^ 40` (`codesNb`), by the open leaf
CompileFuncSlotsV2, which `compile_program`'s pre lemma and its callers' assume
(`COMPILE_OVERRIDES`); `Tactic.valueFacts` passes it from the context. -/
theorem vals_compileFuncs (ar : List Arity) : ∀ (fs : List Func) (codes : List Code),
    compileFuncs ar fs = some codes → Lanius.Open.CompileFuncSlotsV2 →
      codesSlack codes = 0 ∧ codesNb codes ≤ max (nb fs) 1099511627776
  | [], codes, h, _ => by
    simp only [compileFuncs, Option.some.injEq] at h; subst h
    exact ⟨codesSlack_nil, Nat.zero_le _⟩
  | f :: rest, codes, h, hs => by
    rw [compileFuncs] at h
    split at h
    · simp at h
    · rename_i c hc
      split at h
      · simp at h
      · rename_i cs hcs
        simp only [Option.some.injEq] at h; subst h
        have ⟨h1, h2, h3, h4⟩ := hs ar f c hc
        have ⟨h5, h6⟩ := vals_compileFuncs ar rest cs hcs hs
        simp only [codesSlack_cons_eq_zero, codesNb, nb_cons, frameLimit] at *
        omega

end Lanius.Faithful.SelfPre
