module

public import Lanius.Faithful.BudgetTactic
public import Lanius.Faithful.Gen.SelfRep
public import Lanius.Faithful.Gen.SelfSrcF_stringOpen
public import Lanius.Faithful.Gen.SelfStmtF_stringOpen
public import Lanius.Faithful.GenB.SelfBStmtF_Inline_pPathMore
public import Lanius.Faithful.GenB.SelfBStmtF_Inline_pTypeArgsNone
public import Lanius.Faithful.GenB.SelfBStmtF_argView
public import Lanius.Faithful.GenB.SelfBStmtF_collect
public import Lanius.Faithful.GenB.SelfBStmtF_consBinder
public import Lanius.Faithful.GenB.SelfBStmtF_consBound
public import Lanius.Faithful.GenB.SelfBStmtF_consTreeTail
public import Lanius.Faithful.GenB.SelfBStmtF_divergeArm
public import Lanius.Faithful.GenB.SelfBStmtF_fnInstRet
public import Lanius.Faithful.GenB.SelfBStmtF_hasConst
public import Lanius.Faithful.GenB.SelfBStmtF_hasKids
public import Lanius.Faithful.GenB.SelfBStmtF_isEmptyUsize
public import Lanius.Faithful.GenB.SelfBStmtF_matchTysOrNone
public import Lanius.Faithful.GenB.SelfBStmtF_noBlock
public import Lanius.Faithful.GenB.SelfBStmtF_noToken
public import Lanius.Faithful.GenB.SelfBStmtF_noTrees
public import Lanius.Faithful.GenB.SelfBStmtF_purePart
public import Lanius.Faithful.GenB.SelfBStmtF_repeatEff
public import Lanius.Faithful.GenB.SelfBStmtF_retBinds
public import Lanius.Faithful.GenB.SelfBStmtF_sliceHead
public import Lanius.Faithful.GenB.SelfBStmtF_stringOpen
public import Lanius.Faithful.GenB.SelfBStmtF_textSelf
public import Lanius.Faithful.GenB.SelfBStmtF_typePathSpellings
public import Lanius.Faithful.GenB.SelfBStmtN0
public import Lanius.Faithful.GenB.SelfBStmtN2
public import Lanius.Faithful.GenB.SelfBStmtN4
public import Lanius.Faithful.GenB.SelfBStmtN5
public import Lanius.Faithful.GenB.SelfBStmtN7
import all Lanius.Faithful.Gen.SelfSrcF_stringOpen
import all Lanius.Faithful.Gen.SelfStmtF_stringOpen
import all Lanius.Mini.Frontend.P.Inline_pArrayLit
import all Lanius.Mini.Frontend.P.Inline_pArrayRepeat
import all Lanius.Mini.Frontend.P.Inline_pArraySome
import all Lanius.Mini.Frontend.P.Inline_pAssign
import all Lanius.Mini.Frontend.P.Inline_pBase
import all Lanius.Mini.Frontend.P.Inline_pCast
import all Lanius.Mini.Frontend.P.Inline_pExpr
import all Lanius.Mini.Frontend.P.Inline_pGroup
import all Lanius.Mini.Frontend.P.Inline_pIdent
import all Lanius.Mini.Frontend.P.Inline_pIdentPlain
import all Lanius.Mini.Frontend.P.Inline_pMatchExpr
import all Lanius.Mini.Frontend.P.Inline_pMemberTypeArgsNone
import all Lanius.Mini.Frontend.P.Inline_pNeg
import all Lanius.Mini.Frontend.P.Inline_pNot
import all Lanius.Mini.Frontend.P.Inline_pPatternIdent
import all Lanius.Mini.Frontend.P.Inline_pPatternPlain
import all Lanius.Mini.Frontend.P.Inline_pPostfix
import all Lanius.Mini.Frontend.P.Inline_pPostfixCall
import all Lanius.Mini.Frontend.P.Inline_pPostfixEnd
import all Lanius.Mini.Frontend.P.Inline_pPostfixIndex
import all Lanius.Mini.Frontend.P.Inline_pPostfixMember
import all Lanius.Mini.Frontend.P.Inline_pStructLit
import all Lanius.Mini.Frontend.P.Inline_pTypeArgsNone
import all Lanius.Mini.Frontend.P.Inline_pTypeIdent
import all Lanius.Mini.Frontend.P.allocPath
import all Lanius.Mini.Frontend.P.argExpected
import all Lanius.Mini.Frontend.P.armNamed
import all Lanius.Mini.Frontend.P.armValueTrees
import all Lanius.Mini.Frontend.P.bareTy
import all Lanius.Mini.Frontend.P.bindArg
import all Lanius.Mini.Frontend.P.bindersOf
import all Lanius.Mini.Frontend.P.boundArgs
import all Lanius.Mini.Frontend.P.checkedEffs
import all Lanius.Mini.Frontend.P.deallocPath
import all Lanius.Mini.Frontend.P.decimal
import all Lanius.Mini.Frontend.P.divergeArm
import all Lanius.Mini.Frontend.P.effBinary
import all Lanius.Mini.Frontend.P.effOf
import all Lanius.Mini.Frontend.P.effPlace
import all Lanius.Mini.Frontend.P.effSliceLocal
import all Lanius.Mini.Frontend.P.effTy
import all Lanius.Mini.Frontend.P.expectedArray
import all Lanius.Mini.Frontend.P.explicitInst
import all Lanius.Mini.Frontend.P.exprOf
import all Lanius.Mini.Frontend.P.fieldExpects
import all Lanius.Mini.Frontend.P.fieldOfTy
import all Lanius.Mini.Frontend.P.fieldValues
import all Lanius.Mini.Frontend.P.findFn
import all Lanius.Mini.Frontend.P.findMethod
import all Lanius.Mini.Frontend.P.hasKids
import all Lanius.Mini.Frontend.P.hasLocal
import all Lanius.Mini.Frontend.P.hasTys
import all Lanius.Mini.Frontend.P.headTy
import all Lanius.Mini.Frontend.P.isFnPath
import all Lanius.Mini.Frontend.P.isLevel
import all Lanius.Mini.Frontend.P.isMethodForm
import all Lanius.Mini.Frontend.P.isPath
import all Lanius.Mini.Frontend.P.isPathCall
import all Lanius.Mini.Frontend.P.isTypeOwner
import all Lanius.Mini.Frontend.P.kid
import all Lanius.Mini.Frontend.P.kidToken
import all Lanius.Mini.Frontend.P.knownArgs
import all Lanius.Mini.Frontend.P.listItems
import all Lanius.Mini.Frontend.P.litWants
import all Lanius.Mini.Frontend.P.localOf
import all Lanius.Mini.Frontend.P.matchOrder
import all Lanius.Mini.Frontend.P.memberArgs
import all Lanius.Mini.Frontend.P.methodBinds
import all Lanius.Mini.Frontend.P.methodOfTy
import all Lanius.Mini.Frontend.P.namedParts
import all Lanius.Mini.Frontend.P.namedSplit
import all Lanius.Mini.Frontend.P.noNames
import all Lanius.Mini.Frontend.P.noTrees
import all Lanius.Mini.Frontend.P.nodeProd
import all Lanius.Mini.Frontend.P.paramExpects
import all Lanius.Mini.Frontend.P.paramPatterns
import all Lanius.Mini.Frontend.P.pathModule
import all Lanius.Mini.Frontend.P.pathRef
import all Lanius.Mini.Frontend.P.pathSpellings
import all Lanius.Mini.Frontend.P.payloadTys
import all Lanius.Mini.Frontend.P.repeatTy
import all Lanius.Mini.Frontend.P.retBinds
import all Lanius.Mini.Frontend.P.sameNames
import all Lanius.Mini.Frontend.P.skipExpects
import all Lanius.Mini.Frontend.P.splitLast
import all Lanius.Mini.Frontend.P.stepExpected
import all Lanius.Mini.Frontend.P.stringInit
import all Lanius.Mini.Frontend.P.tailTys
import all Lanius.Mini.Frontend.P.textSliceFromRawParts
import all Lanius.Mini.Frontend.P.textSliceLen
import all Lanius.Mini.Frontend.P.textSliceStride
import all Lanius.Mini.Frontend.P.textStr
import all Lanius.Mini.Frontend.P.typeDeclAt
import all Lanius.Mini.Frontend.P.variantByPath
import all Lanius.Mini.Frontend.P.variantExpects
import all Lanius.Mini.Frontend.P.viewOf
import all Lanius.Mini.Frontend.P.viewsOf
import all Lanius.Mini.Frontend.P.xAtOf
import all Lanius.Mini.Frontend.P.xIndexOf
import all Lanius.Mini.Frontend.P.zipVariants

