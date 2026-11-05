module

public import Lanius.Faithful.BudgetTactic
public import Lanius.Faithful.Gen.SelfRep
public import Lanius.Faithful.Gen.SelfSrcF_stringOpen
public import Lanius.Faithful.Gen.SelfStmtF_stringOpen
public import Lanius.Faithful.GenB.SelfBStmtF_Inline_pArrayMore
public import Lanius.Faithful.GenB.SelfBStmtF_Inline_pExpr
public import Lanius.Faithful.GenB.SelfBStmtF_Inline_pIdentPlain
public import Lanius.Faithful.GenB.SelfBStmtF_Inline_pPathMore
public import Lanius.Faithful.GenB.SelfBStmtF_Inline_pStructFieldsMore
public import Lanius.Faithful.GenB.SelfBStmtF_findConst
public import Lanius.Faithful.GenB.SelfBStmtF_floatTyped
public import Lanius.Faithful.GenB.SelfBStmtF_hasConst
public import Lanius.Faithful.GenB.SelfBStmtF_hasKids
public import Lanius.Faithful.GenB.SelfBStmtF_isEmptyUsize
public import Lanius.Faithful.GenB.SelfBStmtF_isFnPath
public import Lanius.Faithful.GenB.SelfBStmtF_isPathCall
public import Lanius.Faithful.GenB.SelfBStmtF_itemOf
public import Lanius.Faithful.GenB.SelfBStmtF_matchTysOrNone
public import Lanius.Faithful.GenB.SelfBStmtF_noBlock
public import Lanius.Faithful.GenB.SelfBStmtF_noToken
public import Lanius.Faithful.GenB.SelfBStmtF_noTrees
public import Lanius.Faithful.GenB.SelfBStmtF_pathRef
public import Lanius.Faithful.GenB.SelfBStmtF_pickTy
public import Lanius.Faithful.GenB.SelfBStmtF_purePart
public import Lanius.Faithful.GenB.SelfBStmtF_sliceHead
public import Lanius.Faithful.GenB.SelfBStmtF_stringOpen
public import Lanius.Faithful.GenB.SelfBStmtF_textSelf
public import Lanius.Faithful.GenB.SelfBStmtF_textSliceLen
public import Lanius.Faithful.GenB.SelfBStmtF_typeDeclAt
public import Lanius.Faithful.GenB.SelfBStmtF_typePathSpellings
public import Lanius.Faithful.GenB.SelfBStmtF_variantIn
public import Lanius.Faithful.GenB.SelfBStmtN2
public import Lanius.Faithful.GenB.SelfBStmtN3
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
programs that hold the functions (group F_stringOpen, part 1). Do not edit. -/

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

