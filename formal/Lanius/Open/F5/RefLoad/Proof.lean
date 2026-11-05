module

public import Lanius.Open.F5.RefLoad.Stmt
public import Lanius.Mini.Refs.Lemmas
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
import all Lanius.Mini.Compiler.P.SrcType_floatTy
import all Lanius.Mini.Compiler.P.SrcType_isBool
import all Lanius.Mini.Compiler.P.SrcType_isChar
import all Lanius.Mini.Compiler.P.SrcType_isFloat
import all Lanius.Mini.Compiler.P.SrcType_isFloatAny
import all Lanius.Mini.Compiler.P.SrcType_isI32
import all Lanius.Mini.Compiler.P.SrcType_isInteger
import all Lanius.Mini.Compiler.P.SrcType_isIsize
import all Lanius.Mini.Compiler.P.SrcType_isPtr
import all Lanius.Mini.Compiler.P.SrcType_isScalar
import all Lanius.Mini.Compiler.P.SrcType_isSint
import all Lanius.Mini.Compiler.P.SrcType_isSintAny
import all Lanius.Mini.Compiler.P.SrcType_isStr
import all Lanius.Mini.Compiler.P.SrcType_isUint
import all Lanius.Mini.Compiler.P.SrcType_isUnit
import all Lanius.Mini.Compiler.P.SrcType_sintKind
import all Lanius.Mini.Compiler.P.SrcType_uintKind
import all Lanius.Mini.Compiler.P.SrcType_word
import all Lanius.Mini.Compiler.P.UintTy_half
import all Lanius.Mini.Compiler.P.UintTy_leastBits
import all Lanius.Mini.Compiler.P.UintTy_signedWord
import all Lanius.Mini.Compiler.P.UintTy_spare
import all Lanius.Mini.Compiler.P.boolBits
import all Lanius.Mini.Compiler.P.lookup
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
import all Lanius.Mini.Compiler.P.UintTy_code
import all Lanius.Mini.Compiler.P.entriesAt
import all Lanius.Mini.Compiler.P.funcsSize
import all Lanius.Mini.Compiler.P.funcsSlots
import all Lanius.Mini.Compiler.P.linkObjects
import all Lanius.Mini.Compiler.P.objectExports
import all Lanius.Mini.Compiler.P.objectFirsts
import all Lanius.Mini.Compiler.P.objectLayout
import all Lanius.Mini.Compiler.P.objectsLayout
import all Lanius.Mini.Compiler.P.objectsOk
import all Lanius.Mini.Compiler.P.objectsSlots
import all Lanius.Mini.Compiler.P.render
import all Lanius.Mini.Compiler.P.renderFuncs
import all Lanius.Mini.Compiler.P.renderObjects

@[expose] public section

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