@[expose] public section

/-! Generated by formal/tools/budget_certs.py: the budget certificates, for any
programs that hold the functions (group F_stringOpen, part 4). Do not edit. -/

set_option maxHeartbeats 1000000
set_option maxRecDepth 100000
set_option linter.unusedVariables false

namespace Lanius.Faithful.SelfBudget

open Lanius.Mini
open Lanius.Core (Value)
open Lanius.Faithful
open Lanius.Faithful.Self
open Lanius.Faithful.SelfRep
open Lanius.Faithful.SelfCert
open Lanius.Faithful.Budget

theorem bstep_eff_infer {spW sp : SrcProgram} {prims : Prims} {ix_eff_infer ix_minus ix_no_names ix_empty_of_mini_selfhost_Ty ix_concat_of_mini_selfhost_List_usize ix_checked_eff ix_has_tys ix_param_expects ix_views_of ix_eff_called ix_skip_expects ix_arg_list ix_param_patterns ix_eff_inferred ix_eff_args_bound ix_ret_binds : Nat}
    (fnW : spW.funcs[ix_eff_infer]? = some (src_eff_infer ix_minus ix_no_names ix_empty_of_mini_selfhost_Ty ix_concat_of_mini_selfhost_List_usize ix_checked_eff ix_has_tys ix_param_expects ix_views_of ix_eff_called ix_skip_expects ix_arg_list ix_param_patterns ix_eff_inferred ix_eff_args_bound ix_ret_binds)) (fn : sp.funcs[ix_eff_infer]? = some (src_eff_infer ix_minus ix_no_names ix_empty_of_mini_selfhost_Ty ix_concat_of_mini_selfhost_List_usize ix_checked_eff ix_has_tys ix_param_expects ix_views_of ix_eff_called ix_skip_expects ix_arg_list ix_param_patterns ix_eff_inferred ix_eff_args_bound ix_ret_binds))
    (np : prims.isPrim ix_eff_infer = false)
    (back : Certified (∀ {n : Nat}, Stmt_eff_infer sp prims ix_eff_infer n))
    (b_minus : Certified (∀ {n : Nat}, BStmt_minus spW sp prims ix_minus n))
    (b_no_names : Certified (∀ {n : Nat}, BStmt_no_names spW sp prims ix_no_names n))
    (b_empty_of_mini_selfhost_Ty : Certified (∀ {n : Nat}, BStmt_empty_of_mini_selfhost_Ty spW sp prims ix_empty_of_mini_selfhost_Ty n))
    (b_concat_of_mini_selfhost_List_usize : Certified (∀ {n : Nat}, BStmt_concat_of_mini_selfhost_List_usize spW sp prims ix_concat_of_mini_selfhost_List_usize n))
    (b_checked_eff : Certified (∀ {n : Nat}, BStmt_checked_eff spW sp prims ix_checked_eff n))
    (b_has_tys : Certified (∀ {n : Nat}, BStmt_has_tys spW sp prims ix_has_tys n))
    (b_param_expects : Certified (∀ {n : Nat}, BStmt_param_expects spW sp prims ix_param_expects n))
    (b_views_of : Certified (∀ {n : Nat}, BStmt_views_of spW sp prims ix_views_of n))
    (b_eff_called : Certified (∀ {n : Nat}, BStmt_eff_called spW sp prims ix_eff_called n))
    (b_skip_expects : Certified (∀ {n : Nat}, BStmt_skip_expects spW sp prims ix_skip_expects n))
    (b_param_patterns : Certified (∀ {n : Nat}, BStmt_param_patterns spW sp prims ix_param_patterns n))
    (b_eff_inferred : Certified (∀ {n : Nat}, BStmt_eff_inferred spW sp prims ix_eff_inferred n))
    (b_ret_binds : Certified (∀ {n : Nat}, BStmt_ret_binds spW sp prims ix_ret_binds n)) {n : Nat}
    (bih_arg_list : Certified (BStmt_arg_list spW sp prims ix_arg_list n))
    (bih_eff_args_bound : Certified (BStmt_eff_args_bound spW sp prims ix_eff_args_bound n)) :
    BStmt_eff_infer spW sp prims ix_eff_infer (n + 1) := by
  intro x0 x1 x2 x3 x4 x5 x6 x7 x8 v0 v1 v2 v3 v4 v5 v6 v7 v8 w k b h r0 r1 r2 r3 r4 r5 r6 r7 r8 hb pre
  have key : qcall sp prims uc (n + 1) ix_eff_infer [v0, v1, v2, v3, v4, v5, v6, v7, v8] = some (w, k) ∧ Cost_eff_infer (n + 1) x0 x1 x2 x3 x4 x5 x6 x7 x8 = k := by
    rw [qcall_succ np fnW] at h
    rw [qcall_succ np fn]
    simp only [src_eff_infer, List.length_cons, List.length_nil, if_true] at h ⊢
    rw [Pre_eff_infer.eq_def] at pre
    simp only at pre
    budget Cost_eff_infer
  exact ⟨key.1, key.2, back.out (pcall_of_q key.1) r0 r1 r2 r3 r4 r5 r6 r7 r8⟩