theorem bstep_eff_postfix {spW sp : SrcProgram} {prims : Prims} {ix_eff_postfix ix_minus ix_node_prod ix_kid ix_eff_of ix_eff_node ix_p_ident ix_p_ident_plain ix_p_postfix_end ix_p_postfix_call ix_local_of ix_is_path_call ix_eff_path_call ix_is_method_form ix_eff_method ix_p_postfix_index ix_x_index_of ix_eff_chain ix_eff_primary : Nat}
    (fnW : spW.funcs[ix_eff_postfix]? = some (src_eff_postfix ix_minus ix_node_prod ix_kid ix_eff_of ix_eff_node ix_p_ident ix_p_ident_plain ix_p_postfix_end ix_p_postfix_call ix_local_of ix_is_path_call ix_eff_path_call ix_is_method_form ix_eff_method ix_p_postfix_index ix_x_index_of ix_eff_chain ix_eff_primary)) (fn : sp.funcs[ix_eff_postfix]? = some (src_eff_postfix ix_minus ix_node_prod ix_kid ix_eff_of ix_eff_node ix_p_ident ix_p_ident_plain ix_p_postfix_end ix_p_postfix_call ix_local_of ix_is_path_call ix_eff_path_call ix_is_method_form ix_eff_method ix_p_postfix_index ix_x_index_of ix_eff_chain ix_eff_primary))
    (np : prims.isPrim ix_eff_postfix = false)
    (back : Certified (∀ {n : Nat}, Stmt_eff_postfix sp prims ix_eff_postfix n))
    (b_minus : Certified (∀ {n : Nat}, BStmt_minus spW sp prims ix_minus n))
    (b_node_prod : Certified (∀ {n : Nat}, BStmt_node_prod spW sp prims ix_node_prod n))
    (b_kid : Certified (∀ {n : Nat}, BStmt_kid spW sp prims ix_kid n))
    (b_p_ident : Certified (∀ {n : Nat}, BStmt_p_ident spW sp prims ix_p_ident n))
    (b_p_ident_plain : Certified (∀ {n : Nat}, BStmt_p_ident_plain spW sp prims ix_p_ident_plain n))
    (b_p_postfix_end : Certified (∀ {n : Nat}, BStmt_p_postfix_end spW sp prims ix_p_postfix_end n))
    (b_p_postfix_call : Certified (∀ {n : Nat}, BStmt_p_postfix_call spW sp prims ix_p_postfix_call n))
    (b_local_of : Certified (∀ {n : Nat}, BStmt_local_of spW sp prims ix_local_of n))
    (b_is_path_call : Certified (∀ {n : Nat}, BStmt_is_path_call spW sp prims ix_is_path_call n))
    (b_is_method_form : Certified (∀ {n : Nat}, BStmt_is_method_form spW sp prims ix_is_method_form n))
    (b_p_postfix_index : Certified (∀ {n : Nat}, BStmt_p_postfix_index spW sp prims ix_p_postfix_index n))
    (b_x_index_of : Certified (∀ {n : Nat}, BStmt_x_index_of spW sp prims ix_x_index_of n)) {n : Nat}
    (bih_eff_of : Certified (BStmt_eff_of spW sp prims ix_eff_of n))
    (bih_eff_node : Certified (BStmt_eff_node spW sp prims ix_eff_node n))
    (bih_eff_path_call : Certified (BStmt_eff_path_call spW sp prims ix_eff_path_call n))
    (bih_eff_method : Certified (BStmt_eff_method spW sp prims ix_eff_method n))
    (bih_eff_chain : Certified (BStmt_eff_chain spW sp prims ix_eff_chain n))
    (bih_eff_primary : Certified (BStmt_eff_primary spW sp prims ix_eff_primary n)) :
    BStmt_eff_postfix spW sp prims ix_eff_postfix (n + 1) := by
  intro x0 x1 x2 x3 x4 v0 v1 v2 v3 v4 w k b h r0 r1 r2 r3 r4 hb pre
  have key : qcall sp prims uc (n + 1) ix_eff_postfix [v0, v1, v2, v3, v4] = some (w, k) ∧ Cost_eff_postfix (n + 1) x0 x1 x2 x3 x4 = k := by
    rw [qcall_succ np fnW] at h
    rw [qcall_succ np fn]
    simp only [src_eff_postfix, List.length_cons, List.length_nil, if_true] at h ⊢
    rw [Pre_eff_postfix.eq_def] at pre
    simp only at pre
    budget Cost_eff_postfix
  exact ⟨key.1, key.2, back.out (pcall_of_q key.1) r0 r1 r2 r3 r4⟩

