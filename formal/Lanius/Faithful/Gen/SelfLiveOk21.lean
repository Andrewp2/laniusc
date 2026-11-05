module

public import Lanius.Faithful.Gen.SelfPureTab
public import Lanius.Faithful.Gen.SelfLiveTab
public import Lanius.Faithful.Gen.SelfSrcC_Inline_blockLeft
public import Lanius.Faithful.Gen.SelfSrcC_UintTy_half
public import Lanius.Faithful.Gen.SelfSrcC_arithUint
public import Lanius.Faithful.Gen.SelfSrcC_codeSize
public import Lanius.Faithful.Gen.SelfSrcC_declareFuncs
public import Lanius.Faithful.Gen.SelfSrcC_enumVariants
public import Lanius.Faithful.Gen.SelfSrcC_evalSlotLimit
public import Lanius.Faithful.Gen.SelfSrcC_lowerLocal
public import Lanius.Faithful.Gen.SelfSrcC_packRound
public import Lanius.Faithful.Gen.SelfSrcC_render
public import Lanius.Faithful.Gen.SelfSrcF_Inline_attachParent
public import Lanius.Faithful.Gen.SelfSrcF_Inline_findMethodAt
public import Lanius.Faithful.Gen.SelfSrcF_Inline_pAndTail
public import Lanius.Faithful.Gen.SelfSrcF_Inline_pArgsMore
public import Lanius.Faithful.Gen.SelfSrcF_Inline_variantsNamedAt
public import Lanius.Faithful.Gen.SelfSrcF_basedDigits
public import Lanius.Faithful.Gen.SelfSrcF_litEffMatch
public import Lanius.Faithful.Gen.SelfSrcF_matchTysOrNone
public import Lanius.Faithful.Gen.SelfSrcF_tryLet
public import Lanius.Faithful.Gen.SelfSrcF_viewHead
import all Lanius.Faithful.Gen.SelfLiveTab
import all Lanius.Faithful.Gen.SelfPureTab
import all Lanius.Faithful.Gen.SelfSrcC_Inline_blockLeft
import all Lanius.Faithful.Gen.SelfSrcC_UintTy_half
import all Lanius.Faithful.Gen.SelfSrcC_arithUint
import all Lanius.Faithful.Gen.SelfSrcC_codeSize
import all Lanius.Faithful.Gen.SelfSrcC_declareFuncs
import all Lanius.Faithful.Gen.SelfSrcC_enumVariants
import all Lanius.Faithful.Gen.SelfSrcC_evalSlotLimit
import all Lanius.Faithful.Gen.SelfSrcC_lowerLocal
import all Lanius.Faithful.Gen.SelfSrcC_packRound
import all Lanius.Faithful.Gen.SelfSrcC_render
import all Lanius.Faithful.Gen.SelfSrcF_Inline_attachParent
import all Lanius.Faithful.Gen.SelfSrcF_Inline_findMethodAt
import all Lanius.Faithful.Gen.SelfSrcF_Inline_pAndTail
import all Lanius.Faithful.Gen.SelfSrcF_Inline_pArgsMore
import all Lanius.Faithful.Gen.SelfSrcF_Inline_variantsNamedAt
import all Lanius.Faithful.Gen.SelfSrcF_basedDigits
import all Lanius.Faithful.Gen.SelfSrcF_litEffMatch
import all Lanius.Faithful.Gen.SelfSrcF_matchTysOrNone
import all Lanius.Faithful.Gen.SelfSrcF_tryLet
import all Lanius.Faithful.Gen.SelfSrcF_viewHead
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

open Lanius.Faithful.Termination

/-- mini::selfhost::compile_words -/
theorem lok6 : LiveOk prims outside liveBad 6 (src_compile_words 11 12) := by decide +kernel

/-- mini::selfhost::binary_words -/
theorem lok11 : LiveOk prims outside liveBad 11 (src_binary_words 35 36) := by decide +kernel

/-- mini::selfhost::image_words -/
theorem lok35 : LiveOk prims outside liveBad 35 (src_image_words 9 51 52 53) := by decide +kernel

/-- mini::selfhost::pack_rounds -/
theorem lok36 : LiveOk prims outside liveBad 36 (src_pack_rounds 36 54 55 56) := by decide +kernel