theorem bstep_eff_arms {spW sp : SrcProgram} {prims : Prims} {ix_eff_arms ix_minus ix_unbox_of_mini_selfhost_List_mini_selfhost_CTree ix_unbox_of_mini_selfhost_List_mini_selfhost_VariantTy ix_empty_of_mini_selfhost_EffArm ix_cons_eff_arm ix_eff_arm : Nat}
    (fnW : spW.funcs[ix_eff_arms]? = some (src_eff_arms ix_minus ix_unbox_of_mini_selfhost_List_mini_selfhost_CTree ix_unbox_of_mini_selfhost_List_mini_selfhost_VariantTy ix_eff_arms ix_empty_of_mini_selfhost_EffArm ix_cons_eff_arm ix_eff_arm)) (fn : sp.funcs[ix_eff_arms]? = some (src_eff_arms ix_minus ix_unbox_of_mini_selfhost_List_mini_selfhost_CTree ix_unbox_of_mini_selfhost_List_mini_selfhost_VariantTy ix_eff_arms ix_empty_of_mini_selfhost_EffArm ix_cons_eff_arm ix_eff_arm))
    (np : prims.isPrim ix_eff_arms = false)
    (back : Certified (∀ {n : Nat}, Stmt_eff_arms sp prims ix_eff_arms n))
    (b_minus : Certified (∀ {n : Nat}, BStmt_minus spW sp prims ix_minus n))
    (pp_unbox_of_mini_selfhost_List_mini_selfhost_CTree : prims.isPrim ix_unbox_of_mini_selfhost_List_mini_selfhost_CTree = true) (bx_unbox_of_mini_selfhost_List_mini_selfhost_CTree : prims.boxed.contains ix_unbox_of_mini_selfhost_List_mini_selfhost_CTree = false)
    (pp_unbox_of_mini_selfhost_List_mini_selfhost_VariantTy : prims.isPrim ix_unbox_of_mini_selfhost_List_mini_selfhost_VariantTy = true) (bx_unbox_of_mini_selfhost_List_mini_selfhost_VariantTy : prims.boxed.contains ix_unbox_of_mini_selfhost_List_mini_selfhost_VariantTy = false)
    (b_empty_of_mini_selfhost_EffArm : Certified (∀ {n : Nat}, BStmt_empty_of_mini_selfhost_EffArm spW sp prims ix_empty_of_mini_selfhost_EffArm n))
    (b_cons_eff_arm : Certified (∀ {n : Nat}, BStmt_cons_eff_arm spW sp prims ix_cons_eff_arm n)) {n : Nat}
    (bih_eff_arms : Certified (BStmt_eff_arms spW sp prims ix_eff_arms n))
    (bih_eff_arm : Certified (BStmt_eff_arm spW sp prims ix_eff_arm n)) :
    BStmt_eff_arms spW sp prims ix_eff_arms (n + 1) := by
  intro x0 x1 x2 x3 x4 x5 x6 v0 v1 v2 v3 v4 v5 v6 w k b h r0 r1 r2 r3 r4 r5 r6 hb pre
  have key : qcall sp prims uc (n + 1) ix_eff_arms [v0, v1, v2, v3, v4, v5, v6] = some (w, k) ∧ Cost_eff_arms (n + 1) x0 x1 x2 x3 x4 x5 x6 = k := by
    rw [qcall_succ np fnW] at h
    rw [qcall_succ np fn]
    simp only [src_eff_arms, List.length_cons, List.length_nil, if_true] at h ⊢
    rw [Pre_eff_arms.eq_def] at pre
    simp only at pre
    budget Cost_eff_arms
  exact ⟨key.1, key.2, back.out (pcall_of_q key.1) r0 r1 r2 r3 r4 r5 r6⟩

