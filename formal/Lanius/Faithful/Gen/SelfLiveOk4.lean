module

public import Lanius.Faithful.Gen.SelfPureTab
public import Lanius.Faithful.Gen.SelfLiveTab
public import Lanius.Faithful.Gen.SelfSrcC_BinOp_folds
public import Lanius.Faithful.Gen.SelfSrcC_FloatTy_rex
public import Lanius.Faithful.Gen.SelfSrcC_UintTy_mask
public import Lanius.Faithful.Gen.SelfSrcC_evalDivide
public import Lanius.Faithful.Gen.SelfSrcC_lowerSetCallArgs
public import Lanius.Faithful.Gen.SelfSrcC_lowerSetValues
public import Lanius.Faithful.Gen.SelfSrcF_Inline_pArrayMore
public import Lanius.Faithful.Gen.SelfSrcF_Inline_pSelfParamPlain
public import Lanius.Faithful.Gen.SelfSrcF_allocClosed
public import Lanius.Faithful.Gen.SelfSrcF_eDerefClosed
public import Lanius.Faithful.Gen.SelfSrcF_isPathCall
public import Lanius.Faithful.Gen.SelfSrcF_repeatEff
public import Lanius.Faithful.Gen.SelfSrcF_whileEvalOf
import all Lanius.Faithful.Gen.SelfLiveTab
import all Lanius.Faithful.Gen.SelfPureTab
import all Lanius.Faithful.Gen.SelfSrcC_BinOp_folds
import all Lanius.Faithful.Gen.SelfSrcC_FloatTy_rex
import all Lanius.Faithful.Gen.SelfSrcC_UintTy_mask
import all Lanius.Faithful.Gen.SelfSrcC_evalDivide
import all Lanius.Faithful.Gen.SelfSrcC_lowerSetCallArgs
import all Lanius.Faithful.Gen.SelfSrcC_lowerSetValues
import all Lanius.Faithful.Gen.SelfSrcF_Inline_pArrayMore
import all Lanius.Faithful.Gen.SelfSrcF_Inline_pSelfParamPlain
import all Lanius.Faithful.Gen.SelfSrcF_allocClosed
import all Lanius.Faithful.Gen.SelfSrcF_eDerefClosed
import all Lanius.Faithful.Gen.SelfSrcF_isPathCall
import all Lanius.Faithful.Gen.SelfSrcF_repeatEff
import all Lanius.Faithful.Gen.SelfSrcF_whileEvalOf
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

/-- mini::selfhost::lower_then -/
theorem lok200 : LiveOk prims outside liveBad 200 (src_lower_then 188) := by decide +kernel

/-- mini::selfhost::lower_set -/
theorem lok203 : LiveOk prims outside liveBad 203 (src_lower_set 193 330) := by decide +kernel

/-- mini::selfhost::lower_set_field -/
theorem lok204 : LiveOk prims outside liveBad 204 (src_lower_set_field 331) := by decide +kernel

/-- mini::selfhost::lower_set_call -/
theorem lok205 : LiveOk prims outside liveBad 205 (src_lower_set_call 120 198 332) := by decide +kernel

/-- mini::selfhost::lower_if -/
theorem lok206 : LiveOk prims outside liveBad 206 (src_lower_if 188) := by decide +kernel

/-- mini::selfhost::lower_while -/
theorem lok208 : LiveOk prims outside liveBad 208 (src_lower_while 334) := by decide +kernel

/-- mini::selfhost::lower_set_values -/
theorem lok330 : LiveOk prims outside liveBad 330 (src_lower_set_values 316) := by decide +kernel

/-- mini::selfhost::lower_set_field_of -/
theorem lok331 : LiveOk prims outside liveBad 331 (src_lower_set_field_of 75 181 519 520 521) := by decide +kernel

/-- mini::selfhost::lower_set_call_args -/
theorem lok332 : LiveOk prims outside liveBad 332 (src_lower_set_call_args) := by decide +kernel