/-- mini::selfhost::pack_round -/
theorem lok54 : LiveOk prims outside liveBad 54 (src_pack_round 5 54 56 77 78 79 80) := by decide +kernel

/-- mini::selfhost::round_join -/
theorem lok55 : LiveOk prims outside liveBad 55 (src_round_join 51 75) := by decide +kernel

/-- mini::selfhost::is_unit -/
theorem lok57 : LiveOk prims outside liveBad 57 (src_SrcType_is_unit) := by decide +kernel

/-- mini::selfhost::declare_funcs -/
theorem lok63 : LiveOk prims outside liveBad 63 (src_declare_funcs 59 90 91) := by decide +kernel

/-- mini::selfhost::declare_funcs_after -/
theorem lok90 : LiveOk prims outside liveBad 90 (src_declare_funcs_after 63) := by decide +kernel

/-- mini::selfhost::declare_in -/
theorem lok142 : LiveOk prims outside liveBad 142 (src_declare_in 244) := by decide +kernel

/-- mini::selfhost::block_left -/
theorem lok178 : LiveOk prims outside liveBad 178 (src_block_left 56 177) := by decide +kernel

/-- mini::selfhost::lookup -/
theorem lok202 : LiveOk prims outside liveBad 202 (src_lookup 328 329) := by decide +kernel

/-- mini::selfhost::declare_params_after -/
theorem lok243 : LiveOk prims outside liveBad 243 (src_declare_params_after 141) := by decide +kernel

/-- mini::selfhost::attach_sym -/
theorem lok255 : LiveOk prims outside liveBad 255 (src_attach_sym 420 421) := by decide +kernel

/-- mini::selfhost::is_scalar -/
theorem lok317 : LiveOk prims outside liveBad 317 (src_SrcType_is_scalar) := by decide +kernel

/-- mini::selfhost::is_i32 -/
theorem lok338 : LiveOk prims outside liveBad 338 (src_SrcType_is_i32) := by decide +kernel

/-- mini::selfhost::is_uint -/
theorem lok339 : LiveOk prims outside liveBad 339 (src_SrcType_is_uint 524) := by decide +kernel

/-- mini::selfhost::is_bool -/
theorem lok387 : LiveOk prims outside liveBad 387 (src_SrcType_is_bool) := by decide +kernel

/-- mini::selfhost::is_ptr -/
theorem lok390 : LiveOk prims outside liveBad 390 (src_SrcType_is_ptr) := by decide +kernel

/-- mini::selfhost::is_isize -/
theorem lok391 : LiveOk prims outside liveBad 391 (src_SrcType_is_isize) := by decide +kernel

/-- mini::selfhost::is_char -/
theorem lok392 : LiveOk prims outside liveBad 392 (src_SrcType_is_char) := by decide +kernel

/-- mini::selfhost::is_float -/
theorem lok393 : LiveOk prims outside liveBad 393 (src_SrcType_is_float 574) := by decide +kernel

/-- mini::selfhost::is_sint -/
theorem lok394 : LiveOk prims outside liveBad 394 (src_SrcType_is_sint 524) := by decide +kernel

/-- mini::selfhost::is_str -/
theorem lok395 : LiveOk prims outside liveBad 395 (src_SrcType_is_str) := by decide +kernel

/-- mini::selfhost::declare_struct_in -/
theorem lok406 : LiveOk prims outside liveBad 406 (src_declare_struct_in 388 582 583) := by decide +kernel

/-- mini::selfhost::declare_types_after -/
theorem lok408 : LiveOk prims outside liveBad 408 (src_declare_types_after 246) := by decide +kernel

/-- mini::selfhost::declare_enum_in -/
theorem lok409 : LiveOk prims outside liveBad 409 (src_declare_enum_in 389 582 586) := by decide +kernel

/-- mini::selfhost::enum_variants -/
theorem lok410 : LiveOk prims outside liveBad 410 (src_enum_variants 587 588) := by decide +kernel

/-- mini::selfhost::declare_variants_after -/
theorem lok411 : LiveOk prims outside liveBad 411 (src_declare_variants_after 248) := by decide +kernel

/-- mini::selfhost::attach_nonterm -/
theorem lok421 : LiveOk prims outside liveBad 421 (src_attach_nonterm 76 603) := by decide +kernel