theorem bstep_arg_list {spW sp : SrcProgram} {prims : Prims} {ix_arg_list ix_minus ix_unbox_of_mini_selfhost_List_mini_selfhost_CTree ix_empty_of_mini_selfhost_MEff ix_cons_eff ix_head_ty ix_tail_tys ix_arg_eff : Nat}
    (fnW : spW.funcs[ix_arg_list]? = some (src_arg_list ix_minus ix_unbox_of_mini_selfhost_List_mini_selfhost_CTree ix_empty_of_mini_selfhost_MEff ix_cons_eff ix_head_ty ix_tail_tys ix_arg_list ix_arg_eff)) (fn : sp.funcs[ix_arg_list]? = some (src_arg_list ix_minus ix_unbox_of_mini_selfhost_List_mini_selfhost_CTree ix_empty_of_mini_selfhost_MEff ix_cons_eff ix_head_ty ix_tail_tys ix_arg_list ix_arg_eff))
    (np : prims.isPrim ix_arg_list = false)
    (back : Certified (∀ {n : Nat}, Stmt_arg_list sp prims ix_arg_list n))
    (b_minus : Certified (∀ {n : Nat}, BStmt_minus spW sp prims ix_minus n))
    (pp_unbox_of_mini_selfhost_List_mini_selfhost_CTree : prims.isPrim ix_unbox_of_mini_selfhost_List_mini_selfhost_CTree = true) (bx_unbox_of_mini_selfhost_List_mini_selfhost_CTree : prims.boxed.contains ix_unbox_of_mini_selfhost_List_mini_selfhost_CTree = false)
    (b_empty_of_mini_selfhost_MEff : Certified (∀ {n : Nat}, BStmt_empty_of_mini_selfhost_MEff spW sp prims ix_empty_of_mini_selfhost_MEff n))
    (b_cons_eff : Certified (∀ {n : Nat}, BStmt_cons_eff spW sp prims ix_cons_eff n))
    (b_head_ty : Certified (∀ {n : Nat}, BStmt_head_ty spW sp prims ix_head_ty n))
    (b_tail_tys : Certified (∀ {n : Nat}, BStmt_tail_tys spW sp prims ix_tail_tys n)) {n : Nat}
    (bih_arg_list : Certified (BStmt_arg_list spW sp prims ix_arg_list n))
    (bih_arg_eff : Certified (BStmt_arg_eff spW sp prims ix_arg_eff n)) :
    BStmt_arg_list spW sp prims ix_arg_list (n + 1) := by
  intro x0 x1 x2 x3 x4 v0 v1 v2 v3 v4 w k b h r0 r1 r2 r3 r4 hb pre
  have key : qcall sp prims uc (n + 1) ix_arg_list [v0, v1, v2, v3, v4] = some (w, k) ∧ Cost_arg_list (n + 1) x0 x1 x2 x3 x4 = k := by
    rw [qcall_succ np fnW] at h
    rw [qcall_succ np fn]
    simp only [src_arg_list, List.length_cons, List.length_nil, if_true] at h ⊢
    rw [Pre_arg_list.eq_def] at pre
    simp only at pre
    budget Cost_arg_list
  exact ⟨key.1, key.2, back.out (pcall_of_q key.1) r0 r1 r2 r3 r4⟩

