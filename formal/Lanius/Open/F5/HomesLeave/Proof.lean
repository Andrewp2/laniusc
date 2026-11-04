module

public import Lanius.Open.F5.HomesLeave.Stmt
public import Lanius.Mini.Refs.CoreLemmas

@[expose] public section

open Lanius.Mini
open Lanius.Core (Value ValueProjection)
open Lanius.Semantics (State)

/-- The caller's homes are the suffix after the callee's own: home `i` is
home `own.length + i` before, and the homes older than it are the same, so
its hold carries over; the frame pointer `f` is below them and the call
rule's bounds hold at `f`. -/
theorem Lanius.Open.HomesLeave.proof : Lanius.Open.HomesLeave := by
  intro sx bud bud' own places st hp f homes above room ceiling bounded
  have idx : ∀ i, (own ++ places)[own.length + i]? = places[i]? := fun i => by
    rw [List.getElem?_append_right (by omega), Nat.add_sub_cancel_left]
  have mem : ∀ x ∈ places, x ∈ own ++ places := fun x hx => List.mem_append_right own hx
  refine
    { holds := fun i x hx => ?_
      roots := fun x hx => homes.roots x (mem x hx)
      sliced := fun x hx => homes.sliced x (mem x hx)
      layout := fun x hx => homes.layout x (mem x hx)
      inside := fun x hx => ⟨above x hx, (homes.inside x (mem x hx)).2⟩
      small := fun x hx => homes.small x (mem x hx)
      apart := fun i j x y hx hy ne =>
        homes.apart (own.length + i) (own.length + j) x y (by rw [idx]; exact hx) (by rw [idx]; exact hy)
          (by omega)
      unviewed := fun v hv x hx => homes.unviewed v hv x (mem x hx)
      room := room
      ceiling := ceiling
      bounded := bounded
      statics := CoreRefs.staticsAt_frame homes.statics rfl rfl rfl rfl }
  obtain ⟨v, hv, hold⟩ := homes.holds (own.length + i) x (by rw [idx]; exact hx)
  refine ⟨v, hv, ?_⟩
  have drop : (own ++ places).drop (own.length + i + 1) = places.drop (i + 1) := by
    rw [Nat.add_assoc, List.drop_append]
    simp
  rw [drop] at hold
  rw [CoreRefs.homeView_fsp]
  exact hold