/-- mini::selfhost::mono_next -/
theorem lok443 : LiveOk prims outside liveBad 443 (src_mono_next 75 270 677 678 679) := by decide +kernel

/-- mini::selfhost::code_size -/
theorem lok480 : LiveOk prims outside liveBad 480 (src_code_size 75 480 741 749) := by decide +kernel

/-- mini::selfhost::bool_bits -/
theorem lok502 : LiveOk prims outside liveBad 502 (src_bool_bits) := by decide +kernel

/-- mini::selfhost::lower_unsigned -/
theorem lok503 : LiveOk prims outside liveBad 503 (src_lower_unsigned 760) := by decide +kernel

/-- mini::selfhost::lower_local -/
theorem lok504 : LiveOk prims outside liveBad 504 (src_lower_local 761) := by decide +kernel

/-- mini::selfhost::lower_field -/
theorem lok505 : LiveOk prims outside liveBad 505 (src_lower_field 762) := by decide +kernel

/-- mini::selfhost::lower_negate -/
theorem lok506 : LiveOk prims outside liveBad 506 (src_lower_negate 551) := by decide +kernel

/-- mini::selfhost::lower_not -/
theorem lok507 : LiveOk prims outside liveBad 507 (src_lower_not 552) := by decide +kernel

/-- mini::selfhost::code -/
theorem lok524 : LiveOk prims outside liveBad 524 (src_UintTy_code) := by decide +kernel

/-- mini::selfhost::eval_slot_limit -/
theorem lok545 : LiveOk prims outside liveBad 545 (src_eval_slot_limit) := by decide +kernel

/-- mini::selfhost::lower_negate_typed -/
theorem lok551 : LiveOk prims outside liveBad 551 (src_lower_negate_typed 337 338 391 800 801 802 803 804) := by decide +kernel

/-- mini::selfhost::lower_not_typed -/
theorem lok552 : LiveOk prims outside liveBad 552 (src_lower_not_typed 337 387) := by decide +kernel

/-- mini::selfhost::attach_leaf -/
theorem lok602 : LiveOk prims outside liveBad 602 (src_attach_leaf 149 834 841 842 843 844 845) := by decide +kernel

/-- mini::selfhost::attach_parent -/
theorem lok603 : LiveOk prims outside liveBad 603 (src_attach_parent 76 846) := by decide +kernel

/-- mini::selfhost::type_table_more_at -/
theorem lok665 : LiveOk prims outside liveBad 665 (src_type_table_more_at 438 439 974 975) := by decide +kernel

/-- mini::selfhost::type_table_next -/
theorem lok667 : LiveOk prims outside liveBad 667 (src_type_table_next 439 677) := by decide +kernel

/-- mini::selfhost::compile_expr -/
theorem lok742 : LiveOk prims outside liveBad 742 (src_compile_expr 75 478 492 742 743) := by decide +kernel

/-- mini::selfhost::lower_field_of -/
theorem lok762 : LiveOk prims outside liveBad 762 (src_lower_field_of 75 181 520 521 1050) := by decide +kernel

/-- mini::selfhost::is_float_any -/
theorem lok800 : LiveOk prims outside liveBad 800 (src_SrcType_is_float_any) := by decide +kernel

/-- mini::selfhost::negate_float -/
theorem lok801 : LiveOk prims outside liveBad 801 (src_negate_float 337 1081 1082) := by decide +kernel

/-- mini::selfhost::float_ty -/
theorem lok802 : LiveOk prims outside liveBad 802 (src_SrcType_float_ty) := by decide +kernel

/-- mini::selfhost::sint_kind -/
theorem lok803 : LiveOk prims outside liveBad 803 (src_SrcType_sint_kind) := by decide +kernel

/-- mini::selfhost::negate_signed -/
theorem lok804 : LiveOk prims outside liveBad 804 (src_negate_signed 337 1083 1084) := by decide +kernel

/-- mini::selfhost::uint_kind -/
theorem lok810 : LiveOk prims outside liveBad 810 (src_SrcType_uint_kind) := by decide +kernel

/-- mini::selfhost::p_args_none -/
theorem lok857 : LiveOk prims outside liveBad 857 (src_p_args_none) := by decide +kernel

/-- mini::selfhost::p_args_some -/
theorem lok858 : LiveOk prims outside liveBad 858 (src_p_args_some) := by decide +kernel

