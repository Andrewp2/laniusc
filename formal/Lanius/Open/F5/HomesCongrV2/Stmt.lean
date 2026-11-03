import Lanius.Mini.Refs.Model

open Lanius.Mini
open Lanius.Core (Value ValueProjection)
open Lanius.Semantics (State)

/-- **Other changes keep the homes.** A step that keeps the places' cells and
Core's views, the heap's limit, size, frame pointer and static region, and
every byte of frame memory at or above the frame pointer keeps the homes: a
bump allocation, a store below the frame pointer, or a Core write to another
cell. Replaces `HomesCongr`, which left out the static region (`Homes.statics`
needs it; HomesCongr/NOTES.md has the counterexample). -/
def Lanius.Open.HomesCongrV2 : Prop :=
  ∀ (sx : Statics) (bud : Budget) (places : List Addressed) (st st' : State) (hp hp' : Heap),
    Homes sx bud places st hp →
    (∀ y ∈ places, Semantics.readCellProjection st' y.cell [] = Semantics.readCellProjection st y.cell []) →
    st'.i32ArrayViews = st.i32ArrayViews →
    hp'.limit = hp.limit → hp'.frameSize = hp.frameSize → hp'.fsp = hp.fsp →
    hp'.staticBase = hp.staticBase → hp'.statics = hp.statics →
    (∀ b, hp.fsp ≤ b → hp'.bytes b = hp.bytes b) →
    Homes sx bud places st' hp'
