module

public import Lanius.Faithful.SelfPre.NB
public import Lanius.Faithful.SelfPre.EvalSlots
public import Lanius.Mini.Frontend.Types
public import Lanius.Mini.Frontend.P.depthLimit
public import Lanius.Mini.Frontend.P.limFuncs
public import Lanius.Mini.Frontend.P.limNest
public import Lanius.Mini.Frontend.P.limNestEff
public import Lanius.Mini.Frontend.P.limNestStep
public import Lanius.Mini.Frontend.P.limNum
public import Lanius.Mini.Frontend.P.limNumsArms
public import Lanius.Mini.Frontend.P.limNumsEff
public import Lanius.Mini.Frontend.P.limNumsExpr
public import Lanius.Mini.Frontend.P.limNumsExprs
public import Lanius.Mini.Frontend.P.limNumsIds
public import Lanius.Mini.Frontend.P.limNumsIdss
public import Lanius.Mini.Frontend.P.limNumsParams
public import Lanius.Mini.Frontend.P.limNumsStmt
public import Lanius.Mini.Frontend.P.limNumsTy
public import Lanius.Mini.Frontend.P.only
import all Lanius.Mini.Frontend.P.limConst
import all Lanius.Mini.Frontend.P.limGuard
import all Lanius.Mini.Frontend.P.limLeaf
import all Lanius.Mini.Frontend.P.limMax
import all Lanius.Mini.Frontend.P.limNest
import all Lanius.Mini.Frontend.P.limNestEff
import all Lanius.Mini.Frontend.P.limNestStep
import all Lanius.Mini.Frontend.P.limNum
import all Lanius.Mini.Frontend.P.limNumsExpr
import all Lanius.Mini.Frontend.P.limNumsExprs
import all Lanius.Mini.Frontend.P.limNumsIds
import all Lanius.Mini.Frontend.P.limNumsIdss
import all Lanius.Mini.Frontend.P.limNumsTy
import all Lanius.Mini.Frontend.P.limOne
import all Lanius.Mini.Frontend.P.limParamSlots
import all Lanius.Mini.Frontend.P.limParams
import all Lanius.Mini.Frontend.P.limStmt
import all Lanius.Mini.Frontend.P.limNumsArms
import all Lanius.Mini.Frontend.P.limFuncs
import all Lanius.Mini.Frontend.P.limNumsEff
import all Lanius.Mini.Frontend.P.limNumsParams
import all Lanius.Mini.Frontend.P.limNumsStmt

@[expose] public section

/-! # The front end's number and nesting limits (F14)

`limFuncs` checks every function's numbers against `depthLimit` (`limNums*`,
the largest number as `nb` counts it) and its expressions' unchecked slot
steps (`limNest`, which is `SrcStmt.slotNest`). Generated once by
target/claude-work/leafA/lims/gen.py from the constructors; edited by hand since. -/

open Lanius.Mini
open Lanius.Faithful.SelfPre

namespace Lanius.Faithful.SelfPre.Limits

theorem limNumsIds_ok : ∀ (v : List Nat), limNumsIds v = true → nb v ≤ depthLimit
  | [], _ => by simp
  | a :: rest, h => by have h1 := limNumsIds_ok rest; simp_all [nb_simp, Nat.max_le, Bool.and_eq_true, limNum, decide_eq_true_eq, limNumsIds]

theorem limNumsIdss_ok : ∀ (v : List (List Nat)), limNumsIdss v = true → nb v ≤ depthLimit
  | [], _ => by simp
  | a :: rest, h => by have h0 := limNumsIds_ok a; have h1 := limNumsIdss_ok rest; simp_all [nb_simp, Nat.max_le, Bool.and_eq_true, limNum, decide_eq_true_eq, limNumsIdss]