theorem bstep_eff_ident {spW sp : SrcProgram} {prims : Prims} {ix_eff_ident ix_minus ix_empty_of_mini_selfhost_CTree ix_node_prod ix_list_items ix_kid ix_field_types_Decls_of_mini_selfhost_Decls ix_path_spellings ix_field_consts_Decls_of_mini_selfhost_Decls ix_get_of_mini_selfhost_TypeDecl ix_type_decl_at ix_split_last ix_path_module ix_p_ident_plain ix_local_of ix_checked_eff ix_has_local ix_has_const ix_find_const ix_eff_variant ix_variant_by_path ix_p_struct_lit ix_eff_literal : Nat}
    (fnW : spW.funcs[ix_eff_ident]? = some (src_eff_ident ix_minus ix_empty_of_mini_selfhost_CTree ix_node_prod ix_list_items ix_kid ix_field_types_Decls_of_mini_selfhost_Decls ix_path_spellings ix_field_consts_Decls_of_mini_selfhost_Decls ix_get_of_mini_selfhost_TypeDecl ix_type_decl_at ix_split_last ix_path_module ix_p_ident_plain ix_local_of ix_checked_eff ix_has_local ix_has_const ix_find_const ix_eff_variant ix_variant_by_path ix_p_struct_lit ix_eff_literal)) (fn : sp.funcs[ix_eff_ident]? = some (src_eff_ident ix_minus ix_empty_of_mini_selfhost_CTree ix_node_prod ix_list_items ix_kid ix_field_types_Decls_of_mini_selfhost_Decls ix_path_spellings ix_field_consts_Decls_of_mini_selfhost_Decls ix_get_of_mini_selfhost_TypeDecl ix_type_decl_at ix_split_last ix_path_module ix_p_ident_plain ix_local_of ix_checked_eff ix_has_local ix_has_const ix_find_const ix_eff_variant ix_variant_by_path ix_p_struct_lit ix_eff_literal))
    (np : prims.isPrim ix_eff_ident = false)
    (back : Certified (∀ {n : Nat}, Stmt_eff_ident sp prims ix_eff_ident n))
    (b_minus : Certified (∀ {n : Nat}, BStmt_minus spW sp prims ix_minus n))
    (b_empty_of_mini_selfhost_CTree : Certified (∀ {n : Nat}, BStmt_empty_of_mini_selfhost_CTree spW sp prims ix_empty_of_mini_selfhost_CTree n))
    (b_node_prod : Certified (∀ {n : Nat}, BStmt_node_prod spW sp prims ix_node_prod n))
    (b_list_items : Certified (∀ {n : Nat}, BStmt_list_items spW sp prims ix_list_items n))
    (b_kid : Certified (∀ {n : Nat}, BStmt_kid spW sp prims ix_kid n))
    (b_field_types_Decls_of_mini_selfhost_Decls : Certified (∀ {n : Nat}, BStmt_field_types_Decls_of_mini_selfhost_Decls spW sp prims ix_field_types_Decls_of_mini_selfhost_Decls n))
    (b_path_spellings : Certified (∀ {n : Nat}, BStmt_path_spellings spW sp prims ix_path_spellings n))
    (b_field_consts_Decls_of_mini_selfhost_Decls : Certified (∀ {n : Nat}, BStmt_field_consts_Decls_of_mini_selfhost_Decls spW sp prims ix_field_consts_Decls_of_mini_selfhost_Decls n))
    (b_get_of_mini_selfhost_TypeDecl : Certified (∀ {n : Nat}, BStmt_get_of_mini_selfhost_TypeDecl spW sp prims ix_get_of_mini_selfhost_TypeDecl n))
    (b_type_decl_at : Certified (∀ {n : Nat}, BStmt_type_decl_at spW sp prims ix_type_decl_at n))
    (b_split_last : Certified (∀ {n : Nat}, BStmt_split_last spW sp prims ix_split_last n))
    (b_path_module : Certified (∀ {n : Nat}, BStmt_path_module spW sp prims ix_path_module n))
    (b_p_ident_plain : Certified (∀ {n : Nat}, BStmt_p_ident_plain spW sp prims ix_p_ident_plain n))
    (b_local_of : Certified (∀ {n : Nat}, BStmt_local_of spW sp prims ix_local_of n))
    (b_checked_eff : Certified (∀ {n : Nat}, BStmt_checked_eff spW sp prims ix_checked_eff n))
    (b_has_local : Certified (∀ {n : Nat}, BStmt_has_local spW sp prims ix_has_local n))
    (b_has_const : Certified (∀ {n : Nat}, BStmt_has_const spW sp prims ix_has_const n))
    (b_find_const : Certified (∀ {n : Nat}, BStmt_find_const spW sp prims ix_find_const n))
    (b_variant_by_path : Certified (∀ {n : Nat}, BStmt_variant_by_path spW sp prims ix_variant_by_path n))
    (b_p_struct_lit : Certified (∀ {n : Nat}, BStmt_p_struct_lit spW sp prims ix_p_struct_lit n)) {n : Nat}
    (bih_eff_variant : Certified (BStmt_eff_variant spW sp prims ix_eff_variant n))
    (bih_eff_literal : Certified (BStmt_eff_literal spW sp prims ix_eff_literal n)) :
    BStmt_eff_ident spW sp prims ix_eff_ident (n + 1) := by
  intro x0 x1 x2 x3 x4 v0 v1 v2 v3 v4 w k b h r0 r1 r2 r3 r4 hb pre
  have key : qcall sp prims uc (n + 1) ix_eff_ident [v0, v1, v2, v3, v4] = some (w, k) ∧ Cost_eff_ident (n + 1) x0 x1 x2 x3 x4 = k := by
    rw [qcall_succ np fnW] at h
    rw [qcall_succ np fn]
    simp only [src_eff_ident, List.length_cons, List.length_nil, if_true] at h ⊢
    rw [Pre_eff_ident.eq_def] at pre
    simp only at pre
    budget Cost_eff_ident
  exact ⟨key.1, key.2, back.out (pcall_of_q key.1) r0 r1 r2 r3 r4⟩