/-- mini::selfhost::while_loop -/
theorem lok334 : LiveOk prims outside liveBad 334 (src_while_loop 188 312 336) := by decide +kernel

/-- mini::selfhost::eval_negate -/
theorem lok359 : LiveOk prims outside liveBad 359 (src_eval_negate 550 551) := by decide +kernel

/-- mini::selfhost::eval_division -/
theorem lok370 : LiveOk prims outside liveBad 370 (src_eval_division 560) := by decide +kernel

/-- mini::selfhost::lower_set_field_at -/
theorem lok519 : LiveOk prims outside liveBad 519 (src_lower_set_field_at 772) := by decide +kernel

/-- mini::selfhost::eval_then -/
theorem lok550 : LiveOk prims outside liveBad 550 (src_eval_then 188) := by decide +kernel

/-- mini::selfhost::scalar_cast -/
theorem lok553 : LiveOk prims outside liveBad 553 (src_scalar_cast 317 764) := by decide +kernel

/-- mini::selfhost::eval_divide -/
theorem lok560 : LiveOk prims outside liveBad 560 (src_eval_divide 75 188 338 391 803 808 809 810 811) := by decide +kernel

/-- mini::selfhost::mask -/
theorem lok760 : LiveOk prims outside liveBad 760 (src_UintTy_mask) := by decide +kernel

/-- mini::selfhost::p_array_some -/
theorem lok914 : LiveOk prims outside liveBad 914 (src_p_array_some) := by decide +kernel

/-- mini::selfhost::p_array_more -/
theorem lok915 : LiveOk prims outside liveBad 915 (src_p_array_more) := by decide +kernel

/-- mini::selfhost::number -/
theorem lok1029 : LiveOk prims outside liveBad 1029 (src_DivOp_number) := by decide +kernel

/-- mini::selfhost::number -/
theorem lok1030 : LiveOk prims outside liveBad 1030 (src_Syscall_number) := by decide +kernel

/-- mini::selfhost::lower_set_value -/
theorem lok1069 : LiveOk prims outside liveBad 1069 (src_lower_set_value) := by decide +kernel

/-- mini::selfhost::alloc_closed -/
theorem lok1164 : LiveOk prims outside liveBad 1164 (src_alloc_closed 1202) := by decide +kernel

/-- mini::selfhost::let_slice_closed -/
theorem lok1165 : LiveOk prims outside liveBad 1165 (src_let_slice_closed 1202) := by decide +kernel

/-- mini::selfhost::let_index_closed -/
theorem lok1166 : LiveOk prims outside liveBad 1166 (src_let_index_closed 1202) := by decide +kernel

/-- mini::selfhost::let_view_closed -/
theorem lok1167 : LiveOk prims outside liveBad 1167 (src_let_view_closed 1202) := by decide +kernel

/-- mini::selfhost::let_str_closed -/
theorem lok1168 : LiveOk prims outside liveBad 1168 (src_let_str_closed 1202) := by decide +kernel

/-- mini::selfhost::set_place_closed -/
theorem lok1182 : LiveOk prims outside liveBad 1182 (src_set_place_closed) := by decide +kernel

/-- mini::selfhost::set_place_op_closed -/
theorem lok1183 : LiveOk prims outside liveBad 1183 (src_set_place_op_closed) := by decide +kernel

/-- mini::selfhost::folds -/
theorem lok1252 : LiveOk prims outside liveBad 1252 (src_BinOp_folds) := by decide +kernel

/-- mini::selfhost::annihilates -/
theorem lok1254 : LiveOk prims outside liveBad 1254 (src_BinOp_annihilates) := by decide +kernel

/-- mini::selfhost::commutes -/
theorem lok1255 : LiveOk prims outside liveBad 1255 (src_BinOp_commutes) := by decide +kernel

/-- mini::selfhost::unit -/
theorem lok1257 : LiveOk prims outside liveBad 1257 (src_BinOp_unit) := by decide +kernel

