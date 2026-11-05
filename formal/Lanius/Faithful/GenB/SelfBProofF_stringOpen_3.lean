module

public import Lanius.Faithful.BudgetTactic
public import Lanius.Faithful.Gen.SelfRep
public import Lanius.Faithful.Gen.SelfSrcF_stringOpen
public import Lanius.Faithful.Gen.SelfStmtF_stringOpen
public import Lanius.Faithful.GenB.SelfBStmtF_Inline_pLeTail
public import Lanius.Faithful.GenB.SelfBStmtF_Inline_pPathMore
public import Lanius.Faithful.GenB.SelfBStmtF_argView
public import Lanius.Faithful.GenB.SelfBStmtF_consBinder
public import Lanius.Faithful.GenB.SelfBStmtF_fieldValue
public import Lanius.Faithful.GenB.SelfBStmtF_fnInstRet
public import Lanius.Faithful.GenB.SelfBStmtF_hasConst
public import Lanius.Faithful.GenB.SelfBStmtF_hasKids
public import Lanius.Faithful.GenB.SelfBStmtF_isEmptyUsize
public import Lanius.Faithful.GenB.SelfBStmtF_isFnPath
public import Lanius.Faithful.GenB.SelfBStmtF_itemOf
public import Lanius.Faithful.GenB.SelfBStmtF_noBlock
public import Lanius.Faithful.GenB.SelfBStmtF_noToken
public import Lanius.Faithful.GenB.SelfBStmtF_noTrees
public import Lanius.Faithful.GenB.SelfBStmtF_paramGoals
public import Lanius.Faithful.GenB.SelfBStmtF_projection
public import Lanius.Faithful.GenB.SelfBStmtF_purePart
public import Lanius.Faithful.GenB.SelfBStmtF_rootInsts
public import Lanius.Faithful.GenB.SelfBStmtF_stringOpen
public import Lanius.Faithful.GenB.SelfBStmtF_typeDeclAt
public import Lanius.Faithful.GenB.SelfBStmtN0
public import Lanius.Faithful.GenB.SelfBStmtN1
public import Lanius.Faithful.GenB.SelfBStmtN2
public import Lanius.Faithful.GenB.SelfBStmtN3
public import Lanius.Faithful.GenB.SelfBStmtN4
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
programs that hold the functions (group F_stringOpen, part 3). Do not edit. -/

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

