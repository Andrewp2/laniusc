module

public import Lanius.Mini.Refs.Model

@[expose] public section

open Lanius.Mini
open Lanius.Core (Value ValueProjection)
open Lanius.Semantics (State)

/-- **A new home.** A local that gets a home in frame memory, whose bytes hold
its cell's value (naming only the older homes), apart from the other places
and their cells, joins the homes as the youngest, when Core's step that
bound it kept the other places' cells and the views. -/
def Lanius.Open.HomesPush : Prop :=
  ∀ (sx : Statics) (bud : Budget) (places : List Addressed) (st st' : State) (hp : Heap) (x : Addressed)
    (v : Value),
    Homes sx bud places st hp →
    (∀ y ∈ places, Semantics.readCellProjection st' y.cell [] = Semantics.readCellProjection st y.cell []) →
    st'.i32ArrayViews = st.i32ArrayViews →
    Semantics.readCellProjection st' x.cell [] = .ok v →
    x.ty.HoldsAt sx places v (x.ty.homeView x.address hp) 0 →
    x.projections = [] → x.sliced = true → x.ty.homeOk = true →
    hp.fsp ≤ x.address → hp.limit ≤ x.address → x.address + 8 * x.ty.words ≤ hp.top →
    x.address + 8 * x.ty.words < 2 ^ 62 →
    (∀ y ∈ places, x.cell ≠ y.cell ∧
      (x.address + 8 * x.ty.words ≤ y.address ∨ y.address + 8 * y.ty.words ≤ x.address)) →
    (∀ w ∈ st.i32ArrayViews, w.root ≠ x.cell) →
    Homes sx bud (x :: places) st' hp
