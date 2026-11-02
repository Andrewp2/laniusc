import Lanius.Faithful.Sim.Wrap
import Lanius.Faithful.Sim.Mono
import Lanius.Faithful.Sim.QMono

/-! # A wrapped program's guarded runs are the program's runs

`wrapAt` replaces a function's body by wrapping arithmetic (`Sim/Wrap.lean`).
Where the arithmetic does not wrap, the wrapped body gives what the original
body gives. `pcallG sp' prims safe` is `pcall` of the wrapped program `sp'`
with no value for a call that `safe` rules out (for the prelude's `plus` and
`times`: one whose result passes `2 ^ 64`). When every function of `sp'`
gives, where `safe` holds, only values its counterpart in `sp` gives
(`Agrees`), a guarded run of `sp'` is a run of `sp` with the same fuel and
value (`pcall_of_pcallG`). `Agrees` holds for a function left as it was
(`agrees_refl`), carries over a `wrapAt` whose body agrees where `safe` holds
(`agrees_wrapAt`), and composes (`agrees_trans`).

The same for the heap cost (`Cost.lean`): `qcallG` is `qcall` with the guard,
its values are `pcallG`'s (`pcallG_eq_qcallG`), and under `QAgrees` a
guarded run of `sp'` has the value and cost of a run of `sp`
(`qcall_of_qcallG`), so where `pcallG` has a value, `sp` and `sp'` have the
same value and cost (`qcall_both`). -/

namespace Lanius.Faithful.Termination

open Lanius.Mini
open Lanius.Faithful
open Lanius.Core (Value)

open Classical in
/-- `pcall` of `sp`, where a call that `safe` rules out has no value. -/
noncomputable def pcallG (sp : SrcProgram) (prims : Prims) (safe : Nat → List Value → Prop) : Nat → Calls
  | 0, _, _ => none
  | fuel + 1, callee, values =>
    if safe callee values then
      if prims.isPrim callee then single values
      else
        match sp.funcs[callee]? with
        | none => none
        | some f =>
          if values.length = f.params.length then
            (pstmt (pcallG sp prims safe fuel) (paramEnv f.params values) f.body).bind (doneValue f.ret)
          else none
    else none