theorem bstep_eff_step {spW sp : SrcProgram} {prims : Prims} {ix_eff_step ix_minus ix_node_prod ix_list_items ix_kid ix_field_text_Token_of_mini_selfhost_Token ix_kid_token ix_p_member_type_args_none ix_eff_of ix_p_postfix_member ix_p_postfix_call ix_p_postfix_index ix_x_index_of ix_eff_chain ix_member_args ix_eff_found_with ix_single_of_mini_selfhost_MEff ix_eff_ty ix_step_expected ix_method_of_ty ix_field_of_ty ix_eff_place ix_x_at_of ix_eff_slice_local : Nat}
    (fnW : spW.funcs[ix_eff_step]? = some (src_eff_step ix_minus ix_node_prod ix_list_items ix_kid ix_field_text_Token_of_mini_selfhost_Token ix_kid_token ix_p_member_type_args_none ix_eff_of ix_p_postfix_member ix_p_postfix_call ix_p_postfix_index ix_x_index_of ix_eff_chain ix_member_args ix_eff_found_with ix_single_of_mini_selfhost_MEff ix_eff_ty ix_step_expected ix_method_of_ty ix_field_of_ty ix_eff_place ix_x_at_of ix_eff_slice_local)) (fn : sp.funcs[ix_eff_step]? = some (src_eff_step ix_minus ix_node_prod ix_list_items ix_kid ix_field_text_Token_of_mini_selfhost_Token ix_kid_token ix_p_member_type_args_none ix_eff_of ix_p_postfix_member ix_p_postfix_call ix_p_postfix_index ix_x_index_of ix_eff_chain ix_member_args ix_eff_found_with ix_single_of_mini_selfhost_MEff ix_eff_ty ix_step_expected ix_method_of_ty ix_field_of_ty ix_eff_place ix_x_at_of ix_eff_slice_local))
    (np : prims.isPrim ix_eff_step = false)
    (back : Certified (∀ {n : Nat}, Stmt_eff_step sp prims ix_eff_step n))
    (b_minus : Certified (∀ {n : Nat}, BStmt_minus spW sp prims ix_minus n))
    (b_node_prod : Certified (∀ {n : Nat}, BStmt_node_prod spW sp prims ix_node_prod n))
    (b_list_items : Certified (∀ {n : Nat}, BStmt_list_items spW sp prims ix_list_items n))
    (b_kid : Certified (∀ {n : Nat}, BStmt_kid spW sp prims ix_kid n))
    (b_field_text_Token_of_mini_selfhost_Token : Certified (∀ {n : Nat}, BStmt_field_text_Token_of_mini_selfhost_Token spW sp prims ix_field_text_Token_of_mini_selfhost_Token n))
    (b_kid_token : Certified (∀ {n : Nat}, BStmt_kid_token spW sp prims ix_kid_token n))
    (b_p_member_type_args_none : Certified (∀ {n : Nat}, BStmt_p_member_type_args_none spW sp prims ix_p_member_type_args_none n))
    (b_p_postfix_member : Certified (∀ {n : Nat}, BStmt_p_postfix_member spW sp prims ix_p_postfix_member n))
    (b_p_postfix_call : Certified (∀ {n : Nat}, BStmt_p_postfix_call spW sp prims ix_p_postfix_call n))
    (b_p_postfix_index : Certified (∀ {n : Nat}, BStmt_p_postfix_index spW sp prims ix_p_postfix_index n))
    (b_x_index_of : Certified (∀ {n : Nat}, BStmt_x_index_of spW sp prims ix_x_index_of n))
    (b_member_args : Certified (∀ {n : Nat}, BStmt_member_args spW sp prims ix_member_args n))
    (b_single_of_mini_selfhost_MEff : Certified (∀ {n : Nat}, BStmt_single_of_mini_selfhost_MEff spW sp prims ix_single_of_mini_selfhost_MEff n))
    (b_eff_ty : Certified (∀ {n : Nat}, BStmt_eff_ty spW sp prims ix_eff_ty n))
    (b_step_expected : Certified (∀ {n : Nat}, BStmt_step_expected spW sp prims ix_step_expected n))
    (b_method_of_ty : Certified (∀ {n : Nat}, BStmt_method_of_ty spW sp prims ix_method_of_ty n))
    (b_field_of_ty : Certified (∀ {n : Nat}, BStmt_field_of_ty spW sp prims ix_field_of_ty n))
    (b_eff_place : Certified (∀ {n : Nat}, BStmt_eff_place spW sp prims ix_eff_place n))
    (b_x_at_of : Certified (∀ {n : Nat}, BStmt_x_at_of spW sp prims ix_x_at_of n))
    (b_eff_slice_local : Certified (∀ {n : Nat}, BStmt_eff_slice_local spW sp prims ix_eff_slice_local n)) {n : Nat}
    (bih_eff_of : Certified (BStmt_eff_of spW sp prims ix_eff_of n))
    (bih_eff_chain : Certified (BStmt_eff_chain spW sp prims ix_eff_chain n))
    (bih_eff_found_with : Certified (BStmt_eff_found_with spW sp prims ix_eff_found_with n)) :
    BStmt_eff_step spW sp prims ix_eff_step (n + 1) := by
  intro x0 x1 x2 x3 x4 x5 v0 v1 v2 v3 v4 v5 w k b h r0 r1 r2 r3 r4 r5 hb pre
  have key : qcall sp prims uc (n + 1) ix_eff_step [v0, v1, v2, v3, v4, v5] = some (w, k) ∧ Cost_eff_step (n + 1) x0 x1 x2 x3 x4 x5 = k := by
    rw [qcall_succ np fnW] at h
    rw [qcall_succ np fn]
    simp only [src_eff_step, List.length_cons, List.length_nil, if_true] at h ⊢
    rw [Pre_eff_step.eq_def] at pre
    simp only at pre
    budget Cost_eff_step
  exact ⟨key.1, key.2, back.out (pcall_of_q key.1) r0 r1 r2 r3 r4 r5⟩

