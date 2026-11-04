import Lanius.Open.F5.HomedCorrAssignPlain.Stmt
import Lanius.Mini.Refs.HomedLemmas

open Lanius.Mini
open Lanius.Core (Value)
open Lanius.Semantics (State)

set_option linter.unusedSimpArgs false

namespace Lanius.Open.HomedCorrAssignPlain

/-- Only a reference type holds a reference. -/
theorem holds_reference {sx : Statics} {places : List Addressed} {ty : SrcType} {v : Value} {env : Env}
    {slot : Nat} (h : ty.HoldsAt sx places v env slot) {T : Lanius.Core.Ty} {cell : Lanius.CellId}
    {path : List Lanius.Core.ValueProjection} (eq : v = .reference T cell path) : ∃ r, ty = .ref r := by
  subst eq
  cases h with
  | ref _ => exact ⟨_, rfl⟩
  | i32 h => simp [SrcType.Holds] at h
  | bool h => simp [SrcType.Holds] at h
  | uint h => simp [SrcType.Holds] at h
  | ptr h => simp [SrcType.Holds] at h
  | isize h => simp [SrcType.Holds] at h
  | char h => simp [SrcType.Holds] at h
  | float h =>
    rename_i t
    cases t <;> simp [SrcType.Holds, FloatTy.value] at h
  | sint h =>
    rename_i kind
    cases kind <;> simp [SrcType.Holds, UintTy.SintHolds, NarrowHolds] at h

end Lanius.Open.HomedCorrAssignPlain

theorem Lanius.Open.HomedCorrAssignPlain.proof : Lanius.Open.HomedCorrAssignPlain := by
  intro sx places scope frame c st env env' base next b rv hc fr bmem bun outside holds nv notRef hframe hslots
  have cidEq : ∀ id, ({ st with cells := Semantics.replaceCell st.cells (frame b.slot) rv } : State).cellId? id =
      st.cellId? id := fun _ => rfl
  refine
    { locals := hc.locals
      values := fun a mem un => ?_
      unviewed := hc.unviewed
      viewed := fun a mem un n hty => ?_
      refs := ⟨fun id offset ty hl => ?_, fun id T cell path hl hloc => ?_⟩
      homedTy := hc.homedTy
      unhomed := hc.unhomed }
  · rw [assigned_entry]
    by_cases same : frame a.slot = frame b.slot
    · have := fr.inj a mem b bmem same
      subst this
      obtain ⟨v0, entry, _⟩ := hc.values a mem un
      rw [if_pos rfl, entry]
      exact ⟨rv, rfl, holds⟩
    · rw [if_neg same]
      obtain ⟨v1, entry, holds1⟩ := hc.values a mem un
      have ne : a ≠ b := fun eq => same (by rw [eq])
      refine ⟨v1, entry, holds1.congr fun i below => outside _ ?_⟩
      rcases fr.apart a mem b bmem ne with left | right
      · omega
      · omega
  · obtain ⟨w, wm, root, address, length, pos⟩ := hc.viewed a mem un n hty
    refine ⟨w, wm, root, ?_, length, pos⟩
    have ne : a ≠ b := fun eq => by subst eq; rw [hty] at nv; simp [viewedType] at nv
    rw [outside a.slot ?_]
    · exact address
    rcases fr.apart a mem b bmem ne with left | right
    · exact .inl (by have := fr.sized a mem; omega)
    · exact .inr right
  · obtain ⟨x, xm, cell, hcell, xcell, xty, xaddr⟩ := hc.refs.homes id offset ty hl
    exact ⟨x, xm, cell, by rw [cidEq]; exact hcell, xcell, xty, by rw [hframe]; exact xaddr⟩
  · rw [hslots id hl]
    apply hc.refs.refs id T cell path hl
    have cid := hc.cellId id
    unfold coreLocal at hloc ⊢
    rw [cidEq, cid] at hloc
    rw [cid]
    cases found : lookup scope id with
    | none => simp [found] at hloc
    | some a =>
      rw [found] at hloc
      simp only [Option.map_some] at hloc ⊢
      rw [assigned_entry] at hloc
      by_cases same : frame a.slot = frame b.slot
      · have := fr.inj a (lookup_mem found).1 b bmem same
        subst this
        obtain ⟨v0, entry, _⟩ := hc.values a (lookup_mem found).1 bun
        rw [if_pos rfl, entry] at hloc
        simp only [Option.map_some] at hloc
        obtain ⟨r, hr⟩ := Lanius.Open.HomedCorrAssignPlain.holds_reference holds (Option.some.inj hloc)
        exact absurd hr (notRef r)
      · rw [if_neg same] at hloc
        exact hloc
