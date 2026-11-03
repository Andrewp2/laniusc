import Lanius.Mini.Refs.Model

open Lanius.Mini
open Lanius.Core (Value ValueProjection)
open Lanius.Semantics (State)

/-- **A call's references, from the arguments' `HoldsAt`.** `CallRefsAgree`
with its hypothesis on reference arguments given by each argument's
`HoldsAt` at its parameter's slot: a reference argument is held at a
reference type (`HoldsAt.ref`), whose referent the callee's context gives the
parameter. -/
def Lanius.Open.CallRefsHeld : Prop :=
  ∀ (sx : Statics) (places : List Addressed) (st : State) (bindings : List (Lanius.VarId × Value)) (c : RCtx)
    (args : List (BitVec 64)),
    (∀ e ∈ st.cells, e.id < st.nextCell) → c.homes = [] →
    (∀ id v, (id, v) ∈ bindings → ∃ ty : SrcType, ty.HoldsAt sx places v (Func.entry args) (c.slotOf id) ∧
      ∀ referent, ty = .ref referent → c.refTy id = referent) →
    RefsAgree c places (({ st with locals := [] } : State).bindLocals bindings) (Func.entry args)
