import Lanius.Mini.Refs.Homed
import Lanius.Mini.LowerStmt

open Lanius.Mini
open Lanius.Core (Value ValueProjection)
open Lanius.Semantics (State)

/-- **A plain `let`, its reference from `HoldsAt`.** `HomedCorrPushPlain`
with the reference hypothesis folded into the value's `HoldsAt`: a reference
value is held only at a reference type (`HoldsAt.ref`, `RefHeld`), so when the
context gives the local the slot `next` and, at a reference type, its
referent, the local's word represents the reference. -/
def Lanius.Open.HomedCorrPushHeld : Prop :=
  ∀ (sx : Statics) (places : List Addressed) (scope : List Binding) (frame : Nat → Nat) (c c' : RCtx)
    (st : State) (env env' : Env) (base next id : Nat) (ty : SrcType) (v : Value),
    HomedCorr sx places scope frame c st env → Layout scope frame base next → st.Fresh →
    ScopeAgree scope env env' → ty.HoldsAt sx places v env' next → (∀ y ∈ places, y.cell < st.nextCell) →
    viewedType ty = false → c'.frame = c.frame → env' c.frame = env c.frame → c'.homes.lookup id = none →
    (∀ id', id' ≠ id →
      c'.homes.lookup id' = c.homes.lookup id' ∧ c'.slotOf id' = c.slotOf id' ∧ c'.refTy id' = c.refTy id') →
    (∀ id', id' ≠ id → c.homes.lookup id' = none → env' (c.slotOf id') = env (c.slotOf id')) →
    c'.slotOf id = next → (∀ referent, ty = .ref referent → c'.refTy id = referent) →
    HomedCorr sx places (⟨id, next, ty⟩ :: scope) (upd frame next st.nextCell) c' (st.bindLocal id v) env'
