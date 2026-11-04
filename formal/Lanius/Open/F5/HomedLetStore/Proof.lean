import Lanius.Open.F5.HomedLetStore.Stmt
import Lanius.Open.F5.HomesPush.Proof
import Lanius.Open.F5.HomedCorrPushV2.Proof
import Lanius.Mini.Refs.HomedLemmas

open Lanius.Mini
open Lanius.Core (Value ValueProjection)
open Lanius.Semantics (State)

/-- The stores (`storesFrom_exec` of `homeInit`, whose `refSlotAt` is the
home's `slotAt`) write each slot's native word, cut to its width, into the
home's block; so the home's view holds `v` (`HoldsAt.trunc`). The other
homes' blocks lie apart and keep their bytes; then `HomesPush` and
`HomedCorrPushV2`. -/
theorem Lanius.Open.HomedLetStore.proof : Lanius.Open.HomedLetStore := by
  intro sx bud places scope frame c st hp env base next id offset t ty v prog depth homes hc fr fresh under
    hv hok fits hfsp blockPos fitsBlock apartx tAbove tFrame tSlots
  have pos : 0 < bud.room + bud.block := by omega
  have room := homes.room pos
  have ceiling := homes.ceiling pos
  have bounded := homes.bounded pos
  have wfit : ∀ s < ty.size, (ty.slotAt s).1 + (ty.slotAt s).2.bytes ≤ 8 * ty.words :=
    fun s lt => SrcType.slot_fits ty s lt
  have eframe : env c.frame = BitVec.ofNat 64 hp.fsp :=
    BitVec.eq_of_toNat_eq (by rw [hfsp, BitVec.toNat_ofNat, Nat.mod_eq_of_lt (by omega)])
  have run1 : Exec prog depth env hp (.assign t (addOff c.frame offset))
      (.normal (env.set t (BitVec.ofNat 64 (hp.fsp + offset))) hp) := by
    have := Exec.assign (prog := prog) (depth := depth) (env := env) (heap := hp) (index := t)
      (value := addOff c.frame offset)
    rwa [addOff_eval_ofNat offset eframe] at this
  have at_ : ((env.set t (BitVec.ofNat 64 (hp.fsp + offset))) t).toNat = hp.fsp + offset := by
    simp only [Env.set, if_pos rfl, BitVec.toNat_ofNat]
    exact Nat.mod_eq_of_lt (by omega)
  have hsize := ty.homeInit_size
  obtain ⟨hp', run2, others, outside, stored⟩ := ty.homeInit.storesFrom_exec (prog := prog) (depth := depth)
    (slot := next) ty.homeInit.size 0 _ hp at_
    (fun s _ hi => by
      rw [SrcType.homeInit_refSlotAt]
      have := wfit s (by omega)
      omega)
    (fun s s' _ hi _ hi' ne => by
      rw [SrcType.homeInit_refSlotAt, SrcType.homeInit_refSlotAt]
      exact SrcType.slots_apart ty hok s s' (by omega) (by omega) ne)
  obtain ⟨eTop, eFsp, eLimit, eBase, eStatics⟩ := Heap.top_of_others others
  have block : ∀ b, (b < hp.fsp + offset ∨ hp.fsp + offset + 8 * ty.words ≤ b) → hp'.bytes b = hp.bytes b :=
    fun b away => outside b fun s _ hi => by
      rw [SrcType.homeInit_refSlotAt]
      have := wfit s (by omega)
      omega
  -- the home's view holds `v`
  have cut : ∀ s < ty.size, ty.homeView (hp.fsp + offset) hp' (0 + s) =
      BitVec.ofNat 64 ((env (next + s)).toNat % 256 ^ (ty.slotAt s).2.bytes) := by
    intro s lt
    have st_ := stored s (Nat.zero_le _) (by omega)
    rw [SrcType.homeInit_refSlotAt] at st_
    have keep : (env.set t (BitVec.ofNat 64 (hp.fsp + offset))) (next + s) = env (next + s) := by
      simp only [Env.set]
      exact if_neg (by omega)
    rw [keep] at st_
    simp only [SrcType.homeView, Nat.zero_add, st_]
  have hold : ty.HoldsAt sx places v (ty.homeView (hp.fsp + offset) hp') 0 :=
    SrcType.HoldsAt.trunc hv hok fits fun s lt => cut s lt
  -- the older homes keep their bytes
  have homes' : Homes sx bud places st hp' :=
    { holds := fun i y hy => by
        obtain ⟨w, hw, holdy⟩ := homes.holds i y hy
        refine ⟨w, hw, holdy.congr fun s lt => ?_⟩
        simp only [SrcType.homeView, Nat.zero_add]
        have fitsy := SrcType.slot_fits y.ty s lt
        have away := apartx y (List.mem_of_getElem? hy)
        exact congrArg _ (Heap.readLE_congr fun b lo hi => block b (by omega))
      roots := homes.roots
      sliced := homes.sliced
      layout := homes.layout
      inside := fun y my => by rw [eFsp, eLimit, eTop]; exact homes.inside y my
      small := homes.small
      apart := homes.apart
      unviewed := homes.unviewed
      room := by rw [eLimit, eFsp]; exact homes.room
      ceiling := by rw [eFsp, eTop]; exact homes.ceiling
      bounded := by rw [eTop]; exact homes.bounded
      statics := homes.statics.congr eBase eStatics eTop }
  have cells : ∀ y ∈ places, Semantics.readCellProjection (st.bindLocal id v) y.cell [] =
      Semantics.readCellProjection st y.cell [] := fun y my => by
    simp only [Semantics.readCellProjection, bindLocal_entry (under y my) id v]
  have read : Semantics.readCellProjection (st.bindLocal id v) st.nextCell [] = .ok v := by
    simp [Semantics.readCellProjection, bindLocal_self fresh id v, Semantics.projectedValue]
  have pushed := Lanius.Open.HomesPush.proof sx bud places st (st.bindLocal id v) hp'
    ⟨st.nextCell, [], ty, hp.fsp + offset, true⟩ v homes' cells rfl read hold rfl rfl hok
    (by simp only; omega) (by simp only; omega) (by simp only; omega) (by simp only; omega)
    (fun y my => ⟨fun e => by have := under y my; simp only at e; omega, apartx y my⟩)
    (fun w wm e => by
      obtain ⟨vs, b, h⟩ := fresh.2.1 w wm
      exact Nat.ne_of_lt (fresh.below (Views.ViewHolds.cellEntry h)) e)
  have corr := Lanius.Open.HomedCorrPushV2.proof sx places scope frame c st env
    (env.set t (BitVec.ofNat 64 (hp.fsp + offset))) base next id offset ty (some offset) v
    ⟨st.nextCell, [], ty, hp.fsp + offset, true⟩ hc fr fresh
    (fr.agree fun j lt => by simp only [Env.set]; exact if_neg (by omega)) under
    (by simp only [Env.set]; exact if_neg tFrame)
    (fun id' none_ => by simp only [Env.set]; exact if_neg (tSlots id' none_)) rfl rfl
    (by simp only; rw [hfsp])
  exact ⟨hp', .seq run1 run2, pushed, corr, others, block⟩
