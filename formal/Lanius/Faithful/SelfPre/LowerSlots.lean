import Lanius.Open.F14.LowerSlotsSmall.Stmt
import Lanius.Mini.FrameRoom

/-! # The lowered functions' slots and numbers, for the compile side's pre lemmas (F14)

The open leaf `LowerSlotsSmall` bounds a statement's lowering. Here it is taken
to `lowerFunc`'s body (its frame and its unit tail added: `lowered_body`, which
`lower_func`'s pre lemma states up front, `COMPILE_FACTS`, so that `lower_body`
can take the body's `Stmt.extent`) and to `lowerFuncs` (`val_lowerFuncs`, which
`Tactic.valueFacts` finds by name, so that `compile_declared` can hand the
lowered functions to `compile_lowered`, whose numbers are below `2 ^ 62`). -/

namespace Lanius.Faithful.SelfPre

open Lanius.Mini

/-- The parameters' bindings carry the parameters' numbers and slots from `slot`. -/
theorem nb_paramScope : ∀ (ps : List SrcParam) (slot : Nat) (scope : List Binding),
    nb (paramScope ps slot scope) ≤ max (max (nb ps) (nb scope)) (slot + paramsSize ps)
  | [], slot, scope => by simp only [paramScope, nb_nil, paramsSize]; omega
  | p :: ps, slot, scope => by
    have ih := nb_paramScope ps (slot + SrcType.size p.ty)
      ({ id := p.id, slot := slot, ty := p.ty, home := none } :: scope)
    have hp : nb p = max (nb p.id) (nb p.ty) := rfl
    simp only [paramScope, nb_cons, nb_Binding_mk, nb_none, paramsSize, hp] at ih ⊢
    have : nb slot = slot := rfl
    omega

/-- The open leaf at `lowerFunc`'s body: the parameters' scope from slot `0`, the
statement from the slot past them. -/
theorem lowered_core (sigs : List Sig) (own : Sig) (decls : SrcDecls) (func : SrcFunc)
    (hO : Lanius.Open.LowerSlotsSmall) (h1 : ts sigs ≤ 4194304) (h2 : sigsParams sigs ≤ 1099511627776)
    (h3 : tsd decls ≤ 4194304) (h4 : ts func ≤ 4194304) (h5 : paramsSize func.params ≤ 1099511627776)
    (h6 : SrcStmt.depth func.body ≤ 36028797018963968)
    (h7 : SrcStmt.slotNest func.body ≤ 36028797018963968) :
    optExtent (SrcStmt.lower func.body (withBudget sigs (own.need - frameBlock func) (frameBlock func)) decls
        func.ret (paramScope func.params 0 []) (paramsSize func.params)) ≤ 2 ^ 60 ∧
      nb (SrcStmt.lower func.body (withBudget sigs (own.need - frameBlock func) (frameBlock func)) decls
        func.ret (paramScope func.params 0 []) (paramsSize func.params)) ≤ max (nb func) (2 ^ 60) := by
  have hb := val_withBudget sigs (own.need - frameBlock func) (frameBlock func)
  have hs := val_paramScope func.params 0 []
  have ht := slots_paramScope func.params 0 []
  have hn := nb_paramScope func.params 0 []
  have hr := ts_le_SrcFunc_ret func
  have hy := ts_le_SrcFunc_body func
  have hq := ts_le_SrcFunc_params func
  have hnb : nb func = max (nb func.params) (max (nb func.ret) (nb func.body)) := rfl
  simp only [ts_nil, scopeTop, nb_nil] at hs ht hn
  have := hO func.body (withBudget sigs (own.need - frameBlock func) (frameBlock func)) decls func.ret
    (paramScope func.params 0 []) (paramsSize func.params) (by omega) (by omega) h3 (by omega) (by omega)
    (by omega) (by omega) (by omega) (by omega)
  omega

