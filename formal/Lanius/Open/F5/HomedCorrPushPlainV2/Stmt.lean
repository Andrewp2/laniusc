module

public import Lanius.Mini.Refs.Homed
public import Lanius.Mini.LowerStmt

@[expose] public section

open Lanius.Mini
open Lanius.Core (Value ValueProjection)
open Lanius.Semantics (State)

/-- **A plain `let`.** A `let` whose local has no home binds it in Core to the
next cell (`bindLocal`) and holds its value in its slots from `next`, past
the scope's slots, as in `Corr.push`. `HomedCorr` then holds for the longer
scope with the places unchanged, in a context `c'` that gives the local no
home (shadowing any outer home of the name) and is `c` for every other name,
when the code kept the scope's slots, the frame slot, and the slots of the
other reference locals without homes. A reference value is represented by its
word (`RefTo`, for stage 1's reference locals).

Replaces `HomedCorrPushPlain`, which stopped elaborating when `Binding` gained `home`
(F5 S6a-2): the `let`'s binding has any home (`OPEN_STATEMENTS.md`, "Deleting a
statement"). -/
def Lanius.Open.HomedCorrPushPlainV2 : Prop :=
  ∀ (sx : Statics) (places : List Addressed) (scope : List Binding) (frame : Nat → Nat) (c c' : RCtx)
    (st : State) (env env' : Env) (base next id : Nat) (ty : SrcType) (home : Option Nat) (v : Value),
    HomedCorr sx places scope frame c st env → Layout scope frame base next → st.Fresh →
    ScopeAgree scope env env' → ty.HoldsAt sx places v env' next → (∀ y ∈ places, y.cell < st.nextCell) →
    viewedType ty = false → c'.frame = c.frame → env' c.frame = env c.frame → c'.homes.lookup id = none →
    (∀ id', id' ≠ id →
      c'.homes.lookup id' = c.homes.lookup id' ∧ c'.slotOf id' = c.slotOf id' ∧ c'.refTy id' = c.refTy id') →
    (∀ id', id' ≠ id → c.homes.lookup id' = none → env' (c.slotOf id') = env (c.slotOf id')) →
    (∀ T cell path, v = .reference T cell path → RefTo places (c'.refTy id) cell path (env' (c'.slotOf id))) →
    HomedCorr sx places (⟨id, next, ty, home⟩ :: scope) (upd frame next st.nextCell) c' (st.bindLocal id v) env'