/-- mini::selfhost::p_args_more -/
theorem lok859 : LiveOk prims outside liveBad 859 (src_p_args_more) := by decide +kernel

/-- mini::selfhost::p_args_end -/
theorem lok860 : LiveOk prims outside liveBad 860 (src_p_args_end) := by decide +kernel

/-- mini::selfhost::p_args_after_comma_more -/
theorem lok861 : LiveOk prims outside liveBad 861 (src_p_args_after_comma_more) := by decide +kernel

/-- mini::selfhost::p_args_after_comma_trailing -/
theorem lok862 : LiveOk prims outside liveBad 862 (src_p_args_after_comma_trailing) := by decide +kernel

/-- mini::selfhost::p_array_after_comma_more -/
theorem lok917 : LiveOk prims outside liveBad 917 (src_p_array_after_comma_more) := by decide +kernel

/-- mini::selfhost::weigh_next -/
theorem lok970 : LiveOk prims outside liveBad 970 (src_weigh_next 662 1218) := by decide +kernel

/-- mini::selfhost::lower_field_at -/
theorem lok1050 : LiveOk prims outside liveBad 1050 (src_lower_field_at 1303) := by decide +kernel

/-- mini::selfhost::weigh_round_at -/
theorem lok1219 : LiveOk prims outside liveBad 1219 (src_weigh_round_at 969 971 972 973 1454) := by decide +kernel

/-- mini::selfhost::neg_agrees -/
theorem lok1272 : LiveOk prims outside liveBad 1272 (src_neg_agrees 492 1021) := by decide +kernel

/-- mini::selfhost::binary_agrees -/
theorem lok1273 : LiveOk prims outside liveBad 1273 (src_binary_agrees 492 1021 1028 1494) := by decide +kernel

/-- mini::selfhost::unit_agrees -/
theorem lok1274 : LiveOk prims outside liveBad 1274 (src_unit_agrees 1021 1255 1258 1495) := by decide +kernel

/-- mini::selfhost::compare_agrees -/
theorem lok1275 : LiveOk prims outside liveBad 1275 (src_compare_agrees 492 1021 1028 1496) := by decide +kernel

/-- mini::selfhost::fp_agrees -/
theorem lok1276 : LiveOk prims outside liveBad 1276 (src_fp_agrees 492 1021 1497) := by decide +kernel

/-- mini::selfhost::is_sint_any -/
theorem lok1305 : LiveOk prims outside liveBad 1305 (src_SrcType_is_sint_any) := by decide +kernel

/-- mini::selfhost::arith_sint -/
theorem lok1306 : LiveOk prims outside liveBad 1306 (src_arith_sint 1513) := by decide +kernel

/-- mini::selfhost::arith_uint -/
theorem lok1307 : LiveOk prims outside liveBad 1307 (src_arith_uint 1514) := by decide +kernel

/-- mini::selfhost::is_integer -/
theorem lok1308 : LiveOk prims outside liveBad 1308 (src_SrcType_is_integer) := by decide +kernel

/-- mini::selfhost::word -/
theorem lok1313 : LiveOk prims outside liveBad 1313 (src_SrcType_word 1322) := by decide +kernel

/-- mini::selfhost::sint_to_i32 -/
theorem lok1315 : LiveOk prims outside liveBad 1315 (src_sint_to_i32 1083 1314) := by decide +kernel

/-- mini::selfhost::from_i32 -/
theorem lok1316 : LiveOk prims outside liveBad 1316 (src_from_i32 337 1083 1314) := by decide +kernel

/-- mini::selfhost::signed_word -/
theorem lok1322 : LiveOk prims outside liveBad 1322 (src_UintTy_signed_word 1083) := by decide +kernel

/-- mini::selfhost::spare -/
theorem lok1332 : LiveOk prims outside liveBad 1332 (src_UintTy_spare) := by decide +kernel

/-- mini::selfhost::least_bits -/
theorem lok1333 : LiveOk prims outside liveBad 1333 (src_UintTy_least_bits) := by decide +kernel

/-- mini::selfhost::lx_quoted_at -/
theorem lok1341 : LiveOk prims outside liveBad 1341 (src_lx_quoted_at 75 1107) := by decide +kernel

/-- mini::selfhost::ty_local_at -/
theorem lok1445 : LiveOk prims outside liveBad 1445 (src_ty_local_at 1210) := by decide +kernel

