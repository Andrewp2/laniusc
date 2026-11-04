module

public import Lanius.Open.F5.RefStoreV2.Stmt
public import Lanius.Mini.Refs.Store
import all Lanius.Mini.Compiler.P.SrcType_same
import all Lanius.Mini.Compiler.P.UintTy_half
import all Lanius.Mini.Compiler.P.Word_narrows
import all Lanius.Mini.Compiler.P.arrayCallSig
import all Lanius.Mini.Compiler.P.callAgrees
import all Lanius.Mini.Compiler.P.loadAtBytes
import all Lanius.Mini.Compiler.P.render

@[expose] public section

open Lanius.Mini
open Lanius.Core (Value ValueProjection)

/-- The stores (`storesFrom_exec`, at `refSlotAt`) write each slot's low bytes
into ranges that lie apart (`refSlots_apart`) and inside the parent's slots
(`SlotsIn.ref`). The home's other slots keep their bytes (`slots_apart`), and
slot `j + s` of its new view is slot `s` of `v` cut to its width (a `u8` home
word keeps its zero upper bytes), so `HoldsAt.trunc` and `sub_replace` give
`root'`. The other homes' blocks lie apart. -/
theorem Lanius.Open.RefStoreV2.proof : Lanius.Open.RefStoreV2 := by
  intro sx bud places st st' hp i x path address ty v root root' prog depth env r slot homes hx hsub fitTags hr
    hv hread hrep hassign
  obtain ⟨root₀, hroot₀, hold⟩ := homes.holds i x hx
  rw [hread] at hroot₀
  cases hroot₀
  have mem : x ∈ places := List.mem_of_getElem? hx
  simp only [Addressed.sub] at hsub
  split at hsub
  · cases hsub
  rename_i off t hs
  simp only [Option.some.injEq, Prod.mk.injEq] at hsub
  obtain ⟨rfl, rfl⟩ := hsub
  have hok := homes.layout x mem
  have tok := SrcType.sub_homeOk path hok hs
  obtain ⟨j, old, hj, -, holdOld, slots, rebuild⟩ := SrcType.sub_replace path hs hold hrep
  simp only [Nat.zero_add] at hj holdOld rebuild
  have top := (homes.inside x mem).2.2
  have small := homes.small x mem
  have refIn := slots.ref
  -- each written range lies inside the parent's slot `j + s`, inside the block
  have fitsAt : ∀ s < t.size, x.address + off + (t.refSlotAt s).1 = x.address + (x.ty.slotAt (j + s)).1 ∧
      x.address + (x.ty.slotAt (j + s)).1 + (t.refSlotAt s).2.bytes ≤ x.address + 8 * x.ty.words := by
    intro s lt
    obtain ⟨a1, a2⟩ := refIn s lt
    have fits := SrcType.slot_fits x.ty (j + s) (by omega)
    omega
  obtain ⟨hp', run, others, outside, stored⟩ := t.storesFrom_exec (prog := prog) (depth := depth)
    (slot := slot) t.size 0 env hp hr
    (fun s _ hi => by have := fitsAt s (by omega); omega)
    (fun s s' _ hi _ hi' ne => SrcType.refSlots_apart tok s s' (by omega) (by omega) ne)
  obtain ⟨eTop, eFsp, eLimit, eBase, eStatics⟩ := Heap.top_of_others others
  have block : ∀ b, (b < x.address ∨ x.address + 8 * x.ty.words ≤ b) → hp'.bytes b = hp.bytes b :=
    fun b away => outside b fun s _ hi => by have := fitsAt s (by omega); omega
  -- the home's slots outside the sub-place keep their reading
  have keep : ∀ q, q < x.ty.size → (q < j ∨ j + t.size ≤ q) →
      x.ty.homeView x.address hp' q = x.ty.homeView x.address hp q := by
    intro q lt away
    simp only [SrcType.homeView]
    rw [Heap.readLE_congr fun b lo hi => outside b fun s _ hs => ?_]
    obtain ⟨a1, a2⟩ := refIn s (by omega)
    rcases SrcType.slots_apart x.ty hok q (j + s) lt (by omega) (by omega) with c | c <;> omega
  -- the sub-place's slots hold `v`'s slots cut to their widths
  have cut : ∀ s < t.size, x.ty.homeView x.address hp' (0 + j + s) =
      BitVec.ofNat 64 ((env (slot + s)).toNat % 256 ^ (t.slotAt s).2.bytes) := by
    intro s lt
    have st_ := stored s (Nat.zero_le _) (by omega)
    simp only [Nat.zero_add] at st_ ⊢
    cases hu : t.isUint .uint8 with
    | false =>
      rw [SrcType.refSlotAt_other hu] at st_
      rcases slots s lt with eq | ⟨rfl, -⟩
      · simp only [SrcType.homeView, eq, ← Nat.add_assoc, st_]
      · simp [SrcType.isUint, UintTy.code] at hu
    | true =>
      obtain rfl := SrcType.isUint_u8 hu
      have s0 : s = 0 := by simp only [SrcType.size] at lt; omega
      subst s0
      rw [SrcType.refSlotAt_u8] at st_
      simp only [Nat.add_zero, Access.bytes] at st_ ⊢
      have venv : (env slot).toNat < 256 := by
        cases hv with
        | uint h => simpa [UintTy.width] using h.2
      rw [SrcType.slotAt_u8]
      simp only [MemWidth.bytes_m32]
      rw [Nat.mod_eq_of_lt (Nat.lt_of_lt_of_le venv (by decide))]
      rw [Nat.mod_eq_of_lt venv] at st_
      rcases slots 0 lt with eq | ⟨-, eq⟩
      · rw [SrcType.slotAt_u8] at eq
        simp only [Nat.add_zero] at eq
        -- the old value is below 256, so the word's upper 3 bytes are zero
        have up : hp.readLE (x.address + off + 1) 3 = 0 := by
          cases holdOld with
          | uint h =>
            have h2 := h.2
            simp only [SrcType.homeView, eq, Access.bytes, MemWidth.bytes_m32, BitVec.toNat_ofNat,
              UintTy.width] at h2
            have lt64 : hp.readLE (x.address + off) 4 < 2 ^ 64 :=
              Nat.lt_of_lt_of_le (hp.readLE_lt (x.address + off) 4) (by decide)
            rw [Nat.mod_eq_of_lt lt64] at h2
            have split := hp.readLE_split (x.address + off) 1 3
            simp only [Nat.reduceAdd] at split
            omega
        have split := hp'.readLE_split (x.address + off) 1 3
        simp only [Nat.reduceAdd] at split
        have same : hp'.readLE (x.address + off + 1) 3 = hp.readLE (x.address + off + 1) 3 :=
          Heap.readLE_congr fun b lo hi => outside b fun s _ hs => by
            have : s = 0 := by simp only [SrcType.size] at hs; omega
            subst this
            simp only [SrcType.refSlotAt_u8, Access.bytes, Nat.add_zero]
            omega
        simp only [SrcType.homeView, eq, Access.bytes, MemWidth.bytes_m32]
        rw [split, same, up, st_]
        simp
      · simp only [Nat.add_zero] at eq
        simp only [SrcType.homeView, eq, Access.bytes, st_]
  have holdNew : t.HoldsAt sx (places.drop (i + 1)) v (x.ty.homeView x.address hp') (0 + j) :=
    SrcType.HoldsAt.trunc hv tok fitTags fun s lt => by rw [cut s lt]
  have holdRoot : x.ty.HoldsAt sx (places.drop (i + 1)) root' (x.ty.homeView x.address hp') 0 :=
    rebuild _ (by simpa only [Nat.zero_add] using holdNew) fun q _ lt away => keep q (by omega) away
  obtain ⟨readNew, readOther, views⟩ := assignCell_read hassign
  refine ⟨hp', run, ?_, others, fun b away => outside b fun s _ hs => ?_⟩
  · refine
      { holds := fun i' y hy => ?_
        roots := homes.roots
        sliced := homes.sliced
        layout := homes.layout
        inside := fun y my => by rw [eFsp, eLimit, eTop]; exact homes.inside y my
        small := homes.small
        apart := homes.apart
        unviewed := by rw [views]; exact homes.unviewed
        room := by rw [eLimit, eFsp]; exact homes.room
        ceiling := by rw [eFsp, eTop]; exact homes.ceiling
        bounded := by rw [eTop]; exact homes.bounded
        statics := homes.statics.congr eBase eStatics eTop }
    by_cases same : i' = i
    · subst same
      rw [hx] at hy
      cases hy
      exact ⟨root', readNew, holdRoot⟩
    · obtain ⟨cellNe, apartB⟩ := homes.apart i' i y x hy hx same
      obtain ⟨w, hw, holdy⟩ := homes.holds i' y hy
      refine ⟨w, by rw [readOther _ _ cellNe]; exact hw, holdy.congr fun s lt => ?_⟩
      simp only [SrcType.homeView, Nat.zero_add]
      have fits := SrcType.slot_fits y.ty s lt
      exact congrArg _ (Heap.readLE_congr fun b lo hi => block b (by omega))
  · have := fitsAt s (by omega)
    have inSpan := SrcType.refSlot_in_span t s (by omega)
    omega
