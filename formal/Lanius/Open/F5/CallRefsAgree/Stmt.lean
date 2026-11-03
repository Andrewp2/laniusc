import Lanius.Mini.Refs.Model

open Lanius.Mini
open Lanius.Core (Value ValueProjection)
open Lanius.Semantics (State)

/-- **A call's references.** At a callee's entry, before any of its locals has
a home (`c.homes = []`), Core's locals are the parameters bound to the
arguments' values from no locals (`bindLocals`, as Core's call does) and the
mini slots are the argument words (`Func.entry`). When each argument that is
a reference is represented by the word at its parameter's slot (`RefTo`, as
`BorrowRefHeld` gives the caller), the callee's context agrees
(`RefsAgree`): its reference parameters name the caller's homes. Cells are
below the next cell, as in a fresh state. -/
def Lanius.Open.CallRefsAgree : Prop :=
  ∀ (places : List Addressed) (st : State) (bindings : List (Lanius.VarId × Value)) (c : RCtx)
    (args : List (BitVec 64)),
    (∀ e ∈ st.cells, e.id < st.nextCell) → c.homes = [] →
    (∀ id v, (id, v) ∈ bindings → ∀ T cell path, v = .reference T cell path →
      RefTo places (c.refTy id) cell path (Func.entry args (c.slotOf id))) →
    RefsAgree c places (({ st with locals := [] } : State).bindLocals bindings) (Func.entry args)