theorem bstep_eff_match_enum {spW sp : SrcProgram} {prims : Prims} {ix_eff_match_enum ix_minus ix_list_items ix_kid ix_x_match_of ix_eff_arms_ordered ix_zip_variants : Nat}
    (fnW : spW.funcs[ix_eff_match_enum]? = some (src_eff_match_enum ix_minus ix_list_items ix_kid ix_x_match_of ix_eff_arms_ordered ix_zip_variants)) (fn : sp.funcs[ix_eff_match_enum]? = some (src_eff_match_enum ix_minus ix_list_items ix_kid ix_x_match_of ix_eff_arms_ordered ix_zip_variants))
    (np : prims.isPrim ix_eff_match_enum = false)
    (back : Certified (∀ {n : Nat}, Stmt_eff_match_enum sp prims ix_eff_match_enum n))
    (b_minus : Certified (∀ {n : Nat}, BStmt_minus spW sp prims ix_minus n))
    (b_list_items : Certified (∀ {n : Nat}, BStmt_list_items spW sp prims ix_list_items n))
    (b_kid : Certified (∀ {n : Nat}, BStmt_kid spW sp prims ix_kid n))
    (b_x_match_of : Certified (∀ {n : Nat}, BStmt_x_match_of spW sp prims ix_x_match_of n))
    (b_zip_variants : Certified (∀ {n : Nat}, BStmt_zip_variants spW sp prims ix_zip_variants n)) {n : Nat}
    (bih_eff_arms_ordered : Certified (BStmt_eff_arms_ordered spW sp prims ix_eff_arms_ordered n)) :
    BStmt_eff_match_enum spW sp prims ix_eff_match_enum (n + 1) := by
  intro x0 x1 x2 x3 x4 x5 x6 x7 x8 v0 v1 v2 v3 v4 v5 v6 v7 v8 w k b h r0 r1 r2 r3 r4 r5 r6 r7 r8 hb pre
  have key : qcall sp prims uc (n + 1) ix_eff_match_enum [v0, v1, v2, v3, v4, v5, v6, v7, v8] = some (w, k) ∧ Cost_eff_match_enum (n + 1) x0 x1 x2 x3 x4 x5 x6 x7 x8 = k := by
    rw [qcall_succ np fnW] at h
    rw [qcall_succ np fn]
    simp only [src_eff_match_enum, List.length_cons, List.length_nil, if_true] at h ⊢
    rw [Pre_eff_match_enum.eq_def] at pre
    simp only at pre
    budget Cost_eff_match_enum
  exact ⟨key.1, key.2, back.out (pcall_of_q key.1) r0 r1 r2 r3 r4 r5 r6 r7 r8⟩

