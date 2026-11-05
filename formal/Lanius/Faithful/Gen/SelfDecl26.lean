module

public import Lanius.Faithful.Gen.SelfPureTab
public import Lanius.Faithful.Gen.SelfSrc0
public import Lanius.Faithful.Gen.SelfSrcF_Inline_charOpen
public import Lanius.Faithful.Gen.SelfSrcF_Inline_pPathMore
public import Lanius.Faithful.Gen.SelfSrcF_anyNested
public import Lanius.Faithful.Gen.SelfSrcF_armsOf
public import Lanius.Faithful.Gen.SelfSrcF_callParts
public import Lanius.Faithful.Gen.SelfSrcF_consBinder
public import Lanius.Faithful.Gen.SelfSrcF_flDecimal
public import Lanius.Faithful.Gen.SelfSrcF_i32ArrayLength
public import Lanius.Faithful.Gen.SelfSrcF_isTypedSliceSegments
public import Lanius.Faithful.Gen.SelfSrcF_isUnderscore
public import Lanius.Faithful.Gen.SelfSrcF_matchTysOrNone
public import Lanius.Faithful.Gen.SelfSrcF_oneTreeNames
public import Lanius.Faithful.Gen.SelfSrcF_paramGoals
public import Lanius.Faithful.Gen.SelfSrcF_plainNaming
public import Lanius.Faithful.Gen.SelfSrcF_shadowUse
public import Lanius.Faithful.Gen.SelfSrcF_textSelf
public import Lanius.Faithful.Gen.SelfSrcF_variantArm
import all Lanius.Faithful.Gen.SelfPureTab
import all Lanius.Faithful.Gen.SelfSrc0
import all Lanius.Faithful.Gen.SelfSrcF_Inline_charOpen
import all Lanius.Faithful.Gen.SelfSrcF_Inline_pPathMore
import all Lanius.Faithful.Gen.SelfSrcF_anyNested
import all Lanius.Faithful.Gen.SelfSrcF_armsOf
import all Lanius.Faithful.Gen.SelfSrcF_callParts
import all Lanius.Faithful.Gen.SelfSrcF_consBinder
import all Lanius.Faithful.Gen.SelfSrcF_flDecimal
import all Lanius.Faithful.Gen.SelfSrcF_i32ArrayLength
import all Lanius.Faithful.Gen.SelfSrcF_isTypedSliceSegments
import all Lanius.Faithful.Gen.SelfSrcF_isUnderscore
import all Lanius.Faithful.Gen.SelfSrcF_matchTysOrNone
import all Lanius.Faithful.Gen.SelfSrcF_oneTreeNames
import all Lanius.Faithful.Gen.SelfSrcF_paramGoals
import all Lanius.Faithful.Gen.SelfSrcF_plainNaming
import all Lanius.Faithful.Gen.SelfSrcF_shadowUse
import all Lanius.Faithful.Gen.SelfSrcF_textSelf
import all Lanius.Faithful.Gen.SelfSrcF_variantArm
import all Lanius.Faithful.Gen.SelfTypes
import all Lanius.Mini.Compiler.P.BinOp_compute
import all Lanius.Mini.Compiler.P.BinOp_size
import all Lanius.Mini.Compiler.P.Code_image
import all Lanius.Mini.Compiler.P.Code_size
import all Lanius.Mini.Compiler.P.DivOp_size
import all Lanius.Mini.Compiler.P.FOp_size
import all Lanius.Mini.Compiler.P.FloatTy_mask
import all Lanius.Mini.Compiler.P.FloatTy_number
import all Lanius.Mini.Compiler.P.FloatTy_rexSize
import all Lanius.Mini.Compiler.P.FloatTy_signBit
import all Lanius.Mini.Compiler.P.FloatTy_signWord
import all Lanius.Mini.Compiler.P.Instr_encode
import all Lanius.Mini.Compiler.P.Instr_size
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
import all Lanius.Mini.Compiler.P.SrcEff_isSlice
import all Lanius.Mini.Compiler.P.SrcEff_passesSlices
import all Lanius.Mini.Compiler.P.SrcEff_sliceCall
import all Lanius.Mini.Compiler.P.SrcEff_types
import all Lanius.Mini.Compiler.P.SrcExpr_guard
import all Lanius.Mini.Compiler.P.SrcStmt_breaksOut
import all Lanius.Mini.Compiler.P.SrcStmt_declare
import all Lanius.Mini.Compiler.P.SrcStmt_depth
import all Lanius.Mini.Compiler.P.SrcStmt_lower
import all Lanius.Mini.Compiler.P.SrcStmt_returns
import all Lanius.Mini.Compiler.P.SrcType_declare
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
import all Lanius.Mini.Compiler.P.SrcType_same
import all Lanius.Mini.Compiler.P.SrcType_sintKind
import all Lanius.Mini.Compiler.P.SrcType_size
import all Lanius.Mini.Compiler.P.SrcType_uintKind
import all Lanius.Mini.Compiler.P.SrcType_word
import all Lanius.Mini.Compiler.P.UintTy_code
import all Lanius.Mini.Compiler.P.UintTy_half
import all Lanius.Mini.Compiler.P.UintTy_isWide
import all Lanius.Mini.Compiler.P.UintTy_leastBits
import all Lanius.Mini.Compiler.P.UintTy_signedWord
import all Lanius.Mini.Compiler.P.UintTy_spare
import all Lanius.Mini.Compiler.P.Word_prefix
import all Lanius.Mini.Compiler.P.argBase
import all Lanius.Mini.Compiler.P.arith
import all Lanius.Mini.Compiler.P.arithShiftRight
import all Lanius.Mini.Compiler.P.arrayCall
import all Lanius.Mini.Compiler.P.arrayCallSig
import all Lanius.Mini.Compiler.P.boolBits
import all Lanius.Mini.Compiler.P.boundsGuard
import all Lanius.Mini.Compiler.P.checkThen
import all Lanius.Mini.Compiler.P.codeSize
import all Lanius.Mini.Compiler.P.compileExpr
import all Lanius.Mini.Compiler.P.copyBytes
import all Lanius.Mini.Compiler.P.declareEnum
import all Lanius.Mini.Compiler.P.declareFunc
import all Lanius.Mini.Compiler.P.declareFuncs
import all Lanius.Mini.Compiler.P.declareParams
import all Lanius.Mini.Compiler.P.declareProgram
import all Lanius.Mini.Compiler.P.declareStruct
import all Lanius.Mini.Compiler.P.declaredSame
import all Lanius.Mini.Compiler.P.declaredVariants
import all Lanius.Mini.Compiler.P.effsSlice
import all Lanius.Mini.Compiler.P.encodeFrom
import all Lanius.Mini.Compiler.P.encodeOnto
import all Lanius.Mini.Compiler.P.entriesAt
import all Lanius.Mini.Compiler.P.enumVariants
import all Lanius.Mini.Compiler.P.epilogue
import all Lanius.Mini.Compiler.P.equality
import all Lanius.Mini.Compiler.P.evalIf
import all Lanius.Mini.Compiler.P.evalIfOf
import all Lanius.Mini.Compiler.P.evalLetIn
import all Lanius.Mini.Compiler.P.evalLetInOf
import all Lanius.Mini.Compiler.P.evalMatch
import all Lanius.Mini.Compiler.P.evalMatchOf
import all Lanius.Mini.Compiler.P.expectType
import all Lanius.Mini.Compiler.P.fieldOffset
import all Lanius.Mini.Compiler.P.floatApply
import all Lanius.Mini.Compiler.P.floatArith
import all Lanius.Mini.Compiler.P.floatCompare
import all Lanius.Mini.Compiler.P.floatOrder
import all Lanius.Mini.Compiler.P.frameSize
import all Lanius.Mini.Compiler.P.funcsReturn
import all Lanius.Mini.Compiler.P.funcsSize
import all Lanius.Mini.Compiler.P.funcsSlots
import all Lanius.Mini.Compiler.P.guardAll
import all Lanius.Mini.Compiler.P.guarded
import all Lanius.Mini.Compiler.P.keepIf
import all Lanius.Mini.Compiler.P.layout
import all Lanius.Mini.Compiler.P.linkFrom
import all Lanius.Mini.Compiler.P.linkObjects
import all Lanius.Mini.Compiler.P.linkOnto
import all Lanius.Mini.Compiler.P.loadAtBytes
import all Lanius.Mini.Compiler.P.loadWordBytes
import all Lanius.Mini.Compiler.P.lookup
import all Lanius.Mini.Compiler.P.lowBits
import all Lanius.Mini.Compiler.P.lowerAppend
import all Lanius.Mini.Compiler.P.lowerAs
import all Lanius.Mini.Compiler.P.lowerBody
import all Lanius.Mini.Compiler.P.lowerDiscard
import all Lanius.Mini.Compiler.P.lowerFunc
import all Lanius.Mini.Compiler.P.lowerFuncCons
import all Lanius.Mini.Compiler.P.lowerFuncs
import all Lanius.Mini.Compiler.P.lowerIfEval
import all Lanius.Mini.Compiler.P.lowerLet
import all Lanius.Mini.Compiler.P.lowerLetCall
import all Lanius.Mini.Compiler.P.lowerLetEval
import all Lanius.Mini.Compiler.P.lowerReturnEval
import all Lanius.Mini.Compiler.P.lowerSetEval
import all Lanius.Mini.Compiler.P.lowerWhileEval
import all Lanius.Mini.Compiler.P.matchVariants
import all Lanius.Mini.Compiler.P.norm
import all Lanius.Mini.Compiler.P.objectExports
import all Lanius.Mini.Compiler.P.objectFirsts
import all Lanius.Mini.Compiler.P.objectLayout
import all Lanius.Mini.Compiler.P.objectsLayout
import all Lanius.Mini.Compiler.P.objectsOk
import all Lanius.Mini.Compiler.P.objectsSlots
import all Lanius.Mini.Compiler.P.offsetOrArith
import all Lanius.Mini.Compiler.P.order
import all Lanius.Mini.Compiler.P.orderSint
import all Lanius.Mini.Compiler.P.orderUint
import all Lanius.Mini.Compiler.P.paramScope
import all Lanius.Mini.Compiler.P.paramTypes
import all Lanius.Mini.Compiler.P.paramsSize
import all Lanius.Mini.Compiler.P.paramsValid
import all Lanius.Mini.Compiler.P.prologue
import all Lanius.Mini.Compiler.P.relative
import all Lanius.Mini.Compiler.P.render
import all Lanius.Mini.Compiler.P.renderFuncs
import all Lanius.Mini.Compiler.P.renderObjects
import all Lanius.Mini.Compiler.P.signKey
import all Lanius.Mini.Compiler.P.signedKey
import all Lanius.Mini.Compiler.P.slotRange
import all Lanius.Mini.Compiler.P.slotVars
import all Lanius.Mini.Compiler.P.stackCheck
import all Lanius.Mini.Compiler.P.stmtEval
import all Lanius.Mini.Compiler.P.storeAtBytes
import all Lanius.Mini.Compiler.P.storeWordBytes
import all Lanius.Mini.Compiler.P.structFields
import all Lanius.Mini.Compiler.P.sysBytes
import all Lanius.Mini.Compiler.P.syscallLinuxByte
import all Lanius.Mini.Compiler.P.syscallLinuxHigh
import all Lanius.Mini.Compiler.P.syscallRsiBytes
import all Lanius.Mini.Compiler.P.thenCheck
import all Lanius.Mini.Compiler.P.trap
import all Lanius.Mini.Compiler.P.unitTail
import all Lanius.Mini.Compiler.P.withFrame
import all Lanius.Mini.Compiler.P.wordElement
import all Lanius.Mini.Compiler.P.wordType
import all Lanius.Mini.Compiler.P.wordWidth
import all Lanius.Mini.Compiler.P.wrap
import all Lanius.Mini.Compiler.Types

