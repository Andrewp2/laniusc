module

public import Lanius.Open.F5.CallRefsAgree.Stmt
public import Lanius.Mini.Refs.HomedLemmas

@[expose] public section

open Lanius.Mini

/-- A callee's local is one of the bound values (`coreLocal_bindLocals`; there
are no locals before), so a reference local's word is its argument's. -/
theorem Lanius.Open.CallRefsAgree.proof : Lanius.Open.CallRefsAgree := by
  intro places st bindings c args cells hc hyp
  refine ⟨fun id offset ty hl => by simp [hc] at hl, fun id T cell path _ hloc => ?_⟩
  rcases coreLocal_bindLocals bindings { st with locals := [] } cells (by simp) id _ hloc with ⟨v, mem, hv⟩ | h
  · exact hyp id v mem T cell path hv.symm
  · simp [coreLocal, Semantics.State.cellId?] at h