mutual
theorem limNumsTy_ok : ∀ (v : SrcType), limNumsTy v = true → nb v ≤ depthLimit
  | .i32, h => by simp_all [nb_simp, Nat.max_le, Bool.and_eq_true, limNum, decide_eq_true_eq, limNumsTy]
  | .bool, h => by simp_all [nb_simp, Nat.max_le, Bool.and_eq_true, limNum, decide_eq_true_eq, limNumsTy]
  | .uint _, h => by simp_all [nb_simp, Nat.max_le, Bool.and_eq_true, limNum, decide_eq_true_eq, limNumsTy]
  | .struct a0 a1, h => by have h1 := limNumsTys_ok a1; simp_all [nb_simp, Nat.max_le, Bool.and_eq_true, limNum, decide_eq_true_eq, limNumsTy]
  | .enum a0 a1, h => by have h1 := limNumsVariants_ok a1; simp_all [nb_simp, Nat.max_le, Bool.and_eq_true, limNum, decide_eq_true_eq, limNumsTy]
  | .ptr, h => by simp_all [nb_simp, Nat.max_le, Bool.and_eq_true, limNum, decide_eq_true_eq, limNumsTy]
  | .slice a0, h => by have h0 := limNumsTy_ok a0; simp_all [nb_simp, Nat.max_le, Bool.and_eq_true, limNum, decide_eq_true_eq, limNumsTy]
  | .array a0 a1, h => by have h0 := limNumsTy_ok a0; simp_all [nb_simp, Nat.max_le, Bool.and_eq_true, limNum, decide_eq_true_eq, limNumsTy]
  | .unit, h => by simp_all [nb_simp, Nat.max_le, Bool.and_eq_true, limNum, decide_eq_true_eq, limNumsTy]
  | .isize, h => by simp_all [nb_simp, Nat.max_le, Bool.and_eq_true, limNum, decide_eq_true_eq, limNumsTy]
  | .char, h => by simp_all [nb_simp, Nat.max_le, Bool.and_eq_true, limNum, decide_eq_true_eq, limNumsTy]
  | .float _, h => by simp_all [nb_simp, Nat.max_le, Bool.and_eq_true, limNum, decide_eq_true_eq, limNumsTy]
  | .sint _, h => by simp_all [nb_simp, Nat.max_le, Bool.and_eq_true, limNum, decide_eq_true_eq, limNumsTy]
  | .view a0, h => by simp_all [nb_simp, Nat.max_le, Bool.and_eq_true, limNum, decide_eq_true_eq, limNumsTy]
  | .str, h => by simp_all [nb_simp, Nat.max_le, Bool.and_eq_true, limNum, decide_eq_true_eq, limNumsTy]
  | .ref a0, h => by have h0 := limNumsTy_ok a0; simp_all [nb_simp, Nat.max_le, Bool.and_eq_true, limNum, decide_eq_true_eq, limNumsTy]
termination_by structural v => v

theorem limNumsTys_ok : ∀ (v : List SrcType), limNumsTys v = true → nb v ≤ depthLimit
  | [], _ => by simp
  | a :: rest, h => by have h0 := limNumsTy_ok a; have h1 := limNumsTys_ok rest; simp_all [nb_simp, Nat.max_le, Bool.and_eq_true, limNum, decide_eq_true_eq, limNumsTys]
termination_by structural v => v

theorem limNumsVariants_ok : ∀ (v : List (List SrcType)), limNumsVariants v = true → nb v ≤ depthLimit
  | [], _ => by simp
  | a :: rest, h => by have h0 := limNumsTys_ok a; have h1 := limNumsVariants_ok rest; simp_all [nb_simp, Nat.max_le, Bool.and_eq_true, limNum, decide_eq_true_eq, limNumsVariants]
termination_by structural v => v
end

theorem limNumsExpr_ok : ∀ (v : SrcExpr), limNumsExpr v = true → nb v ≤ depthLimit
  | .int _, h => by simp_all [nb_simp, Nat.max_le, Bool.and_eq_true, limNum, decide_eq_true_eq, limNumsExpr]
  | .boolean _, h => by simp_all [nb_simp, Nat.max_le, Bool.and_eq_true, limNum, decide_eq_true_eq, limNumsExpr]
  | .unsigned _ _, h => by simp_all [nb_simp, Nat.max_le, Bool.and_eq_true, limNum, decide_eq_true_eq, limNumsExpr]
  | .local a0, h => by simp_all [nb_simp, Nat.max_le, Bool.and_eq_true, limNum, decide_eq_true_eq, limNumsExpr]
  | .field a0 a1, h => by simp_all [nb_simp, Nat.max_le, Bool.and_eq_true, limNum, decide_eq_true_eq, limNumsExpr]
  | .negate a0, h => by have h0 := limNumsExpr_ok a0; simp_all [nb_simp, Nat.max_le, Bool.and_eq_true, limNum, decide_eq_true_eq, limNumsExpr]
  | .not a0, h => by have h0 := limNumsExpr_ok a0; simp_all [nb_simp, Nat.max_le, Bool.and_eq_true, limNum, decide_eq_true_eq, limNumsExpr]
  | .apply _ a1 a2, h => by have h1 := limNumsExpr_ok a1; have h2 := limNumsExpr_ok a2; simp_all [nb_simp, Nat.max_le, Bool.and_eq_true, limNum, decide_eq_true_eq, limNumsExpr]
  | .cast a0 a1, h => by have h0 := limNumsTy_ok a0; have h1 := limNumsExpr_ok a1; simp_all [nb_simp, Nat.max_le, Bool.and_eq_true, limNum, decide_eq_true_eq, limNumsExpr]
  | .null, h => by simp_all [nb_simp, Nat.max_le, Bool.and_eq_true, limNum, decide_eq_true_eq, limNumsExpr]
  | .char _, h => by simp_all [nb_simp, Nat.max_le, Bool.and_eq_true, limNum, decide_eq_true_eq, limNumsExpr]
  | .float _ _, h => by simp_all [nb_simp, Nat.max_le, Bool.and_eq_true, limNum, decide_eq_true_eq, limNumsExpr]