theorem bstep_eff_fn_path {spW sp : SrcProgram} {prims : Prims} {ix_eff_fn_path ix_minus ix_field_fns_Decls_of_mini_selfhost_Decls ix_get_of_mini_selfhost_FnDecl ix_empty_of_mini_selfhost_MEff ix_bare_ty ix_path_module ix_find_method ix_no_trees ix_is_type_owner ix_find_fn ix_eff_found ix_eff_free : Nat}
    (fnW : spW.funcs[ix_eff_fn_path]? = some (src_eff_fn_path ix_minus ix_field_fns_Decls_of_mini_selfhost_Decls ix_get_of_mini_selfhost_FnDecl ix_empty_of_mini_selfhost_MEff ix_bare_ty ix_path_module ix_find_method ix_no_trees ix_is_type_owner ix_find_fn ix_eff_found ix_eff_free)) (fn : sp.funcs[ix_eff_fn_path]? = some (src_eff_fn_path ix_minus ix_field_fns_Decls_of_mini_selfhost_Decls ix_get_of_mini_selfhost_FnDecl ix_empty_of_mini_selfhost_MEff ix_bare_ty ix_path_module ix_find_method ix_no_trees ix_is_type_owner ix_find_fn ix_eff_found ix_eff_free))
    (np : prims.isPrim ix_eff_fn_path = false)
    (back : Certified (∀ {n : Nat}, Stmt_eff_fn_path sp prims ix_eff_fn_path n))
    (b_minus : Certified (∀ {n : Nat}, BStmt_minus spW sp prims ix_minus n))
    (b_field_fns_Decls_of_mini_selfhost_Decls : Certified (∀ {n : Nat}, BStmt_field_fns_Decls_of_mini_selfhost_Decls spW sp prims ix_field_fns_Decls_of_mini_selfhost_Decls n))
    (b_get_of_mini_selfhost_FnDecl : Certified (∀ {n : Nat}, BStmt_get_of_mini_selfhost_FnDecl spW sp prims ix_get_of_mini_selfhost_FnDecl n))
    (b_empty_of_mini_selfhost_MEff : Certified (∀ {n : Nat}, BStmt_empty_of_mini_selfhost_MEff spW sp prims ix_empty_of_mini_selfhost_MEff n))
    (b_bare_ty : Certified (∀ {n : Nat}, BStmt_bare_ty spW sp prims ix_bare_ty n))
    (b_path_module : Certified (∀ {n : Nat}, BStmt_path_module spW sp prims ix_path_module n))
    (b_find_method : Certified (∀ {n : Nat}, BStmt_find_method spW sp prims ix_find_method n))
    (b_no_trees : Certified (∀ {n : Nat}, BStmt_no_trees spW sp prims ix_no_trees n))
    (b_is_type_owner : Certified (∀ {n : Nat}, BStmt_is_type_owner spW sp prims ix_is_type_owner n))
    (b_find_fn : Certified (∀ {n : Nat}, BStmt_find_fn spW sp prims ix_find_fn n)) {n : Nat}
    (bih_eff_found : Certified (BStmt_eff_found spW sp prims ix_eff_found n))
    (bih_eff_free : Certified (BStmt_eff_free spW sp prims ix_eff_free n)) :
    BStmt_eff_fn_path spW sp prims ix_eff_fn_path (n + 1) := by
  intro x0 x1 x2 x3 x4 x5 x6 v0 v1 v2 v3 v4 v5 v6 w k b h r0 r1 r2 r3 r4 r5 r6 hb pre
  have key : qcall sp prims uc (n + 1) ix_eff_fn_path [v0, v1, v2, v3, v4, v5, v6] = some (w, k) ∧ Cost_eff_fn_path (n + 1) x0 x1 x2 x3 x4 x5 x6 = k := by
    rw [qcall_succ np fnW] at h
    rw [qcall_succ np fn]
    simp only [src_eff_fn_path, List.length_cons, List.length_nil, if_true] at h ⊢
    rw [Pre_eff_fn_path.eq_def] at pre
    simp only at pre
    budget Cost_eff_fn_path
  exact ⟨key.1, key.2, back.out (pcall_of_q key.1) r0 r1 r2 r3 r4 r5 r6⟩

theorem bstep_eff_bound {spW sp : SrcProgram} {prims : Prims} {ix_eff_bound ix_minus ix_eff_infer : Nat}
    (fnW : spW.funcs[ix_eff_bound]? = some (src_eff_bound ix_minus ix_eff_infer)) (fn : sp.funcs[ix_eff_bound]? = some (src_eff_bound ix_minus ix_eff_infer))
    (np : prims.isPrim ix_eff_bound = false)
    (back : Certified (∀ {n : Nat}, Stmt_eff_bound sp prims ix_eff_bound n))
    (b_minus : Certified (∀ {n : Nat}, BStmt_minus spW sp prims ix_minus n)) {n : Nat}
    (bih_eff_infer : Certified (BStmt_eff_infer spW sp prims ix_eff_infer n)) :
    BStmt_eff_bound spW sp prims ix_eff_bound (n + 1) := by
  intro x0 x1 x2 x3 x4 x5 x6 x7 x8 v0 v1 v2 v3 v4 v5 v6 v7 v8 w k b h r0 r1 r2 r3 r4 r5 r6 r7 r8 hb pre
  have key : qcall sp prims uc (n + 1) ix_eff_bound [v0, v1, v2, v3, v4, v5, v6, v7, v8] = some (w, k) ∧ Cost_eff_bound (n + 1) x0 x1 x2 x3 x4 x5 x6 x7 x8 = k := by
    rw [qcall_succ np fnW] at h
    rw [qcall_succ np fn]
    simp only [src_eff_bound, List.length_cons, List.length_nil, if_true] at h ⊢
    rw [Pre_eff_bound.eq_def] at pre
    simp only at pre
    budget Cost_eff_bound
  exact ⟨key.1, key.2, back.out (pcall_of_q key.1) r0 r1 r2 r3 r4 r5 r6 r7 r8⟩

