module

public import Lanius.Open.F5.HomedParamStore.Stmt
public import Lanius.Open.F5.HomedLetStore.Proof
public import Lanius.Mini.Refs.HomedLemmas
import all Lanius.Mini.Compiler.P.Inline_branchAgrees
import all Lanius.Mini.Compiler.P.Inline_deadAgrees
import all Lanius.Mini.Compiler.P.Inline_factOr
import all Lanius.Mini.Compiler.P.Inline_iteAgrees
import all Lanius.Mini.Compiler.P.Inline_kept
import all Lanius.Mini.Compiler.P.Inline_loopAgrees
import all Lanius.Mini.Compiler.P.Inline_optimizeSequence
import all Lanius.Mini.Compiler.P.Inline_seqAgrees
import all Lanius.Mini.Compiler.P.Inline_unknown
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
import all Lanius.Mini.Compiler.P.Expr_narrow
import all Lanius.Mini.Compiler.P.FArith_number
import all Lanius.Mini.Compiler.P.FCmp_number
import all Lanius.Mini.Compiler.P.FOp_number
import all Lanius.Mini.Compiler.P.Word_keeps
import all Lanius.Mini.Compiler.P.Word_narrows
import all Lanius.Mini.Compiler.P.Word_number
import all Lanius.Mini.Compiler.P.absorbed
import all Lanius.Mini.Compiler.P.foldConstant
import all Lanius.Mini.Compiler.P.negateConstant
import all Lanius.Mini.Compiler.P.SrcEff_isSlice
import all Lanius.Mini.Compiler.P.SrcEff_passesSlices
import all Lanius.Mini.Compiler.P.SrcEff_sliceCall
import all Lanius.Mini.Compiler.P.SrcStmt_breaksOut
import all Lanius.Mini.Compiler.P.SrcStmt_depth
import all Lanius.Mini.Compiler.P.SrcStmt_lower
import all Lanius.Mini.Compiler.P.arrayCall
import all Lanius.Mini.Compiler.P.arrayCallSig
import all Lanius.Mini.Compiler.P.effsSlice
import all Lanius.Mini.Compiler.P.paramScope
import all Lanius.Mini.Compiler.P.paramTypes
import all Lanius.Mini.Compiler.P.paramsSize
import all Lanius.Mini.Compiler.P.paramsValid
import all Lanius.Mini.Compiler.P.stmtEval
import all Lanius.Mini.Compiler.P.Expr_isAtom
import all Lanius.Mini.Compiler.P.Expr_mentions
import all Lanius.Mini.Compiler.P.Expr_subst
import all Lanius.Mini.Compiler.P.allocAgrees
import all Lanius.Mini.Compiler.P.callAgrees
import all Lanius.Mini.Compiler.P.divideAgrees
import all Lanius.Mini.Compiler.P.factValue
import all Lanius.Mini.Compiler.P.frameAgrees
import all Lanius.Mini.Compiler.P.loadByteAgrees
import all Lanius.Mini.Compiler.P.loadWordAgrees
import all Lanius.Mini.Compiler.P.retAgrees
import all Lanius.Mini.Compiler.P.staticAgrees
import all Lanius.Mini.Compiler.P.storeByteAgrees
import all Lanius.Mini.Compiler.P.storeWordAgrees
import all Lanius.Mini.Compiler.P.sysAgrees
import all Lanius.Mini.Compiler.P.lowerEnumValue
import all Lanius.Mini.Compiler.P.lowerTagged
import all Lanius.Mini.Compiler.P.viewedType
import all Lanius.Mini.Compiler.P.SrcType_same
import all Lanius.Mini.Compiler.P.SrcType_size
import all Lanius.Mini.Compiler.P.fieldOffset
import all Lanius.Mini.Compiler.P.norm
import all Lanius.Mini.Compiler.P.wrap
import all Lanius.Mini.Unique

@[expose] public section

open Lanius.Mini
open Lanius.Core (Value ValueProjection)
open Lanius.Semantics (State)