@[expose] public section

/-! Generated by formal/tools/faithful_pure.py. Do not edit. -/

namespace Lanius.Faithful.SelfPure

open Lanius.Mini
open Lanius.Faithful
open Lanius.Faithful.Self

/-- Functions 2600 to 2678, and their signature entries. -/
def dpart26 : List SrcFunc := [(src_fl_exp_digits 76 1997 2619), (src_view_array 1671 1897 2040), (src_fit_same_decl 56 2620), (src_diverge_call 368 680 941 1234 1239 2621), (src_is_mem_typed 558 934 2385 2622), (src_is_u8_ty 1671), (src_string_data_ptr_path 647 1141 2384 2385 2623), (src_one_tree_names 103 1763 2586), (src_int_primary 153 627 628 1798 1821 1822), (src_binder_name_ok 163 1142 2556), (src_arm_names 153 156 429 2425 2426), (src_used_arms), (src_join_use 148), (src_wild_use 2596), (src_rows_use 2624), (src_row_cons 2617), (src_arm_naming 156 429 2625), (src_arms_naming_at 148), (src_wild_tail 148 156 254 607 894 2626 2627), (src_fl_exp_digit_at 56 75 105 2106 2600), (src_fit_args 56 103 666 2628 2629), (src_diverge_checked 672 975), (src_is_last_typed 558 934 2630 2631), (src_text_string_data_ptr 376 418), (src_nested_or_plain 2632 2633), (src_named_known 2426), (src_p_pattern_tuple), (src_wild_binders 75 96 148 666 2627 2634), (src_fit_args_next 56 2620), (src_fit_arg 56 153 156 1791 2402), (src_text_typed_slice_from_raw_parts 418 2008), (src_is_empty_texts), (src_nest_use 2635 2636), (src_plain_use 2290 2637), (src_wild_binder 75 148 153 156 254 607 628), (src_row_pats 153 155 156 2425 2427), (src_nest_pats 2638 2639), (src_shadow_use 2640), (src_first_nested 75 103 2589 2638 2641), (src_nest_at 1000 2642 2643 2644), (src_shadow_if), (src_first_at), (src_get_of_mini_selfhost_CTree 56 103 2642), (src_nest_inner 2645 2646), (src_column_arms 96 103 2635 2644 2647 2648), (src_wild_inner 2646 2649 2650 2651), (src_nest_arm 148 153 156 254 607 888 894 1835 2652 2653 2654), (src_column_arm 2642 2655 2656 2657), (src_is_last), (src_ends_wild 2510), (src_known_use 2658), (src_covers 163 1185 2035 2659), (src_replace_at 56 96 103 148 2652), (src_hidden_pat 96 148 254 607 2425 2427 2660), (src_hidden_expr 96 148 254 607 1796 1797 2660), (src_column_fit 2572), (src_row_fits 75 103 2656 2661), (src_column_sub 156 1800 2589 2662 2663 2664), (src_covered_use 156 2646 2665 2666), (src_covers_decl 2667), (src_hidden_path 2668 2669), (src_col_fits 156 1800 2589 2670), (src_quiet_sub 2671), (src_quiet_in 607 2576 2672), (src_sub_arm 148 153 156 254 607), (src_quiet_use 2673), (src_cols_quiet 75 103 1700 2666 2674), (src_covers_enum 2675), (src_named_path 96 148 156 254 607 628 645 646 1859), (src_text_hidden 376), (src_same_opt_name 934), (src_quiet_arm 2664 2676), (src_mentions 56 103 934 1120 2421 2672), (src_appended_use 607 1120 2646), (src_col_quiet 156 1800 2663), (src_covers_all 558 1700 2675 2677), (src_wild_pat 96 148 254 607 2425 2427 2517 2668), (src_covered_by 103 2421 2677 2678), (src_plain_naming 1700 2422 2576 2616)]