theorem bstep_eff_arms_ordered {spW sp : SrcProgram} {prims : Prims} {ix_eff_arms_ordered ix_minus ix_match_order ix_eff_arms : Nat}
    (fnW : spW.funcs[ix_eff_arms_ordered]? = some (src_eff_arms_ordered ix_minus ix_match_order ix_eff_arms)) (fn : sp.funcs[ix_eff_arms_ordered]? = some (src_eff_arms_ordered ix_minus ix_match_order ix_eff_arms))
    (np : prims.isPrim ix_eff_arms_ordered = false)
    (back : Certified (∀ {n : Nat}, Stmt_eff_arms_ordered sp prims ix_eff_arms_ordered n))
    (b_minus : Certified (∀ {n : Nat}, BStmt_minus spW sp prims ix_minus n))
    (b_match_order : Certified (∀ {n : Nat}, BStmt_match_order spW sp prims ix_match_order n)) {n : Nat}
    (bih_eff_arms : Certified (BStmt_eff_arms spW sp prims ix_eff_arms n)) :
    BStmt_eff_arms_ordered spW sp prims ix_eff_arms_ordered (n + 1) := by
  intro x0 x1 x2 x3 x4 x5 x6 v0 v1 v2 v3 v4 v5 v6 w k b h r0 r1 r2 r3 r4 r5 r6 hb pre
  have key : qcall sp prims uc (n + 1) ix_eff_arms_ordered [v0, v1, v2, v3, v4, v5, v6] = some (w, k) ∧ Cost_eff_arms_ordered (n + 1) x0 x1 x2 x3 x4 x5 x6 = k := by
    rw [qcall_succ np fnW] at h
    rw [qcall_succ np fn]
    simp only [src_eff_arms_ordered, List.length_cons, List.length_nil, if_true] at h ⊢
    rw [Pre_eff_arms_ordered.eq_def] at pre
    simp only at pre
    budget Cost_eff_arms_ordered
  exact ⟨key.1, key.2, back.out (pcall_of_q key.1) r0 r1 r2 r3 r4 r5 r6⟩

theorem bstep_eff_found {spW sp : SrcProgram} {prims : Prims} {ix_eff_found ix_minus ix_field_fns_Decls_of_mini_selfhost_Decls ix_get_of_mini_selfhost_FnDecl ix_eff_infer : Nat}
    (fnW : spW.funcs[ix_eff_found]? = some (src_eff_found ix_minus ix_field_fns_Decls_of_mini_selfhost_Decls ix_get_of_mini_selfhost_FnDecl ix_eff_infer)) (fn : sp.funcs[ix_eff_found]? = some (src_eff_found ix_minus ix_field_fns_Decls_of_mini_selfhost_Decls ix_get_of_mini_selfhost_FnDecl ix_eff_infer))
    (np : prims.isPrim ix_eff_found = false)
    (back : Certified (∀ {n : Nat}, Stmt_eff_found sp prims ix_eff_found n))
    (b_minus : Certified (∀ {n : Nat}, BStmt_minus spW sp prims ix_minus n))
    (b_field_fns_Decls_of_mini_selfhost_Decls : Certified (∀ {n : Nat}, BStmt_field_fns_Decls_of_mini_selfhost_Decls spW sp prims ix_field_fns_Decls_of_mini_selfhost_Decls n))
    (b_get_of_mini_selfhost_FnDecl : Certified (∀ {n : Nat}, BStmt_get_of_mini_selfhost_FnDecl spW sp prims ix_get_of_mini_selfhost_FnDecl n)) {n : Nat}
    (bih_eff_infer : Certified (BStmt_eff_infer spW sp prims ix_eff_infer n)) :
    BStmt_eff_found spW sp prims ix_eff_found (n + 1) := by
  intro x0 x1 x2 x3 x4 x5 x6 v0 v1 v2 v3 v4 v5 v6 w k b h r0 r1 r2 r3 r4 r5 r6 hb pre
  have key : qcall sp prims uc (n + 1) ix_eff_found [v0, v1, v2, v3, v4, v5, v6] = some (w, k) ∧ Cost_eff_found (n + 1) x0 x1 x2 x3 x4 x5 x6 = k := by
    rw [qcall_succ np fnW] at h
    rw [qcall_succ np fn]
    simp only [src_eff_found, List.length_cons, List.length_nil, if_true] at h ⊢
    rw [Pre_eff_found.eq_def] at pre
    simp only at pre
    budget Cost_eff_found
  exact ⟨key.1, key.2, back.out (pcall_of_q key.1) r0 r1 r2 r3 r4 r5 r6⟩