/-- mini::selfhost::weighed_more_at -/
theorem lok1453 : LiveOk prims outside liveBad 1453 (src_weighed_more_at 968 969 1218) := by decide +kernel

/-- mini::selfhost::param_of -/
theorem lok1463 : LiveOk prims outside liveBad 1463 (src_param_of 56 153 1142 1236 1591 1592 1593 1594 1595 1596 1597 1598 1599) := by decide +kernel

/-- mini::selfhost::lx_ident_run_at -/
theorem lok1522 : LiveOk prims outside liveBad 1522 (src_lx_ident_run_at 75 1336 1639) := by decide +kernel

/-- mini::selfhost::lx_digit_run_at -/
theorem lok1525 : LiveOk prims outside liveBad 1525 (src_lx_digit_run_at 75 1640 1641) := by decide +kernel

/-- mini::selfhost::lx_space_run_at -/
theorem lok1527 : LiveOk prims outside liveBad 1527 (src_lx_space_run_at 75 1104 1340) := by decide +kernel

/-- mini::selfhost::float_op -/
theorem lok1636 : LiveOk prims outside liveBad 1636 (src_float_op) := by decide +kernel

/-- mini::selfhost::lx_digit_tail_at -/
theorem lok1713 : LiveOk prims outside liveBad 1713 (src_lx_digit_tail_at 75 76 1640 1641 1773) := by decide +kernel

/-- mini::selfhost::decimal_digit -/
theorem lok1745 : LiveOk prims outside liveBad 1745 (src_decimal_digit 56 75 105 1682) := by decide +kernel

/-- mini::selfhost::lx_digit_sep -/
theorem lok1773 : LiveOk prims outside liveBad 1773 (src_lx_digit_sep 75 1640 1641) := by decide +kernel

/-- mini::selfhost::lx_exponent_sign -/
theorem lok1774 : LiveOk prims outside liveBad 1774 (src_lx_exponent_sign 75) := by decide +kernel

/-- mini::selfhost::int_literal -/
theorem lok1822 : LiveOk prims outside liveBad 1822 (src_int_literal 1879 1880) := by decide +kernel

/-- mini::selfhost::char_literal -/
theorem lok1826 : LiveOk prims outside liveBad 1826 (src_char_literal 76 1881) := by decide +kernel

/-- mini::selfhost::then_of -/
theorem lok1842 : LiveOk prims outside liveBad 1842 (src_then_of 1949) := by decide +kernel

/-- mini::selfhost::lx_line_run_at -/
theorem lok1846 : LiveOk prims outside liveBad 1846 (src_lx_line_run_at 75 1778) := by decide +kernel

/-- mini::selfhost::lx_block_at -/
theorem lok1847 : LiveOk prims outside liveBad 1847 (src_lx_block_at 75 1950) := by decide +kernel

/-- mini::selfhost::item_import_at -/
theorem lok1852 : LiveOk prims outside liveBad 1852 (src_item_import_at 939 1789 1953) := by decide +kernel

/-- mini::selfhost::p_andexpr -/
theorem lok1862 : LiveOk prims outside liveBad 1862 (src_p_andexpr) := by decide +kernel

/-- mini::selfhost::lit_value -/
theorem lok1879 : LiveOk prims outside liveBad 1879 (src_lit_value 76 1994) := by decide +kernel

/-- mini::selfhost::lit_sized -/
theorem lok1880 : LiveOk prims outside liveBad 1880 (src_lit_sized 1995) := by decide +kernel

/-- mini::selfhost::array_repeat_of -/
theorem lok1908 : LiveOk prims outside liveBad 1908 (src_array_repeat_of 1242 1887 1897 2041) := by decide +kernel

/-- mini::selfhost::array_of -/
theorem lok1909 : LiveOk prims outside liveBad 1909 (src_array_of 1242 1897 2042) := by decide +kernel

/-- mini::selfhost::let_head_or_eval -/
theorem lok1921 : LiveOk prims outside liveBad 1921 (src_let_head_or_eval 1706 2059 2060 2061) := by decide +kernel

/-- mini::selfhost::untyped_head -/
theorem lok1926 : LiveOk prims outside liveBad 1926 (src_untyped_head 1706 2062 2063 2064) := by decide +kernel