theorem limNumsExprs_ok : ∀ (v : List SrcExpr), limNumsExprs v = true → nb v ≤ depthLimit
  | [], _ => by simp
  | a :: rest, h => by have h0 := limNumsExpr_ok a; have h1 := limNumsExprs_ok rest; simp_all [nb_simp, Nat.max_le, Bool.and_eq_true, limNum, decide_eq_true_eq, limNumsExprs]

theorem limNumsArms_ok : ∀ (v : List SrcArm), limNumsArms v = true → nb v ≤ depthLimit
  | [], _ => by simp
  | ⟨bs, e⟩ :: rest, h => by
    have h0 := limNumsIds_ok bs; have h2 := limNumsExpr_ok e; have h1 := limNumsArms_ok rest
    simp_all [nb_simp, Nat.max_le, Bool.and_eq_true, limNum, decide_eq_true_eq, limNumsArms]

mutual
theorem limNumsEff_ok : ∀ (v : SrcEff), limNumsEff v = true → nb v ≤ depthLimit
  | .ePure a0, h => by have h0 := limNumsExpr_ok a0; simp_all [nb_simp, Nat.max_le, Bool.and_eq_true, limNum, decide_eq_true_eq, limNumsEff]
  | .eCall a0 a1, h => by have h1 := limNumsEffs_ok a1; simp_all [nb_simp, Nat.max_le, Bool.and_eq_true, limNum, decide_eq_true_eq, limNumsEff]
  | .eApply _ a1 a2, h => by have h1 := limNumsEff_ok a1; have h2 := limNumsEff_ok a2; simp_all [nb_simp, Nat.max_le, Bool.and_eq_true, limNum, decide_eq_true_eq, limNumsEff]
  | .eNeg a0, h => by have h0 := limNumsEff_ok a0; simp_all [nb_simp, Nat.max_le, Bool.and_eq_true, limNum, decide_eq_true_eq, limNumsEff]
  | .eNot a0, h => by have h0 := limNumsEff_ok a0; simp_all [nb_simp, Nat.max_le, Bool.and_eq_true, limNum, decide_eq_true_eq, limNumsEff]
  | .eCast a0 a1, h => by have h0 := limNumsTy_ok a0; have h1 := limNumsEff_ok a1; simp_all [nb_simp, Nat.max_le, Bool.and_eq_true, limNum, decide_eq_true_eq, limNumsEff]
  | .eIndex a0 a1, h => by have h1 := limNumsEff_ok a1; simp_all [nb_simp, Nat.max_le, Bool.and_eq_true, limNum, decide_eq_true_eq, limNumsEff]
  | .eStruct a0 a1, h => by have h0 := limNumsTy_ok a0; have h1 := limNumsEffs_ok a1; simp_all [nb_simp, Nat.max_le, Bool.and_eq_true, limNum, decide_eq_true_eq, limNumsEff]
  | .eVariant a0 a1 a2, h => by have h0 := limNumsTy_ok a0; have h2 := limNumsEffs_ok a2; simp_all [nb_simp, Nat.max_le, Bool.and_eq_true, limNum, decide_eq_true_eq, limNumsEff]
  | .eMatch a0 a1 a2 a3 a4, h => by have h0 := limNumsEff_ok a0; have h1 := limNumsTy_ok a1; have h2 := limNumsTy_ok a2; have h3 := limNumsIdss_ok a3; have h4 := limNumsEffs_ok a4; simp_all [nb_simp, Nat.max_le, Bool.and_eq_true, limNum, decide_eq_true_eq, limNumsEff]
  | .eDivide _ a1 a2, h => by have h1 := limNumsEff_ok a1; have h2 := limNumsEff_ok a2; simp_all [nb_simp, Nat.max_le, Bool.and_eq_true, limNum, decide_eq_true_eq, limNumsEff]
  | .eStride a0, h => by simp_all [nb_simp, Nat.max_le, Bool.and_eq_true, limNum, decide_eq_true_eq, limNumsEff]
  | .arraySlice a0 a1, h => by have h0 := limNumsTy_ok a0; simp_all [nb_simp, Nat.max_le, Bool.and_eq_true, limNum, decide_eq_true_eq, limNumsEff]
  | .eIf a0 a1 a2 a3, h => by have h0 := limNumsEff_ok a0; have h1 := limNumsTy_ok a1; have h2 := limNumsEff_ok a2; have h3 := limNumsEff_ok a3; simp_all [nb_simp, Nat.max_le, Bool.and_eq_true, limNum, decide_eq_true_eq, limNumsEff]
  | .eLet a0 a1 a2 a3 a4, h => by have h1 := limNumsTy_ok a1; have h2 := limNumsEff_ok a2; have h3 := limNumsTy_ok a3; have h4 := limNumsEff_ok a4; simp_all [nb_simp, Nat.max_le, Bool.and_eq_true, limNum, decide_eq_true_eq, limNumsEff]
  | .eLen a0, h => by simp_all [nb_simp, Nat.max_le, Bool.and_eq_true, limNum, decide_eq_true_eq, limNumsEff]
  | .eStr a0 a1, h => by have h1 := limNumsIds_ok a1; simp_all [nb_simp, Nat.max_le, Bool.and_eq_true, limNum, decide_eq_true_eq, limNumsEff]
  | .eBorrow a0 a1, h => by have h0 := limNumsTy_ok a0; have h1 := limNumsEff_ok a1; simp_all [nb_simp, Nat.max_le, Bool.and_eq_true, limNum, decide_eq_true_eq, limNumsEff]
  | .eDeref a0 a1, h => by have h0 := limNumsTy_ok a0; have h1 := limNumsEff_ok a1; simp_all [nb_simp, Nat.max_le, Bool.and_eq_true, limNum, decide_eq_true_eq, limNumsEff]
  | .eField a0 a1, h => by have h0 := limNumsEff_ok a0; simp_all [nb_simp, Nat.max_le, Bool.and_eq_true, limNum, decide_eq_true_eq, limNumsEff]
  | .eAt a0 a1, h => by have h0 := limNumsEff_ok a0; have h1 := limNumsEff_ok a1; simp_all [nb_simp, Nat.max_le, Bool.and_eq_true, limNum, decide_eq_true_eq, limNumsEff]
