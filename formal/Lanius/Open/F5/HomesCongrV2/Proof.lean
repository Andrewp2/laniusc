import Lanius.Open.F5.HomesCongrV2.Stmt

open Lanius.Mini
open Lanius.Core (Value ValueProjection)
open Lanius.Semantics (State)

/-- Every byte `homeView` reads is at or above the home's address, so at or
above the frame pointer (`inside`), so the views agree on every slot
(`SrcType.HoldsAt.congr`); the cells' values are the same; the bounds use
only the limit, size and frame pointer; the static region is kept
(`Heap.StaticsAt.congr`). -/
theorem Lanius.Open.HomesCongrV2.proof : Lanius.Open.HomesCongrV2 := by
  intro sx bud places st st' hp hp' homes cells views limit size fsp base statics bytes
  have top : hp'.top = hp.top := by simp only [Heap.top, limit, size]
  refine
    { holds := fun i x hx => ?_
      roots := homes.roots
      sliced := homes.sliced
      layout := homes.layout
      inside := fun x hx => by rw [fsp, limit, top]; exact homes.inside x hx
      small := homes.small
      apart := homes.apart
      unviewed := by rw [views]; exact homes.unviewed
      room := fun pos => by rw [fsp, limit]; exact homes.room pos
      ceiling := fun pos => by rw [fsp, top]; exact homes.ceiling pos
      bounded := fun pos => by rw [top]; exact homes.bounded pos
      statics := homes.statics.congr base statics top }
  obtain ⟨v, hv, hold⟩ := homes.holds i x hx
  have mem : x ∈ places := List.mem_of_getElem? hx
  have above := (homes.inside x mem).1
  refine ⟨v, by rw [cells x mem]; exact hv, hold.congr fun s _ => ?_⟩
  simp only [SrcType.homeView, Nat.zero_add]
  rw [Heap.readLE_congr fun a lo _ => bytes a (by omega)]
