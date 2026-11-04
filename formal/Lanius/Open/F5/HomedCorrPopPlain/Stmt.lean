module

public import Lanius.Mini.Refs.Homed
public import Lanius.Mini.LowerStmt

@[expose] public section

open Lanius.Mini
open Lanius.Core (Value ValueProjection)
open Lanius.Semantics (State)

/-- **Leaving a plain `let`'s block.** At the end of the block of a `let` whose
local had no home (`HomedCorrPushPlain`, context `c'`), Core restores the
outer locals and keeps the cells. `HomedCorr` then holds for the outer scope
and context `c`. As in `HomedCorrPopHome`, facts about the outer context
that the inner one hides come from `HomedCorr` before the `let` (`st₀`,
`env₀`): the locals are the same, the frame slot is kept, and an outer
reference local the `let` shadowed is as it was. -/
def Lanius.Open.HomedCorrPopPlain : Prop :=
  ∀ (sx : Statics) (places : List Addressed) (scope : List Binding) (frame : Nat → Nat) (c c' : RCtx)
    (st₀ st st' : State) (env₀ env : Env) (base next id cell : Nat) (ty : SrcType),
    HomedCorr sx places scope frame c st₀ env₀ →
    HomedCorr sx places (⟨id, next, ty⟩ :: scope) (upd frame next cell) c' st env →
    Layout scope frame base next →
    (∀ id', id' ≠ id →
      c'.homes.lookup id' = c.homes.lookup id' ∧ c'.slotOf id' = c.slotOf id' ∧ c'.refTy id' = c.refTy id') →
    st'.locals = st₀.locals → st'.cells = st.cells → st'.i32ArrayViews = st.i32ArrayViews →
    env c.frame = env₀ c.frame →
    (c.homes.lookup id = none → coreLocal st' id = coreLocal st₀ id ∧ env (c.slotOf id) = env₀ (c.slotOf id)) →
    HomedCorr sx places scope frame c st' env