/-- mini::selfhost::test -/
theorem lok1259 : LiveOk prims outside liveBad 1259 (src_CmpOp_test) := by decide +kernel

/-- mini::selfhost::e_call_closed -/
theorem lok1372 : LiveOk prims outside liveBad 1372 (src_e_call_closed 1447) := by decide +kernel

/-- mini::selfhost::e_apply_closed -/
theorem lok1374 : LiveOk prims outside liveBad 1374 (src_e_apply_closed 1449) := by decide +kernel

/-- mini::selfhost::e_index_closed -/
theorem lok1378 : LiveOk prims outside liveBad 1378 (src_e_index_closed 1449) := by decide +kernel

/-- mini::selfhost::e_array_slice_closed -/
theorem lok1383 : LiveOk prims outside liveBad 1383 (src_e_array_slice_closed) := by decide +kernel

/-- mini::selfhost::e_deref_closed -/
theorem lok1386 : LiveOk prims outside liveBad 1386 (src_e_deref_closed 1449) := by decide +kernel

/-- mini::selfhost::e_place_field_closed -/
theorem lok1387 : LiveOk prims outside liveBad 1387 (src_e_place_field_closed 1449) := by decide +kernel

/-- mini::selfhost::e_place_at_closed -/
theorem lok1388 : LiveOk prims outside liveBad 1388 (src_e_place_at_closed 1449) := by decide +kernel

/-- mini::selfhost::number -/
theorem lok1494 : LiveOk prims outside liveBad 1494 (src_BinOp_number) := by decide +kernel

/-- mini::selfhost::number -/
theorem lok1496 : LiveOk prims outside liveBad 1496 (src_CmpOp_number) := by decide +kernel

/-- mini::selfhost::scalar_prefix -/
theorem lok1631 : LiveOk prims outside liveBad 1631 (src_FloatTy_scalar_prefix) := by decide +kernel

/-- mini::selfhost::p_self_param_plain -/
theorem lok1673 : LiveOk prims outside liveBad 1673 (src_p_self_param_plain) := by decide +kernel

/-- mini::selfhost::rex -/
theorem lok1710 : LiveOk prims outside liveBad 1710 (src_FloatTy_rex 110 1043) := by decide +kernel

/-- mini::selfhost::p_base -/
theorem lok1804 : LiveOk prims outside liveBad 1804 (src_p_base) := by decide +kernel

/-- mini::selfhost::p_assign -/
theorem lok1805 : LiveOk prims outside liveBad 1805 (src_p_assign) := by decide +kernel

/-- mini::selfhost::p_assign_end -/
theorem lok1860 : LiveOk prims outside liveBad 1860 (src_p_assign_end) := by decide +kernel

/-- mini::selfhost::is_path_call -/
theorem lok1889 : LiveOk prims outside liveBad 1889 (src_is_path_call 153 156 1796 1797 1798 1802) := by decide +kernel

/-- mini::selfhost::p_array_repeat -/
theorem lok1906 : LiveOk prims outside liveBad 1906 (src_p_array_repeat) := by decide +kernel

/-- mini::selfhost::while_or_eval -/
theorem lok1941 : LiveOk prims outside liveBad 1941 (src_while_or_eval 1706 2073) := by decide +kernel

/-- mini::selfhost::match_ty -/
theorem lok1954 : LiveOk prims outside liveBad 1954 (src_match_ty 56 153 155 156 1600 1601 1606 1609 1954 2083 2084) := by decide +kernel

/-- mini::selfhost::match_args -/
theorem lok1957 : LiveOk prims outside liveBad 1957 (src_match_args 56 103 666 2086 2087) := by decide +kernel

/-- mini::selfhost::p_band_tail -/
theorem lok1972 : LiveOk prims outside liveBad 1972 (src_p_band_tail) := by decide +kernel

/-- mini::selfhost::named_parts -/
theorem lok2035 : LiveOk prims outside liveBad 2035 (src_named_parts 666) := by decide +kernel

