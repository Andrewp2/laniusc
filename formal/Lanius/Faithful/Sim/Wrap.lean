module

public import Lanius.Faithful.Sim.Live
public import Lanius.Faithful.Sim.CheckFast

@[expose] public section

/-! # A program with some functions' bodies replaced by wrapping arithmetic

`wrapAt sp i op` is `sp` with function `i`'s body replaced by `return a op b`
of its first two parameters: for the prelude's `plus` and `times`, which
panic on overflow, the operator alone, which wraps. The function keeps its
signature, so the checks that read only the signatures (`callTy`,
`boxElem`), the termination annotations and the prims carry over. -/

namespace Lanius.Faithful.Termination

open Lanius.Mini
open Lanius.Faithful

/-- `f` with its body `return a op b` of its first two parameters. -/
def wrapFunc (op : SrcOp) (f : SrcFunc) : SrcFunc :=
  { f with
    body := match f.params with
      | p :: q :: _ => .return (.apply op (.local p.id) (.local q.id))
      | [] => .return (.int 0)
      | [_] => .return (.int 0) }

/-- `sp` with function `i` wrapped. -/
def wrapAt (sp : SrcProgram) (i : Nat) (op : SrcOp) : SrcProgram :=
  { funcs :=
      match sp.funcs[i]? with
      | some f => sp.funcs.set i (wrapFunc op f)
      | none => sp.funcs
    statics := sp.statics }

section
variable {sp : SrcProgram} {i : Nat} {op : SrcOp}

theorem wrapAt_get (j : Nat) :
    (wrapAt sp i op).funcs[j]? = if i = j then (sp.funcs[j]?).map (wrapFunc op) else sp.funcs[j]? := by
  unfold wrapAt
  cases h : sp.funcs[i]? with
  | none =>
    simp only
    split
    · rename_i e
      subst e
      rw [h]
      rfl
    · rfl
  | some f =>
    simp only
    have lt : i < sp.funcs.length := by
      rcases List.getElem?_eq_some_iff.mp h with ⟨lt, -⟩
      exact lt
    rw [List.getElem?_set]
    split
    · rename_i e
      subst e
      have hh := List.getElem?_eq_some_iff.mp h
      simp only [List.getElem?_eq_getElem lt, Option.map_some, hh.2]
    · rfl

theorem wrapAt_ne {j : Nat} (ne : i ≠ j) : (wrapAt sp i op).funcs[j]? = sp.funcs[j]? := by
  rw [wrapAt_get, if_neg ne]

theorem callTy_wrapAt (outside : List Nat) : callTy (wrapAt sp i op) outside = callTy sp outside := by
  funext c ts
  unfold callTy
  by_cases e : i = c
  · rw [wrapAt_get, if_pos e]
    cases sp.funcs[c]? <;> rfl
  · rw [wrapAt_ne e]

theorem boxElem_wrapAt (prims : Prims) : boxElem (wrapAt sp i op) prims = boxElem sp prims := by
  funext id
  unfold boxElem
  congr
  funext j
  by_cases e : i = j
  · rw [wrapAt_get, if_pos e]
    cases sp.funcs[j]? <;> rfl
  · rw [wrapAt_ne e]

theorem pureFunc_wrapAt (prims : Prims) (outside : List Nat) (g : SrcFunc) :
    PureFunc (wrapAt sp i op) prims outside g = PureFunc sp prims outside g := by
  unfold PureFunc
  rw [boxElem_wrapAt, ← stmtOkC_eq (sp := wrapAt sp i op), ← stmtOkC_eq (sp := sp), callTy_wrapAt]

theorem pureProg_wrapAt {prims : Prims} {outside : List Nat} (hp : PureProg sp prims outside)
    (hw : ∀ f, sp.funcs[i]? = some f → prims.isPrim i = false → outside.contains i = false →
      PureFunc sp prims outside (wrapFunc op f) = true) :
    PureProg (wrapAt sp i op) prims outside := by
  intro j g hg hpj houtj
  rw [pureFunc_wrapAt]
  rw [wrapAt_get] at hg
  split at hg
  · rename_i e
    subst e
    cases hf : sp.funcs[i]? with
    | none => rw [hf] at hg; cases hg
    | some f =>
      rw [hf] at hg
      cases hg
      exact hw f hf hpj houtj
  · exact hp j g hg hpj houtj

theorem primsTy_wrapAt {prims : Prims} (hP : PrimsTy sp prims) (hi : prims.isPrim i = false) :
    PrimsTy (wrapAt sp i op) prims := by
  intro c f hp hf vs hvs
  rw [boxElem_wrapAt] at hvs ⊢
  have hc : i ≠ c := by
    rintro rfl
    rw [hi] at hp
    cases hp
  rw [wrapAt_ne hc] at hf
  exact hP c f hp hf vs hvs

theorem chkFn_wrap (prims : Prims) (T : TermInfo) (a : TermAnn) (f : SrcFunc) :
    chkFn prims T a (wrapFunc op f) = true := by
  unfold chkFn wrapFunc
  cases f.params with
  | nil => rfl
  | cons p ps =>
    cases ps with
    | nil => rfl
    | cons q qs => rfl

theorem termOk_wrapAt {prims : Prims} {T : TermInfo} (hT : TermOk sp prims T) (hd : T.decs.contains i = false)
    (hc : (T.consts.map Prod.fst).contains i = false) : TermOk (wrapAt sp i op) prims T where
  decs := by
    intro c mem
    have ne : i ≠ c := by
      rintro rfl
      have : T.decs.contains i = true := List.elem_iff.mpr mem
      rw [hd] at this
      cases this
    obtain ⟨np, f, a, b, panic, hf, rest⟩ := hT.decs c mem
    exact ⟨np, f, a, b, panic, by rw [wrapAt_ne ne]; exact hf, rest⟩
  consts := by
    intro p mem
    have ne : i ≠ p.1 := by
      intro e
      have hm : i ∈ T.consts.map Prod.fst := e ▸ List.mem_map_of_mem mem
      have : (T.consts.map Prod.fst).contains i = true := List.elem_iff.mpr hm
      rw [hc] at this
      cases this
    obtain ⟨np, f, ty, hf, rest⟩ := hT.consts p mem
    exact ⟨np, f, ty, by rw [wrapAt_ne ne]; exact hf, rest⟩
  fns := by
    intro p mem
    refine (hT.fns p mem).imp_right fun h f hf => ?_
    rw [wrapAt_get] at hf
    split at hf
    · rename_i e
      subst e
      cases hg : sp.funcs[p.1]? with
      | none => rw [hg] at hf; cases hf
      | some g =>
        rw [hg] at hf
        cases hf
        exact chkFn_wrap prims T p.2 g
    · exact h f hf

end

end Lanius.Faithful.Termination

namespace Lanius.Faithful.Termination

open Lanius.Mini

theorem liveFn_wrap {bad : List Nat} {op : SrcOp} {f : SrcFunc} (h : isShiftOp op = false) :
    LiveFn bad (wrapFunc op f) = true := by
  unfold LiveFn wrapFunc
  cases f.params with
  | nil => simp [liveStmt, liveExpr, neverNext]
  | cons p ps =>
    cases ps with
    | nil => simp [liveStmt, liveExpr, neverNext]
    | cons q qs => simp [liveStmt, liveExpr, neverNext, h]

end Lanius.Faithful.Termination