def dents26 : List SigEntry := [some ([ty20, ty320, (.uint .usize), (.uint .usize), .bool, (.uint .usize)], ty322), some ([(.uint .usize), ty154, ty318, ty193], ty317), some ([(.uint .usize), ty276, ty27, .bool, ty86, ty155, ty335], ty363), some ([ty128, ty154, ty156, ty191, ty193], ty193), some ([ty27], .bool), some ([ty251], .bool), some ([], ty27), some ([(.uint .usize), ty87, ty20], .bool), some ([ty85, ty85], ty286), some ([ty276, ty226], .bool), some ([(.uint .usize), ty108, ty20, ty85], .bool), some ([.bool, ty86], ty87), some ([ty386, ty385], ty385), some ([ty138, ty346], ty387), some ([(.uint .usize), ty276, ty346, ty85, ty86, ty86, ty138, ty308], ty387), some ([ty308, ty85, ty87], ty87), some ([(.uint .usize), ty108, ty20, ty85], ty308), some ([.bool, ty85, ty86], ty86), some ([ty85, ty155], ty85), some ([(.uint .usize), ty20, ty320, (.uint .usize), (.uint .usize), .bool, (.uint .usize)], ty322), some ([(.uint .usize), ty276, ty27, ty86, ty155, ty335], ty363), some ([.bool, ty154, ty156, ty191, ty193], ty193), some ([ty27], .bool), some ([], ty20), some ([(.uint .usize), ty276, ty346, ty85, ty86, ty86, ty138, .bool], ty387), some ([ty108, ty20, ty151], ty308), some ([], (.uint .usize)), some ([ty85, (.uint .usize), ty155], ty86), some ([(.uint .usize), ty276, ty27, ty86, ty155, ty363], ty363), some ([(.uint .usize), ty276, ty27, ty85, ty154, ty335], ty363), some ([], ty20), some ([ty27], .bool), some ([(.uint .usize), ty276, ty346, ty85, ty86, ty138], ty387), some ([(.uint .usize), ty276, ty85, ty86], ty387), some ([ty85, (.uint .usize)], ty85), some ([(.uint .usize), ty85], ty87), some ([(.uint .usize), ty276, ty346, ty85, ty86, ty86, ty138], ty387), some ([ty85, ty308], ty387), some ([ty276, ty86, (.uint .usize)], ty146), some ([(.uint .usize), ty276, ty346, ty85, ty86, (.uint .usize), ty86, ty138], ty387), some ([ty85, .bool], ty387), some ([.bool, (.uint .usize), ty146], ty146), some ([ty86, (.uint .usize)], ty138), some ([(.uint .usize), ty276, ty85, ty86, (.uint .usize), ty85, ty154, ty87, ty138], ty387), some ([(.uint .usize), ty276, ty86, (.uint .usize), ty86], ty87), some ([(.uint .usize), ty276, ty85, ty86, (.uint .usize), ty85, ty154, ty86, ty85], ty387), some ([ty85, ty86, (.uint .usize), ty85, ty86], ty85), some ([(.uint .usize), ty276, ty86, (.uint .usize), ty85, .bool, ty87, ty87], ty87), some ([ty86], .bool), some ([ty86], .bool), some ([(.uint .usize), ty85, ty86, (.uint .usize), ty85, ty86, ty85, ty308], ty387), some ([(.uint .usize), ty276, ty154, ty86], ty308), some ([ty86, (.uint .usize), ty85], ty86), some ([ty85], ty85), some ([ty85], ty85), some ([.bool, ty138, ty87], ty87), some ([ty276, ty86, ty86, (.uint .usize), (.uint .usize), .bool], .bool), some ([(.uint .usize), ty276, ty85, ty85], ty138), some ([(.uint .usize), ty85, ty86, (.uint .usize), ty85, ty86, ty85, .bool], ty387), some ([(.uint .usize), ty276, ty244, ty86], ty308), some ([ty85], ty85), some ([ty276, ty85, ty85, .bool, .bool], .bool), some ([ty85, ty85, ty308], ty138), some ([(.uint .usize), ty226, ty85], ty308), some ([ty85, ty85], ty85), some ([ty85, ty86, (.uint .usize), ty85, ty86, ty85, ty308], ty387), some ([(.uint .usize), ty86, (.uint .usize), (.uint .usize), ty85], ty308), some ([(.uint .usize), ty276, ty108, ty86], ty308), some ([ty85, ty20], ty85), some ([], ty20), some ([ty226, ty226], .bool), some ([.bool, ty85, ty85], ty138), some ([(.uint .usize), ty86, ty20], ty308), some ([ty85, ty86, (.uint .usize), ty85, ty86, ty85, .bool], ty387), some ([(.uint .usize), ty85, .bool, ty85], ty308), some ([(.uint .usize), ty276, ty108, ty27, ty86], ty308), some ([ty85], ty85), some ([(.uint .usize), ty276, ty108, ty20, ty86], ty308), some ([(.uint .usize), ty276, ty108, ty20, ty85], ty308)]

/-- `declareFuncs` of functions 2600 to 2678. -/
theorem dchunk26 : declsStep dpart26 decls 0 0 0 0 = true := by decide +kernel

theorem dfit26 : entriesFit dpart26 dents26 = true := by decide +kernel

end Lanius.Faithful.SelfPure
