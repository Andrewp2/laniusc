module

public import Lanius.Mini.Refs.Model

@[expose] public section

open Lanius.Mini
open Lanius.Core (Value ValueProjection)
open Lanius.Semantics (State)

/-- **A home's end, and its reuse in a loop.** Dropping the youngest home `x`
keeps the older homes, in any state that keeps their cells and the views:
their values name only older homes (the age order). Its block stays free for
a new home of the same type at the same address with a cell no other home
has, as a loop's next iteration binds it: such a home meets `HomesPush`'s
conditions on its block. -/
def Lanius.Open.HomesPopHome : Prop :=
  ∀ (sx : Statics) (bud : Budget) (x : Addressed) (places : List Addressed) (st st' : State) (hp : Heap),
    Homes sx bud (x :: places) st hp →
    (∀ y ∈ places, Semantics.readCellProjection st' y.cell [] = Semantics.readCellProjection st y.cell []) →
    st'.i32ArrayViews = st.i32ArrayViews →
    Homes sx bud places st' hp ∧
      ∀ x' : Addressed, x'.address = x.address → x'.ty = x.ty → (∀ y ∈ places, x'.cell ≠ y.cell) →
        hp.fsp ≤ x'.address ∧ hp.limit ≤ x'.address ∧ x'.address + 8 * x'.ty.words ≤ hp.top ∧
        x'.address + 8 * x'.ty.words < 2 ^ 62 ∧
        ∀ y ∈ places, x'.cell ≠ y.cell ∧
          (x'.address + 8 * x'.ty.words ≤ y.address ∨ y.address + 8 * y.ty.words ≤ x'.address)