theorem bstep_eff_args_bound {spW sp : SrcProgram} {prims : Prims} {ix_eff_args_bound ix_minus ix_unbox_of_mini_selfhost_List_mini_selfhost_CTree ix_unbox_of_mini_selfhost_List_mini_selfhost_MEff ix_empty_of_mini_selfhost_MEff ix_has_ty ix_eff_of ix_has_tys ix_bound_args ix_checked_bound ix_arg_expected ix_eff_arg_next ix_view_of ix_cons_bound ix_bind_arg : Nat}
    (fnW : spW.funcs[ix_eff_args_bound]? = some (src_eff_args_bound ix_minus ix_unbox_of_mini_selfhost_List_mini_selfhost_CTree ix_unbox_of_mini_selfhost_List_mini_selfhost_MEff ix_empty_of_mini_selfhost_MEff ix_has_ty ix_eff_of ix_has_tys ix_bound_args ix_eff_args_bound ix_checked_bound ix_arg_expected ix_eff_arg_next ix_view_of ix_cons_bound ix_bind_arg)) (fn : sp.funcs[ix_eff_args_bound]? = some (src_eff_args_bound ix_minus ix_unbox_of_mini_selfhost_List_mini_selfhost_CTree ix_unbox_of_mini_selfhost_List_mini_selfhost_MEff ix_empty_of_mini_selfhost_MEff ix_has_ty ix_eff_of ix_has_tys ix_bound_args ix_eff_args_bound ix_checked_bound ix_arg_expected ix_eff_arg_next ix_view_of ix_cons_bound ix_bind_arg))
    (np : prims.isPrim ix_eff_args_bound = false)
    (back : Certified (∀ {n : Nat}, Stmt_eff_args_bound sp prims ix_eff_args_bound n))
    (b_minus : Certified (∀ {n : Nat}, BStmt_minus spW sp prims ix_minus n))
    (pp_unbox_of_mini_selfhost_List_mini_selfhost_CTree : prims.isPrim ix_unbox_of_mini_selfhost_List_mini_selfhost_CTree = true) (bx_unbox_of_mini_selfhost_List_mini_selfhost_CTree : prims.boxed.contains ix_unbox_of_mini_selfhost_List_mini_selfhost_CTree = false)
    (pp_unbox_of_mini_selfhost_List_mini_selfhost_MEff : prims.isPrim ix_unbox_of_mini_selfhost_List_mini_selfhost_MEff = true) (bx_unbox_of_mini_selfhost_List_mini_selfhost_MEff : prims.boxed.contains ix_unbox_of_mini_selfhost_List_mini_selfhost_MEff = false)
    (b_empty_of_mini_selfhost_MEff : Certified (∀ {n : Nat}, BStmt_empty_of_mini_selfhost_MEff spW sp prims ix_empty_of_mini_selfhost_MEff n))
    (b_has_ty : Certified (∀ {n : Nat}, BStmt_has_ty spW sp prims ix_has_ty n))
    (b_has_tys : Certified (∀ {n : Nat}, BStmt_has_tys spW sp prims ix_has_tys n))
    (b_bound_args : Certified (∀ {n : Nat}, BStmt_bound_args spW sp prims ix_bound_args n))
    (b_checked_bound : Certified (∀ {n : Nat}, BStmt_checked_bound spW sp prims ix_checked_bound n))
    (b_arg_expected : Certified (∀ {n : Nat}, BStmt_arg_expected spW sp prims ix_arg_expected n))
    (b_view_of : Certified (∀ {n : Nat}, BStmt_view_of spW sp prims ix_view_of n))
    (b_cons_bound : Certified (∀ {n : Nat}, BStmt_cons_bound spW sp prims ix_cons_bound n))
    (b_bind_arg : Certified (∀ {n : Nat}, BStmt_bind_arg spW sp prims ix_bind_arg n)) {n : Nat}
    (bih_eff_of : Certified (BStmt_eff_of spW sp prims ix_eff_of n))
    (bih_eff_args_bound : Certified (BStmt_eff_args_bound spW sp prims ix_eff_args_bound n))
    (bih_eff_arg_next : Certified (BStmt_eff_arg_next spW sp prims ix_eff_arg_next n)) :
    BStmt_eff_args_bound spW sp prims ix_eff_args_bound (n + 1) := by
  intro x0 x1 x2 x3 x4 x5 x6 x7 x8 v0 v1 v2 v3 v4 v5 v6 v7 v8 w k b h r0 r1 r2 r3 r4 r5 r6 r7 r8 hb pre
  have key : qcall sp prims uc (n + 1) ix_eff_args_bound [v0, v1, v2, v3, v4, v5, v6, v7, v8] = some (w, k) ∧ Cost_eff_args_bound (n + 1) x0 x1 x2 x3 x4 x5 x6 x7 x8 = k := by
    rw [qcall_succ np fnW] at h
    rw [qcall_succ np fn]
    simp only [src_eff_args_bound, List.length_cons, List.length_nil, if_true] at h ⊢
    rw [Pre_eff_args_bound.eq_def] at pre
    simp only at pre
    budget Cost_eff_args_bound
  exact ⟨key.1, key.2, back.out (pcall_of_q key.1) r0 r1 r2 r3 r4 r5 r6 r7 r8⟩