/-- mini::selfhost::repeat_eff -/
theorem lok2041 : LiveOk prims outside liveBad 2041 (src_repeat_eff 56 1471 1472 2041) := by decide +kernel

/-- mini::selfhost::while_eval_of -/
theorem lok2073 : LiveOk prims outside liveBad 2073 (src_while_eval_of 2189) := by decide +kernel

/-- mini::selfhost::p_assign_set -/
theorem lok2076 : LiveOk prims outside liveBad 2076 (src_p_assign_set) := by decide +kernel

/-- mini::selfhost::match_path -/
theorem lok2084 : LiveOk prims outside liveBad 2084 (src_match_path 56 2215) := by decide +kernel

/-- mini::selfhost::bound_args -/
theorem lok2085 : LiveOk prims outside liveBad 2085 (src_bound_args 448 558 1621 2085 2216) := by decide +kernel

/-- mini::selfhost::match_args_next -/
theorem lok2086 : LiveOk prims outside liveBad 2086 (src_match_args_next 56 1957) := by decide +kernel

/-- mini::selfhost::match_arg -/
theorem lok2087 : LiveOk prims outside liveBad 2087 (src_match_arg 56 153 156 1791 1954) := by decide +kernel

/-- mini::selfhost::set_or_eval -/
theorem lok2203 : LiveOk prims outside liveBad 2203 (src_set_or_eval 2062 2328) := by decide +kernel

/-- mini::selfhost::is_try_call -/
theorem lok2212 : LiveOk prims outside liveBad 2212 (src_is_try_call 153 156 1796 1797 1798 1802 2340) := by decide +kernel

/-- mini::selfhost::match_named -/
theorem lok2215 : LiveOk prims outside liveBad 2215 (src_match_named 56 1671 1688 2035 2342 2343 2344 2345 2346) := by decide +kernel

/-- mini::selfhost::match_tys -/
theorem lok2258 : LiveOk prims outside liveBad 2258 (src_match_tys 56 103 666 1954 2406) := by decide +kernel

/-- mini::selfhost::is_try_method -/
theorem lok2308 : LiveOk prims outside liveBad 2308 (src_is_try_method 153 156 1796 1797 1798 1801 1802 1818 2016 2340) := by decide +kernel

/-- mini::selfhost::is_try_local -/
theorem lok2310 : LiveOk prims outside liveBad 2310 (src_is_try_local 153 156 1798 2340) := by decide +kernel

/-- mini::selfhost::stmt_unless -/
theorem lok2322 : LiveOk prims outside liveBad 2322 (src_stmt_unless) := by decide +kernel

/-- mini::selfhost::set_try_or_eval -/
theorem lok2328 : LiveOk prims outside liveBad 2328 (src_set_try_or_eval 1595 1671 1706 2333 2444) := by decide +kernel

/-- mini::selfhost::set_index_eval_of -/
theorem lok2330 : LiveOk prims outside liveBad 2330 (src_set_index_eval_of 2322 2443 2446) := by decide +kernel

/-- mini::selfhost::set_eval_of -/
theorem lok2333 : LiveOk prims outside liveBad 2333 (src_set_eval_of 2301 2456) := by decide +kernel

/-- mini::selfhost::match_decl -/
theorem lok2346 : LiveOk prims outside liveBad 2346 (src_match_decl 56 2468) := by decide +kernel

/-- mini::selfhost::text_core -/
theorem lok2384 : LiveOk prims outside liveBad 2384 (src_text_core 376 418) := by decide +kernel

/-- mini::selfhost::text_mem -/
theorem lok2385 : LiveOk prims outside liveBad 2385 (src_text_mem 376 418) := by decide +kernel

/-- mini::selfhost::text_i32_array_data_ptr -/
theorem lok2386 : LiveOk prims outside liveBad 2386 (src_text_i32_array_data_ptr 376 418) := by decide +kernel