theorem bstep_eff_match {spW sp : SrcProgram} {prims : Prims} {ix_eff_match ix_minus ix_kid ix_eff_of ix_eff_match_on : Nat}
    (fnW : spW.funcs[ix_eff_match]? = some (src_eff_match ix_minus ix_kid ix_eff_of ix_eff_match_on)) (fn : sp.funcs[ix_eff_match]? = some (src_eff_match ix_minus ix_kid ix_eff_of ix_eff_match_on))
    (np : prims.isPrim ix_eff_match = false)
    (back : Certified (∀ {n : Nat}, Stmt_eff_match sp prims ix_eff_match n))
    (b_minus : Certified (∀ {n : Nat}, BStmt_minus spW sp prims ix_minus n))
    (b_kid : Certified (∀ {n : Nat}, BStmt_kid spW sp prims ix_kid n)) {n : Nat}
    (bih_eff_of : Certified (BStmt_eff_of spW sp prims ix_eff_of n))
    (bih_eff_match_on : Certified (BStmt_eff_match_on spW sp prims ix_eff_match_on n)) :
    BStmt_eff_match spW sp prims ix_eff_match (n + 1) := by
  intro x0 x1 x2 x3 x4 v0 v1 v2 v3 v4 w k b h r0 r1 r2 r3 r4 hb pre
  have key : qcall sp prims uc (n + 1) ix_eff_match [v0, v1, v2, v3, v4] = some (w, k) ∧ Cost_eff_match (n + 1) x0 x1 x2 x3 x4 = k := by
    rw [qcall_succ np fnW] at h
    rw [qcall_succ np fn]
    simp only [src_eff_match, List.length_cons, List.length_nil, if_true] at h ⊢
    rw [Pre_eff_match.eq_def] at pre
    simp only at pre
    budget Cost_eff_match
  exact ⟨key.1, key.2, back.out (pcall_of_q key.1) r0 r1 r2 r3 r4⟩

