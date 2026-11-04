module

public import Lanius.Mini.Refs.Homed
public import Lanius.Mini.LowerStmt

@[expose] public section

open Lanius.Mini
open Lanius.Core (Value ValueProjection)
open Lanius.Semantics (State)

/-- **Leaving a homed `let`'s block.** At the end of the block of a `let` whose
local had the home `x` (`HomedCorrPush`), Core restores the outer locals and
keeps the cells. `HomedCorr` then holds for the outer scope, the places
without `x` and the outer context, when no outer local's value names `x`'s
cell (`Value.Names`: the lifetime rule's dynamic side, which its static check
gives). Facts about the outer context that the inner one hides come from
`HomedCorr` before the `let` (`st₀`, `env₀`): the locals are the same, the
frame slot is kept, and an outer reference local the `let` shadowed is as it
was. -/
def Lanius.Open.HomedCorrPopHome : Prop :=
  ∀ (sx : Statics) (places : List Addressed) (scope : List Binding) (frame : Nat → Nat) (c : RCtx)
    (st₀ st st' : State) (env₀ env : Env) (base next id offset : Nat) (ty : SrcType) (x : Addressed),
    HomedCorr sx places scope frame c st₀ env₀ →
    HomedCorr sx (x :: places) (⟨id, next, ty⟩ :: scope) (upd frame next x.cell)
      { c with homes := (id, offset, ty) :: c.homes } st env →
    Layout scope frame base next → (∀ b ∈ scope, frame b.slot ≠ x.cell) →
    st'.locals = st₀.locals → st'.cells = st.cells → st'.i32ArrayViews = st.i32ArrayViews →
    env c.frame = env₀ c.frame →
    (∀ b ∈ scope, ∀ w, st.cellEntry? (frame b.slot) = some ⟨frame b.slot, some w⟩ → ¬ w.Names x.cell) →
    (c.homes.lookup id = none → coreLocal st' id = coreLocal st₀ id ∧ env (c.slotOf id) = env₀ (c.slotOf id)) →
    HomedCorr sx places scope frame c st' env