termination_by structural v => v

theorem limNumsEffs_ok : ∀ (v : List SrcEff), limNumsEffs v = true → nb v ≤ depthLimit
  | [], _ => by simp
  | a :: rest, h => by have h0 := limNumsEff_ok a; have h1 := limNumsEffs_ok rest; simp_all [nb_simp, Nat.max_le, Bool.and_eq_true, limNum, decide_eq_true_eq, limNumsEffs]
termination_by structural v => v
end

theorem limNumsStmt_ok : ∀ (v : SrcStmt), limNumsStmt v = true → nb v ≤ depthLimit
  | .nop, h => by simp_all [nb_simp, Nat.max_le, Bool.and_eq_true, limNum, decide_eq_true_eq, limNumsStmt]
  | .let a0 a1 a2 a3, h => by have h1 := limNumsTy_ok a1; have h2 := limNumsExpr_ok a2; have h3 := limNumsStmt_ok a3; simp_all [nb_simp, Nat.max_le, Bool.and_eq_true, limNum, decide_eq_true_eq, limNumsStmt]
  | .letStruct a0 a1 a2 a3, h => by have h1 := limNumsTy_ok a1; have h2 := limNumsExprs_ok a2; have h3 := limNumsStmt_ok a3; simp_all [nb_simp, Nat.max_le, Bool.and_eq_true, limNum, decide_eq_true_eq, limNumsStmt]
  | .letCall a0 a1 a2 a3 a4, h => by have h1 := limNumsTy_ok a1; have h3 := limNumsExprs_ok a3; have h4 := limNumsStmt_ok a4; simp_all [nb_simp, Nat.max_le, Bool.and_eq_true, limNum, decide_eq_true_eq, limNumsStmt]
  | .letEnum a0 a1 a2 a3 a4, h => by have h1 := limNumsTy_ok a1; have h3 := limNumsExprs_ok a3; have h4 := limNumsStmt_ok a4; simp_all [nb_simp, Nat.max_le, Bool.and_eq_true, limNum, decide_eq_true_eq, limNumsStmt]
  | .letMatch a0 a1 a2 a3 a4 a5, h => by have h1 := limNumsTy_ok a1; have h4 := limNumsArms_ok a4; have h5 := limNumsStmt_ok a5; simp_all [nb_simp, Nat.max_le, Bool.and_eq_true, limNum, decide_eq_true_eq, limNumsStmt]
  | .set a0 a1, h => by have h1 := limNumsExpr_ok a1; simp_all [nb_simp, Nat.max_le, Bool.and_eq_true, limNum, decide_eq_true_eq, limNumsStmt]
  | .setField a0 a1 a2, h => by have h2 := limNumsExpr_ok a2; simp_all [nb_simp, Nat.max_le, Bool.and_eq_true, limNum, decide_eq_true_eq, limNumsStmt]
  | .setCall a0 a1 a2, h => by have h2 := limNumsExprs_ok a2; simp_all [nb_simp, Nat.max_le, Bool.and_eq_true, limNum, decide_eq_true_eq, limNumsStmt]
  | .then a0 a1, h => by have h0 := limNumsStmt_ok a0; have h1 := limNumsStmt_ok a1; simp_all [nb_simp, Nat.max_le, Bool.and_eq_true, limNum, decide_eq_true_eq, limNumsStmt]
  | .if a0 a1 a2, h => by have h0 := limNumsExpr_ok a0; have h1 := limNumsStmt_ok a1; have h2 := limNumsStmt_ok a2; simp_all [nb_simp, Nat.max_le, Bool.and_eq_true, limNum, decide_eq_true_eq, limNumsStmt]
  | .while a0 a1, h => by have h0 := limNumsExpr_ok a0; have h1 := limNumsStmt_ok a1; simp_all [nb_simp, Nat.max_le, Bool.and_eq_true, limNum, decide_eq_true_eq, limNumsStmt]
  | .return a0, h => by have h0 := limNumsExpr_ok a0; simp_all [nb_simp, Nat.max_le, Bool.and_eq_true, limNum, decide_eq_true_eq, limNumsStmt]
  | .letAlloc a0 a1 a2 a3, h => by have h1 := limNumsExpr_ok a1; have h3 := limNumsStmt_ok a3; simp_all [nb_simp, Nat.max_le, Bool.and_eq_true, limNum, decide_eq_true_eq, limNumsStmt]
  | .letLoad a0 a1 a2 a3, h => by have h1 := limNumsExpr_ok a1; have h2 := limNumsExpr_ok a2; have h3 := limNumsStmt_ok a3; simp_all [nb_simp, Nat.max_le, Bool.and_eq_true, limNum, decide_eq_true_eq, limNumsStmt]
  | .setByte a0 a1 a2, h => by have h0 := limNumsExpr_ok a0; have h1 := limNumsExpr_ok a1; have h2 := limNumsExpr_ok a2; simp_all [nb_simp, Nat.max_le, Bool.and_eq_true, limNum, decide_eq_true_eq, limNumsStmt]
  | .free a0 a1 a2, h => by have h0 := limNumsExpr_ok a0; have h1 := limNumsExpr_ok a1; simp_all [nb_simp, Nat.max_le, Bool.and_eq_true, limNum, decide_eq_true_eq, limNumsStmt]
  | .letSlice a0 a1 a2 a3 a4, h => by have h1 := limNumsTy_ok a1; have h2 := limNumsExpr_ok a2; have h3 := limNumsExpr_ok a3; have h4 := limNumsStmt_ok a4; simp_all [nb_simp, Nat.max_le, Bool.and_eq_true, limNum, decide_eq_true_eq, limNumsStmt]
  | .letIndex a0 a1 a2 a3 a4, h => by have h1 := limNumsTy_ok a1; have h3 := limNumsExpr_ok a3; have h4 := limNumsStmt_ok a4; simp_all [nb_simp, Nat.max_le, Bool.and_eq_true, limNum, decide_eq_true_eq, limNumsStmt]
  | .setIndex a0 a1 a2, h => by have h1 := limNumsExpr_ok a1; have h2 := limNumsExpr_ok a2; simp_all [nb_simp, Nat.max_le, Bool.and_eq_true, limNum, decide_eq_true_eq, limNumsStmt]
  | .letEval a0 a1 a2 a3, h => by have h1 := limNumsTy_ok a1; have h2 := limNumsEff_ok a2; have h3 := limNumsStmt_ok a3; simp_all [nb_simp, Nat.max_le, Bool.and_eq_true, limNum, decide_eq_true_eq, limNumsStmt]
  | .setEval a0 a1, h => by have h1 := limNumsEff_ok a1; simp_all [nb_simp, Nat.max_le, Bool.and_eq_true, limNum, decide_eq_true_eq, limNumsStmt]
  | .ifEval a0 a1 a2, h => by have h0 := limNumsEff_ok a0; have h1 := limNumsStmt_ok a1; have h2 := limNumsStmt_ok a2; simp_all [nb_simp, Nat.max_le, Bool.and_eq_true, limNum, decide_eq_true_eq, limNumsStmt]
  | .whileEval a0 a1, h => by have h0 := limNumsEff_ok a0; have h1 := limNumsStmt_ok a1; simp_all [nb_simp, Nat.max_le, Bool.and_eq_true, limNum, decide_eq_true_eq, limNumsStmt]
  | .returnEval a0, h => by have h0 := limNumsEff_ok a0; simp_all [nb_simp, Nat.max_le, Bool.and_eq_true, limNum, decide_eq_true_eq, limNumsStmt]
  | .discard a0, h => by have h0 := limNumsEff_ok a0; simp_all [nb_simp, Nat.max_le, Bool.and_eq_true, limNum, decide_eq_true_eq, limNumsStmt]
  | .setIndexEval a0 a1 a2, h => by have h1 := limNumsEff_ok a1; have h2 := limNumsEff_ok a2; simp_all [nb_simp, Nat.max_le, Bool.and_eq_true, limNum, decide_eq_true_eq, limNumsStmt]
  | .setFieldEval a0 a1 a2, h => by have h2 := limNumsEff_ok a2; simp_all [nb_simp, Nat.max_le, Bool.and_eq_true, limNum, decide_eq_true_eq, limNumsStmt]
  | .returnUnit, h => by simp_all [nb_simp, Nat.max_le, Bool.and_eq_true, limNum, decide_eq_true_eq, limNumsStmt]
  | .assert a0, h => by have h0 := limNumsEff_ok a0; simp_all [nb_simp, Nat.max_le, Bool.and_eq_true, limNum, decide_eq_true_eq, limNumsStmt]
  | .break, h => by simp_all [nb_simp, Nat.max_le, Bool.and_eq_true, limNum, decide_eq_true_eq, limNumsStmt]
  | .continue, h => by simp_all [nb_simp, Nat.max_le, Bool.and_eq_true, limNum, decide_eq_true_eq, limNumsStmt]
  | .matchArm a0 a1 a2 _ a4 a5 a6 a7, h => by have h5 := limNumsTy_ok a5; have h6 := limNumsStmt_ok a6; have h7 := limNumsStmt_ok a7; simp_all [nb_simp, Nat.max_le, Bool.and_eq_true, limNum, decide_eq_true_eq, limNumsStmt]
  | .unreachable a0 a1, h => by have h1 := limNumsTy_ok a1; simp_all [nb_simp, Nat.max_le, Bool.and_eq_true, limNum, decide_eq_true_eq, limNumsStmt]
  | .letView a0 a1 a2 a3 a4, h => by have h2 := limNumsExprs_ok a2; have h4 := limNumsStmt_ok a4; simp_all [nb_simp, Nat.max_le, Bool.and_eq_true, limNum, decide_eq_true_eq, limNumsStmt]
  | .letStr a0 a1 a2, h => by have h1 := limNumsIds_ok a1; have h2 := limNumsStmt_ok a2; simp_all [nb_simp, Nat.max_le, Bool.and_eq_true, limNum, decide_eq_true_eq, limNumsStmt]
  | .setPlace a0 a1, h => by have h0 := limNumsEff_ok a0; have h1 := limNumsEff_ok a1; simp_all [nb_simp, Nat.max_le, Bool.and_eq_true, limNum, decide_eq_true_eq, limNumsStmt]
  | .setPlaceOp _ a1 a2, h => by have h1 := limNumsEff_ok a1; have h2 := limNumsEff_ok a2; simp_all [nb_simp, Nat.max_le, Bool.and_eq_true, limNum, decide_eq_true_eq, limNumsStmt]

