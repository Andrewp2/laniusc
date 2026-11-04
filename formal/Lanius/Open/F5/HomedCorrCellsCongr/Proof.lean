module

public import Lanius.Open.F5.HomedCorrCellsCongr.Stmt
public import Lanius.Mini.Refs.HomedLemmas

@[expose] public section

open Lanius.Mini

theorem Lanius.Open.HomedCorrCellsCongr.proof : Lanius.Open.HomedCorrCellsCongr := by
  intro sx places scope frame c st st' env hc locals kept hold views
  have viewVal : ∀ b ∈ scope, Unhomed places frame b → ∀ n, b.ty = .view n → ∃ vs,
      st'.cellEntry? (frame b.slot) = some ⟨frame b.slot, some (.array vs)⟩ ∧
        b.ty.HoldsAt sx places (.array vs) env b.slot := by
    intro b mem un n hty
    obtain ⟨w, wm, root, -, wlen, -⟩ := hc.viewed b mem un n hty
    obtain ⟨vs, blk, h⟩ := hold.1 w (views ▸ wm)
    exact ⟨vs, root ▸ h.cellEntry, by rw [hty]; exact .view (h.length.trans wlen) h.i32s⟩
  have cidEq : ∀ id, st'.cellId? id = st.cellId? id := fun id => by
    simp [Lanius.Semantics.State.cellId?, locals]
  refine
    { locals := locals.trans hc.locals
      values := fun b mem un => ?_
      unviewed := by rw [views]; exact hc.unviewed
      viewed := by rw [views]; exact hc.viewed
      refs := ⟨fun id offset ty hl => ?_, fun id T cell path hl hloc => ?_⟩
      homedTy := hc.homedTy
      unhomed := hc.unhomed }
  · cases nv : viewedType b.ty
    · rw [kept b mem un nv]
      exact hc.values b mem un
    · obtain ⟨n, hty⟩ := viewedType_true nv
      obtain ⟨vs, entry, holds⟩ := viewVal b mem un n hty
      exact ⟨_, entry, holds⟩
  · obtain ⟨x, mem, cell, hcell, rest⟩ := hc.refs.homes id offset ty hl
    exact ⟨x, mem, cell, by rw [cidEq]; exact hcell, rest⟩
  · apply hc.refs.refs id T cell path hl
    have cid := hc.cellId id
    unfold coreLocal at hloc ⊢
    rw [cidEq, cid] at hloc
    rw [cid]
    cases found : lookup scope id with
    | none => simp [found] at hloc
    | some b =>
      rw [found] at hloc
      simp only [Option.map_some] at hloc ⊢
      have un := hc.unhomed id b found hl
      have mem := (lookup_mem found).1
      cases nv : viewedType b.ty
      · rw [kept b mem un nv] at hloc
        exact hloc
      · obtain ⟨n, hty⟩ := viewedType_true nv
        obtain ⟨vs, entry, -⟩ := viewVal b mem un n hty
        simp [entry] at hloc