/-- Each function of `sp'` has one in `sp` with its parameters whose body,
where `safe` holds of the arguments, gives every value the body of `sp'`
gives, with calls that give at least as much. -/
def Agrees (sp sp' : SrcProgram) (safe : Nat → List Value → Prop) : Prop :=
  ∀ c f', sp'.funcs[c]? = some f' → ∃ f, sp.funcs[c]? = some f ∧ f.params = f'.params ∧
    ∀ vs, safe c vs → ∀ (call call' : Calls) (v : Value), CallsLe call call' →
      (pstmt call (paramEnv f'.params vs) f'.body).bind (doneValue f'.ret) = some v →
      (pstmt call' (paramEnv f.params vs) f.body).bind (doneValue f.ret) = some v

section
variable {sp sp' sp'' : SrcProgram} {prims : Prims} {safe : Nat → List Value → Prop}

/-- **A guarded run of the wrapped program is a run of the program.** -/
theorem pcall_of_pcallG (h : Agrees sp sp' safe) :
    ∀ (n : Nat) {c : Nat} {vs : List Value} {v : Value}, pcallG sp' prims safe n c vs = some v →
      pcall sp prims n c vs = some v
  | 0, _, _, _, hv => by simp [pcallG] at hv
  | n + 1, c, vs, v, hv => by
    simp only [pcallG] at hv
    simp only [pcall]
    split at hv
    · rename_i hs
      split at hv
      · rename_i prim
        rw [if_pos prim]
        exact hv
      · rename_i prim
        rw [if_neg prim]
        split at hv
        · simp at hv
        · rename_i f' hf'
          obtain ⟨f, hf, hp, hb⟩ := h c f' hf'
          rw [hf]
          simp only
          split at hv
          · rename_i len
            rw [if_pos (hp ▸ len)]
            exact hb vs hs _ _ v (fun _ _ _ hc => pcall_of_pcallG h n hc) hv
          · simp at hv
    · simp at hv

/-- A program agrees with itself. -/
theorem agrees_refl : Agrees sp sp safe := by
  intro c f hf
  refine ⟨f, hf, rfl, fun vs _ call call' v le hv => ?_⟩
  exact bind_mono (fun _ hx => pstmt_mono le _ hx) (fun _ _ hx => hx) hv

theorem agrees_trans (h₁ : Agrees sp sp' safe) (h₂ : Agrees sp' sp'' safe) : Agrees sp sp'' safe := by
  intro c f'' hf''
  obtain ⟨f', hf', hp', hb'⟩ := h₂ c f'' hf''
  obtain ⟨f, hf, hp, hb⟩ := h₁ c f' hf'
  refine ⟨f, hf, hp.trans hp', fun vs hs call call' v le hv => ?_⟩
  exact hb vs hs call' call' v (fun _ _ _ hc => hc) (hb' vs hs call call' v le hv)

/-- Wrapping function `i` keeps the agreement where its wrapped body agrees
with its own. -/
theorem agrees_wrapAt {i : Nat} {op : SrcOp}
    (hw : ∀ f, sp.funcs[i]? = some f → ∀ vs, safe i vs → ∀ (call call' : Calls) (v : Value),
      CallsLe call call' →
      (pstmt call (paramEnv f.params vs) (wrapFunc op f).body).bind (doneValue f.ret) = some v →
      (pstmt call' (paramEnv f.params vs) f.body).bind (doneValue f.ret) = some v) :
    Agrees sp (wrapAt sp i op) safe := by
  intro c f' hf'
  rw [wrapAt_get] at hf'
  split at hf'
  · rename_i e
    subst e
    cases hf : sp.funcs[i]? with
    | none => rw [hf] at hf'; cases hf'
    | some f =>
      rw [hf] at hf'
      cases hf'
      exact ⟨f, rfl, rfl, fun vs hs call call' v le hv => hw f hf vs hs call call' v le hv⟩
  · exact agrees_refl c f' hf'

end

/-! ## Costs -/

open Classical in
/-- `qcall` of `sp`, where a call that `safe` rules out has no value. -/
noncomputable def qcallG (sp : SrcProgram) (prims : Prims) (cost : Nat → Nat) (safe : Nat → List Value → Prop) :
    Nat → QCalls
  | 0, _, _ => none
  | fuel + 1, callee, values =>
    if safe callee values then
      if prims.isPrim callee then
        (single values).map (·, if prims.boxed.contains callee then cost callee else 0)
      else
        match sp.funcs[callee]? with
        | none => none
        | some f =>
          if values.length = f.params.length then
            qthen (qstmt (qcallG sp prims cost safe fuel) (paramEnv f.params values) f.body) fun d =>
              qfree (doneValue f.ret d)
          else none
    else none

/-- `QAgrees`: `Agrees` with costs. -/
def QAgrees (sp sp' : SrcProgram) (safe : Nat → List Value → Prop) : Prop :=
  ∀ c f', sp'.funcs[c]? = some f' → ∃ f, sp.funcs[c]? = some f ∧ f.params = f'.params ∧
    ∀ vs, safe c vs → ∀ (call call' : QCalls) (p : Value × Nat), QCallsLe call call' →
      qthen (qstmt call (paramEnv f'.params vs) f'.body) (fun d => qfree (doneValue f'.ret d)) = some p →
      qthen (qstmt call' (paramEnv f.params vs) f.body) (fun d => qfree (doneValue f.ret d)) = some p

section
variable {sp sp' sp'' : SrcProgram} {prims : Prims} {cost : Nat → Nat} {safe : Nat → List Value → Prop}

/-- `qcallG`'s values are `pcallG`'s. -/
theorem pcallG_eq_qcallG (sp : SrcProgram) (prims : Prims) (cost : Nat → Nat) (safe : Nat → List Value → Prop) :
    ∀ (fuel c : Nat) (vs : List Value),
      pcallG sp prims safe fuel c vs = (qcallG sp prims cost safe fuel c vs).map Prod.fst
  | 0, _, _ => rfl
  | fuel + 1, c, vs => by
    rw [pcallG, qcallG]
    split
    · split
      · cases single vs <;> rfl
      · cases sp.funcs[c]? with
        | none => rfl
        | some f =>
          simp only
          split
          · exact fst_qthen (pstmt_eq (pcallG_eq_qcallG sp prims cost safe fuel) f.body _) fun d => fst_qfree _
          · rfl
    · rfl

/-- **A guarded run of the wrapped program has a run of the program's value
and cost.** -/
theorem qcall_of_qcallG (h : QAgrees sp sp' safe) :
    ∀ (n : Nat) {c : Nat} {vs : List Value} {p : Value × Nat}, qcallG sp' prims cost safe n c vs = some p →
      qcall sp prims cost n c vs = some p
  | 0, _, _, _, hv => by simp [qcallG] at hv
  | n + 1, c, vs, p, hv => by
    simp only [qcallG] at hv
    simp only [qcall]
    split at hv
    · rename_i hs
      split at hv
      · rename_i prim
        rw [if_pos prim]
        exact hv
      · rename_i prim
        rw [if_neg prim]
        split at hv
        · simp at hv
        · rename_i f' hf'
          obtain ⟨f, hf, hp, hb⟩ := h c f' hf'
          rw [hf]
          simp only
          split at hv
          · rename_i len
            rw [if_pos (hp ▸ len)]
            exact hb vs hs _ _ p (fun _ _ _ hc => qcall_of_qcallG h n hc) hv
          · simp at hv
    · simp at hv

theorem qagrees_refl : QAgrees sp sp safe := by
  intro c f hf
  refine ⟨f, hf, rfl, fun vs _ call call' p le hv => ?_⟩
  exact qthen_mono (fun _ hx => qstmt_mono le _ hx) (fun _ _ hx => hx) hv

theorem qagrees_trans (h₁ : QAgrees sp sp' safe) (h₂ : QAgrees sp' sp'' safe) : QAgrees sp sp'' safe := by
  intro c f'' hf''
  obtain ⟨f', hf', hp', hb'⟩ := h₂ c f'' hf''
  obtain ⟨f, hf, hp, hb⟩ := h₁ c f' hf'
  refine ⟨f, hf, hp.trans hp', fun vs hs call call' p le hv => ?_⟩
  exact hb vs hs call' call' p (fun _ _ _ hc => hc) (hb' vs hs call call' p le hv)

theorem qagrees_wrapAt {i : Nat} {op : SrcOp}
    (hw : ∀ f, sp.funcs[i]? = some f → ∀ vs, safe i vs → ∀ (call call' : QCalls) (p : Value × Nat),
      QCallsLe call call' →
      qthen (qstmt call (paramEnv f.params vs) (wrapFunc op f).body) (fun d => qfree (doneValue f.ret d)) = some p →
      qthen (qstmt call' (paramEnv f.params vs) f.body) (fun d => qfree (doneValue f.ret d)) = some p) :
    QAgrees sp (wrapAt sp i op) safe := by
  intro c f' hf'
  rw [wrapAt_get] at hf'
  split at hf'
  · rename_i e
    subst e
    cases hf : sp.funcs[i]? with
    | none => rw [hf] at hf'; cases hf'
    | some f =>
      rw [hf] at hf'
      cases hf'
      exact ⟨f, rfl, rfl, fun vs hs call call' p le hv => hw f hf vs hs call call' p le hv⟩
  · exact qagrees_refl c f' hf'

/-- **Where the guarded run has a value, the program and the wrapped one have
it, at the same cost.** -/
theorem qcall_both (h : QAgrees sp sp' safe) {n c : Nat} {vs : List Value} {v : Value}
    (hv : pcallG sp' prims safe n c vs = some v) :
    ∃ k, qcall sp prims cost n c vs = some (v, k) ∧ qcall sp' prims cost n c vs = some (v, k) := by
  rw [pcallG_eq_qcallG sp' prims cost safe] at hv
  cases hq : qcallG sp' prims cost safe n c vs with
  | none => rw [hq] at hv; cases hv
  | some p =>
    rw [hq] at hv
    simp only [Option.map_some, Option.some.injEq] at hv
    subst hv
    exact ⟨p.2, qcall_of_qcallG h n hq, qcall_of_qcallG qagrees_refl n hq⟩

end

end Lanius.Faithful.Termination