theorem bstep_eff_arm {spW sp : SrcProgram} {prims : Prims} {ix_eff_arm ix_minus ix_empty_of_usize ix_node_prod ix_list_items ix_kid ix_path_spellings ix_p_pattern_ident ix_arm_named ix_p_pattern_plain ix_binders_of ix_eff_arm_bound : Nat}
    (fnW : spW.funcs[ix_eff_arm]? = some (src_eff_arm ix_minus ix_empty_of_usize ix_node_prod ix_list_items ix_kid ix_path_spellings ix_p_pattern_ident ix_arm_named ix_p_pattern_plain ix_binders_of ix_eff_arm_bound)) (fn : sp.funcs[ix_eff_arm]? = some (src_eff_arm ix_minus ix_empty_of_usize ix_node_prod ix_list_items ix_kid ix_path_spellings ix_p_pattern_ident ix_arm_named ix_p_pattern_plain ix_binders_of ix_eff_arm_bound))
    (np : prims.isPrim ix_eff_arm = false)
    (back : Certified (∀ {n : Nat}, Stmt_eff_arm sp prims ix_eff_arm n))
    (b_minus : Certified (∀ {n : Nat}, BStmt_minus spW sp prims ix_minus n))
    (b_empty_of_usize : Certified (∀ {n : Nat}, BStmt_empty_of_usize spW sp prims ix_empty_of_usize n))
    (b_node_prod : Certified (∀ {n : Nat}, BStmt_node_prod spW sp prims ix_node_prod n))
    (b_list_items : Certified (∀ {n : Nat}, BStmt_list_items spW sp prims ix_list_items n))
    (b_kid : Certified (∀ {n : Nat}, BStmt_kid spW sp prims ix_kid n))
    (b_path_spellings : Certified (∀ {n : Nat}, BStmt_path_spellings spW sp prims ix_path_spellings n))
    (b_p_pattern_ident : Certified (∀ {n : Nat}, BStmt_p_pattern_ident spW sp prims ix_p_pattern_ident n))
    (b_arm_named : Certified (∀ {n : Nat}, BStmt_arm_named spW sp prims ix_arm_named n))
    (b_p_pattern_plain : Certified (∀ {n : Nat}, BStmt_p_pattern_plain spW sp prims ix_p_pattern_plain n))
    (b_binders_of : Certified (∀ {n : Nat}, BStmt_binders_of spW sp prims ix_binders_of n)) {n : Nat}
    (bih_eff_arm_bound : Certified (BStmt_eff_arm_bound spW sp prims ix_eff_arm_bound n)) :
    BStmt_eff_arm spW sp prims ix_eff_arm (n + 1) := by
  intro x0 x1 x2 x3 x4 x5 x6 v0 v1 v2 v3 v4 v5 v6 w k b h r0 r1 r2 r3 r4 r5 r6 hb pre
  have key : qcall sp prims uc (n + 1) ix_eff_arm [v0, v1, v2, v3, v4, v5, v6] = some (w, k) ∧ Cost_eff_arm (n + 1) x0 x1 x2 x3 x4 x5 x6 = k := by
    rw [qcall_succ np fnW] at h
    rw [qcall_succ np fn]
    simp only [src_eff_arm, List.length_cons, List.length_nil, if_true] at h ⊢
    rw [Pre_eff_arm.eq_def] at pre
    simp only at pre
    budget Cost_eff_arm
  exact ⟨key.1, key.2, back.out (pcall_of_q key.1) r0 r1 r2 r3 r4 r5 r6⟩