/-- The local's value is its cell's (`HomedCorr.values`, it is unhomed), so
`HomedLetStore.firstStore` with Core's state unchanged gives the homes. For
`HomedCorr`: a binding still unhomed was unhomed before (one place more); the
context's new home is the local's cell, which `locals` gives; every other id
keeps its context, its cell is not the new home's, and the slots it reads
are kept. -/
theorem Lanius.Open.HomedParamStore.proof : Lanius.Open.HomedParamStore := by
  intro sx bud places scope frame c st hp env id slot offset t ty home prog depth homes hc found unhomedId
    distinct hok fits hfsp blockPos fitsBlock apartx tScope tFrame tSlots
  obtain ⟨mem, -⟩ := lookup_mem found
  have un := hc.unhomed id _ found unhomedId
  obtain ⟨w, entry, hv⟩ := hc.values _ mem un
  have read : Semantics.readCellProjection st (frame slot) [] = .ok w := by
    simp [Semantics.readCellProjection, entry, Semantics.projectedValue]
  have notViewed : viewedType ty = false := by
    cases ty <;> simp_all [viewedType, SrcType.homeOk]
  obtain ⟨hp', run, pushed, others, block⟩ := Lanius.Open.HomedLetStore.firstStore (prog := prog) (depth := depth)
    (t := t) (st' := st) homes hv hok fits hfsp blockPos fitsBlock apartx (fun i lt => tScope _ mem i lt)
    (fun _ _ => rfl) rfl read (fun y my e => un y my e.symm)
    (fun v vm => hc.unviewed v vm _ mem un notViewed)
  let x : Addressed := ⟨frame slot, [], ty, hp.fsp + offset, true⟩
  have keepScope : ∀ b ∈ scope, ∀ i < b.ty.size, (env.set t (BitVec.ofNat 64 (hp.fsp + offset))) (b.slot + i) = env (b.slot + i) := fun b bm i lt => by
    simp only [Env.set]; exact if_neg (tScope b bm i lt)
  have unNew : ∀ b ∈ scope, Unhomed (x :: places) frame b → Unhomed places frame b :=
    fun b _ u y my => u y (List.mem_cons_of_mem _ my)
  refine ⟨hp', run, pushed, ?_, others, block⟩
  refine
    { locals := hc.locals
      values := fun b bm u => ?_
      unviewed := fun v vm b bm u nv => hc.unviewed v vm b bm (unNew b bm u) nv
      viewed := fun b bm u n hty => ?_
      refs := ⟨fun id' o ty' hl => ?_, fun id' T cell path hl hloc => ?_⟩
      homedTy := fun id' b o ty' hs hl => ?_
      unhomed := fun id' b hs hl => ?_ }
  · obtain ⟨v, e, h⟩ := hc.values b bm (unNew b bm u)
    exact ⟨v, e, (h.mono fun y m => List.mem_cons_of_mem _ m).congr (keepScope b bm)⟩
  · obtain ⟨v, vm, root, address, length, pos⟩ := hc.viewed b bm (unNew b bm u) n hty
    refine ⟨v, vm, root, ?_, length, pos⟩
    have := keepScope b bm 0 (by rw [hty]; exact pos)
    simp only [Nat.add_zero] at this
    rw [this]
    exact address
  · have fr' : (env.set t (BitVec.ofNat 64 (hp.fsp + offset))) c.frame = env c.frame := by simp only [Env.set]; exact if_neg tFrame
    by_cases eq : id' = id
    · subst eq
      rw [homes_lookup_self, Option.some.injEq, Prod.mk.injEq] at hl
      obtain ⟨rfl, rfl⟩ := hl
      refine ⟨x, List.mem_cons_self, frame slot, ?_, rfl, rfl, by dsimp only; rw [fr', hfsp]⟩
      rw [hc.cellId, found]
      rfl
    · rw [homes_lookup_ne _ eq] at hl
      obtain ⟨y, my, cell, hcell, yc, yt, ya⟩ := hc.refs.homes id' o ty' hl
      exact ⟨y, List.mem_cons_of_mem _ my, cell, hcell, yc, yt, by dsimp only; rw [fr']; exact ya⟩
  · by_cases eq : id' = id
    · subst eq
      simp at hl
    · rw [homes_lookup_ne _ eq] at hl
      have r := hc.refs.refs id' T cell path hl hloc
      have kept : (env.set t (BitVec.ofNat 64 (hp.fsp + offset))) (c.slotOf id') = env (c.slotOf id') := by
        simp only [Env.set]; exact if_neg (tSlots id' hl)
      dsimp only
      rw [kept]
      exact r.mono
  · by_cases eq : id' = id
    · subst eq
      rw [homes_lookup_self, Option.some.injEq, Prod.mk.injEq] at hl
      obtain ⟨-, rfl⟩ := hl
      rw [found] at hs
      cases hs
      rfl
    · rw [homes_lookup_ne _ eq] at hl
      exact hc.homedTy id' b o ty' hs hl
  · by_cases eq : id' = id
    · subst eq
      simp at hl
    · rw [homes_lookup_ne _ eq] at hl
      obtain ⟨bm, bid⟩ := lookup_mem hs
      have old := hc.unhomed id' b hs hl
      intro y my
      rcases List.mem_cons.mp my with rfl | my
      · exact fun e => distinct b bm (by rw [bid]; exact eq) e.symm
      · exact old y my
