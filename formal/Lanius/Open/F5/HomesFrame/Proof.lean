module

public import Lanius.Open.F5.HomesFrame.Stmt
public import Lanius.Mini.Refs.CoreLemmas

@[expose] public section

open Lanius.Mini
open Lanius.Core (Value ValueProjection)
open Lanius.Semantics (State)

/-- `homeView` reads bytes, not the frame pointer, so the holds carry over;
the homes stay above the lowered frame pointer; the callee's room and block
fit in the caller's room, which lies below the caller's frame pointer. -/
theorem Lanius.Open.HomesFrame.proof : Lanius.Open.HomesFrame := by
  intro sx bud bud' places st hp homes fit
  refine
    { holds := fun i x hx => by
        rw [CoreRefs.homeView_fsp]
        exact homes.holds i x hx
      roots := homes.roots
      sliced := homes.sliced
      layout := homes.layout
      inside := fun x hx => ?_
      small := homes.small
      apart := homes.apart
      unviewed := homes.unviewed
      room := fun pos => ?_
      ceiling := fun pos => ?_
      bounded := fun pos => ?_
      statics := CoreRefs.staticsAt_frame homes.statics rfl rfl rfl rfl }
  · have := homes.inside x hx
    exact ⟨by simp only; omega, this.2.1, this.2.2⟩
  · have := homes.room (by omega)
    simp only; omega
  · have := homes.room (by omega)
    have := homes.ceiling (by omega)
    simp only [Heap.top] at this ⊢; omega
  · exact homes.bounded (by omega)