/-- mini::selfhost::then_rest -/
theorem lok1949 : LiveOk prims outside liveBad 1949 (src_then_rest 1241) := by decide +kernel

/-- mini::selfhost::lx_block_next -/
theorem lok1950 : LiveOk prims outside liveBad 1950 (src_lx_block_next 75 1779) := by decide +kernel

/-- mini::selfhost::p_and_tail -/
theorem lok1969 : LiveOk prims outside liveBad 1969 (src_p_and_tail) := by decide +kernel

/-- mini::selfhost::char_body -/
theorem lok1996 : LiveOk prims outside liveBad 1996 (src_char_body 76 2105) := by decide +kernel

/-- mini::selfhost::lit_eff_match -/
theorem lok2037 : LiveOk prims outside liveBad 2037 (src_lit_eff_match 2155 2156 2157) := by decide +kernel

/-- mini::selfhost::literal_head -/
theorem lok2056 : LiveOk prims outside liveBad 2056 (src_literal_head) := by decide +kernel

/-- mini::selfhost::untyped_try -/
theorem lok2063 : LiveOk prims outside liveBad 2063 (src_untyped_try) := by decide +kernel

/-- mini::selfhost::untyped_eval -/
theorem lok2064 : LiveOk prims outside liveBad 2064 (src_untyped_eval 2034 2175 2177 2178) := by decide +kernel

/-- mini::selfhost::for_of -/
theorem lok2074 : LiveOk prims outside liveBad 2074 (src_for_of 56 153 156 627 628 1142 1233 1595 1599 1620 1798 1800 1822 1877 2083 2190 2191 2192 2193 2194 2195 2196 2197 2198 2199) := by decide +kernel

/-- mini::selfhost::lit_prefixed -/
theorem lok2102 : LiveOk prims outside liveBad 2102 (src_lit_prefixed 2104 2224) := by decide +kernel

/-- mini::selfhost::lit_base -/
theorem lok2103 : LiveOk prims outside liveBad 2103 (src_lit_base) := by decide +kernel

/-- mini::selfhost::find_method_at -/
theorem lok2126 : LiveOk prims outside liveBad 2126 (src_find_method_at 75 934 2018 2250 2251 2252) := by decide +kernel

/-- mini::selfhost::variants_named_at -/
theorem lok2142 : LiveOk prims outside liveBad 2142 (src_variants_named_at 75 939 1785 2029 2138) := by decide +kernel

/-- mini::selfhost::untyped_if -/
theorem lok2177 : LiveOk prims outside liveBad 2177 (src_untyped_if) := by decide +kernel

/-- mini::selfhost::inferred -/
theorem lok2178 : LiveOk prims outside liveBad 2178 (src_inferred 2312) := by decide +kernel

/-- mini::selfhost::is_ptr_ty -/
theorem lok2180 : LiveOk prims outside liveBad 2180 (src_is_ptr_ty) := by decide +kernel

/-- mini::selfhost::try_let -/
theorem lok2182 : LiveOk prims outside liveBad 2182 (src_try_let 1241 2313) := by decide +kernel

/-- mini::selfhost::try_stmt -/
theorem lok2213 : LiveOk prims outside liveBad 2213 (src_try_stmt 2313) := by decide +kernel

/-- mini::selfhost::based_digits -/
theorem lok2224 : LiveOk prims outside liveBad 2224 (src_based_digits 76 2359) := by decide +kernel

/-- mini::selfhost::wide_digit -/
theorem lok2225 : LiveOk prims outside liveBad 2225 (src_wide_digit 56 75 105 2104) := by decide +kernel

/-- mini::selfhost::char_close -/
theorem lok2227 : LiveOk prims outside liveBad 2227 (src_char_close 76 2362) := by decide +kernel

/-- mini::selfhost::char_tail -/
theorem lok2228 : LiveOk prims outside liveBad 2228 (src_char_tail 76 2363) := by decide +kernel

/-- mini::selfhost::fl_add -/
theorem lok2229 : LiveOk prims outside liveBad 2229 (src_fl_add 1883 2229 2235 2364 2365 2366 2367) := by decide +kernel

/-- mini::selfhost::fl_mul10 -/
theorem lok2230 : LiveOk prims outside liveBad 2230 (src_fl_mul10 2229 2365) := by decide +kernel