theorem bstep_eff_array {spW sp : SrcProgram} {prims : Prims} {ix_eff_array ix_minus ix_node_prod ix_list_items ix_kid ix_field_text_Token_of_mini_selfhost_Token ix_kid_token ix_p_array_some ix_decimal ix_eff_of ix_p_array_repeat ix_expected_array ix_array_repeat_of ix_array_of ix_eff_list ix_repeat_ty : Nat}
    (fnW : spW.funcs[ix_eff_array]? = some (src_eff_array ix_minus ix_node_prod ix_list_items ix_kid ix_field_text_Token_of_mini_selfhost_Token ix_kid_token ix_p_array_some ix_decimal ix_eff_of ix_p_array_repeat ix_expected_array ix_array_repeat_of ix_array_of ix_eff_list ix_repeat_ty)) (fn : sp.funcs[ix_eff_array]? = some (src_eff_array ix_minus ix_node_prod ix_list_items ix_kid ix_field_text_Token_of_mini_selfhost_Token ix_kid_token ix_p_array_some ix_decimal ix_eff_of ix_p_array_repeat ix_expected_array ix_array_repeat_of ix_array_of ix_eff_list ix_repeat_ty))
    (np : prims.isPrim ix_eff_array = false)
    (back : Certified (∀ {n : Nat}, Stmt_eff_array sp prims ix_eff_array n))
    (b_minus : Certified (∀ {n : Nat}, BStmt_minus spW sp prims ix_minus n))
    (b_node_prod : Certified (∀ {n : Nat}, BStmt_node_prod spW sp prims ix_node_prod n))
    (b_list_items : Certified (∀ {n : Nat}, BStmt_list_items spW sp prims ix_list_items n))
    (b_kid : Certified (∀ {n : Nat}, BStmt_kid spW sp prims ix_kid n))
    (b_field_text_Token_of_mini_selfhost_Token : Certified (∀ {n : Nat}, BStmt_field_text_Token_of_mini_selfhost_Token spW sp prims ix_field_text_Token_of_mini_selfhost_Token n))
    (b_kid_token : Certified (∀ {n : Nat}, BStmt_kid_token spW sp prims ix_kid_token n))
    (b_p_array_some : Certified (∀ {n : Nat}, BStmt_p_array_some spW sp prims ix_p_array_some n))
    (b_decimal : Certified (∀ {n : Nat}, BStmt_decimal spW sp prims ix_decimal n))
    (b_p_array_repeat : Certified (∀ {n : Nat}, BStmt_p_array_repeat spW sp prims ix_p_array_repeat n))
    (b_expected_array : Certified (∀ {n : Nat}, BStmt_expected_array spW sp prims ix_expected_array n))
    (b_array_repeat_of : Certified (∀ {n : Nat}, BStmt_array_repeat_of spW sp prims ix_array_repeat_of n))
    (b_array_of : Certified (∀ {n : Nat}, BStmt_array_of spW sp prims ix_array_of n))
    (b_repeat_ty : Certified (∀ {n : Nat}, BStmt_repeat_ty spW sp prims ix_repeat_ty n)) {n : Nat}
    (bih_eff_of : Certified (BStmt_eff_of spW sp prims ix_eff_of n))
    (bih_eff_list : Certified (BStmt_eff_list spW sp prims ix_eff_list n)) :
    BStmt_eff_array spW sp prims ix_eff_array (n + 1) := by
  intro x0 x1 x2 x3 x4 v0 v1 v2 v3 v4 w k b h r0 r1 r2 r3 r4 hb pre
  have key : qcall sp prims uc (n + 1) ix_eff_array [v0, v1, v2, v3, v4] = some (w, k) ∧ Cost_eff_array (n + 1) x0 x1 x2 x3 x4 = k := by
    rw [qcall_succ np fnW] at h
    rw [qcall_succ np fn]
    simp only [src_eff_array, List.length_cons, List.length_nil, if_true] at h ⊢
    rw [Pre_eff_array.eq_def] at pre
    simp only at pre
    budget Cost_eff_array
  exact ⟨key.1, key.2, back.out (pcall_of_q key.1) r0 r1 r2 r3 r4⟩

