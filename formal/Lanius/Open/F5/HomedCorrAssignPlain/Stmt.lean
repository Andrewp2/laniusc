import Lanius.Mini.Refs.Homed
import Lanius.Mini.LowerStmt

open Lanius.Mini
open Lanius.Core (Value ValueProjection)
open Lanius.Semantics (State)

/-- **Assigning a local without a home** (`Corr.assign`'s analogue). Core
replaces the binding's cell's value by `rv`, which its slots in `env'` hold;
the other slots are kept, and so are the frame slot and the unhomed
reference locals' slots. The binding is not of a reference type (a
reference parameter is not reassigned, SEMANTIC_DECISIONS "References: the
memory model" point 9) and not a viewed array. -/
def Lanius.Open.HomedCorrAssignPlain : Prop :=
  ∀ (sx : Statics) (places : List Addressed) (scope : List Binding) (frame : Nat → Nat) (c : RCtx)
    (st : State) (env env' : Env) (base next : Nat) (b : Binding) (rv : Value),
    HomedCorr sx places scope frame c st env → Layout scope frame base next → b ∈ scope →
    Unhomed places frame b → (∀ j, j < b.slot ∨ b.slot + b.ty.size ≤ j → env' j = env j) →
    b.ty.HoldsAt sx places rv env' b.slot → viewedType b.ty = false → (∀ r, b.ty ≠ .ref r) →
    env' c.frame = env c.frame → (∀ id, c.homes.lookup id = none → env' (c.slotOf id) = env (c.slotOf id)) →
    HomedCorr sx places scope frame c { st with cells := Semantics.replaceCell st.cells (frame b.slot) rv } env'