/-- mini::selfhost::fl_times10 -/
theorem lok2238 : LiveOk prims outside liveBad 2238 (src_fl_times10 56 2230 2238) := by decide +kernel

/-- mini::selfhost::imported_variants_at -/
theorem lok2259 : LiveOk prims outside liveBad 2259 (src_imported_variants_at 939 2029 2137 2407) := by decide +kernel

/-- mini::selfhost::pure_inferred -/
theorem lok2312 : LiveOk prims outside liveBad 2312 (src_pure_inferred) := by decide +kernel

/-- mini::selfhost::based_digit -/
theorem lok2359 : LiveOk prims outside liveBad 2359 (src_based_digit 75 105 2224 2475 2476) := by decide +kernel

/-- mini::selfhost::char_close_opt -/
theorem lok2360 : LiveOk prims outside liveBad 2360 (src_char_close_opt 2227) := by decide +kernel

/-- mini::selfhost::escaped_byte -/
theorem lok2361 : LiveOk prims outside liveBad 2361 (src_escaped_byte) := by decide +kernel

/-- mini::selfhost::fl_carry_out -/
theorem lok2364 : LiveOk prims outside liveBad 2364 (src_fl_carry_out 1883 2239) := by decide +kernel

/-- mini::selfhost::fl_xor -/
theorem lok2366 : LiveOk prims outside liveBad 2366 (src_fl_xor) := by decide +kernel

/-- mini::selfhost::fl_carry -/
theorem lok2367 : LiveOk prims outside liveBad 2367 (src_fl_carry) := by decide +kernel

/-- mini::selfhost::fl_shl -/
theorem lok2377 : LiveOk prims outside liveBad 2377 (src_fl_shl 56 2365 2377) := by decide +kernel

/-- mini::selfhost::fl_less -/
theorem lok2379 : LiveOk prims outside liveBad 2379 (src_fl_less 1883 2235 2379 2479) := by decide +kernel

/-- mini::selfhost::eff_inferred -/
theorem lok2398 : LiveOk prims outside liveBad 2398 (src_eff_inferred 2483 2488) := by decide +kernel

/-- mini::selfhost::view_head -/
theorem lok2435 : LiveOk prims outside liveBad 2435 (src_view_head 321) := by decide +kernel

/-- mini::selfhost::fl_borrow_bit -/
theorem lok2479 : LiveOk prims outside liveBad 2479 (src_fl_borrow_bit) := by decide +kernel

/-- mini::selfhost::inst_bound -/
theorem lok2488 : LiveOk prims outside liveBad 2488 (src_inst_bound 1956 2085 2256 2403 2532 2533) := by decide +kernel

/-- mini::selfhost::p_arm_block -/
theorem lok2507 : LiveOk prims outside liveBad 2507 (src_p_arm_block) := by decide +kernel

/-- mini::selfhost::binder_of -/
theorem lok2515 : LiveOk prims outside liveBad 2515 (src_binder_of 56 153 156 163 628 1142 1595 1599 1800 2425 2427 2428 2555 2556 2557) := by decide +kernel

/-- mini::selfhost::fl_sub -/
theorem lok2527 : LiveOk prims outside liveBad 2527 (src_fl_sub 1883 2235 2365 2366 2479 2527) := by decide +kernel

/-- mini::selfhost::match_tys_or_none -/
theorem lok2533 : LiveOk prims outside liveBad 2533 (src_match_tys_or_none 2258) := by decide +kernel

/-- mini::selfhost::string_byte -/
theorem lok2541 : LiveOk prims outside liveBad 2541 (src_string_byte 2505 2580 2581 2582) := by decide +kernel

/-- mini::selfhost::diverge_eff -/
theorem lok2579 : LiveOk prims outside liveBad 2579 (src_diverge_eff 2603) := by decide +kernel

/-- mini::selfhost::string_close -/
theorem lok2580 : LiveOk prims outside liveBad 2580 (src_string_close 139) := by decide +kernel

/-- mini::selfhost::diverge_call -/
theorem lok2603 : LiveOk prims outside liveBad 2603 (src_diverge_call 368 680 941 1234 1239 2621) := by decide +kernel

/-- mini::selfhost::diverge_checked -/
theorem lok2621 : LiveOk prims outside liveBad 2621 (src_diverge_checked 672 975) := by decide +kernel

end Lanius.Faithful.SelfPure