theorem bstep_eff_free {spW sp : SrcProgram} {prims : Prims} {ix_eff_free ix_minus ix_boxed_of_mini_selfhost_List_mini_selfhost_MEff ix_empty_of_mini_selfhost_MEff ix_eff_list ix_empty_of_mini_selfhost_Bind ix_has_tys ix_no_trees ix_eff_infer ix_explicit_inst ix_checked_effs ix_param_expects ix_views_of : Nat}
    (fnW : spW.funcs[ix_eff_free]? = some (src_eff_free ix_minus ix_boxed_of_mini_selfhost_List_mini_selfhost_MEff ix_empty_of_mini_selfhost_MEff ix_eff_list ix_empty_of_mini_selfhost_Bind ix_has_tys ix_no_trees ix_eff_infer ix_explicit_inst ix_checked_effs ix_param_expects ix_views_of)) (fn : sp.funcs[ix_eff_free]? = some (src_eff_free ix_minus ix_boxed_of_mini_selfhost_List_mini_selfhost_MEff ix_empty_of_mini_selfhost_MEff ix_eff_list ix_empty_of_mini_selfhost_Bind ix_has_tys ix_no_trees ix_eff_infer ix_explicit_inst ix_checked_effs ix_param_expects ix_views_of))
    (np : prims.isPrim ix_eff_free = false)
    (back : Certified (∀ {n : Nat}, Stmt_eff_free sp prims ix_eff_free n))
    (b_minus : Certified (∀ {n : Nat}, BStmt_minus spW sp prims ix_minus n))
    (pp_boxed_of_mini_selfhost_List_mini_selfhost_MEff : prims.isPrim ix_boxed_of_mini_selfhost_List_mini_selfhost_MEff = true) (bx_boxed_of_mini_selfhost_List_mini_selfhost_MEff : prims.boxed.contains ix_boxed_of_mini_selfhost_List_mini_selfhost_MEff = true)
    (b_empty_of_mini_selfhost_MEff : Certified (∀ {n : Nat}, BStmt_empty_of_mini_selfhost_MEff spW sp prims ix_empty_of_mini_selfhost_MEff n))
    (b_empty_of_mini_selfhost_Bind : Certified (∀ {n : Nat}, BStmt_empty_of_mini_selfhost_Bind spW sp prims ix_empty_of_mini_selfhost_Bind n))
    (b_has_tys : Certified (∀ {n : Nat}, BStmt_has_tys spW sp prims ix_has_tys n))
    (b_no_trees : Certified (∀ {n : Nat}, BStmt_no_trees spW sp prims ix_no_trees n))
    (b_explicit_inst : Certified (∀ {n : Nat}, BStmt_explicit_inst spW sp prims ix_explicit_inst n))
    (b_checked_effs : Certified (∀ {n : Nat}, BStmt_checked_effs spW sp prims ix_checked_effs n))
    (b_param_expects : Certified (∀ {n : Nat}, BStmt_param_expects spW sp prims ix_param_expects n))
    (b_views_of : Certified (∀ {n : Nat}, BStmt_views_of spW sp prims ix_views_of n)) {n : Nat}
    (bih_eff_list : Certified (BStmt_eff_list spW sp prims ix_eff_list n))
    (bih_eff_infer : Certified (BStmt_eff_infer spW sp prims ix_eff_infer n)) :
    BStmt_eff_free spW sp prims ix_eff_free (n + 1) := by
  intro x0 x1 x2 x3 x4 x5 x6 x7 v0 v1 v2 v3 v4 v5 v6 v7 w k b h r0 r1 r2 r3 r4 r5 r6 r7 hb pre
  have key : qcall sp prims uc (n + 1) ix_eff_free [v0, v1, v2, v3, v4, v5, v6, v7] = some (w, k) ∧ Cost_eff_free (n + 1) x0 x1 x2 x3 x4 x5 x6 x7 = k := by
    rw [qcall_succ np fnW] at h
    rw [qcall_succ np fn]
    simp only [src_eff_free, List.length_cons, List.length_nil, if_true] at h ⊢
    rw [Pre_eff_free.eq_def] at pre
    simp only at pre
    budget Cost_eff_free
  exact ⟨key.1, key.2, back.out (pcall_of_q key.1) r0 r1 r2 r3 r4 r5 r6 r7⟩

end Lanius.Faithful.SelfBudget