theorem bstep_eff_path_call {spW sp : SrcProgram} {prims : Prims} {ix_eff_path_call ix_minus ix_list_items ix_kid ix_path_spellings ix_single_of_mini_selfhost_List_usize ix_is_path ix_alloc_path ix_dealloc_path ix_text_slice_from_raw_parts ix_text_slice_stride ix_stride_arg ix_text_slice_len ix_len_arg ix_path_ref ix_named_split ix_eff_named : Nat}
    (fnW : spW.funcs[ix_eff_path_call]? = some (src_eff_path_call ix_minus ix_list_items ix_kid ix_path_spellings ix_single_of_mini_selfhost_List_usize ix_is_path ix_alloc_path ix_dealloc_path ix_text_slice_from_raw_parts ix_text_slice_stride ix_stride_arg ix_text_slice_len ix_len_arg ix_path_ref ix_named_split ix_eff_named)) (fn : sp.funcs[ix_eff_path_call]? = some (src_eff_path_call ix_minus ix_list_items ix_kid ix_path_spellings ix_single_of_mini_selfhost_List_usize ix_is_path ix_alloc_path ix_dealloc_path ix_text_slice_from_raw_parts ix_text_slice_stride ix_stride_arg ix_text_slice_len ix_len_arg ix_path_ref ix_named_split ix_eff_named))
    (np : prims.isPrim ix_eff_path_call = false)
    (back : Certified (∀ {n : Nat}, Stmt_eff_path_call sp prims ix_eff_path_call n))
    (b_minus : Certified (∀ {n : Nat}, BStmt_minus spW sp prims ix_minus n))
    (b_list_items : Certified (∀ {n : Nat}, BStmt_list_items spW sp prims ix_list_items n))
    (b_kid : Certified (∀ {n : Nat}, BStmt_kid spW sp prims ix_kid n))
    (b_path_spellings : Certified (∀ {n : Nat}, BStmt_path_spellings spW sp prims ix_path_spellings n))
    (b_single_of_mini_selfhost_List_usize : Certified (∀ {n : Nat}, BStmt_single_of_mini_selfhost_List_usize spW sp prims ix_single_of_mini_selfhost_List_usize n))
    (b_is_path : Certified (∀ {n : Nat}, BStmt_is_path spW sp prims ix_is_path n))
    (b_alloc_path : Certified (∀ {n : Nat}, BStmt_alloc_path spW sp prims ix_alloc_path n))
    (b_dealloc_path : Certified (∀ {n : Nat}, BStmt_dealloc_path spW sp prims ix_dealloc_path n))
    (b_text_slice_from_raw_parts : Certified (∀ {n : Nat}, BStmt_text_slice_from_raw_parts spW sp prims ix_text_slice_from_raw_parts n))
    (b_text_slice_stride : Certified (∀ {n : Nat}, BStmt_text_slice_stride spW sp prims ix_text_slice_stride n))
    (b_stride_arg : Certified (∀ {n : Nat}, BStmt_stride_arg spW sp prims ix_stride_arg n))
    (b_text_slice_len : Certified (∀ {n : Nat}, BStmt_text_slice_len spW sp prims ix_text_slice_len n))
    (b_len_arg : Certified (∀ {n : Nat}, BStmt_len_arg spW sp prims ix_len_arg n))
    (b_path_ref : Certified (∀ {n : Nat}, BStmt_path_ref spW sp prims ix_path_ref n))
    (b_named_split : Certified (∀ {n : Nat}, BStmt_named_split spW sp prims ix_named_split n)) {n : Nat}
    (bih_eff_named : Certified (BStmt_eff_named spW sp prims ix_eff_named n)) :
    BStmt_eff_path_call spW sp prims ix_eff_path_call (n + 1) := by
  intro x0 x1 x2 x3 x4 x5 v0 v1 v2 v3 v4 v5 w k b h r0 r1 r2 r3 r4 r5 hb pre
  have key : qcall sp prims uc (n + 1) ix_eff_path_call [v0, v1, v2, v3, v4, v5] = some (w, k) ∧ Cost_eff_path_call (n + 1) x0 x1 x2 x3 x4 x5 = k := by
    rw [qcall_succ np fnW] at h
    rw [qcall_succ np fn]
    simp only [src_eff_path_call, List.length_cons, List.length_nil, if_true] at h ⊢
    rw [Pre_eff_path_call.eq_def] at pre
    simp only at pre
    budget Cost_eff_path_call
  exact ⟨key.1, key.2, back.out (pcall_of_q key.1) r0 r1 r2 r3 r4 r5⟩

end Lanius.Faithful.SelfBudget
