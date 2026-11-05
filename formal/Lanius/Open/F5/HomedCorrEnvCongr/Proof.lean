module

public import Lanius.Open.F5.HomedCorrEnvCongr.Stmt
import all Lanius.Mini.Compiler.P.BinOp_size
import all Lanius.Mini.Compiler.P.Lists_concat
import all Lanius.Mini.Compiler.P.Lists_cons
import all Lanius.Mini.Compiler.P.Lists_empty
import all Lanius.Mini.Compiler.P.Lists_get
import all Lanius.Mini.Compiler.P.Lists_getOr
import all Lanius.Mini.Compiler.P.Lists_length
import all Lanius.Mini.Compiler.P.Lists_single
import all Lanius.Mini.Compiler.P.MemWidth_bytes
import all Lanius.Mini.Compiler.P.MemWidth_prefix
import all Lanius.Mini.Compiler.P.MemWidth_rex
import all Lanius.Mini.Compiler.P.Word_prefix
import all Lanius.Mini.Compiler.P.SrcType_same
import all Lanius.Mini.Compiler.P.SrcType_size
import all Lanius.Mini.Compiler.P.fieldOffset
import all Lanius.Mini.Compiler.P.norm
import all Lanius.Mini.Compiler.P.wrap

@[expose] public section

open Lanius.Mini

theorem Lanius.Open.HomedCorrEnvCongr.proof : Lanius.Open.HomedCorrEnvCongr := by
  intro sx places scope frame c st env env' hc agree hframe hslots
  exact
    { locals := hc.locals
      values := fun b mem un => by
        obtain ⟨v, entry, holds⟩ := hc.values b mem un
        exact ⟨v, entry, holds.congr (agree b mem)⟩
      unviewed := hc.unviewed
      viewed := fun b mem un n hty => by
        obtain ⟨w, wm, root, address, length, pos⟩ := hc.viewed b mem un n hty
        refine ⟨w, wm, root, ?_, length, pos⟩
        have sized : 0 < b.ty.size := by rw [hty]; exact pos
        have := agree b mem 0 sized
        simp only [Nat.add_zero] at this
        rw [this]
        exact address
      refs := ⟨fun id offset ty hl => by
          obtain ⟨x, xm, cell, hcell, xcell, xty, xaddr⟩ := hc.refs.homes id offset ty hl
          exact ⟨x, xm, cell, hcell, xcell, xty, by rw [hframe]; exact xaddr⟩,
        fun id T cell path hl hloc => by
          rw [hslots id hl]
          exact hc.refs.refs id T cell path hl hloc⟩
      homedTy := hc.homedTy
      unhomed := hc.unhomed }