theorem bstep_arg_eff {spW sp : SrcProgram} {prims : Prims} {ix_arg_eff ix_minus ix_eff_of ix_string_init : Nat}
    (fnW : spW.funcs[ix_arg_eff]? = some (src_arg_eff ix_minus ix_eff_of ix_string_init)) (fn : sp.funcs[ix_arg_eff]? = some (src_arg_eff ix_minus ix_eff_of ix_string_init))
    (np : prims.isPrim ix_arg_eff = false)
    (back : Certified (∀ {n : Nat}, Stmt_arg_eff sp prims ix_arg_eff n))
    (b_minus : Certified (∀ {n : Nat}, BStmt_minus spW sp prims ix_minus n))
    (b_string_init : Certified (∀ {n : Nat}, BStmt_string_init spW sp prims ix_string_init n)) {n : Nat}
    (bih_eff_of : Certified (BStmt_eff_of spW sp prims ix_eff_of n)) :
    BStmt_arg_eff spW sp prims ix_arg_eff (n + 1) := by
  intro x0 x1 x2 x3 x4 v0 v1 v2 v3 v4 w k b h r0 r1 r2 r3 r4 hb pre
  have key : qcall sp prims uc (n + 1) ix_arg_eff [v0, v1, v2, v3, v4] = some (w, k) ∧ Cost_arg_eff (n + 1) x0 x1 x2 x3 x4 = k := by
    rw [qcall_succ np fnW] at h
    rw [qcall_succ np fn]
    simp only [src_arg_eff, List.length_cons, List.length_nil, if_true] at h ⊢
    rw [Pre_arg_eff.eq_def] at pre
    simp only at pre
    budget Cost_arg_eff
  exact ⟨key.1, key.2, back.out (pcall_of_q key.1) r0 r1 r2 r3 r4⟩

theorem bstep_eff_arg_next {spW sp : SrcProgram} {prims : Prims} {ix_eff_arg_next ix_minus ix_empty_of_mini_selfhost_MEff ix_eff_args_bound ix_cons_bound ix_bind_arg : Nat}
    (fnW : spW.funcs[ix_eff_arg_next]? = some (src_eff_arg_next ix_minus ix_empty_of_mini_selfhost_MEff ix_eff_args_bound ix_cons_bound ix_bind_arg)) (fn : sp.funcs[ix_eff_arg_next]? = some (src_eff_arg_next ix_minus ix_empty_of_mini_selfhost_MEff ix_eff_args_bound ix_cons_bound ix_bind_arg))
    (np : prims.isPrim ix_eff_arg_next = false)
    (back : Certified (∀ {n : Nat}, Stmt_eff_arg_next sp prims ix_eff_arg_next n))
    (b_minus : Certified (∀ {n : Nat}, BStmt_minus spW sp prims ix_minus n))
    (b_empty_of_mini_selfhost_MEff : Certified (∀ {n : Nat}, BStmt_empty_of_mini_selfhost_MEff spW sp prims ix_empty_of_mini_selfhost_MEff n))
    (b_cons_bound : Certified (∀ {n : Nat}, BStmt_cons_bound spW sp prims ix_cons_bound n))
    (b_bind_arg : Certified (∀ {n : Nat}, BStmt_bind_arg spW sp prims ix_bind_arg n)) {n : Nat}
    (bih_eff_args_bound : Certified (BStmt_eff_args_bound spW sp prims ix_eff_args_bound n)) :
    BStmt_eff_arg_next spW sp prims ix_eff_arg_next (n + 1) := by
  intro x0 x1 x2 x3 x4 x5 x6 x7 x8 x9 v0 v1 v2 v3 v4 v5 v6 v7 v8 v9 w k b h r0 r1 r2 r3 r4 r5 r6 r7 r8 r9 hb pre
  have key : qcall sp prims uc (n + 1) ix_eff_arg_next [v0, v1, v2, v3, v4, v5, v6, v7, v8, v9] = some (w, k) ∧ Cost_eff_arg_next (n + 1) x0 x1 x2 x3 x4 x5 x6 x7 x8 x9 = k := by
    rw [qcall_succ np fnW] at h
    rw [qcall_succ np fn]
    simp only [src_eff_arg_next, List.length_cons, List.length_nil, if_true] at h ⊢
    rw [Pre_eff_arg_next.eq_def] at pre
    simp only at pre
    budget Cost_eff_arg_next
  exact ⟨key.1, key.2, back.out (pcall_of_q key.1) r0 r1 r2 r3 r4 r5 r6 r7 r8 r9⟩

