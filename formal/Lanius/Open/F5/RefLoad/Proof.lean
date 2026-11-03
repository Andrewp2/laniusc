import Lanius.Open.F5.RefLoad.Stmt
import Lanius.Mini.Refs.Lemmas

open Lanius.Mini
open Lanius.Core (Value ValueProjection)

/-- Home `i` holds its value in its view (`Homes.holds`); down the path the
sub-place's value is held in the same view, at slots whose bytes and widths
are the referent's (`SrcType.sub_holds`), one byte for a `u8` whose native
word has zero upper bytes. So the loads (`loadsFrom_exec`) give the view's
words, inside the home's block. -/
theorem Lanius.Open.RefLoad.proof : Lanius.Open.RefLoad := by
  intro sx bud places st hp i x path address ty v prog depth env r target homes hx hsub hread hr apart
  obtain ⟨root, hroot, hold⟩ := homes.holds i x hx
  have mem : x ∈ places := List.mem_of_getElem? hx
  have hv : Semantics.projectedValue root path = .ok v := by rw [← readCell_path hroot]; exact hread
  simp only [Addressed.sub] at hsub
  split at hsub
  · cases hsub
  rename_i off t hs
  simp only [Option.some.injEq, Prod.mk.injEq] at hsub
  obtain ⟨rfl, rfl⟩ := hsub
  obtain ⟨j, hj, hholds, slots⟩ := SrcType.sub_holds path hs hold hv
  have top := (homes.inside x mem).2.2
  have small := homes.small x mem
  have agree : ∀ s < t.size,
      x.address + off + (t.refSlotAt s).1 = x.address + (x.ty.slotAt (j + s)).1 ∧
      (t.refSlotAt s).2.bytes ≤ (x.ty.slotAt (j + s)).2.bytes ∧
      BitVec.ofNat 64 (hp.readLE (x.address + off + (t.refSlotAt s).1) (t.refSlotAt s).2.bytes) =
        x.ty.homeView x.address hp (0 + j + s) := by
    intro s lt
    cases hu : t.isUint .uint8 with
    | false =>
      rw [SrcType.refSlotAt_other hu]
      rcases slots s lt with eq | ⟨rfl, -⟩
      · refine ⟨by rw [eq]; omega, by simp [eq], ?_⟩
        simp only [SrcType.homeView, Nat.zero_add, eq, Nat.add_assoc]
      · simp [SrcType.isUint, UintTy.code] at hu
    | true =>
      obtain rfl := SrcType.isUint_u8 hu
      rw [SrcType.refSlotAt_u8]
      have s0 : s = 0 := by simp only [SrcType.size] at lt; omega
      subst s0
      simp only [Nat.add_zero, Nat.zero_add, SrcType.homeView]
      rcases slots 0 lt with eq | ⟨-, eq⟩
      · rw [SrcType.slotAt_u8] at eq
        simp only [Nat.add_zero] at eq
        have bound := hholds
        cases bound with
        | uint h =>
          have h2 := h.2
          simp only [SrcType.homeView, Nat.zero_add, eq, Access.bytes, MemWidth.bytes,
            BitVec.toNat_ofNat] at h2
          have lt64 : hp.readLE (x.address + off) 4 < 2 ^ 64 :=
            Nat.lt_of_lt_of_le (hp.readLE_lt (x.address + off) 4) (by decide)
          rw [Nat.mod_eq_of_lt lt64] at h2
          have narrow := hp.readLE_narrow (a := x.address + off) (w := 1) (m := 4) (by omega)
            (by simpa [UintTy.width] using h2)
          rw [eq]
          refine ⟨by omega, by simp [Access.bytes, MemWidth.bytes_m32], ?_⟩
          simp only [Access.bytes] at narrow ⊢
          rw [narrow]
          rfl
      · simp only [Nat.add_zero] at eq
        rw [eq]
        exact ⟨by omega, Nat.le_refl _, rfl⟩
  obtain ⟨env', run, loaded, same⟩ := t.loadsFrom_exec (prog := prog) (depth := depth) (target := target)
    (hp := hp) t.size 0 env hr (fun k _ hk => by omega) (fun k _ hk => by
      obtain ⟨a1, a2, -⟩ := agree k (by omega)
      have fits := SrcType.slot_fits x.ty (j + k) (by omega)
      omega)
  refine ⟨env', run, hholds.congr fun s lt => ?_, fun q away => same q fun k _ hk => by omega⟩
  rw [loaded s (by omega) (by omega)]
  exact (agree s lt).2.2
