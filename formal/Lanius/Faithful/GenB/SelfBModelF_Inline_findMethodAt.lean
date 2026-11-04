import Lanius.Faithful.BudgetCore
import Lanius.Faithful.GenB.SelfBModelF_Inline_charOpen
import Lanius.Faithful.GenB.SelfBModelF_Inline_positionAt
import Lanius.Faithful.GenB.SelfBModelF_Inline_variantsNamedAt
import Lanius.Faithful.GenB.SelfBModelF_argView
import Lanius.Faithful.GenB.SelfBModelF_bindsOfTys
import Lanius.Faithful.GenB.SelfBModelF_callParts
import Lanius.Faithful.GenB.SelfBModelF_consBinder
import Lanius.Faithful.GenB.SelfBModelF_consBound
import Lanius.Faithful.GenB.SelfBModelF_consTreeTail
import Lanius.Faithful.GenB.SelfBModelF_consTys
import Lanius.Faithful.GenB.SelfBModelF_divergeArm
import Lanius.Faithful.GenB.SelfBModelF_findConst
import Lanius.Faithful.GenB.SelfBModelF_flattenTys
import Lanius.Faithful.GenB.SelfBModelF_floatTyped
import Lanius.Faithful.GenB.SelfBModelF_fnInstRet
import Lanius.Faithful.GenB.SelfBModelF_forRange
import Lanius.Faithful.GenB.SelfBModelF_freshId
import Lanius.Faithful.GenB.SelfBModelF_hasConst
import Lanius.Faithful.GenB.SelfBModelF_hasKids
import Lanius.Faithful.GenB.SelfBModelF_i32ArrayLength
import Lanius.Faithful.GenB.SelfBModelF_ifEff
import Lanius.Faithful.GenB.SelfBModelF_isFnPath
import Lanius.Faithful.GenB.SelfBModelF_isTryEnum
import Lanius.Faithful.GenB.SelfBModelF_isUnderscore
import Lanius.Faithful.GenB.SelfBModelF_joinInsts
import Lanius.Faithful.GenB.SelfBModelF_litEffMatch
import Lanius.Faithful.GenB.SelfBModelF_litWants
import Lanius.Faithful.GenB.SelfBModelF_lowerTy
import Lanius.Faithful.GenB.SelfBModelF_matchLetHead
import Lanius.Faithful.GenB.SelfBModelF_matchTysOrNone
import Lanius.Faithful.GenB.SelfBModelF_noBlock
import Lanius.Faithful.GenB.SelfBModelF_noTrees
import Lanius.Faithful.GenB.SelfBModelF_paramGoals
import Lanius.Faithful.GenB.SelfBModelF_pathRef
import Lanius.Faithful.GenB.SelfBModelF_pickTy
import Lanius.Faithful.GenB.SelfBModelF_projection
import Lanius.Faithful.GenB.SelfBModelF_projectionRet
import Lanius.Faithful.GenB.SelfBModelF_purePart
import Lanius.Faithful.GenB.SelfBModelF_repeatEff
import Lanius.Faithful.GenB.SelfBModelF_retBinds
import Lanius.Faithful.GenB.SelfBModelF_sliceHead
import Lanius.Faithful.GenB.SelfBModelF_stringCons
import Lanius.Faithful.GenB.SelfBModelF_stringReturn
import Lanius.Faithful.GenB.SelfBModelF_textSelf
import Lanius.Faithful.GenB.SelfBModelF_textSliceLen
import Lanius.Faithful.GenB.SelfBModelF_treeTokens
import Lanius.Faithful.GenB.SelfBModelF_typeDeclAt
import Lanius.Faithful.GenB.SelfBModelF_typePathSpellings
import Lanius.Faithful.GenB.SelfBModelF_variantIn
import Lanius.Faithful.GenB.SelfBModelF_weightAdd
import Lanius.Faithful.GenB.SelfBModelF_wideOf
import Lanius.Faithful.GenB.SelfBModelN0
import Lanius.Faithful.GenB.SelfBModelN1
import Lanius.Faithful.GenB.SelfBModelN2
import Lanius.Faithful.GenB.SelfBModelN3
import Lanius.Faithful.GenB.SelfBModelN4
import Lanius.Faithful.GenB.SelfBModelN5
import Lanius.Faithful.GenB.SelfBModelN6
import Lanius.Faithful.GenB.SelfBModelN7
import Lanius.Mini.Compiler.Types
import Lanius.Mini.Frontend.P.Inline_pAndTail
import Lanius.Mini.Frontend.P.Inline_pArgsMore
import Lanius.Mini.Frontend.P.Inline_pArrayAfterCommaTrailing
import Lanius.Mini.Frontend.P.Inline_pArrayMore
import Lanius.Mini.Frontend.P.Inline_pBitAnd
import Lanius.Mini.Frontend.P.Inline_pBoundTypeArgsAfterCommaMore
import Lanius.Mini.Frontend.P.Inline_pContractsNone
import Lanius.Mini.Frontend.P.Inline_pElseStmt
import Lanius.Mini.Frontend.P.Inline_pExpr
import Lanius.Mini.Frontend.P.Inline_pIdentPlain
import Lanius.Mini.Frontend.P.Inline_pLeTail
import Lanius.Mini.Frontend.P.Inline_pModTail
import Lanius.Mini.Frontend.P.Inline_pPathMore
import Lanius.Mini.Frontend.P.Inline_pRangeStartInt
import Lanius.Mini.Frontend.P.Inline_pRetVoid
import Lanius.Mini.Frontend.P.Inline_pSelfValue
import Lanius.Mini.Frontend.P.Inline_pStmtsMore
import Lanius.Mini.Frontend.P.Inline_pStructFieldsMore
import Lanius.Mini.Frontend.P.Inline_pTypeArgsNone
import Lanius.Mini.Frontend.P.argView
import Lanius.Mini.Frontend.P.basedDigits
import Lanius.Mini.Frontend.P.bindsOfTys
import Lanius.Mini.Frontend.P.blockArmsOf
import Lanius.Mini.Frontend.P.callParts
import Lanius.Mini.Frontend.P.collect
import Lanius.Mini.Frontend.P.consBinder
import Lanius.Mini.Frontend.P.consTreeTail
import Lanius.Mini.Frontend.P.consTys
import Lanius.Mini.Frontend.P.divergeArm
import Lanius.Mini.Frontend.P.effNamedTys
import Lanius.Mini.Frontend.P.fieldValue
import Lanius.Mini.Frontend.P.findConst
import Lanius.Mini.Frontend.P.flattenTys
import Lanius.Mini.Frontend.P.floatTyped
import Lanius.Mini.Frontend.P.fnInstRet
import Lanius.Mini.Frontend.P.forRange
import Lanius.Mini.Frontend.P.freshId
import Lanius.Mini.Frontend.P.funcsOnto
import Lanius.Mini.Frontend.P.hasConst
import Lanius.Mini.Frontend.P.hasKids
import Lanius.Mini.Frontend.P.i32ArrayLength
import Lanius.Mini.Frontend.P.ifNotWrites
import Lanius.Mini.Frontend.P.isEmptyUsize
import Lanius.Mini.Frontend.P.isFnPath
import Lanius.Mini.Frontend.P.isMatchStmt
import Lanius.Mini.Frontend.P.isPathCall
import Lanius.Mini.Frontend.P.isTypedSliceSegments
import Lanius.Mini.Frontend.P.isUnderscore
import Lanius.Mini.Frontend.P.itemOf
import Lanius.Mini.Frontend.P.joinInsts
import Lanius.Mini.Frontend.P.litIf
import Lanius.Mini.Frontend.P.litWants
import Lanius.Mini.Frontend.P.lowerTy
import Lanius.Mini.Frontend.P.lxBlockEnd
import Lanius.Mini.Frontend.P.lxSymbolStart
import Lanius.Mini.Frontend.P.matchStmtIf
import Lanius.Mini.Frontend.P.methodDecl
import Lanius.Mini.Frontend.P.noBlock
import Lanius.Mini.Frontend.P.noToken
import Lanius.Mini.Frontend.P.noTrees
import Lanius.Mini.Frontend.P.paramGoals
import Lanius.Mini.Frontend.P.pathRef
import Lanius.Mini.Frontend.P.pickTy
import Lanius.Mini.Frontend.P.primaryNames
import Lanius.Mini.Frontend.P.projection
import Lanius.Mini.Frontend.P.projectionRet
import Lanius.Mini.Frontend.P.purePart
import Lanius.Mini.Frontend.P.readInst
import Lanius.Mini.Frontend.P.repeatEff
import Lanius.Mini.Frontend.P.retBinds
import Lanius.Mini.Frontend.P.rootInsts
import Lanius.Mini.Frontend.P.setFieldOrEval
import Lanius.Mini.Frontend.P.setPlaceOf
import Lanius.Mini.Frontend.P.sliceHead
import Lanius.Mini.Frontend.P.stringCons
import Lanius.Mini.Frontend.P.stringLast
import Lanius.Mini.Frontend.P.stringOpen
import Lanius.Mini.Frontend.P.textSelf
import Lanius.Mini.Frontend.P.textSliceLen
import Lanius.Mini.Frontend.P.treeTokens
import Lanius.Mini.Frontend.P.triedIf
import Lanius.Mini.Frontend.P.tryLet
import Lanius.Mini.Frontend.P.tryLetHead
import Lanius.Mini.Frontend.P.tryLocalOf
import Lanius.Mini.Frontend.P.typeDeclAt
import Lanius.Mini.Frontend.P.typePathSpellings
import Lanius.Mini.Frontend.P.variantIn
import Lanius.Mini.Frontend.P.wideLeftStmt
import Lanius.Mini.Frontend.P.wideOf
import Lanius.Mini.Frontend.Types

/-! Generated by formal/tools/budget_certs.py: the cost models and preconditions of the self program's functions, group F_Inline_findMethodAt. Do not edit. -/

set_option maxHeartbeats 10000000
set_option maxRecDepth 100000
set_option linter.unusedVariables false

set_option Elab.async false

namespace Lanius.Faithful.SelfBudget

open Lanius.Mini
open Lanius.Core (Value)
open Lanius.Faithful
open Lanius.Faithful.Budget

noncomputable section

mutual
def Pre_lx_ident_run : Nat → List Nat → Nat → Prop
  | 0, x13, b => True
  | n + 1, x13, b => (match x13 with | [] => True | x100 :: x103 => (Pre_lx_ident_run_at n x100 x103 b))
termination_by structural fuel => fuel

def Pre_lx_ident_run_at : Nat → Nat → List Nat → Nat → Prop
  | 0, x16, x27, b => True
  | n + 1, x16, x27, b => (if (Lanius.Mini.lxIdentContinue x16) = true then ((Pre_lx_ident_run n x27 b) ∧ (Pre_plus n (Lanius.Mini.lxIdentRun x27) 1 b)) else True)
termination_by structural fuel => fuel
end

end

noncomputable section

def Pre_lx_base_digit : Nat → Nat → Nat → Nat → Prop
  | 0, x14, x24, b => True
  | n + 1, x14, x24, b => (if ((decide (48 ≤ x14)) && (decide (x14 ≤ 57))) = true then True else (if ((decide (97 ≤ x14)) && (decide (x14 ≤ 102))) = true then (Pre_plus n (x14 - 97) 10 b) else (if ((decide (65 ≤ x14)) && (decide (x14 ≤ 70))) = true then (Pre_plus n (x14 - 65) 10 b) else True)))

end

noncomputable section

mutual
def Pre_lx_digit_tail : Nat → Nat → List Nat → Nat → Nat → Prop
  | 0, x14, x27, x46, b => True
  | n + 1, x14, x27, x46, b => (match x27 with | [] => True | x143 :: x146 => (Pre_lx_digit_tail_at n x14 x143 x146 x46 b))
termination_by structural fuel => fuel

def Pre_lx_digit_tail_at : Nat → Nat → Nat → List Nat → Nat → Nat → Prop
  | 0, x17, x31, x42, x62, b => True
  | n + 1, x17, x31, x42, x62, b => ((Pre_lx_base_digit n x31 x17 b) ∧ (if (Lanius.Mini.lxBaseDigit x31 x17) = true then ((Pre_plus n x62 1 b) ∧ (Pre_lx_digit_tail n x17 x42 (x62 + 1) b)) else (if (decide (x31 = 95)) = true then (match x42 with | [] => (Pre_plus n x62 1 b) | x307 :: x313 => (Pre_lx_digit_sep n x17 x307 x313 x62 b)) else True)))
termination_by structural fuel => fuel

def Pre_lx_digit_sep : Nat → Nat → Nat → List Nat → Nat → Nat → Prop
  | 0, x13, x27, x41, x62, b => True
  | n + 1, x13, x27, x41, x62, b => ((Pre_lx_base_digit n x27 x13 b) ∧ (if (Lanius.Mini.lxBaseDigit x27 x13) = true then ((Pre_plus n x62 2 b) ∧ (Pre_lx_digit_tail n x13 x41 (x62 + 2) b)) else (Pre_plus n x62 1 b)))
termination_by structural fuel => fuel
end

end

noncomputable section

def Pre_lx_digit_run_at : Nat → Nat → List Nat → Nat → Nat → Nat → Prop
  | 0, x16, x31, x51, x66, b => True
  | n + 1, x16, x31, x51, x66, b => ((Pre_lx_base_digit n x16 x66 b) ∧ (if (Lanius.Mini.lxBaseDigit x16 x66) = true then ((Pre_plus n x51 1 b) ∧ (Pre_lx_digit_tail n x66 x31 (x51 + 1) b)) else True))

end

noncomputable section

def Pre_lx_digit_run : Nat → List Nat → Nat → Nat → Nat → Prop
  | 0, x13, x34, x48, b => True
  | n + 1, x13, x34, x48, b => (match (Lanius.Mini.lxDrop x13 x34) with | [] => True | x160 :: x167 => (Pre_lx_digit_run_at n x160 x167 x34 x48 b))

end

noncomputable section

def Pre_lx_exponent_sign : Nat → Nat → Nat → Nat → Prop
  | 0, x17, x28, b => True
  | n + 1, x17, x28, b => (if ((decide (x17 = 43)) || (decide (x17 = 45))) = true then ((Pre_plus n x28 1 b) ∧ (Pre_plus n (x28 + 1) 1 b)) else (Pre_plus n x28 1 b))

end

noncomputable section

def Pre_lx_exponent_digits : Nat → List Nat → Nat → Nat → Prop
  | 0, x19, x40, b => True
  | n + 1, x19, x40, b => ((Pre_plus n x40 1 b) ∧ (match (x19[(x40 + 1)]?) with | some x147 => (Pre_lx_exponent_sign n x147 x40 b) | none => (Pre_plus n x40 1 b)))

end

noncomputable section

mutual
def Pre_lx_space_run : Nat → List Nat → Nat → Prop
  | 0, x13, b => True
  | n + 1, x13, b => (match x13 with | [] => True | x100 :: x103 => (Pre_lx_space_run_at n x100 x103 b))
termination_by structural fuel => fuel

def Pre_lx_space_run_at : Nat → Nat → List Nat → Nat → Prop
  | 0, x16, x27, b => True
  | n + 1, x16, x27, b => (if (Lanius.Mini.lxSpace x16) = true then ((Pre_lx_space_run n x27 b) ∧ (Pre_plus n (Lanius.Mini.lxSpaceRun x27) 1 b)) else True)
termination_by structural fuel => fuel
end

end

noncomputable section

mutual
def Pre_lx_quoted : Nat → Nat → Bool → List Nat → Nat → Nat → Prop
  | 0, x10, x24, x40, x59, b => True
  | n + 1, x10, x24, x40, x59, b => (match x40 with | [] => True | x156 :: x159 => (Pre_lx_quoted_at n x10 x24 x156 x159 x59 b))
termination_by structural fuel => fuel

def Pre_lx_quoted_at : Nat → Nat → Bool → Nat → List Nat → Nat → Nat → Prop
  | 0, x13, x28, x45, x56, x76, b => True
  | n + 1, x13, x28, x45, x56, x76, b => (if x28 = true then ((Pre_plus n x76 1 b) ∧ (Pre_lx_quoted n x13 false x56 (x76 + 1) b)) else (if (decide (x45 = 10)) = true then True else (if (decide (x45 = x13)) = true then (Pre_plus n x76 1 b) else (if (decide (x45 = 92)) = true then ((Pre_plus n x76 1 b) ∧ (Pre_lx_quoted n x13 true x56 (x76 + 1) b)) else ((Pre_plus n x76 1 b) ∧ (Pre_lx_quoted n x13 false x56 (x76 + 1) b))))))
termination_by structural fuel => fuel
end

end

noncomputable section

mutual
def Pre_lx_line_run : Nat → List Nat → Nat → Prop
  | 0, x12, b => True
  | n + 1, x12, b => (match x12 with | [] => True | x99 :: x102 => (Pre_lx_line_run_at n x99 x102 b))
termination_by structural fuel => fuel

def Pre_lx_line_run_at : Nat → Nat → List Nat → Nat → Prop
  | 0, x15, x26, b => True
  | n + 1, x15, x26, b => (if (!decide (x15 = 10)) = true then ((Pre_lx_line_run n x26 b) ∧ (Pre_plus n (Lanius.Mini.lxLineRun x26) 1 b)) else True)
termination_by structural fuel => fuel
end

end

noncomputable section

mutual
def Pre_lx_block : Nat → List Nat → Nat → Nat → Prop
  | 0, x9, x28, b => True
  | n + 1, x9, x28, b => (match x9 with | [] => True | x125 :: x128 => (Pre_lx_block_at n x125 x128 x28 b))
termination_by structural fuel => fuel

def Pre_lx_block_at : Nat → Nat → List Nat → Nat → Nat → Prop
  | 0, x12, x23, x43, b => True
  | n + 1, x12, x23, x43, b => (match x23 with | [] => (Pre_plus n x43 1 b) | x152 :: x158 => (Pre_lx_block_next n x12 x152 x23 x43 b))
termination_by structural fuel => fuel

def Pre_lx_block_next : Nat → Nat → Nat → List Nat → Nat → Nat → Prop
  | 0, x14, x25, x39, x59, b => True
  | n + 1, x14, x25, x39, x59, b => (if ((decide (x14 = 42)) && (decide (x25 = 47))) = true then (Pre_plus n x59 2 b) else ((Pre_plus n x59 1 b) ∧ (Pre_lx_block n x39 (x59 + 1) b)))
termination_by structural fuel => fuel
end

end

noncomputable section

def Pre_lx_block_end : Nat → List Nat → Nat → Nat → Prop
  | 0, x13, x34, b => True
  | n + 1, x13, x34, b => ((Pre_plus n x34 2 b) ∧ ((Pre_plus n x34 2 b) ∧ (Pre_lx_block n (Lanius.Mini.lxDrop x13 ((x34 + 2))) (x34 + 2) b)))

end

noncomputable section

mutual
def Cost_lowered_all : Nat → Nat → Lanius.Mini.Decls → List Lanius.Mini.Inst → List Lanius.Mini.Inst → Nat
  | 0, x12, x25, x39, x58 => 18446744073709551616
  | n + 1, x12, x25, x39, x58 => (match x58 with | [] => 0 | x182 :: x185 => ((Cost_lower_named n (x12 - 1) x25 x39 x182.decl x182.args) + ((Cost_lowered_all n x12 x25 x39 x185) + (Cost_cons_of_core_option_Option_mini_selfhost_SrcType n (Lanius.Mini.lowerNamed ((x12 - 1)) x25 x39 x182.decl x182.args) (Lanius.Mini.loweredAll x12 x25 x39 x185)))))
termination_by structural fuel => fuel
end

end
noncomputable section

mutual
def Pre_lowered_all : Nat → Nat → Lanius.Mini.Decls → List Lanius.Mini.Inst → List Lanius.Mini.Inst → Nat → Prop
  | 0, x12, x25, x39, x58, b => True
  | n + 1, x12, x25, x39, x58, b => (match x58 with | [] => True | x182 :: x185 => ((Pre_lower_named n (x12 - 1) x25 x39 x182.decl x182.args b) ∧ (∀ b1 : Nat, (Cost_lower_named n (x12 - 1) x25 x39 x182.decl x182.args) < b → b1 = b - (Cost_lower_named n (x12 - 1) x25 x39 x182.decl x182.args) → (Pre_lowered_all n x12 x25 x39 x185 b1))))
termination_by structural fuel => fuel
end

end

noncomputable section

mutual
def Pre_ty_weight : Nat → List Lanius.Mini.Inst → List (Option Nat) → Lanius.Mini.Ty → Nat → Prop
  | 0, x10, x29, x68, b => True
  | n + 1, x10, x29, x68, b => (match x68 with | .tyI32 => True | .tyBool => True | .tyUint x199 => True | .tyPtr => True | .tyIsize => True | .tyChar => True | .tyFloat x413 => True | .tySlice x445 => ((Pre_ty_weight n x10 x29 x445 b) ∧ (Pre_weight_add_to n 1 (Lanius.Mini.tyWeight x10 x29 x445) b)) | .tyNamed x591 x594 => (Pre_inst_index n x10 (Lanius.Mini.Inst.mk x591 x594) 0 b) | .tySint x695 => True | .tyArray x517 x520 => ((Pre_ty_weight n x10 x29 x517 b) ∧ (Pre_weight_array n x520 (Lanius.Mini.tyWeight x10 x29 x517) b)) | .tyStr => True | .tyRef x335 => ((Pre_ty_weight n x10 x29 x335 b) ∧ (Pre_weight_add_to n 1 (Lanius.Mini.tyWeight x10 x29 x335) b)))
termination_by structural fuel => fuel
end

end

noncomputable section

mutual
def Pre_tys_weight : Nat → List Lanius.Mini.Inst → List (Option Nat) → List Lanius.Mini.Ty → Nat → Prop
  | 0, x11, x30, x69, b => True
  | n + 1, x11, x30, x69, b => (match x69 with | [] => True | x177 :: x180 => ((Pre_ty_weight n x11 x30 x177 b) ∧ ((Pre_tys_weight n x11 x30 x180 b) ∧ (Pre_weight_add n (Lanius.Mini.tyWeight x11 x30 x177) (Lanius.Mini.tysWeight x11 x30 x180) b))))
termination_by structural fuel => fuel
end

end

noncomputable section

def Cost_payloads_weight : Nat → List Lanius.Mini.Inst → List (Option Nat) → Option (List (List Lanius.Mini.Ty)) → Nat
  | 0, x16, x35, x74 => 18446744073709551616
  | n + 1, x16, x35, x74 => (match x74 with | some x208 => (Cost_flatten_tys n x208) | none => 0)

end
noncomputable section

def Pre_payloads_weight : Nat → List Lanius.Mini.Inst → List (Option Nat) → Option (List (List Lanius.Mini.Ty)) → Nat → Prop
  | 0, x16, x35, x74, b => True
  | n + 1, x16, x35, x74, b => (match x74 with | some x208 => (∀ b1 : Nat, (Cost_flatten_tys n x208) < b → b1 = b - (Cost_flatten_tys n x208) → ((Pre_tys_weight n x16 x35 (Lanius.Mini.flattenTys x208) b1) ∧ (Pre_weight_add_to n 1 (Lanius.Mini.tysWeight x16 x35 ((Lanius.Mini.flattenTys x208))) b1))) | none => True)

end

noncomputable section

def Pre_fields_weight : Nat → List Lanius.Mini.Inst → List (Option Nat) → Option (List Lanius.Mini.Ty) → Nat → Prop
  | 0, x14, x33, x72, b => True
  | n + 1, x14, x33, x72, b => (match x72 with | some x200 => ((Pre_tys_weight n x14 x33 x200 b) ∧ (Pre_weight_add_to n 1 (Lanius.Mini.tysWeight x14 x33 x200) b)) | none => True)

end

noncomputable section

def Cost_decl_weight : Nat → Nat → Lanius.Mini.Decls → List Lanius.Mini.Inst → List (Option Nat) → Bool → Lanius.Mini.Inst → Nat
  | 0, x12, x25, x39, x58, x97, x112 => 18446744073709551616
  | n + 1, x12, x25, x39, x58, x97, x112 => (if x97 = true then ((Cost_payload_tys n x12 x25 x112.decl x112.args) + (Cost_payloads_weight n x39 x58 (Lanius.Mini.payloadTys x12 x25 x112.decl x112.args))) else (Cost_field_tys n x12 x25 x112.decl x112.args))

end
noncomputable section

def Pre_decl_weight : Nat → Nat → Lanius.Mini.Decls → List Lanius.Mini.Inst → List (Option Nat) → Bool → Lanius.Mini.Inst → Nat → Prop
  | 0, x12, x25, x39, x58, x97, x112, b => True
  | n + 1, x12, x25, x39, x58, x97, x112, b => (if x97 = true then ((Pre_payload_tys n x12 x25 x112.decl x112.args b) ∧ (∀ b1 : Nat, (Cost_payload_tys n x12 x25 x112.decl x112.args) < b → b1 = b - (Cost_payload_tys n x12 x25 x112.decl x112.args) → (Pre_payloads_weight n x39 x58 (Lanius.Mini.payloadTys x12 x25 x112.decl x112.args) b1))) else ((Pre_field_tys n x12 x25 x112.decl x112.args b) ∧ (∀ b3 : Nat, (Cost_field_tys n x12 x25 x112.decl x112.args) < b → b3 = b - (Cost_field_tys n x12 x25 x112.decl x112.args) → (Pre_fields_weight n x39 x58 (Lanius.Mini.fieldTys x12 x25 x112.decl x112.args) b3))))

end

noncomputable section

def Cost_inst_weight : Nat → Nat → Lanius.Mini.Decls → List Lanius.Mini.Inst → List (Option Nat) → Lanius.Mini.Inst → Nat
  | 0, x12, x25, x39, x58, x97 => 18446744073709551616
  | n + 1, x12, x25, x39, x58, x97 => (match (x25.types[x97.decl]?) with | some x220 => (Cost_decl_weight n x12 x25 x39 x58 x220.isEnum x97) | none => 0)

end
noncomputable section

def Pre_inst_weight : Nat → Nat → Lanius.Mini.Decls → List Lanius.Mini.Inst → List (Option Nat) → Lanius.Mini.Inst → Nat → Prop
  | 0, x12, x25, x39, x58, x97, b => True
  | n + 1, x12, x25, x39, x58, x97, b => (match (x25.types[x97.decl]?) with | some x220 => (Pre_decl_weight n x12 x25 x39 x58 x220.isEnum x97 b) | none => True)

end

noncomputable section

def Cost_weigh_again : Nat → Nat → Lanius.Mini.Decls → List Lanius.Mini.Inst → List (Option Nat) → Lanius.Mini.Inst → Option Nat → Nat
  | 0, x12, x25, x39, x58, x97, x106 => 18446744073709551616
  | n + 1, x12, x25, x39, x58, x97, x106 => (match x106 with | some x267 => 0 | none => (Cost_inst_weight n x12 x25 x39 x58 x97))

end
noncomputable section

def Pre_weigh_again : Nat → Nat → Lanius.Mini.Decls → List Lanius.Mini.Inst → List (Option Nat) → Lanius.Mini.Inst → Option Nat → Nat → Prop
  | 0, x12, x25, x39, x58, x97, x106, b => True
  | n + 1, x12, x25, x39, x58, x97, x106, b => (match x106 with | some x267 => True | none => (Pre_inst_weight n x12 x25 x39 x58 x97 b))

end

noncomputable section

mutual
def Cost_weigh_round : Nat → Nat → Lanius.Mini.Decls → List Lanius.Mini.Inst → List (Option Nat) → List Lanius.Mini.Inst → List (Option Nat) → Nat
  | 0, x12, x25, x39, x58, x97, x113 => 18446744073709551616
  | n + 1, x12, x25, x39, x58, x97, x113 => (match x97 with | [] => 0 | x254 :: x257 => (Cost_weigh_round_at n x12 x25 x39 x58 x254 x257 x113))
termination_by structural fuel => fuel

def Cost_weigh_round_at : Nat → Nat → Lanius.Mini.Decls → List Lanius.Mini.Inst → List (Option Nat) → Lanius.Mini.Inst → List Lanius.Mini.Inst → List (Option Nat) → Nat
  | 0, x15, x29, x44, x64, x104, x114, x133 => 18446744073709551616
  | n + 1, x15, x29, x44, x64, x104, x114, x133 => (match x133 with | [] => 0 | x278 :: x284 => ((Cost_weigh_again n x15 x29 x44 x64 x104 x278) + ((Cost_weigh_round n x15 x29 x44 x64 x114 x284) + (Cost_cons_of_core_option_Option_usize n (Lanius.Mini.weighAgain x15 x29 x44 x64 x104 x278) (Lanius.Mini.weighRound x15 x29 x44 x64 x114 x284)))))
termination_by structural fuel => fuel
end

end
noncomputable section

mutual
def Pre_weigh_round : Nat → Nat → Lanius.Mini.Decls → List Lanius.Mini.Inst → List (Option Nat) → List Lanius.Mini.Inst → List (Option Nat) → Nat → Prop
  | 0, x12, x25, x39, x58, x97, x113, b => True
  | n + 1, x12, x25, x39, x58, x97, x113, b => (match x97 with | [] => True | x254 :: x257 => (Pre_weigh_round_at n x12 x25 x39 x58 x254 x257 x113 b))
termination_by structural fuel => fuel

def Pre_weigh_round_at : Nat → Nat → Lanius.Mini.Decls → List Lanius.Mini.Inst → List (Option Nat) → Lanius.Mini.Inst → List Lanius.Mini.Inst → List (Option Nat) → Nat → Prop
  | 0, x15, x29, x44, x64, x104, x114, x133, b => True
  | n + 1, x15, x29, x44, x64, x104, x114, x133, b => (match x133 with | [] => True | x278 :: x284 => ((Pre_weigh_again n x15 x29 x44 x64 x104 x278 b) ∧ (∀ b1 : Nat, (Cost_weigh_again n x15 x29 x44 x64 x104 x278) < b → b1 = b - (Cost_weigh_again n x15 x29 x44 x64 x104 x278) → (Pre_weigh_round n x15 x29 x44 x64 x114 x284 b1))))
termination_by structural fuel => fuel
end

end

noncomputable section

mutual
def Cost_weigh_rounds : Nat → Nat → Nat → Lanius.Mini.Decls → List Lanius.Mini.Inst → List (Option Nat) → Nat
  | 0, x13, x28, x41, x55, x74 => 18446744073709551616
  | n + 1, x13, x28, x41, x55, x74 => (if (decide (x13 = 0)) = true then 0 else ((Cost_weigh_round n x28 x41 x55 x74 x55 x74) + (Cost_weigh_next n (x13 - 1) x28 x41 x55 x74 (Lanius.Mini.weighRound x28 x41 x55 x74 x55 x74))))
termination_by structural fuel => fuel

def Cost_weigh_next : Nat → Nat → Nat → Lanius.Mini.Decls → List Lanius.Mini.Inst → List (Option Nat) → List (Option Nat) → Nat
  | 0, x11, x27, x41, x56, x76, x116 => 18446744073709551616
  | n + 1, x11, x27, x41, x56, x76, x116 => (if (Lanius.Mini.weighedMore x76 x116) = true then (Cost_weigh_rounds n x11 x27 x41 x56 x116) else 0)
termination_by structural fuel => fuel
end

end
noncomputable section

mutual
def Pre_weigh_rounds : Nat → Nat → Nat → Lanius.Mini.Decls → List Lanius.Mini.Inst → List (Option Nat) → Nat → Prop
  | 0, x13, x28, x41, x55, x74, b => True
  | n + 1, x13, x28, x41, x55, x74, b => (if (decide (x13 = 0)) = true then True else ((Pre_weigh_round n x28 x41 x55 x74 x55 x74 b) ∧ (∀ b1 : Nat, (Cost_weigh_round n x28 x41 x55 x74 x55 x74) < b → b1 = b - (Cost_weigh_round n x28 x41 x55 x74 x55 x74) → (Pre_weigh_next n (x13 - 1) x28 x41 x55 x74 (Lanius.Mini.weighRound x28 x41 x55 x74 x55 x74) b1))))
termination_by structural fuel => fuel

def Pre_weigh_next : Nat → Nat → Nat → Lanius.Mini.Decls → List Lanius.Mini.Inst → List (Option Nat) → List (Option Nat) → Nat → Prop
  | 0, x11, x27, x41, x56, x76, x116, b => True
  | n + 1, x11, x27, x41, x56, x76, x116, b => (if (Lanius.Mini.weighedMore x76 x116) = true then (Pre_weigh_rounds n x11 x27 x41 x56 x116 b) else True)
termination_by structural fuel => fuel
end

end

noncomputable section

mutual
def Cost_unweighed : Nat → List Lanius.Mini.Inst → Nat
  | 0, x10 => 18446744073709551616
  | n + 1, x10 => (match x10 with | [] => 0 | x126 :: x129 => ((Cost_unweighed n x129) + (Cost_cons_of_core_option_Option_usize n (none : Option Nat) (Lanius.Mini.unweighed x129))))
termination_by structural fuel => fuel
end

end

noncomputable section

mutual
def Cost_type_table : Nat → Nat → Lanius.Mini.Decls → List Lanius.Mini.Inst → List Lanius.Mini.Ty → Nat
  | 0, x11, x24, x38, x57 => 18446744073709551616
  | n + 1, x11, x24, x38, x57 => (match x57 with | [] => 0 | x174 :: x177 => ((Cost_ty_insts n x11 x24 x174) + (Cost_type_table_next n x11 x24 x38 (Lanius.Mini.tyInsts x11 x24 x174) x177)))
termination_by structural fuel => fuel

def Cost_type_table_next : Nat → Nat → Lanius.Mini.Decls → List Lanius.Mini.Inst → Option (List Lanius.Mini.Inst) → List Lanius.Mini.Ty → Nat
  | 0, x16, x30, x45, x65, x105 => 18446744073709551616
  | n + 1, x16, x30, x45, x65, x105 => (match x65 with | some x221 => ((Cost_add_insts n x45 x221) + (Cost_type_table n x16 x30 (Lanius.Mini.addInsts x45 x221) x105)) | none => 0)
termination_by structural fuel => fuel
end

end
noncomputable section

mutual
def Pre_type_table : Nat → Nat → Lanius.Mini.Decls → List Lanius.Mini.Inst → List Lanius.Mini.Ty → Nat → Prop
  | 0, x11, x24, x38, x57, b => True
  | n + 1, x11, x24, x38, x57, b => (match x57 with | [] => True | x174 :: x177 => ((Pre_ty_insts n x11 x24 x174 b) ∧ (∀ b1 : Nat, (Cost_ty_insts n x11 x24 x174) < b → b1 = b - (Cost_ty_insts n x11 x24 x174) → (Pre_type_table_next n x11 x24 x38 (Lanius.Mini.tyInsts x11 x24 x174) x177 b1))))
termination_by structural fuel => fuel

def Pre_type_table_next : Nat → Nat → Lanius.Mini.Decls → List Lanius.Mini.Inst → Option (List Lanius.Mini.Inst) → List Lanius.Mini.Ty → Nat → Prop
  | 0, x16, x30, x45, x65, x105, b => True
  | n + 1, x16, x30, x45, x65, x105, b => (match x65 with | some x221 => (∀ b1 : Nat, (Cost_add_insts n x45 x221) < b → b1 = b - (Cost_add_insts n x45 x221) → (Pre_type_table n x16 x30 (Lanius.Mini.addInsts x45 x221) x105 b1)) | none => True)
termination_by structural fuel => fuel
end

end

noncomputable section

mutual
def Cost_type_table_more : Nat → Nat → Lanius.Mini.Decls → Option (List Lanius.Mini.Inst) → List Lanius.Mini.Ty → Nat
  | 0, x16, x29, x43, x84 => 18446744073709551616
  | n + 1, x16, x29, x43, x84 => (match x43 with | some x198 => (match x84 with | [] => 0 | x262 :: x265 => (Cost_type_table_more_at n x16 x29 x198 x262 x265)) | none => 0)
termination_by structural fuel => fuel

def Cost_type_table_more_at : Nat → Nat → Lanius.Mini.Decls → List Lanius.Mini.Inst → Lanius.Mini.Ty → List Lanius.Mini.Ty → Nat
  | 0, x19, x33, x48, x68, x76 => 18446744073709551616
  | n + 1, x19, x33, x48, x68, x76 => (if (Lanius.Mini.tyKnown x48 x68) = true then (Cost_type_table_more n x19 x33 (some x48) x76) else ((Cost_single_of_mini_selfhost_Ty n x68) + ((Cost_type_table n x19 x33 x48 ([x68])) + (Cost_type_table_more n x19 x33 (Lanius.Mini.typeTable x19 x33 x48 ([x68])) x76))))
termination_by structural fuel => fuel
end

end
noncomputable section

mutual
def Pre_type_table_more : Nat → Nat → Lanius.Mini.Decls → Option (List Lanius.Mini.Inst) → List Lanius.Mini.Ty → Nat → Prop
  | 0, x16, x29, x43, x84, b => True
  | n + 1, x16, x29, x43, x84, b => (match x43 with | some x198 => (match x84 with | [] => True | x262 :: x265 => (Pre_type_table_more_at n x16 x29 x198 x262 x265 b)) | none => True)
termination_by structural fuel => fuel

def Pre_type_table_more_at : Nat → Nat → Lanius.Mini.Decls → List Lanius.Mini.Inst → Lanius.Mini.Ty → List Lanius.Mini.Ty → Nat → Prop
  | 0, x19, x33, x48, x68, x76, b => True
  | n + 1, x19, x33, x48, x68, x76, b => (if (Lanius.Mini.tyKnown x48 x68) = true then (Pre_type_table_more n x19 x33 (some x48) x76 b) else (∀ b2 : Nat, (Cost_single_of_mini_selfhost_Ty n x68) < b → b2 = b - (Cost_single_of_mini_selfhost_Ty n x68) → ((Pre_type_table n x19 x33 x48 ([x68]) b2) ∧ (∀ b3 : Nat, (Cost_type_table n x19 x33 x48 ([x68])) < b2 → b3 = b2 - (Cost_type_table n x19 x33 x48 ([x68])) → (Pre_type_table_more n x19 x33 (Lanius.Mini.typeTable x19 x33 x48 ([x68])) x76 b3)))))
termination_by structural fuel => fuel
end

end

noncomputable section

mutual
def Cost_seed_tys : Nat → List Lanius.Mini.Inst → Nat
  | 0, x9 => 18446744073709551616
  | n + 1, x9 => (match x9 with | [] => 0 | x106 :: x109 => (1 + ((Cost_seed_tys n x109) + (Cost_cons_of_mini_selfhost_Ty n (Lanius.Mini.Ty.tyNamed x106.decl x106.args) (Lanius.Mini.seedTys x109)))))
termination_by structural fuel => fuel
end

end

noncomputable section

mutual
def Cost_param_tys : Nat → List Lanius.Mini.MParam → Nat
  | 0, x10 => 18446744073709551616
  | n + 1, x10 => (match x10 with | [] => 0 | x103 :: x106 => ((Cost_param_tys n x106) + (Cost_cons_of_mini_selfhost_Ty n x103.ty (Lanius.Mini.paramTys x106))))
termination_by structural fuel => fuel
end

end

noncomputable section

def Cost_ret_tys : Nat → Lanius.Mini.RetTy → Nat
  | 0, x8 => 18446744073709551616
  | n + 1, x8 => (match x8 with | .retUnit => 0 | .retOf x97 => (Cost_single_of_mini_selfhost_Ty n x97))

end

noncomputable section

mutual
def Cost_eff_named_tys : Nat → Lanius.Mini.MEff → Nat
  | 0, x14 => 18446744073709551616
  | n + 1, x14 => (match x14 with | .xPure x74 => 0 | .xCall x103 x109 => (Cost_effs_named_tys n x109) | .xApply x162 x166 x169 => ((Cost_eff_named_tys n x166) + ((Cost_eff_named_tys n x169) + (Cost_concat_of_mini_selfhost_Ty n (Lanius.Mini.effNamedTys x166) (Lanius.Mini.effNamedTys x169)))) | .xNeg x246 => (Cost_eff_named_tys n x246) | .xNot x290 => (Cost_eff_named_tys n x290) | .xCast x335 x338 => (Cost_eff_named_tys n x338) | .xIndex x384 x387 => (Cost_eff_named_tys n x387) | .xStruct x434 x437 => ((Cost_effs_named_tys n x437) + (Cost_cons_of_mini_selfhost_Ty n x434 (Lanius.Mini.effsNamedTys x437))) | .xVariant x497 x500 x503 => ((Cost_effs_named_tys n x503) + (Cost_cons_of_mini_selfhost_Ty n x497 (Lanius.Mini.effsNamedTys x503))) | .xMatch x561 x564 x569 x572 x576 => ((Cost_eff_named_tys n x561) + ((Cost_effs_named_tys n x576) + ((Cost_cons_of_mini_selfhost_Ty n x569 (Lanius.Mini.effsNamedTys x576)) + ((Cost_cons_of_mini_selfhost_Ty n x564 (x569 :: (Lanius.Mini.effsNamedTys x576))) + (Cost_concat_of_mini_selfhost_Ty n (Lanius.Mini.effNamedTys x561) (x564 :: (x569 :: (Lanius.Mini.effsNamedTys x576)))))))) | .xDivide x679 x683 x686 => ((Cost_eff_named_tys n x683) + ((Cost_eff_named_tys n x686) + (Cost_concat_of_mini_selfhost_Ty n (Lanius.Mini.effNamedTys x683) (Lanius.Mini.effNamedTys x686)))) | .xStride x766 => 0 | .xArraySlice x802 x805 => (Cost_single_of_mini_selfhost_Ty n x802) | .xHost x837 x841 => (Cost_effs_named_tys n x841) | .xIf x891 x894 x897 x900 => ((Cost_eff_named_tys n x891) + ((Cost_eff_named_tys n x897) + ((Cost_eff_named_tys n x900) + ((Cost_concat_of_mini_selfhost_Ty n (Lanius.Mini.effNamedTys x897) (Lanius.Mini.effNamedTys x900)) + ((Cost_cons_of_mini_selfhost_Ty n x894 ((Lanius.Mini.effNamedTys x897) ++ (Lanius.Mini.effNamedTys x900))) + (Cost_concat_of_mini_selfhost_Ty n (Lanius.Mini.effNamedTys x891) (x894 :: ((Lanius.Mini.effNamedTys x897) ++ (Lanius.Mini.effNamedTys x900))))))))) | .xLet x1019 x1023 x1026 x1029 x1033 => ((Cost_eff_named_tys n x1026) + ((Cost_eff_named_tys n x1033) + ((Cost_cons_of_mini_selfhost_Ty n x1029 (Lanius.Mini.effNamedTys x1033)) + ((Cost_cons_of_mini_selfhost_Ty n x1023 (x1029 :: (Lanius.Mini.effNamedTys x1033))) + (Cost_concat_of_mini_selfhost_Ty n (Lanius.Mini.effNamedTys x1026) (x1023 :: (x1029 :: (Lanius.Mini.effNamedTys x1033)))))))) | .xLen x1129 => 0 | .xStr x1158 => 0 | .xDeref x1189 x1194 => ((Cost_eff_named_tys n x1194) + (Cost_cons_of_mini_selfhost_Ty n x1189 (Lanius.Mini.effNamedTys x1194))) | .xPlaceField x1256 x1259 => (Cost_eff_named_tys n x1256) | .xPlaceAt x1307 x1310 => ((Cost_eff_named_tys n x1307) + ((Cost_eff_named_tys n x1310) + (Cost_concat_of_mini_selfhost_Ty n (Lanius.Mini.effNamedTys x1307) (Lanius.Mini.effNamedTys x1310)))) | .xBorrow x1390 x1395 => ((Cost_eff_named_tys n x1395) + (Cost_cons_of_mini_selfhost_Ty n x1390 (Lanius.Mini.effNamedTys x1395))))
termination_by structural fuel => fuel

def Cost_effs_named_tys : Nat → List Lanius.Mini.MEff → Nat
  | 0, x15 => 18446744073709551616
  | n + 1, x15 => (match x15 with | [] => 0 | x106 :: x109 => ((Cost_eff_named_tys n x106) + ((Cost_effs_named_tys n x109) + (Cost_concat_of_mini_selfhost_Ty n (Lanius.Mini.effNamedTys x106) (Lanius.Mini.effsNamedTys x109)))))
termination_by structural fuel => fuel
end

end

noncomputable section

mutual
def Cost_stmt_tys : Nat → Lanius.Mini.MStmt → Nat
  | 0, x9 => 18446744073709551616
  | n + 1, x9 => (match x9 with | .mNop => 0 | .mLet x94 x98 x102 x105 => ((Cost_stmt_tys n x105) + (Cost_cons_of_mini_selfhost_Ty n x98 (Lanius.Mini.stmtTys x105))) | .mLetStruct x166 x170 x174 x178 => ((Cost_stmt_tys n x178) + (Cost_cons_of_mini_selfhost_Ty n x170 (Lanius.Mini.stmtTys x178))) | .mLetCall x237 x241 x245 x251 x257 => ((Cost_stmt_tys n x257) + (Cost_cons_of_mini_selfhost_Ty n x241 (Lanius.Mini.stmtTys x257))) | .mLetEnum x316 x320 x324 x327 x331 => ((Cost_stmt_tys n x331) + (Cost_cons_of_mini_selfhost_Ty n x320 (Lanius.Mini.stmtTys x331))) | .mLetMatch x391 x395 x399 x402 x407 x413 => ((Cost_stmt_tys n x413) + ((Cost_cons_of_mini_selfhost_Ty n x402 (Lanius.Mini.stmtTys x413)) + (Cost_cons_of_mini_selfhost_Ty n x395 (x402 :: (Lanius.Mini.stmtTys x413))))) | .mSet x479 x483 => 0 | .mSetField x516 x520 x523 => 0 | .mSetCall x555 x559 x565 => 0 | .mThen x597 x600 => ((Cost_stmt_tys n x597) + ((Cost_stmt_tys n x600) + (Cost_concat_of_mini_selfhost_Ty n (Lanius.Mini.stmtTys x597) (Lanius.Mini.stmtTys x600)))) | .mIf x666 x669 x672 => ((Cost_stmt_tys n x669) + ((Cost_stmt_tys n x672) + (Cost_concat_of_mini_selfhost_Ty n (Lanius.Mini.stmtTys x669) (Lanius.Mini.stmtTys x672)))) | .mWhile x741 x744 => (Cost_stmt_tys n x744) | .mReturn x792 => 0 | .mLetAlloc x825 x829 x835 x842 => (Cost_stmt_tys n x842) | .mFree x888 x891 x897 => 0 | .mLetSlice x934 x938 x941 x944 x947 => ((Cost_stmt_tys n x947) + (Cost_cons_of_mini_selfhost_Ty n x938 (Lanius.Mini.stmtTys x947))) | .mLetIndex x1006 x1010 x1014 x1017 x1020 => ((Cost_stmt_tys n x1020) + (Cost_cons_of_mini_selfhost_Ty n x1010 (Lanius.Mini.stmtTys x1020))) | .mLetView x1079 x1083 x1086 x1090 x1093 => (1 + ((Cost_stmt_tys n x1093) + (Cost_cons_of_mini_selfhost_Ty n (Lanius.Mini.Ty.tyArray Lanius.Mini.Ty.tyI32 x1083) (Lanius.Mini.stmtTys x1093)))) | .mLetStr x1173 x1177 x1181 => (Cost_stmt_tys n x1181) | .mSetIndex x1231 x1234 x1237 => 0 | .mLetEval x1269 x1273 x1277 x1280 => ((Cost_eff_named_tys n x1277) + ((Cost_stmt_tys n x1280) + ((Cost_concat_of_mini_selfhost_Ty n (Lanius.Mini.effNamedTys x1277) (Lanius.Mini.stmtTys x1280)) + (Cost_cons_of_mini_selfhost_Ty n x1273 ((Lanius.Mini.effNamedTys x1277) ++ (Lanius.Mini.stmtTys x1280)))))) | .mSetEval x1365 x1369 => (Cost_eff_named_tys n x1369) | .mIfEval x1409 x1412 x1415 => ((Cost_eff_named_tys n x1409) + ((Cost_stmt_tys n x1412) + ((Cost_stmt_tys n x1415) + ((Cost_concat_of_mini_selfhost_Ty n (Lanius.Mini.stmtTys x1412) (Lanius.Mini.stmtTys x1415)) + (Cost_concat_of_mini_selfhost_Ty n (Lanius.Mini.effNamedTys x1409) ((Lanius.Mini.stmtTys x1412) ++ (Lanius.Mini.stmtTys x1415))))))) | .mWhileEval x1514 x1517 => ((Cost_eff_named_tys n x1514) + ((Cost_stmt_tys n x1517) + (Cost_concat_of_mini_selfhost_Ty n (Lanius.Mini.effNamedTys x1514) (Lanius.Mini.stmtTys x1517)))) | .mReturnEval x1595 => (Cost_eff_named_tys n x1595) | .mDiscard x1636 => (Cost_eff_named_tys n x1636) | .mSetIndexEval x1682 x1685 x1688 => ((Cost_eff_named_tys n x1685) + ((Cost_eff_named_tys n x1688) + (Cost_concat_of_mini_selfhost_Ty n (Lanius.Mini.effNamedTys x1685) (Lanius.Mini.effNamedTys x1688)))) | .mSetFieldEval x1760 x1764 x1767 => (Cost_eff_named_tys n x1767) | .mReturnUnit => 0 | .mAssert x1839 => (Cost_eff_named_tys n x1839) | .mBreak => 0 | .mContinue => 0 | .mMatchArm x1938 x1942 x1947 x1950 x1954 x1957 x1961 x1967 => ((Cost_stmt_tys n x1961) + ((Cost_stmt_tys n x1967) + ((Cost_concat_of_mini_selfhost_Ty n (Lanius.Mini.stmtTys x1961) (Lanius.Mini.stmtTys x1967)) + ((Cost_cons_of_mini_selfhost_Ty n x1957 ((Lanius.Mini.stmtTys x1961) ++ (Lanius.Mini.stmtTys x1967))) + (Cost_cons_of_mini_selfhost_Ty n x1942 (x1957 :: ((Lanius.Mini.stmtTys x1961) ++ (Lanius.Mini.stmtTys x1967)))))))) | .mUnreachable x2072 x2076 => (Cost_single_of_mini_selfhost_Ty n x2076) | .mSetPlace x2113 x2117 => ((Cost_eff_named_tys n x2113) + ((Cost_eff_named_tys n x2117) + (Cost_concat_of_mini_selfhost_Ty n (Lanius.Mini.effNamedTys x2113) (Lanius.Mini.effNamedTys x2117)))) | .mSetPlaceOp x2188 x2192 x2196 => ((Cost_eff_named_tys n x2192) + ((Cost_eff_named_tys n x2196) + (Cost_concat_of_mini_selfhost_Ty n (Lanius.Mini.effNamedTys x2192) (Lanius.Mini.effNamedTys x2196)))))
termination_by structural fuel => fuel
end

end

noncomputable section

mutual
def Cost_funcs_tys : Nat → List Lanius.Mini.MFunc → Nat
  | 0, x10 => 18446744073709551616
  | n + 1, x10 => (match x10 with | [] => 0 | x102 :: x105 => ((Cost_param_tys n x102.params) + ((Cost_ret_tys n x102.ret) + ((Cost_stmt_tys n x102.body) + ((Cost_funcs_tys n x105) + ((Cost_concat_of_mini_selfhost_Ty n (Lanius.Mini.stmtTys x102.body) (Lanius.Mini.funcsTys x105)) + ((Cost_concat_of_mini_selfhost_Ty n (Lanius.Mini.retTys x102.ret) ((Lanius.Mini.stmtTys x102.body) ++ (Lanius.Mini.funcsTys x105))) + (Cost_concat_of_mini_selfhost_Ty n (Lanius.Mini.paramTys x102.params) ((Lanius.Mini.retTys x102.ret) ++ ((Lanius.Mini.stmtTys x102.body) ++ (Lanius.Mini.funcsTys x105)))))))))))
termination_by structural fuel => fuel
end

end

noncomputable section

mutual
def Cost_eff_calls : Nat → Lanius.Mini.MEff → Nat
  | 0, x10 => 18446744073709551616
  | n + 1, x10 => (match x10 with | .xPure x72 => 0 | .xCall x101 x107 => ((Cost_effs_calls n x107) + (Cost_cons_of_mini_selfhost_Inst n x101 (Lanius.Mini.effsCalls x107))) | .xApply x168 x172 x175 => ((Cost_eff_calls n x172) + ((Cost_eff_calls n x175) + (Cost_concat_of_mini_selfhost_Inst n (Lanius.Mini.effCalls x172) (Lanius.Mini.effCalls x175)))) | .xNeg x244 => (Cost_eff_calls n x244) | .xNot x284 => (Cost_eff_calls n x284) | .xCast x325 x328 => (Cost_eff_calls n x328) | .xIndex x370 x373 => (Cost_eff_calls n x373) | .xStruct x416 x419 => (Cost_effs_calls n x419) | .xVariant x466 x469 x472 => (Cost_effs_calls n x472) | .xMatch x517 x520 x525 x528 x532 => ((Cost_eff_calls n x517) + ((Cost_effs_calls n x532) + (Cost_concat_of_mini_selfhost_Inst n (Lanius.Mini.effCalls x517) (Lanius.Mini.effsCalls x532)))) | .xDivide x607 x611 x614 => ((Cost_eff_calls n x611) + ((Cost_eff_calls n x614) + (Cost_concat_of_mini_selfhost_Inst n (Lanius.Mini.effCalls x611) (Lanius.Mini.effCalls x614)))) | .xStride x686 => 0 | .xArraySlice x722 x725 => 0 | .xHost x755 x759 => (Cost_effs_calls n x759) | .xIf x805 x808 x811 x814 => ((Cost_eff_calls n x805) + ((Cost_eff_calls n x811) + ((Cost_eff_calls n x814) + ((Cost_concat_of_mini_selfhost_Inst n (Lanius.Mini.effCalls x811) (Lanius.Mini.effCalls x814)) + (Cost_concat_of_mini_selfhost_Inst n (Lanius.Mini.effCalls x805) ((Lanius.Mini.effCalls x811) ++ (Lanius.Mini.effCalls x814))))))) | .xLet x912 x916 x919 x922 x926 => ((Cost_eff_calls n x919) + ((Cost_eff_calls n x926) + (Cost_concat_of_mini_selfhost_Inst n (Lanius.Mini.effCalls x919) (Lanius.Mini.effCalls x926)))) | .xLen x995 => 0 | .xStr x1024 => 0 | .xDeref x1055 x1060 => (Cost_eff_calls n x1060) | .xPlaceField x1107 x1110 => (Cost_eff_calls n x1107) | .xPlaceAt x1154 x1157 => ((Cost_eff_calls n x1154) + ((Cost_eff_calls n x1157) + (Cost_concat_of_mini_selfhost_Inst n (Lanius.Mini.effCalls x1154) (Lanius.Mini.effCalls x1157)))) | .xBorrow x1229 x1234 => (Cost_eff_calls n x1234))
termination_by structural fuel => fuel

def Cost_effs_calls : Nat → List Lanius.Mini.MEff → Nat
  | 0, x11 => 18446744073709551616
  | n + 1, x11 => (match x11 with | [] => 0 | x104 :: x107 => ((Cost_eff_calls n x104) + ((Cost_effs_calls n x107) + (Cost_concat_of_mini_selfhost_Inst n (Lanius.Mini.effCalls x104) (Lanius.Mini.effsCalls x107)))))
termination_by structural fuel => fuel
end

end

noncomputable section

mutual
def Cost_stmt_calls : Nat → Lanius.Mini.MStmt → Nat
  | 0, x11 => 18446744073709551616
  | n + 1, x11 => (match x11 with | .mNop => 0 | .mLet x98 x102 x106 x109 => (Cost_stmt_calls n x109) | .mLetStruct x162 x166 x170 x174 => (Cost_stmt_calls n x174) | .mLetCall x225 x229 x233 x239 x245 => ((Cost_stmt_calls n x245) + (Cost_cons_of_mini_selfhost_Inst n x233 (Lanius.Mini.stmtCalls x245))) | .mLetEnum x308 x312 x316 x319 x323 => (Cost_stmt_calls n x323) | .mLetMatch x375 x379 x383 x386 x391 x397 => (Cost_stmt_calls n x397) | .mSet x444 x448 => 0 | .mSetField x481 x485 x488 => 0 | .mSetCall x520 x524 x530 => (Cost_single_of_mini_selfhost_Inst n x524) | .mThen x567 x570 => ((Cost_stmt_calls n x567) + ((Cost_stmt_calls n x570) + (Cost_concat_of_mini_selfhost_Inst n (Lanius.Mini.stmtCalls x567) (Lanius.Mini.stmtCalls x570)))) | .mIf x640 x643 x646 => ((Cost_stmt_calls n x643) + ((Cost_stmt_calls n x646) + (Cost_concat_of_mini_selfhost_Inst n (Lanius.Mini.stmtCalls x643) (Lanius.Mini.stmtCalls x646)))) | .mWhile x719 x722 => (Cost_stmt_calls n x722) | .mReturn x772 => 0 | .mLetAlloc x805 x809 x815 x822 => (Cost_stmt_calls n x822) | .mFree x870 x873 x879 => 0 | .mLetSlice x916 x920 x923 x926 x929 => (Cost_stmt_calls n x929) | .mLetIndex x981 x985 x989 x992 x995 => (Cost_stmt_calls n x995) | .mLetView x1046 x1050 x1053 x1057 x1060 => (Cost_stmt_calls n x1060) | .mLetStr x1110 x1114 x1118 => (Cost_stmt_calls n x1118) | .mSetIndex x1170 x1173 x1176 => 0 | .mLetEval x1208 x1212 x1216 x1219 => ((Cost_eff_calls n x1216) + ((Cost_stmt_calls n x1219) + (Cost_concat_of_mini_selfhost_Inst n (Lanius.Mini.effCalls x1216) (Lanius.Mini.stmtCalls x1219)))) | .mSetEval x1292 x1296 => (Cost_eff_calls n x1296) | .mIfEval x1332 x1335 x1338 => ((Cost_eff_calls n x1332) + ((Cost_stmt_calls n x1335) + ((Cost_stmt_calls n x1338) + ((Cost_concat_of_mini_selfhost_Inst n (Lanius.Mini.stmtCalls x1335) (Lanius.Mini.stmtCalls x1338)) + (Cost_concat_of_mini_selfhost_Inst n (Lanius.Mini.effCalls x1332) ((Lanius.Mini.stmtCalls x1335) ++ (Lanius.Mini.stmtCalls x1338))))))) | .mWhileEval x1437 x1440 => ((Cost_eff_calls n x1437) + ((Cost_stmt_calls n x1440) + (Cost_concat_of_mini_selfhost_Inst n (Lanius.Mini.effCalls x1437) (Lanius.Mini.stmtCalls x1440)))) | .mReturnEval x1516 => (Cost_eff_calls n x1516) | .mDiscard x1553 => (Cost_eff_calls n x1553) | .mSetIndexEval x1595 x1598 x1601 => ((Cost_eff_calls n x1598) + ((Cost_eff_calls n x1601) + (Cost_concat_of_mini_selfhost_Inst n (Lanius.Mini.effCalls x1598) (Lanius.Mini.effCalls x1601)))) | .mSetFieldEval x1665 x1669 x1672 => (Cost_eff_calls n x1672) | .mReturnUnit => 0 | .mAssert x1740 => (Cost_eff_calls n x1740) | .mBreak => 0 | .mContinue => 0 | .mMatchArm x1835 x1839 x1844 x1847 x1851 x1854 x1858 x1864 => ((Cost_stmt_calls n x1858) + ((Cost_stmt_calls n x1864) + (Cost_concat_of_mini_selfhost_Inst n (Lanius.Mini.stmtCalls x1858) (Lanius.Mini.stmtCalls x1864)))) | .mUnreachable x1952 x1956 => 0 | .mSetPlace x1990 x1994 => ((Cost_eff_calls n x1990) + ((Cost_eff_calls n x1994) + (Cost_concat_of_mini_selfhost_Inst n (Lanius.Mini.effCalls x1990) (Lanius.Mini.effCalls x1994)))) | .mSetPlaceOp x2057 x2061 x2065 => ((Cost_eff_calls n x2061) + ((Cost_eff_calls n x2065) + (Cost_concat_of_mini_selfhost_Inst n (Lanius.Mini.effCalls x2061) (Lanius.Mini.effCalls x2065)))))
termination_by structural fuel => fuel
end

end

noncomputable section

mutual
def Cost_param_effs : Nat → List Lanius.Mini.MParam → Nat
  | 0, x11 => 18446744073709551616
  | n + 1, x11 => (match x11 with | [] => 0 | x106 :: x109 => ((Cost_param_effs n x109) + (Cost_cons_of_mini_selfhost_MEff n (Lanius.Mini.MEff.xPure (Lanius.Mini.SrcExpr.local x106.id)) (Lanius.Mini.paramEffs x109))))
termination_by structural fuel => fuel
end

end

noncomputable section

def Cost_extern_body : Nat → Option Lanius.Mini.MParams → Option Lanius.Mini.RetTy → Nat → Nat
  | 0, x12, x51, x85 => 18446744073709551616
  | n + 1, x12, x51, x85 => (match x12 with | some x192 => (match x51 with | some x256 => ((Cost_param_effs n x192.params) + 1) | none => 0) | none => 0)

end

noncomputable section

def Cost_cons_param : Nat → Lanius.Mini.MParam → Option Lanius.Mini.MParams → Nat
  | 0, x11, x22 => 18446744073709551616
  | n + 1, x11, x22 => (match x22 with | some x155 => (Cost_cons_of_mini_selfhost_MParam n x11 x155.params) | none => 0)

end

noncomputable section

mutual
def Cost_params_of : Nat → Nat → Lanius.Mini.FrontEnv → Lanius.Mini.FnDecl → List Lanius.Mini.Local → List Lanius.Mini.CTree → Nat
  | 0, x10, x23, x38, x50, x70 => 18446744073709551616
  | n + 1, x10, x23, x38, x50, x70 => (match x70 with | [] => 0 | x229 :: x232 => (Cost_param_of n x10 x23 x38 x50 x229 x232))
termination_by structural fuel => fuel

def Cost_param_of : Nat → Nat → Lanius.Mini.FrontEnv → Lanius.Mini.FnDecl → List Lanius.Mini.Local → Lanius.Mini.CTree → List Lanius.Mini.CTree → Nat
  | 0, x9, x23, x39, x52, x73, x84 => 18446744073709551616
  | n + 1, x9, x23, x39, x52, x73, x84 => (let k2 := (match (Lanius.Mini.patternOf x39 x73) with | some x512 => ((Cost_self_param_ty n x9 x23 x73 x512) + (match (Lanius.Mini.selfParamTy x9 x23 x73 x512) with | some x613 => ((Cost_cons_of_mini_selfhost_Local n (Lanius.Mini.Local.mk ((Lanius.Mini.paramToken x73).text) (((Lanius.Mini.paramToken x73).start) - x23.base) x613) x52) + ((Cost_params_of n x9 x23 x39 ((Lanius.Mini.Local.mk ((Lanius.Mini.paramToken x73).text) (((Lanius.Mini.paramToken x73).start) - x23.base) x613) :: x52) x84) + (Cost_cons_param n (Lanius.Mini.MParam.mk (((Lanius.Mini.paramToken x73).start) - x23.base) x613) (Lanius.Mini.paramsOf x9 x23 x39 (((Lanius.Mini.Local.mk ((Lanius.Mini.paramToken x73).text) (((Lanius.Mini.paramToken x73).start) - x23.base) x613) :: x52)) x84)))) | none => 0)) | none => 0); let k3 := 0; (if (decide ((Lanius.Mini.nodeProd x73) = Lanius.Mini.Inline.pParamNamed)) = true then (if (!(Lanius.Mini.member x23.globals (((Lanius.Mini.paramToken x73).text)))) = true then (if (Lanius.Mini.freshId x52 ((((Lanius.Mini.paramToken x73).start) - x23.base))) = true then k2 else k3) else k3) else (if (decide ((Lanius.Mini.nodeProd x73) = Lanius.Mini.Inline.pParamSelf)) = true then (if (!(Lanius.Mini.member x23.globals (((Lanius.Mini.paramToken x73).text)))) = true then (if (Lanius.Mini.freshId x52 ((((Lanius.Mini.paramToken x73).start) - x23.base))) = true then k2 else k3) else k3) else (if (decide ((Lanius.Mini.nodeProd x73) = Lanius.Mini.Inline.pParamSelfRef)) = true then (if (!(Lanius.Mini.member x23.globals (((Lanius.Mini.paramToken x73).text)))) = true then (if (Lanius.Mini.freshId x52 ((((Lanius.Mini.paramToken x73).start) - x23.base))) = true then k2 else k3) else k3) else (if (decide ((Lanius.Mini.nodeProd x73) = Lanius.Mini.Inline.pParamSelfRefMut)) = true then (if (!(Lanius.Mini.member x23.globals (((Lanius.Mini.paramToken x73).text)))) = true then (if (Lanius.Mini.freshId x52 ((((Lanius.Mini.paramToken x73).start) - x23.base))) = true then k2 else k3) else k3) else k3)))))
termination_by structural fuel => fuel
end

end
noncomputable section

mutual
def Pre_params_of : Nat → Nat → Lanius.Mini.FrontEnv → Lanius.Mini.FnDecl → List Lanius.Mini.Local → List Lanius.Mini.CTree → Nat → Prop
  | 0, x10, x23, x38, x50, x70, b => True
  | n + 1, x10, x23, x38, x50, x70, b => (match x70 with | [] => True | x229 :: x232 => (Pre_param_of n x10 x23 x38 x50 x229 x232 b))
termination_by structural fuel => fuel

def Pre_param_of : Nat → Nat → Lanius.Mini.FrontEnv → Lanius.Mini.FnDecl → List Lanius.Mini.Local → Lanius.Mini.CTree → List Lanius.Mini.CTree → Nat → Prop
  | 0, x9, x23, x39, x52, x73, x84, b => True
  | n + 1, x9, x23, x39, x52, x73, x84, b => (let k6 := fun (b1 : Nat) => (match (Lanius.Mini.patternOf x39 x73) with | some x512 => ((Pre_self_param_ty n x9 x23 x73 x512 b1) ∧ (∀ b2 : Nat, (Cost_self_param_ty n x9 x23 x73 x512) < b1 → b2 = b1 - (Cost_self_param_ty n x9 x23 x73 x512) → (match (Lanius.Mini.selfParamTy x9 x23 x73 x512) with | some x613 => (∀ b3 : Nat, (Cost_cons_of_mini_selfhost_Local n (Lanius.Mini.Local.mk ((Lanius.Mini.paramToken x73).text) (((Lanius.Mini.paramToken x73).start) - x23.base) x613) x52) < b2 → b3 = b2 - (Cost_cons_of_mini_selfhost_Local n (Lanius.Mini.Local.mk ((Lanius.Mini.paramToken x73).text) (((Lanius.Mini.paramToken x73).start) - x23.base) x613) x52) → (Pre_params_of n x9 x23 x39 ((Lanius.Mini.Local.mk ((Lanius.Mini.paramToken x73).text) (((Lanius.Mini.paramToken x73).start) - x23.base) x613) :: x52) x84 b3)) | none => True))) | none => True); let k7 := fun (b1 : Nat) => True; (if (decide ((Lanius.Mini.nodeProd x73) = Lanius.Mini.Inline.pParamNamed)) = true then (if (!(Lanius.Mini.member x23.globals (((Lanius.Mini.paramToken x73).text)))) = true then (if (Lanius.Mini.freshId x52 ((((Lanius.Mini.paramToken x73).start) - x23.base))) = true then (k6 b) else (k7 b)) else (k7 b)) else (if (decide ((Lanius.Mini.nodeProd x73) = Lanius.Mini.Inline.pParamSelf)) = true then (if (!(Lanius.Mini.member x23.globals (((Lanius.Mini.paramToken x73).text)))) = true then (if (Lanius.Mini.freshId x52 ((((Lanius.Mini.paramToken x73).start) - x23.base))) = true then (k6 b) else (k7 b)) else (k7 b)) else (if (decide ((Lanius.Mini.nodeProd x73) = Lanius.Mini.Inline.pParamSelfRef)) = true then (if (!(Lanius.Mini.member x23.globals (((Lanius.Mini.paramToken x73).text)))) = true then (if (Lanius.Mini.freshId x52 ((((Lanius.Mini.paramToken x73).start) - x23.base))) = true then (k6 b) else (k7 b)) else (k7 b)) else (if (decide ((Lanius.Mini.nodeProd x73) = Lanius.Mini.Inline.pParamSelfRefMut)) = true then (if (!(Lanius.Mini.member x23.globals (((Lanius.Mini.paramToken x73).text)))) = true then (if (Lanius.Mini.freshId x52 ((((Lanius.Mini.paramToken x73).start) - x23.base))) = true then (k6 b) else (k7 b)) else (k7 b)) else (k7 b))))))
termination_by structural fuel => fuel
end

end

noncomputable section

def Cost_result_of : Nat → Nat → Lanius.Mini.FrontEnv → Lanius.Mini.CTree → Nat
  | 0, x10, x23, x38 => 18446744073709551616
  | n + 1, x10, x23, x38 => (if (decide ((Lanius.Mini.nodeProd x38) = Lanius.Mini.Inline.pRetVoid)) = true then 0 else (let k2 := 0; let k3 := (if (decide ((Lanius.Mini.nodeProd x38) = Lanius.Mini.Inline.pRetType)) = true then (Cost_ty_of n x10 x23 (Lanius.Mini.kid x38 1)) else 0); (if (decide ((Lanius.Mini.nodeProd x38) = Lanius.Mini.Inline.pRetType)) = true then (if (decide ((Lanius.Mini.nodeProd ((Lanius.Mini.kid x38 1))) = Lanius.Mini.Inline.pTypeNever)) = true then k2 else k3) else k3)))

end
noncomputable section

def Pre_result_of : Nat → Nat → Lanius.Mini.FrontEnv → Lanius.Mini.CTree → Nat → Prop
  | 0, x10, x23, x38, b => True
  | n + 1, x10, x23, x38, b => (if (decide ((Lanius.Mini.nodeProd x38) = Lanius.Mini.Inline.pRetVoid)) = true then True else (let k3 := fun (b1 : Nat) => True; let k4 := fun (b1 : Nat) => (if (decide ((Lanius.Mini.nodeProd x38) = Lanius.Mini.Inline.pRetType)) = true then (Pre_ty_of n x10 x23 (Lanius.Mini.kid x38 1) b1) else True); (if (decide ((Lanius.Mini.nodeProd x38) = Lanius.Mini.Inline.pRetType)) = true then (if (decide ((Lanius.Mini.nodeProd ((Lanius.Mini.kid x38 1))) = Lanius.Mini.Inline.pTypeNever)) = true then (k3 b) else (k4 b)) else (k4 b))))

end

noncomputable section

def Cost_extern_func : Nat → Nat → Lanius.Mini.Decls → Lanius.Mini.FnDecl → List Lanius.Mini.Ty → Nat
  | 0, x12, x25, x39, x51 => 18446744073709551616
  | n + 1, x12, x25, x39, x51 => ((Cost_concat_of_mini_selfhost_List_usize n x39.implParams x39.params) + ((Cost_module_globals n x25 x39.home) + (let k2 := ((Cost_list_items n x12 (Lanius.Mini.kid x39.tree 4)) + (match (Lanius.Mini.listItems x12 ((Lanius.Mini.kid x39.tree 4))) with | some x519 => ((Cost_params_of n x12 (Lanius.Mini.FrontEnv.mk x25 x39.home (x39.implParams ++ x39.params) x51 (Lanius.Mini.moduleGlobals x25 x39.home) (none : Option Lanius.Mini.Ty) (((Lanius.Mini.kidToken x39.tree 1)).start)) x39 ([] : List Lanius.Mini.Local) x519) + ((Cost_result_of n x12 (Lanius.Mini.FrontEnv.mk x25 x39.home (x39.implParams ++ x39.params) x51 (Lanius.Mini.moduleGlobals x25 x39.home) (none : Option Lanius.Mini.Ty) (((Lanius.Mini.kidToken x39.tree 1)).start)) (Lanius.Mini.kid x39.tree 6)) + ((Cost_host_id n x39.name) + (Cost_extern_body n (Lanius.Mini.paramsOf x12 ((Lanius.Mini.FrontEnv.mk x25 x39.home (x39.implParams ++ x39.params) x51 (Lanius.Mini.moduleGlobals x25 x39.home) (none : Option Lanius.Mini.Ty) (((Lanius.Mini.kidToken x39.tree 1)).start))) x39 (([] : List Lanius.Mini.Local)) x519) (Lanius.Mini.resultOf x12 ((Lanius.Mini.FrontEnv.mk x25 x39.home (x39.implParams ++ x39.params) x51 (Lanius.Mini.moduleGlobals x25 x39.home) (none : Option Lanius.Mini.Ty) (((Lanius.Mini.kidToken x39.tree 1)).start))) ((Lanius.Mini.kid x39.tree 6))) (Lanius.Mini.hostId x39.name))))) | none => 0)); let k3 := 0; (if (decide (((x39.implParams ++ x39.params).length) = 0)) = true then (if (decide (x51.length = 0)) = true then k2 else k3) else k3))))

end
noncomputable section

def Pre_extern_func : Nat → Nat → Lanius.Mini.Decls → Lanius.Mini.FnDecl → List Lanius.Mini.Ty → Nat → Prop
  | 0, x12, x25, x39, x51, b => True
  | n + 1, x12, x25, x39, x51, b => (∀ b1 : Nat, (Cost_concat_of_mini_selfhost_List_usize n x39.implParams x39.params) < b → b1 = b - (Cost_concat_of_mini_selfhost_List_usize n x39.implParams x39.params) → (∀ b2 : Nat, (Cost_module_globals n x25 x39.home) < b1 → b2 = b1 - (Cost_module_globals n x25 x39.home) → (let k9 := fun (b3 : Nat) => (∀ b4 : Nat, (Cost_list_items n x12 (Lanius.Mini.kid x39.tree 4)) < b3 → b4 = b3 - (Cost_list_items n x12 (Lanius.Mini.kid x39.tree 4)) → (match (Lanius.Mini.listItems x12 ((Lanius.Mini.kid x39.tree 4))) with | some x519 => ((Pre_params_of n x12 (Lanius.Mini.FrontEnv.mk x25 x39.home (x39.implParams ++ x39.params) x51 (Lanius.Mini.moduleGlobals x25 x39.home) (none : Option Lanius.Mini.Ty) (((Lanius.Mini.kidToken x39.tree 1)).start)) x39 ([] : List Lanius.Mini.Local) x519 b4) ∧ (∀ b5 : Nat, (Cost_params_of n x12 (Lanius.Mini.FrontEnv.mk x25 x39.home (x39.implParams ++ x39.params) x51 (Lanius.Mini.moduleGlobals x25 x39.home) (none : Option Lanius.Mini.Ty) (((Lanius.Mini.kidToken x39.tree 1)).start)) x39 ([] : List Lanius.Mini.Local) x519) < b4 → b5 = b4 - (Cost_params_of n x12 (Lanius.Mini.FrontEnv.mk x25 x39.home (x39.implParams ++ x39.params) x51 (Lanius.Mini.moduleGlobals x25 x39.home) (none : Option Lanius.Mini.Ty) (((Lanius.Mini.kidToken x39.tree 1)).start)) x39 ([] : List Lanius.Mini.Local) x519) → (Pre_result_of n x12 (Lanius.Mini.FrontEnv.mk x25 x39.home (x39.implParams ++ x39.params) x51 (Lanius.Mini.moduleGlobals x25 x39.home) (none : Option Lanius.Mini.Ty) (((Lanius.Mini.kidToken x39.tree 1)).start)) (Lanius.Mini.kid x39.tree 6) b5))) | none => True)); let k10 := fun (b3 : Nat) => True; ((Pre_length_of_mini_selfhost_List_usize n (x39.implParams ++ x39.params) b2) ∧ (if (decide (((x39.implParams ++ x39.params).length) = 0)) = true then ((Pre_length_of_mini_selfhost_Ty n x51 b2) ∧ (if (decide (x51.length = 0)) = true then (k9 b2) else (k10 b2))) else (k10 b2))))))

end

noncomputable section

def Cost_diverge_func : Nat → Option Lanius.Mini.MFunc → Lanius.Mini.Inst → Nat
  | 0, x13, x45 => 18446744073709551616
  | n + 1, x13, x45 => (match x13 with | some x148 => (match (Lanius.Mini.lastTy x45.args) with | some x226 => ((Cost_init_tys n x45.args) + ((Cost_param_effs n x148.params) + (1 + (1 + ((Cost_param_effs n x148.params) + (1 + 1)))))) | none => 0) | none => 0)

end

noncomputable section

def Cost_primary_names : Nat → Lanius.Mini.CTree → List Nat → Nat
  | 0, x14, x30 => 18446744073709551616
  | n + 1, x14, x30 => (if (decide ((Lanius.Mini.nodeProd x14) = Lanius.Mini.Inline.pIdent)) = true then (if (decide ((Lanius.Mini.nodeProd ((Lanius.Mini.kid x14 1))) = Lanius.Mini.Inline.pIdentPlain)) = true then (if (Lanius.Mini.isText ((Lanius.Mini.pathName ((Lanius.Mini.kid x14 0)))) x30) = true then 0 else (if (decide ((Lanius.Mini.nodeProd x14) = Lanius.Mini.Inline.pSelfValue)) = true then (Cost_text_self n ) else 0)) else (if (decide ((Lanius.Mini.nodeProd x14) = Lanius.Mini.Inline.pSelfValue)) = true then (Cost_text_self n ) else 0)) else (if (decide ((Lanius.Mini.nodeProd x14) = Lanius.Mini.Inline.pSelfValue)) = true then (Cost_text_self n ) else 0))

end

noncomputable section

def Cost_arg_names : Nat → Nat → Lanius.Mini.CTree → List Nat → Nat
  | 0, x10, x23, x33 => 18446744073709551616
  | n + 1, x10, x23, x33 => (match (Lanius.Mini.peel x10 x23) with | some x133 => (Cost_primary_names n (Lanius.Mini.kid x133 0) x33) | none => 0)

end

noncomputable section

def Cost_names_field_base : Nat → Lanius.Mini.CTree → List Nat → Nat
  | 0, x17, x28 => 18446744073709551616
  | n + 1, x17, x28 => (Cost_primary_names n (Lanius.Mini.kid x17 0) x28)

end

noncomputable section

def Cost_ref_kids : Nat → Nat → Lanius.Mini.CTree → List Nat → Nat
  | 0, x9, x22, x32 => 18446744073709551616
  | n + 1, x9, x22, x32 => (let k5 := (Cost_single_of_mini_selfhost_CTree n (Lanius.Mini.kid x22 1)); let k6 := (let k3 := (Cost_single_of_mini_selfhost_CTree n (Lanius.Mini.kid ((Lanius.Mini.kid x22 1)) 3)); let k4 := 0; (if (decide ((Lanius.Mini.nodeProd x22) = Lanius.Mini.Inline.pPostfix)) = true then ((Cost_names_field_base n x22 x32) + (if (Lanius.Mini.namesFieldBase x22 x32) = true then k3 else k4)) else k4)); (if (decide ((Lanius.Mini.nodeProd x22) = Lanius.Mini.Inline.pArgsSome)) = true then ((Cost_arg_names n x9 (Lanius.Mini.kid x22 0) x32) + (if (Lanius.Mini.argNames x9 ((Lanius.Mini.kid x22 0)) x32) = true then k5 else k6)) else (if (decide ((Lanius.Mini.nodeProd x22) = Lanius.Mini.Inline.pArgsAfterCommaMore)) = true then ((Cost_arg_names n x9 (Lanius.Mini.kid x22 0) x32) + (if (Lanius.Mini.argNames x9 ((Lanius.Mini.kid x22 0)) x32) = true then k5 else k6)) else k6)))

end

noncomputable section

mutual
def Cost_ref_uses_ok : Nat → Nat → List Lanius.Mini.CTree → List Nat → Nat
  | 0, x12, x25, x44 => 18446744073709551616
  | n + 1, x12, x25, x44 => (if (decide (x12 = 0)) = true then 0 else (match x25 with | [] => 0 | x209 :: x212 => (match x209 with | .leaf x250 => (Cost_ref_uses_ok n (x12 - 1) x212 x44) | .node x368 x371 => ((Cost_ref_kids n x12 x209 x44) + ((Cost_concat_of_mini_selfhost_CTree n (Lanius.Mini.refKids x12 x209 x44) x212) + (Cost_ref_uses_ok n (x12 - 1) ((Lanius.Mini.refKids x12 x209 x44) ++ x212) x44))))))
termination_by structural fuel => fuel
end

end

noncomputable section

mutual
def Cost_refs_used_ok : Nat → Nat → List Lanius.Mini.CTree → List Lanius.Mini.CTree → List Lanius.Mini.MParam → Nat
  | 0, x13, x26, x46, x66 => 18446744073709551616
  | n + 1, x13, x26, x46, x66 => (match x46 with | [] => 0 | x155 :: x158 => (match x66 with | [] => 0 | x223 :: x226 => (if (!(Lanius.Mini.isRefTy x223.ty)) = true then (Cost_refs_used_ok n x13 x26 x158 x226) else ((Cost_ref_uses_ok n x13 x26 (((Lanius.Mini.paramToken x155)).text)) + (if (Lanius.Mini.knownTrue ((Lanius.Mini.refUsesOk x13 x26 ((((Lanius.Mini.paramToken x155)).text))))) = true then (Cost_refs_used_ok n x13 x26 x158 x226) else 0)))))
termination_by structural fuel => fuel
end

end

noncomputable section

def Cost_refs_checked : Nat → Nat → Lanius.Mini.CTree → List Lanius.Mini.CTree → Option Lanius.Mini.MFunc → Nat
  | 0, x13, x26, x36, x56 => 18446744073709551616
  | n + 1, x13, x26, x36, x56 => (match x56 with | some x179 => ((Cost_single_of_mini_selfhost_CTree n (Lanius.Mini.kid x26 9)) + ((Cost_cons_of_mini_selfhost_CTree n (Lanius.Mini.kid x26 8) ([(Lanius.Mini.kid x26 9)])) + (Cost_refs_used_ok n x13 ((Lanius.Mini.kid x26 8) :: ([(Lanius.Mini.kid x26 9)])) x36 x179.params))) | none => 0)

end

noncomputable section

def Cost_contract_then : Nat → Option Lanius.Mini.MEff → Option Lanius.Mini.MStmt → Nat
  | 0, x14, x45 => 18446744073709551616
  | n + 1, x14, x45 => (match x14 with | some x171 => (match x45 with | some x235 => (1 + 1) | none => 0) | none => 0)

end

noncomputable section

def Cost_stride_of_postfix : Nat → Lanius.Mini.FrontEnv → List Lanius.Mini.Local → Option Lanius.Mini.CTree → Nat
  | 0, x18, x33, x53 => 18446744073709551616
  | n + 1, x18, x33, x53 => (match x53 with | some x177 => (Cost_local_of n x18 x33 (Lanius.Mini.kid x177 0)) | none => 0)

end

noncomputable section

def Cost_stride_arg : Nat → Nat → Lanius.Mini.FrontEnv → List Lanius.Mini.Local → List Lanius.Mini.CTree → Nat
  | 0, x11, x24, x39, x59 => 18446744073709551616
  | n + 1, x11, x24, x39, x59 => (match x59 with | [] => 0 | x172 :: x175 => (match x175 with | [] => (Cost_stride_of_postfix n x24 x39 (Lanius.Mini.peel x11 x172)) | x288 :: x291 => 0))

end

noncomputable section

def Cost_len_of_postfix : Nat → Lanius.Mini.FrontEnv → List Lanius.Mini.Local → Option Lanius.Mini.CTree → Nat
  | 0, x15, x30, x50 => 18446744073709551616
  | n + 1, x15, x30, x50 => (match x50 with | some x174 => (Cost_local_of n x15 x30 (Lanius.Mini.kid x174 0)) | none => 0)

end

noncomputable section

def Cost_len_arg : Nat → Nat → Lanius.Mini.FrontEnv → List Lanius.Mini.Local → List Lanius.Mini.CTree → Nat
  | 0, x8, x21, x36, x56 => 18446744073709551616
  | n + 1, x8, x21, x36, x56 => (match x56 with | [] => 0 | x169 :: x172 => (match x172 with | [] => (Cost_len_of_postfix n x21 x36 (Lanius.Mini.peel x8 x169)) | x282 :: x285 => 0))

end

noncomputable section

mutual
def Cost_find_method : Nat → Nat → Lanius.Mini.Decls → List Lanius.Mini.FnDecl → Nat → List Nat → Lanius.Mini.Ty → Nat
  | 0, x12, x25, x39, x58, x68, x87 => 18446744073709551616
  | n + 1, x12, x25, x39, x58, x68, x87 => (match x39 with | [] => 0 | x186 :: x190 => (Cost_find_method_at n x12 x25 x186 x190 x58 x68 x87))
termination_by structural fuel => fuel

def Cost_find_method_at : Nat → Nat → Lanius.Mini.Decls → Lanius.Mini.FnDecl → List Lanius.Mini.FnDecl → Nat → List Nat → Lanius.Mini.Ty → Nat
  | 0, x15, x29, x44, x57, x78, x89, x109 => 18446744073709551616
  | n + 1, x15, x29, x44, x57, x78, x89, x109 => (if (Lanius.Mini.sameText x44.name x89) = true then ((Cost_impl_fit n x15 x29 x44 x109) + (match (Lanius.Mini.implFit x15 x29 x44 x109) with | .fits x263 => (Cost_no_method n x15 x29 x57 x89 x109) | .misfit => (Cost_find_method n x15 x29 x57 (x78 + 1) x89 x109) | .spent => 0)) else (Cost_find_method n x15 x29 x57 (x78 + 1) x89 x109))
termination_by structural fuel => fuel
end

end
noncomputable section

mutual
def Pre_find_method : Nat → Nat → Lanius.Mini.Decls → List Lanius.Mini.FnDecl → Nat → List Nat → Lanius.Mini.Ty → Nat → Prop
  | 0, x12, x25, x39, x58, x68, x87, b => True
  | n + 1, x12, x25, x39, x58, x68, x87, b => (match x39 with | [] => True | x186 :: x190 => (Pre_find_method_at n x12 x25 x186 x190 x58 x68 x87 b))
termination_by structural fuel => fuel

def Pre_find_method_at : Nat → Nat → Lanius.Mini.Decls → Lanius.Mini.FnDecl → List Lanius.Mini.FnDecl → Nat → List Nat → Lanius.Mini.Ty → Nat → Prop
  | 0, x15, x29, x44, x57, x78, x89, x109, b => True
  | n + 1, x15, x29, x44, x57, x78, x89, x109, b => (if (Lanius.Mini.sameText x44.name x89) = true then ((Pre_impl_fit n x15 x29 x44 x109 b) ∧ (∀ b1 : Nat, (Cost_impl_fit n x15 x29 x44 x109) < b → b1 = b - (Cost_impl_fit n x15 x29 x44 x109) → (match (Lanius.Mini.implFit x15 x29 x44 x109) with | .fits x263 => (Pre_no_method n x15 x29 x57 x89 x109 b1) | .misfit => ((Pre_plus n x78 1 b1) ∧ (Pre_find_method n x15 x29 x57 (x78 + 1) x89 x109 b1)) | .spent => True))) else ((Pre_plus n x78 1 b) ∧ (Pre_find_method n x15 x29 x57 (x78 + 1) x89 x109 b)))
termination_by structural fuel => fuel
end

end

noncomputable section

mutual
def Cost_string_body : Nat → List Nat → Nat
  | 0, x12 => 18446744073709551616
  | n + 1, x12 => (match x12 with | [] => 0 | x126 :: x129 => (Cost_string_byte n x126 x129))
termination_by structural fuel => fuel

def Cost_string_byte : Nat → Nat → List Nat → Nat
  | 0, x12, x23 => 18446744073709551616
  | n + 1, x12, x23 => (match x23 with | [] => 0 | x161 :: x165 => ((Cost_string_body n x23) + (Cost_string_cons n (Lanius.Mini.plainStringByte x12) x12 (Lanius.Mini.stringBody x23))))
termination_by structural fuel => fuel
end

end

noncomputable section

def Cost_string_open : Nat → Bool → List Nat → Nat
  | 0, x12, x22 => 18446744073709551616
  | n + 1, x12, x22 => (if x12 = true then (Cost_string_body n x22) else 0)

end

noncomputable section

def Cost_string_literal : Nat → List Nat → Nat
  | 0, x15 => 18446744073709551616
  | n + 1, x15 => (match x15 with | [] => 0 | x133 :: x136 => (Cost_string_open n (decide (x133 = 34)) x136))

end

noncomputable section

def Cost_string_primary : Nat → Lanius.Mini.CTree → Lanius.Mini.CTree → Nat
  | 0, x15, x31 => 18446744073709551616
  | n + 1, x15, x31 => (let k2 := (Cost_string_literal n (((Lanius.Mini.kidToken x15 0)).text)); let k3 := 0; (if (decide ((Lanius.Mini.nodeProd x15) = Lanius.Mini.Inline.pString)) = true then (if (decide ((Lanius.Mini.nodeProd x31) = Lanius.Mini.Inline.pPostfixEnd)) = true then k2 else k3) else k3))

end

noncomputable section

def Cost_string_init : Nat → Nat → Lanius.Mini.CTree → Nat
  | 0, x12, x25 => 18446744073709551616
  | n + 1, x12, x25 => (match (Lanius.Mini.peel x12 x25) with | some x150 => (Cost_string_primary n (Lanius.Mini.kid x150 0) (Lanius.Mini.kid x150 1)) | none => 0)

end

noncomputable section

def Cost_borrow_of : Nat → Lanius.Mini.Ty → Option Lanius.Mini.MEff → Nat
  | 0, x10, x17 => 18446744073709551616
  | n + 1, x10, x17 => (match x17 with | some x140 => (1 + 1) | none => 0)

end

noncomputable section

def Cost_place_of : Nat → Lanius.Mini.MEff → Nat
  | 0, x9 => 18446744073709551616
  | n + 1, x9 => (match x9 with | .xPure x87 => (match x87 with | .int x230 => 0 | .boolean x262 => 0 | .unsigned x295 x298 => 0 | .local x123 => 0 | .field x157 x161 => 1 | .negate x329 => 0 | .not x357 => 0 | .apply x387 x391 x394 => 0 | .cast x423 x426 => 0 | .null => 0 | .char x490 => 0 | .float x532 x536 => 0) | .xCall x576 x582 => 0 | .xApply x612 x616 x619 => 0 | .xNeg x644 => 0 | .xNot x669 => 0 | .xCast x695 x698 => 0 | .xIndex x725 x728 => 0 | .xStruct x756 x759 => 0 | .xVariant x789 x792 x795 => 0 | .xMatch x823 x826 x831 x834 x838 => 0 | .xDivide x867 x871 x874 => 0 | .xStride x902 => 0 | .xArraySlice x935 x938 => 0 | .xHost x965 x969 => 0 | .xIf x996 x999 x1002 x1005 => 0 | .xLet x1030 x1034 x1037 x1040 x1044 => 0 | .xLen x1069 => 0 | .xStr x1095 => 0 | .xDeref x1123 x1128 => 0 | .xPlaceField x1163 x1166 => 0 | .xPlaceAt x1198 x1201 => 0 | .xBorrow x1232 x1237 => 0)

end

noncomputable section

def Cost_receiver_of : Nat → Bool → Lanius.Mini.Ty → Lanius.Mini.MEff → Nat
  | 0, x12, x26, x33 => 18446744073709551616
  | n + 1, x12, x26, x33 => (let k2 := 0; let k3 := (if x12 = true then ((Cost_place_of n x33) + (Cost_borrow_of n x26 (Lanius.Mini.placeOf x33))) else 0); (if x12 = true then (if (Lanius.Mini.isRefTy x26) = true then k2 else k3) else k3))

end

noncomputable section

def Cost_receiver_typed : Nat → Bool → Option Lanius.Mini.Ty → Lanius.Mini.MEff → Nat
  | 0, x15, x29, x58 => 18446744073709551616
  | n + 1, x15, x29, x58 => (match x29 with | some x157 => (Cost_receiver_of n x15 x157 x58) | none => 0)

end

noncomputable section

def Cost_receivers_of : Nat → Nat → Lanius.Mini.FrontEnv → List Lanius.Mini.Local → Lanius.Mini.FnDecl → List Lanius.Mini.MEff → Nat
  | 0, x13, x26, x41, x61, x73 => 18446744073709551616
  | n + 1, x13, x26, x41, x61, x73 => (match x73 with | [] => 0 | x196 :: x199 => (match x199 with | [] => ((Cost_eff_ty n x13 x26 x41 x196) + ((Cost_receiver_typed n (Lanius.Mini.selfByRef x61) (Lanius.Mini.effTy x13 x26 x41 x196) x196) + (match (Lanius.Mini.receiverTyped ((Lanius.Mini.selfByRef x61)) ((Lanius.Mini.effTy x13 x26 x41 x196)) x196) with | some x374 => (Cost_single_of_mini_selfhost_MEff n x374) | none => 0))) | x429 :: x432 => 0))

end
noncomputable section

def Pre_receivers_of : Nat → Nat → Lanius.Mini.FrontEnv → List Lanius.Mini.Local → Lanius.Mini.FnDecl → List Lanius.Mini.MEff → Nat → Prop
  | 0, x13, x26, x41, x61, x73, b => True
  | n + 1, x13, x26, x41, x61, x73, b => (match x73 with | [] => True | x196 :: x199 => (match x199 with | [] => (Pre_eff_ty n x13 x26 x41 x196 b) | x429 :: x432 => True))

end

noncomputable section

def Cost_method_of_ty : Nat → Nat → Lanius.Mini.FrontEnv → Option Lanius.Mini.Ty → List Nat → Nat
  | 0, x13, x26, x41, x70 => 18446744073709551616
  | n + 1, x13, x26, x41, x70 => (match x41 with | some x180 => (Cost_find_method n x13 x26.decls x26.decls.fns 0 x70 x180) | none => 0)

end
noncomputable section

def Pre_method_of_ty : Nat → Nat → Lanius.Mini.FrontEnv → Option Lanius.Mini.Ty → List Nat → Nat → Prop
  | 0, x13, x26, x41, x70, b => True
  | n + 1, x13, x26, x41, x70, b => (match x41 with | some x180 => (Pre_find_method n x13 x26.decls x26.decls.fns 0 x70 x180 b) | none => True)

end

noncomputable section

def Cost_field_value : Nat → Lanius.Mini.Decls → Lanius.Mini.MEff → Lanius.Mini.Ty → Nat → Nat
  | 0, x12, x26, x35, x42 => 18446744073709551616
  | n + 1, x12, x26, x35, x42 => (if (Lanius.Mini.effPlace x26) = true then 1 else (match (Lanius.Mini.referent x35) with | some x179 => (1 + 1) | none => (match (Lanius.Mini.effLocal x26) with | some x285 => 0 | none => ((Cost_projection n x12 x35 x42) + ((Cost_single_of_mini_selfhost_MEff n x26) + 1)))))

end
noncomputable section

def Pre_field_value : Nat → Lanius.Mini.Decls → Lanius.Mini.MEff → Lanius.Mini.Ty → Nat → Nat → Prop
  | 0, x12, x26, x35, x42, b => True
  | n + 1, x12, x26, x35, x42, b => (if (Lanius.Mini.effPlace x26) = true then True else (match (Lanius.Mini.referent x35) with | some x179 => True | none => (match (Lanius.Mini.effLocal x26) with | some x285 => True | none => (Pre_projection n x12 x35 x42 b))))

end

noncomputable section

def Cost_field_of_ty : Nat → Lanius.Mini.FrontEnv → Lanius.Mini.MEff → Option Lanius.Mini.Ty → List Nat → Nat
  | 0, x12, x27, x36, x65 => 18446744073709551616
  | n + 1, x12, x27, x36, x65 => (match x36 with | some x174 => (match (Lanius.Mini.fieldIndex x12 ((Lanius.Mini.referentOr x174)) x65) with | some x274 => (Cost_field_value n x12.decls x27 x174 x274) | none => 0) | none => 0)

end
noncomputable section

def Pre_field_of_ty : Nat → Lanius.Mini.FrontEnv → Lanius.Mini.MEff → Option Lanius.Mini.Ty → List Nat → Nat → Prop
  | 0, x12, x27, x36, x65, b => True
  | n + 1, x12, x27, x36, x65, b => (match x36 with | some x174 => ((Pre_field_index n x12 (Lanius.Mini.referentOr x174) x65 b) ∧ (match (Lanius.Mini.fieldIndex x12 ((Lanius.Mini.referentOr x174)) x65) with | some x274 => (Pre_field_value n x12.decls x27 x174 x274 b) | none => True)) | none => True)

end

noncomputable section

mutual
def Cost_binders_of : Nat → Lanius.Mini.FrontEnv → List Lanius.Mini.Local → List Lanius.Mini.CTree → List Lanius.Mini.Ty → Nat
  | 0, x11, x26, x46, x65 => 18446744073709551616
  | n + 1, x11, x26, x46, x65 => (match x65 with | [] => 0 | x298 :: x301 => (match x46 with | [] => 0 | x367 :: x370 => (Cost_binder_of n x11 x26 x367 x298 x370 x301)))
termination_by structural fuel => fuel

def Cost_binder_of : Nat → Lanius.Mini.FrontEnv → List Lanius.Mini.Local → Lanius.Mini.CTree → Lanius.Mini.Ty → List Lanius.Mini.CTree → List Lanius.Mini.Ty → Nat
  | 0, x10, x25, x45, x55, x62, x81 => 18446744073709551616
  | n + 1, x10, x25, x45, x55, x62, x81 => (let k2 := ((Cost_cons_of_mini_selfhost_Local n (Lanius.Mini.Local.mk ((Lanius.Mini.kidToken ((Lanius.Mini.kid ((Lanius.Mini.kid x45 0)) 0)) 0).text) (((Lanius.Mini.kidToken ((Lanius.Mini.kid ((Lanius.Mini.kid x45 0)) 0)) 0).start) - x10.base) x55) x25) + ((Cost_binders_of n x10 ((Lanius.Mini.Local.mk ((Lanius.Mini.kidToken ((Lanius.Mini.kid ((Lanius.Mini.kid x45 0)) 0)) 0).text) (((Lanius.Mini.kidToken ((Lanius.Mini.kid ((Lanius.Mini.kid x45 0)) 0)) 0).start) - x10.base) x55) :: x25) x62 x81) + (Cost_cons_binder n (((Lanius.Mini.kidToken ((Lanius.Mini.kid ((Lanius.Mini.kid x45 0)) 0)) 0).start) - x10.base) (Lanius.Mini.bindersOf x10 (((Lanius.Mini.Local.mk ((Lanius.Mini.kidToken ((Lanius.Mini.kid ((Lanius.Mini.kid x45 0)) 0)) 0).text) (((Lanius.Mini.kidToken ((Lanius.Mini.kid ((Lanius.Mini.kid x45 0)) 0)) 0).start) - x10.base) x55) :: x25)) x62 x81)))); let k3 := 0; (if (decide ((Lanius.Mini.nodeProd x45) = Lanius.Mini.Inline.pPatternIdent)) = true then (if (decide ((Lanius.Mini.nodeProd ((Lanius.Mini.kid x45 1))) = Lanius.Mini.Inline.pPatternPlain)) = true then (if (Lanius.Mini.isSomeName ((Lanius.Mini.pathName ((Lanius.Mini.kid x45 0))))) = true then (if (!(Lanius.Mini.member x10.globals (((Lanius.Mini.kidToken ((Lanius.Mini.kid ((Lanius.Mini.kid x45 0)) 0)) 0).text)))) = true then (if (!(Lanius.Mini.anyVariant x10.decls.types (((Lanius.Mini.kidToken ((Lanius.Mini.kid ((Lanius.Mini.kid x45 0)) 0)) 0).text)))) = true then (if (Lanius.Mini.freshId x25 ((((Lanius.Mini.kidToken ((Lanius.Mini.kid ((Lanius.Mini.kid x45 0)) 0)) 0).start) - x10.base))) = true then k2 else k3) else k3) else k3) else k3) else k3) else k3))
termination_by structural fuel => fuel
end

end

noncomputable section

mutual
def Cost_eff_of : Nat → Nat → Lanius.Mini.FrontEnv → List Lanius.Mini.Local → Option Lanius.Mini.Ty → Lanius.Mini.CTree → Nat
  | 0, x7, x20, x35, x55, x91 => 18446744073709551616
  | n + 1, x7, x20, x35, x55, x91 => (if (decide (x7 = 0)) = true then 0 else ((Cost_expr_of n x7 x20 x35 x91) + (match (Lanius.Mini.exprOf x7 x20 x35 x91) with | some x244 => 0 | none => (Cost_eff_node n (x7 - 1) x20 x35 x55 x91))))
termination_by structural fuel => fuel

def Cost_eff_node : Nat → Nat → Lanius.Mini.FrontEnv → List Lanius.Mini.Local → Option Lanius.Mini.Ty → Lanius.Mini.CTree → Nat
  | 0, x9, x22, x37, x57, x93 => 18446744073709551616
  | n + 1, x9, x22, x37, x57, x93 => (if (decide (x9 = 0)) = true then 0 else (let k5 := (Cost_eff_of n (x9 - 1) x22 x37 x57 (Lanius.Mini.kid x93 0)); let k6 := (let k3 := (Cost_eff_of n (x9 - 1) x22 x37 x57 (Lanius.Mini.kid x93 0)); let k4 := (if (Lanius.Mini.isLevel ((Lanius.Mini.nodeProd x93))) = true then ((Cost_eff_of n (x9 - 1) x22 x37 (none : Option Lanius.Mini.Ty) (Lanius.Mini.kid x93 0)) + (Cost_eff_fold n (x9 - 1) x22 x37 (Lanius.Mini.effOf ((x9 - 1)) x22 x37 ((none : Option Lanius.Mini.Ty)) ((Lanius.Mini.kid x93 0))) (Lanius.Mini.kid x93 1))) else (if (decide ((Lanius.Mini.nodeProd x93) = Lanius.Mini.Inline.pCast)) = true then ((Cost_eff_of n (x9 - 1) x22 x37 (none : Option Lanius.Mini.Ty) (Lanius.Mini.kid x93 0)) + (Cost_eff_casts n (x9 - 1) x22 (Lanius.Mini.effOf ((x9 - 1)) x22 x37 ((none : Option Lanius.Mini.Ty)) ((Lanius.Mini.kid x93 0))) (Lanius.Mini.kid x93 1))) else (if (decide ((Lanius.Mini.nodeProd x93) = Lanius.Mini.Inline.pNeg)) = true then ((Cost_eff_of n (x9 - 1) x22 x37 x57 (Lanius.Mini.kid x93 1)) + (Cost_x_neg_of n (Lanius.Mini.effOf ((x9 - 1)) x22 x37 x57 ((Lanius.Mini.kid x93 1))))) else (if (decide ((Lanius.Mini.nodeProd x93) = Lanius.Mini.Inline.pNot)) = true then ((Cost_eff_of n (x9 - 1) x22 x37 (some Lanius.Mini.Ty.tyBool) (Lanius.Mini.kid x93 1)) + (Cost_x_not_of n (Lanius.Mini.effOf ((x9 - 1)) x22 x37 ((some Lanius.Mini.Ty.tyBool)) ((Lanius.Mini.kid x93 1))))) else (if (decide ((Lanius.Mini.nodeProd x93) = Lanius.Mini.Inline.pPostfix)) = true then (Cost_eff_postfix n (x9 - 1) x22 x37 x57 x93) else (if (decide ((Lanius.Mini.nodeProd x93) = Lanius.Mini.Inline.pGroup)) = true then (Cost_eff_of n (x9 - 1) x22 x37 x57 (Lanius.Mini.kid x93 1)) else (if (decide ((Lanius.Mini.nodeProd x93) = Lanius.Mini.Inline.pIdent)) = true then (Cost_eff_ident n (x9 - 1) x22 x37 x57 x93) else (if (decide ((Lanius.Mini.nodeProd x93) = Lanius.Mini.Inline.pMatchExpr)) = true then (Cost_eff_match n (x9 - 1) x22 x37 x57 x93) else (if (decide ((Lanius.Mini.nodeProd x93) = Lanius.Mini.Inline.pArrayLit)) = true then (Cost_eff_array n (x9 - 1) x22 x37 x57 (Lanius.Mini.kid x93 1)) else 0))))))))); (if (decide ((Lanius.Mini.nodeProd x93) = Lanius.Mini.Inline.pAssign)) = true then (if (!(Lanius.Mini.hasKids ((Lanius.Mini.kid x93 1)))) = true then k3 else k4) else (if (Lanius.Mini.isLevel ((Lanius.Mini.nodeProd x93))) = true then (if (!(Lanius.Mini.hasKids ((Lanius.Mini.kid x93 1)))) = true then k3 else k4) else (if (decide ((Lanius.Mini.nodeProd x93) = Lanius.Mini.Inline.pCast)) = true then (if (!(Lanius.Mini.hasKids ((Lanius.Mini.kid x93 1)))) = true then k3 else k4) else k4)))); (if (decide ((Lanius.Mini.nodeProd x93) = Lanius.Mini.Inline.pExpr)) = true then k5 else (if (decide ((Lanius.Mini.nodeProd x93) = Lanius.Mini.Inline.pBase)) = true then k5 else k6))))
termination_by structural fuel => fuel

def Cost_eff_fold : Nat → Nat → Lanius.Mini.FrontEnv → List Lanius.Mini.Local → Option Lanius.Mini.MEff → Lanius.Mini.CTree → Nat
  | 0, x9, x22, x37, x57, x90 => 18446744073709551616
  | n + 1, x9, x22, x37, x57, x90 => (if (decide (x9 = 0)) = true then 0 else (if (Lanius.Mini.hasKids x90) = true then ((Cost_eff_of n (x9 - 1) x22 x37 (none : Option Lanius.Mini.Ty) (Lanius.Mini.kid x90 1)) + ((Cost_eff_binary n (Lanius.Mini.nodeProd x90) x57 (Lanius.Mini.effOf ((x9 - 1)) x22 x37 ((none : Option Lanius.Mini.Ty)) ((Lanius.Mini.kid x90 1)))) + (Cost_eff_fold n (x9 - 1) x22 x37 (Lanius.Mini.effBinary ((Lanius.Mini.nodeProd x90)) x57 ((Lanius.Mini.effOf ((x9 - 1)) x22 x37 ((none : Option Lanius.Mini.Ty)) ((Lanius.Mini.kid x90 1))))) (Lanius.Mini.kid x90 2)))) else 0))
termination_by structural fuel => fuel

def Cost_eff_postfix : Nat → Nat → Lanius.Mini.FrontEnv → List Lanius.Mini.Local → Option Lanius.Mini.Ty → Lanius.Mini.CTree → Nat
  | 0, x12, x25, x40, x60, x96 => 18446744073709551616
  | n + 1, x12, x25, x40, x60, x96 => (if (decide (x12 = 0)) = true then 0 else (if (decide ((Lanius.Mini.nodeProd ((Lanius.Mini.kid x96 1))) = Lanius.Mini.Inline.pPostfixEnd)) = true then (Cost_eff_node n (x12 - 1) x25 x40 x60 (Lanius.Mini.kid x96 0)) else (if (Lanius.Mini.isPathCall x96) = true then (Cost_eff_path_call n (x12 - 1) x25 x40 x60 (Lanius.Mini.kid ((Lanius.Mini.kid x96 0)) 0) (Lanius.Mini.kid ((Lanius.Mini.kid x96 1)) 1)) else (if (Lanius.Mini.isMethodForm x96) = true then (Cost_eff_method n (x12 - 1) x25 x40 x60 x96) else (let k5 := ((Cost_local_of n x25 x40 (Lanius.Mini.kid x96 0)) + ((Cost_eff_of n (x12 - 1) x25 x40 (none : Option Lanius.Mini.Ty) (Lanius.Mini.kid ((Lanius.Mini.kid x96 1)) 1)) + (Cost_x_index_of n (Lanius.Mini.localOf x25 x40 ((Lanius.Mini.kid x96 0))) (Lanius.Mini.effOf ((x12 - 1)) x25 x40 ((none : Option Lanius.Mini.Ty)) ((Lanius.Mini.kid ((Lanius.Mini.kid x96 1)) 1)))))); let k6 := (let k3 := ((Cost_eff_path_call n (x12 - 1) x25 x40 (none : Option Lanius.Mini.Ty) (Lanius.Mini.kid ((Lanius.Mini.kid x96 0)) 0) (Lanius.Mini.kid ((Lanius.Mini.kid x96 1)) 1)) + (Cost_eff_chain n (x12 - 1) x25 x40 x60 (Lanius.Mini.effPathCall ((x12 - 1)) x25 x40 ((none : Option Lanius.Mini.Ty)) ((Lanius.Mini.kid ((Lanius.Mini.kid x96 0)) 0)) ((Lanius.Mini.kid ((Lanius.Mini.kid x96 1)) 1))) (Lanius.Mini.kid ((Lanius.Mini.kid x96 1)) 3))); let k4 := ((Cost_eff_primary n (x12 - 1) x25 x40 (Lanius.Mini.kid x96 0)) + (Cost_eff_chain n (x12 - 1) x25 x40 x60 (Lanius.Mini.effPrimary ((x12 - 1)) x25 x40 ((Lanius.Mini.kid x96 0))) (Lanius.Mini.kid x96 1))); (if (decide ((Lanius.Mini.nodeProd ((Lanius.Mini.kid x96 0))) = Lanius.Mini.Inline.pIdent)) = true then (if (decide ((Lanius.Mini.nodeProd ((Lanius.Mini.kid ((Lanius.Mini.kid x96 0)) 1))) = Lanius.Mini.Inline.pIdentPlain)) = true then (if (decide ((Lanius.Mini.nodeProd ((Lanius.Mini.kid x96 1))) = Lanius.Mini.Inline.pPostfixCall)) = true then k3 else k4) else k4) else k4)); (if (decide ((Lanius.Mini.nodeProd ((Lanius.Mini.kid x96 0))) = Lanius.Mini.Inline.pIdent)) = true then (if (decide ((Lanius.Mini.nodeProd ((Lanius.Mini.kid ((Lanius.Mini.kid x96 0)) 1))) = Lanius.Mini.Inline.pIdentPlain)) = true then (if (decide ((Lanius.Mini.nodeProd ((Lanius.Mini.kid x96 1))) = Lanius.Mini.Inline.pPostfixIndex)) = true then (if (decide ((Lanius.Mini.nodeProd ((Lanius.Mini.kid ((Lanius.Mini.kid x96 1)) 3))) = Lanius.Mini.Inline.pPostfixEnd)) = true then k5 else k6) else k6) else k6) else k6))))))
termination_by structural fuel => fuel

def Cost_eff_ident : Nat → Nat → Lanius.Mini.FrontEnv → List Lanius.Mini.Local → Option Lanius.Mini.Ty → Lanius.Mini.CTree → Nat
  | 0, x10, x23, x38, x58, x94 => 18446744073709551616
  | n + 1, x10, x23, x38, x58, x94 => (if (decide (x10 = 0)) = true then 0 else (if (decide ((Lanius.Mini.nodeProd ((Lanius.Mini.kid x94 1))) = Lanius.Mini.Inline.pIdentPlain)) = true then ((Cost_path_spellings n x10 (Lanius.Mini.kid ((Lanius.Mini.kid x94 0)) 0) (Lanius.Mini.kid ((Lanius.Mini.kid x94 0)) 1)) + (match (Lanius.Mini.pathSpellings x10 ((Lanius.Mini.kid ((Lanius.Mini.kid x94 0)) 0)) ((Lanius.Mini.kid ((Lanius.Mini.kid x94 0)) 1))) with | some x385 => ((Cost_split_last n x385) + (match (Lanius.Mini.splitLast x385) with | some x468 => ((Cost_local_of n x23 x38 x94) + (if (!(Lanius.Mini.hasLocal ((Lanius.Mini.localOf x23 x38 x94)))) = true then ((Cost_path_module n x23 x468.home x468.name) + ((Cost_variant_by_path n x23 x468) + (Cost_eff_variant n (x10 - 1) x23 x38 x58 (Lanius.Mini.variantByPath x23 x468) ([] : List Lanius.Mini.CTree)))) else ((Cost_variant_by_path n x23 x468) + (Cost_eff_variant n (x10 - 1) x23 x38 x58 (Lanius.Mini.variantByPath x23 x468) ([] : List Lanius.Mini.CTree))))) | none => 0)) | none => 0)) else (if (decide ((Lanius.Mini.nodeProd ((Lanius.Mini.kid x94 1))) = Lanius.Mini.Inline.pStructLit)) = true then ((Cost_path_spellings n x10 (Lanius.Mini.kid ((Lanius.Mini.kid x94 0)) 0) (Lanius.Mini.kid ((Lanius.Mini.kid x94 0)) 1)) + (match (Lanius.Mini.pathSpellings x10 ((Lanius.Mini.kid ((Lanius.Mini.kid x94 0)) 0)) ((Lanius.Mini.kid ((Lanius.Mini.kid x94 0)) 1))) with | some x894 => ((Cost_list_items n x10 (Lanius.Mini.kid ((Lanius.Mini.kid x94 1)) 1)) + (match (Lanius.Mini.listItems x10 ((Lanius.Mini.kid ((Lanius.Mini.kid x94 1)) 1))) with | some x998 => ((Cost_type_decl_at n x23 x894) + (match (Lanius.Mini.typeDeclAt x23 x894) with | some x1096 => (match (x23.decls.types[x1096]?) with | some x1203 => (Cost_eff_literal n (x10 - 1) x23 x38 x58 x1096 x1203 x998) | none => 0) | none => 0)) | none => 0)) | none => 0)) else 0)))
termination_by structural fuel => fuel

def Cost_eff_match : Nat → Nat → Lanius.Mini.FrontEnv → List Lanius.Mini.Local → Option Lanius.Mini.Ty → Lanius.Mini.CTree → Nat
  | 0, x10, x23, x38, x58, x94 => 18446744073709551616
  | n + 1, x10, x23, x38, x58, x94 => (if (decide (x10 = 0)) = true then 0 else ((Cost_eff_of n (x10 - 1) x23 x38 (none : Option Lanius.Mini.Ty) (Lanius.Mini.kid x94 2)) + (Cost_eff_match_on n (x10 - 1) x23 x38 x58 (Lanius.Mini.effOf ((x10 - 1)) x23 x38 ((none : Option Lanius.Mini.Ty)) ((Lanius.Mini.kid x94 2))) x94)))
termination_by structural fuel => fuel

def Cost_eff_array : Nat → Nat → Lanius.Mini.FrontEnv → List Lanius.Mini.Local → Option Lanius.Mini.Ty → Lanius.Mini.CTree → Nat
  | 0, x10, x23, x38, x58, x94 => 18446744073709551616
  | n + 1, x10, x23, x38, x58, x94 => (if (decide (x10 = 0)) = true then 0 else (let k2 := (match (Lanius.Mini.expectedArray x58) with | some x410 => ((Cost_eff_of n (x10 - 1) x23 x38 (some x410.element) (Lanius.Mini.kid x94 0)) + (Cost_array_repeat_of n x410 (Lanius.Mini.decimal ((((Lanius.Mini.kidToken ((Lanius.Mini.kid ((Lanius.Mini.kid x94 1)) 1)) 0)).text)) 0) (Lanius.Mini.effOf ((x10 - 1)) x23 x38 ((some x410.element)) ((Lanius.Mini.kid x94 0))))) | none => 0); let k3 := (match (Lanius.Mini.expectedArray x58) with | some x643 => ((Cost_list_items n (x10 - 1) x94) + (match (Lanius.Mini.listItems ((x10 - 1)) x94) with | some x723 => ((Cost_repeat_ty n x643.element x643.count) + ((Cost_eff_list n (x10 - 1) x23 x38 (some (Lanius.Mini.repeatTy x643.element x643.count)) x723) + (Cost_array_of n x643 (Lanius.Mini.effList ((x10 - 1)) x23 x38 ((some (Lanius.Mini.repeatTy x643.element x643.count))) x723)))) | none => 0)) | none => 0); (if (decide ((Lanius.Mini.nodeProd x94) = Lanius.Mini.Inline.pArraySome)) = true then (if (decide ((Lanius.Mini.nodeProd ((Lanius.Mini.kid x94 1))) = Lanius.Mini.Inline.pArrayRepeat)) = true then k2 else k3) else k3)))
termination_by structural fuel => fuel

def Cost_eff_path_call : Nat → Nat → Lanius.Mini.FrontEnv → List Lanius.Mini.Local → Option Lanius.Mini.Ty → Lanius.Mini.CTree → Lanius.Mini.CTree → Nat
  | 0, x14, x27, x42, x62, x98, x111 => 18446744073709551616
  | n + 1, x14, x27, x42, x62, x98, x111 => (if (decide (x14 = 0)) = true then 0 else ((Cost_path_spellings n x14 (Lanius.Mini.kid x98 0) (Lanius.Mini.kid x98 1)) + (let k2 := 0; let k3 := ((Cost_text_slice_stride n ) + ((Cost_single_of_mini_selfhost_List_usize n Lanius.Mini.textSliceStride) + (if (Lanius.Mini.isPath ((Lanius.Mini.pathSpellings x14 ((Lanius.Mini.kid x98 0)) ((Lanius.Mini.kid x98 1)))) ([Lanius.Mini.textSliceStride])) = true then ((Cost_list_items n x14 x111) + (match (Lanius.Mini.listItems x14 x111) with | some x628 => (Cost_stride_arg n x14 x27 x42 x628) | none => 0)) else ((Cost_text_slice_len n ) + ((Cost_single_of_mini_selfhost_List_usize n Lanius.Mini.textSliceLen) + (if (Lanius.Mini.isPath ((Lanius.Mini.pathSpellings x14 ((Lanius.Mini.kid x98 0)) ((Lanius.Mini.kid x98 1)))) ([Lanius.Mini.textSliceLen])) = true then ((Cost_list_items n x14 x111) + (match (Lanius.Mini.listItems x14 x111) with | some x838 => (Cost_len_arg n x14 x27 x42 x838) | none => 0)) else ((Cost_path_ref n x14 (Lanius.Mini.kid x98 0) (Lanius.Mini.kid x98 1)) + (match (Lanius.Mini.pathRef x14 ((Lanius.Mini.kid x98 0)) ((Lanius.Mini.kid x98 1))) with | some x998 => ((Cost_named_split n x998.segments) + (match (Lanius.Mini.namedSplit x998.segments) with | some x1083 => ((Cost_list_items n x14 x111) + (match (Lanius.Mini.listItems x14 x111) with | some x1173 => (Cost_eff_named n (x14 - 1) x27 x42 x62 x1083 x998.targs x1173) | none => 0)) | none => 0)) | none => 0)))))))); ((Cost_alloc_path n ) + (if (Lanius.Mini.isPath ((Lanius.Mini.pathSpellings x14 ((Lanius.Mini.kid x98 0)) ((Lanius.Mini.kid x98 1)))) Lanius.Mini.allocPath) = true then k2 else ((Cost_dealloc_path n ) + (if (Lanius.Mini.isPath ((Lanius.Mini.pathSpellings x14 ((Lanius.Mini.kid x98 0)) ((Lanius.Mini.kid x98 1)))) Lanius.Mini.deallocPath) = true then k2 else ((Cost_text_slice_from_raw_parts n ) + ((Cost_single_of_mini_selfhost_List_usize n Lanius.Mini.textSliceFromRawParts) + (if (Lanius.Mini.isPath ((Lanius.Mini.pathSpellings x14 ((Lanius.Mini.kid x98 0)) ((Lanius.Mini.kid x98 1)))) ([Lanius.Mini.textSliceFromRawParts])) = true then k2 else k3))))))))))
termination_by structural fuel => fuel

def Cost_eff_method : Nat → Nat → Lanius.Mini.FrontEnv → List Lanius.Mini.Local → Option Lanius.Mini.Ty → Lanius.Mini.CTree → Nat
  | 0, x11, x24, x39, x59, x95 => 18446744073709551616
  | n + 1, x11, x24, x39, x59, x95 => (if (decide (x11 = 0)) = true then 0 else ((Cost_local_of n x24 x39 (Lanius.Mini.kid x95 0)) + (match (Lanius.Mini.localOf x24 x39 ((Lanius.Mini.kid x95 0))) with | some x309 => ((Cost_list_items n x11 (Lanius.Mini.kid ((Lanius.Mini.kid ((Lanius.Mini.kid x95 1)) 3)) 1)) + (match (Lanius.Mini.listItems x11 ((Lanius.Mini.kid ((Lanius.Mini.kid ((Lanius.Mini.kid x95 1)) 3)) 1))) with | some x407 => ((Cost_find_method n x11 x24.decls x24.decls.fns 0 (((Lanius.Mini.kidToken ((Lanius.Mini.kid x95 1)) 1)).text) (Lanius.Mini.referentOr x309.ty)) + ((Cost_single_of_mini_selfhost_MEff n (Lanius.Mini.MEff.xPure (Lanius.Mini.SrcExpr.local x309.id))) + (Cost_eff_found_with n (x11 - 1) x24 x39 x59 (Lanius.Mini.findMethod x11 x24.decls x24.decls.fns 0 ((((Lanius.Mini.kidToken ((Lanius.Mini.kid x95 1)) 1)).text)) ((Lanius.Mini.referentOr x309.ty))) (Lanius.Mini.kid ((Lanius.Mini.kid x95 1)) 2) ([(Lanius.Mini.MEff.xPure (Lanius.Mini.SrcExpr.local x309.id))]) x407))) | none => 0)) | none => 0)))
termination_by structural fuel => fuel

def Cost_eff_chain : Nat → Nat → Lanius.Mini.FrontEnv → List Lanius.Mini.Local → Option Lanius.Mini.Ty → Option Lanius.Mini.MEff → Lanius.Mini.CTree → Nat
  | 0, x10, x23, x38, x58, x94, x125 => 18446744073709551616
  | n + 1, x10, x23, x38, x58, x94, x125 => (if (decide (x10 = 0)) = true then 0 else (if (decide ((Lanius.Mini.nodeProd x125) = Lanius.Mini.Inline.pPostfixEnd)) = true then 0 else (match x94 with | some x346 => (Cost_eff_step n (x10 - 1) x23 x38 x58 x346 x125) | none => 0)))
termination_by structural fuel => fuel

def Cost_eff_primary : Nat → Nat → Lanius.Mini.FrontEnv → List Lanius.Mini.Local → Lanius.Mini.CTree → Nat
  | 0, x12, x25, x40, x60 => 18446744073709551616
  | n + 1, x12, x25, x40, x60 => ((Cost_local_of n x25 x40 x60) + (match (Lanius.Mini.localOf x25 x40 x60) with | some x172 => 0 | none => (Cost_eff_node n x12 x25 x40 (none : Option Lanius.Mini.Ty) x60)))
termination_by structural fuel => fuel

def Cost_eff_variant : Nat → Nat → Lanius.Mini.FrontEnv → List Lanius.Mini.Local → Option Lanius.Mini.Ty → Option Lanius.Mini.VariantAt → List Lanius.Mini.CTree → Nat
  | 0, x12, x25, x40, x60, x96, x132 => 18446744073709551616
  | n + 1, x12, x25, x40, x60, x96, x132 => (if (decide (x12 = 0)) = true then 0 else (match x96 with | some x290 => (match (x25.decls.types[x290.owner]?) with | some x379 => (if (!(Lanius.Mini.hasTys ((Lanius.Mini.knownArgs x379 x290.owner x60)))) = true then ((Cost_variant_expects n x12 x25.decls x290.owner x290.index (Lanius.Mini.knownArgs x379 x290.owner x60)) + ((Cost_eff_list n (x12 - 1) x25 x40 (Lanius.Mini.variantExpects x12 x25.decls x290.owner x290.index ((Lanius.Mini.knownArgs x379 x290.owner x60))) x132) + (Cost_x_variant_of n x12 x25 x40 x290.owner x379 x290.index (Lanius.Mini.knownArgs x379 x290.owner x60) (Lanius.Mini.effList ((x12 - 1)) x25 x40 ((Lanius.Mini.variantExpects x12 x25.decls x290.owner x290.index ((Lanius.Mini.knownArgs x379 x290.owner x60)))) x132)))) else ((Cost_variant_expects n x12 x25.decls x290.owner x290.index (Lanius.Mini.knownArgs x379 x290.owner x60)) + ((Cost_variant_expects n x12 x25.decls x290.owner x290.index (Lanius.Mini.knownArgs x379 x290.owner x60)) + ((Cost_eff_list n (x12 - 1) x25 x40 (Lanius.Mini.variantExpects x12 x25.decls x290.owner x290.index ((Lanius.Mini.knownArgs x379 x290.owner x60))) x132) + (Cost_x_variant_of n x12 x25 x40 x290.owner x379 x290.index (Lanius.Mini.knownArgs x379 x290.owner x60) (Lanius.Mini.effList ((x12 - 1)) x25 x40 ((Lanius.Mini.variantExpects x12 x25.decls x290.owner x290.index ((Lanius.Mini.knownArgs x379 x290.owner x60)))) x132)))))) | none => 0) | none => 0))
termination_by structural fuel => fuel

def Cost_eff_literal : Nat → Nat → Lanius.Mini.FrontEnv → List Lanius.Mini.Local → Option Lanius.Mini.Ty → Nat → Lanius.Mini.TypeDecl → List Lanius.Mini.CTree → Nat
  | 0, x12, x25, x40, x60, x96, x106, x119 => 18446744073709551616
  | n + 1, x12, x25, x40, x60, x96, x106, x119 => (if (decide (x12 = 0)) = true then 0 else (let k2 := ((Cost_field_expects n x12 x25.decls x96 (Lanius.Mini.knownArgs x106 x96 x60)) + ((Cost_field_values n x119) + ((Cost_eff_list n (x12 - 1) x25 x40 (Lanius.Mini.fieldExpects x12 x25.decls x96 ((Lanius.Mini.knownArgs x106 x96 x60))) (Lanius.Mini.fieldValues x119)) + (Cost_x_struct_of n x12 x25 x40 x96 x106 (Lanius.Mini.knownArgs x106 x96 x60) (Lanius.Mini.effList ((x12 - 1)) x25 x40 ((Lanius.Mini.fieldExpects x12 x25.decls x96 ((Lanius.Mini.knownArgs x106 x96 x60)))) ((Lanius.Mini.fieldValues x119))))))); let k3 := 0; (if (!x106.isEnum) = true then (if (Lanius.Mini.sameNames x106.fields x119) = true then k2 else k3) else k3)))
termination_by structural fuel => fuel

def Cost_eff_match_on : Nat → Nat → Lanius.Mini.FrontEnv → List Lanius.Mini.Local → Option Lanius.Mini.Ty → Option Lanius.Mini.MEff → Lanius.Mini.CTree → Nat
  | 0, x13, x26, x41, x61, x97, x128 => 18446744073709551616
  | n + 1, x13, x26, x41, x61, x97, x128 => (if (decide (x13 = 0)) = true then 0 else (match x97 with | some x276 => ((Cost_eff_ty n x13 x26 x41 x276) + (match (Lanius.Mini.effTy x13 x26 x41 x276) with | some x363 => (match (Lanius.Mini.namedParts x363) with | some x753 => (match (x26.decls.types[x753.decl]?) with | some x857 => ((Cost_payload_tys n x13 x26.decls x753.decl x753.args) + (Cost_eff_match_enum n (x13 - 1) x26 x41 x61 x276 x363 x857 (Lanius.Mini.payloadTys x13 x26.decls x753.decl x753.args) x128)) | none => 0) | none => ((Cost_list_items n x13 (Lanius.Mini.kid x128 5)) + (match (Lanius.Mini.listItems x13 ((Lanius.Mini.kid x128 5))) with | some x519 => ((Cost_lit_wants n x61 x519) + ((Cost_arm_value_trees n x519) + ((Cost_eff_list n (x13 - 1) x26 x41 (Lanius.Mini.litWants x61 x519) (Lanius.Mini.armValueTrees x519)) + (Cost_lit_eff_match n x13 x26 x41 x61 ((((Lanius.Mini.kidToken x128 0)).start) - x26.base) x276 x363 x519 (Lanius.Mini.effList ((x13 - 1)) x26 x41 ((Lanius.Mini.litWants x61 x519)) ((Lanius.Mini.armValueTrees x519))))))) | none => 0))) | none => 0)) | none => 0))
termination_by structural fuel => fuel

def Cost_eff_list : Nat → Nat → Lanius.Mini.FrontEnv → List Lanius.Mini.Local → Option (List Lanius.Mini.Ty) → List Lanius.Mini.CTree → Nat
  | 0, x9, x22, x37, x57, x98 => 18446744073709551616
  | n + 1, x9, x22, x37, x57, x98 => (if (decide (x9 = 0)) = true then 0 else (match x98 with | [] => 0 | x274 :: x277 => ((Cost_eff_of n (x9 - 1) x22 x37 (Lanius.Mini.headTy x57) x274) + ((Cost_eff_list n (x9 - 1) x22 x37 (Lanius.Mini.tailTys x57) x277) + (Cost_cons_eff n (Lanius.Mini.effOf ((x9 - 1)) x22 x37 ((Lanius.Mini.headTy x57)) x274) (Lanius.Mini.effList ((x9 - 1)) x22 x37 ((Lanius.Mini.tailTys x57)) x277))))))
termination_by structural fuel => fuel

def Cost_eff_named : Nat → Nat → Lanius.Mini.FrontEnv → List Lanius.Mini.Local → Option Lanius.Mini.Ty → Lanius.Mini.Split → List Lanius.Mini.CTree → List Lanius.Mini.CTree → Nat
  | 0, x10, x23, x38, x58, x94, x104, x124 => 18446744073709551616
  | n + 1, x10, x23, x38, x58, x94, x104, x124 => (if (decide (x10 = 0)) = true then 0 else ((Cost_is_fn_path n x23 x94) + (if (Lanius.Mini.isFnPath x23 x94) = true then (Cost_eff_fn_path n (x10 - 1) x23 x38 x58 x94 x104 x124) else (if (Lanius.Mini.noTrees x104) = true then ((Cost_variant_by_path n x23 x94) + (Cost_eff_variant n (x10 - 1) x23 x38 x58 (Lanius.Mini.variantByPath x23 x94) x124)) else 0))))
termination_by structural fuel => fuel

def Cost_eff_found_with : Nat → Nat → Lanius.Mini.FrontEnv → List Lanius.Mini.Local → Option Lanius.Mini.Ty → Option Lanius.Mini.Found → Lanius.Mini.CTree → List Lanius.Mini.MEff → List Lanius.Mini.CTree → Nat
  | 0, x15, x28, x43, x63, x99, x135, x149, x166 => 18446744073709551616
  | n + 1, x15, x28, x43, x63, x99, x135, x149, x166 => (if (decide (x15 = 0)) = true then 0 else (match x99 with | some x328 => (match (x28.decls.fns[x328.decl]?) with | some x414 => ((Cost_method_binds n (x15 - 1) x28 x414 x328.binds x135) + ((Cost_receivers_of n (x15 - 1) x28 x43 x414 x149) + (Cost_eff_bound_recv n (x15 - 1) x28 x43 x63 x328.decl x414 (Lanius.Mini.methodBinds ((x15 - 1)) x28 x414 x328.binds x135) (Lanius.Mini.receiversOf ((x15 - 1)) x28 x43 x414 x149) x166))) | none => 0) | none => 0))
termination_by structural fuel => fuel

def Cost_eff_step : Nat → Nat → Lanius.Mini.FrontEnv → List Lanius.Mini.Local → Option Lanius.Mini.Ty → Lanius.Mini.MEff → Lanius.Mini.CTree → Nat
  | 0, x9, x22, x37, x57, x93, x102 => 18446744073709551616
  | n + 1, x9, x22, x37, x57, x93, x102 => (if (decide (x9 = 0)) = true then 0 else (let k5 := (if (decide ((Lanius.Mini.nodeProd ((Lanius.Mini.kid x102 3))) = Lanius.Mini.Inline.pPostfixCall)) = true then ((Cost_list_items n (x9 - 1) (Lanius.Mini.kid ((Lanius.Mini.kid x102 3)) 1)) + (match (Lanius.Mini.listItems ((x9 - 1)) ((Lanius.Mini.kid ((Lanius.Mini.kid x102 3)) 1))) with | some x518 => ((Cost_eff_ty n (x9 - 1) x22 x37 x93) + ((Cost_method_of_ty n (x9 - 1) x22 (Lanius.Mini.referentOrOf ((Lanius.Mini.effTy ((x9 - 1)) x22 x37 x93))) (((Lanius.Mini.kidToken x102 1)).text)) + ((Cost_single_of_mini_selfhost_MEff n x93) + ((Cost_eff_found_with n (x9 - 1) x22 x37 (Lanius.Mini.stepExpected x57 ((Lanius.Mini.kid ((Lanius.Mini.kid x102 3)) 3))) (Lanius.Mini.methodOfTy ((x9 - 1)) x22 ((Lanius.Mini.referentOrOf ((Lanius.Mini.effTy ((x9 - 1)) x22 x37 x93)))) ((((Lanius.Mini.kidToken x102 1)).text))) (Lanius.Mini.kid x102 2) ([x93]) x518) + (Cost_eff_chain n (x9 - 1) x22 x37 x57 (Lanius.Mini.effFoundWith ((x9 - 1)) x22 x37 ((Lanius.Mini.stepExpected x57 ((Lanius.Mini.kid ((Lanius.Mini.kid x102 3)) 3)))) ((Lanius.Mini.methodOfTy ((x9 - 1)) x22 ((Lanius.Mini.referentOrOf ((Lanius.Mini.effTy ((x9 - 1)) x22 x37 x93)))) ((((Lanius.Mini.kidToken x102 1)).text)))) ((Lanius.Mini.kid x102 2)) ([x93]) x518) (Lanius.Mini.kid ((Lanius.Mini.kid x102 3)) 3)))))) | none => 0)) else (if (decide ((Lanius.Mini.nodeProd ((Lanius.Mini.kid x102 2))) = Lanius.Mini.Inline.pMemberTypeArgsNone)) = true then ((Cost_eff_ty n (x9 - 1) x22 x37 x93) + ((Cost_field_of_ty n x22 x93 (Lanius.Mini.effTy ((x9 - 1)) x22 x37 x93) (((Lanius.Mini.kidToken x102 1)).text)) + (Cost_eff_chain n (x9 - 1) x22 x37 x57 (Lanius.Mini.fieldOfTy x22 x93 ((Lanius.Mini.effTy ((x9 - 1)) x22 x37 x93)) ((((Lanius.Mini.kidToken x102 1)).text))) (Lanius.Mini.kid x102 3)))) else 0)); let k6 := (let k3 := ((Cost_eff_of n (x9 - 1) x22 x37 (none : Option Lanius.Mini.Ty) (Lanius.Mini.kid x102 1)) + ((Cost_x_at_of n x93 (Lanius.Mini.effOf ((x9 - 1)) x22 x37 ((none : Option Lanius.Mini.Ty)) ((Lanius.Mini.kid x102 1)))) + (Cost_eff_chain n (x9 - 1) x22 x37 x57 (Lanius.Mini.xAtOf x93 ((Lanius.Mini.effOf ((x9 - 1)) x22 x37 ((none : Option Lanius.Mini.Ty)) ((Lanius.Mini.kid x102 1))))) (Lanius.Mini.kid x102 3)))); let k4 := (if (decide ((Lanius.Mini.nodeProd x102) = Lanius.Mini.Inline.pPostfixIndex)) = true then ((Cost_eff_of n (x9 - 1) x22 x37 (none : Option Lanius.Mini.Ty) (Lanius.Mini.kid x102 1)) + ((Cost_x_index_of n (Lanius.Mini.effSliceLocal x37 x93) (Lanius.Mini.effOf ((x9 - 1)) x22 x37 ((none : Option Lanius.Mini.Ty)) ((Lanius.Mini.kid x102 1)))) + (Cost_eff_chain n (x9 - 1) x22 x37 x57 (Lanius.Mini.xIndexOf ((Lanius.Mini.effSliceLocal x37 x93)) ((Lanius.Mini.effOf ((x9 - 1)) x22 x37 ((none : Option Lanius.Mini.Ty)) ((Lanius.Mini.kid x102 1))))) (Lanius.Mini.kid x102 3)))) else 0); (if (decide ((Lanius.Mini.nodeProd x102) = Lanius.Mini.Inline.pPostfixIndex)) = true then (if (Lanius.Mini.effPlace x93) = true then k3 else k4) else k4)); (if (decide ((Lanius.Mini.nodeProd x102) = Lanius.Mini.Inline.pPostfixMember)) = true then (if (Lanius.Mini.memberArgs ((Lanius.Mini.nodeProd ((Lanius.Mini.kid x102 2))))) = true then k5 else k6) else k6)))
termination_by structural fuel => fuel

def Cost_eff_match_enum : Nat → Nat → Lanius.Mini.FrontEnv → List Lanius.Mini.Local → Option Lanius.Mini.Ty → Lanius.Mini.MEff → Lanius.Mini.Ty → Lanius.Mini.TypeDecl → Option (List (List Lanius.Mini.Ty)) → Lanius.Mini.CTree → Nat
  | 0, x15, x28, x43, x63, x99, x108, x117, x130, x178 => 18446744073709551616
  | n + 1, x15, x28, x43, x63, x99, x108, x117, x130, x178 => (if (decide (x15 = 0)) = true then 0 else (if x117.isEnum = true then (match x130 with | some x366 => ((Cost_list_items n x15 (Lanius.Mini.kid x178 5)) + (match (Lanius.Mini.listItems x15 ((Lanius.Mini.kid x178 5))) with | some x462 => ((Cost_zip_variants n x117.variants x366) + ((Cost_eff_arms_ordered n (x15 - 1) x28 x43 x63 x117 (Lanius.Mini.zipVariants x117.variants x366) x462) + (Cost_x_match_of n x99 x108 x63 (Lanius.Mini.effArmsOrdered ((x15 - 1)) x28 x43 x63 x117 ((Lanius.Mini.zipVariants x117.variants x366)) x462)))) | none => 0)) | none => 0) else 0))
termination_by structural fuel => fuel

def Cost_eff_fn_path : Nat → Nat → Lanius.Mini.FrontEnv → List Lanius.Mini.Local → Option Lanius.Mini.Ty → Lanius.Mini.Split → List Lanius.Mini.CTree → List Lanius.Mini.CTree → Nat
  | 0, x12, x25, x40, x60, x96, x106, x126 => 18446744073709551616
  | n + 1, x12, x25, x40, x60, x96, x106, x126 => (if (decide (x12 = 0)) = true then 0 else (let k2 := ((Cost_bare_ty n x25 x96.home) + (match (Lanius.Mini.bareTy x25 x96.home) with | some x444 => ((Cost_find_method n x12 x25.decls x25.decls.fns 0 x96.name x444) + (Cost_eff_found n (x12 - 1) x25 x40 x60 (Lanius.Mini.findMethod x12 x25.decls x25.decls.fns 0 x96.name x444) ([] : List Lanius.Mini.MEff) x126)) | none => 0)); let k3 := ((Cost_path_module n x25 x96.home x96.name) + (match (Lanius.Mini.findFn x25.decls.fns ((Lanius.Mini.pathModule x25 x96.home x96.name)) x96.name 0) with | some x715 => (match (x25.decls.fns[x715]?) with | some x796 => (Cost_eff_free n (x12 - 1) x25 x40 x60 x715 x796 x106 x126) | none => 0) | none => 0)); ((Cost_is_type_owner n x25 x96.home x96.name) + (if (Lanius.Mini.isTypeOwner x25 x96.home x96.name) = true then (if (Lanius.Mini.noTrees x106) = true then k2 else k3) else k3))))
termination_by structural fuel => fuel

def Cost_eff_bound_recv : Nat → Nat → Lanius.Mini.FrontEnv → List Lanius.Mini.Local → Option Lanius.Mini.Ty → Nat → Lanius.Mini.FnDecl → Option (List Lanius.Mini.Bind) → Option (List Lanius.Mini.MEff) → List Lanius.Mini.CTree → Nat
  | 0, x15, x28, x43, x63, x99, x109, x121, x162, x201 => 18446744073709551616
  | n + 1, x15, x28, x43, x63, x99, x109, x121, x162, x201 => (match x162 with | some x313 => (Cost_eff_bound n x15 x28 x43 x63 x99 x109 x121 x313 x201) | none => 0)
termination_by structural fuel => fuel

def Cost_eff_arms_ordered : Nat → Nat → Lanius.Mini.FrontEnv → List Lanius.Mini.Local → Option Lanius.Mini.Ty → Lanius.Mini.TypeDecl → List Lanius.Mini.VariantTy → List Lanius.Mini.CTree → Nat
  | 0, x17, x30, x45, x65, x101, x118, x145 => 18446744073709551616
  | n + 1, x17, x30, x45, x65, x101, x118, x145 => (if (decide (x17 = 0)) = true then 0 else ((Cost_match_order n x17 x30 x101 x118 x145) + (match (Lanius.Mini.matchOrder x17 x30 x101 x118 x145) with | some x354 => (Cost_eff_arms n (x17 - 1) x30 x45 x65 x101 x118 x354) | none => 0)))
termination_by structural fuel => fuel

def Cost_eff_found : Nat → Nat → Lanius.Mini.FrontEnv → List Lanius.Mini.Local → Option Lanius.Mini.Ty → Option Lanius.Mini.Found → List Lanius.Mini.MEff → List Lanius.Mini.CTree → Nat
  | 0, x10, x23, x38, x58, x94, x130, x147 => 18446744073709551616
  | n + 1, x10, x23, x38, x58, x94, x130, x147 => (if (decide (x10 = 0)) = true then 0 else (match x94 with | some x309 => (match (x23.decls.fns[x309.decl]?) with | some x395 => (Cost_eff_infer n (x10 - 1) x23 x38 x58 x309.decl x395 x309.binds x130 x147) | none => 0) | none => 0))
termination_by structural fuel => fuel

def Cost_eff_free : Nat → Nat → Lanius.Mini.FrontEnv → List Lanius.Mini.Local → Option Lanius.Mini.Ty → Nat → Lanius.Mini.FnDecl → List Lanius.Mini.CTree → List Lanius.Mini.CTree → Nat
  | 0, x9, x22, x37, x57, x93, x103, x115, x135 => 18446744073709551616
  | n + 1, x9, x22, x37, x57, x93, x103, x115, x135 => (if (decide (x9 = 0)) = true then 0 else (if (Lanius.Mini.noTrees x115) = true then (Cost_eff_infer n (x9 - 1) x22 x37 x57 x93 x103 ([] : List Lanius.Mini.Bind) ([] : List Lanius.Mini.MEff) x135) else ((Cost_explicit_inst n x9 x22 x93 x103 x115) + (match (Lanius.Mini.explicitInst x9 x22 x93 x103 x115) with | some x459 => ((Cost_param_expects n x9 x22.decls x103 (some x459.args)) + ((Cost_param_expects n x9 x22.decls x103 (some x459.args)) + ((Cost_param_expects n x9 x22.decls x103 (some x459.args)) + ((Cost_eff_list n (x9 - 1) x22 x37 (Lanius.Mini.paramExpects x9 x22.decls x103 ((some x459.args))) x135) + ((Cost_views_of n x37 (Lanius.Mini.paramExpects x9 x22.decls x103 ((some x459.args))) (Lanius.Mini.effList ((x9 - 1)) x22 x37 ((Lanius.Mini.paramExpects x9 x22.decls x103 ((some x459.args)))) x135)) + (match (Lanius.Mini.checkedEffs ((Lanius.Mini.hasTys ((Lanius.Mini.paramExpects x9 x22.decls x103 ((some x459.args)))))) ((Lanius.Mini.viewsOf x37 ((Lanius.Mini.paramExpects x9 x22.decls x103 ((some x459.args)))) ((Lanius.Mini.effList ((x9 - 1)) x22 x37 ((Lanius.Mini.paramExpects x9 x22.decls x103 ((some x459.args)))) x135))))) with | some x752 => 1 | none => 0)))))) | none => 0))))
termination_by structural fuel => fuel

def Cost_eff_bound : Nat → Nat → Lanius.Mini.FrontEnv → List Lanius.Mini.Local → Option Lanius.Mini.Ty → Nat → Lanius.Mini.FnDecl → Option (List Lanius.Mini.Bind) → List Lanius.Mini.MEff → List Lanius.Mini.CTree → Nat
  | 0, x10, x23, x38, x58, x94, x104, x116, x157, x174 => 18446744073709551616
  | n + 1, x10, x23, x38, x58, x94, x104, x116, x157, x174 => (if (decide (x10 = 0)) = true then 0 else (match x116 with | some x336 => (Cost_eff_infer n (x10 - 1) x23 x38 x58 x94 x104 x336 x157 x174) | none => 0))
termination_by structural fuel => fuel

def Cost_eff_arms : Nat → Nat → Lanius.Mini.FrontEnv → List Lanius.Mini.Local → Option Lanius.Mini.Ty → Lanius.Mini.TypeDecl → List Lanius.Mini.VariantTy → List Lanius.Mini.CTree → Nat
  | 0, x9, x22, x37, x57, x93, x110, x137 => 18446744073709551616
  | n + 1, x9, x22, x37, x57, x93, x110, x137 => (if (decide (x9 = 0)) = true then 0 else (match x110 with | [] => 0 | x397 :: x400 => (match x137 with | [] => 0 | x466 :: x469 => ((Cost_eff_arm n (x9 - 1) x22 x37 x57 x93 x397 x466) + ((Cost_eff_arms n (x9 - 1) x22 x37 x57 x93 x400 x469) + (Cost_cons_eff_arm n (Lanius.Mini.effArm ((x9 - 1)) x22 x37 x57 x93 x397 x466) (Lanius.Mini.effArms ((x9 - 1)) x22 x37 x57 x93 x400 x469)))))))
termination_by structural fuel => fuel

def Cost_eff_infer : Nat → Nat → Lanius.Mini.FrontEnv → List Lanius.Mini.Local → Option Lanius.Mini.Ty → Nat → Lanius.Mini.FnDecl → List Lanius.Mini.Bind → List Lanius.Mini.MEff → List Lanius.Mini.CTree → Nat
  | 0, x10, x23, x38, x58, x94, x104, x116, x135, x152 => 18446744073709551616
  | n + 1, x10, x23, x38, x58, x94, x104, x116, x135, x152 => (if (decide (x10 = 0)) = true then 0 else ((Cost_concat_of_mini_selfhost_List_usize n x104.implParams x104.params) + (if (Lanius.Mini.noNames ((x104.implParams ++ x104.params))) = true then ((Cost_param_expects n x10 x23.decls x104 (some ([] : List Lanius.Mini.Ty))) + ((Cost_arg_list n (x10 - 1) x23 x38 (Lanius.Mini.skipExpects ((Lanius.Mini.paramExpects x10 x23.decls x104 ((some ([] : List Lanius.Mini.Ty))))) x135) x152) + ((Cost_views_of n x38 (Lanius.Mini.skipExpects ((Lanius.Mini.paramExpects x10 x23.decls x104 ((some ([] : List Lanius.Mini.Ty))))) x135) (Lanius.Mini.argList ((x10 - 1)) x23 x38 ((Lanius.Mini.skipExpects ((Lanius.Mini.paramExpects x10 x23.decls x104 ((some ([] : List Lanius.Mini.Ty))))) x135)) x152)) + (Cost_eff_called n x10 x23 x38 x58 x94 x104 x116 x135 (Lanius.Mini.viewsOf x38 ((Lanius.Mini.skipExpects ((Lanius.Mini.paramExpects x10 x23.decls x104 ((some ([] : List Lanius.Mini.Ty))))) x135)) ((Lanius.Mini.argList ((x10 - 1)) x23 x38 ((Lanius.Mini.skipExpects ((Lanius.Mini.paramExpects x10 x23.decls x104 ((some ([] : List Lanius.Mini.Ty))))) x135)) x152))))))) else ((Cost_param_patterns n x10 x104) + (match (Lanius.Mini.paramPatterns x10 x104) with | some x764 => ((Cost_ret_binds n x10 x23.decls x104 (x104.implParams ++ x104.params) x116 x58) + ((Cost_eff_args_bound n (x10 - 1) x23 x38 x104 (x104.implParams ++ x104.params) x764 x135 x152 (Lanius.Mini.retBinds x10 x23.decls x104 ((x104.implParams ++ x104.params)) x116 x58)) + (Cost_eff_inferred n x10 x23 x38 x94 x104 (x104.implParams ++ x104.params) x764 (Lanius.Mini.effArgsBound ((x10 - 1)) x23 x38 x104 ((x104.implParams ++ x104.params)) x764 x135 x152 ((Lanius.Mini.retBinds x10 x23.decls x104 ((x104.implParams ++ x104.params)) x116 x58)))))) | none => 0)))))
termination_by structural fuel => fuel

def Cost_eff_arm : Nat → Nat → Lanius.Mini.FrontEnv → List Lanius.Mini.Local → Option Lanius.Mini.Ty → Lanius.Mini.TypeDecl → Lanius.Mini.VariantTy → Lanius.Mini.CTree → Nat
  | 0, x8, x21, x36, x56, x92, x109, x123 => 18446744073709551616
  | n + 1, x8, x21, x36, x56, x92, x109, x123 => (if (decide (x8 = 0)) = true then 0 else (let k2 := (if (decide ((Lanius.Mini.nodeProd ((Lanius.Mini.kid ((Lanius.Mini.kid x123 0)) 1))) = Lanius.Mini.Inline.pPatternPlain)) = true then (Cost_eff_arm_bound n (x8 - 1) x21 x56 (some (Lanius.Mini.Bound.mk ([] : List Nat) x36)) (Lanius.Mini.kid x123 2)) else ((Cost_list_items n x8 (Lanius.Mini.kid ((Lanius.Mini.kid ((Lanius.Mini.kid x123 0)) 1)) 1)) + (match (Lanius.Mini.listItems x8 ((Lanius.Mini.kid ((Lanius.Mini.kid ((Lanius.Mini.kid x123 0)) 1)) 1))) with | some x748 => ((Cost_binders_of n x21 x36 x748 x109.payload) + (Cost_eff_arm_bound n (x8 - 1) x21 x56 (Lanius.Mini.bindersOf x21 x36 x748 x109.payload) (Lanius.Mini.kid x123 2))) | none => 0))); let k3 := 0; (if (decide ((Lanius.Mini.nodeProd ((Lanius.Mini.kid x123 0))) = Lanius.Mini.Inline.pPatternIdent)) = true then ((Cost_path_spellings n x8 (Lanius.Mini.kid ((Lanius.Mini.kid ((Lanius.Mini.kid x123 0)) 0)) 0) (Lanius.Mini.kid ((Lanius.Mini.kid ((Lanius.Mini.kid x123 0)) 0)) 1)) + ((Cost_arm_named n (Lanius.Mini.pathSpellings x8 ((Lanius.Mini.kid ((Lanius.Mini.kid ((Lanius.Mini.kid x123 0)) 0)) 0)) ((Lanius.Mini.kid ((Lanius.Mini.kid ((Lanius.Mini.kid x123 0)) 0)) 1))) x92 x109.name) + (if (Lanius.Mini.armNamed ((Lanius.Mini.pathSpellings x8 ((Lanius.Mini.kid ((Lanius.Mini.kid ((Lanius.Mini.kid x123 0)) 0)) 0)) ((Lanius.Mini.kid ((Lanius.Mini.kid ((Lanius.Mini.kid x123 0)) 0)) 1)))) x92 x109.name) = true then k2 else k3))) else k3)))
termination_by structural fuel => fuel

def Cost_arg_list : Nat → Nat → Lanius.Mini.FrontEnv → List Lanius.Mini.Local → Option (List Lanius.Mini.Ty) → List Lanius.Mini.CTree → Nat
  | 0, x9, x22, x37, x57, x98 => 18446744073709551616
  | n + 1, x9, x22, x37, x57, x98 => (if (decide (x9 = 0)) = true then 0 else (match x98 with | [] => 0 | x274 :: x277 => ((Cost_arg_eff n (x9 - 1) x22 x37 (Lanius.Mini.headTy x57) x274) + ((Cost_arg_list n (x9 - 1) x22 x37 (Lanius.Mini.tailTys x57) x277) + (Cost_cons_eff n (Lanius.Mini.argEff ((x9 - 1)) x22 x37 ((Lanius.Mini.headTy x57)) x274) (Lanius.Mini.argList ((x9 - 1)) x22 x37 ((Lanius.Mini.tailTys x57)) x277))))))
termination_by structural fuel => fuel

def Cost_eff_args_bound : Nat → Nat → Lanius.Mini.FrontEnv → List Lanius.Mini.Local → Lanius.Mini.FnDecl → List (List Nat) → List Lanius.Mini.CTree → List Lanius.Mini.MEff → List Lanius.Mini.CTree → Option (List Lanius.Mini.Bind) → Nat
  | 0, x15, x28, x43, x63, x75, x101, x118, x135, x155 => 18446744073709551616
  | n + 1, x15, x28, x43, x63, x75, x101, x118, x135, x155 => (if (decide (x15 = 0)) = true then 0 else (match x155 with | some x378 => (match x101 with | [] => 0 | x674 :: x677 => (match x118 with | [] => (match x135 with | [] => 0 | x965 :: x968 => ((Cost_bound_args n x75 x378) + (if (!(Lanius.Mini.hasTys ((Lanius.Mini.boundArgs x75 x378)))) = true then ((Cost_arg_expected n (x15 - 1) x28.decls x63 x75 x674 x378) + ((Cost_arg_expected n (x15 - 1) x28.decls x63 x75 x674 x378) + ((Cost_eff_of n (x15 - 1) x28 x43 (Lanius.Mini.argExpected ((x15 - 1)) x28.decls x63 x75 x674 x378) x965) + (Cost_eff_arg_next n (x15 - 1) x28 x43 x63 x75 x674 x677 x968 x378 (Lanius.Mini.viewOf x43 ((Lanius.Mini.argExpected ((x15 - 1)) x28.decls x63 x75 x674 x378)) ((Lanius.Mini.effOf ((x15 - 1)) x28 x43 ((Lanius.Mini.argExpected ((x15 - 1)) x28.decls x63 x75 x674 x378)) x965))))))) else ((Cost_arg_expected n (x15 - 1) x28.decls x63 x75 x674 x378) + ((Cost_arg_expected n (x15 - 1) x28.decls x63 x75 x674 x378) + ((Cost_arg_expected n (x15 - 1) x28.decls x63 x75 x674 x378) + ((Cost_eff_of n (x15 - 1) x28 x43 (Lanius.Mini.argExpected ((x15 - 1)) x28.decls x63 x75 x674 x378) x965) + (Cost_eff_arg_next n (x15 - 1) x28 x43 x63 x75 x674 x677 x968 x378 (Lanius.Mini.viewOf x43 ((Lanius.Mini.argExpected ((x15 - 1)) x28.decls x63 x75 x674 x378)) ((Lanius.Mini.effOf ((x15 - 1)) x28 x43 ((Lanius.Mini.argExpected ((x15 - 1)) x28.decls x63 x75 x674 x378)) x965))))))))))) | x721 :: x724 => ((Cost_bind_arg n (x15 - 1) x28 x43 x63 x75 x674 x721 x378) + ((Cost_eff_args_bound n (x15 - 1) x28 x43 x63 x75 x677 x724 x135 (Lanius.Mini.bindArg ((x15 - 1)) x28 x43 x63 x75 x674 x721 x378)) + (Cost_cons_bound n x721 (Lanius.Mini.effArgsBound ((x15 - 1)) x28 x43 x63 x75 x677 x724 x135 ((Lanius.Mini.bindArg ((x15 - 1)) x28 x43 x63 x75 x674 x721 x378)))))))) | none => 0))
termination_by structural fuel => fuel

def Cost_eff_arm_bound : Nat → Nat → Lanius.Mini.FrontEnv → Option Lanius.Mini.Ty → Option Lanius.Mini.Bound → Lanius.Mini.CTree → Nat
  | 0, x14, x27, x42, x78, x114 => 18446744073709551616
  | n + 1, x14, x27, x42, x78, x114 => (if (decide (x14 = 0)) = true then 0 else (match x78 with | some x272 => ((Cost_eff_of n (x14 - 1) x27 x272.scope x42 x114) + ((Cost_diverge_arm n x27.decls x42 (Lanius.Mini.effOf ((x14 - 1)) x27 x272.scope x42 x114)) + (Cost_arm_eff n x14 x27 x272 (Lanius.Mini.divergeArm x27.decls x42 ((Lanius.Mini.effOf ((x14 - 1)) x27 x272.scope x42 x114)))))) | none => 0))
termination_by structural fuel => fuel

def Cost_arg_eff : Nat → Nat → Lanius.Mini.FrontEnv → List Lanius.Mini.Local → Option Lanius.Mini.Ty → Lanius.Mini.CTree → Nat
  | 0, x8, x21, x36, x56, x92 => 18446744073709551616
  | n + 1, x8, x21, x36, x56, x92 => (if (decide (x8 = 0)) = true then 0 else ((Cost_string_init n x8 x92) + (match (Lanius.Mini.stringInit x8 x92) with | some x237 => 0 | none => (Cost_eff_of n (x8 - 1) x21 x36 x56 x92))))
termination_by structural fuel => fuel

def Cost_eff_arg_next : Nat → Nat → Lanius.Mini.FrontEnv → List Lanius.Mini.Local → Lanius.Mini.FnDecl → List (List Nat) → Lanius.Mini.CTree → List Lanius.Mini.CTree → List Lanius.Mini.CTree → List Lanius.Mini.Bind → Option Lanius.Mini.MEff → Nat
  | 0, x13, x26, x41, x61, x73, x99, x109, x126, x146, x161 => 18446744073709551616
  | n + 1, x13, x26, x41, x61, x73, x99, x109, x126, x146, x161 => (if (decide (x13 = 0)) = true then 0 else (match x161 with | some x335 => ((Cost_bind_arg n (x13 - 1) x26 x41 x61 x73 x99 x335 x146) + ((Cost_eff_args_bound n (x13 - 1) x26 x41 x61 x73 x109 ([] : List Lanius.Mini.MEff) x126 (Lanius.Mini.bindArg ((x13 - 1)) x26 x41 x61 x73 x99 x335 x146)) + (Cost_cons_bound n x335 (Lanius.Mini.effArgsBound ((x13 - 1)) x26 x41 x61 x73 x109 (([] : List Lanius.Mini.MEff)) x126 ((Lanius.Mini.bindArg ((x13 - 1)) x26 x41 x61 x73 x99 x335 x146)))))) | none => 0))
termination_by structural fuel => fuel
end

end
noncomputable section

mutual
def Pre_eff_of : Nat → Nat → Lanius.Mini.FrontEnv → List Lanius.Mini.Local → Option Lanius.Mini.Ty → Lanius.Mini.CTree → Nat → Prop
  | 0, x7, x20, x35, x55, x91, b => True
  | n + 1, x7, x20, x35, x55, x91, b => (if (decide (x7 = 0)) = true then True else ((Pre_expr_of n x7 x20 x35 x91 b) ∧ (∀ b1 : Nat, (Cost_expr_of n x7 x20 x35 x91) < b → b1 = b - (Cost_expr_of n x7 x20 x35 x91) → (match (Lanius.Mini.exprOf x7 x20 x35 x91) with | some x244 => True | none => (Pre_eff_node n (x7 - 1) x20 x35 x55 x91 b1)))))
termination_by structural fuel => fuel

def Pre_eff_node : Nat → Nat → Lanius.Mini.FrontEnv → List Lanius.Mini.Local → Option Lanius.Mini.Ty → Lanius.Mini.CTree → Nat → Prop
  | 0, x9, x22, x37, x57, x93, b => True
  | n + 1, x9, x22, x37, x57, x93, b => (if (decide (x9 = 0)) = true then True else (let k20 := fun (b1 : Nat) => (Pre_eff_of n (x9 - 1) x22 x37 x57 (Lanius.Mini.kid x93 0) b1); let k21 := fun (b1 : Nat) => (let k18 := fun (b3 : Nat) => (Pre_eff_of n (x9 - 1) x22 x37 x57 (Lanius.Mini.kid x93 0) b3); let k19 := fun (b3 : Nat) => (if (Lanius.Mini.isLevel ((Lanius.Mini.nodeProd x93))) = true then ((Pre_eff_of n (x9 - 1) x22 x37 (none : Option Lanius.Mini.Ty) (Lanius.Mini.kid x93 0) b3) ∧ (∀ b5 : Nat, (Cost_eff_of n (x9 - 1) x22 x37 (none : Option Lanius.Mini.Ty) (Lanius.Mini.kid x93 0)) < b3 → b5 = b3 - (Cost_eff_of n (x9 - 1) x22 x37 (none : Option Lanius.Mini.Ty) (Lanius.Mini.kid x93 0)) → (Pre_eff_fold n (x9 - 1) x22 x37 (Lanius.Mini.effOf ((x9 - 1)) x22 x37 ((none : Option Lanius.Mini.Ty)) ((Lanius.Mini.kid x93 0))) (Lanius.Mini.kid x93 1) b5))) else (if (decide ((Lanius.Mini.nodeProd x93) = Lanius.Mini.Inline.pCast)) = true then ((Pre_eff_of n (x9 - 1) x22 x37 (none : Option Lanius.Mini.Ty) (Lanius.Mini.kid x93 0) b3) ∧ (∀ b7 : Nat, (Cost_eff_of n (x9 - 1) x22 x37 (none : Option Lanius.Mini.Ty) (Lanius.Mini.kid x93 0)) < b3 → b7 = b3 - (Cost_eff_of n (x9 - 1) x22 x37 (none : Option Lanius.Mini.Ty) (Lanius.Mini.kid x93 0)) → (Pre_eff_casts n (x9 - 1) x22 (Lanius.Mini.effOf ((x9 - 1)) x22 x37 ((none : Option Lanius.Mini.Ty)) ((Lanius.Mini.kid x93 0))) (Lanius.Mini.kid x93 1) b7))) else (if (decide ((Lanius.Mini.nodeProd x93) = Lanius.Mini.Inline.pNeg)) = true then (Pre_eff_of n (x9 - 1) x22 x37 x57 (Lanius.Mini.kid x93 1) b3) else (if (decide ((Lanius.Mini.nodeProd x93) = Lanius.Mini.Inline.pNot)) = true then (Pre_eff_of n (x9 - 1) x22 x37 (some Lanius.Mini.Ty.tyBool) (Lanius.Mini.kid x93 1) b3) else (if (decide ((Lanius.Mini.nodeProd x93) = Lanius.Mini.Inline.pPostfix)) = true then (Pre_eff_postfix n (x9 - 1) x22 x37 x57 x93 b3) else (if (decide ((Lanius.Mini.nodeProd x93) = Lanius.Mini.Inline.pGroup)) = true then (Pre_eff_of n (x9 - 1) x22 x37 x57 (Lanius.Mini.kid x93 1) b3) else (if (decide ((Lanius.Mini.nodeProd x93) = Lanius.Mini.Inline.pIdent)) = true then (Pre_eff_ident n (x9 - 1) x22 x37 x57 x93 b3) else (if (decide ((Lanius.Mini.nodeProd x93) = Lanius.Mini.Inline.pMatchExpr)) = true then (Pre_eff_match n (x9 - 1) x22 x37 x57 x93 b3) else (if (decide ((Lanius.Mini.nodeProd x93) = Lanius.Mini.Inline.pArrayLit)) = true then (Pre_eff_array n (x9 - 1) x22 x37 x57 (Lanius.Mini.kid x93 1) b3) else True))))))))); (if (decide ((Lanius.Mini.nodeProd x93) = Lanius.Mini.Inline.pAssign)) = true then (if (!(Lanius.Mini.hasKids ((Lanius.Mini.kid x93 1)))) = true then (k18 b1) else (k19 b1)) else (if (Lanius.Mini.isLevel ((Lanius.Mini.nodeProd x93))) = true then (if (!(Lanius.Mini.hasKids ((Lanius.Mini.kid x93 1)))) = true then (k18 b1) else (k19 b1)) else (if (decide ((Lanius.Mini.nodeProd x93) = Lanius.Mini.Inline.pCast)) = true then (if (!(Lanius.Mini.hasKids ((Lanius.Mini.kid x93 1)))) = true then (k18 b1) else (k19 b1)) else (k19 b1))))); (if (decide ((Lanius.Mini.nodeProd x93) = Lanius.Mini.Inline.pExpr)) = true then (k20 b) else (if (decide ((Lanius.Mini.nodeProd x93) = Lanius.Mini.Inline.pBase)) = true then (k20 b) else (k21 b)))))
termination_by structural fuel => fuel

def Pre_eff_fold : Nat → Nat → Lanius.Mini.FrontEnv → List Lanius.Mini.Local → Option Lanius.Mini.MEff → Lanius.Mini.CTree → Nat → Prop
  | 0, x9, x22, x37, x57, x90, b => True
  | n + 1, x9, x22, x37, x57, x90, b => (if (decide (x9 = 0)) = true then True else (if (Lanius.Mini.hasKids x90) = true then ((Pre_eff_of n (x9 - 1) x22 x37 (none : Option Lanius.Mini.Ty) (Lanius.Mini.kid x90 1) b) ∧ (∀ b1 : Nat, (Cost_eff_of n (x9 - 1) x22 x37 (none : Option Lanius.Mini.Ty) (Lanius.Mini.kid x90 1)) < b → b1 = b - (Cost_eff_of n (x9 - 1) x22 x37 (none : Option Lanius.Mini.Ty) (Lanius.Mini.kid x90 1)) → (∀ b2 : Nat, (Cost_eff_binary n (Lanius.Mini.nodeProd x90) x57 (Lanius.Mini.effOf ((x9 - 1)) x22 x37 ((none : Option Lanius.Mini.Ty)) ((Lanius.Mini.kid x90 1)))) < b1 → b2 = b1 - (Cost_eff_binary n (Lanius.Mini.nodeProd x90) x57 (Lanius.Mini.effOf ((x9 - 1)) x22 x37 ((none : Option Lanius.Mini.Ty)) ((Lanius.Mini.kid x90 1)))) → (Pre_eff_fold n (x9 - 1) x22 x37 (Lanius.Mini.effBinary ((Lanius.Mini.nodeProd x90)) x57 ((Lanius.Mini.effOf ((x9 - 1)) x22 x37 ((none : Option Lanius.Mini.Ty)) ((Lanius.Mini.kid x90 1))))) (Lanius.Mini.kid x90 2) b2)))) else True))
termination_by structural fuel => fuel

def Pre_eff_postfix : Nat → Nat → Lanius.Mini.FrontEnv → List Lanius.Mini.Local → Option Lanius.Mini.Ty → Lanius.Mini.CTree → Nat → Prop
  | 0, x12, x25, x40, x60, x96, b => True
  | n + 1, x12, x25, x40, x60, x96, b => (if (decide (x12 = 0)) = true then True else (if (decide ((Lanius.Mini.nodeProd ((Lanius.Mini.kid x96 1))) = Lanius.Mini.Inline.pPostfixEnd)) = true then (Pre_eff_node n (x12 - 1) x25 x40 x60 (Lanius.Mini.kid x96 0) b) else (if (Lanius.Mini.isPathCall x96) = true then (Pre_eff_path_call n (x12 - 1) x25 x40 x60 (Lanius.Mini.kid ((Lanius.Mini.kid x96 0)) 0) (Lanius.Mini.kid ((Lanius.Mini.kid x96 1)) 1) b) else (if (Lanius.Mini.isMethodForm x96) = true then (Pre_eff_method n (x12 - 1) x25 x40 x60 x96 b) else (let k15 := fun (b4 : Nat) => (∀ b5 : Nat, (Cost_local_of n x25 x40 (Lanius.Mini.kid x96 0)) < b4 → b5 = b4 - (Cost_local_of n x25 x40 (Lanius.Mini.kid x96 0)) → (Pre_eff_of n (x12 - 1) x25 x40 (none : Option Lanius.Mini.Ty) (Lanius.Mini.kid ((Lanius.Mini.kid x96 1)) 1) b5)); let k16 := fun (b4 : Nat) => (let k13 := fun (b8 : Nat) => ((Pre_eff_path_call n (x12 - 1) x25 x40 (none : Option Lanius.Mini.Ty) (Lanius.Mini.kid ((Lanius.Mini.kid x96 0)) 0) (Lanius.Mini.kid ((Lanius.Mini.kid x96 1)) 1) b8) ∧ (∀ b9 : Nat, (Cost_eff_path_call n (x12 - 1) x25 x40 (none : Option Lanius.Mini.Ty) (Lanius.Mini.kid ((Lanius.Mini.kid x96 0)) 0) (Lanius.Mini.kid ((Lanius.Mini.kid x96 1)) 1)) < b8 → b9 = b8 - (Cost_eff_path_call n (x12 - 1) x25 x40 (none : Option Lanius.Mini.Ty) (Lanius.Mini.kid ((Lanius.Mini.kid x96 0)) 0) (Lanius.Mini.kid ((Lanius.Mini.kid x96 1)) 1)) → (Pre_eff_chain n (x12 - 1) x25 x40 x60 (Lanius.Mini.effPathCall ((x12 - 1)) x25 x40 ((none : Option Lanius.Mini.Ty)) ((Lanius.Mini.kid ((Lanius.Mini.kid x96 0)) 0)) ((Lanius.Mini.kid ((Lanius.Mini.kid x96 1)) 1))) (Lanius.Mini.kid ((Lanius.Mini.kid x96 1)) 3) b9))); let k14 := fun (b8 : Nat) => ((Pre_eff_primary n (x12 - 1) x25 x40 (Lanius.Mini.kid x96 0) b8) ∧ (∀ b11 : Nat, (Cost_eff_primary n (x12 - 1) x25 x40 (Lanius.Mini.kid x96 0)) < b8 → b11 = b8 - (Cost_eff_primary n (x12 - 1) x25 x40 (Lanius.Mini.kid x96 0)) → (Pre_eff_chain n (x12 - 1) x25 x40 x60 (Lanius.Mini.effPrimary ((x12 - 1)) x25 x40 ((Lanius.Mini.kid x96 0))) (Lanius.Mini.kid x96 1) b11))); (if (decide ((Lanius.Mini.nodeProd ((Lanius.Mini.kid x96 0))) = Lanius.Mini.Inline.pIdent)) = true then (if (decide ((Lanius.Mini.nodeProd ((Lanius.Mini.kid ((Lanius.Mini.kid x96 0)) 1))) = Lanius.Mini.Inline.pIdentPlain)) = true then (if (decide ((Lanius.Mini.nodeProd ((Lanius.Mini.kid x96 1))) = Lanius.Mini.Inline.pPostfixCall)) = true then (k13 b4) else (k14 b4)) else (k14 b4)) else (k14 b4))); (if (decide ((Lanius.Mini.nodeProd ((Lanius.Mini.kid x96 0))) = Lanius.Mini.Inline.pIdent)) = true then (if (decide ((Lanius.Mini.nodeProd ((Lanius.Mini.kid ((Lanius.Mini.kid x96 0)) 1))) = Lanius.Mini.Inline.pIdentPlain)) = true then (if (decide ((Lanius.Mini.nodeProd ((Lanius.Mini.kid x96 1))) = Lanius.Mini.Inline.pPostfixIndex)) = true then (if (decide ((Lanius.Mini.nodeProd ((Lanius.Mini.kid ((Lanius.Mini.kid x96 1)) 3))) = Lanius.Mini.Inline.pPostfixEnd)) = true then (k15 b) else (k16 b)) else (k16 b)) else (k16 b)) else (k16 b)))))))
termination_by structural fuel => fuel

def Pre_eff_ident : Nat → Nat → Lanius.Mini.FrontEnv → List Lanius.Mini.Local → Option Lanius.Mini.Ty → Lanius.Mini.CTree → Nat → Prop
  | 0, x10, x23, x38, x58, x94, b => True
  | n + 1, x10, x23, x38, x58, x94, b => (if (decide (x10 = 0)) = true then True else (if (decide ((Lanius.Mini.nodeProd ((Lanius.Mini.kid x94 1))) = Lanius.Mini.Inline.pIdentPlain)) = true then (∀ b1 : Nat, (Cost_path_spellings n x10 (Lanius.Mini.kid ((Lanius.Mini.kid x94 0)) 0) (Lanius.Mini.kid ((Lanius.Mini.kid x94 0)) 1)) < b → b1 = b - (Cost_path_spellings n x10 (Lanius.Mini.kid ((Lanius.Mini.kid x94 0)) 0) (Lanius.Mini.kid ((Lanius.Mini.kid x94 0)) 1)) → (match (Lanius.Mini.pathSpellings x10 ((Lanius.Mini.kid ((Lanius.Mini.kid x94 0)) 0)) ((Lanius.Mini.kid ((Lanius.Mini.kid x94 0)) 1))) with | some x385 => (∀ b2 : Nat, (Cost_split_last n x385) < b1 → b2 = b1 - (Cost_split_last n x385) → (match (Lanius.Mini.splitLast x385) with | some x468 => (∀ b3 : Nat, (Cost_local_of n x23 x38 x94) < b2 → b3 = b2 - (Cost_local_of n x23 x38 x94) → (if (!(Lanius.Mini.hasLocal ((Lanius.Mini.localOf x23 x38 x94)))) = true then (∀ b6 : Nat, (Cost_path_module n x23 x468.home x468.name) < b3 → b6 = b3 - (Cost_path_module n x23 x468.home x468.name) → ((Pre_variant_by_path n x23 x468 b6) ∧ (∀ b7 : Nat, (Cost_variant_by_path n x23 x468) < b6 → b7 = b6 - (Cost_variant_by_path n x23 x468) → (Pre_eff_variant n (x10 - 1) x23 x38 x58 (Lanius.Mini.variantByPath x23 x468) ([] : List Lanius.Mini.CTree) b7)))) else ((Pre_variant_by_path n x23 x468 b3) ∧ (∀ b4 : Nat, (Cost_variant_by_path n x23 x468) < b3 → b4 = b3 - (Cost_variant_by_path n x23 x468) → (Pre_eff_variant n (x10 - 1) x23 x38 x58 (Lanius.Mini.variantByPath x23 x468) ([] : List Lanius.Mini.CTree) b4))))) | none => True)) | none => True)) else (if (decide ((Lanius.Mini.nodeProd ((Lanius.Mini.kid x94 1))) = Lanius.Mini.Inline.pStructLit)) = true then (∀ b9 : Nat, (Cost_path_spellings n x10 (Lanius.Mini.kid ((Lanius.Mini.kid x94 0)) 0) (Lanius.Mini.kid ((Lanius.Mini.kid x94 0)) 1)) < b → b9 = b - (Cost_path_spellings n x10 (Lanius.Mini.kid ((Lanius.Mini.kid x94 0)) 0) (Lanius.Mini.kid ((Lanius.Mini.kid x94 0)) 1)) → (match (Lanius.Mini.pathSpellings x10 ((Lanius.Mini.kid ((Lanius.Mini.kid x94 0)) 0)) ((Lanius.Mini.kid ((Lanius.Mini.kid x94 0)) 1))) with | some x894 => (∀ b10 : Nat, (Cost_list_items n x10 (Lanius.Mini.kid ((Lanius.Mini.kid x94 1)) 1)) < b9 → b10 = b9 - (Cost_list_items n x10 (Lanius.Mini.kid ((Lanius.Mini.kid x94 1)) 1)) → (match (Lanius.Mini.listItems x10 ((Lanius.Mini.kid ((Lanius.Mini.kid x94 1)) 1))) with | some x998 => ((Pre_type_decl_at n x23 x894 b10) ∧ (∀ b11 : Nat, (Cost_type_decl_at n x23 x894) < b10 → b11 = b10 - (Cost_type_decl_at n x23 x894) → (match (Lanius.Mini.typeDeclAt x23 x894) with | some x1096 => (match (x23.decls.types[x1096]?) with | some x1203 => (Pre_eff_literal n (x10 - 1) x23 x38 x58 x1096 x1203 x998 b11) | none => True) | none => True))) | none => True)) | none => True)) else True)))
termination_by structural fuel => fuel

def Pre_eff_match : Nat → Nat → Lanius.Mini.FrontEnv → List Lanius.Mini.Local → Option Lanius.Mini.Ty → Lanius.Mini.CTree → Nat → Prop
  | 0, x10, x23, x38, x58, x94, b => True
  | n + 1, x10, x23, x38, x58, x94, b => (if (decide (x10 = 0)) = true then True else ((Pre_eff_of n (x10 - 1) x23 x38 (none : Option Lanius.Mini.Ty) (Lanius.Mini.kid x94 2) b) ∧ (∀ b1 : Nat, (Cost_eff_of n (x10 - 1) x23 x38 (none : Option Lanius.Mini.Ty) (Lanius.Mini.kid x94 2)) < b → b1 = b - (Cost_eff_of n (x10 - 1) x23 x38 (none : Option Lanius.Mini.Ty) (Lanius.Mini.kid x94 2)) → (Pre_eff_match_on n (x10 - 1) x23 x38 x58 (Lanius.Mini.effOf ((x10 - 1)) x23 x38 ((none : Option Lanius.Mini.Ty)) ((Lanius.Mini.kid x94 2))) x94 b1))))
termination_by structural fuel => fuel

def Pre_eff_array : Nat → Nat → Lanius.Mini.FrontEnv → List Lanius.Mini.Local → Option Lanius.Mini.Ty → Lanius.Mini.CTree → Nat → Prop
  | 0, x10, x23, x38, x58, x94, b => True
  | n + 1, x10, x23, x38, x58, x94, b => (if (decide (x10 = 0)) = true then True else (let k8 := fun (b1 : Nat) => (match (Lanius.Mini.expectedArray x58) with | some x410 => ((Pre_decimal n (((Lanius.Mini.kidToken ((Lanius.Mini.kid ((Lanius.Mini.kid x94 1)) 1)) 0)).text) 0 b1) ∧ (Pre_eff_of n (x10 - 1) x23 x38 (some x410.element) (Lanius.Mini.kid x94 0) b1)) | none => True); let k9 := fun (b1 : Nat) => (match (Lanius.Mini.expectedArray x58) with | some x643 => (∀ b4 : Nat, (Cost_list_items n (x10 - 1) x94) < b1 → b4 = b1 - (Cost_list_items n (x10 - 1) x94) → (match (Lanius.Mini.listItems ((x10 - 1)) x94) with | some x723 => (∀ b5 : Nat, (Cost_repeat_ty n x643.element x643.count) < b4 → b5 = b4 - (Cost_repeat_ty n x643.element x643.count) → ((Pre_eff_list n (x10 - 1) x23 x38 (some (Lanius.Mini.repeatTy x643.element x643.count)) x723 b5) ∧ (∀ b6 : Nat, (Cost_eff_list n (x10 - 1) x23 x38 (some (Lanius.Mini.repeatTy x643.element x643.count)) x723) < b5 → b6 = b5 - (Cost_eff_list n (x10 - 1) x23 x38 (some (Lanius.Mini.repeatTy x643.element x643.count)) x723) → (Pre_array_of n x643 (Lanius.Mini.effList ((x10 - 1)) x23 x38 ((some (Lanius.Mini.repeatTy x643.element x643.count))) x723) b6)))) | none => True)) | none => True); (if (decide ((Lanius.Mini.nodeProd x94) = Lanius.Mini.Inline.pArraySome)) = true then (if (decide ((Lanius.Mini.nodeProd ((Lanius.Mini.kid x94 1))) = Lanius.Mini.Inline.pArrayRepeat)) = true then (k8 b) else (k9 b)) else (k9 b))))
termination_by structural fuel => fuel

def Pre_eff_path_call : Nat → Nat → Lanius.Mini.FrontEnv → List Lanius.Mini.Local → Option Lanius.Mini.Ty → Lanius.Mini.CTree → Lanius.Mini.CTree → Nat → Prop
  | 0, x14, x27, x42, x62, x98, x111, b => True
  | n + 1, x14, x27, x42, x62, x98, x111, b => (if (decide (x14 = 0)) = true then True else (∀ b1 : Nat, (Cost_path_spellings n x14 (Lanius.Mini.kid x98 0) (Lanius.Mini.kid x98 1)) < b → b1 = b - (Cost_path_spellings n x14 (Lanius.Mini.kid x98 0) (Lanius.Mini.kid x98 1)) → (let k15 := fun (b2 : Nat) => True; let k16 := fun (b2 : Nat) => (∀ b3 : Nat, (Cost_text_slice_stride n ) < b2 → b3 = b2 - (Cost_text_slice_stride n ) → (∀ b4 : Nat, (Cost_single_of_mini_selfhost_List_usize n Lanius.Mini.textSliceStride) < b3 → b4 = b3 - (Cost_single_of_mini_selfhost_List_usize n Lanius.Mini.textSliceStride) → (if (Lanius.Mini.isPath ((Lanius.Mini.pathSpellings x14 ((Lanius.Mini.kid x98 0)) ((Lanius.Mini.kid x98 1)))) ([Lanius.Mini.textSliceStride])) = true then True else (∀ b7 : Nat, (Cost_text_slice_len n ) < b4 → b7 = b4 - (Cost_text_slice_len n ) → (∀ b8 : Nat, (Cost_single_of_mini_selfhost_List_usize n Lanius.Mini.textSliceLen) < b7 → b8 = b7 - (Cost_single_of_mini_selfhost_List_usize n Lanius.Mini.textSliceLen) → (if (Lanius.Mini.isPath ((Lanius.Mini.pathSpellings x14 ((Lanius.Mini.kid x98 0)) ((Lanius.Mini.kid x98 1)))) ([Lanius.Mini.textSliceLen])) = true then True else (∀ b11 : Nat, (Cost_path_ref n x14 (Lanius.Mini.kid x98 0) (Lanius.Mini.kid x98 1)) < b8 → b11 = b8 - (Cost_path_ref n x14 (Lanius.Mini.kid x98 0) (Lanius.Mini.kid x98 1)) → (match (Lanius.Mini.pathRef x14 ((Lanius.Mini.kid x98 0)) ((Lanius.Mini.kid x98 1))) with | some x998 => (∀ b12 : Nat, (Cost_named_split n x998.segments) < b11 → b12 = b11 - (Cost_named_split n x998.segments) → (match (Lanius.Mini.namedSplit x998.segments) with | some x1083 => (∀ b13 : Nat, (Cost_list_items n x14 x111) < b12 → b13 = b12 - (Cost_list_items n x14 x111) → (match (Lanius.Mini.listItems x14 x111) with | some x1173 => (Pre_eff_named n (x14 - 1) x27 x42 x62 x1083 x998.targs x1173 b13) | none => True)) | none => True)) | none => True)))))))); (∀ b17 : Nat, (Cost_alloc_path n ) < b1 → b17 = b1 - (Cost_alloc_path n ) → (if (Lanius.Mini.isPath ((Lanius.Mini.pathSpellings x14 ((Lanius.Mini.kid x98 0)) ((Lanius.Mini.kid x98 1)))) Lanius.Mini.allocPath) = true then (k15 b17) else (∀ b20 : Nat, (Cost_dealloc_path n ) < b17 → b20 = b17 - (Cost_dealloc_path n ) → (if (Lanius.Mini.isPath ((Lanius.Mini.pathSpellings x14 ((Lanius.Mini.kid x98 0)) ((Lanius.Mini.kid x98 1)))) Lanius.Mini.deallocPath) = true then (k15 b20) else (∀ b21 : Nat, (Cost_text_slice_from_raw_parts n ) < b20 → b21 = b20 - (Cost_text_slice_from_raw_parts n ) → (∀ b22 : Nat, (Cost_single_of_mini_selfhost_List_usize n Lanius.Mini.textSliceFromRawParts) < b21 → b22 = b21 - (Cost_single_of_mini_selfhost_List_usize n Lanius.Mini.textSliceFromRawParts) → (if (Lanius.Mini.isPath ((Lanius.Mini.pathSpellings x14 ((Lanius.Mini.kid x98 0)) ((Lanius.Mini.kid x98 1)))) ([Lanius.Mini.textSliceFromRawParts])) = true then (k15 b22) else (k16 b22)))))))))))
termination_by structural fuel => fuel

def Pre_eff_method : Nat → Nat → Lanius.Mini.FrontEnv → List Lanius.Mini.Local → Option Lanius.Mini.Ty → Lanius.Mini.CTree → Nat → Prop
  | 0, x11, x24, x39, x59, x95, b => True
  | n + 1, x11, x24, x39, x59, x95, b => (if (decide (x11 = 0)) = true then True else (∀ b1 : Nat, (Cost_local_of n x24 x39 (Lanius.Mini.kid x95 0)) < b → b1 = b - (Cost_local_of n x24 x39 (Lanius.Mini.kid x95 0)) → (match (Lanius.Mini.localOf x24 x39 ((Lanius.Mini.kid x95 0))) with | some x309 => (∀ b2 : Nat, (Cost_list_items n x11 (Lanius.Mini.kid ((Lanius.Mini.kid ((Lanius.Mini.kid x95 1)) 3)) 1)) < b1 → b2 = b1 - (Cost_list_items n x11 (Lanius.Mini.kid ((Lanius.Mini.kid ((Lanius.Mini.kid x95 1)) 3)) 1)) → (match (Lanius.Mini.listItems x11 ((Lanius.Mini.kid ((Lanius.Mini.kid ((Lanius.Mini.kid x95 1)) 3)) 1))) with | some x407 => ((Pre_find_method n x11 x24.decls x24.decls.fns 0 (((Lanius.Mini.kidToken ((Lanius.Mini.kid x95 1)) 1)).text) (Lanius.Mini.referentOr x309.ty) b2) ∧ (∀ b3 : Nat, (Cost_find_method n x11 x24.decls x24.decls.fns 0 (((Lanius.Mini.kidToken ((Lanius.Mini.kid x95 1)) 1)).text) (Lanius.Mini.referentOr x309.ty)) < b2 → b3 = b2 - (Cost_find_method n x11 x24.decls x24.decls.fns 0 (((Lanius.Mini.kidToken ((Lanius.Mini.kid x95 1)) 1)).text) (Lanius.Mini.referentOr x309.ty)) → (∀ b4 : Nat, (Cost_single_of_mini_selfhost_MEff n (Lanius.Mini.MEff.xPure (Lanius.Mini.SrcExpr.local x309.id))) < b3 → b4 = b3 - (Cost_single_of_mini_selfhost_MEff n (Lanius.Mini.MEff.xPure (Lanius.Mini.SrcExpr.local x309.id))) → (Pre_eff_found_with n (x11 - 1) x24 x39 x59 (Lanius.Mini.findMethod x11 x24.decls x24.decls.fns 0 ((((Lanius.Mini.kidToken ((Lanius.Mini.kid x95 1)) 1)).text)) ((Lanius.Mini.referentOr x309.ty))) (Lanius.Mini.kid ((Lanius.Mini.kid x95 1)) 2) ([(Lanius.Mini.MEff.xPure (Lanius.Mini.SrcExpr.local x309.id))]) x407 b4)))) | none => True)) | none => True)))
termination_by structural fuel => fuel

def Pre_eff_chain : Nat → Nat → Lanius.Mini.FrontEnv → List Lanius.Mini.Local → Option Lanius.Mini.Ty → Option Lanius.Mini.MEff → Lanius.Mini.CTree → Nat → Prop
  | 0, x10, x23, x38, x58, x94, x125, b => True
  | n + 1, x10, x23, x38, x58, x94, x125, b => (if (decide (x10 = 0)) = true then True else (if (decide ((Lanius.Mini.nodeProd x125) = Lanius.Mini.Inline.pPostfixEnd)) = true then True else (match x94 with | some x346 => (Pre_eff_step n (x10 - 1) x23 x38 x58 x346 x125 b) | none => True)))
termination_by structural fuel => fuel

def Pre_eff_primary : Nat → Nat → Lanius.Mini.FrontEnv → List Lanius.Mini.Local → Lanius.Mini.CTree → Nat → Prop
  | 0, x12, x25, x40, x60, b => True
  | n + 1, x12, x25, x40, x60, b => (∀ b1 : Nat, (Cost_local_of n x25 x40 x60) < b → b1 = b - (Cost_local_of n x25 x40 x60) → (match (Lanius.Mini.localOf x25 x40 x60) with | some x172 => True | none => (Pre_eff_node n x12 x25 x40 (none : Option Lanius.Mini.Ty) x60 b1)))
termination_by structural fuel => fuel

def Pre_eff_variant : Nat → Nat → Lanius.Mini.FrontEnv → List Lanius.Mini.Local → Option Lanius.Mini.Ty → Option Lanius.Mini.VariantAt → List Lanius.Mini.CTree → Nat → Prop
  | 0, x12, x25, x40, x60, x96, x132, b => True
  | n + 1, x12, x25, x40, x60, x96, x132, b => (if (decide (x12 = 0)) = true then True else (match x96 with | some x290 => (match (x25.decls.types[x290.owner]?) with | some x379 => (if (!(Lanius.Mini.hasTys ((Lanius.Mini.knownArgs x379 x290.owner x60)))) = true then ((Pre_variant_expects n x12 x25.decls x290.owner x290.index (Lanius.Mini.knownArgs x379 x290.owner x60) b) ∧ (∀ b1 : Nat, (Cost_variant_expects n x12 x25.decls x290.owner x290.index (Lanius.Mini.knownArgs x379 x290.owner x60)) < b → b1 = b - (Cost_variant_expects n x12 x25.decls x290.owner x290.index (Lanius.Mini.knownArgs x379 x290.owner x60)) → ((Pre_eff_list n (x12 - 1) x25 x40 (Lanius.Mini.variantExpects x12 x25.decls x290.owner x290.index ((Lanius.Mini.knownArgs x379 x290.owner x60))) x132 b1) ∧ (∀ b2 : Nat, (Cost_eff_list n (x12 - 1) x25 x40 (Lanius.Mini.variantExpects x12 x25.decls x290.owner x290.index ((Lanius.Mini.knownArgs x379 x290.owner x60))) x132) < b1 → b2 = b1 - (Cost_eff_list n (x12 - 1) x25 x40 (Lanius.Mini.variantExpects x12 x25.decls x290.owner x290.index ((Lanius.Mini.knownArgs x379 x290.owner x60))) x132) → (Pre_x_variant_of n x12 x25 x40 x290.owner x379 x290.index (Lanius.Mini.knownArgs x379 x290.owner x60) (Lanius.Mini.effList ((x12 - 1)) x25 x40 ((Lanius.Mini.variantExpects x12 x25.decls x290.owner x290.index ((Lanius.Mini.knownArgs x379 x290.owner x60)))) x132) b2))))) else ((Pre_variant_expects n x12 x25.decls x290.owner x290.index (Lanius.Mini.knownArgs x379 x290.owner x60) b) ∧ (∀ b4 : Nat, (Cost_variant_expects n x12 x25.decls x290.owner x290.index (Lanius.Mini.knownArgs x379 x290.owner x60)) < b → b4 = b - (Cost_variant_expects n x12 x25.decls x290.owner x290.index (Lanius.Mini.knownArgs x379 x290.owner x60)) → ((Pre_variant_expects n x12 x25.decls x290.owner x290.index (Lanius.Mini.knownArgs x379 x290.owner x60) b4) ∧ (∀ b5 : Nat, (Cost_variant_expects n x12 x25.decls x290.owner x290.index (Lanius.Mini.knownArgs x379 x290.owner x60)) < b4 → b5 = b4 - (Cost_variant_expects n x12 x25.decls x290.owner x290.index (Lanius.Mini.knownArgs x379 x290.owner x60)) → ((Pre_eff_list n (x12 - 1) x25 x40 (Lanius.Mini.variantExpects x12 x25.decls x290.owner x290.index ((Lanius.Mini.knownArgs x379 x290.owner x60))) x132 b5) ∧ (∀ b6 : Nat, (Cost_eff_list n (x12 - 1) x25 x40 (Lanius.Mini.variantExpects x12 x25.decls x290.owner x290.index ((Lanius.Mini.knownArgs x379 x290.owner x60))) x132) < b5 → b6 = b5 - (Cost_eff_list n (x12 - 1) x25 x40 (Lanius.Mini.variantExpects x12 x25.decls x290.owner x290.index ((Lanius.Mini.knownArgs x379 x290.owner x60))) x132) → (Pre_x_variant_of n x12 x25 x40 x290.owner x379 x290.index (Lanius.Mini.knownArgs x379 x290.owner x60) (Lanius.Mini.effList ((x12 - 1)) x25 x40 ((Lanius.Mini.variantExpects x12 x25.decls x290.owner x290.index ((Lanius.Mini.knownArgs x379 x290.owner x60)))) x132) b6)))))))) | none => True) | none => True))
termination_by structural fuel => fuel

def Pre_eff_literal : Nat → Nat → Lanius.Mini.FrontEnv → List Lanius.Mini.Local → Option Lanius.Mini.Ty → Nat → Lanius.Mini.TypeDecl → List Lanius.Mini.CTree → Nat → Prop
  | 0, x12, x25, x40, x60, x96, x106, x119, b => True
  | n + 1, x12, x25, x40, x60, x96, x106, x119, b => (if (decide (x12 = 0)) = true then True else (let k9 := fun (b1 : Nat) => ((Pre_field_expects n x12 x25.decls x96 (Lanius.Mini.knownArgs x106 x96 x60) b1) ∧ (∀ b2 : Nat, (Cost_field_expects n x12 x25.decls x96 (Lanius.Mini.knownArgs x106 x96 x60)) < b1 → b2 = b1 - (Cost_field_expects n x12 x25.decls x96 (Lanius.Mini.knownArgs x106 x96 x60)) → (if (!(Lanius.Mini.hasTys ((Lanius.Mini.knownArgs x106 x96 x60)))) = true then (∀ b3 : Nat, (Cost_field_values n x119) < b2 → b3 = b2 - (Cost_field_values n x119) → ((Pre_eff_list n (x12 - 1) x25 x40 (Lanius.Mini.fieldExpects x12 x25.decls x96 ((Lanius.Mini.knownArgs x106 x96 x60))) (Lanius.Mini.fieldValues x119) b3) ∧ (∀ b4 : Nat, (Cost_eff_list n (x12 - 1) x25 x40 (Lanius.Mini.fieldExpects x12 x25.decls x96 ((Lanius.Mini.knownArgs x106 x96 x60))) (Lanius.Mini.fieldValues x119)) < b3 → b4 = b3 - (Cost_eff_list n (x12 - 1) x25 x40 (Lanius.Mini.fieldExpects x12 x25.decls x96 ((Lanius.Mini.knownArgs x106 x96 x60))) (Lanius.Mini.fieldValues x119)) → (Pre_x_struct_of n x12 x25 x40 x96 x106 (Lanius.Mini.knownArgs x106 x96 x60) (Lanius.Mini.effList ((x12 - 1)) x25 x40 ((Lanius.Mini.fieldExpects x12 x25.decls x96 ((Lanius.Mini.knownArgs x106 x96 x60)))) ((Lanius.Mini.fieldValues x119))) b4)))) else (∀ b6 : Nat, (Cost_field_values n x119) < b2 → b6 = b2 - (Cost_field_values n x119) → ((Pre_eff_list n (x12 - 1) x25 x40 (Lanius.Mini.fieldExpects x12 x25.decls x96 ((Lanius.Mini.knownArgs x106 x96 x60))) (Lanius.Mini.fieldValues x119) b6) ∧ (∀ b7 : Nat, (Cost_eff_list n (x12 - 1) x25 x40 (Lanius.Mini.fieldExpects x12 x25.decls x96 ((Lanius.Mini.knownArgs x106 x96 x60))) (Lanius.Mini.fieldValues x119)) < b6 → b7 = b6 - (Cost_eff_list n (x12 - 1) x25 x40 (Lanius.Mini.fieldExpects x12 x25.decls x96 ((Lanius.Mini.knownArgs x106 x96 x60))) (Lanius.Mini.fieldValues x119)) → (Pre_x_struct_of n x12 x25 x40 x96 x106 (Lanius.Mini.knownArgs x106 x96 x60) (Lanius.Mini.effList ((x12 - 1)) x25 x40 ((Lanius.Mini.fieldExpects x12 x25.decls x96 ((Lanius.Mini.knownArgs x106 x96 x60)))) ((Lanius.Mini.fieldValues x119))) b7))))))); let k10 := fun (b1 : Nat) => True; (if (!x106.isEnum) = true then (if (Lanius.Mini.sameNames x106.fields x119) = true then (k9 b) else (k10 b)) else (k10 b))))
termination_by structural fuel => fuel

def Pre_eff_match_on : Nat → Nat → Lanius.Mini.FrontEnv → List Lanius.Mini.Local → Option Lanius.Mini.Ty → Option Lanius.Mini.MEff → Lanius.Mini.CTree → Nat → Prop
  | 0, x13, x26, x41, x61, x97, x128, b => True
  | n + 1, x13, x26, x41, x61, x97, x128, b => (if (decide (x13 = 0)) = true then True else (match x97 with | some x276 => ((Pre_eff_ty n x13 x26 x41 x276 b) ∧ (∀ b1 : Nat, (Cost_eff_ty n x13 x26 x41 x276) < b → b1 = b - (Cost_eff_ty n x13 x26 x41 x276) → (match (Lanius.Mini.effTy x13 x26 x41 x276) with | some x363 => (match (Lanius.Mini.namedParts x363) with | some x753 => (match (x26.decls.types[x753.decl]?) with | some x857 => ((Pre_payload_tys n x13 x26.decls x753.decl x753.args b1) ∧ (∀ b2 : Nat, (Cost_payload_tys n x13 x26.decls x753.decl x753.args) < b1 → b2 = b1 - (Cost_payload_tys n x13 x26.decls x753.decl x753.args) → (Pre_eff_match_enum n (x13 - 1) x26 x41 x61 x276 x363 x857 (Lanius.Mini.payloadTys x13 x26.decls x753.decl x753.args) x128 b2))) | none => True) | none => (∀ b4 : Nat, (Cost_list_items n x13 (Lanius.Mini.kid x128 5)) < b1 → b4 = b1 - (Cost_list_items n x13 (Lanius.Mini.kid x128 5)) → (match (Lanius.Mini.listItems x13 ((Lanius.Mini.kid x128 5))) with | some x519 => (∀ b5 : Nat, (Cost_lit_wants n x61 x519) < b4 → b5 = b4 - (Cost_lit_wants n x61 x519) → (∀ b6 : Nat, (Cost_arm_value_trees n x519) < b5 → b6 = b5 - (Cost_arm_value_trees n x519) → ((Pre_eff_list n (x13 - 1) x26 x41 (Lanius.Mini.litWants x61 x519) (Lanius.Mini.armValueTrees x519) b6) ∧ (∀ b7 : Nat, (Cost_eff_list n (x13 - 1) x26 x41 (Lanius.Mini.litWants x61 x519) (Lanius.Mini.armValueTrees x519)) < b6 → b7 = b6 - (Cost_eff_list n (x13 - 1) x26 x41 (Lanius.Mini.litWants x61 x519) (Lanius.Mini.armValueTrees x519)) → (Pre_lit_eff_match n x13 x26 x41 x61 ((((Lanius.Mini.kidToken x128 0)).start) - x26.base) x276 x363 x519 (Lanius.Mini.effList ((x13 - 1)) x26 x41 ((Lanius.Mini.litWants x61 x519)) ((Lanius.Mini.armValueTrees x519))) b7))))) | none => True))) | none => True))) | none => True))
termination_by structural fuel => fuel

def Pre_eff_list : Nat → Nat → Lanius.Mini.FrontEnv → List Lanius.Mini.Local → Option (List Lanius.Mini.Ty) → List Lanius.Mini.CTree → Nat → Prop
  | 0, x9, x22, x37, x57, x98, b => True
  | n + 1, x9, x22, x37, x57, x98, b => (if (decide (x9 = 0)) = true then True else (match x98 with | [] => True | x274 :: x277 => ((Pre_eff_of n (x9 - 1) x22 x37 (Lanius.Mini.headTy x57) x274 b) ∧ (∀ b1 : Nat, (Cost_eff_of n (x9 - 1) x22 x37 (Lanius.Mini.headTy x57) x274) < b → b1 = b - (Cost_eff_of n (x9 - 1) x22 x37 (Lanius.Mini.headTy x57) x274) → (Pre_eff_list n (x9 - 1) x22 x37 (Lanius.Mini.tailTys x57) x277 b1)))))
termination_by structural fuel => fuel

def Pre_eff_named : Nat → Nat → Lanius.Mini.FrontEnv → List Lanius.Mini.Local → Option Lanius.Mini.Ty → Lanius.Mini.Split → List Lanius.Mini.CTree → List Lanius.Mini.CTree → Nat → Prop
  | 0, x10, x23, x38, x58, x94, x104, x124, b => True
  | n + 1, x10, x23, x38, x58, x94, x104, x124, b => (if (decide (x10 = 0)) = true then True else ((Pre_is_fn_path n x23 x94 b) ∧ (∀ b1 : Nat, (Cost_is_fn_path n x23 x94) < b → b1 = b - (Cost_is_fn_path n x23 x94) → (if (Lanius.Mini.isFnPath x23 x94) = true then (Pre_eff_fn_path n (x10 - 1) x23 x38 x58 x94 x104 x124 b1) else (if (Lanius.Mini.noTrees x104) = true then ((Pre_variant_by_path n x23 x94 b1) ∧ (∀ b3 : Nat, (Cost_variant_by_path n x23 x94) < b1 → b3 = b1 - (Cost_variant_by_path n x23 x94) → (Pre_eff_variant n (x10 - 1) x23 x38 x58 (Lanius.Mini.variantByPath x23 x94) x124 b3))) else True)))))
termination_by structural fuel => fuel

def Pre_eff_found_with : Nat → Nat → Lanius.Mini.FrontEnv → List Lanius.Mini.Local → Option Lanius.Mini.Ty → Option Lanius.Mini.Found → Lanius.Mini.CTree → List Lanius.Mini.MEff → List Lanius.Mini.CTree → Nat → Prop
  | 0, x15, x28, x43, x63, x99, x135, x149, x166, b => True
  | n + 1, x15, x28, x43, x63, x99, x135, x149, x166, b => (if (decide (x15 = 0)) = true then True else (match x99 with | some x328 => (match (x28.decls.fns[x328.decl]?) with | some x414 => ((Pre_method_binds n (x15 - 1) x28 x414 x328.binds x135 b) ∧ (∀ b1 : Nat, (Cost_method_binds n (x15 - 1) x28 x414 x328.binds x135) < b → b1 = b - (Cost_method_binds n (x15 - 1) x28 x414 x328.binds x135) → ((Pre_receivers_of n (x15 - 1) x28 x43 x414 x149 b1) ∧ (∀ b2 : Nat, (Cost_receivers_of n (x15 - 1) x28 x43 x414 x149) < b1 → b2 = b1 - (Cost_receivers_of n (x15 - 1) x28 x43 x414 x149) → (Pre_eff_bound_recv n (x15 - 1) x28 x43 x63 x328.decl x414 (Lanius.Mini.methodBinds ((x15 - 1)) x28 x414 x328.binds x135) (Lanius.Mini.receiversOf ((x15 - 1)) x28 x43 x414 x149) x166 b2))))) | none => True) | none => True))
termination_by structural fuel => fuel

def Pre_eff_step : Nat → Nat → Lanius.Mini.FrontEnv → List Lanius.Mini.Local → Option Lanius.Mini.Ty → Lanius.Mini.MEff → Lanius.Mini.CTree → Nat → Prop
  | 0, x9, x22, x37, x57, x93, x102, b => True
  | n + 1, x9, x22, x37, x57, x93, x102, b => (if (decide (x9 = 0)) = true then True else (let k20 := fun (b1 : Nat) => (if (decide ((Lanius.Mini.nodeProd ((Lanius.Mini.kid x102 3))) = Lanius.Mini.Inline.pPostfixCall)) = true then (∀ b2 : Nat, (Cost_list_items n (x9 - 1) (Lanius.Mini.kid ((Lanius.Mini.kid x102 3)) 1)) < b1 → b2 = b1 - (Cost_list_items n (x9 - 1) (Lanius.Mini.kid ((Lanius.Mini.kid x102 3)) 1)) → (match (Lanius.Mini.listItems ((x9 - 1)) ((Lanius.Mini.kid ((Lanius.Mini.kid x102 3)) 1))) with | some x518 => ((Pre_eff_ty n (x9 - 1) x22 x37 x93 b2) ∧ (∀ b3 : Nat, (Cost_eff_ty n (x9 - 1) x22 x37 x93) < b2 → b3 = b2 - (Cost_eff_ty n (x9 - 1) x22 x37 x93) → ((Pre_method_of_ty n (x9 - 1) x22 (Lanius.Mini.referentOrOf ((Lanius.Mini.effTy ((x9 - 1)) x22 x37 x93))) (((Lanius.Mini.kidToken x102 1)).text) b3) ∧ (∀ b4 : Nat, (Cost_method_of_ty n (x9 - 1) x22 (Lanius.Mini.referentOrOf ((Lanius.Mini.effTy ((x9 - 1)) x22 x37 x93))) (((Lanius.Mini.kidToken x102 1)).text)) < b3 → b4 = b3 - (Cost_method_of_ty n (x9 - 1) x22 (Lanius.Mini.referentOrOf ((Lanius.Mini.effTy ((x9 - 1)) x22 x37 x93))) (((Lanius.Mini.kidToken x102 1)).text)) → (∀ b5 : Nat, (Cost_single_of_mini_selfhost_MEff n x93) < b4 → b5 = b4 - (Cost_single_of_mini_selfhost_MEff n x93) → ((Pre_eff_found_with n (x9 - 1) x22 x37 (Lanius.Mini.stepExpected x57 ((Lanius.Mini.kid ((Lanius.Mini.kid x102 3)) 3))) (Lanius.Mini.methodOfTy ((x9 - 1)) x22 ((Lanius.Mini.referentOrOf ((Lanius.Mini.effTy ((x9 - 1)) x22 x37 x93)))) ((((Lanius.Mini.kidToken x102 1)).text))) (Lanius.Mini.kid x102 2) ([x93]) x518 b5) ∧ (∀ b6 : Nat, (Cost_eff_found_with n (x9 - 1) x22 x37 (Lanius.Mini.stepExpected x57 ((Lanius.Mini.kid ((Lanius.Mini.kid x102 3)) 3))) (Lanius.Mini.methodOfTy ((x9 - 1)) x22 ((Lanius.Mini.referentOrOf ((Lanius.Mini.effTy ((x9 - 1)) x22 x37 x93)))) ((((Lanius.Mini.kidToken x102 1)).text))) (Lanius.Mini.kid x102 2) ([x93]) x518) < b5 → b6 = b5 - (Cost_eff_found_with n (x9 - 1) x22 x37 (Lanius.Mini.stepExpected x57 ((Lanius.Mini.kid ((Lanius.Mini.kid x102 3)) 3))) (Lanius.Mini.methodOfTy ((x9 - 1)) x22 ((Lanius.Mini.referentOrOf ((Lanius.Mini.effTy ((x9 - 1)) x22 x37 x93)))) ((((Lanius.Mini.kidToken x102 1)).text))) (Lanius.Mini.kid x102 2) ([x93]) x518) → (Pre_eff_chain n (x9 - 1) x22 x37 x57 (Lanius.Mini.effFoundWith ((x9 - 1)) x22 x37 ((Lanius.Mini.stepExpected x57 ((Lanius.Mini.kid ((Lanius.Mini.kid x102 3)) 3)))) ((Lanius.Mini.methodOfTy ((x9 - 1)) x22 ((Lanius.Mini.referentOrOf ((Lanius.Mini.effTy ((x9 - 1)) x22 x37 x93)))) ((((Lanius.Mini.kidToken x102 1)).text)))) ((Lanius.Mini.kid x102 2)) ([x93]) x518) (Lanius.Mini.kid ((Lanius.Mini.kid x102 3)) 3) b6)))))))) | none => True)) else (if (decide ((Lanius.Mini.nodeProd ((Lanius.Mini.kid x102 2))) = Lanius.Mini.Inline.pMemberTypeArgsNone)) = true then ((Pre_eff_ty n (x9 - 1) x22 x37 x93 b1) ∧ (∀ b8 : Nat, (Cost_eff_ty n (x9 - 1) x22 x37 x93) < b1 → b8 = b1 - (Cost_eff_ty n (x9 - 1) x22 x37 x93) → ((Pre_field_of_ty n x22 x93 (Lanius.Mini.effTy ((x9 - 1)) x22 x37 x93) (((Lanius.Mini.kidToken x102 1)).text) b8) ∧ (∀ b9 : Nat, (Cost_field_of_ty n x22 x93 (Lanius.Mini.effTy ((x9 - 1)) x22 x37 x93) (((Lanius.Mini.kidToken x102 1)).text)) < b8 → b9 = b8 - (Cost_field_of_ty n x22 x93 (Lanius.Mini.effTy ((x9 - 1)) x22 x37 x93) (((Lanius.Mini.kidToken x102 1)).text)) → (Pre_eff_chain n (x9 - 1) x22 x37 x57 (Lanius.Mini.fieldOfTy x22 x93 ((Lanius.Mini.effTy ((x9 - 1)) x22 x37 x93)) ((((Lanius.Mini.kidToken x102 1)).text))) (Lanius.Mini.kid x102 3) b9))))) else True)); let k21 := fun (b1 : Nat) => (let k18 := fun (b11 : Nat) => ((Pre_eff_of n (x9 - 1) x22 x37 (none : Option Lanius.Mini.Ty) (Lanius.Mini.kid x102 1) b11) ∧ (∀ b12 : Nat, (Cost_eff_of n (x9 - 1) x22 x37 (none : Option Lanius.Mini.Ty) (Lanius.Mini.kid x102 1)) < b11 → b12 = b11 - (Cost_eff_of n (x9 - 1) x22 x37 (none : Option Lanius.Mini.Ty) (Lanius.Mini.kid x102 1)) → (∀ b13 : Nat, (Cost_x_at_of n x93 (Lanius.Mini.effOf ((x9 - 1)) x22 x37 ((none : Option Lanius.Mini.Ty)) ((Lanius.Mini.kid x102 1)))) < b12 → b13 = b12 - (Cost_x_at_of n x93 (Lanius.Mini.effOf ((x9 - 1)) x22 x37 ((none : Option Lanius.Mini.Ty)) ((Lanius.Mini.kid x102 1)))) → (Pre_eff_chain n (x9 - 1) x22 x37 x57 (Lanius.Mini.xAtOf x93 ((Lanius.Mini.effOf ((x9 - 1)) x22 x37 ((none : Option Lanius.Mini.Ty)) ((Lanius.Mini.kid x102 1))))) (Lanius.Mini.kid x102 3) b13)))); let k19 := fun (b11 : Nat) => (if (decide ((Lanius.Mini.nodeProd x102) = Lanius.Mini.Inline.pPostfixIndex)) = true then ((Pre_eff_of n (x9 - 1) x22 x37 (none : Option Lanius.Mini.Ty) (Lanius.Mini.kid x102 1) b11) ∧ (∀ b15 : Nat, (Cost_eff_of n (x9 - 1) x22 x37 (none : Option Lanius.Mini.Ty) (Lanius.Mini.kid x102 1)) < b11 → b15 = b11 - (Cost_eff_of n (x9 - 1) x22 x37 (none : Option Lanius.Mini.Ty) (Lanius.Mini.kid x102 1)) → (∀ b16 : Nat, (Cost_x_index_of n (Lanius.Mini.effSliceLocal x37 x93) (Lanius.Mini.effOf ((x9 - 1)) x22 x37 ((none : Option Lanius.Mini.Ty)) ((Lanius.Mini.kid x102 1)))) < b15 → b16 = b15 - (Cost_x_index_of n (Lanius.Mini.effSliceLocal x37 x93) (Lanius.Mini.effOf ((x9 - 1)) x22 x37 ((none : Option Lanius.Mini.Ty)) ((Lanius.Mini.kid x102 1)))) → (Pre_eff_chain n (x9 - 1) x22 x37 x57 (Lanius.Mini.xIndexOf ((Lanius.Mini.effSliceLocal x37 x93)) ((Lanius.Mini.effOf ((x9 - 1)) x22 x37 ((none : Option Lanius.Mini.Ty)) ((Lanius.Mini.kid x102 1))))) (Lanius.Mini.kid x102 3) b16)))) else True); (if (decide ((Lanius.Mini.nodeProd x102) = Lanius.Mini.Inline.pPostfixIndex)) = true then (if (Lanius.Mini.effPlace x93) = true then (k18 b1) else (k19 b1)) else (k19 b1))); (if (decide ((Lanius.Mini.nodeProd x102) = Lanius.Mini.Inline.pPostfixMember)) = true then (if (Lanius.Mini.memberArgs ((Lanius.Mini.nodeProd ((Lanius.Mini.kid x102 2))))) = true then (k20 b) else (k21 b)) else (k21 b))))
termination_by structural fuel => fuel

def Pre_eff_match_enum : Nat → Nat → Lanius.Mini.FrontEnv → List Lanius.Mini.Local → Option Lanius.Mini.Ty → Lanius.Mini.MEff → Lanius.Mini.Ty → Lanius.Mini.TypeDecl → Option (List (List Lanius.Mini.Ty)) → Lanius.Mini.CTree → Nat → Prop
  | 0, x15, x28, x43, x63, x99, x108, x117, x130, x178, b => True
  | n + 1, x15, x28, x43, x63, x99, x108, x117, x130, x178, b => (if (decide (x15 = 0)) = true then True else (if x117.isEnum = true then (match x130 with | some x366 => (∀ b1 : Nat, (Cost_list_items n x15 (Lanius.Mini.kid x178 5)) < b → b1 = b - (Cost_list_items n x15 (Lanius.Mini.kid x178 5)) → (match (Lanius.Mini.listItems x15 ((Lanius.Mini.kid x178 5))) with | some x462 => (∀ b2 : Nat, (Cost_zip_variants n x117.variants x366) < b1 → b2 = b1 - (Cost_zip_variants n x117.variants x366) → (Pre_eff_arms_ordered n (x15 - 1) x28 x43 x63 x117 (Lanius.Mini.zipVariants x117.variants x366) x462 b2)) | none => True)) | none => True) else True))
termination_by structural fuel => fuel

def Pre_eff_fn_path : Nat → Nat → Lanius.Mini.FrontEnv → List Lanius.Mini.Local → Option Lanius.Mini.Ty → Lanius.Mini.Split → List Lanius.Mini.CTree → List Lanius.Mini.CTree → Nat → Prop
  | 0, x12, x25, x40, x60, x96, x106, x126, b => True
  | n + 1, x12, x25, x40, x60, x96, x106, x126, b => (if (decide (x12 = 0)) = true then True else (let k7 := fun (b1 : Nat) => ((Pre_bare_ty n x25 x96.home b1) ∧ (∀ b2 : Nat, (Cost_bare_ty n x25 x96.home) < b1 → b2 = b1 - (Cost_bare_ty n x25 x96.home) → (match (Lanius.Mini.bareTy x25 x96.home) with | some x444 => ((Pre_find_method n x12 x25.decls x25.decls.fns 0 x96.name x444 b2) ∧ (∀ b3 : Nat, (Cost_find_method n x12 x25.decls x25.decls.fns 0 x96.name x444) < b2 → b3 = b2 - (Cost_find_method n x12 x25.decls x25.decls.fns 0 x96.name x444) → (Pre_eff_found n (x12 - 1) x25 x40 x60 (Lanius.Mini.findMethod x12 x25.decls x25.decls.fns 0 x96.name x444) ([] : List Lanius.Mini.MEff) x126 b3))) | none => True))); let k8 := fun (b1 : Nat) => (∀ b5 : Nat, (Cost_path_module n x25 x96.home x96.name) < b1 → b5 = b1 - (Cost_path_module n x25 x96.home x96.name) → ((Pre_find_fn n x25.decls.fns (Lanius.Mini.pathModule x25 x96.home x96.name) x96.name 0 b5) ∧ (match (Lanius.Mini.findFn x25.decls.fns ((Lanius.Mini.pathModule x25 x96.home x96.name)) x96.name 0) with | some x715 => (match (x25.decls.fns[x715]?) with | some x796 => (Pre_eff_free n (x12 - 1) x25 x40 x60 x715 x796 x106 x126 b5) | none => True) | none => True))); ((Pre_is_type_owner n x25 x96.home x96.name b) ∧ (∀ b9 : Nat, (Cost_is_type_owner n x25 x96.home x96.name) < b → b9 = b - (Cost_is_type_owner n x25 x96.home x96.name) → (if (Lanius.Mini.isTypeOwner x25 x96.home x96.name) = true then (if (Lanius.Mini.noTrees x106) = true then (k7 b9) else (k8 b9)) else (k8 b9))))))
termination_by structural fuel => fuel

def Pre_eff_bound_recv : Nat → Nat → Lanius.Mini.FrontEnv → List Lanius.Mini.Local → Option Lanius.Mini.Ty → Nat → Lanius.Mini.FnDecl → Option (List Lanius.Mini.Bind) → Option (List Lanius.Mini.MEff) → List Lanius.Mini.CTree → Nat → Prop
  | 0, x15, x28, x43, x63, x99, x109, x121, x162, x201, b => True
  | n + 1, x15, x28, x43, x63, x99, x109, x121, x162, x201, b => (match x162 with | some x313 => (Pre_eff_bound n x15 x28 x43 x63 x99 x109 x121 x313 x201 b) | none => True)
termination_by structural fuel => fuel

def Pre_eff_arms_ordered : Nat → Nat → Lanius.Mini.FrontEnv → List Lanius.Mini.Local → Option Lanius.Mini.Ty → Lanius.Mini.TypeDecl → List Lanius.Mini.VariantTy → List Lanius.Mini.CTree → Nat → Prop
  | 0, x17, x30, x45, x65, x101, x118, x145, b => True
  | n + 1, x17, x30, x45, x65, x101, x118, x145, b => (if (decide (x17 = 0)) = true then True else ((Pre_match_order n x17 x30 x101 x118 x145 b) ∧ (∀ b1 : Nat, (Cost_match_order n x17 x30 x101 x118 x145) < b → b1 = b - (Cost_match_order n x17 x30 x101 x118 x145) → (match (Lanius.Mini.matchOrder x17 x30 x101 x118 x145) with | some x354 => (Pre_eff_arms n (x17 - 1) x30 x45 x65 x101 x118 x354 b1) | none => True))))
termination_by structural fuel => fuel

def Pre_eff_found : Nat → Nat → Lanius.Mini.FrontEnv → List Lanius.Mini.Local → Option Lanius.Mini.Ty → Option Lanius.Mini.Found → List Lanius.Mini.MEff → List Lanius.Mini.CTree → Nat → Prop
  | 0, x10, x23, x38, x58, x94, x130, x147, b => True
  | n + 1, x10, x23, x38, x58, x94, x130, x147, b => (if (decide (x10 = 0)) = true then True else (match x94 with | some x309 => (match (x23.decls.fns[x309.decl]?) with | some x395 => (Pre_eff_infer n (x10 - 1) x23 x38 x58 x309.decl x395 x309.binds x130 x147 b) | none => True) | none => True))
termination_by structural fuel => fuel

def Pre_eff_free : Nat → Nat → Lanius.Mini.FrontEnv → List Lanius.Mini.Local → Option Lanius.Mini.Ty → Nat → Lanius.Mini.FnDecl → List Lanius.Mini.CTree → List Lanius.Mini.CTree → Nat → Prop
  | 0, x9, x22, x37, x57, x93, x103, x115, x135, b => True
  | n + 1, x9, x22, x37, x57, x93, x103, x115, x135, b => (if (decide (x9 = 0)) = true then True else (if (Lanius.Mini.noTrees x115) = true then (Pre_eff_infer n (x9 - 1) x22 x37 x57 x93 x103 ([] : List Lanius.Mini.Bind) ([] : List Lanius.Mini.MEff) x135 b) else ((Pre_explicit_inst n x9 x22 x93 x103 x115 b) ∧ (∀ b2 : Nat, (Cost_explicit_inst n x9 x22 x93 x103 x115) < b → b2 = b - (Cost_explicit_inst n x9 x22 x93 x103 x115) → (match (Lanius.Mini.explicitInst x9 x22 x93 x103 x115) with | some x459 => ((Pre_param_expects n x9 x22.decls x103 (some x459.args) b2) ∧ (∀ b3 : Nat, (Cost_param_expects n x9 x22.decls x103 (some x459.args)) < b2 → b3 = b2 - (Cost_param_expects n x9 x22.decls x103 (some x459.args)) → ((Pre_param_expects n x9 x22.decls x103 (some x459.args) b3) ∧ (∀ b4 : Nat, (Cost_param_expects n x9 x22.decls x103 (some x459.args)) < b3 → b4 = b3 - (Cost_param_expects n x9 x22.decls x103 (some x459.args)) → ((Pre_param_expects n x9 x22.decls x103 (some x459.args) b4) ∧ (∀ b5 : Nat, (Cost_param_expects n x9 x22.decls x103 (some x459.args)) < b4 → b5 = b4 - (Cost_param_expects n x9 x22.decls x103 (some x459.args)) → (Pre_eff_list n (x9 - 1) x22 x37 (Lanius.Mini.paramExpects x9 x22.decls x103 ((some x459.args))) x135 b5))))))) | none => True)))))
termination_by structural fuel => fuel

def Pre_eff_bound : Nat → Nat → Lanius.Mini.FrontEnv → List Lanius.Mini.Local → Option Lanius.Mini.Ty → Nat → Lanius.Mini.FnDecl → Option (List Lanius.Mini.Bind) → List Lanius.Mini.MEff → List Lanius.Mini.CTree → Nat → Prop
  | 0, x10, x23, x38, x58, x94, x104, x116, x157, x174, b => True
  | n + 1, x10, x23, x38, x58, x94, x104, x116, x157, x174, b => (if (decide (x10 = 0)) = true then True else (match x116 with | some x336 => (Pre_eff_infer n (x10 - 1) x23 x38 x58 x94 x104 x336 x157 x174 b) | none => True))
termination_by structural fuel => fuel

def Pre_eff_arms : Nat → Nat → Lanius.Mini.FrontEnv → List Lanius.Mini.Local → Option Lanius.Mini.Ty → Lanius.Mini.TypeDecl → List Lanius.Mini.VariantTy → List Lanius.Mini.CTree → Nat → Prop
  | 0, x9, x22, x37, x57, x93, x110, x137, b => True
  | n + 1, x9, x22, x37, x57, x93, x110, x137, b => (if (decide (x9 = 0)) = true then True else (match x110 with | [] => True | x397 :: x400 => (match x137 with | [] => True | x466 :: x469 => ((Pre_eff_arm n (x9 - 1) x22 x37 x57 x93 x397 x466 b) ∧ (∀ b1 : Nat, (Cost_eff_arm n (x9 - 1) x22 x37 x57 x93 x397 x466) < b → b1 = b - (Cost_eff_arm n (x9 - 1) x22 x37 x57 x93 x397 x466) → (Pre_eff_arms n (x9 - 1) x22 x37 x57 x93 x400 x469 b1))))))
termination_by structural fuel => fuel

def Pre_eff_infer : Nat → Nat → Lanius.Mini.FrontEnv → List Lanius.Mini.Local → Option Lanius.Mini.Ty → Nat → Lanius.Mini.FnDecl → List Lanius.Mini.Bind → List Lanius.Mini.MEff → List Lanius.Mini.CTree → Nat → Prop
  | 0, x10, x23, x38, x58, x94, x104, x116, x135, x152, b => True
  | n + 1, x10, x23, x38, x58, x94, x104, x116, x135, x152, b => (if (decide (x10 = 0)) = true then True else (∀ b1 : Nat, (Cost_concat_of_mini_selfhost_List_usize n x104.implParams x104.params) < b → b1 = b - (Cost_concat_of_mini_selfhost_List_usize n x104.implParams x104.params) → (if (Lanius.Mini.noNames ((x104.implParams ++ x104.params))) = true then ((Pre_param_expects n x10 x23.decls x104 (some ([] : List Lanius.Mini.Ty)) b1) ∧ (∀ b2 : Nat, (Cost_param_expects n x10 x23.decls x104 (some ([] : List Lanius.Mini.Ty))) < b1 → b2 = b1 - (Cost_param_expects n x10 x23.decls x104 (some ([] : List Lanius.Mini.Ty))) → ((Pre_arg_list n (x10 - 1) x23 x38 (Lanius.Mini.skipExpects ((Lanius.Mini.paramExpects x10 x23.decls x104 ((some ([] : List Lanius.Mini.Ty))))) x135) x152 b2) ∧ (∀ b3 : Nat, (Cost_arg_list n (x10 - 1) x23 x38 (Lanius.Mini.skipExpects ((Lanius.Mini.paramExpects x10 x23.decls x104 ((some ([] : List Lanius.Mini.Ty))))) x135) x152) < b2 → b3 = b2 - (Cost_arg_list n (x10 - 1) x23 x38 (Lanius.Mini.skipExpects ((Lanius.Mini.paramExpects x10 x23.decls x104 ((some ([] : List Lanius.Mini.Ty))))) x135) x152) → (∀ b4 : Nat, (Cost_views_of n x38 (Lanius.Mini.skipExpects ((Lanius.Mini.paramExpects x10 x23.decls x104 ((some ([] : List Lanius.Mini.Ty))))) x135) (Lanius.Mini.argList ((x10 - 1)) x23 x38 ((Lanius.Mini.skipExpects ((Lanius.Mini.paramExpects x10 x23.decls x104 ((some ([] : List Lanius.Mini.Ty))))) x135)) x152)) < b3 → b4 = b3 - (Cost_views_of n x38 (Lanius.Mini.skipExpects ((Lanius.Mini.paramExpects x10 x23.decls x104 ((some ([] : List Lanius.Mini.Ty))))) x135) (Lanius.Mini.argList ((x10 - 1)) x23 x38 ((Lanius.Mini.skipExpects ((Lanius.Mini.paramExpects x10 x23.decls x104 ((some ([] : List Lanius.Mini.Ty))))) x135)) x152)) → (Pre_eff_called n x10 x23 x38 x58 x94 x104 x116 x135 (Lanius.Mini.viewsOf x38 ((Lanius.Mini.skipExpects ((Lanius.Mini.paramExpects x10 x23.decls x104 ((some ([] : List Lanius.Mini.Ty))))) x135)) ((Lanius.Mini.argList ((x10 - 1)) x23 x38 ((Lanius.Mini.skipExpects ((Lanius.Mini.paramExpects x10 x23.decls x104 ((some ([] : List Lanius.Mini.Ty))))) x135)) x152))) b4)))))) else (∀ b6 : Nat, (Cost_param_patterns n x10 x104) < b1 → b6 = b1 - (Cost_param_patterns n x10 x104) → (match (Lanius.Mini.paramPatterns x10 x104) with | some x764 => ((Pre_ret_binds n x10 x23.decls x104 (x104.implParams ++ x104.params) x116 x58 b6) ∧ (∀ b7 : Nat, (Cost_ret_binds n x10 x23.decls x104 (x104.implParams ++ x104.params) x116 x58) < b6 → b7 = b6 - (Cost_ret_binds n x10 x23.decls x104 (x104.implParams ++ x104.params) x116 x58) → ((Pre_eff_args_bound n (x10 - 1) x23 x38 x104 (x104.implParams ++ x104.params) x764 x135 x152 (Lanius.Mini.retBinds x10 x23.decls x104 ((x104.implParams ++ x104.params)) x116 x58) b7) ∧ (∀ b8 : Nat, (Cost_eff_args_bound n (x10 - 1) x23 x38 x104 (x104.implParams ++ x104.params) x764 x135 x152 (Lanius.Mini.retBinds x10 x23.decls x104 ((x104.implParams ++ x104.params)) x116 x58)) < b7 → b8 = b7 - (Cost_eff_args_bound n (x10 - 1) x23 x38 x104 (x104.implParams ++ x104.params) x764 x135 x152 (Lanius.Mini.retBinds x10 x23.decls x104 ((x104.implParams ++ x104.params)) x116 x58)) → (Pre_eff_inferred n x10 x23 x38 x94 x104 (x104.implParams ++ x104.params) x764 (Lanius.Mini.effArgsBound ((x10 - 1)) x23 x38 x104 ((x104.implParams ++ x104.params)) x764 x135 x152 ((Lanius.Mini.retBinds x10 x23.decls x104 ((x104.implParams ++ x104.params)) x116 x58))) b8))))) | none => True)))))
termination_by structural fuel => fuel

def Pre_eff_arm : Nat → Nat → Lanius.Mini.FrontEnv → List Lanius.Mini.Local → Option Lanius.Mini.Ty → Lanius.Mini.TypeDecl → Lanius.Mini.VariantTy → Lanius.Mini.CTree → Nat → Prop
  | 0, x8, x21, x36, x56, x92, x109, x123, b => True
  | n + 1, x8, x21, x36, x56, x92, x109, x123, b => (if (decide (x8 = 0)) = true then True else (let k6 := fun (b1 : Nat) => (if (decide ((Lanius.Mini.nodeProd ((Lanius.Mini.kid ((Lanius.Mini.kid x123 0)) 1))) = Lanius.Mini.Inline.pPatternPlain)) = true then (Pre_eff_arm_bound n (x8 - 1) x21 x56 (some (Lanius.Mini.Bound.mk ([] : List Nat) x36)) (Lanius.Mini.kid x123 2) b1) else (∀ b3 : Nat, (Cost_list_items n x8 (Lanius.Mini.kid ((Lanius.Mini.kid ((Lanius.Mini.kid x123 0)) 1)) 1)) < b1 → b3 = b1 - (Cost_list_items n x8 (Lanius.Mini.kid ((Lanius.Mini.kid ((Lanius.Mini.kid x123 0)) 1)) 1)) → (match (Lanius.Mini.listItems x8 ((Lanius.Mini.kid ((Lanius.Mini.kid ((Lanius.Mini.kid x123 0)) 1)) 1))) with | some x748 => (∀ b4 : Nat, (Cost_binders_of n x21 x36 x748 x109.payload) < b3 → b4 = b3 - (Cost_binders_of n x21 x36 x748 x109.payload) → (Pre_eff_arm_bound n (x8 - 1) x21 x56 (Lanius.Mini.bindersOf x21 x36 x748 x109.payload) (Lanius.Mini.kid x123 2) b4)) | none => True))); let k7 := fun (b1 : Nat) => True; (if (decide ((Lanius.Mini.nodeProd ((Lanius.Mini.kid x123 0))) = Lanius.Mini.Inline.pPatternIdent)) = true then (∀ b8 : Nat, (Cost_path_spellings n x8 (Lanius.Mini.kid ((Lanius.Mini.kid ((Lanius.Mini.kid x123 0)) 0)) 0) (Lanius.Mini.kid ((Lanius.Mini.kid ((Lanius.Mini.kid x123 0)) 0)) 1)) < b → b8 = b - (Cost_path_spellings n x8 (Lanius.Mini.kid ((Lanius.Mini.kid ((Lanius.Mini.kid x123 0)) 0)) 0) (Lanius.Mini.kid ((Lanius.Mini.kid ((Lanius.Mini.kid x123 0)) 0)) 1)) → (∀ b9 : Nat, (Cost_arm_named n (Lanius.Mini.pathSpellings x8 ((Lanius.Mini.kid ((Lanius.Mini.kid ((Lanius.Mini.kid x123 0)) 0)) 0)) ((Lanius.Mini.kid ((Lanius.Mini.kid ((Lanius.Mini.kid x123 0)) 0)) 1))) x92 x109.name) < b8 → b9 = b8 - (Cost_arm_named n (Lanius.Mini.pathSpellings x8 ((Lanius.Mini.kid ((Lanius.Mini.kid ((Lanius.Mini.kid x123 0)) 0)) 0)) ((Lanius.Mini.kid ((Lanius.Mini.kid ((Lanius.Mini.kid x123 0)) 0)) 1))) x92 x109.name) → (if (Lanius.Mini.armNamed ((Lanius.Mini.pathSpellings x8 ((Lanius.Mini.kid ((Lanius.Mini.kid ((Lanius.Mini.kid x123 0)) 0)) 0)) ((Lanius.Mini.kid ((Lanius.Mini.kid ((Lanius.Mini.kid x123 0)) 0)) 1)))) x92 x109.name) = true then (k6 b9) else (k7 b9)))) else (k7 b))))
termination_by structural fuel => fuel

def Pre_arg_list : Nat → Nat → Lanius.Mini.FrontEnv → List Lanius.Mini.Local → Option (List Lanius.Mini.Ty) → List Lanius.Mini.CTree → Nat → Prop
  | 0, x9, x22, x37, x57, x98, b => True
  | n + 1, x9, x22, x37, x57, x98, b => (if (decide (x9 = 0)) = true then True else (match x98 with | [] => True | x274 :: x277 => ((Pre_arg_eff n (x9 - 1) x22 x37 (Lanius.Mini.headTy x57) x274 b) ∧ (∀ b1 : Nat, (Cost_arg_eff n (x9 - 1) x22 x37 (Lanius.Mini.headTy x57) x274) < b → b1 = b - (Cost_arg_eff n (x9 - 1) x22 x37 (Lanius.Mini.headTy x57) x274) → (Pre_arg_list n (x9 - 1) x22 x37 (Lanius.Mini.tailTys x57) x277 b1)))))
termination_by structural fuel => fuel

def Pre_eff_args_bound : Nat → Nat → Lanius.Mini.FrontEnv → List Lanius.Mini.Local → Lanius.Mini.FnDecl → List (List Nat) → List Lanius.Mini.CTree → List Lanius.Mini.MEff → List Lanius.Mini.CTree → Option (List Lanius.Mini.Bind) → Nat → Prop
  | 0, x15, x28, x43, x63, x75, x101, x118, x135, x155, b => True
  | n + 1, x15, x28, x43, x63, x75, x101, x118, x135, x155, b => (if (decide (x15 = 0)) = true then True else (match x155 with | some x378 => (match x101 with | [] => True | x674 :: x677 => (match x118 with | [] => (match x135 with | [] => True | x965 :: x968 => (∀ b1 : Nat, (Cost_bound_args n x75 x378) < b → b1 = b - (Cost_bound_args n x75 x378) → (if (!(Lanius.Mini.hasTys ((Lanius.Mini.boundArgs x75 x378)))) = true then ((Pre_arg_expected n (x15 - 1) x28.decls x63 x75 x674 x378 b1) ∧ (∀ b2 : Nat, (Cost_arg_expected n (x15 - 1) x28.decls x63 x75 x674 x378) < b1 → b2 = b1 - (Cost_arg_expected n (x15 - 1) x28.decls x63 x75 x674 x378) → ((Pre_arg_expected n (x15 - 1) x28.decls x63 x75 x674 x378 b2) ∧ (∀ b3 : Nat, (Cost_arg_expected n (x15 - 1) x28.decls x63 x75 x674 x378) < b2 → b3 = b2 - (Cost_arg_expected n (x15 - 1) x28.decls x63 x75 x674 x378) → ((Pre_eff_of n (x15 - 1) x28 x43 (Lanius.Mini.argExpected ((x15 - 1)) x28.decls x63 x75 x674 x378) x965 b3) ∧ (∀ b4 : Nat, (Cost_eff_of n (x15 - 1) x28 x43 (Lanius.Mini.argExpected ((x15 - 1)) x28.decls x63 x75 x674 x378) x965) < b3 → b4 = b3 - (Cost_eff_of n (x15 - 1) x28 x43 (Lanius.Mini.argExpected ((x15 - 1)) x28.decls x63 x75 x674 x378) x965) → (Pre_eff_arg_next n (x15 - 1) x28 x43 x63 x75 x674 x677 x968 x378 (Lanius.Mini.viewOf x43 ((Lanius.Mini.argExpected ((x15 - 1)) x28.decls x63 x75 x674 x378)) ((Lanius.Mini.effOf ((x15 - 1)) x28 x43 ((Lanius.Mini.argExpected ((x15 - 1)) x28.decls x63 x75 x674 x378)) x965))) b4))))))) else ((Pre_arg_expected n (x15 - 1) x28.decls x63 x75 x674 x378 b1) ∧ (∀ b6 : Nat, (Cost_arg_expected n (x15 - 1) x28.decls x63 x75 x674 x378) < b1 → b6 = b1 - (Cost_arg_expected n (x15 - 1) x28.decls x63 x75 x674 x378) → ((Pre_arg_expected n (x15 - 1) x28.decls x63 x75 x674 x378 b6) ∧ (∀ b7 : Nat, (Cost_arg_expected n (x15 - 1) x28.decls x63 x75 x674 x378) < b6 → b7 = b6 - (Cost_arg_expected n (x15 - 1) x28.decls x63 x75 x674 x378) → ((Pre_arg_expected n (x15 - 1) x28.decls x63 x75 x674 x378 b7) ∧ (∀ b8 : Nat, (Cost_arg_expected n (x15 - 1) x28.decls x63 x75 x674 x378) < b7 → b8 = b7 - (Cost_arg_expected n (x15 - 1) x28.decls x63 x75 x674 x378) → ((Pre_eff_of n (x15 - 1) x28 x43 (Lanius.Mini.argExpected ((x15 - 1)) x28.decls x63 x75 x674 x378) x965 b8) ∧ (∀ b9 : Nat, (Cost_eff_of n (x15 - 1) x28 x43 (Lanius.Mini.argExpected ((x15 - 1)) x28.decls x63 x75 x674 x378) x965) < b8 → b9 = b8 - (Cost_eff_of n (x15 - 1) x28 x43 (Lanius.Mini.argExpected ((x15 - 1)) x28.decls x63 x75 x674 x378) x965) → (Pre_eff_arg_next n (x15 - 1) x28 x43 x63 x75 x674 x677 x968 x378 (Lanius.Mini.viewOf x43 ((Lanius.Mini.argExpected ((x15 - 1)) x28.decls x63 x75 x674 x378)) ((Lanius.Mini.effOf ((x15 - 1)) x28 x43 ((Lanius.Mini.argExpected ((x15 - 1)) x28.decls x63 x75 x674 x378)) x965))) b9)))))))))))) | x721 :: x724 => ((Pre_bind_arg n (x15 - 1) x28 x43 x63 x75 x674 x721 x378 b) ∧ (∀ b11 : Nat, (Cost_bind_arg n (x15 - 1) x28 x43 x63 x75 x674 x721 x378) < b → b11 = b - (Cost_bind_arg n (x15 - 1) x28 x43 x63 x75 x674 x721 x378) → (Pre_eff_args_bound n (x15 - 1) x28 x43 x63 x75 x677 x724 x135 (Lanius.Mini.bindArg ((x15 - 1)) x28 x43 x63 x75 x674 x721 x378) b11))))) | none => True))
termination_by structural fuel => fuel

def Pre_eff_arm_bound : Nat → Nat → Lanius.Mini.FrontEnv → Option Lanius.Mini.Ty → Option Lanius.Mini.Bound → Lanius.Mini.CTree → Nat → Prop
  | 0, x14, x27, x42, x78, x114, b => True
  | n + 1, x14, x27, x42, x78, x114, b => (if (decide (x14 = 0)) = true then True else (match x78 with | some x272 => ((Pre_eff_of n (x14 - 1) x27 x272.scope x42 x114 b) ∧ (∀ b1 : Nat, (Cost_eff_of n (x14 - 1) x27 x272.scope x42 x114) < b → b1 = b - (Cost_eff_of n (x14 - 1) x27 x272.scope x42 x114) → ((Pre_diverge_arm n x27.decls x42 (Lanius.Mini.effOf ((x14 - 1)) x27 x272.scope x42 x114) b1) ∧ (∀ b2 : Nat, (Cost_diverge_arm n x27.decls x42 (Lanius.Mini.effOf ((x14 - 1)) x27 x272.scope x42 x114)) < b1 → b2 = b1 - (Cost_diverge_arm n x27.decls x42 (Lanius.Mini.effOf ((x14 - 1)) x27 x272.scope x42 x114)) → (Pre_arm_eff n x14 x27 x272 (Lanius.Mini.divergeArm x27.decls x42 ((Lanius.Mini.effOf ((x14 - 1)) x27 x272.scope x42 x114))) b2))))) | none => True))
termination_by structural fuel => fuel

def Pre_arg_eff : Nat → Nat → Lanius.Mini.FrontEnv → List Lanius.Mini.Local → Option Lanius.Mini.Ty → Lanius.Mini.CTree → Nat → Prop
  | 0, x8, x21, x36, x56, x92, b => True
  | n + 1, x8, x21, x36, x56, x92, b => (if (decide (x8 = 0)) = true then True else (∀ b1 : Nat, (Cost_string_init n x8 x92) < b → b1 = b - (Cost_string_init n x8 x92) → (match (Lanius.Mini.stringInit x8 x92) with | some x237 => True | none => (Pre_eff_of n (x8 - 1) x21 x36 x56 x92 b1))))
termination_by structural fuel => fuel

def Pre_eff_arg_next : Nat → Nat → Lanius.Mini.FrontEnv → List Lanius.Mini.Local → Lanius.Mini.FnDecl → List (List Nat) → Lanius.Mini.CTree → List Lanius.Mini.CTree → List Lanius.Mini.CTree → List Lanius.Mini.Bind → Option Lanius.Mini.MEff → Nat → Prop
  | 0, x13, x26, x41, x61, x73, x99, x109, x126, x146, x161, b => True
  | n + 1, x13, x26, x41, x61, x73, x99, x109, x126, x146, x161, b => (if (decide (x13 = 0)) = true then True else (match x161 with | some x335 => ((Pre_bind_arg n (x13 - 1) x26 x41 x61 x73 x99 x335 x146 b) ∧ (∀ b1 : Nat, (Cost_bind_arg n (x13 - 1) x26 x41 x61 x73 x99 x335 x146) < b → b1 = b - (Cost_bind_arg n (x13 - 1) x26 x41 x61 x73 x99 x335 x146) → (Pre_eff_args_bound n (x13 - 1) x26 x41 x61 x73 x109 ([] : List Lanius.Mini.MEff) x126 (Lanius.Mini.bindArg ((x13 - 1)) x26 x41 x61 x73 x99 x335 x146) b1))) | none => True))
termination_by structural fuel => fuel
end

end

noncomputable section

mutual
def Cost_contracts_of : Nat → Nat → Lanius.Mini.FrontEnv → List Lanius.Mini.Local → Lanius.Mini.CTree → Option Lanius.Mini.MStmt → Nat
  | 0, x13, x26, x41, x61, x71 => 18446744073709551616
  | n + 1, x13, x26, x41, x61, x71 => (if (decide (x13 = 0)) = true then 0 else (if (decide ((Lanius.Mini.nodeProd x61) = Lanius.Mini.Inline.pContractsNone)) = true then 0 else (let k2 := ((Cost_eff_of n x13 x26 x41 (some Lanius.Mini.Ty.tyBool) (Lanius.Mini.kid ((Lanius.Mini.kid x61 0)) 2)) + ((Cost_contracts_of n (x13 - 1) x26 x41 (Lanius.Mini.kid x61 1) x71) + (Cost_contract_then n (Lanius.Mini.effOf x13 x26 x41 ((some Lanius.Mini.Ty.tyBool)) ((Lanius.Mini.kid ((Lanius.Mini.kid x61 0)) 2))) (Lanius.Mini.contractsOf ((x13 - 1)) x26 x41 ((Lanius.Mini.kid x61 1)) x71)))); let k3 := 0; (if (decide ((Lanius.Mini.nodeProd x61) = Lanius.Mini.Inline.pContractsMore)) = true then (if (decide ((Lanius.Mini.nodeProd ((Lanius.Mini.kid x61 0))) = Lanius.Mini.Inline.pRequires)) = true then k2 else k3) else k3))))
termination_by structural fuel => fuel
end

end
noncomputable section

mutual
def Pre_contracts_of : Nat → Nat → Lanius.Mini.FrontEnv → List Lanius.Mini.Local → Lanius.Mini.CTree → Option Lanius.Mini.MStmt → Nat → Prop
  | 0, x13, x26, x41, x61, x71, b => True
  | n + 1, x13, x26, x41, x61, x71, b => (if (decide (x13 = 0)) = true then True else (if (decide ((Lanius.Mini.nodeProd x61) = Lanius.Mini.Inline.pContractsNone)) = true then True else (let k5 := fun (b1 : Nat) => ((Pre_eff_of n x13 x26 x41 (some Lanius.Mini.Ty.tyBool) (Lanius.Mini.kid ((Lanius.Mini.kid x61 0)) 2) b1) ∧ (∀ b2 : Nat, (Cost_eff_of n x13 x26 x41 (some Lanius.Mini.Ty.tyBool) (Lanius.Mini.kid ((Lanius.Mini.kid x61 0)) 2)) < b1 → b2 = b1 - (Cost_eff_of n x13 x26 x41 (some Lanius.Mini.Ty.tyBool) (Lanius.Mini.kid ((Lanius.Mini.kid x61 0)) 2)) → (Pre_contracts_of n (x13 - 1) x26 x41 (Lanius.Mini.kid x61 1) x71 b2))); let k6 := fun (b1 : Nat) => True; (if (decide ((Lanius.Mini.nodeProd x61) = Lanius.Mini.Inline.pContractsMore)) = true then (if (decide ((Lanius.Mini.nodeProd ((Lanius.Mini.kid x61 0))) = Lanius.Mini.Inline.pRequires)) = true then (k5 b) else (k6 b)) else (k6 b)))))
termination_by structural fuel => fuel
end

end

noncomputable section

def Cost_is_str_type : Nat → Nat → Lanius.Mini.CTree → Nat
  | 0, x12, x25 => 18446744073709551616
  | n + 1, x12, x25 => (if (decide ((Lanius.Mini.nodeProd x25) = Lanius.Mini.Inline.pTypeIdent)) = true then (if (decide ((Lanius.Mini.nodeProd ((Lanius.Mini.kid x25 1))) = Lanius.Mini.Inline.pTypeArgsNone)) = true then ((Cost_type_path_spellings n x12 (Lanius.Mini.kid ((Lanius.Mini.kid x25 0)) 0) (Lanius.Mini.kid ((Lanius.Mini.kid x25 0)) 1)) + ((Cost_text_str n ) + (Cost_single_of_mini_selfhost_List_usize n Lanius.Mini.textStr))) else 0) else 0)

end

noncomputable section

def Cost_is_str_let : Nat → Nat → Lanius.Mini.FrontEnv → List Lanius.Mini.Local → Lanius.Mini.CTree → Nat
  | 0, x11, x24, x39, x59 => 18446744073709551616
  | n + 1, x11, x24, x39, x59 => (if (decide ((Lanius.Mini.nodeProd ((Lanius.Mini.kid x59 2))) = Lanius.Mini.Inline.pLetType)) = true then (if (decide ((Lanius.Mini.nodeProd ((Lanius.Mini.kid x59 3))) = Lanius.Mini.Inline.pLetInit)) = true then (if (!(Lanius.Mini.member x24.globals (((Lanius.Mini.kidToken x59 1).text)))) = true then (if (Lanius.Mini.freshId x39 ((((Lanius.Mini.kidToken x59 1).start) - x24.base))) = true then (Cost_is_str_type n x11 (Lanius.Mini.kid ((Lanius.Mini.kid x59 2)) 1)) else 0) else 0) else 0) else 0)

end

noncomputable section

def Cost_string_last : Nat → Nat → Lanius.Mini.FrontEnv → Nat → List Nat → List Nat → List Lanius.Mini.CTree → Nat
  | 0, x12, x25, x40, x51, x70, x90 => 18446744073709551616
  | n + 1, x12, x25, x40, x51, x70, x90 => (match x90 with | [] => 0 | x202 :: x205 => (match x205 with | [] => (Cost_string_return n x12 x25 x40 x51 x70 x202) | x318 :: x321 => 0))

end
noncomputable section

def Pre_string_last : Nat → Nat → Lanius.Mini.FrontEnv → Nat → List Nat → List Nat → List Lanius.Mini.CTree → Nat → Prop
  | 0, x12, x25, x40, x51, x70, x90, b => True
  | n + 1, x12, x25, x40, x51, x70, x90, b => (match x90 with | [] => True | x202 :: x205 => (match x205 with | [] => (Pre_string_return n x12 x25 x40 x51 x70 x202 b) | x318 :: x321 => True))

end

noncomputable section

def Cost_string_let : Nat → Nat → Lanius.Mini.FrontEnv → Nat → List Nat → Lanius.Mini.CTree → List Lanius.Mini.CTree → Nat
  | 0, x11, x24, x39, x50, x69, x82 => 18446744073709551616
  | n + 1, x11, x24, x39, x50, x69, x82 => ((Cost_string_init n x11 x69) + (match (Lanius.Mini.stringInit x11 x69) with | some x214 => (Cost_string_last n x11 x24 x39 x50 x214 x82) | none => 0))

end
noncomputable section

def Pre_string_let : Nat → Nat → Lanius.Mini.FrontEnv → Nat → List Nat → Lanius.Mini.CTree → List Lanius.Mini.CTree → Nat → Prop
  | 0, x11, x24, x39, x50, x69, x82, b => True
  | n + 1, x11, x24, x39, x50, x69, x82, b => (∀ b1 : Nat, (Cost_string_init n x11 x69) < b → b1 = b - (Cost_string_init n x11 x69) → (match (Lanius.Mini.stringInit x11 x69) with | some x214 => (Pre_string_last n x11 x24 x39 x50 x214 x82 b1) | none => True))

end

noncomputable section

def Cost_lit_wanted : Nat → Nat → Lanius.Mini.FrontEnv → List Lanius.Mini.Local → Lanius.Mini.CTree → Nat
  | 0, x11, x24, x39, x59 => 18446744073709551616
  | n + 1, x11, x24, x39, x59 => (Cost_list_items n x11 (Lanius.Mini.kid x59 5))

end

noncomputable section

def Cost_is_lit_init : Nat → Nat → Lanius.Mini.FrontEnv → List Lanius.Mini.Local → Lanius.Mini.CTree → Nat
  | 0, x12, x25, x40, x60 => 18446744073709551616
  | n + 1, x12, x25, x40, x60 => (match (Lanius.Mini.matchInit x12 x60) with | some x163 => (if (Lanius.Mini.litFirst x163) = true then (Cost_lit_wanted n x12 x25 x40 x163) else 0) | none => 0)

end

noncomputable section

def Cost_lit_match_parts : Nat → Nat → Lanius.Mini.FrontEnv → List Lanius.Mini.Local → Lanius.Mini.CTree → Nat
  | 0, x16, x29, x44, x64 => 18446744073709551616
  | n + 1, x16, x29, x44, x64 => ((Cost_eff_of n x16 x29 x44 (none : Option Lanius.Mini.Ty) (Lanius.Mini.kid x64 2)) + (match (Lanius.Mini.effOf x16 x29 x44 ((none : Option Lanius.Mini.Ty)) ((Lanius.Mini.kid x64 2))) with | some x208 => (Cost_eff_ty n x16 x29 x44 x208) | none => 0))

end
noncomputable section

def Pre_lit_match_parts : Nat → Nat → Lanius.Mini.FrontEnv → List Lanius.Mini.Local → Lanius.Mini.CTree → Nat → Prop
  | 0, x16, x29, x44, x64, b => True
  | n + 1, x16, x29, x44, x64, b => ((Pre_eff_of n x16 x29 x44 (none : Option Lanius.Mini.Ty) (Lanius.Mini.kid x64 2) b) ∧ (∀ b1 : Nat, (Cost_eff_of n x16 x29 x44 (none : Option Lanius.Mini.Ty) (Lanius.Mini.kid x64 2)) < b → b1 = b - (Cost_eff_of n x16 x29 x44 (none : Option Lanius.Mini.Ty) (Lanius.Mini.kid x64 2)) → (match (Lanius.Mini.effOf x16 x29 x44 ((none : Option Lanius.Mini.Ty)) ((Lanius.Mini.kid x64 2))) with | some x208 => (Pre_eff_ty n x16 x29 x44 x208 b1) | none => True)))

end

noncomputable section

def Cost_lit_bind : Nat → Lanius.Mini.LitMatch → Option Lanius.Mini.MStmt → Nat
  | 0, x9, x22 => 18446744073709551616
  | n + 1, x9, x22 => (match x22 with | some x153 => (match x9.value with | some x223 => 1 | none => 0) | none => 0)

end

noncomputable section

def Cost_tried_of : Nat → Nat → Lanius.Mini.FrontEnv → Nat → Option Lanius.Mini.MEff → Option Lanius.Mini.Ty → Nat → Nat
  | 0, x9, x22, x37, x47, x81, x112 => 18446744073709551616
  | n + 1, x9, x22, x37, x47, x81, x112 => (match x81 with | some x215 => (match (Lanius.Mini.namedParts x215) with | some x291 => (match x22.ret with | some x366 => (match (Lanius.Mini.namedParts x366) with | some x458 => (match (x22.decls.types[x291.decl]?) with | some x570 => (if (decide (x291.decl = x458.decl)) = true then ((Cost_is_try_enum n x570) + ((Cost_payload_tys n x9 x22.decls x291.decl x291.args) + (Cost_payload_tys n x9 x22.decls x458.decl x458.args))) else ((Cost_payload_tys n x9 x22.decls x291.decl x291.args) + (Cost_payload_tys n x9 x22.decls x458.decl x458.args))) | none => 0) | none => 0) | none => 0) | none => 0) | none => 0)

end
noncomputable section

def Pre_tried_of : Nat → Nat → Lanius.Mini.FrontEnv → Nat → Option Lanius.Mini.MEff → Option Lanius.Mini.Ty → Nat → Nat → Prop
  | 0, x9, x22, x37, x47, x81, x112, b => True
  | n + 1, x9, x22, x37, x47, x81, x112, b => (match x81 with | some x215 => (match (Lanius.Mini.namedParts x215) with | some x291 => (match x22.ret with | some x366 => (match (Lanius.Mini.namedParts x366) with | some x458 => (match (x22.decls.types[x291.decl]?) with | some x570 => (if (decide (x291.decl = x458.decl)) = true then (∀ b3 : Nat, (Cost_is_try_enum n x570) < b → b3 = b - (Cost_is_try_enum n x570) → ((Pre_payload_tys n x9 x22.decls x291.decl x291.args b3) ∧ (∀ b4 : Nat, (Cost_payload_tys n x9 x22.decls x291.decl x291.args) < b3 → b4 = b3 - (Cost_payload_tys n x9 x22.decls x291.decl x291.args) → (Pre_payload_tys n x9 x22.decls x458.decl x458.args b4)))) else ((Pre_payload_tys n x9 x22.decls x291.decl x291.args b) ∧ (∀ b1 : Nat, (Cost_payload_tys n x9 x22.decls x291.decl x291.args) < b → b1 = b - (Cost_payload_tys n x9 x22.decls x291.decl x291.args) → (Pre_payload_tys n x9 x22.decls x458.decl x458.args b1)))) | none => True) | none => True) | none => True) | none => True) | none => True)

end

noncomputable section

def Cost_tried_call : Nat → Nat → Lanius.Mini.FrontEnv → List Lanius.Mini.Local → Nat → Nat → Option Lanius.Mini.MEff → Nat
  | 0, x11, x24, x39, x59, x69, x79 => 18446744073709551616
  | n + 1, x11, x24, x39, x59, x69, x79 => (match x79 with | some x201 => ((Cost_eff_ty n x11 x24 x39 x201) + (Cost_tried_of n x11 x24 x59 (some x201) (Lanius.Mini.effTy x11 x24 x39 x201) x69)) | none => 0)

end
noncomputable section

def Pre_tried_call : Nat → Nat → Lanius.Mini.FrontEnv → List Lanius.Mini.Local → Nat → Nat → Option Lanius.Mini.MEff → Nat → Prop
  | 0, x11, x24, x39, x59, x69, x79, b => True
  | n + 1, x11, x24, x39, x59, x69, x79, b => (match x79 with | some x201 => ((Pre_eff_ty n x11 x24 x39 x201 b) ∧ (∀ b1 : Nat, (Cost_eff_ty n x11 x24 x39 x201) < b → b1 = b - (Cost_eff_ty n x11 x24 x39 x201) → (Pre_tried_of n x11 x24 x59 (some x201) (Lanius.Mini.effTy x11 x24 x39 x201) x69 b1))) | none => True)

end

noncomputable section

def Cost_try_call_of : Nat → Nat → Lanius.Mini.FrontEnv → List Lanius.Mini.Local → Lanius.Mini.CTree → Nat
  | 0, x12, x25, x40, x60 => 18446744073709551616
  | n + 1, x12, x25, x40, x60 => (let k2 := ((Cost_eff_path_call n x12 x25 x40 (none : Option Lanius.Mini.Ty) (Lanius.Mini.kid ((Lanius.Mini.kid x60 0)) 0) (Lanius.Mini.kid ((Lanius.Mini.kid x60 1)) 1)) + (Cost_tried_call n x12 x25 x40 ((((Lanius.Mini.kidToken ((Lanius.Mini.kid x60 1)) 0)).start) - x25.base) ((((Lanius.Mini.kidToken ((Lanius.Mini.kid ((Lanius.Mini.kid x60 1)) 3)) 0)).start) - x25.base) (Lanius.Mini.effPathCall x12 x25 x40 ((none : Option Lanius.Mini.Ty)) ((Lanius.Mini.kid ((Lanius.Mini.kid x60 0)) 0)) ((Lanius.Mini.kid ((Lanius.Mini.kid x60 1)) 1))))); let k3 := 0; (if (Lanius.Mini.freshId x40 (((((Lanius.Mini.kidToken ((Lanius.Mini.kid x60 1)) 0)).start) - x25.base))) = true then (if ((Lanius.Mini.freshId x40 (((((Lanius.Mini.kidToken ((Lanius.Mini.kid ((Lanius.Mini.kid x60 1)) 3)) 0)).start) - x25.base))) && (!decide (((((Lanius.Mini.kidToken ((Lanius.Mini.kid x60 1)) 0)).start) - x25.base) = ((((Lanius.Mini.kidToken ((Lanius.Mini.kid ((Lanius.Mini.kid x60 1)) 3)) 0)).start) - x25.base)))) = true then k2 else k3) else (if (false && (!decide (((((Lanius.Mini.kidToken ((Lanius.Mini.kid x60 1)) 0)).start) - x25.base) = ((((Lanius.Mini.kidToken ((Lanius.Mini.kid ((Lanius.Mini.kid x60 1)) 3)) 0)).start) - x25.base)))) = true then k2 else k3)))

end
noncomputable section

def Pre_try_call_of : Nat → Nat → Lanius.Mini.FrontEnv → List Lanius.Mini.Local → Lanius.Mini.CTree → Nat → Prop
  | 0, x12, x25, x40, x60, b => True
  | n + 1, x12, x25, x40, x60, b => (let k4 := fun (b1 : Nat) => ((Pre_eff_path_call n x12 x25 x40 (none : Option Lanius.Mini.Ty) (Lanius.Mini.kid ((Lanius.Mini.kid x60 0)) 0) (Lanius.Mini.kid ((Lanius.Mini.kid x60 1)) 1) b1) ∧ (∀ b2 : Nat, (Cost_eff_path_call n x12 x25 x40 (none : Option Lanius.Mini.Ty) (Lanius.Mini.kid ((Lanius.Mini.kid x60 0)) 0) (Lanius.Mini.kid ((Lanius.Mini.kid x60 1)) 1)) < b1 → b2 = b1 - (Cost_eff_path_call n x12 x25 x40 (none : Option Lanius.Mini.Ty) (Lanius.Mini.kid ((Lanius.Mini.kid x60 0)) 0) (Lanius.Mini.kid ((Lanius.Mini.kid x60 1)) 1)) → (Pre_tried_call n x12 x25 x40 ((((Lanius.Mini.kidToken ((Lanius.Mini.kid x60 1)) 0)).start) - x25.base) ((((Lanius.Mini.kidToken ((Lanius.Mini.kid ((Lanius.Mini.kid x60 1)) 3)) 0)).start) - x25.base) (Lanius.Mini.effPathCall x12 x25 x40 ((none : Option Lanius.Mini.Ty)) ((Lanius.Mini.kid ((Lanius.Mini.kid x60 0)) 0)) ((Lanius.Mini.kid ((Lanius.Mini.kid x60 1)) 1))) b2))); let k5 := fun (b1 : Nat) => True; (if (Lanius.Mini.freshId x40 (((((Lanius.Mini.kidToken ((Lanius.Mini.kid x60 1)) 0)).start) - x25.base))) = true then (if ((Lanius.Mini.freshId x40 (((((Lanius.Mini.kidToken ((Lanius.Mini.kid ((Lanius.Mini.kid x60 1)) 3)) 0)).start) - x25.base))) && (!decide (((((Lanius.Mini.kidToken ((Lanius.Mini.kid x60 1)) 0)).start) - x25.base) = ((((Lanius.Mini.kidToken ((Lanius.Mini.kid ((Lanius.Mini.kid x60 1)) 3)) 0)).start) - x25.base)))) = true then (k4 b) else (k5 b)) else (if (false && (!decide (((((Lanius.Mini.kidToken ((Lanius.Mini.kid x60 1)) 0)).start) - x25.base) = ((((Lanius.Mini.kidToken ((Lanius.Mini.kid ((Lanius.Mini.kid x60 1)) 3)) 0)).start) - x25.base)))) = true then (k4 b) else (k5 b))))

end

noncomputable section

def Cost_try_method_of : Nat → Nat → Lanius.Mini.FrontEnv → List Lanius.Mini.Local → Lanius.Mini.CTree → Nat
  | 0, x14, x27, x42, x62 => 18446744073709551616
  | n + 1, x14, x27, x42, x62 => (let k2 := ((Cost_eff_method n x14 x27 x42 (none : Option Lanius.Mini.Ty) x62) + (Cost_tried_call n x14 x27 x42 ((((Lanius.Mini.kidToken ((Lanius.Mini.kid ((Lanius.Mini.kid x62 1)) 3)) 0)).start) - x27.base) ((((Lanius.Mini.kidToken ((Lanius.Mini.kid ((Lanius.Mini.kid ((Lanius.Mini.kid x62 1)) 3)) 3)) 0)).start) - x27.base) (Lanius.Mini.effMethod x14 x27 x42 ((none : Option Lanius.Mini.Ty)) x62))); let k3 := 0; (if (Lanius.Mini.freshId x42 (((((Lanius.Mini.kidToken ((Lanius.Mini.kid ((Lanius.Mini.kid x62 1)) 3)) 0)).start) - x27.base))) = true then (if ((Lanius.Mini.freshId x42 (((((Lanius.Mini.kidToken ((Lanius.Mini.kid ((Lanius.Mini.kid ((Lanius.Mini.kid x62 1)) 3)) 3)) 0)).start) - x27.base))) && (!decide (((((Lanius.Mini.kidToken ((Lanius.Mini.kid ((Lanius.Mini.kid x62 1)) 3)) 0)).start) - x27.base) = ((((Lanius.Mini.kidToken ((Lanius.Mini.kid ((Lanius.Mini.kid ((Lanius.Mini.kid x62 1)) 3)) 3)) 0)).start) - x27.base)))) = true then k2 else k3) else (if (false && (!decide (((((Lanius.Mini.kidToken ((Lanius.Mini.kid ((Lanius.Mini.kid x62 1)) 3)) 0)).start) - x27.base) = ((((Lanius.Mini.kidToken ((Lanius.Mini.kid ((Lanius.Mini.kid ((Lanius.Mini.kid x62 1)) 3)) 3)) 0)).start) - x27.base)))) = true then k2 else k3)))

end
noncomputable section

def Pre_try_method_of : Nat → Nat → Lanius.Mini.FrontEnv → List Lanius.Mini.Local → Lanius.Mini.CTree → Nat → Prop
  | 0, x14, x27, x42, x62, b => True
  | n + 1, x14, x27, x42, x62, b => (let k4 := fun (b1 : Nat) => ((Pre_eff_method n x14 x27 x42 (none : Option Lanius.Mini.Ty) x62 b1) ∧ (∀ b2 : Nat, (Cost_eff_method n x14 x27 x42 (none : Option Lanius.Mini.Ty) x62) < b1 → b2 = b1 - (Cost_eff_method n x14 x27 x42 (none : Option Lanius.Mini.Ty) x62) → (Pre_tried_call n x14 x27 x42 ((((Lanius.Mini.kidToken ((Lanius.Mini.kid ((Lanius.Mini.kid x62 1)) 3)) 0)).start) - x27.base) ((((Lanius.Mini.kidToken ((Lanius.Mini.kid ((Lanius.Mini.kid ((Lanius.Mini.kid x62 1)) 3)) 3)) 0)).start) - x27.base) (Lanius.Mini.effMethod x14 x27 x42 ((none : Option Lanius.Mini.Ty)) x62) b2))); let k5 := fun (b1 : Nat) => True; (if (Lanius.Mini.freshId x42 (((((Lanius.Mini.kidToken ((Lanius.Mini.kid ((Lanius.Mini.kid x62 1)) 3)) 0)).start) - x27.base))) = true then (if ((Lanius.Mini.freshId x42 (((((Lanius.Mini.kidToken ((Lanius.Mini.kid ((Lanius.Mini.kid ((Lanius.Mini.kid x62 1)) 3)) 3)) 0)).start) - x27.base))) && (!decide (((((Lanius.Mini.kidToken ((Lanius.Mini.kid ((Lanius.Mini.kid x62 1)) 3)) 0)).start) - x27.base) = ((((Lanius.Mini.kidToken ((Lanius.Mini.kid ((Lanius.Mini.kid ((Lanius.Mini.kid x62 1)) 3)) 3)) 0)).start) - x27.base)))) = true then (k4 b) else (k5 b)) else (if (false && (!decide (((((Lanius.Mini.kidToken ((Lanius.Mini.kid ((Lanius.Mini.kid x62 1)) 3)) 0)).start) - x27.base) = ((((Lanius.Mini.kidToken ((Lanius.Mini.kid ((Lanius.Mini.kid ((Lanius.Mini.kid x62 1)) 3)) 3)) 0)).start) - x27.base)))) = true then (k4 b) else (k5 b))))

end

noncomputable section

def Cost_tried_local : Nat → Nat → Lanius.Mini.FrontEnv → Option Lanius.Mini.Local → Nat → Nat
  | 0, x12, x25, x40, x72 => 18446744073709551616
  | n + 1, x12, x25, x40, x72 => (match x40 with | some x173 => (Cost_tried_of n x12 x25 x173.id (none : Option Lanius.Mini.MEff) (some x173.ty) x72) | none => 0)

end
noncomputable section

def Pre_tried_local : Nat → Nat → Lanius.Mini.FrontEnv → Option Lanius.Mini.Local → Nat → Nat → Prop
  | 0, x12, x25, x40, x72, b => True
  | n + 1, x12, x25, x40, x72, b => (match x40 with | some x173 => (Pre_tried_of n x12 x25 x173.id (none : Option Lanius.Mini.MEff) (some x173.ty) x72 b) | none => True)

end

noncomputable section

def Cost_try_local_of : Nat → Nat → Lanius.Mini.FrontEnv → List Lanius.Mini.Local → Lanius.Mini.CTree → Nat
  | 0, x13, x26, x41, x61 => 18446744073709551616
  | n + 1, x13, x26, x41, x61 => (if (Lanius.Mini.freshId x41 (((((Lanius.Mini.kidToken ((Lanius.Mini.kid x61 1)) 0)).start) - x26.base))) = true then ((Cost_local_of n x26 x41 (Lanius.Mini.kid x61 0)) + (Cost_tried_local n x13 x26 (Lanius.Mini.localOf x26 x41 ((Lanius.Mini.kid x61 0))) ((((Lanius.Mini.kidToken ((Lanius.Mini.kid x61 1)) 0)).start) - x26.base))) else 0)

end
noncomputable section

def Pre_try_local_of : Nat → Nat → Lanius.Mini.FrontEnv → List Lanius.Mini.Local → Lanius.Mini.CTree → Nat → Prop
  | 0, x13, x26, x41, x61, b => True
  | n + 1, x13, x26, x41, x61, b => (if (Lanius.Mini.freshId x41 (((((Lanius.Mini.kidToken ((Lanius.Mini.kid x61 1)) 0)).start) - x26.base))) = true then (∀ b1 : Nat, (Cost_local_of n x26 x41 (Lanius.Mini.kid x61 0)) < b → b1 = b - (Cost_local_of n x26 x41 (Lanius.Mini.kid x61 0)) → (Pre_tried_local n x13 x26 (Lanius.Mini.localOf x26 x41 ((Lanius.Mini.kid x61 0))) ((((Lanius.Mini.kidToken ((Lanius.Mini.kid x61 1)) 0)).start) - x26.base) b1)) else True)

end

noncomputable section

def Cost_try_postfix : Nat → Nat → Lanius.Mini.FrontEnv → List Lanius.Mini.Local → Lanius.Mini.CTree → Nat
  | 0, x12, x25, x40, x60 => 18446744073709551616
  | n + 1, x12, x25, x40, x60 => (if (Lanius.Mini.isTryCall x60) = true then (Cost_try_call_of n x12 x25 x40 x60) else (if (Lanius.Mini.isTryMethod x60) = true then (Cost_try_method_of n x12 x25 x40 x60) else (if (Lanius.Mini.isTryLocal x60) = true then (Cost_try_local_of n x12 x25 x40 x60) else 0)))

end
noncomputable section

def Pre_try_postfix : Nat → Nat → Lanius.Mini.FrontEnv → List Lanius.Mini.Local → Lanius.Mini.CTree → Nat → Prop
  | 0, x12, x25, x40, x60, b => True
  | n + 1, x12, x25, x40, x60, b => (if (Lanius.Mini.isTryCall x60) = true then (Pre_try_call_of n x12 x25 x40 x60 b) else (if (Lanius.Mini.isTryMethod x60) = true then (Pre_try_method_of n x12 x25 x40 x60 b) else (if (Lanius.Mini.isTryLocal x60) = true then (Pre_try_local_of n x12 x25 x40 x60 b) else True)))

end

noncomputable section

def Cost_try_of_init : Nat → Nat → Lanius.Mini.FrontEnv → List Lanius.Mini.Local → Lanius.Mini.CTree → Nat
  | 0, x12, x25, x40, x60 => 18446744073709551616
  | n + 1, x12, x25, x40, x60 => (match (Lanius.Mini.peel x12 x60) with | some x179 => (Cost_try_postfix n x12 x25 x40 x179) | none => 0)

end
noncomputable section

def Pre_try_of_init : Nat → Nat → Lanius.Mini.FrontEnv → List Lanius.Mini.Local → Lanius.Mini.CTree → Nat → Prop
  | 0, x12, x25, x40, x60, b => True
  | n + 1, x12, x25, x40, x60, b => (match (Lanius.Mini.peel x12 x60) with | some x179 => (Pre_try_postfix n x12 x25 x40 x179 b) | none => True)

end

noncomputable section

def Cost_try_let_head : Nat → Nat → Lanius.Mini.FrontEnv → List Lanius.Mini.Local → Lanius.Mini.CTree → Nat
  | 0, x13, x26, x41, x61 => 18446744073709551616
  | n + 1, x13, x26, x41, x61 => (Cost_try_of_init n x13 x26 x41 x61)

end
noncomputable section

def Pre_try_let_head : Nat → Nat → Lanius.Mini.FrontEnv → List Lanius.Mini.Local → Lanius.Mini.CTree → Nat → Prop
  | 0, x13, x26, x41, x61, b => True
  | n + 1, x13, x26, x41, x61, b => (Pre_try_of_init n x13 x26 x41 x61 b)

end

noncomputable section

def Cost_let_head_or_eval : Nat → Nat → Lanius.Mini.FrontEnv → List Lanius.Mini.Local → Lanius.Mini.Ty → Lanius.Mini.CTree → Nat
  | 0, x17, x30, x45, x65, x73 => 18446744073709551616
  | n + 1, x17, x30, x45, x65, x73 => ((Cost_let_head n x17 x30 x45 x73) + (match (Lanius.Mini.letHead x17 x30 x45 x73) with | some x188 => 0 | none => ((Cost_try_let_head n x17 x30 x45 x73) + (match (Lanius.Mini.tryLetHead x17 x30 x45 x73) with | some x283 => 0 | none => ((Cost_eff_of n x17 x30 x45 (some x65) x73) + (Cost_eval_head n x65 (Lanius.Mini.effOf x17 x30 x45 ((some x65)) x73)))))))

end
noncomputable section

def Pre_let_head_or_eval : Nat → Nat → Lanius.Mini.FrontEnv → List Lanius.Mini.Local → Lanius.Mini.Ty → Lanius.Mini.CTree → Nat → Prop
  | 0, x17, x30, x45, x65, x73, b => True
  | n + 1, x17, x30, x45, x65, x73, b => ((Pre_let_head n x17 x30 x45 x73 b) ∧ (∀ b1 : Nat, (Cost_let_head n x17 x30 x45 x73) < b → b1 = b - (Cost_let_head n x17 x30 x45 x73) → (match (Lanius.Mini.letHead x17 x30 x45 x73) with | some x188 => True | none => ((Pre_try_let_head n x17 x30 x45 x73 b1) ∧ (∀ b2 : Nat, (Cost_try_let_head n x17 x30 x45 x73) < b1 → b2 = b1 - (Cost_try_let_head n x17 x30 x45 x73) → (match (Lanius.Mini.tryLetHead x17 x30 x45 x73) with | some x283 => True | none => (Pre_eff_of n x17 x30 x45 (some x65) x73 b2)))))))

end

noncomputable section

def Cost_alloc_let : Nat → Bool → Nat → Lanius.Mini.SrcExpr → Nat → Lanius.Mini.MStmt → Nat
  | 0, x10, x20, x31, x46, x60 => 18446744073709551616
  | n + 1, x10, x20, x31, x46, x60 => (if x10 = true then 1 else 0)

end

noncomputable section

def Cost_slice_let : Nat → Option Lanius.Mini.Ty → Nat → Lanius.Mini.SrcExpr → Lanius.Mini.SrcExpr → Lanius.Mini.MStmt → Nat
  | 0, x10, x45, x56, x74, x91 => 18446744073709551616
  | n + 1, x10, x45, x56, x74, x91 => (match x10 with | some x201 => 1 | none => 0)

end

noncomputable section

def Cost_try_payload : Nat → Bool → Nat → Nat
  | 0, x12, x25 => 18446744073709551616
  | n + 1, x12, x25 => (if x12 = true then (Cost_single_of_mini_selfhost_MEff n (Lanius.Mini.MEff.xPure (Lanius.Mini.SrcExpr.local x25))) else 0)

end

noncomputable section

def Cost_try_rest : Nat → Lanius.Mini.Tried → Lanius.Mini.MStmt → Nat
  | 0, x9, x19 => 18446744073709551616
  | n + 1, x9, x19 => (match x9.call with | some x255 => ((Cost_try_payload n x9.binds x9.binder) + (1 + (1 + (1 + 1)))) | none => ((Cost_try_payload n x9.binds x9.binder) + (1 + (1 + 1))))

end

noncomputable section

def Cost_try_let : Nat → Bool → Nat → Lanius.Mini.Ty → Lanius.Mini.Tried → Lanius.Mini.MStmt → Nat
  | 0, x8, x18, x29, x37, x47 => 18446744073709551616
  | n + 1, x8, x18, x29, x37, x47 => (if x8 = true then (1 + (1 + (Cost_try_rest n x37 (Lanius.Mini.MStmt.mMatchArm x37.scrutinee x37.sty 0 true x18 x29 x47 (Lanius.Mini.MStmt.mUnreachable x37.binder x37.ret))))) else 0)

end

noncomputable section

def Cost_let_stmt : Nat → Nat → Lanius.Mini.Ty → Lanius.Mini.LetHead → Lanius.Mini.MStmt → Nat
  | 0, x9, x20, x28, x43 => 18446744073709551616
  | n + 1, x9, x20, x28, x43 => (match x28 with | .plain x129 => 1 | .callOf x186 => 1 | .variantOf x263 x272 => 1 | .literalOf x357 => 1 | .matchOf x431 x442 x447 => 1 | .allocOf x532 x538 => (Cost_alloc_let n (Lanius.Mini.isPtrTy x20) x9 x532 x538 x43) | .sliceOf x613 x622 => (Cost_slice_let n (Lanius.Mini.sliceElem x20) x9 x613 x622 x43) | .viewOf x702 => 0 | .indexOf x734 x741 => 1 | .evalOf x818 => 1 | .tryOf x878 => (Cost_try_let n (Lanius.Mini.sameTy x20 x878.okTy) x9 x20 x878 x43))

end

noncomputable section

def Cost_let_body : Nat → Nat → Lanius.Mini.Ty → Lanius.Mini.LetHead → Option Lanius.Mini.MStmt → Nat
  | 0, x9, x20, x28, x40 => 18446744073709551616
  | n + 1, x9, x20, x28, x40 => (match x40 with | some x169 => (Cost_let_stmt n x9 x20 x28 x169) | none => 0)

end

noncomputable section

def Cost_let_of : Nat → Nat → Lanius.Mini.Ty → Option Lanius.Mini.LetHead → Option Lanius.Mini.MStmt → Nat
  | 0, x7, x18, x26, x63 => 18446744073709551616
  | n + 1, x7, x18, x26, x63 => (match x26 with | some x192 => (Cost_let_body n x7 x18 x192 x63) | none => 0)

end

noncomputable section

def Cost_slice_returned : Nat → Nat → Lanius.Mini.Ty → Option Lanius.Mini.LetHead → Nat
  | 0, x15, x26, x34 => 18446744073709551616
  | n + 1, x15, x26, x34 => (match x34 with | some x159 => (match x159 with | .plain x201 => 0 | .callOf x232 => 0 | .variantOf x266 x275 => 0 | .literalOf x315 => 0 | .matchOf x352 x363 x368 => 0 | .allocOf x403 x409 => 0 | .sliceOf x445 x454 => 1 | .viewOf x553 => 0 | .indexOf x589 x596 => 0 | .evalOf x631 => 0 | .tryOf x661 => 0) | none => 0)

end

noncomputable section

def Cost_return_slice : Nat → Nat → Lanius.Mini.FrontEnv → List Lanius.Mini.Local → Lanius.Mini.CTree → Nat
  | 0, x13, x26, x41, x61 => 18446744073709551616
  | n + 1, x13, x26, x41, x61 => (match x26.ret with | some x168 => (match (Lanius.Mini.sliceElem x168) with | some x241 => ((Cost_tree_tokens n x61) + (match (Lanius.Mini.treeTokens x61) with | [] => 0 | x323 :: x330 => ((Cost_let_head n x13 x26 x41 x61) + (Cost_slice_returned n (x323.start - x26.base) x241 (Lanius.Mini.letHead x13 x26 x41 x61))))) | none => 0) | none => 0)

end
noncomputable section

def Pre_return_slice : Nat → Nat → Lanius.Mini.FrontEnv → List Lanius.Mini.Local → Lanius.Mini.CTree → Nat → Prop
  | 0, x13, x26, x41, x61, b => True
  | n + 1, x13, x26, x41, x61, b => (match x26.ret with | some x168 => (match (Lanius.Mini.sliceElem x168) with | some x241 => (∀ b1 : Nat, (Cost_tree_tokens n x61) < b → b1 = b - (Cost_tree_tokens n x61) → (match (Lanius.Mini.treeTokens x61) with | [] => True | x323 :: x330 => (Pre_let_head n x13 x26 x41 x61 b1))) | none => True) | none => True)

end

noncomputable section

def Cost_return_or_eval : Nat → Nat → Lanius.Mini.FrontEnv → List Lanius.Mini.Local → Lanius.Mini.CTree → Nat
  | 0, x15, x28, x43, x63 => 18446744073709551616
  | n + 1, x15, x28, x43, x63 => ((Cost_return_slice n x15 x28 x43 x63) + (match (Lanius.Mini.returnSlice x15 x28 x43 x63) with | some x174 => 0 | none => (Cost_eff_of n x15 x28 x43 x28.ret x63)))

end
noncomputable section

def Pre_return_or_eval : Nat → Nat → Lanius.Mini.FrontEnv → List Lanius.Mini.Local → Lanius.Mini.CTree → Nat → Prop
  | 0, x15, x28, x43, x63, b => True
  | n + 1, x15, x28, x43, x63, b => ((Pre_return_slice n x15 x28 x43 x63 b) ∧ (∀ b1 : Nat, (Cost_return_slice n x15 x28 x43 x63) < b → b1 = b - (Cost_return_slice n x15 x28 x43 x63) → (match (Lanius.Mini.returnSlice x15 x28 x43 x63) with | some x174 => True | none => (Pre_eff_of n x15 x28 x43 x28.ret x63 b1))))

end

noncomputable section

def Cost_lit_if : Nat → Option Lanius.Mini.SrcExpr → Option Lanius.Mini.MStmt → Option Lanius.Mini.MStmt → Nat
  | 0, x7, x41, x76 => 18446744073709551616
  | n + 1, x7, x41, x76 => (match x7 with | some x202 => (match x41 with | some x266 => (match x76 with | some x338 => (1 + 1) | none => 0) | none => 0) | none => 0)

end

noncomputable section

def Cost_eq_lit : Nat → Nat → Option Lanius.Mini.SrcExpr → Nat
  | 0, x7, x18 => 18446744073709551616
  | n + 1, x7, x18 => (match x18 with | some x145 => (1 + 1) | none => 0)

end

noncomputable section

def Cost_lit_cond : Nat → Nat → Lanius.Mini.Ty → Lanius.Mini.CTree → Nat
  | 0, x9, x20, x29 => 18446744073709551616
  | n + 1, x9, x20, x29 => (if ((decide ((Lanius.Mini.nodeProd x29) = Lanius.Mini.Inline.pPatternInt)) && (!(Lanius.Mini.sameTy x20 Lanius.Mini.Ty.tyBool))) = true then ((Cost_int_literal n (((Lanius.Mini.kidToken x29 0)).text)) + (Cost_eq_lit n x9 (Lanius.Mini.intLiteral ((((Lanius.Mini.kidToken x29 0)).text))))) else (if ((decide ((Lanius.Mini.nodeProd x29) = Lanius.Mini.Inline.pPatternTrue)) && (Lanius.Mini.sameTy x20 Lanius.Mini.Ty.tyBool)) = true then 0 else (if ((decide ((Lanius.Mini.nodeProd x29) = Lanius.Mini.Inline.pPatternFalse)) && (Lanius.Mini.sameTy x20 Lanius.Mini.Ty.tyBool)) = true then 1 else 0)))

end
noncomputable section

def Pre_lit_cond : Nat → Nat → Lanius.Mini.Ty → Lanius.Mini.CTree → Nat → Prop
  | 0, x9, x20, x29, b => True
  | n + 1, x9, x20, x29, b => (if ((decide ((Lanius.Mini.nodeProd x29) = Lanius.Mini.Inline.pPatternInt)) && (!(Lanius.Mini.sameTy x20 Lanius.Mini.Ty.tyBool))) = true then (Pre_int_literal n (((Lanius.Mini.kidToken x29 0)).text) b) else True)

end

noncomputable section

mutual
def Pre_value_arms : Nat → Nat → List Lanius.Mini.CTree → Nat → Prop
  | 0, x11, x24, b => True
  | n + 1, x11, x24, b => (match x24 with | [] => True | x111 :: x114 => ((Pre_value_arms n x11 x114 b) ∧ (Pre_plus n (Lanius.Mini.ifOne ((!(Lanius.Mini.isBlockArm x11 x111)))) (Lanius.Mini.valueArms x11 x114) b)))
termination_by structural fuel => fuel
end

end

noncomputable section

def Pre_block_arms_of : Nat → Nat → Option (List Lanius.Mini.CTree) → Nat → Prop
  | 0, x14, x27, b => True
  | n + 1, x14, x27, b => (match x27 with | some x142 => (if (Lanius.Mini.someBlockArm x14 x142) = true then (Pre_value_arms n x14 x142 b) else True) | none => True)

end

noncomputable section

def Cost_is_block_match : Nat → Nat → Lanius.Mini.CTree → Nat
  | 0, x15, x28 => 18446744073709551616
  | n + 1, x15, x28 => (match (Lanius.Mini.matchInit x15 x28) with | some x131 => (Cost_list_items n x15 (Lanius.Mini.kid x131 5)) | none => 0)

end
noncomputable section

def Pre_is_block_match : Nat → Nat → Lanius.Mini.CTree → Nat → Prop
  | 0, x15, x28, b => True
  | n + 1, x15, x28, b => (match (Lanius.Mini.matchInit x15 x28) with | some x131 => (∀ b1 : Nat, (Cost_list_items n x15 (Lanius.Mini.kid x131 5)) < b → b1 = b - (Cost_list_items n x15 (Lanius.Mini.kid x131 5)) → (Pre_block_arms_of n x15 (Lanius.Mini.listItems x15 ((Lanius.Mini.kid x131 5))) b1)) | none => True)

end

noncomputable section

def Cost_match_stmt_enum : Nat → Lanius.Mini.FrontEnv → List Lanius.Mini.Local → Lanius.Mini.CTree → Lanius.Mini.MEff → Lanius.Mini.Ty → Lanius.Mini.TypeDecl → Option (List (List Lanius.Mini.Ty)) → Nat
  | 0, x16, x31, x51, x61, x70, x79, x92 => 18446744073709551616
  | n + 1, x16, x31, x51, x61, x70, x79, x92 => (if x79.isEnum = true then (match x92 with | some x275 => (match x16.ret with | some x351 => (Cost_zip_variants n x79.variants x275) | none => 0) | none => 0) else 0)

end

noncomputable section

def Cost_match_stmt_on : Nat → Nat → Lanius.Mini.FrontEnv → List Lanius.Mini.Local → Lanius.Mini.CTree → Option Lanius.Mini.MEff → Nat
  | 0, x14, x27, x42, x62, x72 => 18446744073709551616
  | n + 1, x14, x27, x42, x62, x72 => (match x72 with | some x198 => ((Cost_eff_ty n x14 x27 x42 x198) + (match (Lanius.Mini.effTy x14 x27 x42 x198) with | some x285 => (match (Lanius.Mini.namedParts x285) with | some x371 => (match (x27.decls.types[x371.decl]?) with | some x475 => ((Cost_payload_tys n x14 x27.decls x371.decl x371.args) + (Cost_match_stmt_enum n x27 x42 x62 x198 x285 x475 (Lanius.Mini.payloadTys x14 x27.decls x371.decl x371.args))) | none => 0) | none => 0) | none => 0)) | none => 0)

end
noncomputable section

def Pre_match_stmt_on : Nat → Nat → Lanius.Mini.FrontEnv → List Lanius.Mini.Local → Lanius.Mini.CTree → Option Lanius.Mini.MEff → Nat → Prop
  | 0, x14, x27, x42, x62, x72, b => True
  | n + 1, x14, x27, x42, x62, x72, b => (match x72 with | some x198 => ((Pre_eff_ty n x14 x27 x42 x198 b) ∧ (∀ b1 : Nat, (Cost_eff_ty n x14 x27 x42 x198) < b → b1 = b - (Cost_eff_ty n x14 x27 x42 x198) → (match (Lanius.Mini.effTy x14 x27 x42 x198) with | some x285 => (match (Lanius.Mini.namedParts x285) with | some x371 => (match (x27.decls.types[x371.decl]?) with | some x475 => (Pre_payload_tys n x14 x27.decls x371.decl x371.args b1) | none => True) | none => True) | none => True))) | none => True)

end

noncomputable section

def Cost_match_stmt_parts : Nat → Nat → Lanius.Mini.FrontEnv → List Lanius.Mini.Local → Lanius.Mini.CTree → Nat
  | 0, x17, x30, x45, x65 => 18446744073709551616
  | n + 1, x17, x30, x45, x65 => ((Cost_eff_of n x17 x30 x45 (none : Option Lanius.Mini.Ty) (Lanius.Mini.kid x65 2)) + (Cost_match_stmt_on n x17 x30 x45 x65 (Lanius.Mini.effOf x17 x30 x45 ((none : Option Lanius.Mini.Ty)) ((Lanius.Mini.kid x65 2)))))

end
noncomputable section

def Pre_match_stmt_parts : Nat → Nat → Lanius.Mini.FrontEnv → List Lanius.Mini.Local → Lanius.Mini.CTree → Nat → Prop
  | 0, x17, x30, x45, x65, b => True
  | n + 1, x17, x30, x45, x65, b => ((Pre_eff_of n x17 x30 x45 (none : Option Lanius.Mini.Ty) (Lanius.Mini.kid x65 2) b) ∧ (∀ b1 : Nat, (Cost_eff_of n x17 x30 x45 (none : Option Lanius.Mini.Ty) (Lanius.Mini.kid x65 2)) < b → b1 = b - (Cost_eff_of n x17 x30 x45 (none : Option Lanius.Mini.Ty) (Lanius.Mini.kid x65 2)) → (Pre_match_stmt_on n x17 x30 x45 x65 (Lanius.Mini.effOf x17 x30 x45 ((none : Option Lanius.Mini.Ty)) ((Lanius.Mini.kid x65 2))) b1)))

end

noncomputable section

def Cost_stmt_arms : Nat → Nat → Lanius.Mini.FrontEnv → Lanius.Mini.MatchStmt → Lanius.Mini.CTree → Nat
  | 0, x10, x23, x38, x52 => 18446744073709551616
  | n + 1, x10, x23, x38, x52 => ((Cost_list_items n x10 (Lanius.Mini.kid x52 5)) + (match (Lanius.Mini.listItems x10 ((Lanius.Mini.kid x52 5))) with | some x185 => (Cost_stmt_arm_order n x10 x23 x38.owner x38.variants x185) | none => 0))

end
noncomputable section

def Pre_stmt_arms : Nat → Nat → Lanius.Mini.FrontEnv → Lanius.Mini.MatchStmt → Lanius.Mini.CTree → Nat → Prop
  | 0, x10, x23, x38, x52, b => True
  | n + 1, x10, x23, x38, x52, b => (∀ b1 : Nat, (Cost_list_items n x10 (Lanius.Mini.kid x52 5)) < b → b1 = b - (Cost_list_items n x10 (Lanius.Mini.kid x52 5)) → (match (Lanius.Mini.listItems x10 ((Lanius.Mini.kid x52 5))) with | some x185 => (Pre_stmt_arm_order n x10 x23 x38.owner x38.variants x185 b1) | none => True))

end

noncomputable section

def Cost_match_stmt_value : Nat → Lanius.Mini.MatchStmt → Option Lanius.Mini.MStmt → Nat
  | 0, x17, x31 => 18446744073709551616
  | n + 1, x17, x31 => (match x31 with | some x162 => (match x17.value with | some x232 => 1 | none => 0) | none => 0)

end

noncomputable section

def Cost_arm_binding : Nat → Nat → Lanius.Mini.FrontEnv → List Lanius.Mini.Local → Lanius.Mini.TypeDecl → Lanius.Mini.VariantTy → Lanius.Mini.CTree → Nat
  | 0, x12, x25, x40, x60, x77, x91 => 18446744073709551616
  | n + 1, x12, x25, x40, x60, x77, x91 => (let k2 := (if (decide ((Lanius.Mini.nodeProd ((Lanius.Mini.kid ((Lanius.Mini.kid x91 0)) 1))) = Lanius.Mini.Inline.pPatternPlain)) = true then 0 else ((Cost_list_items n x12 (Lanius.Mini.kid ((Lanius.Mini.kid ((Lanius.Mini.kid x91 0)) 1)) 1)) + (match (Lanius.Mini.listItems x12 ((Lanius.Mini.kid ((Lanius.Mini.kid ((Lanius.Mini.kid x91 0)) 1)) 1))) with | some x608 => (Cost_binders_of n x25 x40 x608 x77.payload) | none => 0))); let k3 := 0; (if (decide ((Lanius.Mini.nodeProd ((Lanius.Mini.kid x91 0))) = Lanius.Mini.Inline.pPatternIdent)) = true then ((Cost_path_spellings n x12 (Lanius.Mini.kid ((Lanius.Mini.kid ((Lanius.Mini.kid x91 0)) 0)) 0) (Lanius.Mini.kid ((Lanius.Mini.kid ((Lanius.Mini.kid x91 0)) 0)) 1)) + ((Cost_arm_named n (Lanius.Mini.pathSpellings x12 ((Lanius.Mini.kid ((Lanius.Mini.kid ((Lanius.Mini.kid x91 0)) 0)) 0)) ((Lanius.Mini.kid ((Lanius.Mini.kid ((Lanius.Mini.kid x91 0)) 0)) 1))) x60 x77.name) + (if (Lanius.Mini.armNamed ((Lanius.Mini.pathSpellings x12 ((Lanius.Mini.kid ((Lanius.Mini.kid ((Lanius.Mini.kid x91 0)) 0)) 0)) ((Lanius.Mini.kid ((Lanius.Mini.kid ((Lanius.Mini.kid x91 0)) 0)) 1)))) x60 x77.name) = true then k2 else k3))) else k3))

end

noncomputable section

def Cost_arm_binder : Nat → Lanius.Mini.MatchStmt → Nat → List Nat → List Lanius.Mini.Ty → Lanius.Mini.MStmt → Lanius.Mini.MStmt → Nat
  | 0, x11, x25, x35, x53, x72, x85 => 18446744073709551616
  | n + 1, x11, x25, x35, x53, x72, x85 => (match x35 with | [] => (1 + 1) | x274 :: x277 => (match x277 with | [] => (match x53 with | [] => 0 | x395 :: x398 => (1 + 1)) | x515 :: x518 => 0))

end

noncomputable section

def Cost_arm_stmt : Nat → Lanius.Mini.MatchStmt → Nat → Lanius.Mini.Bound → Lanius.Mini.VariantTy → Option Lanius.Mini.MStmt → Option Lanius.Mini.MStmt → Nat
  | 0, x9, x23, x33, x43, x57, x92 => 18446744073709551616
  | n + 1, x9, x23, x33, x43, x57, x92 => (match x57 with | some x221 => (match x92 with | some x285 => (Cost_arm_binder n x9 x23 x33.ids x43.payload x221 x285) | none => 0) | none => 0)

end

noncomputable section

def Cost_untyped_eval : Nat → Nat → Lanius.Mini.FrontEnv → List Lanius.Mini.Local → Option Lanius.Mini.MEff → Nat
  | 0, x13, x26, x41, x61 => 18446744073709551616
  | n + 1, x13, x26, x41, x61 => (match x61 with | some x185 => ((Cost_eff_ty n x13 x26 x41 x185) + (match (Lanius.Mini.effTy x13 x26 x41 x185) with | some x272 => (Cost_eval_let_head n x272 x185) | none => 0)) | none => 0)

end
noncomputable section

def Pre_untyped_eval : Nat → Nat → Lanius.Mini.FrontEnv → List Lanius.Mini.Local → Option Lanius.Mini.MEff → Nat → Prop
  | 0, x13, x26, x41, x61, b => True
  | n + 1, x13, x26, x41, x61, b => (match x61 with | some x185 => (Pre_eff_ty n x13 x26 x41 x185 b) | none => True)

end

noncomputable section

def Cost_untyped_head : Nat → Nat → Lanius.Mini.FrontEnv → List Lanius.Mini.Local → Lanius.Mini.CTree → Nat
  | 0, x13, x26, x41, x61 => 18446744073709551616
  | n + 1, x13, x26, x41, x61 => ((Cost_try_of_init n x13 x26 x41 x61) + (match (Lanius.Mini.tryOfInit x13 x26 x41 x61) with | some x179 => 0 | none => ((Cost_eff_of n x13 x26 x41 (none : Option Lanius.Mini.Ty) x61) + (Cost_untyped_eval n x13 x26 x41 (Lanius.Mini.effOf x13 x26 x41 ((none : Option Lanius.Mini.Ty)) x61)))))

end
noncomputable section

def Pre_untyped_head : Nat → Nat → Lanius.Mini.FrontEnv → List Lanius.Mini.Local → Lanius.Mini.CTree → Nat → Prop
  | 0, x13, x26, x41, x61, b => True
  | n + 1, x13, x26, x41, x61, b => ((Pre_try_of_init n x13 x26 x41 x61 b) ∧ (∀ b1 : Nat, (Cost_try_of_init n x13 x26 x41 x61) < b → b1 = b - (Cost_try_of_init n x13 x26 x41 x61) → (match (Lanius.Mini.tryOfInit x13 x26 x41 x61) with | some x179 => True | none => ((Pre_eff_of n x13 x26 x41 (none : Option Lanius.Mini.Ty) x61 b1) ∧ (∀ b2 : Nat, (Cost_eff_of n x13 x26 x41 (none : Option Lanius.Mini.Ty) x61) < b1 → b2 = b1 - (Cost_eff_of n x13 x26 x41 (none : Option Lanius.Mini.Ty) x61) → (Pre_untyped_eval n x13 x26 x41 (Lanius.Mini.effOf x13 x26 x41 ((none : Option Lanius.Mini.Ty)) x61) b2))))))

end

noncomputable section

def Cost_if_eval_of : Nat → Option Lanius.Mini.MEff → Option Lanius.Mini.MStmt → Option Lanius.Mini.MStmt → Nat
  | 0, x11, x42, x74 => 18446744073709551616
  | n + 1, x11, x42, x74 => (match x11 with | some x197 => (match x42 with | some x258 => (match x74 with | some x327 => (Cost_if_eff n x197 x258 x327) | none => 0) | none => 0) | none => 0)

end

noncomputable section

def Cost_if_or_eval : Nat → Nat → Lanius.Mini.FrontEnv → List Lanius.Mini.Local → Lanius.Mini.CTree → Option Lanius.Mini.MStmt → Option Lanius.Mini.MStmt → Nat
  | 0, x11, x24, x39, x59, x69, x101 => 18446744073709551616
  | n + 1, x11, x24, x39, x59, x69, x101 => ((Cost_eff_of n x11 x24 x39 (some Lanius.Mini.Ty.tyBool) x59) + (Cost_if_eval_of n (Lanius.Mini.effOf x11 x24 x39 ((some Lanius.Mini.Ty.tyBool)) x59) x69 x101))

end
noncomputable section

def Pre_if_or_eval : Nat → Nat → Lanius.Mini.FrontEnv → List Lanius.Mini.Local → Lanius.Mini.CTree → Option Lanius.Mini.MStmt → Option Lanius.Mini.MStmt → Nat → Prop
  | 0, x11, x24, x39, x59, x69, x101, b => True
  | n + 1, x11, x24, x39, x59, x69, x101, b => (Pre_eff_of n x11 x24 x39 (some Lanius.Mini.Ty.tyBool) x59 b)

end

noncomputable section

def Cost_while_eval_of : Nat → Option Lanius.Mini.MEff → Option Lanius.Mini.MStmt → Nat
  | 0, x14, x45 => 18446744073709551616
  | n + 1, x14, x45 => (match x14 with | some x171 => (match x45 with | some x235 => (Cost_while_eff n x171 x235) | none => 0) | none => 0)

end

noncomputable section

def Cost_while_or_eval : Nat → Nat → Lanius.Mini.FrontEnv → List Lanius.Mini.Local → Lanius.Mini.CTree → Option Lanius.Mini.MStmt → Nat
  | 0, x14, x27, x42, x62, x72 => 18446744073709551616
  | n + 1, x14, x27, x42, x62, x72 => ((Cost_eff_of n x14 x27 x42 (some Lanius.Mini.Ty.tyBool) x62) + (Cost_while_eval_of n (Lanius.Mini.effOf x14 x27 x42 ((some Lanius.Mini.Ty.tyBool)) x62) x72))

end
noncomputable section

def Pre_while_or_eval : Nat → Nat → Lanius.Mini.FrontEnv → List Lanius.Mini.Local → Lanius.Mini.CTree → Option Lanius.Mini.MStmt → Nat → Prop
  | 0, x14, x27, x42, x62, x72, b => True
  | n + 1, x14, x27, x42, x62, x72, b => (Pre_eff_of n x14 x27 x42 (some Lanius.Mini.Ty.tyBool) x62 b)

end

noncomputable section

def Cost_ref_target : Nat → Lanius.Mini.FrontEnv → List Lanius.Mini.Local → Lanius.Mini.CTree → Nat
  | 0, x11, x26, x46 => 18446744073709551616
  | n + 1, x11, x26, x46 => (if (!decide ((Lanius.Mini.nodeProd ((Lanius.Mini.kid x46 1))) = Lanius.Mini.Inline.pPostfixEnd)) = true then (Cost_local_of n x11 x26 (Lanius.Mini.kid x46 0)) else 0)

end

noncomputable section

def Cost_set_place_of : Nat → Nat → Lanius.Mini.FrontEnv → List Lanius.Mini.Local → Lanius.Mini.CTree → Lanius.Mini.CTree → Nat
  | 0, x13, x26, x41, x61, x76 => 18446744073709551616
  | n + 1, x13, x26, x41, x61, x76 => ((Cost_eff_of n x13 x26 x41 (none : Option Lanius.Mini.Ty) x61) + (match (Lanius.Mini.effOf x13 x26 x41 ((none : Option Lanius.Mini.Ty)) x61) with | some x218 => (if (Lanius.Mini.effPlace x218) = true then ((Cost_eff_ty n x13 x26 x41 x218) + ((Cost_eff_ty n x13 x26 x41 x218) + (Cost_eff_of n x13 x26 x41 (Lanius.Mini.effTy x13 x26 x41 x218) x76))) else ((Cost_eff_ty n x13 x26 x41 x218) + (Cost_eff_of n x13 x26 x41 (Lanius.Mini.effTy x13 x26 x41 x218) x76))) | none => 0))

end
noncomputable section

def Pre_set_place_of : Nat → Nat → Lanius.Mini.FrontEnv → List Lanius.Mini.Local → Lanius.Mini.CTree → Lanius.Mini.CTree → Nat → Prop
  | 0, x13, x26, x41, x61, x76, b => True
  | n + 1, x13, x26, x41, x61, x76, b => ((Pre_eff_of n x13 x26 x41 (none : Option Lanius.Mini.Ty) x61 b) ∧ (∀ b1 : Nat, (Cost_eff_of n x13 x26 x41 (none : Option Lanius.Mini.Ty) x61) < b → b1 = b - (Cost_eff_of n x13 x26 x41 (none : Option Lanius.Mini.Ty) x61) → (match (Lanius.Mini.effOf x13 x26 x41 ((none : Option Lanius.Mini.Ty)) x61) with | some x218 => (if (Lanius.Mini.effPlace x218) = true then ((Pre_eff_ty n x13 x26 x41 x218 b1) ∧ (∀ b4 : Nat, (Cost_eff_ty n x13 x26 x41 x218) < b1 → b4 = b1 - (Cost_eff_ty n x13 x26 x41 x218) → ((Pre_length_of_mini_selfhost_FnDecl n x26.decls.fns b4) ∧ ((Pre_eff_ty n x13 x26 x41 x218 b4) ∧ (∀ b5 : Nat, (Cost_eff_ty n x13 x26 x41 x218) < b4 → b5 = b4 - (Cost_eff_ty n x13 x26 x41 x218) → (Pre_eff_of n x13 x26 x41 (Lanius.Mini.effTy x13 x26 x41 x218) x76 b5)))))) else ((Pre_length_of_mini_selfhost_FnDecl n x26.decls.fns b1) ∧ ((Pre_eff_ty n x13 x26 x41 x218 b1) ∧ (∀ b2 : Nat, (Cost_eff_ty n x13 x26 x41 x218) < b1 → b2 = b1 - (Cost_eff_ty n x13 x26 x41 x218) → (Pre_eff_of n x13 x26 x41 (Lanius.Mini.effTy x13 x26 x41 x218) x76 b2))))) | none => True)))

end

noncomputable section

def Cost_set_eval_of : Nat → Nat → Option Lanius.Mini.MEff → Nat
  | 0, x12, x23 => 18446744073709551616
  | n + 1, x12, x23 => (match x23 with | some x145 => (Cost_call_parts n x145) | none => 0)

end

noncomputable section

def Cost_try_set : Nat → Bool → Nat → Nat → Lanius.Mini.Tried → Nat
  | 0, x8, x18, x29, x39 => 18446744073709551616
  | n + 1, x8, x18, x29, x39 => (if ((x8 && (!decide (x29 = x39.scrutinee))) && (!decide (x29 = x39.binder))) = true then (1 + (1 + (Cost_try_rest n x39 (Lanius.Mini.MStmt.mMatchArm x39.scrutinee x39.sty 0 true x29 x39.okTy (Lanius.Mini.MStmt.mSet x18 (Lanius.Mini.SrcExpr.local x29)) (Lanius.Mini.MStmt.mUnreachable x39.binder x39.ret))))) else 0)

end

noncomputable section

def Cost_set_try_or_eval : Nat → Nat → Lanius.Mini.FrontEnv → List Lanius.Mini.Local → Lanius.Mini.Local → Nat → Option Lanius.Mini.Tried → Lanius.Mini.CTree → Nat
  | 0, x16, x29, x44, x64, x74, x84, x116 => 18446744073709551616
  | n + 1, x16, x29, x44, x64, x74, x84, x116 => (match x84 with | some x199 => (if (Lanius.Mini.sameTy x64.ty x199.okTy) = true then (Cost_try_set n (Lanius.Mini.freshId x44 x74) x64.id x74 x199) else (Cost_try_set n false x64.id x74 x199)) | none => ((Cost_eff_of n x16 x29 x44 (some x64.ty) x116) + (Cost_set_eval_of n x64.id (Lanius.Mini.effOf x16 x29 x44 ((some x64.ty)) x116))))

end
noncomputable section

def Pre_set_try_or_eval : Nat → Nat → Lanius.Mini.FrontEnv → List Lanius.Mini.Local → Lanius.Mini.Local → Nat → Option Lanius.Mini.Tried → Lanius.Mini.CTree → Nat → Prop
  | 0, x16, x29, x44, x64, x74, x84, x116, b => True
  | n + 1, x16, x29, x44, x64, x74, x84, x116, b => (match x84 with | some x199 => True | none => (Pre_eff_of n x16 x29 x44 (some x64.ty) x116 b))

end

noncomputable section

def Cost_set_or_eval : Nat → Nat → Lanius.Mini.FrontEnv → List Lanius.Mini.Local → Lanius.Mini.Local → Nat → Lanius.Mini.CTree → Nat
  | 0, x12, x25, x40, x60, x70, x80 => 18446744073709551616
  | n + 1, x12, x25, x40, x60, x70, x80 => ((Cost_try_of_init n x12 x25 x40 x80) + (Cost_set_try_or_eval n x12 x25 x40 x60 x70 (Lanius.Mini.tryOfInit x12 x25 x40 x80) x80))

end
noncomputable section

def Pre_set_or_eval : Nat → Nat → Lanius.Mini.FrontEnv → List Lanius.Mini.Local → Lanius.Mini.Local → Nat → Lanius.Mini.CTree → Nat → Prop
  | 0, x12, x25, x40, x60, x70, x80, b => True
  | n + 1, x12, x25, x40, x60, x70, x80, b => ((Pre_try_of_init n x12 x25 x40 x80 b) ∧ (∀ b1 : Nat, (Cost_try_of_init n x12 x25 x40 x80) < b → b1 = b - (Cost_try_of_init n x12 x25 x40 x80) → (Pre_set_try_or_eval n x12 x25 x40 x60 x70 (Lanius.Mini.tryOfInit x12 x25 x40 x80) x80 b1)))

end

noncomputable section

def Cost_set_field_or_eval : Nat → Nat → Lanius.Mini.FrontEnv → List Lanius.Mini.Local → Lanius.Mini.Local → List Nat → Lanius.Mini.CTree → Nat
  | 0, x18, x31, x46, x66, x76, x95 => 18446744073709551616
  | n + 1, x18, x31, x46, x66, x76, x95 => (match (Lanius.Mini.fieldIndex x31 x66.ty x76) with | some x227 => ((Cost_field_ty_at n x18 x31.decls x66.ty x227) + ((Cost_field_ty_at n x18 x31.decls x66.ty x227) + (Cost_eff_of n x18 x31 x46 (Lanius.Mini.fieldTyAt x18 x31.decls x66.ty x227) x95))) | none => 0)

end
noncomputable section

def Pre_set_field_or_eval : Nat → Nat → Lanius.Mini.FrontEnv → List Lanius.Mini.Local → Lanius.Mini.Local → List Nat → Lanius.Mini.CTree → Nat → Prop
  | 0, x18, x31, x46, x66, x76, x95, b => True
  | n + 1, x18, x31, x46, x66, x76, x95, b => ((Pre_field_index n x31 x66.ty x76 b) ∧ (match (Lanius.Mini.fieldIndex x31 x66.ty x76) with | some x227 => ((Pre_field_ty_at n x18 x31.decls x66.ty x227 b) ∧ (∀ b1 : Nat, (Cost_field_ty_at n x18 x31.decls x66.ty x227) < b → b1 = b - (Cost_field_ty_at n x18 x31.decls x66.ty x227) → ((Pre_field_ty_at n x18 x31.decls x66.ty x227 b1) ∧ (∀ b2 : Nat, (Cost_field_ty_at n x18 x31.decls x66.ty x227) < b1 → b2 = b1 - (Cost_field_ty_at n x18 x31.decls x66.ty x227) → (Pre_eff_of n x18 x31 x46 (Lanius.Mini.fieldTyAt x18 x31.decls x66.ty x227) x95 b2))))) | none => True))

end

noncomputable section

def Cost_set_index_or_eval : Nat → Nat → Lanius.Mini.FrontEnv → List Lanius.Mini.Local → Lanius.Mini.Local → Lanius.Mini.CTree → Lanius.Mini.CTree → Nat
  | 0, x18, x31, x46, x66, x76, x90 => 18446744073709551616
  | n + 1, x18, x31, x46, x66, x76, x90 => ((Cost_eff_of n x18 x31 x46 (none : Option Lanius.Mini.Ty) x76) + (Cost_eff_of n x18 x31 x46 (Lanius.Mini.indexElem x66.ty) x90))

end
noncomputable section

def Pre_set_index_or_eval : Nat → Nat → Lanius.Mini.FrontEnv → List Lanius.Mini.Local → Lanius.Mini.Local → Lanius.Mini.CTree → Lanius.Mini.CTree → Nat → Prop
  | 0, x18, x31, x46, x66, x76, x90, b => True
  | n + 1, x18, x31, x46, x66, x76, x90, b => ((Pre_length_of_mini_selfhost_FnDecl n x31.decls.fns b) ∧ ((Pre_eff_of n x18 x31 x46 (none : Option Lanius.Mini.Ty) x76 b) ∧ (∀ b1 : Nat, (Cost_eff_of n x18 x31 x46 (none : Option Lanius.Mini.Ty) x76) < b → b1 = b - (Cost_eff_of n x18 x31 x46 (none : Option Lanius.Mini.Ty) x76) → (Pre_eff_of n x18 x31 x46 (Lanius.Mini.indexElem x66.ty) x90 b1))))

end

noncomputable section

def Cost_assign_target : Nat → Nat → Lanius.Mini.FrontEnv → List Lanius.Mini.Local → Lanius.Mini.CTree → Nat → Lanius.Mini.CTree → Nat
  | 0, x14, x27, x42, x62, x77, x87 => 18446744073709551616
  | n + 1, x14, x27, x42, x62, x77, x87 => ((Cost_ref_target n x27 x42 x62) + (if (Lanius.Mini.refTarget x27 x42 x62) = true then (Cost_set_place_of n x14 x27 x42 x62 x87) else (if (decide ((Lanius.Mini.nodeProd ((Lanius.Mini.kid x62 1))) = Lanius.Mini.Inline.pPostfixEnd)) = true then ((Cost_local_of n x27 x42 (Lanius.Mini.kid x62 0)) + (match (Lanius.Mini.localOf x27 x42 ((Lanius.Mini.kid x62 0))) with | some x433 => (Cost_set_or_eval n x14 x27 x42 x433 x77 x87) | none => 0)) else (let k5 := ((Cost_local_of n x27 x42 (Lanius.Mini.kid x62 0)) + (match (Lanius.Mini.localOf x27 x42 ((Lanius.Mini.kid x62 0))) with | some x756 => (Cost_set_field_or_eval n x14 x27 x42 x756 (((Lanius.Mini.kidToken ((Lanius.Mini.kid x62 1)) 1)).text) x87) | none => 0)); let k6 := (let k3 := ((Cost_local_of n x27 x42 (Lanius.Mini.kid x62 0)) + (match (Lanius.Mini.localOf x27 x42 ((Lanius.Mini.kid x62 0))) with | some x1050 => (Cost_set_index_or_eval n x14 x27 x42 x1050 (Lanius.Mini.kid ((Lanius.Mini.kid x62 1)) 1) x87) | none => 0)); let k4 := 0; (if (decide ((Lanius.Mini.nodeProd ((Lanius.Mini.kid x62 1))) = Lanius.Mini.Inline.pPostfixIndex)) = true then (if (decide ((Lanius.Mini.nodeProd ((Lanius.Mini.kid ((Lanius.Mini.kid x62 1)) 3))) = Lanius.Mini.Inline.pPostfixEnd)) = true then k3 else k4) else k4)); (if (decide ((Lanius.Mini.nodeProd ((Lanius.Mini.kid x62 1))) = Lanius.Mini.Inline.pPostfixMember)) = true then (if (decide ((Lanius.Mini.nodeProd ((Lanius.Mini.kid ((Lanius.Mini.kid x62 1)) 2))) = Lanius.Mini.Inline.pMemberTypeArgsNone)) = true then (if (decide ((Lanius.Mini.nodeProd ((Lanius.Mini.kid ((Lanius.Mini.kid x62 1)) 3))) = Lanius.Mini.Inline.pPostfixEnd)) = true then k5 else k6) else k6) else k6)))))

end
noncomputable section

def Pre_assign_target : Nat → Nat → Lanius.Mini.FrontEnv → List Lanius.Mini.Local → Lanius.Mini.CTree → Nat → Lanius.Mini.CTree → Nat → Prop
  | 0, x14, x27, x42, x62, x77, x87, b => True
  | n + 1, x14, x27, x42, x62, x77, x87, b => (∀ b1 : Nat, (Cost_ref_target n x27 x42 x62) < b → b1 = b - (Cost_ref_target n x27 x42 x62) → (if (Lanius.Mini.refTarget x27 x42 x62) = true then (Pre_set_place_of n x14 x27 x42 x62 x87 b1) else (if (decide ((Lanius.Mini.nodeProd ((Lanius.Mini.kid x62 1))) = Lanius.Mini.Inline.pPostfixEnd)) = true then (∀ b3 : Nat, (Cost_local_of n x27 x42 (Lanius.Mini.kid x62 0)) < b1 → b3 = b1 - (Cost_local_of n x27 x42 (Lanius.Mini.kid x62 0)) → (match (Lanius.Mini.localOf x27 x42 ((Lanius.Mini.kid x62 0))) with | some x433 => (Pre_set_or_eval n x14 x27 x42 x433 x77 x87 b3) | none => True)) else (let k13 := fun (b5 : Nat) => (∀ b6 : Nat, (Cost_local_of n x27 x42 (Lanius.Mini.kid x62 0)) < b5 → b6 = b5 - (Cost_local_of n x27 x42 (Lanius.Mini.kid x62 0)) → (match (Lanius.Mini.localOf x27 x42 ((Lanius.Mini.kid x62 0))) with | some x756 => (Pre_set_field_or_eval n x14 x27 x42 x756 (((Lanius.Mini.kidToken ((Lanius.Mini.kid x62 1)) 1)).text) x87 b6) | none => True)); let k14 := fun (b5 : Nat) => (let k11 := fun (b8 : Nat) => (∀ b9 : Nat, (Cost_local_of n x27 x42 (Lanius.Mini.kid x62 0)) < b8 → b9 = b8 - (Cost_local_of n x27 x42 (Lanius.Mini.kid x62 0)) → (match (Lanius.Mini.localOf x27 x42 ((Lanius.Mini.kid x62 0))) with | some x1050 => (Pre_set_index_or_eval n x14 x27 x42 x1050 (Lanius.Mini.kid ((Lanius.Mini.kid x62 1)) 1) x87 b9) | none => True)); let k12 := fun (b8 : Nat) => True; (if (decide ((Lanius.Mini.nodeProd ((Lanius.Mini.kid x62 1))) = Lanius.Mini.Inline.pPostfixIndex)) = true then (if (decide ((Lanius.Mini.nodeProd ((Lanius.Mini.kid ((Lanius.Mini.kid x62 1)) 3))) = Lanius.Mini.Inline.pPostfixEnd)) = true then (k11 b5) else (k12 b5)) else (k12 b5))); (if (decide ((Lanius.Mini.nodeProd ((Lanius.Mini.kid x62 1))) = Lanius.Mini.Inline.pPostfixMember)) = true then (if (decide ((Lanius.Mini.nodeProd ((Lanius.Mini.kid ((Lanius.Mini.kid x62 1)) 2))) = Lanius.Mini.Inline.pMemberTypeArgsNone)) = true then (if (decide ((Lanius.Mini.nodeProd ((Lanius.Mini.kid ((Lanius.Mini.kid x62 1)) 3))) = Lanius.Mini.Inline.pPostfixEnd)) = true then (k13 b1) else (k14 b1)) else (k14 b1)) else (k14 b1))))))

end

noncomputable section

def Cost_set_place_op_of : Nat → Nat → Lanius.Mini.FrontEnv → List Lanius.Mini.Local → Option Lanius.Mini.SrcAssignOp → Lanius.Mini.CTree → Lanius.Mini.CTree → Nat
  | 0, x16, x29, x44, x64, x103, x118 => 18446744073709551616
  | n + 1, x16, x29, x44, x64, x103, x118 => (match x64 with | some x224 => ((Cost_eff_of n x16 x29 x44 (none : Option Lanius.Mini.Ty) x103) + (match (Lanius.Mini.effOf x16 x29 x44 ((none : Option Lanius.Mini.Ty)) x103) with | some x322 => (if (Lanius.Mini.effPlace x322) = true then ((Cost_eff_ty n x16 x29 x44 x322) + ((Cost_eff_ty n x16 x29 x44 x322) + (Cost_eff_of n x16 x29 x44 (Lanius.Mini.effTy x16 x29 x44 x322) x118))) else ((Cost_eff_ty n x16 x29 x44 x322) + (Cost_eff_of n x16 x29 x44 (Lanius.Mini.effTy x16 x29 x44 x322) x118))) | none => 0)) | none => 0)

end
noncomputable section

def Pre_set_place_op_of : Nat → Nat → Lanius.Mini.FrontEnv → List Lanius.Mini.Local → Option Lanius.Mini.SrcAssignOp → Lanius.Mini.CTree → Lanius.Mini.CTree → Nat → Prop
  | 0, x16, x29, x44, x64, x103, x118, b => True
  | n + 1, x16, x29, x44, x64, x103, x118, b => (match x64 with | some x224 => ((Pre_eff_of n x16 x29 x44 (none : Option Lanius.Mini.Ty) x103 b) ∧ (∀ b1 : Nat, (Cost_eff_of n x16 x29 x44 (none : Option Lanius.Mini.Ty) x103) < b → b1 = b - (Cost_eff_of n x16 x29 x44 (none : Option Lanius.Mini.Ty) x103) → (match (Lanius.Mini.effOf x16 x29 x44 ((none : Option Lanius.Mini.Ty)) x103) with | some x322 => (if (Lanius.Mini.effPlace x322) = true then ((Pre_eff_ty n x16 x29 x44 x322 b1) ∧ (∀ b4 : Nat, (Cost_eff_ty n x16 x29 x44 x322) < b1 → b4 = b1 - (Cost_eff_ty n x16 x29 x44 x322) → ((Pre_length_of_mini_selfhost_FnDecl n x29.decls.fns b4) ∧ ((Pre_eff_ty n x16 x29 x44 x322 b4) ∧ (∀ b5 : Nat, (Cost_eff_ty n x16 x29 x44 x322) < b4 → b5 = b4 - (Cost_eff_ty n x16 x29 x44 x322) → (Pre_eff_of n x16 x29 x44 (Lanius.Mini.effTy x16 x29 x44 x322) x118 b5)))))) else ((Pre_length_of_mini_selfhost_FnDecl n x29.decls.fns b1) ∧ ((Pre_eff_ty n x16 x29 x44 x322 b1) ∧ (∀ b2 : Nat, (Cost_eff_ty n x16 x29 x44 x322) < b1 → b2 = b1 - (Cost_eff_ty n x16 x29 x44 x322) → (Pre_eff_of n x16 x29 x44 (Lanius.Mini.effTy x16 x29 x44 x322) x118 b2))))) | none => True))) | none => True)

end

noncomputable section

def Cost_compound_eff : Nat → Nat → Lanius.Mini.MEff → Option Lanius.Mini.MEff → Nat
  | 0, x13, x23, x35 => 18446744073709551616
  | n + 1, x13, x23, x35 => (if (decide (x13 = Lanius.Mini.Inline.pAssignDiv)) = true then (Cost_x_divide_of n Lanius.Mini.SrcDivOp.quotient (some x23) x35) else (if (decide (x13 = Lanius.Mini.Inline.pAssignMod)) = true then (Cost_x_divide_of n Lanius.Mini.SrcDivOp.remainder (some x23) x35) else (match (Lanius.Mini.compoundOp x13) with | some x362 => (Cost_x_apply_of n x362 (some x23) x35) | none => 0)))

end

noncomputable section

def Cost_compound_field_eval : Nat → Nat → Lanius.Mini.FrontEnv → List Lanius.Mini.Local → Lanius.Mini.Local → Option Nat → Nat → Lanius.Mini.CTree → Nat
  | 0, x20, x33, x48, x68, x78, x114, x124 => 18446744073709551616
  | n + 1, x20, x33, x48, x68, x78, x114, x124 => (match x78 with | some x233 => ((Cost_field_ty_at n x20 x33.decls x68.ty x233) + ((Cost_field_ty_at n x20 x33.decls x68.ty x233) + ((Cost_eff_of n x20 x33 x48 (Lanius.Mini.fieldTyAt x20 x33.decls x68.ty x233) x124) + (Cost_compound_eff n x114 (Lanius.Mini.MEff.xPure (Lanius.Mini.SrcExpr.field x68.id x233)) (Lanius.Mini.effOf x20 x33 x48 ((Lanius.Mini.fieldTyAt x20 x33.decls x68.ty x233)) x124))))) | none => 0)

end
noncomputable section

def Pre_compound_field_eval : Nat → Nat → Lanius.Mini.FrontEnv → List Lanius.Mini.Local → Lanius.Mini.Local → Option Nat → Nat → Lanius.Mini.CTree → Nat → Prop
  | 0, x20, x33, x48, x68, x78, x114, x124, b => True
  | n + 1, x20, x33, x48, x68, x78, x114, x124, b => (match x78 with | some x233 => ((Pre_field_ty_at n x20 x33.decls x68.ty x233 b) ∧ (∀ b1 : Nat, (Cost_field_ty_at n x20 x33.decls x68.ty x233) < b → b1 = b - (Cost_field_ty_at n x20 x33.decls x68.ty x233) → ((Pre_field_ty_at n x20 x33.decls x68.ty x233 b1) ∧ (∀ b2 : Nat, (Cost_field_ty_at n x20 x33.decls x68.ty x233) < b1 → b2 = b1 - (Cost_field_ty_at n x20 x33.decls x68.ty x233) → (Pre_eff_of n x20 x33 x48 (Lanius.Mini.fieldTyAt x20 x33.decls x68.ty x233) x124 b2))))) | none => True)

end

noncomputable section

def Cost_compound_eval : Nat → Nat → Lanius.Mini.FrontEnv → List Lanius.Mini.Local → Lanius.Mini.CTree → Nat → Lanius.Mini.CTree → Nat
  | 0, x14, x27, x42, x62, x77, x87 => 18446744073709551616
  | n + 1, x14, x27, x42, x62, x77, x87 => ((Cost_ref_target n x27 x42 x62) + (if (Lanius.Mini.refTarget x27 x42 x62) = true then (Cost_set_place_op_of n x14 x27 x42 (Lanius.Mini.assignOpOf x77) x62 x87) else (if (decide ((Lanius.Mini.nodeProd ((Lanius.Mini.kid x62 1))) = Lanius.Mini.Inline.pPostfixEnd)) = true then ((Cost_local_of n x27 x42 (Lanius.Mini.kid x62 0)) + (match (Lanius.Mini.localOf x27 x42 ((Lanius.Mini.kid x62 0))) with | some x425 => ((Cost_eff_of n x14 x27 x42 (some x425.ty) x87) + ((Cost_compound_eff n x77 (Lanius.Mini.MEff.xPure (Lanius.Mini.SrcExpr.local x425.id)) (Lanius.Mini.effOf x14 x27 x42 ((some x425.ty)) x87)) + (Cost_set_eval_of n x425.id (Lanius.Mini.compoundEff x77 ((Lanius.Mini.MEff.xPure (Lanius.Mini.SrcExpr.local x425.id))) ((Lanius.Mini.effOf x14 x27 x42 ((some x425.ty)) x87)))))) | none => 0)) else (let k2 := ((Cost_local_of n x27 x42 (Lanius.Mini.kid x62 0)) + (match (Lanius.Mini.localOf x27 x42 ((Lanius.Mini.kid x62 0))) with | some x843 => (Cost_compound_field_eval n x14 x27 x42 x843 (Lanius.Mini.fieldIndex x27 x843.ty ((((Lanius.Mini.kidToken ((Lanius.Mini.kid x62 1)) 1)).text))) x77 x87) | none => 0)); let k3 := 0; (if (decide ((Lanius.Mini.nodeProd ((Lanius.Mini.kid x62 1))) = Lanius.Mini.Inline.pPostfixMember)) = true then (if (decide ((Lanius.Mini.nodeProd ((Lanius.Mini.kid ((Lanius.Mini.kid x62 1)) 2))) = Lanius.Mini.Inline.pMemberTypeArgsNone)) = true then (if (decide ((Lanius.Mini.nodeProd ((Lanius.Mini.kid ((Lanius.Mini.kid x62 1)) 3))) = Lanius.Mini.Inline.pPostfixEnd)) = true then k2 else k3) else k3) else k3)))))

end
noncomputable section

def Pre_compound_eval : Nat → Nat → Lanius.Mini.FrontEnv → List Lanius.Mini.Local → Lanius.Mini.CTree → Nat → Lanius.Mini.CTree → Nat → Prop
  | 0, x14, x27, x42, x62, x77, x87, b => True
  | n + 1, x14, x27, x42, x62, x77, x87, b => (∀ b1 : Nat, (Cost_ref_target n x27 x42 x62) < b → b1 = b - (Cost_ref_target n x27 x42 x62) → (if (Lanius.Mini.refTarget x27 x42 x62) = true then (Pre_set_place_op_of n x14 x27 x42 (Lanius.Mini.assignOpOf x77) x62 x87 b1) else (if (decide ((Lanius.Mini.nodeProd ((Lanius.Mini.kid x62 1))) = Lanius.Mini.Inline.pPostfixEnd)) = true then (∀ b3 : Nat, (Cost_local_of n x27 x42 (Lanius.Mini.kid x62 0)) < b1 → b3 = b1 - (Cost_local_of n x27 x42 (Lanius.Mini.kid x62 0)) → (match (Lanius.Mini.localOf x27 x42 ((Lanius.Mini.kid x62 0))) with | some x425 => (Pre_eff_of n x14 x27 x42 (some x425.ty) x87 b3) | none => True)) else (let k10 := fun (b7 : Nat) => (∀ b8 : Nat, (Cost_local_of n x27 x42 (Lanius.Mini.kid x62 0)) < b7 → b8 = b7 - (Cost_local_of n x27 x42 (Lanius.Mini.kid x62 0)) → (match (Lanius.Mini.localOf x27 x42 ((Lanius.Mini.kid x62 0))) with | some x843 => ((Pre_field_index n x27 x843.ty (((Lanius.Mini.kidToken ((Lanius.Mini.kid x62 1)) 1)).text) b8) ∧ (Pre_compound_field_eval n x14 x27 x42 x843 (Lanius.Mini.fieldIndex x27 x843.ty ((((Lanius.Mini.kidToken ((Lanius.Mini.kid x62 1)) 1)).text))) x77 x87 b8)) | none => True)); let k11 := fun (b7 : Nat) => True; (if (decide ((Lanius.Mini.nodeProd ((Lanius.Mini.kid x62 1))) = Lanius.Mini.Inline.pPostfixMember)) = true then (if (decide ((Lanius.Mini.nodeProd ((Lanius.Mini.kid ((Lanius.Mini.kid x62 1)) 2))) = Lanius.Mini.Inline.pMemberTypeArgsNone)) = true then (if (decide ((Lanius.Mini.nodeProd ((Lanius.Mini.kid ((Lanius.Mini.kid x62 1)) 3))) = Lanius.Mini.Inline.pPostfixEnd)) = true then (k10 b1) else (k11 b1)) else (k11 b1)) else (k11 b1))))))

end

noncomputable section

def Cost_compound_of : Nat → Nat → Lanius.Mini.FrontEnv → List Lanius.Mini.Local → Option Lanius.Mini.CTree → Nat → Lanius.Mini.CTree → Nat
  | 0, x12, x25, x40, x60, x97, x107 => 18446744073709551616
  | n + 1, x12, x25, x40, x60, x97, x107 => (match x60 with | some x217 => (Cost_compound_eval n x12 x25 x40 x217 x97 x107) | none => 0)

end
noncomputable section

def Pre_compound_of : Nat → Nat → Lanius.Mini.FrontEnv → List Lanius.Mini.Local → Option Lanius.Mini.CTree → Nat → Lanius.Mini.CTree → Nat → Prop
  | 0, x12, x25, x40, x60, x97, x107, b => True
  | n + 1, x12, x25, x40, x60, x97, x107, b => (match x60 with | some x217 => (Pre_compound_eval n x12 x25 x40 x217 x97 x107 b) | none => True)

end

noncomputable section

def Pre_free_of : Nat → Option (List Lanius.Mini.SrcExpr) → Nat → Prop
  | 0, x8, b => True
  | n + 1, x8, b => (match x8 with | some x145 => (match x145 with | [] => True | x207 :: x216 => (match x216 with | [] => True | x297 :: x303 => (match x303 with | [] => True | x392 :: x399 => (Pre_shift_of n x392 b)))) | none => True)

end

noncomputable section

def Cost_assert_arg : Nat → Nat → Lanius.Mini.FrontEnv → List Lanius.Mini.Local → Option (List Lanius.Mini.CTree) → Nat
  | 0, x11, x24, x39, x59 => 18446744073709551616
  | n + 1, x11, x24, x39, x59 => (match x59 with | some x194 => (match x194 with | [] => 0 | x262 :: x265 => (match x265 with | [] => (Cost_eff_of n x11 x24 x39 (some Lanius.Mini.Ty.tyBool) x262) | x394 :: x397 => 0)) | none => 0)

end
noncomputable section

def Pre_assert_arg : Nat → Nat → Lanius.Mini.FrontEnv → List Lanius.Mini.Local → Option (List Lanius.Mini.CTree) → Nat → Prop
  | 0, x11, x24, x39, x59, b => True
  | n + 1, x11, x24, x39, x59, b => (match x59 with | some x194 => (match x194 with | [] => True | x262 :: x265 => (match x265 with | [] => (Pre_eff_of n x11 x24 x39 (some Lanius.Mini.Ty.tyBool) x262 b) | x394 :: x397 => True)) | none => True)

end

noncomputable section

def Cost_try_stmt : Nat → Option Lanius.Mini.Tried → Nat
  | 0, x9 => 18446744073709551616
  | n + 1, x9 => (match x9 with | some x132 => (Cost_try_rest n x132 Lanius.Mini.MStmt.mNop) | none => 0)

end

noncomputable section

def Cost_call_stmt : Nat → Nat → Lanius.Mini.FrontEnv → List Lanius.Mini.Local → Lanius.Mini.CTree → Nat
  | 0, x10, x23, x38, x58 => 18446744073709551616
  | n + 1, x10, x23, x38, x58 => (let k8 := (Cost_args_of n x10 x23 x38 (Lanius.Mini.kid ((Lanius.Mini.kid x58 1)) 1)); let k9 := (let k6 := ((Cost_list_items n x10 (Lanius.Mini.kid ((Lanius.Mini.kid x58 1)) 1)) + (Cost_assert_arg n x10 x23 x38 (Lanius.Mini.listItems x10 ((Lanius.Mini.kid ((Lanius.Mini.kid x58 1)) 1))))); let k7 := (let k4 := (Cost_eff_postfix n x10 x23 x38 (none : Option Lanius.Mini.Ty) x58); let k5 := (if (Lanius.Mini.isTryCall x58) = true then ((Cost_try_call_of n x10 x23 x38 x58) + (Cost_try_stmt n (Lanius.Mini.tryCallOf x10 x23 x38 x58))) else 0); (if (Lanius.Mini.isPathCall x58) = true then k4 else (if (Lanius.Mini.isMethodForm x58) = true then k4 else k5))); (if (Lanius.Mini.isPathCall x58) = true then ((Cost_path_spellings n x10 (Lanius.Mini.kid ((Lanius.Mini.kid ((Lanius.Mini.kid x58 0)) 0)) 0) (Lanius.Mini.kid ((Lanius.Mini.kid ((Lanius.Mini.kid x58 0)) 0)) 1)) + ((Cost_text_assert n ) + ((Cost_single_of_mini_selfhost_List_usize n Lanius.Mini.textAssert) + (if (Lanius.Mini.isPath ((Lanius.Mini.pathSpellings x10 ((Lanius.Mini.kid ((Lanius.Mini.kid ((Lanius.Mini.kid x58 0)) 0)) 0)) ((Lanius.Mini.kid ((Lanius.Mini.kid ((Lanius.Mini.kid x58 0)) 0)) 1)))) ([Lanius.Mini.textAssert])) = true then k6 else k7)))) else k7)); (if (Lanius.Mini.isPathCall x58) = true then ((Cost_path_spellings n x10 (Lanius.Mini.kid ((Lanius.Mini.kid ((Lanius.Mini.kid x58 0)) 0)) 0) (Lanius.Mini.kid ((Lanius.Mini.kid ((Lanius.Mini.kid x58 0)) 0)) 1)) + ((Cost_dealloc_path n ) + (if (Lanius.Mini.isPath ((Lanius.Mini.pathSpellings x10 ((Lanius.Mini.kid ((Lanius.Mini.kid ((Lanius.Mini.kid x58 0)) 0)) 0)) ((Lanius.Mini.kid ((Lanius.Mini.kid ((Lanius.Mini.kid x58 0)) 0)) 1)))) Lanius.Mini.deallocPath) = true then k8 else k9))) else k9))

end
noncomputable section

def Pre_call_stmt : Nat → Nat → Lanius.Mini.FrontEnv → List Lanius.Mini.Local → Lanius.Mini.CTree → Nat → Prop
  | 0, x10, x23, x38, x58, b => True
  | n + 1, x10, x23, x38, x58, b => (let k17 := fun (b1 : Nat) => ((Pre_args_of n x10 x23 x38 (Lanius.Mini.kid ((Lanius.Mini.kid x58 1)) 1) b1) ∧ (∀ b2 : Nat, (Cost_args_of n x10 x23 x38 (Lanius.Mini.kid ((Lanius.Mini.kid x58 1)) 1)) < b1 → b2 = b1 - (Cost_args_of n x10 x23 x38 (Lanius.Mini.kid ((Lanius.Mini.kid x58 1)) 1)) → (Pre_free_of n (Lanius.Mini.argsOf x10 x23 x38 ((Lanius.Mini.kid ((Lanius.Mini.kid x58 1)) 1))) b2))); let k18 := fun (b1 : Nat) => (let k12 := fun (b3 : Nat) => (∀ b4 : Nat, (Cost_list_items n x10 (Lanius.Mini.kid ((Lanius.Mini.kid x58 1)) 1)) < b3 → b4 = b3 - (Cost_list_items n x10 (Lanius.Mini.kid ((Lanius.Mini.kid x58 1)) 1)) → (Pre_assert_arg n x10 x23 x38 (Lanius.Mini.listItems x10 ((Lanius.Mini.kid ((Lanius.Mini.kid x58 1)) 1))) b4)); let k13 := fun (b3 : Nat) => (let k10 := fun (b6 : Nat) => (Pre_eff_postfix n x10 x23 x38 (none : Option Lanius.Mini.Ty) x58 b6); let k11 := fun (b6 : Nat) => (if (Lanius.Mini.isTryCall x58) = true then (Pre_try_call_of n x10 x23 x38 x58 b6) else True); (if (Lanius.Mini.isPathCall x58) = true then (k10 b3) else (if (Lanius.Mini.isMethodForm x58) = true then (k10 b3) else (k11 b3)))); (if (Lanius.Mini.isPathCall x58) = true then (∀ b14 : Nat, (Cost_path_spellings n x10 (Lanius.Mini.kid ((Lanius.Mini.kid ((Lanius.Mini.kid x58 0)) 0)) 0) (Lanius.Mini.kid ((Lanius.Mini.kid ((Lanius.Mini.kid x58 0)) 0)) 1)) < b1 → b14 = b1 - (Cost_path_spellings n x10 (Lanius.Mini.kid ((Lanius.Mini.kid ((Lanius.Mini.kid x58 0)) 0)) 0) (Lanius.Mini.kid ((Lanius.Mini.kid ((Lanius.Mini.kid x58 0)) 0)) 1)) → (∀ b15 : Nat, (Cost_text_assert n ) < b14 → b15 = b14 - (Cost_text_assert n ) → (∀ b16 : Nat, (Cost_single_of_mini_selfhost_List_usize n Lanius.Mini.textAssert) < b15 → b16 = b15 - (Cost_single_of_mini_selfhost_List_usize n Lanius.Mini.textAssert) → (if (Lanius.Mini.isPath ((Lanius.Mini.pathSpellings x10 ((Lanius.Mini.kid ((Lanius.Mini.kid ((Lanius.Mini.kid x58 0)) 0)) 0)) ((Lanius.Mini.kid ((Lanius.Mini.kid ((Lanius.Mini.kid x58 0)) 0)) 1)))) ([Lanius.Mini.textAssert])) = true then (k12 b16) else (k13 b16))))) else (k13 b1))); (if (Lanius.Mini.isPathCall x58) = true then (∀ b19 : Nat, (Cost_path_spellings n x10 (Lanius.Mini.kid ((Lanius.Mini.kid ((Lanius.Mini.kid x58 0)) 0)) 0) (Lanius.Mini.kid ((Lanius.Mini.kid ((Lanius.Mini.kid x58 0)) 0)) 1)) < b → b19 = b - (Cost_path_spellings n x10 (Lanius.Mini.kid ((Lanius.Mini.kid ((Lanius.Mini.kid x58 0)) 0)) 0) (Lanius.Mini.kid ((Lanius.Mini.kid ((Lanius.Mini.kid x58 0)) 0)) 1)) → (∀ b20 : Nat, (Cost_dealloc_path n ) < b19 → b20 = b19 - (Cost_dealloc_path n ) → (if (Lanius.Mini.isPath ((Lanius.Mini.pathSpellings x10 ((Lanius.Mini.kid ((Lanius.Mini.kid ((Lanius.Mini.kid x58 0)) 0)) 0)) ((Lanius.Mini.kid ((Lanius.Mini.kid ((Lanius.Mini.kid x58 0)) 0)) 1)))) Lanius.Mini.deallocPath) = true then (k17 b20) else (k18 b20)))) else (k18 b)))

end

noncomputable section

def Cost_assignment : Nat → Nat → Lanius.Mini.FrontEnv → List Lanius.Mini.Local → Lanius.Mini.CTree → Nat
  | 0, x11, x24, x39, x59 => 18446744073709551616
  | n + 1, x11, x24, x39, x59 => (let k8 := (match (Lanius.Mini.peel x11 ((Lanius.Mini.kid ((Lanius.Mini.kid x59 0)) 0))) with | some x356 => (Cost_assign_target n x11 x24 x39 x356 ((((Lanius.Mini.kidToken ((Lanius.Mini.kid ((Lanius.Mini.kid x59 0)) 1)) 0)).start) - x24.base) (Lanius.Mini.kid ((Lanius.Mini.kid ((Lanius.Mini.kid x59 0)) 1)) 1)) | none => 0); let k9 := (let k6 := (Cost_compound_of n x11 x24 x39 (Lanius.Mini.peel x11 ((Lanius.Mini.kid ((Lanius.Mini.kid x59 0)) 0))) (Lanius.Mini.nodeProd ((Lanius.Mini.kid ((Lanius.Mini.kid x59 0)) 1))) (Lanius.Mini.kid ((Lanius.Mini.kid ((Lanius.Mini.kid x59 0)) 1)) 1)); let k7 := (let k4 := (match (Lanius.Mini.peel x11 ((Lanius.Mini.kid ((Lanius.Mini.kid x59 0)) 0))) with | some x895 => (Cost_call_stmt n x11 x24 x39 x895) | none => 0); let k5 := 0; (if (decide ((Lanius.Mini.nodeProd x59) = Lanius.Mini.Inline.pExpr)) = true then (if (decide ((Lanius.Mini.nodeProd ((Lanius.Mini.kid x59 0))) = Lanius.Mini.Inline.pAssign)) = true then (if (decide ((Lanius.Mini.nodeProd ((Lanius.Mini.kid ((Lanius.Mini.kid x59 0)) 1))) = Lanius.Mini.Inline.pAssignEnd)) = true then k4 else k5) else k5) else k5)); (if (decide ((Lanius.Mini.nodeProd x59) = Lanius.Mini.Inline.pExpr)) = true then (if (decide ((Lanius.Mini.nodeProd ((Lanius.Mini.kid x59 0))) = Lanius.Mini.Inline.pAssign)) = true then (if (Lanius.Mini.hasKids ((Lanius.Mini.kid ((Lanius.Mini.kid x59 0)) 1))) = true then (if (!decide ((Lanius.Mini.nodeProd ((Lanius.Mini.kid ((Lanius.Mini.kid x59 0)) 1))) = Lanius.Mini.Inline.pAssignSet)) = true then k6 else k7) else k7) else k7) else k7)); (if (decide ((Lanius.Mini.nodeProd x59) = Lanius.Mini.Inline.pExpr)) = true then (if (decide ((Lanius.Mini.nodeProd ((Lanius.Mini.kid x59 0))) = Lanius.Mini.Inline.pAssign)) = true then (if (decide ((Lanius.Mini.nodeProd ((Lanius.Mini.kid ((Lanius.Mini.kid x59 0)) 1))) = Lanius.Mini.Inline.pAssignSet)) = true then k8 else k9) else k9) else k9))

end
noncomputable section

def Pre_assignment : Nat → Nat → Lanius.Mini.FrontEnv → List Lanius.Mini.Local → Lanius.Mini.CTree → Nat → Prop
  | 0, x11, x24, x39, x59, b => True
  | n + 1, x11, x24, x39, x59, b => (let k11 := fun (b1 : Nat) => (match (Lanius.Mini.peel x11 ((Lanius.Mini.kid ((Lanius.Mini.kid x59 0)) 0))) with | some x356 => (Pre_assign_target n x11 x24 x39 x356 ((((Lanius.Mini.kidToken ((Lanius.Mini.kid ((Lanius.Mini.kid x59 0)) 1)) 0)).start) - x24.base) (Lanius.Mini.kid ((Lanius.Mini.kid ((Lanius.Mini.kid x59 0)) 1)) 1) b1) | none => True); let k12 := fun (b1 : Nat) => (let k9 := fun (b3 : Nat) => (Pre_compound_of n x11 x24 x39 (Lanius.Mini.peel x11 ((Lanius.Mini.kid ((Lanius.Mini.kid x59 0)) 0))) (Lanius.Mini.nodeProd ((Lanius.Mini.kid ((Lanius.Mini.kid x59 0)) 1))) (Lanius.Mini.kid ((Lanius.Mini.kid ((Lanius.Mini.kid x59 0)) 1)) 1) b3); let k10 := fun (b3 : Nat) => (let k7 := fun (b5 : Nat) => (match (Lanius.Mini.peel x11 ((Lanius.Mini.kid ((Lanius.Mini.kid x59 0)) 0))) with | some x895 => (Pre_call_stmt n x11 x24 x39 x895 b5) | none => True); let k8 := fun (b5 : Nat) => True; (if (decide ((Lanius.Mini.nodeProd x59) = Lanius.Mini.Inline.pExpr)) = true then (if (decide ((Lanius.Mini.nodeProd ((Lanius.Mini.kid x59 0))) = Lanius.Mini.Inline.pAssign)) = true then (if (decide ((Lanius.Mini.nodeProd ((Lanius.Mini.kid ((Lanius.Mini.kid x59 0)) 1))) = Lanius.Mini.Inline.pAssignEnd)) = true then (k7 b3) else (k8 b3)) else (k8 b3)) else (k8 b3))); (if (decide ((Lanius.Mini.nodeProd x59) = Lanius.Mini.Inline.pExpr)) = true then (if (decide ((Lanius.Mini.nodeProd ((Lanius.Mini.kid x59 0))) = Lanius.Mini.Inline.pAssign)) = true then (if (Lanius.Mini.hasKids ((Lanius.Mini.kid ((Lanius.Mini.kid x59 0)) 1))) = true then (if (!decide ((Lanius.Mini.nodeProd ((Lanius.Mini.kid ((Lanius.Mini.kid x59 0)) 1))) = Lanius.Mini.Inline.pAssignSet)) = true then (k9 b1) else (k10 b1)) else (k10 b1)) else (k10 b1)) else (k10 b1))); (if (decide ((Lanius.Mini.nodeProd x59) = Lanius.Mini.Inline.pExpr)) = true then (if (decide ((Lanius.Mini.nodeProd ((Lanius.Mini.kid x59 0))) = Lanius.Mini.Inline.pAssign)) = true then (if (decide ((Lanius.Mini.nodeProd ((Lanius.Mini.kid ((Lanius.Mini.kid x59 0)) 1))) = Lanius.Mini.Inline.pAssignSet)) = true then (k11 b) else (k12 b)) else (k12 b)) else (k12 b)))

end

noncomputable section

def Cost_then_rest : Nat → Lanius.Mini.MStmt → Option Lanius.Mini.MStmt → Nat
  | 0, x10, x20 => 18446744073709551616
  | n + 1, x10, x20 => (match x20 with | some x149 => (1 + 1) | none => 0)

end

noncomputable section

def Cost_then_of : Nat → Option Lanius.Mini.MStmt → Option Lanius.Mini.MStmt → Nat
  | 0, x8, x43 => 18446744073709551616
  | n + 1, x8, x43 => (match x8 with | some x172 => (Cost_then_rest n x172 x43) | none => 0)

end

noncomputable section

mutual
def Cost_block_of : Nat → Nat → Lanius.Mini.FrontEnv → List Lanius.Mini.Local → Lanius.Mini.CTree → Nat
  | 0, x9, x22, x37, x57 => 18446744073709551616
  | n + 1, x9, x22, x37, x57 => (if (decide (x9 = 0)) = true then 0 else ((Cost_list_items n x9 x57) + (match (Lanius.Mini.listItems x9 x57) with | some x230 => (Cost_stmts_of n (x9 - 1) x22 x37 x230) | none => 0)))
termination_by structural fuel => fuel

def Cost_stmts_of : Nat → Nat → Lanius.Mini.FrontEnv → List Lanius.Mini.Local → List Lanius.Mini.CTree → Nat
  | 0, x9, x22, x37, x57 => 18446744073709551616
  | n + 1, x9, x22, x37, x57 => (if (decide (x9 = 0)) = true then 0 else (match x57 with | [] => 0 | x225 :: x228 => (Cost_stmt_first n (x9 - 1) x22 x37 x225 x228)))
termination_by structural fuel => fuel

def Cost_stmt_first : Nat → Nat → Lanius.Mini.FrontEnv → List Lanius.Mini.Local → Lanius.Mini.CTree → List Lanius.Mini.CTree → Nat
  | 0, x11, x24, x39, x59, x69 => 18446744073709551616
  | n + 1, x11, x24, x39, x59, x69 => (if (decide (x11 = 0)) = true then 0 else (if (decide ((Lanius.Mini.nodeProd x59) = Lanius.Mini.Inline.pLetStmt)) = true then (Cost_let_first n (x11 - 1) x24 x39 x59 x69) else (match x69 with | [] => (Cost_stmt_of n (x11 - 1) x24 x39 x59) | x372 :: x378 => ((Cost_stmt_of n (x11 - 1) x24 x39 x59) + ((Cost_stmts_of n (x11 - 1) x24 x39 x69) + (Cost_then_of n (Lanius.Mini.stmtOf ((x11 - 1)) x24 x39 x59) (Lanius.Mini.stmtsOf ((x11 - 1)) x24 x39 x69)))))))
termination_by structural fuel => fuel

def Cost_let_first : Nat → Nat → Lanius.Mini.FrontEnv → List Lanius.Mini.Local → Lanius.Mini.CTree → List Lanius.Mini.CTree → Nat
  | 0, x10, x23, x38, x58, x68 => 18446744073709551616
  | n + 1, x10, x23, x38, x58, x68 => (if (decide (x10 = 0)) = true then 0 else ((Cost_is_str_let n x10 x23 x38 x58) + (if (Lanius.Mini.isStrLet x10 x23 x38 x58) = true then (Cost_string_let n (x10 - 1) x23 (((Lanius.Mini.kidToken x58 1).start) - x23.base) ((Lanius.Mini.kidToken x58 1).text) (Lanius.Mini.kid ((Lanius.Mini.kid x58 3)) 1) x68) else (let k11 := ((Cost_ty_of n x10 x23 (Lanius.Mini.kid ((Lanius.Mini.kid x58 2)) 1)) + (match (Lanius.Mini.tyOf x10 x23 ((Lanius.Mini.kid ((Lanius.Mini.kid x58 2)) 1))) with | some x691 => ((Cost_cons_of_mini_selfhost_Local n (Lanius.Mini.Local.mk ((Lanius.Mini.kidToken x58 1).text) (((Lanius.Mini.kidToken x58 1).start) - x23.base) x691) x38) + ((Cost_stmts_of n (x10 - 1) x23 ((Lanius.Mini.Local.mk ((Lanius.Mini.kidToken x58 1).text) (((Lanius.Mini.kidToken x58 1).start) - x23.base) x691) :: x38) x68) + (Cost_lit_let_of n (x10 - 1) x23 x38 (Lanius.Mini.Local.mk ((Lanius.Mini.kidToken x58 1).text) (((Lanius.Mini.kidToken x58 1).start) - x23.base) x691) (Lanius.Mini.kid ((Lanius.Mini.kid x58 3)) 1) (Lanius.Mini.stmtsOf ((x10 - 1)) x23 (((Lanius.Mini.Local.mk ((Lanius.Mini.kidToken x58 1).text) (((Lanius.Mini.kidToken x58 1).start) - x23.base) x691) :: x38)) x68)))) | none => 0)); let k12 := (let k9 := ((Cost_ty_of n x10 x23 (Lanius.Mini.kid ((Lanius.Mini.kid x58 2)) 1)) + (match (Lanius.Mini.tyOf x10 x23 ((Lanius.Mini.kid ((Lanius.Mini.kid x58 2)) 1))) with | some x1269 => ((Cost_cons_of_mini_selfhost_Local n (Lanius.Mini.Local.mk ((Lanius.Mini.kidToken x58 1).text) (((Lanius.Mini.kidToken x58 1).start) - x23.base) x1269) x38) + ((Cost_stmts_of n (x10 - 1) x23 ((Lanius.Mini.Local.mk ((Lanius.Mini.kidToken x58 1).text) (((Lanius.Mini.kidToken x58 1).start) - x23.base) x1269) :: x38) x68) + (Cost_let_match_of n (x10 - 1) x23 x38 (Lanius.Mini.Local.mk ((Lanius.Mini.kidToken x58 1).text) (((Lanius.Mini.kidToken x58 1).start) - x23.base) x1269) (Lanius.Mini.kid ((Lanius.Mini.kid x58 3)) 1) (Lanius.Mini.stmtsOf ((x10 - 1)) x23 (((Lanius.Mini.Local.mk ((Lanius.Mini.kidToken x58 1).text) (((Lanius.Mini.kidToken x58 1).start) - x23.base) x1269) :: x38)) x68)))) | none => 0)); let k10 := (let k7 := ((Cost_ty_of n x10 x23 (Lanius.Mini.kid ((Lanius.Mini.kid x58 2)) 1)) + (match (Lanius.Mini.tyOf x10 x23 ((Lanius.Mini.kid ((Lanius.Mini.kid x58 2)) 1))) with | some x1806 => ((Cost_cons_of_mini_selfhost_Local n (Lanius.Mini.Local.mk ((Lanius.Mini.kidToken x58 1).text) (((Lanius.Mini.kidToken x58 1).start) - x23.base) x1806) x38) + ((Cost_let_head_or_eval n (x10 - 1) x23 x38 x1806 (Lanius.Mini.kid ((Lanius.Mini.kid x58 3)) 1)) + ((Cost_view_read n (x10 - 1) x23 ((Lanius.Mini.Local.mk ((Lanius.Mini.kidToken x58 1).text) (((Lanius.Mini.kidToken x58 1).start) - x23.base) x1806) :: x38) (Lanius.Mini.Local.mk ((Lanius.Mini.kidToken x58 1).text) (((Lanius.Mini.kidToken x58 1).start) - x23.base) x1806) (Lanius.Mini.letHeadOrEval ((x10 - 1)) x23 x38 x1806 ((Lanius.Mini.kid ((Lanius.Mini.kid x58 3)) 1))) x68) + (match (Lanius.Mini.viewRead ((x10 - 1)) x23 (((Lanius.Mini.Local.mk ((Lanius.Mini.kidToken x58 1).text) (((Lanius.Mini.kidToken x58 1).start) - x23.base) x1806) :: x38)) ((Lanius.Mini.Local.mk ((Lanius.Mini.kidToken x58 1).text) (((Lanius.Mini.kidToken x58 1).start) - x23.base) x1806)) ((Lanius.Mini.letHeadOrEval ((x10 - 1)) x23 x38 x1806 ((Lanius.Mini.kid ((Lanius.Mini.kid x58 3)) 1)))) x68) with | some x2091 => ((Cost_cons_of_mini_selfhost_Local n (Lanius.Mini.Local.mk ((Lanius.Mini.kidToken x58 1).text) (((Lanius.Mini.kidToken x58 1).start) - x23.base) x1806) x38) + ((Cost_cons_of_mini_selfhost_Local n x2091.pointer ((Lanius.Mini.Local.mk ((Lanius.Mini.kidToken x58 1).text) (((Lanius.Mini.kidToken x58 1).start) - x23.base) x1806) :: x38)) + ((Cost_stmts_of n (x10 - 1) x23 (x2091.pointer :: ((Lanius.Mini.Local.mk ((Lanius.Mini.kidToken x58 1).text) (((Lanius.Mini.kidToken x58 1).start) - x23.base) x1806) :: x38)) x2091.more) + (Cost_view_stmt n (((Lanius.Mini.kidToken x58 1).start) - x23.base) x2091.length x2091.fields x2091.pointer.id (Lanius.Mini.stmtsOf ((x10 - 1)) x23 ((x2091.pointer :: ((Lanius.Mini.Local.mk ((Lanius.Mini.kidToken x58 1).text) (((Lanius.Mini.kidToken x58 1).start) - x23.base) x1806) :: x38))) x2091.more))))) | none => ((Cost_let_head_or_eval n (x10 - 1) x23 x38 x1806 (Lanius.Mini.kid ((Lanius.Mini.kid x58 3)) 1)) + ((Cost_cons_of_mini_selfhost_Local n (Lanius.Mini.Local.mk ((Lanius.Mini.kidToken x58 1).text) (((Lanius.Mini.kidToken x58 1).start) - x23.base) x1806) x38) + ((Cost_stmts_of n (x10 - 1) x23 ((Lanius.Mini.Local.mk ((Lanius.Mini.kidToken x58 1).text) (((Lanius.Mini.kidToken x58 1).start) - x23.base) x1806) :: x38) x68) + (Cost_let_of n (((Lanius.Mini.kidToken x58 1).start) - x23.base) x1806 (Lanius.Mini.letHeadOrEval ((x10 - 1)) x23 x38 x1806 ((Lanius.Mini.kid ((Lanius.Mini.kid x58 3)) 1))) (Lanius.Mini.stmtsOf ((x10 - 1)) x23 (((Lanius.Mini.Local.mk ((Lanius.Mini.kidToken x58 1).text) (((Lanius.Mini.kidToken x58 1).start) - x23.base) x1806) :: x38)) x68))))))))) | none => 0)); let k8 := (let k5 := ((Cost_untyped_head n (x10 - 1) x23 x38 (Lanius.Mini.kid ((Lanius.Mini.kid x58 3)) 1)) + (match (Lanius.Mini.untypedHead ((x10 - 1)) x23 x38 ((Lanius.Mini.kid ((Lanius.Mini.kid x58 3)) 1))) with | some x2884 => ((Cost_cons_of_mini_selfhost_Local n (Lanius.Mini.Local.mk ((Lanius.Mini.kidToken x58 1).text) (((Lanius.Mini.kidToken x58 1).start) - x23.base) x2884.ty) x38) + ((Cost_stmts_of n (x10 - 1) x23 ((Lanius.Mini.Local.mk ((Lanius.Mini.kidToken x58 1).text) (((Lanius.Mini.kidToken x58 1).start) - x23.base) x2884.ty) :: x38) x68) + (Cost_let_body n (((Lanius.Mini.kidToken x58 1).start) - x23.base) x2884.ty x2884.head (Lanius.Mini.stmtsOf ((x10 - 1)) x23 (((Lanius.Mini.Local.mk ((Lanius.Mini.kidToken x58 1).text) (((Lanius.Mini.kidToken x58 1).start) - x23.base) x2884.ty) :: x38)) x68)))) | none => 0)); let k6 := 0; (if (decide ((Lanius.Mini.nodeProd ((Lanius.Mini.kid x58 2))) = Lanius.Mini.Inline.pLetTypeNone)) = true then (if (decide ((Lanius.Mini.nodeProd ((Lanius.Mini.kid x58 3))) = Lanius.Mini.Inline.pLetInit)) = true then (if (!(Lanius.Mini.member x23.globals (((Lanius.Mini.kidToken x58 1).text)))) = true then (if (Lanius.Mini.freshId x38 ((((Lanius.Mini.kidToken x58 1).start) - x23.base))) = true then k5 else k6) else k6) else k6) else k6)); (if (decide ((Lanius.Mini.nodeProd ((Lanius.Mini.kid x58 2))) = Lanius.Mini.Inline.pLetType)) = true then (if (decide ((Lanius.Mini.nodeProd ((Lanius.Mini.kid x58 3))) = Lanius.Mini.Inline.pLetInit)) = true then (if (!(Lanius.Mini.member x23.globals (((Lanius.Mini.kidToken x58 1).text)))) = true then (if (Lanius.Mini.freshId x38 ((((Lanius.Mini.kidToken x58 1).start) - x23.base))) = true then k7 else k8) else k8) else k8) else k8)); (if (decide ((Lanius.Mini.nodeProd ((Lanius.Mini.kid x58 2))) = Lanius.Mini.Inline.pLetType)) = true then (if (decide ((Lanius.Mini.nodeProd ((Lanius.Mini.kid x58 3))) = Lanius.Mini.Inline.pLetInit)) = true then (if (!(Lanius.Mini.member x23.globals (((Lanius.Mini.kidToken x58 1).text)))) = true then (if (Lanius.Mini.freshId x38 ((((Lanius.Mini.kidToken x58 1).start) - x23.base))) = true then ((Cost_is_block_match n x10 (Lanius.Mini.kid ((Lanius.Mini.kid x58 3)) 1)) + (if (Lanius.Mini.isBlockMatch x10 ((Lanius.Mini.kid ((Lanius.Mini.kid x58 3)) 1))) = true then k9 else k10)) else k10) else k10) else k10) else k10)); (if (decide ((Lanius.Mini.nodeProd ((Lanius.Mini.kid x58 2))) = Lanius.Mini.Inline.pLetType)) = true then (if (decide ((Lanius.Mini.nodeProd ((Lanius.Mini.kid x58 3))) = Lanius.Mini.Inline.pLetInit)) = true then (if (!(Lanius.Mini.member x23.globals (((Lanius.Mini.kidToken x58 1).text)))) = true then (if (Lanius.Mini.freshId x38 ((((Lanius.Mini.kidToken x58 1).start) - x23.base))) = true then ((Cost_is_lit_init n x10 x23 x38 (Lanius.Mini.kid ((Lanius.Mini.kid x58 3)) 1)) + (if (Lanius.Mini.isLitInit x10 x23 x38 ((Lanius.Mini.kid ((Lanius.Mini.kid x58 3)) 1))) = true then k11 else k12)) else k12) else k12) else k12) else k12)))))
termination_by structural fuel => fuel

def Cost_stmt_of : Nat → Nat → Lanius.Mini.FrontEnv → List Lanius.Mini.Local → Lanius.Mini.CTree → Nat
  | 0, x8, x21, x36, x56 => 18446744073709551616
  | n + 1, x8, x21, x36, x56 => (if (decide (x8 = 0)) = true then 0 else (let k23 := (match (Lanius.Mini.matchInit ((x8 - 1)) ((Lanius.Mini.kid ((Lanius.Mini.kid x56 1)) 0))) with | some x441 => (Cost_lit_match_of n (x8 - 1) x21 x36 x441 Lanius.Mini.LitForm.litReturn) | none => 0); let k24 := (let k21 := (Cost_return_or_eval n (x8 - 1) x21 x36 (Lanius.Mini.kid ((Lanius.Mini.kid x56 1)) 0)); let k22 := (let k19 := 0; let k20 := (if (decide ((Lanius.Mini.nodeProd x56) = Lanius.Mini.Inline.pBreakStmt)) = true then 0 else (if (decide ((Lanius.Mini.nodeProd x56) = Lanius.Mini.Inline.pContinueStmt)) = true then 0 else (let k17 := ((Cost_block_of n (x8 - 1) x21 x36 (Lanius.Mini.kid ((Lanius.Mini.kid x56 4)) 1)) + ((Cost_block_of n (x8 - 1) x21 x36 (Lanius.Mini.kid ((Lanius.Mini.kid ((Lanius.Mini.kid x56 5)) 1)) 1)) + (Cost_if_or_eval n (x8 - 1) x21 x36 (Lanius.Mini.kid x56 2) (Lanius.Mini.blockOf ((x8 - 1)) x21 x36 ((Lanius.Mini.kid ((Lanius.Mini.kid x56 4)) 1))) (Lanius.Mini.blockOf ((x8 - 1)) x21 x36 ((Lanius.Mini.kid ((Lanius.Mini.kid ((Lanius.Mini.kid x56 5)) 1)) 1)))))); let k18 := (let k15 := ((Cost_block_of n (x8 - 1) x21 x36 (Lanius.Mini.kid ((Lanius.Mini.kid x56 4)) 1)) + (Cost_if_or_eval n (x8 - 1) x21 x36 (Lanius.Mini.kid x56 2) (Lanius.Mini.blockOf ((x8 - 1)) x21 x36 ((Lanius.Mini.kid ((Lanius.Mini.kid x56 4)) 1))) (some Lanius.Mini.MStmt.mNop))); let k16 := (if (decide ((Lanius.Mini.nodeProd x56) = Lanius.Mini.Inline.pWhileStmt)) = true then ((Cost_block_of n (x8 - 1) x21 x36 (Lanius.Mini.kid ((Lanius.Mini.kid x56 4)) 1)) + (Cost_while_or_eval n (x8 - 1) x21 x36 (Lanius.Mini.kid x56 2) (Lanius.Mini.blockOf ((x8 - 1)) x21 x36 ((Lanius.Mini.kid ((Lanius.Mini.kid x56 4)) 1))))) else (let k13 := (Cost_nested_of n (x8 - 1) x21 x36 x56); let k14 := (let k11 := (match (Lanius.Mini.matchPrimary ((x8 - 1)) ((Lanius.Mini.kid x56 0))) with | some x1709 => (Cost_lit_match_of n (x8 - 1) x21 x36 x1709 Lanius.Mini.LitForm.litStmt) | none => 0); let k12 := (let k9 := (Cost_match_stmt_of n (x8 - 1) x21 x36 (Lanius.Mini.kid x56 0)); let k10 := (if (decide ((Lanius.Mini.nodeProd x56) = Lanius.Mini.Inline.pExprStmt)) = true then (Cost_assignment n (x8 - 1) x21 x36 (Lanius.Mini.kid x56 0)) else 0); (if (decide ((Lanius.Mini.nodeProd x56) = Lanius.Mini.Inline.pExprStmt)) = true then (if (Lanius.Mini.isMatchStmt ((x8 - 1)) ((Lanius.Mini.kid x56 0))) = true then k9 else k10) else k10)); (if (decide ((Lanius.Mini.nodeProd x56) = Lanius.Mini.Inline.pExprStmt)) = true then (if (Lanius.Mini.isLitStmt ((x8 - 1)) ((Lanius.Mini.kid x56 0))) = true then k11 else k12) else k12)); (if (decide ((Lanius.Mini.nodeProd x56) = Lanius.Mini.Inline.pForStmt)) = true then k13 else (if (decide ((Lanius.Mini.nodeProd x56) = Lanius.Mini.Inline.pBlockStmt)) = true then k13 else k14)))); (if (decide ((Lanius.Mini.nodeProd x56) = Lanius.Mini.Inline.pIfStmt)) = true then (if (decide ((Lanius.Mini.nodeProd ((Lanius.Mini.kid x56 5))) = Lanius.Mini.Inline.pElseNone)) = true then k15 else k16) else k16)); (if (decide ((Lanius.Mini.nodeProd x56) = Lanius.Mini.Inline.pIfStmt)) = true then (if (decide ((Lanius.Mini.nodeProd ((Lanius.Mini.kid x56 5))) = Lanius.Mini.Inline.pElseStmt)) = true then k17 else k18) else k18)))); (if (decide ((Lanius.Mini.nodeProd x56) = Lanius.Mini.Inline.pReturnStmt)) = true then (if (decide ((Lanius.Mini.nodeProd ((Lanius.Mini.kid x56 1))) = Lanius.Mini.Inline.pReturnVoid)) = true then k19 else k20) else k20)); (if (decide ((Lanius.Mini.nodeProd x56) = Lanius.Mini.Inline.pReturnStmt)) = true then (if (decide ((Lanius.Mini.nodeProd ((Lanius.Mini.kid x56 1))) = Lanius.Mini.Inline.pReturnValue)) = true then k21 else k22) else k22)); (if (decide ((Lanius.Mini.nodeProd x56) = Lanius.Mini.Inline.pReturnStmt)) = true then (if (decide ((Lanius.Mini.nodeProd ((Lanius.Mini.kid x56 1))) = Lanius.Mini.Inline.pReturnValue)) = true then ((Cost_is_lit_init n (x8 - 1) x21 x36 (Lanius.Mini.kid ((Lanius.Mini.kid x56 1)) 0)) + (if (Lanius.Mini.isLitInit ((x8 - 1)) x21 x36 ((Lanius.Mini.kid ((Lanius.Mini.kid x56 1)) 0))) = true then k23 else k24)) else k24) else k24)))
termination_by structural fuel => fuel

def Cost_lit_let_of : Nat → Nat → Lanius.Mini.FrontEnv → List Lanius.Mini.Local → Lanius.Mini.Local → Lanius.Mini.CTree → Option Lanius.Mini.MStmt → Nat
  | 0, x11, x24, x39, x59, x69, x82 => 18446744073709551616
  | n + 1, x11, x24, x39, x59, x69, x82 => (if (decide (x11 = 0)) = true then 0 else (match x82 with | some x259 => (match (Lanius.Mini.matchInit x11 x69) with | some x341 => (Cost_lit_match_of n (x11 - 1) x24 x39 x341 (Lanius.Mini.LitForm.litLet x59 x259)) | none => 0) | none => 0))
termination_by structural fuel => fuel

def Cost_let_match_of : Nat → Nat → Lanius.Mini.FrontEnv → List Lanius.Mini.Local → Lanius.Mini.Local → Lanius.Mini.CTree → Option Lanius.Mini.MStmt → Nat
  | 0, x13, x26, x41, x61, x71, x84 => 18446744073709551616
  | n + 1, x13, x26, x41, x61, x71, x84 => (if (decide (x13 = 0)) = true then 0 else (match (Lanius.Mini.matchInit x13 x71) with | some x279 => ((Cost_match_stmt_parts n x13 x26 x41 x279) + (match (Lanius.Mini.matchStmtParts x13 x26 x41 x279) with | some x376 => ((Cost_stmt_arms n x13 x26 x376 x279) + (match (Lanius.Mini.stmtArms x13 x26 x376 x279) with | some x470 => (match x84 with | some x551 => ((Cost_let_arms_of n (x13 - 1) x26 x41 x376 x61 x551 0 x376.variants x470) + (Cost_match_stmt_value n x376 (Lanius.Mini.letArmsOf ((x13 - 1)) x26 x41 x376 x61 x551 0 x376.variants x470))) | none => 0) | none => 0)) | none => 0)) | none => 0))
termination_by structural fuel => fuel

def Cost_lit_match_of : Nat → Nat → Lanius.Mini.FrontEnv → List Lanius.Mini.Local → Lanius.Mini.CTree → Lanius.Mini.LitForm → Nat
  | 0, x13, x26, x41, x61, x71 => 18446744073709551616
  | n + 1, x13, x26, x41, x61, x71 => (if (decide (x13 = 0)) = true then 0 else ((Cost_lit_match_parts n x13 x26 x41 x61) + (match (Lanius.Mini.litMatchParts x13 x26 x41 x61) with | some x260 => ((Cost_list_items n x13 (Lanius.Mini.kid x61 5)) + (match (Lanius.Mini.listItems x13 ((Lanius.Mini.kid x61 5))) with | some x347 => ((Cost_lit_arms_of n (x13 - 1) x26 x41 x260 x71 false false x347) + (Cost_lit_bind n x260 (Lanius.Mini.litArmsOf ((x13 - 1)) x26 x41 x260 x71 false false x347))) | none => 0)) | none => 0)))
termination_by structural fuel => fuel

def Cost_nested_of : Nat → Nat → Lanius.Mini.FrontEnv → List Lanius.Mini.Local → Lanius.Mini.CTree → Nat
  | 0, x10, x23, x38, x58 => 18446744073709551616
  | n + 1, x10, x23, x38, x58 => (if (decide (x10 = 0)) = true then 0 else (if (decide ((Lanius.Mini.nodeProd x58) = Lanius.Mini.Inline.pForStmt)) = true then (Cost_for_of n (x10 - 1) x23 x38 x58) else (if (decide ((Lanius.Mini.nodeProd x58) = Lanius.Mini.Inline.pBlockStmt)) = true then (Cost_block_of n (x10 - 1) x23 x38 (Lanius.Mini.kid ((Lanius.Mini.kid x58 0)) 1)) else 0)))
termination_by structural fuel => fuel

def Cost_match_stmt_of : Nat → Nat → Lanius.Mini.FrontEnv → List Lanius.Mini.Local → Lanius.Mini.CTree → Nat
  | 0, x14, x27, x42, x62 => 18446744073709551616
  | n + 1, x14, x27, x42, x62 => (if (decide (x14 = 0)) = true then 0 else (match (Lanius.Mini.matchPrimary x14 x62) with | some x232 => ((Cost_match_stmt_parts n x14 x27 x42 x232) + (match (Lanius.Mini.matchStmtParts x14 x27 x42 x232) with | some x329 => ((Cost_stmt_arms n x14 x27 x329 x232) + (match (Lanius.Mini.stmtArms x14 x27 x329 x232) with | some x423 => ((Cost_match_arms_of n (x14 - 1) x27 x42 x329 0 x329.variants x423) + (Cost_match_stmt_value n x329 (Lanius.Mini.matchArmsOf ((x14 - 1)) x27 x42 x329 0 x329.variants x423))) | none => 0)) | none => 0)) | none => 0))
termination_by structural fuel => fuel

def Cost_let_arms_of : Nat → Nat → Lanius.Mini.FrontEnv → List Lanius.Mini.Local → Lanius.Mini.MatchStmt → Lanius.Mini.Local → Lanius.Mini.MStmt → Nat → List Lanius.Mini.VariantTy → List Lanius.Mini.CTree → Nat
  | 0, x12, x25, x40, x60, x74, x84, x97, x107, x134 => 18446744073709551616
  | n + 1, x12, x25, x40, x60, x74, x84, x97, x107, x134 => (if (decide (x12 = 0)) = true then 0 else (match x107 with | [] => 0 | x409 :: x412 => (match x134 with | [] => 0 | x476 :: x479 => ((Cost_let_arms_of n (x12 - 1) x25 x40 x60 x74 x84 (x97 + 1) x412 x479) + (Cost_let_arm_of n (x12 - 1) x25 x40 x60 x74 x84 x97 x409 x476 (Lanius.Mini.letArmsOf ((x12 - 1)) x25 x40 x60 x74 x84 ((x97 + 1)) x412 x479))))))
termination_by structural fuel => fuel

def Cost_lit_arms_of : Nat → Nat → Lanius.Mini.FrontEnv → List Lanius.Mini.Local → Lanius.Mini.LitMatch → Lanius.Mini.LitForm → Bool → Bool → List Lanius.Mini.CTree → Nat
  | 0, x12, x25, x40, x60, x73, x88, x102, x116 => 18446744073709551616
  | n + 1, x12, x25, x40, x60, x73, x88, x102, x116 => (if (decide (x12 = 0)) = true then 0 else (match x116 with | [] => 0 | x300 :: x303 => (Cost_lit_arm_of n (x12 - 1) x25 x40 x60 x73 x88 x102 x300 x303)))
termination_by structural fuel => fuel

def Cost_for_of : Nat → Nat → Lanius.Mini.FrontEnv → List Lanius.Mini.Local → Lanius.Mini.CTree → Nat
  | 0, x7, x21, x37, x58 => 18446744073709551616
  | n + 1, x7, x21, x37, x58 => (let k5 := (match (Lanius.Mini.findLocal x37 ((((Lanius.Mini.kidToken ((Lanius.Mini.kid ((Lanius.Mini.kid ((Lanius.Mini.kid ((Lanius.Mini.kid ((Lanius.Mini.kid x58 3)) 1)) 1)) 0)) 0)) 0)).text))) with | some x856 => ((Cost_int_literal n (((Lanius.Mini.kidToken ((Lanius.Mini.kid ((Lanius.Mini.kid x58 3)) 0)) 0)).text)) + (match (Lanius.Mini.intLiteral ((((Lanius.Mini.kidToken ((Lanius.Mini.kid ((Lanius.Mini.kid x58 3)) 0)) 0)).text))) with | some x968 => ((Cost_cons_of_mini_selfhost_Local n (Lanius.Mini.Local.mk ((Lanius.Mini.kidToken x58 1).text) ((((Lanius.Mini.kidToken x58 2)).start) - x21.base) x856.ty) x37) + ((Cost_block_of n x7 x21 ((Lanius.Mini.Local.mk ((Lanius.Mini.kidToken x58 1).text) ((((Lanius.Mini.kidToken x58 2)).start) - x21.base) x856.ty) :: x37) (Lanius.Mini.kid ((Lanius.Mini.kid x58 4)) 1)) + (Cost_for_range n ((((Lanius.Mini.kidToken x58 0)).start) - x21.base) (((Lanius.Mini.kidToken x58 1).start) - x21.base) ((((Lanius.Mini.kidToken x58 2)).start) - x21.base) x856.ty x968 x856.id (Lanius.Mini.blockOf x7 x21 (((Lanius.Mini.Local.mk ((Lanius.Mini.kidToken x58 1).text) ((((Lanius.Mini.kidToken x58 2)).start) - x21.base) x856.ty) :: x37)) ((Lanius.Mini.kid ((Lanius.Mini.kid x58 4)) 1)))))) | none => 0)) | none => 0); let k6 := (let k3 := (match (Lanius.Mini.pathName ((Lanius.Mini.kid ((Lanius.Mini.kid x58 3)) 0))) with | some x1562 => (match (Lanius.Mini.findLocal x37 x1562) with | some x1657 => (match (Lanius.Mini.arrayLocal x1657) with | some x2189 => ((Cost_cons_of_mini_selfhost_Local n (Lanius.Mini.Local.mk ((Lanius.Mini.kidToken x58 1).text) (((Lanius.Mini.kidToken x58 1).start) - x21.base) x2189.element) x37) + ((Cost_block_of n x7 x21 ((Lanius.Mini.Local.mk ((Lanius.Mini.kidToken x58 1).text) (((Lanius.Mini.kidToken x58 1).start) - x21.base) x2189.element) :: x37) (Lanius.Mini.kid ((Lanius.Mini.kid x58 4)) 1)) + (Cost_for_array n ((((Lanius.Mini.kidToken x58 0)).start) - x21.base) (((Lanius.Mini.kidToken x58 1).start) - x21.base) x2189 (Lanius.Mini.blockOf x7 x21 (((Lanius.Mini.Local.mk ((Lanius.Mini.kidToken x58 1).text) (((Lanius.Mini.kidToken x58 1).start) - x21.base) x2189.element) :: x37)) ((Lanius.Mini.kid ((Lanius.Mini.kid x58 4)) 1)))))) | none => (match (Lanius.Mini.sliceElem x1657.ty) with | some x1810 => ((Cost_cons_of_mini_selfhost_Local n (Lanius.Mini.Local.mk ((Lanius.Mini.kidToken x58 1).text) ((((Lanius.Mini.kidToken x58 2)).start) - x21.base) x1810) x37) + ((Cost_block_of n x7 x21 ((Lanius.Mini.Local.mk ((Lanius.Mini.kidToken x58 1).text) ((((Lanius.Mini.kidToken x58 2)).start) - x21.base) x1810) :: x37) (Lanius.Mini.kid ((Lanius.Mini.kid x58 4)) 1)) + (Cost_for_slice n (Lanius.Mini.freshId x37 (((((Lanius.Mini.kidToken x58 2)).start) - x21.base))) ((((Lanius.Mini.kidToken x58 0)).start) - x21.base) (((Lanius.Mini.kidToken x58 1).start) - x21.base) ((((Lanius.Mini.kidToken x58 2)).start) - x21.base) x1657.id x1810 (Lanius.Mini.blockOf x7 x21 (((Lanius.Mini.Local.mk ((Lanius.Mini.kidToken x58 1).text) ((((Lanius.Mini.kidToken x58 2)).start) - x21.base) x1810) :: x37)) ((Lanius.Mini.kid ((Lanius.Mini.kid x58 4)) 1)))))) | none => 0)) | none => 0) | none => 0); let k4 := 0; (if (decide ((Lanius.Mini.nodeProd ((Lanius.Mini.kid x58 3))) = Lanius.Mini.Inline.pForIterPath)) = true then (if (!(Lanius.Mini.member x21.globals (((Lanius.Mini.kidToken x58 1).text)))) = true then (if (Lanius.Mini.freshId x37 ((((Lanius.Mini.kidToken x58 1).start) - x21.base))) = true then (if (Lanius.Mini.freshId x37 (((((Lanius.Mini.kidToken x58 0)).start) - x21.base))) = true then k3 else k4) else k4) else k4) else k4)); (if (decide ((Lanius.Mini.nodeProd ((Lanius.Mini.kid x58 3))) = Lanius.Mini.Inline.pForIterRangeFromStart)) = true then (if (decide ((Lanius.Mini.nodeProd ((Lanius.Mini.kid ((Lanius.Mini.kid x58 3)) 0))) = Lanius.Mini.Inline.pRangeStartInt)) = true then (if (decide ((Lanius.Mini.nodeProd ((Lanius.Mini.kid ((Lanius.Mini.kid x58 3)) 1))) = Lanius.Mini.Inline.pRangeExclusive)) = true then (if (decide ((Lanius.Mini.nodeProd ((Lanius.Mini.kid ((Lanius.Mini.kid ((Lanius.Mini.kid x58 3)) 1)) 1))) = Lanius.Mini.Inline.pRangeBound)) = true then (if (decide ((Lanius.Mini.nodeProd ((Lanius.Mini.kid ((Lanius.Mini.kid ((Lanius.Mini.kid ((Lanius.Mini.kid x58 3)) 1)) 1)) 0))) = Lanius.Mini.Inline.pRangeBoundName)) = true then (if (decide ((Lanius.Mini.nodeProd ((Lanius.Mini.kid ((Lanius.Mini.kid ((Lanius.Mini.kid ((Lanius.Mini.kid ((Lanius.Mini.kid x58 3)) 1)) 1)) 0)) 1))) = Lanius.Mini.Inline.pPostfixEnd)) = true then (if (!(Lanius.Mini.member x21.globals (((Lanius.Mini.kidToken x58 1).text)))) = true then (if (Lanius.Mini.freshId x37 ((((Lanius.Mini.kidToken x58 1).start) - x21.base))) = true then (if (Lanius.Mini.freshId x37 (((((Lanius.Mini.kidToken x58 0)).start) - x21.base))) = true then (if (Lanius.Mini.freshId x37 (((((Lanius.Mini.kidToken x58 2)).start) - x21.base))) = true then k5 else k6) else k6) else k6) else k6) else k6) else k6) else k6) else k6) else k6) else k6))
termination_by structural fuel => fuel

def Cost_match_arms_of : Nat → Nat → Lanius.Mini.FrontEnv → List Lanius.Mini.Local → Lanius.Mini.MatchStmt → Nat → List Lanius.Mini.VariantTy → List Lanius.Mini.CTree → Nat
  | 0, x14, x27, x42, x62, x76, x86, x113 => 18446744073709551616
  | n + 1, x14, x27, x42, x62, x76, x86, x113 => (if (decide (x14 = 0)) = true then 0 else (match x86 with | [] => 0 | x388 :: x391 => (match x113 with | [] => 0 | x457 :: x460 => ((Cost_match_arms_of n (x14 - 1) x27 x42 x62 (x76 + 1) x391 x460) + (Cost_match_arm_of n (x14 - 1) x27 x42 x62 x76 x388 x457 (Lanius.Mini.matchArmsOf ((x14 - 1)) x27 x42 x62 ((x76 + 1)) x391 x460))))))
termination_by structural fuel => fuel

def Cost_let_arm_of : Nat → Nat → Lanius.Mini.FrontEnv → List Lanius.Mini.Local → Lanius.Mini.MatchStmt → Lanius.Mini.Local → Lanius.Mini.MStmt → Nat → Lanius.Mini.VariantTy → Lanius.Mini.CTree → Option Lanius.Mini.MStmt → Nat
  | 0, x11, x24, x39, x59, x73, x83, x96, x106, x120, x130 => 18446744073709551616
  | n + 1, x11, x24, x39, x59, x73, x83, x96, x106, x120, x130 => (if (decide (x11 = 0)) = true then 0 else ((Cost_arm_binding n x11 x24 x39 x59.owner x106 x120) + (match (Lanius.Mini.armBinding x11 x24 x39 x59.owner x106 x120) with | some x349 => (match (Lanius.Mini.armBlockList x11 x120) with | some x406 => ((Cost_block_of n (x11 - 1) x24 (Lanius.Mini.boundScope x349) x406) + (Cost_arm_stmt n x59 x96 x349 x106 (Lanius.Mini.blockOf ((x11 - 1)) x24 ((Lanius.Mini.boundScope x349)) x406) x130)) | none => ((Cost_let_body_of n (x11 - 1) x24 (Lanius.Mini.boundScope x349) x73 x83 x120) + (Cost_arm_stmt n x59 x96 x349 x106 (Lanius.Mini.letBodyOf ((x11 - 1)) x24 ((Lanius.Mini.boundScope x349)) x73 x83 x120) x130))) | none => 0)))
termination_by structural fuel => fuel

def Cost_lit_arm_of : Nat → Nat → Lanius.Mini.FrontEnv → List Lanius.Mini.Local → Lanius.Mini.LitMatch → Lanius.Mini.LitForm → Bool → Bool → Lanius.Mini.CTree → List Lanius.Mini.CTree → Nat
  | 0, x11, x24, x39, x59, x72, x87, x101, x115, x125 => 18446744073709551616
  | n + 1, x11, x24, x39, x59, x72, x87, x101, x115, x125 => (if (decide (x11 = 0)) = true then 0 else ((Cost_is_wild_arm n x115) + (if (Lanius.Mini.isWildArm x115) = true then (Cost_lit_body_of n (x11 - 1) x24 x39 x72 x115) else ((Cost_lit_cond n x59.scrutinee x59.sty (Lanius.Mini.kid x115 0)) + ((Cost_lit_body_of n (x11 - 1) x24 x39 x72 x115) + (if x87 = true then (if x101 = true then ((Cost_lit_arms_of n (x11 - 1) x24 x39 x59 x72 true true x125) + (Cost_lit_if n (Lanius.Mini.litCond x59.scrutinee x59.sty ((Lanius.Mini.kid x115 0))) (Lanius.Mini.litBodyOf ((x11 - 1)) x24 x39 x72 x115) (Lanius.Mini.litArmsOf ((x11 - 1)) x24 x39 x59 x72 true true x125))) else ((Cost_lit_arms_of n (x11 - 1) x24 x39 x59 x72 true (Lanius.Mini.isFalseArm x115) x125) + (Cost_lit_if n (Lanius.Mini.litCond x59.scrutinee x59.sty ((Lanius.Mini.kid x115 0))) (Lanius.Mini.litBodyOf ((x11 - 1)) x24 x39 x72 x115) (Lanius.Mini.litArmsOf ((x11 - 1)) x24 x39 x59 x72 true ((Lanius.Mini.isFalseArm x115)) x125)))) else (if x101 = true then ((Cost_lit_arms_of n (x11 - 1) x24 x39 x59 x72 (Lanius.Mini.isTrueArm x115) true x125) + (Cost_lit_if n (Lanius.Mini.litCond x59.scrutinee x59.sty ((Lanius.Mini.kid x115 0))) (Lanius.Mini.litBodyOf ((x11 - 1)) x24 x39 x72 x115) (Lanius.Mini.litArmsOf ((x11 - 1)) x24 x39 x59 x72 ((Lanius.Mini.isTrueArm x115)) true x125))) else ((Cost_lit_arms_of n (x11 - 1) x24 x39 x59 x72 (Lanius.Mini.isTrueArm x115) (Lanius.Mini.isFalseArm x115) x125) + (Cost_lit_if n (Lanius.Mini.litCond x59.scrutinee x59.sty ((Lanius.Mini.kid x115 0))) (Lanius.Mini.litBodyOf ((x11 - 1)) x24 x39 x72 x115) (Lanius.Mini.litArmsOf ((x11 - 1)) x24 x39 x59 x72 ((Lanius.Mini.isTrueArm x115)) ((Lanius.Mini.isFalseArm x115)) x125))))))))))
termination_by structural fuel => fuel

def Cost_match_arm_of : Nat → Nat → Lanius.Mini.FrontEnv → List Lanius.Mini.Local → Lanius.Mini.MatchStmt → Nat → Lanius.Mini.VariantTy → Lanius.Mini.CTree → Option Lanius.Mini.MStmt → Nat
  | 0, x13, x26, x41, x61, x75, x85, x99, x109 => 18446744073709551616
  | n + 1, x13, x26, x41, x61, x75, x85, x99, x109 => (if (decide (x13 = 0)) = true then 0 else ((Cost_arm_binding n x13 x26 x41 x61.owner x85 x99) + (match (Lanius.Mini.armBinding x13 x26 x41 x61.owner x85 x99) with | some x326 => ((Cost_arm_body_of n (x13 - 1) x26 (Lanius.Mini.boundScope x326) x99) + (Cost_arm_stmt n x61 x75 x326 x85 (Lanius.Mini.armBodyOf ((x13 - 1)) x26 ((Lanius.Mini.boundScope x326)) x99) x109)) | none => 0)))
termination_by structural fuel => fuel

def Cost_let_body_of : Nat → Nat → Lanius.Mini.FrontEnv → List Lanius.Mini.Local → Lanius.Mini.Local → Lanius.Mini.MStmt → Lanius.Mini.CTree → Nat
  | 0, x12, x25, x40, x60, x70, x83 => 18446744073709551616
  | n + 1, x12, x25, x40, x60, x70, x83 => (if (decide (x12 = 0)) = true then 0 else (if (decide ((Lanius.Mini.nodeProd ((Lanius.Mini.kid x83 2))) = Lanius.Mini.Inline.pMatchExpr)) = true then (Cost_inner_let_of n (x12 - 1) x25 x40 x60 x70 (Lanius.Mini.kid x83 2)) else ((Cost_let_head_or_eval n (x12 - 1) x25 x40 (Lanius.Mini.localTyOf x60) (Lanius.Mini.kid x83 2)) + (Cost_let_of n (Lanius.Mini.localIdOf x60) (Lanius.Mini.localTyOf x60) (Lanius.Mini.letHeadOrEval ((x12 - 1)) x25 x40 ((Lanius.Mini.localTyOf x60)) ((Lanius.Mini.kid x83 2))) (some x70)))))
termination_by structural fuel => fuel

def Cost_lit_body_of : Nat → Nat → Lanius.Mini.FrontEnv → List Lanius.Mini.Local → Lanius.Mini.LitForm → Lanius.Mini.CTree → Nat
  | 0, x12, x25, x40, x60, x75 => 18446744073709551616
  | n + 1, x12, x25, x40, x60, x75 => (if (decide (x12 = 0)) = true then 0 else (match (Lanius.Mini.armBlockList x12 x75) with | some x224 => (Cost_block_of n (x12 - 1) x25 x40 x224) | none => (match x60 with | .litStmt => 0 | .litLet x356 x359 => ((Cost_let_head_or_eval n (x12 - 1) x25 x40 (Lanius.Mini.localTyOf x356) (Lanius.Mini.kid x75 2)) + (Cost_let_of n (Lanius.Mini.localIdOf x356) (Lanius.Mini.localTyOf x356) (Lanius.Mini.letHeadOrEval ((x12 - 1)) x25 x40 ((Lanius.Mini.localTyOf x356)) ((Lanius.Mini.kid x75 2))) (some x359))) | .litReturn => (Cost_return_or_eval n (x12 - 1) x25 x40 (Lanius.Mini.kid x75 2)))))
termination_by structural fuel => fuel

def Cost_arm_body_of : Nat → Nat → Lanius.Mini.FrontEnv → List Lanius.Mini.Local → Lanius.Mini.CTree → Nat
  | 0, x12, x25, x40, x60 => 18446744073709551616
  | n + 1, x12, x25, x40, x60 => (if (decide (x12 = 0)) = true then 0 else (match (Lanius.Mini.armBlockList x12 x60) with | some x209 => (Cost_block_of n (x12 - 1) x25 x40 x209) | none => (Cost_inner_match_of n (x12 - 1) x25 x40 (Lanius.Mini.kid x60 2))))
termination_by structural fuel => fuel

def Cost_inner_let_of : Nat → Nat → Lanius.Mini.FrontEnv → List Lanius.Mini.Local → Lanius.Mini.Local → Lanius.Mini.MStmt → Lanius.Mini.CTree → Nat
  | 0, x13, x26, x41, x61, x71, x84 => 18446744073709551616
  | n + 1, x13, x26, x41, x61, x71, x84 => (if (decide (x13 = 0)) = true then 0 else ((Cost_match_stmt_parts n x13 x26 x41 x84) + (match (Lanius.Mini.matchStmtParts x13 x26 x41 x84) with | some x269 => ((Cost_stmt_arms n x13 x26 x269 x84) + (match (Lanius.Mini.stmtArms x13 x26 x269 x84) with | some x355 => ((Cost_let_arms_of n (x13 - 1) x26 x41 x269 x61 x71 0 x269.variants x355) + (Cost_match_stmt_value n x269 (Lanius.Mini.letArmsOf ((x13 - 1)) x26 x41 x269 x61 x71 0 x269.variants x355))) | none => 0)) | none => 0)))
termination_by structural fuel => fuel

def Cost_inner_match_of : Nat → Nat → Lanius.Mini.FrontEnv → List Lanius.Mini.Local → Lanius.Mini.CTree → Nat
  | 0, x15, x28, x43, x63 => 18446744073709551616
  | n + 1, x15, x28, x43, x63 => (if (decide (x15 = 0)) = true then 0 else (if (decide ((Lanius.Mini.nodeProd x63) = Lanius.Mini.Inline.pMatchExpr)) = true then ((Cost_match_stmt_parts n x15 x28 x43 x63) + (match (Lanius.Mini.matchStmtParts x15 x28 x43 x63) with | some x302 => ((Cost_stmt_arms n x15 x28 x302 x63) + (match (Lanius.Mini.stmtArms x15 x28 x302 x63) with | some x396 => ((Cost_match_arms_of n (x15 - 1) x28 x43 x302 0 x302.variants x396) + (Cost_match_stmt_value n x302 (Lanius.Mini.matchArmsOf ((x15 - 1)) x28 x43 x302 0 x302.variants x396))) | none => 0)) | none => 0)) else 0))
termination_by structural fuel => fuel
end

end
noncomputable section

mutual
def Pre_block_of : Nat → Nat → Lanius.Mini.FrontEnv → List Lanius.Mini.Local → Lanius.Mini.CTree → Nat → Prop
  | 0, x9, x22, x37, x57, b => True
  | n + 1, x9, x22, x37, x57, b => (if (decide (x9 = 0)) = true then True else (∀ b1 : Nat, (Cost_list_items n x9 x57) < b → b1 = b - (Cost_list_items n x9 x57) → (match (Lanius.Mini.listItems x9 x57) with | some x230 => (Pre_stmts_of n (x9 - 1) x22 x37 x230 b1) | none => True)))
termination_by structural fuel => fuel

def Pre_stmts_of : Nat → Nat → Lanius.Mini.FrontEnv → List Lanius.Mini.Local → List Lanius.Mini.CTree → Nat → Prop
  | 0, x9, x22, x37, x57, b => True
  | n + 1, x9, x22, x37, x57, b => (if (decide (x9 = 0)) = true then True else (match x57 with | [] => True | x225 :: x228 => (Pre_stmt_first n (x9 - 1) x22 x37 x225 x228 b)))
termination_by structural fuel => fuel

def Pre_stmt_first : Nat → Nat → Lanius.Mini.FrontEnv → List Lanius.Mini.Local → Lanius.Mini.CTree → List Lanius.Mini.CTree → Nat → Prop
  | 0, x11, x24, x39, x59, x69, b => True
  | n + 1, x11, x24, x39, x59, x69, b => (if (decide (x11 = 0)) = true then True else (if (decide ((Lanius.Mini.nodeProd x59) = Lanius.Mini.Inline.pLetStmt)) = true then (Pre_let_first n (x11 - 1) x24 x39 x59 x69 b) else (match x69 with | [] => (Pre_stmt_of n (x11 - 1) x24 x39 x59 b) | x372 :: x378 => ((Pre_stmt_of n (x11 - 1) x24 x39 x59 b) ∧ (∀ b3 : Nat, (Cost_stmt_of n (x11 - 1) x24 x39 x59) < b → b3 = b - (Cost_stmt_of n (x11 - 1) x24 x39 x59) → (Pre_stmts_of n (x11 - 1) x24 x39 x69 b3))))))
termination_by structural fuel => fuel

def Pre_let_first : Nat → Nat → Lanius.Mini.FrontEnv → List Lanius.Mini.Local → Lanius.Mini.CTree → List Lanius.Mini.CTree → Nat → Prop
  | 0, x10, x23, x38, x58, x68, b => True
  | n + 1, x10, x23, x38, x58, x68, b => (if (decide (x10 = 0)) = true then True else (∀ b1 : Nat, (Cost_is_str_let n x10 x23 x38 x58) < b → b1 = b - (Cost_is_str_let n x10 x23 x38 x58) → (if (Lanius.Mini.isStrLet x10 x23 x38 x58) = true then (Pre_string_let n (x10 - 1) x23 (((Lanius.Mini.kidToken x58 1).start) - x23.base) ((Lanius.Mini.kidToken x58 1).text) (Lanius.Mini.kid ((Lanius.Mini.kid x58 3)) 1) x68 b1) else (let k45 := fun (b3 : Nat) => ((Pre_ty_of n x10 x23 (Lanius.Mini.kid ((Lanius.Mini.kid x58 2)) 1) b3) ∧ (∀ b4 : Nat, (Cost_ty_of n x10 x23 (Lanius.Mini.kid ((Lanius.Mini.kid x58 2)) 1)) < b3 → b4 = b3 - (Cost_ty_of n x10 x23 (Lanius.Mini.kid ((Lanius.Mini.kid x58 2)) 1)) → (match (Lanius.Mini.tyOf x10 x23 ((Lanius.Mini.kid ((Lanius.Mini.kid x58 2)) 1))) with | some x691 => (∀ b5 : Nat, (Cost_cons_of_mini_selfhost_Local n (Lanius.Mini.Local.mk ((Lanius.Mini.kidToken x58 1).text) (((Lanius.Mini.kidToken x58 1).start) - x23.base) x691) x38) < b4 → b5 = b4 - (Cost_cons_of_mini_selfhost_Local n (Lanius.Mini.Local.mk ((Lanius.Mini.kidToken x58 1).text) (((Lanius.Mini.kidToken x58 1).start) - x23.base) x691) x38) → ((Pre_stmts_of n (x10 - 1) x23 ((Lanius.Mini.Local.mk ((Lanius.Mini.kidToken x58 1).text) (((Lanius.Mini.kidToken x58 1).start) - x23.base) x691) :: x38) x68 b5) ∧ (∀ b6 : Nat, (Cost_stmts_of n (x10 - 1) x23 ((Lanius.Mini.Local.mk ((Lanius.Mini.kidToken x58 1).text) (((Lanius.Mini.kidToken x58 1).start) - x23.base) x691) :: x38) x68) < b5 → b6 = b5 - (Cost_stmts_of n (x10 - 1) x23 ((Lanius.Mini.Local.mk ((Lanius.Mini.kidToken x58 1).text) (((Lanius.Mini.kidToken x58 1).start) - x23.base) x691) :: x38) x68) → (Pre_lit_let_of n (x10 - 1) x23 x38 (Lanius.Mini.Local.mk ((Lanius.Mini.kidToken x58 1).text) (((Lanius.Mini.kidToken x58 1).start) - x23.base) x691) (Lanius.Mini.kid ((Lanius.Mini.kid x58 3)) 1) (Lanius.Mini.stmtsOf ((x10 - 1)) x23 (((Lanius.Mini.Local.mk ((Lanius.Mini.kidToken x58 1).text) (((Lanius.Mini.kidToken x58 1).start) - x23.base) x691) :: x38)) x68) b6)))) | none => True))); let k46 := fun (b3 : Nat) => (let k35 := fun (b8 : Nat) => ((Pre_ty_of n x10 x23 (Lanius.Mini.kid ((Lanius.Mini.kid x58 2)) 1) b8) ∧ (∀ b9 : Nat, (Cost_ty_of n x10 x23 (Lanius.Mini.kid ((Lanius.Mini.kid x58 2)) 1)) < b8 → b9 = b8 - (Cost_ty_of n x10 x23 (Lanius.Mini.kid ((Lanius.Mini.kid x58 2)) 1)) → (match (Lanius.Mini.tyOf x10 x23 ((Lanius.Mini.kid ((Lanius.Mini.kid x58 2)) 1))) with | some x1269 => (∀ b10 : Nat, (Cost_cons_of_mini_selfhost_Local n (Lanius.Mini.Local.mk ((Lanius.Mini.kidToken x58 1).text) (((Lanius.Mini.kidToken x58 1).start) - x23.base) x1269) x38) < b9 → b10 = b9 - (Cost_cons_of_mini_selfhost_Local n (Lanius.Mini.Local.mk ((Lanius.Mini.kidToken x58 1).text) (((Lanius.Mini.kidToken x58 1).start) - x23.base) x1269) x38) → ((Pre_stmts_of n (x10 - 1) x23 ((Lanius.Mini.Local.mk ((Lanius.Mini.kidToken x58 1).text) (((Lanius.Mini.kidToken x58 1).start) - x23.base) x1269) :: x38) x68 b10) ∧ (∀ b11 : Nat, (Cost_stmts_of n (x10 - 1) x23 ((Lanius.Mini.Local.mk ((Lanius.Mini.kidToken x58 1).text) (((Lanius.Mini.kidToken x58 1).start) - x23.base) x1269) :: x38) x68) < b10 → b11 = b10 - (Cost_stmts_of n (x10 - 1) x23 ((Lanius.Mini.Local.mk ((Lanius.Mini.kidToken x58 1).text) (((Lanius.Mini.kidToken x58 1).start) - x23.base) x1269) :: x38) x68) → (Pre_let_match_of n (x10 - 1) x23 x38 (Lanius.Mini.Local.mk ((Lanius.Mini.kidToken x58 1).text) (((Lanius.Mini.kidToken x58 1).start) - x23.base) x1269) (Lanius.Mini.kid ((Lanius.Mini.kid x58 3)) 1) (Lanius.Mini.stmtsOf ((x10 - 1)) x23 (((Lanius.Mini.Local.mk ((Lanius.Mini.kidToken x58 1).text) (((Lanius.Mini.kidToken x58 1).start) - x23.base) x1269) :: x38)) x68) b11)))) | none => True))); let k36 := fun (b8 : Nat) => (let k33 := fun (b13 : Nat) => ((Pre_ty_of n x10 x23 (Lanius.Mini.kid ((Lanius.Mini.kid x58 2)) 1) b13) ∧ (∀ b14 : Nat, (Cost_ty_of n x10 x23 (Lanius.Mini.kid ((Lanius.Mini.kid x58 2)) 1)) < b13 → b14 = b13 - (Cost_ty_of n x10 x23 (Lanius.Mini.kid ((Lanius.Mini.kid x58 2)) 1)) → (match (Lanius.Mini.tyOf x10 x23 ((Lanius.Mini.kid ((Lanius.Mini.kid x58 2)) 1))) with | some x1806 => (∀ b15 : Nat, (Cost_cons_of_mini_selfhost_Local n (Lanius.Mini.Local.mk ((Lanius.Mini.kidToken x58 1).text) (((Lanius.Mini.kidToken x58 1).start) - x23.base) x1806) x38) < b14 → b15 = b14 - (Cost_cons_of_mini_selfhost_Local n (Lanius.Mini.Local.mk ((Lanius.Mini.kidToken x58 1).text) (((Lanius.Mini.kidToken x58 1).start) - x23.base) x1806) x38) → ((Pre_let_head_or_eval n (x10 - 1) x23 x38 x1806 (Lanius.Mini.kid ((Lanius.Mini.kid x58 3)) 1) b15) ∧ (∀ b16 : Nat, (Cost_let_head_or_eval n (x10 - 1) x23 x38 x1806 (Lanius.Mini.kid ((Lanius.Mini.kid x58 3)) 1)) < b15 → b16 = b15 - (Cost_let_head_or_eval n (x10 - 1) x23 x38 x1806 (Lanius.Mini.kid ((Lanius.Mini.kid x58 3)) 1)) → ((Pre_view_read n (x10 - 1) x23 ((Lanius.Mini.Local.mk ((Lanius.Mini.kidToken x58 1).text) (((Lanius.Mini.kidToken x58 1).start) - x23.base) x1806) :: x38) (Lanius.Mini.Local.mk ((Lanius.Mini.kidToken x58 1).text) (((Lanius.Mini.kidToken x58 1).start) - x23.base) x1806) (Lanius.Mini.letHeadOrEval ((x10 - 1)) x23 x38 x1806 ((Lanius.Mini.kid ((Lanius.Mini.kid x58 3)) 1))) x68 b16) ∧ (∀ b17 : Nat, (Cost_view_read n (x10 - 1) x23 ((Lanius.Mini.Local.mk ((Lanius.Mini.kidToken x58 1).text) (((Lanius.Mini.kidToken x58 1).start) - x23.base) x1806) :: x38) (Lanius.Mini.Local.mk ((Lanius.Mini.kidToken x58 1).text) (((Lanius.Mini.kidToken x58 1).start) - x23.base) x1806) (Lanius.Mini.letHeadOrEval ((x10 - 1)) x23 x38 x1806 ((Lanius.Mini.kid ((Lanius.Mini.kid x58 3)) 1))) x68) < b16 → b17 = b16 - (Cost_view_read n (x10 - 1) x23 ((Lanius.Mini.Local.mk ((Lanius.Mini.kidToken x58 1).text) (((Lanius.Mini.kidToken x58 1).start) - x23.base) x1806) :: x38) (Lanius.Mini.Local.mk ((Lanius.Mini.kidToken x58 1).text) (((Lanius.Mini.kidToken x58 1).start) - x23.base) x1806) (Lanius.Mini.letHeadOrEval ((x10 - 1)) x23 x38 x1806 ((Lanius.Mini.kid ((Lanius.Mini.kid x58 3)) 1))) x68) → (match (Lanius.Mini.viewRead ((x10 - 1)) x23 (((Lanius.Mini.Local.mk ((Lanius.Mini.kidToken x58 1).text) (((Lanius.Mini.kidToken x58 1).start) - x23.base) x1806) :: x38)) ((Lanius.Mini.Local.mk ((Lanius.Mini.kidToken x58 1).text) (((Lanius.Mini.kidToken x58 1).start) - x23.base) x1806)) ((Lanius.Mini.letHeadOrEval ((x10 - 1)) x23 x38 x1806 ((Lanius.Mini.kid ((Lanius.Mini.kid x58 3)) 1)))) x68) with | some x2091 => (∀ b18 : Nat, (Cost_cons_of_mini_selfhost_Local n (Lanius.Mini.Local.mk ((Lanius.Mini.kidToken x58 1).text) (((Lanius.Mini.kidToken x58 1).start) - x23.base) x1806) x38) < b17 → b18 = b17 - (Cost_cons_of_mini_selfhost_Local n (Lanius.Mini.Local.mk ((Lanius.Mini.kidToken x58 1).text) (((Lanius.Mini.kidToken x58 1).start) - x23.base) x1806) x38) → (∀ b19 : Nat, (Cost_cons_of_mini_selfhost_Local n x2091.pointer ((Lanius.Mini.Local.mk ((Lanius.Mini.kidToken x58 1).text) (((Lanius.Mini.kidToken x58 1).start) - x23.base) x1806) :: x38)) < b18 → b19 = b18 - (Cost_cons_of_mini_selfhost_Local n x2091.pointer ((Lanius.Mini.Local.mk ((Lanius.Mini.kidToken x58 1).text) (((Lanius.Mini.kidToken x58 1).start) - x23.base) x1806) :: x38)) → (Pre_stmts_of n (x10 - 1) x23 (x2091.pointer :: ((Lanius.Mini.Local.mk ((Lanius.Mini.kidToken x58 1).text) (((Lanius.Mini.kidToken x58 1).start) - x23.base) x1806) :: x38)) x2091.more b19))) | none => ((Pre_let_head_or_eval n (x10 - 1) x23 x38 x1806 (Lanius.Mini.kid ((Lanius.Mini.kid x58 3)) 1) b17) ∧ (∀ b22 : Nat, (Cost_let_head_or_eval n (x10 - 1) x23 x38 x1806 (Lanius.Mini.kid ((Lanius.Mini.kid x58 3)) 1)) < b17 → b22 = b17 - (Cost_let_head_or_eval n (x10 - 1) x23 x38 x1806 (Lanius.Mini.kid ((Lanius.Mini.kid x58 3)) 1)) → (∀ b23 : Nat, (Cost_cons_of_mini_selfhost_Local n (Lanius.Mini.Local.mk ((Lanius.Mini.kidToken x58 1).text) (((Lanius.Mini.kidToken x58 1).start) - x23.base) x1806) x38) < b22 → b23 = b22 - (Cost_cons_of_mini_selfhost_Local n (Lanius.Mini.Local.mk ((Lanius.Mini.kidToken x58 1).text) (((Lanius.Mini.kidToken x58 1).start) - x23.base) x1806) x38) → (Pre_stmts_of n (x10 - 1) x23 ((Lanius.Mini.Local.mk ((Lanius.Mini.kidToken x58 1).text) (((Lanius.Mini.kidToken x58 1).start) - x23.base) x1806) :: x38) x68 b23)))))))))) | none => True))); let k34 := fun (b13 : Nat) => (let k31 := fun (b26 : Nat) => ((Pre_untyped_head n (x10 - 1) x23 x38 (Lanius.Mini.kid ((Lanius.Mini.kid x58 3)) 1) b26) ∧ (∀ b27 : Nat, (Cost_untyped_head n (x10 - 1) x23 x38 (Lanius.Mini.kid ((Lanius.Mini.kid x58 3)) 1)) < b26 → b27 = b26 - (Cost_untyped_head n (x10 - 1) x23 x38 (Lanius.Mini.kid ((Lanius.Mini.kid x58 3)) 1)) → (match (Lanius.Mini.untypedHead ((x10 - 1)) x23 x38 ((Lanius.Mini.kid ((Lanius.Mini.kid x58 3)) 1))) with | some x2884 => (∀ b28 : Nat, (Cost_cons_of_mini_selfhost_Local n (Lanius.Mini.Local.mk ((Lanius.Mini.kidToken x58 1).text) (((Lanius.Mini.kidToken x58 1).start) - x23.base) x2884.ty) x38) < b27 → b28 = b27 - (Cost_cons_of_mini_selfhost_Local n (Lanius.Mini.Local.mk ((Lanius.Mini.kidToken x58 1).text) (((Lanius.Mini.kidToken x58 1).start) - x23.base) x2884.ty) x38) → (Pre_stmts_of n (x10 - 1) x23 ((Lanius.Mini.Local.mk ((Lanius.Mini.kidToken x58 1).text) (((Lanius.Mini.kidToken x58 1).start) - x23.base) x2884.ty) :: x38) x68 b28)) | none => True))); let k32 := fun (b26 : Nat) => True; (if (decide ((Lanius.Mini.nodeProd ((Lanius.Mini.kid x58 2))) = Lanius.Mini.Inline.pLetTypeNone)) = true then (if (decide ((Lanius.Mini.nodeProd ((Lanius.Mini.kid x58 3))) = Lanius.Mini.Inline.pLetInit)) = true then (if (!(Lanius.Mini.member x23.globals (((Lanius.Mini.kidToken x58 1).text)))) = true then (if (Lanius.Mini.freshId x38 ((((Lanius.Mini.kidToken x58 1).start) - x23.base))) = true then (k31 b13) else (k32 b13)) else (k32 b13)) else (k32 b13)) else (k32 b13))); (if (decide ((Lanius.Mini.nodeProd ((Lanius.Mini.kid x58 2))) = Lanius.Mini.Inline.pLetType)) = true then (if (decide ((Lanius.Mini.nodeProd ((Lanius.Mini.kid x58 3))) = Lanius.Mini.Inline.pLetInit)) = true then (if (!(Lanius.Mini.member x23.globals (((Lanius.Mini.kidToken x58 1).text)))) = true then (if (Lanius.Mini.freshId x38 ((((Lanius.Mini.kidToken x58 1).start) - x23.base))) = true then (k33 b8) else (k34 b8)) else (k34 b8)) else (k34 b8)) else (k34 b8))); (if (decide ((Lanius.Mini.nodeProd ((Lanius.Mini.kid x58 2))) = Lanius.Mini.Inline.pLetType)) = true then (if (decide ((Lanius.Mini.nodeProd ((Lanius.Mini.kid x58 3))) = Lanius.Mini.Inline.pLetInit)) = true then (if (!(Lanius.Mini.member x23.globals (((Lanius.Mini.kidToken x58 1).text)))) = true then (if (Lanius.Mini.freshId x38 ((((Lanius.Mini.kidToken x58 1).start) - x23.base))) = true then ((Pre_is_block_match n x10 (Lanius.Mini.kid ((Lanius.Mini.kid x58 3)) 1) b3) ∧ (∀ b44 : Nat, (Cost_is_block_match n x10 (Lanius.Mini.kid ((Lanius.Mini.kid x58 3)) 1)) < b3 → b44 = b3 - (Cost_is_block_match n x10 (Lanius.Mini.kid ((Lanius.Mini.kid x58 3)) 1)) → (if (Lanius.Mini.isBlockMatch x10 ((Lanius.Mini.kid ((Lanius.Mini.kid x58 3)) 1))) = true then (k35 b44) else (k36 b44)))) else (k36 b3)) else (k36 b3)) else (k36 b3)) else (k36 b3))); (if (decide ((Lanius.Mini.nodeProd ((Lanius.Mini.kid x58 2))) = Lanius.Mini.Inline.pLetType)) = true then (if (decide ((Lanius.Mini.nodeProd ((Lanius.Mini.kid x58 3))) = Lanius.Mini.Inline.pLetInit)) = true then (if (!(Lanius.Mini.member x23.globals (((Lanius.Mini.kidToken x58 1).text)))) = true then (if (Lanius.Mini.freshId x38 ((((Lanius.Mini.kidToken x58 1).start) - x23.base))) = true then (∀ b54 : Nat, (Cost_is_lit_init n x10 x23 x38 (Lanius.Mini.kid ((Lanius.Mini.kid x58 3)) 1)) < b1 → b54 = b1 - (Cost_is_lit_init n x10 x23 x38 (Lanius.Mini.kid ((Lanius.Mini.kid x58 3)) 1)) → (if (Lanius.Mini.isLitInit x10 x23 x38 ((Lanius.Mini.kid ((Lanius.Mini.kid x58 3)) 1))) = true then (k45 b54) else (k46 b54))) else (k46 b1)) else (k46 b1)) else (k46 b1)) else (k46 b1))))))
termination_by structural fuel => fuel

def Pre_stmt_of : Nat → Nat → Lanius.Mini.FrontEnv → List Lanius.Mini.Local → Lanius.Mini.CTree → Nat → Prop
  | 0, x8, x21, x36, x56, b => True
  | n + 1, x8, x21, x36, x56, b => (if (decide (x8 = 0)) = true then True else (let k36 := fun (b1 : Nat) => (match (Lanius.Mini.matchInit ((x8 - 1)) ((Lanius.Mini.kid ((Lanius.Mini.kid x56 1)) 0))) with | some x441 => (Pre_lit_match_of n (x8 - 1) x21 x36 x441 Lanius.Mini.LitForm.litReturn b1) | none => True); let k37 := fun (b1 : Nat) => (let k34 := fun (b3 : Nat) => (Pre_return_or_eval n (x8 - 1) x21 x36 (Lanius.Mini.kid ((Lanius.Mini.kid x56 1)) 0) b3); let k35 := fun (b3 : Nat) => (let k32 := fun (b5 : Nat) => True; let k33 := fun (b5 : Nat) => (if (decide ((Lanius.Mini.nodeProd x56) = Lanius.Mini.Inline.pBreakStmt)) = true then True else (if (decide ((Lanius.Mini.nodeProd x56) = Lanius.Mini.Inline.pContinueStmt)) = true then True else (let k30 := fun (b6 : Nat) => ((Pre_block_of n (x8 - 1) x21 x36 (Lanius.Mini.kid ((Lanius.Mini.kid x56 4)) 1) b6) ∧ (∀ b7 : Nat, (Cost_block_of n (x8 - 1) x21 x36 (Lanius.Mini.kid ((Lanius.Mini.kid x56 4)) 1)) < b6 → b7 = b6 - (Cost_block_of n (x8 - 1) x21 x36 (Lanius.Mini.kid ((Lanius.Mini.kid x56 4)) 1)) → ((Pre_block_of n (x8 - 1) x21 x36 (Lanius.Mini.kid ((Lanius.Mini.kid ((Lanius.Mini.kid x56 5)) 1)) 1) b7) ∧ (∀ b8 : Nat, (Cost_block_of n (x8 - 1) x21 x36 (Lanius.Mini.kid ((Lanius.Mini.kid ((Lanius.Mini.kid x56 5)) 1)) 1)) < b7 → b8 = b7 - (Cost_block_of n (x8 - 1) x21 x36 (Lanius.Mini.kid ((Lanius.Mini.kid ((Lanius.Mini.kid x56 5)) 1)) 1)) → (Pre_if_or_eval n (x8 - 1) x21 x36 (Lanius.Mini.kid x56 2) (Lanius.Mini.blockOf ((x8 - 1)) x21 x36 ((Lanius.Mini.kid ((Lanius.Mini.kid x56 4)) 1))) (Lanius.Mini.blockOf ((x8 - 1)) x21 x36 ((Lanius.Mini.kid ((Lanius.Mini.kid ((Lanius.Mini.kid x56 5)) 1)) 1))) b8))))); let k31 := fun (b6 : Nat) => (let k28 := fun (b10 : Nat) => ((Pre_block_of n (x8 - 1) x21 x36 (Lanius.Mini.kid ((Lanius.Mini.kid x56 4)) 1) b10) ∧ (∀ b11 : Nat, (Cost_block_of n (x8 - 1) x21 x36 (Lanius.Mini.kid ((Lanius.Mini.kid x56 4)) 1)) < b10 → b11 = b10 - (Cost_block_of n (x8 - 1) x21 x36 (Lanius.Mini.kid ((Lanius.Mini.kid x56 4)) 1)) → (Pre_if_or_eval n (x8 - 1) x21 x36 (Lanius.Mini.kid x56 2) (Lanius.Mini.blockOf ((x8 - 1)) x21 x36 ((Lanius.Mini.kid ((Lanius.Mini.kid x56 4)) 1))) (some Lanius.Mini.MStmt.mNop) b11))); let k29 := fun (b10 : Nat) => (if (decide ((Lanius.Mini.nodeProd x56) = Lanius.Mini.Inline.pWhileStmt)) = true then ((Pre_block_of n (x8 - 1) x21 x36 (Lanius.Mini.kid ((Lanius.Mini.kid x56 4)) 1) b10) ∧ (∀ b13 : Nat, (Cost_block_of n (x8 - 1) x21 x36 (Lanius.Mini.kid ((Lanius.Mini.kid x56 4)) 1)) < b10 → b13 = b10 - (Cost_block_of n (x8 - 1) x21 x36 (Lanius.Mini.kid ((Lanius.Mini.kid x56 4)) 1)) → (Pre_while_or_eval n (x8 - 1) x21 x36 (Lanius.Mini.kid x56 2) (Lanius.Mini.blockOf ((x8 - 1)) x21 x36 ((Lanius.Mini.kid ((Lanius.Mini.kid x56 4)) 1))) b13))) else (let k26 := fun (b15 : Nat) => (Pre_nested_of n (x8 - 1) x21 x36 x56 b15); let k27 := fun (b15 : Nat) => (let k24 := fun (b17 : Nat) => (match (Lanius.Mini.matchPrimary ((x8 - 1)) ((Lanius.Mini.kid x56 0))) with | some x1709 => (Pre_lit_match_of n (x8 - 1) x21 x36 x1709 Lanius.Mini.LitForm.litStmt b17) | none => True); let k25 := fun (b17 : Nat) => (let k22 := fun (b19 : Nat) => (Pre_match_stmt_of n (x8 - 1) x21 x36 (Lanius.Mini.kid x56 0) b19); let k23 := fun (b19 : Nat) => (if (decide ((Lanius.Mini.nodeProd x56) = Lanius.Mini.Inline.pExprStmt)) = true then (Pre_assignment n (x8 - 1) x21 x36 (Lanius.Mini.kid x56 0) b19) else True); (if (decide ((Lanius.Mini.nodeProd x56) = Lanius.Mini.Inline.pExprStmt)) = true then (if (Lanius.Mini.isMatchStmt ((x8 - 1)) ((Lanius.Mini.kid x56 0))) = true then (k22 b17) else (k23 b17)) else (k23 b17))); (if (decide ((Lanius.Mini.nodeProd x56) = Lanius.Mini.Inline.pExprStmt)) = true then (if (Lanius.Mini.isLitStmt ((x8 - 1)) ((Lanius.Mini.kid x56 0))) = true then (k24 b15) else (k25 b15)) else (k25 b15))); (if (decide ((Lanius.Mini.nodeProd x56) = Lanius.Mini.Inline.pForStmt)) = true then (k26 b10) else (if (decide ((Lanius.Mini.nodeProd x56) = Lanius.Mini.Inline.pBlockStmt)) = true then (k26 b10) else (k27 b10))))); (if (decide ((Lanius.Mini.nodeProd x56) = Lanius.Mini.Inline.pIfStmt)) = true then (if (decide ((Lanius.Mini.nodeProd ((Lanius.Mini.kid x56 5))) = Lanius.Mini.Inline.pElseNone)) = true then (k28 b6) else (k29 b6)) else (k29 b6))); (if (decide ((Lanius.Mini.nodeProd x56) = Lanius.Mini.Inline.pIfStmt)) = true then (if (decide ((Lanius.Mini.nodeProd ((Lanius.Mini.kid x56 5))) = Lanius.Mini.Inline.pElseStmt)) = true then (k30 b5) else (k31 b5)) else (k31 b5))))); (if (decide ((Lanius.Mini.nodeProd x56) = Lanius.Mini.Inline.pReturnStmt)) = true then (if (decide ((Lanius.Mini.nodeProd ((Lanius.Mini.kid x56 1))) = Lanius.Mini.Inline.pReturnVoid)) = true then (k32 b3) else (k33 b3)) else (k33 b3))); (if (decide ((Lanius.Mini.nodeProd x56) = Lanius.Mini.Inline.pReturnStmt)) = true then (if (decide ((Lanius.Mini.nodeProd ((Lanius.Mini.kid x56 1))) = Lanius.Mini.Inline.pReturnValue)) = true then (k34 b1) else (k35 b1)) else (k35 b1))); (if (decide ((Lanius.Mini.nodeProd x56) = Lanius.Mini.Inline.pReturnStmt)) = true then (if (decide ((Lanius.Mini.nodeProd ((Lanius.Mini.kid x56 1))) = Lanius.Mini.Inline.pReturnValue)) = true then (∀ b39 : Nat, (Cost_is_lit_init n (x8 - 1) x21 x36 (Lanius.Mini.kid ((Lanius.Mini.kid x56 1)) 0)) < b → b39 = b - (Cost_is_lit_init n (x8 - 1) x21 x36 (Lanius.Mini.kid ((Lanius.Mini.kid x56 1)) 0)) → (if (Lanius.Mini.isLitInit ((x8 - 1)) x21 x36 ((Lanius.Mini.kid ((Lanius.Mini.kid x56 1)) 0))) = true then (k36 b39) else (k37 b39))) else (k37 b)) else (k37 b))))
termination_by structural fuel => fuel

def Pre_lit_let_of : Nat → Nat → Lanius.Mini.FrontEnv → List Lanius.Mini.Local → Lanius.Mini.Local → Lanius.Mini.CTree → Option Lanius.Mini.MStmt → Nat → Prop
  | 0, x11, x24, x39, x59, x69, x82, b => True
  | n + 1, x11, x24, x39, x59, x69, x82, b => (if (decide (x11 = 0)) = true then True else (match x82 with | some x259 => (match (Lanius.Mini.matchInit x11 x69) with | some x341 => (Pre_lit_match_of n (x11 - 1) x24 x39 x341 (Lanius.Mini.LitForm.litLet x59 x259) b) | none => True) | none => True))
termination_by structural fuel => fuel

def Pre_let_match_of : Nat → Nat → Lanius.Mini.FrontEnv → List Lanius.Mini.Local → Lanius.Mini.Local → Lanius.Mini.CTree → Option Lanius.Mini.MStmt → Nat → Prop
  | 0, x13, x26, x41, x61, x71, x84, b => True
  | n + 1, x13, x26, x41, x61, x71, x84, b => (if (decide (x13 = 0)) = true then True else (match (Lanius.Mini.matchInit x13 x71) with | some x279 => ((Pre_match_stmt_parts n x13 x26 x41 x279 b) ∧ (∀ b1 : Nat, (Cost_match_stmt_parts n x13 x26 x41 x279) < b → b1 = b - (Cost_match_stmt_parts n x13 x26 x41 x279) → (match (Lanius.Mini.matchStmtParts x13 x26 x41 x279) with | some x376 => ((Pre_stmt_arms n x13 x26 x376 x279 b1) ∧ (∀ b2 : Nat, (Cost_stmt_arms n x13 x26 x376 x279) < b1 → b2 = b1 - (Cost_stmt_arms n x13 x26 x376 x279) → (match (Lanius.Mini.stmtArms x13 x26 x376 x279) with | some x470 => (match x84 with | some x551 => (Pre_let_arms_of n (x13 - 1) x26 x41 x376 x61 x551 0 x376.variants x470 b2) | none => True) | none => True))) | none => True))) | none => True))
termination_by structural fuel => fuel

def Pre_lit_match_of : Nat → Nat → Lanius.Mini.FrontEnv → List Lanius.Mini.Local → Lanius.Mini.CTree → Lanius.Mini.LitForm → Nat → Prop
  | 0, x13, x26, x41, x61, x71, b => True
  | n + 1, x13, x26, x41, x61, x71, b => (if (decide (x13 = 0)) = true then True else ((Pre_lit_match_parts n x13 x26 x41 x61 b) ∧ (∀ b1 : Nat, (Cost_lit_match_parts n x13 x26 x41 x61) < b → b1 = b - (Cost_lit_match_parts n x13 x26 x41 x61) → (match (Lanius.Mini.litMatchParts x13 x26 x41 x61) with | some x260 => (∀ b2 : Nat, (Cost_list_items n x13 (Lanius.Mini.kid x61 5)) < b1 → b2 = b1 - (Cost_list_items n x13 (Lanius.Mini.kid x61 5)) → (match (Lanius.Mini.listItems x13 ((Lanius.Mini.kid x61 5))) with | some x347 => (Pre_lit_arms_of n (x13 - 1) x26 x41 x260 x71 false false x347 b2) | none => True)) | none => True))))
termination_by structural fuel => fuel

def Pre_nested_of : Nat → Nat → Lanius.Mini.FrontEnv → List Lanius.Mini.Local → Lanius.Mini.CTree → Nat → Prop
  | 0, x10, x23, x38, x58, b => True
  | n + 1, x10, x23, x38, x58, b => (if (decide (x10 = 0)) = true then True else (if (decide ((Lanius.Mini.nodeProd x58) = Lanius.Mini.Inline.pForStmt)) = true then (Pre_for_of n (x10 - 1) x23 x38 x58 b) else (if (decide ((Lanius.Mini.nodeProd x58) = Lanius.Mini.Inline.pBlockStmt)) = true then (Pre_block_of n (x10 - 1) x23 x38 (Lanius.Mini.kid ((Lanius.Mini.kid x58 0)) 1) b) else True)))
termination_by structural fuel => fuel

def Pre_match_stmt_of : Nat → Nat → Lanius.Mini.FrontEnv → List Lanius.Mini.Local → Lanius.Mini.CTree → Nat → Prop
  | 0, x14, x27, x42, x62, b => True
  | n + 1, x14, x27, x42, x62, b => (if (decide (x14 = 0)) = true then True else (match (Lanius.Mini.matchPrimary x14 x62) with | some x232 => ((Pre_match_stmt_parts n x14 x27 x42 x232 b) ∧ (∀ b1 : Nat, (Cost_match_stmt_parts n x14 x27 x42 x232) < b → b1 = b - (Cost_match_stmt_parts n x14 x27 x42 x232) → (match (Lanius.Mini.matchStmtParts x14 x27 x42 x232) with | some x329 => ((Pre_stmt_arms n x14 x27 x329 x232 b1) ∧ (∀ b2 : Nat, (Cost_stmt_arms n x14 x27 x329 x232) < b1 → b2 = b1 - (Cost_stmt_arms n x14 x27 x329 x232) → (match (Lanius.Mini.stmtArms x14 x27 x329 x232) with | some x423 => (Pre_match_arms_of n (x14 - 1) x27 x42 x329 0 x329.variants x423 b2) | none => True))) | none => True))) | none => True))
termination_by structural fuel => fuel

def Pre_let_arms_of : Nat → Nat → Lanius.Mini.FrontEnv → List Lanius.Mini.Local → Lanius.Mini.MatchStmt → Lanius.Mini.Local → Lanius.Mini.MStmt → Nat → List Lanius.Mini.VariantTy → List Lanius.Mini.CTree → Nat → Prop
  | 0, x12, x25, x40, x60, x74, x84, x97, x107, x134, b => True
  | n + 1, x12, x25, x40, x60, x74, x84, x97, x107, x134, b => (if (decide (x12 = 0)) = true then True else (match x107 with | [] => True | x409 :: x412 => (match x134 with | [] => True | x476 :: x479 => ((Pre_plus n x97 1 b) ∧ ((Pre_let_arms_of n (x12 - 1) x25 x40 x60 x74 x84 (x97 + 1) x412 x479 b) ∧ (∀ b1 : Nat, (Cost_let_arms_of n (x12 - 1) x25 x40 x60 x74 x84 (x97 + 1) x412 x479) < b → b1 = b - (Cost_let_arms_of n (x12 - 1) x25 x40 x60 x74 x84 (x97 + 1) x412 x479) → (Pre_let_arm_of n (x12 - 1) x25 x40 x60 x74 x84 x97 x409 x476 (Lanius.Mini.letArmsOf ((x12 - 1)) x25 x40 x60 x74 x84 ((x97 + 1)) x412 x479) b1)))))))
termination_by structural fuel => fuel

def Pre_lit_arms_of : Nat → Nat → Lanius.Mini.FrontEnv → List Lanius.Mini.Local → Lanius.Mini.LitMatch → Lanius.Mini.LitForm → Bool → Bool → List Lanius.Mini.CTree → Nat → Prop
  | 0, x12, x25, x40, x60, x73, x88, x102, x116, b => True
  | n + 1, x12, x25, x40, x60, x73, x88, x102, x116, b => (if (decide (x12 = 0)) = true then True else (match x116 with | [] => True | x300 :: x303 => (Pre_lit_arm_of n (x12 - 1) x25 x40 x60 x73 x88 x102 x300 x303 b)))
termination_by structural fuel => fuel

def Pre_for_of : Nat → Nat → Lanius.Mini.FrontEnv → List Lanius.Mini.Local → Lanius.Mini.CTree → Nat → Prop
  | 0, x7, x21, x37, x58, b => True
  | n + 1, x7, x21, x37, x58, b => (let k15 := fun (b1 : Nat) => (match (Lanius.Mini.findLocal x37 ((((Lanius.Mini.kidToken ((Lanius.Mini.kid ((Lanius.Mini.kid ((Lanius.Mini.kid ((Lanius.Mini.kid ((Lanius.Mini.kid x58 3)) 1)) 1)) 0)) 0)) 0)).text))) with | some x856 => ((Pre_int_literal n (((Lanius.Mini.kidToken ((Lanius.Mini.kid ((Lanius.Mini.kid x58 3)) 0)) 0)).text) b1) ∧ (∀ b2 : Nat, (Cost_int_literal n (((Lanius.Mini.kidToken ((Lanius.Mini.kid ((Lanius.Mini.kid x58 3)) 0)) 0)).text)) < b1 → b2 = b1 - (Cost_int_literal n (((Lanius.Mini.kidToken ((Lanius.Mini.kid ((Lanius.Mini.kid x58 3)) 0)) 0)).text)) → (match (Lanius.Mini.intLiteral ((((Lanius.Mini.kidToken ((Lanius.Mini.kid ((Lanius.Mini.kid x58 3)) 0)) 0)).text))) with | some x968 => (∀ b3 : Nat, (Cost_cons_of_mini_selfhost_Local n (Lanius.Mini.Local.mk ((Lanius.Mini.kidToken x58 1).text) ((((Lanius.Mini.kidToken x58 2)).start) - x21.base) x856.ty) x37) < b2 → b3 = b2 - (Cost_cons_of_mini_selfhost_Local n (Lanius.Mini.Local.mk ((Lanius.Mini.kidToken x58 1).text) ((((Lanius.Mini.kidToken x58 2)).start) - x21.base) x856.ty) x37) → (Pre_block_of n x7 x21 ((Lanius.Mini.Local.mk ((Lanius.Mini.kidToken x58 1).text) ((((Lanius.Mini.kidToken x58 2)).start) - x21.base) x856.ty) :: x37) (Lanius.Mini.kid ((Lanius.Mini.kid x58 4)) 1) b3)) | none => True))) | none => True); let k16 := fun (b1 : Nat) => (let k13 := fun (b6 : Nat) => (match (Lanius.Mini.pathName ((Lanius.Mini.kid ((Lanius.Mini.kid x58 3)) 0))) with | some x1562 => (match (Lanius.Mini.findLocal x37 x1562) with | some x1657 => (match (Lanius.Mini.arrayLocal x1657) with | some x2189 => (∀ b7 : Nat, (Cost_cons_of_mini_selfhost_Local n (Lanius.Mini.Local.mk ((Lanius.Mini.kidToken x58 1).text) (((Lanius.Mini.kidToken x58 1).start) - x21.base) x2189.element) x37) < b6 → b7 = b6 - (Cost_cons_of_mini_selfhost_Local n (Lanius.Mini.Local.mk ((Lanius.Mini.kidToken x58 1).text) (((Lanius.Mini.kidToken x58 1).start) - x21.base) x2189.element) x37) → (Pre_block_of n x7 x21 ((Lanius.Mini.Local.mk ((Lanius.Mini.kidToken x58 1).text) (((Lanius.Mini.kidToken x58 1).start) - x21.base) x2189.element) :: x37) (Lanius.Mini.kid ((Lanius.Mini.kid x58 4)) 1) b7)) | none => (match (Lanius.Mini.sliceElem x1657.ty) with | some x1810 => (∀ b10 : Nat, (Cost_cons_of_mini_selfhost_Local n (Lanius.Mini.Local.mk ((Lanius.Mini.kidToken x58 1).text) ((((Lanius.Mini.kidToken x58 2)).start) - x21.base) x1810) x37) < b6 → b10 = b6 - (Cost_cons_of_mini_selfhost_Local n (Lanius.Mini.Local.mk ((Lanius.Mini.kidToken x58 1).text) ((((Lanius.Mini.kidToken x58 2)).start) - x21.base) x1810) x37) → (Pre_block_of n x7 x21 ((Lanius.Mini.Local.mk ((Lanius.Mini.kidToken x58 1).text) ((((Lanius.Mini.kidToken x58 2)).start) - x21.base) x1810) :: x37) (Lanius.Mini.kid ((Lanius.Mini.kid x58 4)) 1) b10)) | none => True)) | none => True) | none => True); let k14 := fun (b6 : Nat) => True; (if (decide ((Lanius.Mini.nodeProd ((Lanius.Mini.kid x58 3))) = Lanius.Mini.Inline.pForIterPath)) = true then (if (!(Lanius.Mini.member x21.globals (((Lanius.Mini.kidToken x58 1).text)))) = true then (if (Lanius.Mini.freshId x37 ((((Lanius.Mini.kidToken x58 1).start) - x21.base))) = true then (if (Lanius.Mini.freshId x37 (((((Lanius.Mini.kidToken x58 0)).start) - x21.base))) = true then (k13 b1) else (k14 b1)) else (k14 b1)) else (k14 b1)) else (k14 b1))); (if (decide ((Lanius.Mini.nodeProd ((Lanius.Mini.kid x58 3))) = Lanius.Mini.Inline.pForIterRangeFromStart)) = true then (if (decide ((Lanius.Mini.nodeProd ((Lanius.Mini.kid ((Lanius.Mini.kid x58 3)) 0))) = Lanius.Mini.Inline.pRangeStartInt)) = true then (if (decide ((Lanius.Mini.nodeProd ((Lanius.Mini.kid ((Lanius.Mini.kid x58 3)) 1))) = Lanius.Mini.Inline.pRangeExclusive)) = true then (if (decide ((Lanius.Mini.nodeProd ((Lanius.Mini.kid ((Lanius.Mini.kid ((Lanius.Mini.kid x58 3)) 1)) 1))) = Lanius.Mini.Inline.pRangeBound)) = true then (if (decide ((Lanius.Mini.nodeProd ((Lanius.Mini.kid ((Lanius.Mini.kid ((Lanius.Mini.kid ((Lanius.Mini.kid x58 3)) 1)) 1)) 0))) = Lanius.Mini.Inline.pRangeBoundName)) = true then (if (decide ((Lanius.Mini.nodeProd ((Lanius.Mini.kid ((Lanius.Mini.kid ((Lanius.Mini.kid ((Lanius.Mini.kid ((Lanius.Mini.kid x58 3)) 1)) 1)) 0)) 1))) = Lanius.Mini.Inline.pPostfixEnd)) = true then (if (!(Lanius.Mini.member x21.globals (((Lanius.Mini.kidToken x58 1).text)))) = true then (if (Lanius.Mini.freshId x37 ((((Lanius.Mini.kidToken x58 1).start) - x21.base))) = true then (if (Lanius.Mini.freshId x37 (((((Lanius.Mini.kidToken x58 0)).start) - x21.base))) = true then (if (Lanius.Mini.freshId x37 (((((Lanius.Mini.kidToken x58 2)).start) - x21.base))) = true then (k15 b) else (k16 b)) else (k16 b)) else (k16 b)) else (k16 b)) else (k16 b)) else (k16 b)) else (k16 b)) else (k16 b)) else (k16 b)) else (k16 b)))
termination_by structural fuel => fuel

def Pre_match_arms_of : Nat → Nat → Lanius.Mini.FrontEnv → List Lanius.Mini.Local → Lanius.Mini.MatchStmt → Nat → List Lanius.Mini.VariantTy → List Lanius.Mini.CTree → Nat → Prop
  | 0, x14, x27, x42, x62, x76, x86, x113, b => True
  | n + 1, x14, x27, x42, x62, x76, x86, x113, b => (if (decide (x14 = 0)) = true then True else (match x86 with | [] => True | x388 :: x391 => (match x113 with | [] => True | x457 :: x460 => ((Pre_plus n x76 1 b) ∧ ((Pre_match_arms_of n (x14 - 1) x27 x42 x62 (x76 + 1) x391 x460 b) ∧ (∀ b1 : Nat, (Cost_match_arms_of n (x14 - 1) x27 x42 x62 (x76 + 1) x391 x460) < b → b1 = b - (Cost_match_arms_of n (x14 - 1) x27 x42 x62 (x76 + 1) x391 x460) → (Pre_match_arm_of n (x14 - 1) x27 x42 x62 x76 x388 x457 (Lanius.Mini.matchArmsOf ((x14 - 1)) x27 x42 x62 ((x76 + 1)) x391 x460) b1)))))))
termination_by structural fuel => fuel

def Pre_let_arm_of : Nat → Nat → Lanius.Mini.FrontEnv → List Lanius.Mini.Local → Lanius.Mini.MatchStmt → Lanius.Mini.Local → Lanius.Mini.MStmt → Nat → Lanius.Mini.VariantTy → Lanius.Mini.CTree → Option Lanius.Mini.MStmt → Nat → Prop
  | 0, x11, x24, x39, x59, x73, x83, x96, x106, x120, x130, b => True
  | n + 1, x11, x24, x39, x59, x73, x83, x96, x106, x120, x130, b => (if (decide (x11 = 0)) = true then True else (∀ b1 : Nat, (Cost_arm_binding n x11 x24 x39 x59.owner x106 x120) < b → b1 = b - (Cost_arm_binding n x11 x24 x39 x59.owner x106 x120) → (match (Lanius.Mini.armBinding x11 x24 x39 x59.owner x106 x120) with | some x349 => (match (Lanius.Mini.armBlockList x11 x120) with | some x406 => (Pre_block_of n (x11 - 1) x24 (Lanius.Mini.boundScope x349) x406 b1) | none => (Pre_let_body_of n (x11 - 1) x24 (Lanius.Mini.boundScope x349) x73 x83 x120 b1)) | none => True)))
termination_by structural fuel => fuel

def Pre_lit_arm_of : Nat → Nat → Lanius.Mini.FrontEnv → List Lanius.Mini.Local → Lanius.Mini.LitMatch → Lanius.Mini.LitForm → Bool → Bool → Lanius.Mini.CTree → List Lanius.Mini.CTree → Nat → Prop
  | 0, x11, x24, x39, x59, x72, x87, x101, x115, x125, b => True
  | n + 1, x11, x24, x39, x59, x72, x87, x101, x115, x125, b => (if (decide (x11 = 0)) = true then True else (∀ b1 : Nat, (Cost_is_wild_arm n x115) < b → b1 = b - (Cost_is_wild_arm n x115) → (if (Lanius.Mini.isWildArm x115) = true then (Pre_lit_body_of n (x11 - 1) x24 x39 x72 x115 b1) else ((Pre_lit_cond n x59.scrutinee x59.sty (Lanius.Mini.kid x115 0) b1) ∧ (∀ b3 : Nat, (Cost_lit_cond n x59.scrutinee x59.sty (Lanius.Mini.kid x115 0)) < b1 → b3 = b1 - (Cost_lit_cond n x59.scrutinee x59.sty (Lanius.Mini.kid x115 0)) → ((Pre_lit_body_of n (x11 - 1) x24 x39 x72 x115 b3) ∧ (∀ b4 : Nat, (Cost_lit_body_of n (x11 - 1) x24 x39 x72 x115) < b3 → b4 = b3 - (Cost_lit_body_of n (x11 - 1) x24 x39 x72 x115) → (if x87 = true then (if x101 = true then (Pre_lit_arms_of n (x11 - 1) x24 x39 x59 x72 true true x125 b4) else (Pre_lit_arms_of n (x11 - 1) x24 x39 x59 x72 true (Lanius.Mini.isFalseArm x115) x125 b4)) else (if x101 = true then (Pre_lit_arms_of n (x11 - 1) x24 x39 x59 x72 (Lanius.Mini.isTrueArm x115) true x125 b4) else (Pre_lit_arms_of n (x11 - 1) x24 x39 x59 x72 (Lanius.Mini.isTrueArm x115) (Lanius.Mini.isFalseArm x115) x125 b4))))))))))
termination_by structural fuel => fuel

def Pre_match_arm_of : Nat → Nat → Lanius.Mini.FrontEnv → List Lanius.Mini.Local → Lanius.Mini.MatchStmt → Nat → Lanius.Mini.VariantTy → Lanius.Mini.CTree → Option Lanius.Mini.MStmt → Nat → Prop
  | 0, x13, x26, x41, x61, x75, x85, x99, x109, b => True
  | n + 1, x13, x26, x41, x61, x75, x85, x99, x109, b => (if (decide (x13 = 0)) = true then True else (∀ b1 : Nat, (Cost_arm_binding n x13 x26 x41 x61.owner x85 x99) < b → b1 = b - (Cost_arm_binding n x13 x26 x41 x61.owner x85 x99) → (match (Lanius.Mini.armBinding x13 x26 x41 x61.owner x85 x99) with | some x326 => (Pre_arm_body_of n (x13 - 1) x26 (Lanius.Mini.boundScope x326) x99 b1) | none => True)))
termination_by structural fuel => fuel

def Pre_let_body_of : Nat → Nat → Lanius.Mini.FrontEnv → List Lanius.Mini.Local → Lanius.Mini.Local → Lanius.Mini.MStmt → Lanius.Mini.CTree → Nat → Prop
  | 0, x12, x25, x40, x60, x70, x83, b => True
  | n + 1, x12, x25, x40, x60, x70, x83, b => (if (decide (x12 = 0)) = true then True else (if (decide ((Lanius.Mini.nodeProd ((Lanius.Mini.kid x83 2))) = Lanius.Mini.Inline.pMatchExpr)) = true then (Pre_inner_let_of n (x12 - 1) x25 x40 x60 x70 (Lanius.Mini.kid x83 2) b) else (Pre_let_head_or_eval n (x12 - 1) x25 x40 (Lanius.Mini.localTyOf x60) (Lanius.Mini.kid x83 2) b)))
termination_by structural fuel => fuel

def Pre_lit_body_of : Nat → Nat → Lanius.Mini.FrontEnv → List Lanius.Mini.Local → Lanius.Mini.LitForm → Lanius.Mini.CTree → Nat → Prop
  | 0, x12, x25, x40, x60, x75, b => True
  | n + 1, x12, x25, x40, x60, x75, b => (if (decide (x12 = 0)) = true then True else (match (Lanius.Mini.armBlockList x12 x75) with | some x224 => (Pre_block_of n (x12 - 1) x25 x40 x224 b) | none => (match x60 with | .litStmt => True | .litLet x356 x359 => (Pre_let_head_or_eval n (x12 - 1) x25 x40 (Lanius.Mini.localTyOf x356) (Lanius.Mini.kid x75 2) b) | .litReturn => (Pre_return_or_eval n (x12 - 1) x25 x40 (Lanius.Mini.kid x75 2) b))))
termination_by structural fuel => fuel

def Pre_arm_body_of : Nat → Nat → Lanius.Mini.FrontEnv → List Lanius.Mini.Local → Lanius.Mini.CTree → Nat → Prop
  | 0, x12, x25, x40, x60, b => True
  | n + 1, x12, x25, x40, x60, b => (if (decide (x12 = 0)) = true then True else (match (Lanius.Mini.armBlockList x12 x60) with | some x209 => (Pre_block_of n (x12 - 1) x25 x40 x209 b) | none => (Pre_inner_match_of n (x12 - 1) x25 x40 (Lanius.Mini.kid x60 2) b)))
termination_by structural fuel => fuel

def Pre_inner_let_of : Nat → Nat → Lanius.Mini.FrontEnv → List Lanius.Mini.Local → Lanius.Mini.Local → Lanius.Mini.MStmt → Lanius.Mini.CTree → Nat → Prop
  | 0, x13, x26, x41, x61, x71, x84, b => True
  | n + 1, x13, x26, x41, x61, x71, x84, b => (if (decide (x13 = 0)) = true then True else ((Pre_match_stmt_parts n x13 x26 x41 x84 b) ∧ (∀ b1 : Nat, (Cost_match_stmt_parts n x13 x26 x41 x84) < b → b1 = b - (Cost_match_stmt_parts n x13 x26 x41 x84) → (match (Lanius.Mini.matchStmtParts x13 x26 x41 x84) with | some x269 => ((Pre_stmt_arms n x13 x26 x269 x84 b1) ∧ (∀ b2 : Nat, (Cost_stmt_arms n x13 x26 x269 x84) < b1 → b2 = b1 - (Cost_stmt_arms n x13 x26 x269 x84) → (match (Lanius.Mini.stmtArms x13 x26 x269 x84) with | some x355 => (Pre_let_arms_of n (x13 - 1) x26 x41 x269 x61 x71 0 x269.variants x355 b2) | none => True))) | none => True))))
termination_by structural fuel => fuel

def Pre_inner_match_of : Nat → Nat → Lanius.Mini.FrontEnv → List Lanius.Mini.Local → Lanius.Mini.CTree → Nat → Prop
  | 0, x15, x28, x43, x63, b => True
  | n + 1, x15, x28, x43, x63, b => (if (decide (x15 = 0)) = true then True else (if (decide ((Lanius.Mini.nodeProd x63) = Lanius.Mini.Inline.pMatchExpr)) = true then ((Pre_match_stmt_parts n x15 x28 x43 x63 b) ∧ (∀ b1 : Nat, (Cost_match_stmt_parts n x15 x28 x43 x63) < b → b1 = b - (Cost_match_stmt_parts n x15 x28 x43 x63) → (match (Lanius.Mini.matchStmtParts x15 x28 x43 x63) with | some x302 => ((Pre_stmt_arms n x15 x28 x302 x63 b1) ∧ (∀ b2 : Nat, (Cost_stmt_arms n x15 x28 x302 x63) < b1 → b2 = b1 - (Cost_stmt_arms n x15 x28 x302 x63) → (match (Lanius.Mini.stmtArms x15 x28 x302 x63) with | some x396 => (Pre_match_arms_of n (x15 - 1) x28 x43 x302 0 x302.variants x396 b2) | none => True))) | none => True))) else True))
termination_by structural fuel => fuel
end

end

noncomputable section

def Cost_func_ret : Nat → Nat → Lanius.Mini.FrontEnv → Lanius.Mini.MParams → Option Lanius.Mini.RetTy → Lanius.Mini.CTree → Lanius.Mini.CTree → Nat
  | 0, x9, x22, x37, x50, x84, x102 => 18446744073709551616
  | n + 1, x9, x22, x37, x50, x84, x102 => (match x50 with | some x208 => ((Cost_block_of n x9 x22 x37.scope x102) + (Cost_contracts_of n x9 x22 x37.scope x84 (Lanius.Mini.blockOf x9 x22 x37.scope x102))) | none => 0)

end
noncomputable section

def Pre_func_ret : Nat → Nat → Lanius.Mini.FrontEnv → Lanius.Mini.MParams → Option Lanius.Mini.RetTy → Lanius.Mini.CTree → Lanius.Mini.CTree → Nat → Prop
  | 0, x9, x22, x37, x50, x84, x102, b => True
  | n + 1, x9, x22, x37, x50, x84, x102, b => (match x50 with | some x208 => ((Pre_block_of n x9 x22 x37.scope x102 b) ∧ (∀ b1 : Nat, (Cost_block_of n x9 x22 x37.scope x102) < b → b1 = b - (Cost_block_of n x9 x22 x37.scope x102) → (Pre_contracts_of n x9 x22 x37.scope x84 (Lanius.Mini.blockOf x9 x22 x37.scope x102) b1))) | none => True)

end

noncomputable section

def Cost_func_params : Nat → Nat → Lanius.Mini.FrontEnv → Option Lanius.Mini.MParams → Option Lanius.Mini.RetTy → Lanius.Mini.CTree → Lanius.Mini.CTree → Nat
  | 0, x12, x25, x40, x79, x113, x131 => 18446744073709551616
  | n + 1, x12, x25, x40, x79, x113, x131 => (match x40 with | some x240 => (Cost_func_ret n x12 x25 x240 x79 x113 x131) | none => 0)

end
noncomputable section

def Pre_func_params : Nat → Nat → Lanius.Mini.FrontEnv → Option Lanius.Mini.MParams → Option Lanius.Mini.RetTy → Lanius.Mini.CTree → Lanius.Mini.CTree → Nat → Prop
  | 0, x12, x25, x40, x79, x113, x131, b => True
  | n + 1, x12, x25, x40, x79, x113, x131, b => (match x40 with | some x240 => (Pre_func_ret n x12 x25 x240 x79 x113 x131 b) | none => True)

end

noncomputable section

def Cost_read_fn : Nat → Nat → Lanius.Mini.Decls → Lanius.Mini.FnDecl → List Lanius.Mini.Ty → Nat
  | 0, x8, x21, x35, x47 => 18446744073709551616
  | n + 1, x8, x21, x35, x47 => ((Cost_concat_of_mini_selfhost_List_usize n x35.implParams x35.params) + ((Cost_module_globals n x21 x35.home) + ((Cost_result_of n x8 (Lanius.Mini.FrontEnv.mk x21 x35.home (x35.implParams ++ x35.params) x47 (Lanius.Mini.moduleGlobals x21 x35.home) (none : Option Lanius.Mini.Ty) (((Lanius.Mini.kidToken x35.tree 1)).start)) (Lanius.Mini.kid x35.tree 6)) + ((Cost_module_globals n x21 x35.home) + (let k2 := ((Cost_list_items n x8 (Lanius.Mini.kid x35.tree 4)) + (match (Lanius.Mini.listItems x8 ((Lanius.Mini.kid x35.tree 4))) with | some x807 => ((Cost_params_of n x8 (Lanius.Mini.FrontEnv.mk x21 x35.home (x35.implParams ++ x35.params) x47 (Lanius.Mini.moduleGlobals x21 x35.home) (Lanius.Mini.retExpected ((Lanius.Mini.resultOf x8 ((Lanius.Mini.FrontEnv.mk x21 x35.home (x35.implParams ++ x35.params) x47 (Lanius.Mini.moduleGlobals x21 x35.home) (none : Option Lanius.Mini.Ty) (((Lanius.Mini.kidToken x35.tree 1)).start))) ((Lanius.Mini.kid x35.tree 6))))) (((Lanius.Mini.kidToken x35.tree 1)).start)) x35 ([] : List Lanius.Mini.Local) x807) + ((Cost_func_params n x8 (Lanius.Mini.FrontEnv.mk x21 x35.home (x35.implParams ++ x35.params) x47 (Lanius.Mini.moduleGlobals x21 x35.home) (Lanius.Mini.retExpected ((Lanius.Mini.resultOf x8 ((Lanius.Mini.FrontEnv.mk x21 x35.home (x35.implParams ++ x35.params) x47 (Lanius.Mini.moduleGlobals x21 x35.home) (none : Option Lanius.Mini.Ty) (((Lanius.Mini.kidToken x35.tree 1)).start))) ((Lanius.Mini.kid x35.tree 6))))) (((Lanius.Mini.kidToken x35.tree 1)).start)) (Lanius.Mini.paramsOf x8 ((Lanius.Mini.FrontEnv.mk x21 x35.home (x35.implParams ++ x35.params) x47 (Lanius.Mini.moduleGlobals x21 x35.home) (Lanius.Mini.retExpected ((Lanius.Mini.resultOf x8 ((Lanius.Mini.FrontEnv.mk x21 x35.home (x35.implParams ++ x35.params) x47 (Lanius.Mini.moduleGlobals x21 x35.home) (none : Option Lanius.Mini.Ty) (((Lanius.Mini.kidToken x35.tree 1)).start))) ((Lanius.Mini.kid x35.tree 6))))) (((Lanius.Mini.kidToken x35.tree 1)).start))) x35 (([] : List Lanius.Mini.Local)) x807) (Lanius.Mini.resultOf x8 ((Lanius.Mini.FrontEnv.mk x21 x35.home (x35.implParams ++ x35.params) x47 (Lanius.Mini.moduleGlobals x21 x35.home) (none : Option Lanius.Mini.Ty) (((Lanius.Mini.kidToken x35.tree 1)).start))) ((Lanius.Mini.kid x35.tree 6))) (Lanius.Mini.kid x35.tree 8) (Lanius.Mini.kid ((Lanius.Mini.kid x35.tree 9)) 1)) + (Cost_refs_checked n x8 x35.tree x807 (Lanius.Mini.funcParams x8 ((Lanius.Mini.FrontEnv.mk x21 x35.home (x35.implParams ++ x35.params) x47 (Lanius.Mini.moduleGlobals x21 x35.home) (Lanius.Mini.retExpected ((Lanius.Mini.resultOf x8 ((Lanius.Mini.FrontEnv.mk x21 x35.home (x35.implParams ++ x35.params) x47 (Lanius.Mini.moduleGlobals x21 x35.home) (none : Option Lanius.Mini.Ty) (((Lanius.Mini.kidToken x35.tree 1)).start))) ((Lanius.Mini.kid x35.tree 6))))) (((Lanius.Mini.kidToken x35.tree 1)).start))) ((Lanius.Mini.paramsOf x8 ((Lanius.Mini.FrontEnv.mk x21 x35.home (x35.implParams ++ x35.params) x47 (Lanius.Mini.moduleGlobals x21 x35.home) (Lanius.Mini.retExpected ((Lanius.Mini.resultOf x8 ((Lanius.Mini.FrontEnv.mk x21 x35.home (x35.implParams ++ x35.params) x47 (Lanius.Mini.moduleGlobals x21 x35.home) (none : Option Lanius.Mini.Ty) (((Lanius.Mini.kidToken x35.tree 1)).start))) ((Lanius.Mini.kid x35.tree 6))))) (((Lanius.Mini.kidToken x35.tree 1)).start))) x35 (([] : List Lanius.Mini.Local)) x807)) ((Lanius.Mini.resultOf x8 ((Lanius.Mini.FrontEnv.mk x21 x35.home (x35.implParams ++ x35.params) x47 (Lanius.Mini.moduleGlobals x21 x35.home) (none : Option Lanius.Mini.Ty) (((Lanius.Mini.kidToken x35.tree 1)).start))) ((Lanius.Mini.kid x35.tree 6)))) ((Lanius.Mini.kid x35.tree 8)) ((Lanius.Mini.kid ((Lanius.Mini.kid x35.tree 9)) 1)))))) | none => 0)); let k3 := 0; (if (decide (((x35.implParams ++ x35.params).length) = x47.length)) = true then ((Cost_fn_bounds_ok n x8 x21 x35 (Lanius.Mini.FrontEnv.mk x21 x35.home (x35.implParams ++ x35.params) x47 (Lanius.Mini.moduleGlobals x21 x35.home) (none : Option Lanius.Mini.Ty) (((Lanius.Mini.kidToken x35.tree 1)).start))) + (if (Lanius.Mini.fnBoundsOk x8 x21 x35 ((Lanius.Mini.FrontEnv.mk x21 x35.home (x35.implParams ++ x35.params) x47 (Lanius.Mini.moduleGlobals x21 x35.home) (none : Option Lanius.Mini.Ty) (((Lanius.Mini.kidToken x35.tree 1)).start)))) = true then k2 else k3)) else k3))))))

end
noncomputable section

def Pre_read_fn : Nat → Nat → Lanius.Mini.Decls → Lanius.Mini.FnDecl → List Lanius.Mini.Ty → Nat → Prop
  | 0, x8, x21, x35, x47, b => True
  | n + 1, x8, x21, x35, x47, b => (∀ b1 : Nat, (Cost_concat_of_mini_selfhost_List_usize n x35.implParams x35.params) < b → b1 = b - (Cost_concat_of_mini_selfhost_List_usize n x35.implParams x35.params) → (∀ b2 : Nat, (Cost_module_globals n x21 x35.home) < b1 → b2 = b1 - (Cost_module_globals n x21 x35.home) → ((Pre_result_of n x8 (Lanius.Mini.FrontEnv.mk x21 x35.home (x35.implParams ++ x35.params) x47 (Lanius.Mini.moduleGlobals x21 x35.home) (none : Option Lanius.Mini.Ty) (((Lanius.Mini.kidToken x35.tree 1)).start)) (Lanius.Mini.kid x35.tree 6) b2) ∧ (∀ b3 : Nat, (Cost_result_of n x8 (Lanius.Mini.FrontEnv.mk x21 x35.home (x35.implParams ++ x35.params) x47 (Lanius.Mini.moduleGlobals x21 x35.home) (none : Option Lanius.Mini.Ty) (((Lanius.Mini.kidToken x35.tree 1)).start)) (Lanius.Mini.kid x35.tree 6)) < b2 → b3 = b2 - (Cost_result_of n x8 (Lanius.Mini.FrontEnv.mk x21 x35.home (x35.implParams ++ x35.params) x47 (Lanius.Mini.moduleGlobals x21 x35.home) (none : Option Lanius.Mini.Ty) (((Lanius.Mini.kidToken x35.tree 1)).start)) (Lanius.Mini.kid x35.tree 6)) → (∀ b4 : Nat, (Cost_module_globals n x21 x35.home) < b3 → b4 = b3 - (Cost_module_globals n x21 x35.home) → (let k10 := fun (b5 : Nat) => (∀ b6 : Nat, (Cost_list_items n x8 (Lanius.Mini.kid x35.tree 4)) < b5 → b6 = b5 - (Cost_list_items n x8 (Lanius.Mini.kid x35.tree 4)) → (match (Lanius.Mini.listItems x8 ((Lanius.Mini.kid x35.tree 4))) with | some x807 => ((Pre_params_of n x8 (Lanius.Mini.FrontEnv.mk x21 x35.home (x35.implParams ++ x35.params) x47 (Lanius.Mini.moduleGlobals x21 x35.home) (Lanius.Mini.retExpected ((Lanius.Mini.resultOf x8 ((Lanius.Mini.FrontEnv.mk x21 x35.home (x35.implParams ++ x35.params) x47 (Lanius.Mini.moduleGlobals x21 x35.home) (none : Option Lanius.Mini.Ty) (((Lanius.Mini.kidToken x35.tree 1)).start))) ((Lanius.Mini.kid x35.tree 6))))) (((Lanius.Mini.kidToken x35.tree 1)).start)) x35 ([] : List Lanius.Mini.Local) x807 b6) ∧ (∀ b7 : Nat, (Cost_params_of n x8 (Lanius.Mini.FrontEnv.mk x21 x35.home (x35.implParams ++ x35.params) x47 (Lanius.Mini.moduleGlobals x21 x35.home) (Lanius.Mini.retExpected ((Lanius.Mini.resultOf x8 ((Lanius.Mini.FrontEnv.mk x21 x35.home (x35.implParams ++ x35.params) x47 (Lanius.Mini.moduleGlobals x21 x35.home) (none : Option Lanius.Mini.Ty) (((Lanius.Mini.kidToken x35.tree 1)).start))) ((Lanius.Mini.kid x35.tree 6))))) (((Lanius.Mini.kidToken x35.tree 1)).start)) x35 ([] : List Lanius.Mini.Local) x807) < b6 → b7 = b6 - (Cost_params_of n x8 (Lanius.Mini.FrontEnv.mk x21 x35.home (x35.implParams ++ x35.params) x47 (Lanius.Mini.moduleGlobals x21 x35.home) (Lanius.Mini.retExpected ((Lanius.Mini.resultOf x8 ((Lanius.Mini.FrontEnv.mk x21 x35.home (x35.implParams ++ x35.params) x47 (Lanius.Mini.moduleGlobals x21 x35.home) (none : Option Lanius.Mini.Ty) (((Lanius.Mini.kidToken x35.tree 1)).start))) ((Lanius.Mini.kid x35.tree 6))))) (((Lanius.Mini.kidToken x35.tree 1)).start)) x35 ([] : List Lanius.Mini.Local) x807) → (Pre_func_params n x8 (Lanius.Mini.FrontEnv.mk x21 x35.home (x35.implParams ++ x35.params) x47 (Lanius.Mini.moduleGlobals x21 x35.home) (Lanius.Mini.retExpected ((Lanius.Mini.resultOf x8 ((Lanius.Mini.FrontEnv.mk x21 x35.home (x35.implParams ++ x35.params) x47 (Lanius.Mini.moduleGlobals x21 x35.home) (none : Option Lanius.Mini.Ty) (((Lanius.Mini.kidToken x35.tree 1)).start))) ((Lanius.Mini.kid x35.tree 6))))) (((Lanius.Mini.kidToken x35.tree 1)).start)) (Lanius.Mini.paramsOf x8 ((Lanius.Mini.FrontEnv.mk x21 x35.home (x35.implParams ++ x35.params) x47 (Lanius.Mini.moduleGlobals x21 x35.home) (Lanius.Mini.retExpected ((Lanius.Mini.resultOf x8 ((Lanius.Mini.FrontEnv.mk x21 x35.home (x35.implParams ++ x35.params) x47 (Lanius.Mini.moduleGlobals x21 x35.home) (none : Option Lanius.Mini.Ty) (((Lanius.Mini.kidToken x35.tree 1)).start))) ((Lanius.Mini.kid x35.tree 6))))) (((Lanius.Mini.kidToken x35.tree 1)).start))) x35 (([] : List Lanius.Mini.Local)) x807) (Lanius.Mini.resultOf x8 ((Lanius.Mini.FrontEnv.mk x21 x35.home (x35.implParams ++ x35.params) x47 (Lanius.Mini.moduleGlobals x21 x35.home) (none : Option Lanius.Mini.Ty) (((Lanius.Mini.kidToken x35.tree 1)).start))) ((Lanius.Mini.kid x35.tree 6))) (Lanius.Mini.kid x35.tree 8) (Lanius.Mini.kid ((Lanius.Mini.kid x35.tree 9)) 1) b7))) | none => True)); let k11 := fun (b5 : Nat) => True; ((Pre_length_of_mini_selfhost_List_usize n (x35.implParams ++ x35.params) b4) ∧ ((Pre_length_of_mini_selfhost_Ty n x47 b4) ∧ (if (decide (((x35.implParams ++ x35.params).length) = x47.length)) = true then ((Pre_fn_bounds_ok n x8 x21 x35 (Lanius.Mini.FrontEnv.mk x21 x35.home (x35.implParams ++ x35.params) x47 (Lanius.Mini.moduleGlobals x21 x35.home) (none : Option Lanius.Mini.Ty) (((Lanius.Mini.kidToken x35.tree 1)).start)) b4) ∧ (∀ b12 : Nat, (Cost_fn_bounds_ok n x8 x21 x35 (Lanius.Mini.FrontEnv.mk x21 x35.home (x35.implParams ++ x35.params) x47 (Lanius.Mini.moduleGlobals x21 x35.home) (none : Option Lanius.Mini.Ty) (((Lanius.Mini.kidToken x35.tree 1)).start))) < b4 → b12 = b4 - (Cost_fn_bounds_ok n x8 x21 x35 (Lanius.Mini.FrontEnv.mk x21 x35.home (x35.implParams ++ x35.params) x47 (Lanius.Mini.moduleGlobals x21 x35.home) (none : Option Lanius.Mini.Ty) (((Lanius.Mini.kidToken x35.tree 1)).start))) → (if (Lanius.Mini.fnBoundsOk x8 x21 x35 ((Lanius.Mini.FrontEnv.mk x21 x35.home (x35.implParams ++ x35.params) x47 (Lanius.Mini.moduleGlobals x21 x35.home) (none : Option Lanius.Mini.Ty) (((Lanius.Mini.kidToken x35.tree 1)).start)))) = true then (k10 b12) else (k11 b12)))) else (k11 b4))))))))))

end

noncomputable section

def Cost_read_decl_inst : Nat → Nat → Lanius.Mini.Decls → Lanius.Mini.FnDecl → Lanius.Mini.Inst → Nat
  | 0, x15, x28, x42, x54 => 18446744073709551616
  | n + 1, x15, x28, x42, x54 => (if (decide ((Lanius.Mini.nodeProd x42.tree) = Lanius.Mini.Inline.pExternFn)) = true then (Cost_extern_func n x15 x28 x42 x54.args) else ((Cost_diverges n x42 x54) + (if (Lanius.Mini.diverges x42 x54) = true then ((Cost_init_tys n x54.args) + ((Cost_read_fn n x15 x28 x42 (Lanius.Mini.initTys x54.args)) + (Cost_diverge_func n (Lanius.Mini.readFn x15 x28 x42 ((Lanius.Mini.initTys x54.args))) x54))) else (Cost_read_fn n x15 x28 x42 x54.args))))

end
noncomputable section

def Pre_read_decl_inst : Nat → Nat → Lanius.Mini.Decls → Lanius.Mini.FnDecl → Lanius.Mini.Inst → Nat → Prop
  | 0, x15, x28, x42, x54, b => True
  | n + 1, x15, x28, x42, x54, b => (if (decide ((Lanius.Mini.nodeProd x42.tree) = Lanius.Mini.Inline.pExternFn)) = true then (Pre_extern_func n x15 x28 x42 x54.args b) else ((Pre_diverges n x42 x54 b) ∧ (∀ b2 : Nat, (Cost_diverges n x42 x54) < b → b2 = b - (Cost_diverges n x42 x54) → (if (Lanius.Mini.diverges x42 x54) = true then (∀ b3 : Nat, (Cost_init_tys n x54.args) < b2 → b3 = b2 - (Cost_init_tys n x54.args) → (Pre_read_fn n x15 x28 x42 (Lanius.Mini.initTys x54.args) b3)) else (Pre_read_fn n x15 x28 x42 x54.args b2)))))

end

noncomputable section

def Cost_projection_func : Nat → Option Lanius.Mini.Ty → Lanius.Mini.Inst → Lanius.Mini.Decls → Nat
  | 0, x16, x47, x59 => 18446744073709551616
  | n + 1, x16, x47, x59 => (match x16 with | some x166 => (match x47.args with | [] => 0 | x234 :: x237 => (Cost_single_of_mini_selfhost_MParam n (Lanius.Mini.MParam.mk 0 x234))) | none => 0)

end
noncomputable section

def Pre_projection_func : Nat → Option Lanius.Mini.Ty → Lanius.Mini.Inst → Lanius.Mini.Decls → Nat → Prop
  | 0, x16, x47, x59, b => True
  | n + 1, x16, x47, x59, b => (match x16 with | some x166 => (match x47.args with | [] => True | x234 :: x237 => (∀ b1 : Nat, (Cost_single_of_mini_selfhost_MParam n (Lanius.Mini.MParam.mk 0 x234)) < b → b1 = b - (Cost_single_of_mini_selfhost_MParam n (Lanius.Mini.MParam.mk 0 x234)) → (Pre_length_of_mini_selfhost_FnDecl n x59.fns b1))) | none => True)

end

noncomputable section

def Cost_read_inst : Nat → Nat → Lanius.Mini.Decls → Lanius.Mini.Inst → Nat
  | 0, x10, x23, x37 => 18446744073709551616
  | n + 1, x10, x23, x37 => (match (x23.fns[x37.decl]?) with | some x223 => (Cost_read_decl_inst n x10 x23 x223 x37) | none => ((Cost_projection_ret n x10 x23 x37) + (Cost_projection_func n (Lanius.Mini.projectionRet x10 x23 x37) x37 x23)))

end
noncomputable section

def Pre_read_inst : Nat → Nat → Lanius.Mini.Decls → Lanius.Mini.Inst → Nat → Prop
  | 0, x10, x23, x37, b => True
  | n + 1, x10, x23, x37, b => (match (x23.fns[x37.decl]?) with | some x223 => (Pre_read_decl_inst n x10 x23 x223 x37 b) | none => ((Pre_projection_ret n x10 x23 x37 b) ∧ (∀ b2 : Nat, (Cost_projection_ret n x10 x23 x37) < b → b2 = b - (Cost_projection_ret n x10 x23 x37) → (Pre_projection_func n (Lanius.Mini.projectionRet x10 x23 x37) x37 x23 b2))))

end

noncomputable section

mutual
def Cost_funcs_onto : Nat → List Lanius.Mini.MFunc → List Lanius.Mini.MFunc → Nat
  | 0, x11, x28 => 18446744073709551616
  | n + 1, x11, x28 => (match x11 with | [] => 0 | x120 :: x123 => ((Cost_cons_of_mini_selfhost_MFunc n x120 x28) + (Cost_funcs_onto n x123 (x120 :: x28))))
termination_by structural fuel => fuel
end

end

noncomputable section

mutual
def Cost_mono_loop : Nat → Nat → Nat → Lanius.Mini.Decls → List Lanius.Mini.Inst → List Lanius.Mini.MFunc → Nat → Nat
  | 0, x10, x23, x37, x51, x70, x89 => 18446744073709551616
  | n + 1, x10, x23, x37, x51, x70, x89 => (if (decide (x10 = 0)) = true then 0 else (match (x51[x89]?) with | some x306 => ((Cost_read_inst n x23 x37 x306) + (Cost_mono_next n (x10 - 1) x23 x37 x51 x70 x89 (Lanius.Mini.readInst x23 x37 x306))) | none => (Cost_funcs_onto n x70 ([] : List Lanius.Mini.MFunc))))
termination_by structural fuel => fuel

def Cost_mono_next : Nat → Nat → Nat → Lanius.Mini.Decls → List Lanius.Mini.Inst → List Lanius.Mini.MFunc → Nat → Option Lanius.Mini.MFunc → Nat
  | 0, x10, x24, x39, x54, x74, x94, x105 => 18446744073709551616
  | n + 1, x10, x24, x39, x54, x74, x94, x105 => (match x105 with | some x229 => ((Cost_stmt_calls n x229.body) + ((Cost_add_insts n x54 (Lanius.Mini.stmtCalls x229.body)) + ((Cost_cons_of_mini_selfhost_MFunc n x229 x74) + (Cost_mono_loop n x10 x24 x39 (Lanius.Mini.addInsts x54 ((Lanius.Mini.stmtCalls x229.body))) (x229 :: x74) (x94 + 1))))) | none => 0)
termination_by structural fuel => fuel
end

end
noncomputable section

mutual
def Pre_mono_loop : Nat → Nat → Nat → Lanius.Mini.Decls → List Lanius.Mini.Inst → List Lanius.Mini.MFunc → Nat → Nat → Prop
  | 0, x10, x23, x37, x51, x70, x89, b => True
  | n + 1, x10, x23, x37, x51, x70, x89, b => (if (decide (x10 = 0)) = true then True else (match (x51[x89]?) with | some x306 => ((Pre_read_inst n x23 x37 x306 b) ∧ (∀ b1 : Nat, (Cost_read_inst n x23 x37 x306) < b → b1 = b - (Cost_read_inst n x23 x37 x306) → (Pre_mono_next n (x10 - 1) x23 x37 x51 x70 x89 (Lanius.Mini.readInst x23 x37 x306) b1))) | none => True))
termination_by structural fuel => fuel

def Pre_mono_next : Nat → Nat → Nat → Lanius.Mini.Decls → List Lanius.Mini.Inst → List Lanius.Mini.MFunc → Nat → Option Lanius.Mini.MFunc → Nat → Prop
  | 0, x10, x24, x39, x54, x74, x94, x105, b => True
  | n + 1, x10, x24, x39, x54, x74, x94, x105, b => (match x105 with | some x229 => (∀ b1 : Nat, (Cost_stmt_calls n x229.body) < b → b1 = b - (Cost_stmt_calls n x229.body) → (∀ b2 : Nat, (Cost_add_insts n x54 (Lanius.Mini.stmtCalls x229.body)) < b1 → b2 = b1 - (Cost_add_insts n x54 (Lanius.Mini.stmtCalls x229.body)) → (∀ b3 : Nat, (Cost_cons_of_mini_selfhost_MFunc n x229 x74) < b2 → b3 = b2 - (Cost_cons_of_mini_selfhost_MFunc n x229 x74) → ((Pre_plus n x94 1 b3) ∧ (Pre_mono_loop n x10 x24 x39 (Lanius.Mini.addInsts x54 ((Lanius.Mini.stmtCalls x229.body))) (x229 :: x74) (x94 + 1) b3))))) | none => True)
termination_by structural fuel => fuel
end

end

end Lanius.Faithful.SelfBudget