/-- `lowerFunc`'s body, its frame and unit tail added, names slots below `2 ^ 61`
(the bound `lower_body`'s pre lemma takes). -/
theorem lowered_body (sigs : List Sig) (own : Sig) (decls : SrcDecls) (func : SrcFunc)
    (hO : Lanius.Open.LowerSlotsSmall) (h1 : ts sigs ≤ 4194304) (h2 : sigsParams sigs ≤ 1099511627776)
    (h3 : tsd decls ≤ 4194304) (h4 : ts func ≤ 4194304) (h5 : paramsSize func.params ≤ 1099511627776)
    (h6 : SrcStmt.depth func.body ≤ 36028797018963968)
    (h7 : SrcStmt.slotNest func.body ≤ 36028797018963968) :
    optExtent (unitTail func.ret (withFrame (paramsSize func.params) (frameBlock func)
      (SrcStmt.lower func.body (withBudget sigs (own.need - frameBlock func) (frameBlock func)) decls
        func.ret (paramScope func.params 0 []) (paramsSize func.params)))) ≤ 2305843009213693952 ∧
    nb (unitTail func.ret (withFrame (paramsSize func.params) (frameBlock func)
      (SrcStmt.lower func.body (withBudget sigs (own.need - frameBlock func) (frameBlock func)) decls
        func.ret (paramScope func.params 0 []) (paramsSize func.params)))) ≤
      max (nb func) 2305843009213693952 := by
  have ⟨he, hn⟩ := lowered_core sigs own decls func hO h1 h2 h3 h4 h5 h6 h7
  have hf := frameBlock_le func
  generalize SrcStmt.lower func.body _ decls func.ret _ _ = body at he hn ⊢
  have hp : nb (paramsSize func.params) = paramsSize func.params := rfl
  have hk : nb (frameBlock func) = frameBlock func := rfl
  cases body with
  | none =>
    by_cases hu : SrcType.isUnit func.ret = true <;> by_cases hz : frameBlock func = 0 <;>
      simp only [unitTail, withFrame, hu, hz, Bool.not_eq_true, if_true, if_false, optExtent_none,
        nb_none, Bool.false_eq_true] <;> omega
  | some b =>
    simp only [optExtent_some, nb_some] at he hn
    by_cases hu : SrcType.isUnit func.ret = true <;> by_cases hz : frameBlock func = 0 <;>
      simp only [unitTail, withFrame, hu, hz, Bool.not_eq_true, if_true, if_false, optExtent_some,
        nb_some, Bool.false_eq_true, Stmt.extent, nb_Stmt_seq, nb_Stmt_frame, nb_Stmt_ret, nb_cons,
        nb_nil, nb_Expr_lit, argsExtent, Expr.extent] <;> omega

/-- `lowerFunc`'s function: its counts and locals below `2 ^ 61`, its body's numbers by `lowered_body`. -/
theorem nb_lowerFunc (sigs : List Sig) (own : Sig) (decls : SrcDecls) (func : SrcFunc)
    (hO : Lanius.Open.LowerSlotsSmall) (h1 : ts sigs ≤ 4194304) (h2 : sigsParams sigs ≤ 1099511627776)
    (h3 : tsd decls ≤ 4194304) (h4 : ts func ≤ 4194304) (h5 : paramsSize func.params ≤ 1099511627776)
    (h6 : SrcStmt.depth func.body ≤ 36028797018963968)
    (h7 : SrcStmt.slotNest func.body ≤ 36028797018963968) :
    nb (lowerFunc sigs own decls func) ≤ max (nb func) 2305843009213693952 := by
  have ⟨he, hn⟩ := lowered_body sigs own decls func hO h1 h2 h3 h4 h5 h6 h7
  have hr := Nat.le_trans (size_le_tySlots func.ret) (Nat.le_trans (ts_le_SrcFunc_ret func) h4)
  unfold lowerFunc
  simp only
  generalize unitTail func.ret _ = body at he hn ⊢
  split
  · unfold lowerBody
    split
    · simp only [nb_none]; omega
    · rename_i b
      simp only [optExtent_some, nb_some, nb_Func_mk] at he hn ⊢
      have : ∀ k : Nat, nb k = k := fun _ => rfl
      simp only [this]
      omega
  · simp only [nb_none]; omega

/-- The lowered functions' numbers: the functions' or below `2 ^ 61` (the open leaf
first, then the premises the compile side's pre lemmas carry: `Tactic.valueFacts`
passes the leaf and hands `omega` the rest as an implication). -/
theorem val_lowerFuncs (sigs : List Sig) : ∀ (own : List Sig) (decls : SrcDecls) (funcs : List SrcFunc),
    Lanius.Open.LowerSlotsSmall → ts sigs ≤ 4194304 → sigsParams sigs ≤ 1099511627776 →
      tsd decls ≤ 4194304 → ts funcs ≤ 4194304 → paramsMax funcs ≤ 1099511627776 →
      depthMax funcs ≤ 36028797018963968 → nestMax funcs ≤ 36028797018963968 →
      nb (lowerFuncs sigs own decls funcs) ≤ max (nb funcs) 2305843009213693952
  | own, decls, [], hO, h1, h2, h3, h4, h5, h6, h7 => by
    unfold lowerFuncs; simp only [nb_some, nb_nil]; omega
  | own, decls, f :: fs, hO, h1, h2, h3, h4, h5, h6, h7 => by
    simp only [ts_cons, paramsMax, depthMax, nestMax, nb_cons] at h4 h5 h6 h7 ⊢
    unfold lowerFuncs
    match own with
    | [] => simp only [nb_none]; omega
    | s :: others =>
      simp only
      have hf := nb_lowerFunc sigs s decls f hO h1 h2 h3 (by omega) (by omega) (by omega) (by omega)
      have hr := val_lowerFuncs sigs others decls fs hO h1 h2 h3 (by omega) (by omega) (by omega) (by omega)
      generalize lowerFunc sigs s decls f = a at hf ⊢
      generalize lowerFuncs sigs others decls fs = r at hr ⊢
      unfold lowerFuncCons
      match a, r with
      | none, none => simp only [nb_none]; omega
      | none, some xs => simp only [nb_none]; omega
      | some x, none => simp only [nb_none]; omega
      | some x, some xs => simp only [nb_some, nb_cons] at hf hr ⊢; omega

end Lanius.Faithful.SelfPre
