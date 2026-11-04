module

public import Lanius.Open.F5.FrameCorrHomes.Stmt
public import Lanius.Mini.Borrowed
import all Lanius.Mini.Compiler.P.Lists_empty
import all Lanius.Mini.Compiler.P.SrcType_same
import all Lanius.Mini.Compiler.P.loadAtBytes

@[expose] public section

open Lanius.Mini
open Lanius.Core (Value ValueProjection)
open Lanius.Semantics (State)

namespace Lanius.Open.FrameCorrHomes

/-- A packed array takes no more words than slots. -/
theorem words_le {x : Addressed} (packed : x.Packed) : x.ty.words ≤ x.ty.size := by
  obtain ⟨-, -, element, n, ty, el⟩ := packed
  rw [ty]
  rcases el with rfl | rfl <;>
    simp only [SrcType.words, SrcType.size, SrcType.accessKind, Access.narrow, Access.bytes,
      MemWidth.bytes, if_true] <;> omega

/-- A packed array's home view is its slice-layout view. -/
theorem homeView_view {x : Addressed} (packed : x.Packed) (hp : Heap) (s : Nat) :
    x.ty.homeView x.address hp s = x.view hp s := by
  obtain ⟨sl, -, element, n, ty, el⟩ := packed
  simp only [SrcType.homeView, Addressed.view, Addressed.slotBytes, sl, if_true]
  rcases el with rfl | rfl <;> rw [ty] <;>
    simp [SrcType.slotAt, SrcType.accessKind, Access.narrow, Access.bytes, MemWidth.bytes]

end Lanius.Open.FrameCorrHomes

/-- `FrameCorr`'s places are packed `i32` and `u8` arrays: their holds do not
depend on the places (`Addressed.Packed.holdsAt`), their home view is their
view (`homeView_view`), their words are at most their slots (`words_le`), so
`FrameCorr`'s bounds give `Homes`'s, and `Nodup` turns distinct indices into
distinct members for `apart`. -/
theorem Lanius.Open.FrameCorrHomes.proof : Lanius.Open.FrameCorrHomes := by
  intro sx bud places st hp fc nodup
  refine
    { holds := fun i x hx => ?_
      roots := fun x hx => (fc.packed x hx).2.1
      sliced := fun x hx => (fc.packed x hx).1
      layout := fun x hx => ?_
      inside := fun x hx => ?_
      small := fun x hx => ?_
      apart := fun i j x y hx hy ne => ?_
      unviewed := fc.unviewed
      room := fc.room
      ceiling := fc.ceiling
      bounded := fc.bounded
      statics := fc.statics }
  · have mem : x ∈ places := List.mem_of_getElem? hx
    have packed := fc.packed x mem
    obtain ⟨v, hv, hold⟩ := fc.holds x mem
    rw [packed.2.1] at hv
    refine ⟨v, hv, (packed.holdsAt hold).congr fun s _ => ?_⟩
    simp only [Nat.zero_add]
    exact FrameCorrHomes.homeView_view packed hp s
  · obtain ⟨-, -, element, n, ty, el⟩ := fc.packed x hx
    rw [ty]
    rcases el with rfl | rfl <;> simp [SrcType.homeOk]
  · have := fc.inside x hx
    have := FrameCorrHomes.words_le (fc.packed x hx)
    exact ⟨by omega, by omega, by omega⟩
  · have := fc.small x hx
    have := FrameCorrHomes.words_le (fc.packed x hx)
    omega
  · have xm : x ∈ places := List.mem_of_getElem? hx
    have ym : y ∈ places := List.mem_of_getElem? hy
    have xy : x ≠ y := by
      rintro rfl
      have lt : i < places.length := by
        rcases Nat.lt_or_ge i places.length with h | h
        · exact h
        · rw [List.getElem?_eq_none h] at hx; cases hx
      exact ne ((List.getElem?_inj lt nodup).1 (by rw [hx, hy]))
    obtain ⟨c, d⟩ := fc.apart x xm y ym xy
    have := FrameCorrHomes.words_le (fc.packed x xm)
    have := FrameCorrHomes.words_le (fc.packed y ym)
    exact ⟨c, by omega⟩