/-- mini::selfhost::match_tys_next -/
theorem lok2406 : LiveOk prims outside liveBad 2406 (src_match_tys_next 56 2258) := by decide +kernel

/-- mini::selfhost::eff_acts -/
theorem lok2443 : LiveOk prims outside liveBad 2443 (src_eff_acts 1228 1229 2443 2518) := by decide +kernel

/-- mini::selfhost::try_set -/
theorem lok2444 : LiveOk prims outside liveBad 2444 (src_try_set 1241 2313) := by decide +kernel

/-- mini::selfhost::p_assign_add -/
theorem lok2448 : LiveOk prims outside liveBad 2448 (src_p_assign_add) := by decide +kernel

/-- mini::selfhost::p_assign_sub -/
theorem lok2449 : LiveOk prims outside liveBad 2449 (src_p_assign_sub) := by decide +kernel

/-- mini::selfhost::p_assign_mul -/
theorem lok2450 : LiveOk prims outside liveBad 2450 (src_p_assign_mul) := by decide +kernel

/-- mini::selfhost::p_assign_band -/
theorem lok2451 : LiveOk prims outside liveBad 2451 (src_p_assign_band) := by decide +kernel

/-- mini::selfhost::p_assign_bor -/
theorem lok2452 : LiveOk prims outside liveBad 2452 (src_p_assign_bor) := by decide +kernel

/-- mini::selfhost::p_assign_xor -/
theorem lok2453 : LiveOk prims outside liveBad 2453 (src_p_assign_xor) := by decide +kernel

/-- mini::selfhost::p_assign_shl -/
theorem lok2454 : LiveOk prims outside liveBad 2454 (src_p_assign_shl) := by decide +kernel

/-- mini::selfhost::p_assign_shr -/
theorem lok2455 : LiveOk prims outside liveBad 2455 (src_p_assign_shr) := by decide +kernel

/-- mini::selfhost::p_assign_div -/
theorem lok2457 : LiveOk prims outside liveBad 2457 (src_p_assign_div) := by decide +kernel

/-- mini::selfhost::p_assign_mod -/
theorem lok2458 : LiveOk prims outside liveBad 2458 (src_p_assign_mod) := by decide +kernel

/-- mini::selfhost::match_same_decl -/
theorem lok2468 : LiveOk prims outside liveBad 2468 (src_match_same_decl 56 1957) := by decide +kernel

/-- mini::selfhost::effs_act -/
theorem lok2518 : LiveOk prims outside liveBad 2518 (src_effs_act 1228 2443 2518) := by decide +kernel

/-- mini::selfhost::text_result -/
theorem lok2559 : LiveOk prims outside liveBad 2559 (src_text_result 376 418) := by decide +kernel

/-- mini::selfhost::text_result_ty -/
theorem lok2560 : LiveOk prims outside liveBad 2560 (src_text_result_ty 376 418) := by decide +kernel

/-- mini::selfhost::text_ok -/
theorem lok2561 : LiveOk prims outside liveBad 2561 (src_text_ok 376 418) := by decide +kernel

/-- mini::selfhost::text_err -/
theorem lok2562 : LiveOk prims outside liveBad 2562 (src_text_err 376 418) := by decide +kernel

/-- mini::selfhost::text_option -/
theorem lok2563 : LiveOk prims outside liveBad 2563 (src_text_option 376 418) := by decide +kernel

/-- mini::selfhost::text_option_ty -/
theorem lok2564 : LiveOk prims outside liveBad 2564 (src_text_option_ty 376 418) := by decide +kernel

/-- mini::selfhost::text_some -/
theorem lok2565 : LiveOk prims outside liveBad 2565 (src_text_some 376 418) := by decide +kernel

/-- mini::selfhost::text_none -/
theorem lok2566 : LiveOk prims outside liveBad 2566 (src_text_none 376 418) := by decide +kernel

end Lanius.Faithful.SelfPure