theorem limNumsParams_ok : ∀ (v : List SrcParam), limNumsParams v = true → nb v ≤ depthLimit
  | [], _ => by simp
  | ⟨id, t⟩ :: rest, h => by
    have h0 := limNumsTy_ok t; have h1 := limNumsParams_ok rest
    simp_all [nb_simp, Nat.max_le, Bool.and_eq_true, limNum, decide_eq_true_eq, limNumsParams]

theorem limNestStep_le {n : Nat} (h : limNestStep n ≤ depthLimit) : limNestStep n = n + 1 ∧ n + 1 ≤ depthLimit := by
  unfold limNestStep at h ⊢
  split at h <;> simp_all <;> omega

mutual
theorem limNestEff_le : ∀ (v : SrcEff), limNestEff v ≤ depthLimit → SrcEff.slotNest v = limNestEff v
  | .ePure _, h => by simp_all [limNestEff, SrcEff.slotNest, Nat.max_le]
  | .eCall _ a1, h => by have h1 := limNestEffs_le a1; simp_all [limNestEff, SrcEff.slotNest, Nat.max_le]
  | .eApply _ a1 a2, h => by
    have ha := limNestEff_le a1; have hb := limNestEff_le a2
    simp only [limNestEff, Nat.max_le] at h
    obtain ⟨h1, h2⟩ := h
    have st := limNestStep_le h2
    simp only [SrcEff.slotNest, limNestEff, st.1, ha h1, hb (by omega)]
  | .eNeg a0, h => by have h0 := limNestEff_le a0; simp_all [limNestEff, SrcEff.slotNest, Nat.max_le]
  | .eNot a0, h => by have h0 := limNestEff_le a0; simp_all [limNestEff, SrcEff.slotNest, Nat.max_le]
  | .eCast _ a1, h => by have h1 := limNestEff_le a1; simp_all [limNestEff, SrcEff.slotNest, Nat.max_le]
  | .eIndex _ a1, h => by have h1 := limNestEff_le a1; simp_all [limNestEff, SrcEff.slotNest, Nat.max_le]
  | .eStruct _ a1, h => by have h1 := limNestEffs_le a1; simp_all [limNestEff, SrcEff.slotNest, Nat.max_le]
  | .eVariant _ _ a2, h => by have h2 := limNestEffs_le a2; simp_all [limNestEff, SrcEff.slotNest, Nat.max_le]
  | .eMatch a0 _ _ _ a4, h => by have h0 := limNestEff_le a0; have h4 := limNestEffs_le a4; simp_all [limNestEff, SrcEff.slotNest, Nat.max_le]
  | .eDivide _ a1 a2, h => by
    have ha := limNestEff_le a1; have hb := limNestEff_le a2
    simp only [limNestEff, Nat.max_le] at h
    obtain ⟨h1, h2⟩ := h
    have st := limNestStep_le h2
    simp only [SrcEff.slotNest, limNestEff, st.1, ha h1, hb (by omega)]
  | .eStride _, h => by simp_all [limNestEff, SrcEff.slotNest, Nat.max_le]
  | .arraySlice _ _, h => by simp_all [limNestEff, SrcEff.slotNest, Nat.max_le]
  | .eIf a0 _ a2 a3, h => by have h0 := limNestEff_le a0; have h2 := limNestEff_le a2; have h3 := limNestEff_le a3; simp_all [limNestEff, SrcEff.slotNest, Nat.max_le]
  | .eLet _ _ a2 _ a4, h => by have h2 := limNestEff_le a2; have h4 := limNestEff_le a4; simp_all [limNestEff, SrcEff.slotNest, Nat.max_le]
  | .eLen _, h => by simp_all [limNestEff, SrcEff.slotNest, Nat.max_le]
  | .eStr _ _, h => by simp_all [limNestEff, SrcEff.slotNest, Nat.max_le]
  | .eBorrow _ a1, h => by have h1 := limNestEff_le a1; simp_all [limNestEff, SrcEff.slotNest, Nat.max_le]
  | .eDeref _ a1, h => by have h1 := limNestEff_le a1; simp_all [limNestEff, SrcEff.slotNest, Nat.max_le]
  | .eField a0 _, h => by have h0 := limNestEff_le a0; simp_all [limNestEff, SrcEff.slotNest, Nat.max_le]
  | .eAt a0 a1, h => by have h0 := limNestEff_le a0; have h1 := limNestEff_le a1; simp_all [limNestEff, SrcEff.slotNest, Nat.max_le]