theorem bstep_eff_arm_bound {spW sp : SrcProgram} {prims : Prims} {ix_eff_arm_bound ix_minus ix_eff_of ix_arm_eff ix_diverge_arm : Nat}
    (fnW : spW.funcs[ix_eff_arm_bound]? = some (src_eff_arm_bound ix_minus ix_eff_of ix_arm_eff ix_diverge_arm)) (fn : sp.funcs[ix_eff_arm_bound]? = some (src_eff_arm_bound ix_minus ix_eff_of ix_arm_eff ix_diverge_arm))
    (np : prims.isPrim ix_eff_arm_bound = false)
    (back : Certified (∀ {n : Nat}, Stmt_eff_arm_bound sp prims ix_eff_arm_bound n))
    (b_minus : Certified (∀ {n : Nat}, BStmt_minus spW sp prims ix_minus n))
    (b_arm_eff : Certified (∀ {n : Nat}, BStmt_arm_eff spW sp prims ix_arm_eff n))
    (b_diverge_arm : Certified (∀ {n : Nat}, BStmt_diverge_arm spW sp prims ix_diverge_arm n)) {n : Nat}
    (bih_eff_of : Certified (BStmt_eff_of spW sp prims ix_eff_of n)) :
    BStmt_eff_arm_bound spW sp prims ix_eff_arm_bound (n + 1) := by
  intro x0 x1 x2 x3 x4 v0 v1 v2 v3 v4 w k b h r0 r1 r2 r3 r4 hb pre
  have key : qcall sp prims uc (n + 1) ix_eff_arm_bound [v0, v1, v2, v3, v4] = some (w, k) ∧ Cost_eff_arm_bound (n + 1) x0 x1 x2 x3 x4 = k := by
    rw [qcall_succ np fnW] at h
    rw [qcall_succ np fn]
    simp only [src_eff_arm_bound, List.length_cons, List.length_nil, if_true] at h ⊢
    rw [Pre_eff_arm_bound.eq_def] at pre
    simp only at pre
    budget Cost_eff_arm_bound
  exact ⟨key.1, key.2, back.out (pcall_of_q key.1) r0 r1 r2 r3 r4⟩

theorem bproof_is_str_type {spW sp : SrcProgram} {prims : Prims} {ix_is_str_type ix_node_prod ix_kid ix_single_of_mini_selfhost_List_usize ix_p_type_ident ix_p_type_args_none ix_type_path_spellings ix_is_path ix_text_str : Nat}
    (fnW : spW.funcs[ix_is_str_type]? = some (src_is_str_type ix_node_prod ix_kid ix_single_of_mini_selfhost_List_usize ix_p_type_ident ix_p_type_args_none ix_type_path_spellings ix_is_path ix_text_str)) (fn : sp.funcs[ix_is_str_type]? = some (src_is_str_type ix_node_prod ix_kid ix_single_of_mini_selfhost_List_usize ix_p_type_ident ix_p_type_args_none ix_type_path_spellings ix_is_path ix_text_str))
    (np : prims.isPrim ix_is_str_type = false)
    (back : Certified (∀ {n : Nat}, Stmt_is_str_type sp prims ix_is_str_type n))
    (b_node_prod : Certified (∀ {n : Nat}, BStmt_node_prod spW sp prims ix_node_prod n))
    (b_kid : Certified (∀ {n : Nat}, BStmt_kid spW sp prims ix_kid n))
    (b_single_of_mini_selfhost_List_usize : Certified (∀ {n : Nat}, BStmt_single_of_mini_selfhost_List_usize spW sp prims ix_single_of_mini_selfhost_List_usize n))
    (b_p_type_ident : Certified (∀ {n : Nat}, BStmt_p_type_ident spW sp prims ix_p_type_ident n))
    (b_p_type_args_none : Certified (∀ {n : Nat}, BStmt_p_type_args_none spW sp prims ix_p_type_args_none n))
    (b_type_path_spellings : Certified (∀ {n : Nat}, BStmt_type_path_spellings spW sp prims ix_type_path_spellings n))
    (b_is_path : Certified (∀ {n : Nat}, BStmt_is_path spW sp prims ix_is_path n))
    (b_text_str : Certified (∀ {n : Nat}, BStmt_text_str spW sp prims ix_text_str n)) {n : Nat} :
    BStmt_is_str_type spW sp prims ix_is_str_type n := by
  intro x0 x1 v0 v1 w k h r0 r1
  rcases n with _ | n
  · simp only [qcall_zero, reduceCtorEq] at h
  have key : qcall sp prims uc (n + 1) ix_is_str_type [v0, v1] = some (w, k) ∧ Cost_is_str_type (n + 1) x0 x1 = k := by
    rw [qcall_succ np fnW] at h
    rw [qcall_succ np fn]
    simp only [src_is_str_type, List.length_cons, List.length_nil, if_true] at h ⊢
    budget Cost_is_str_type
  exact ⟨key.1, key.2, back.out (pcall_of_q key.1) r0 r1⟩

end Lanius.Faithful.SelfBudget