termination_by structural v => v

theorem limNestEffs_le : ∀ (v : List SrcEff), limNestEffs v ≤ depthLimit → effsSlotNest v = limNestEffs v
  | [], _ => by simp only [limNestEffs, effsSlotNest]
  | a :: rest, h => by have h0 := limNestEff_le a; have h1 := limNestEffs_le rest; simp_all [limNestEffs, effsSlotNest, Nat.max_le]
termination_by structural v => v
end

theorem limNest_le : ∀ (v : SrcStmt), limNest v ≤ depthLimit → SrcStmt.slotNest v = limNest v
  | .nop, h => by simp_all [limNest, SrcStmt.slotNest, Nat.max_le]
  | .let _ _ _ a3, h => by have h3 := limNest_le a3; simp_all [limNest, SrcStmt.slotNest, Nat.max_le]
  | .letStruct _ _ _ a3, h => by have h3 := limNest_le a3; simp_all [limNest, SrcStmt.slotNest, Nat.max_le]
  | .letCall _ _ _ _ a4, h => by have h4 := limNest_le a4; simp_all [limNest, SrcStmt.slotNest, Nat.max_le]
  | .letEnum _ _ _ _ a4, h => by have h4 := limNest_le a4; simp_all [limNest, SrcStmt.slotNest, Nat.max_le]
  | .letMatch _ _ _ _ _ a5, h => by have h5 := limNest_le a5; simp_all [limNest, SrcStmt.slotNest, Nat.max_le]
  | .set _ _, h => by simp_all [limNest, SrcStmt.slotNest, Nat.max_le]
  | .setField _ _ _, h => by simp_all [limNest, SrcStmt.slotNest, Nat.max_le]
  | .setCall _ _ _, h => by simp_all [limNest, SrcStmt.slotNest, Nat.max_le]
  | .then a0 a1, h => by have h0 := limNest_le a0; have h1 := limNest_le a1; simp_all [limNest, SrcStmt.slotNest, Nat.max_le]
  | .if _ a1 a2, h => by have h1 := limNest_le a1; have h2 := limNest_le a2; simp_all [limNest, SrcStmt.slotNest, Nat.max_le]
  | .while _ a1, h => by have h1 := limNest_le a1; simp_all [limNest, SrcStmt.slotNest, Nat.max_le]
  | .return _, h => by simp_all [limNest, SrcStmt.slotNest, Nat.max_le]
  | .letAlloc _ _ _ a3, h => by have h3 := limNest_le a3; simp_all [limNest, SrcStmt.slotNest, Nat.max_le]
  | .letLoad _ _ _ a3, h => by have h3 := limNest_le a3; simp_all [limNest, SrcStmt.slotNest, Nat.max_le]
  | .setByte _ _ _, h => by simp_all [limNest, SrcStmt.slotNest, Nat.max_le]
  | .free _ _ _, h => by simp_all [limNest, SrcStmt.slotNest, Nat.max_le]
  | .letSlice _ _ _ _ a4, h => by have h4 := limNest_le a4; simp_all [limNest, SrcStmt.slotNest, Nat.max_le]
  | .letIndex _ _ _ _ a4, h => by have h4 := limNest_le a4; simp_all [limNest, SrcStmt.slotNest, Nat.max_le]
  | .setIndex _ _ _, h => by simp_all [limNest, SrcStmt.slotNest, Nat.max_le]
  | .letEval _ _ a2 a3, h => by have h2 := limNestEff_le a2; have h3 := limNest_le a3; simp_all [limNest, SrcStmt.slotNest, Nat.max_le]
  | .setEval _ a1, h => by have h1 := limNestEff_le a1; simp_all [limNest, SrcStmt.slotNest, Nat.max_le]
  | .ifEval a0 a1 a2, h => by have h0 := limNestEff_le a0; have h1 := limNest_le a1; have h2 := limNest_le a2; simp_all [limNest, SrcStmt.slotNest, Nat.max_le]
  | .whileEval a0 a1, h => by have h0 := limNestEff_le a0; have h1 := limNest_le a1; simp_all [limNest, SrcStmt.slotNest, Nat.max_le]
  | .returnEval a0, h => by have h0 := limNestEff_le a0; simp_all [limNest, SrcStmt.slotNest, Nat.max_le]
  | .discard a0, h => by have h0 := limNestEff_le a0; simp_all [limNest, SrcStmt.slotNest, Nat.max_le]
  | .setIndexEval _ a1 a2, h => by have h1 := limNestEff_le a1; have h2 := limNestEff_le a2; simp_all [limNest, SrcStmt.slotNest, Nat.max_le]
  | .setFieldEval _ _ a2, h => by have h2 := limNestEff_le a2; simp_all [limNest, SrcStmt.slotNest, Nat.max_le]
  | .returnUnit, h => by simp_all [limNest, SrcStmt.slotNest, Nat.max_le]
  | .assert a0, h => by have h0 := limNestEff_le a0; simp_all [limNest, SrcStmt.slotNest, Nat.max_le]
  | .break, h => by simp_all [limNest, SrcStmt.slotNest, Nat.max_le]
  | .continue, h => by simp_all [limNest, SrcStmt.slotNest, Nat.max_le]
  | .matchArm _ _ _ _ _ _ a6 a7, h => by have h6 := limNest_le a6; have h7 := limNest_le a7; simp_all [limNest, SrcStmt.slotNest, Nat.max_le]
  | .unreachable _ _, h => by simp_all [limNest, SrcStmt.slotNest, Nat.max_le]
  | .letView _ _ _ _ a4, h => by have h4 := limNest_le a4; simp_all [limNest, SrcStmt.slotNest, Nat.max_le]
  | .letStr _ _ a2, h => by have h2 := limNest_le a2; simp_all [limNest, SrcStmt.slotNest, Nat.max_le]
  | .setPlace a0 a1, h => by have h0 := limNestEff_le a0; have h1 := limNestEff_le a1; simp_all [limNest, SrcStmt.slotNest, Nat.max_le]
  | .setPlaceOp _ a1 a2, h => by have h1 := limNestEff_le a1; have h2 := limNestEff_le a2; simp_all [limNest, SrcStmt.slotNest, Nat.max_le]

end Lanius.Faithful.SelfPre.Limits
