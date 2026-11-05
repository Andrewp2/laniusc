module

public import Lanius.Faithful.Gen.SelfPureTab
public import Lanius.Faithful.Gen.SelfLiveTab
public import Lanius.Faithful.Gen.SelfSrcC_armBodyScope
public import Lanius.Faithful.Gen.SelfSrcC_declareProgram
public import Lanius.Faithful.Gen.SelfSrcC_lowerTagged
public import Lanius.Faithful.Gen.SelfSrcF_Inline_pModTail
public import Lanius.Faithful.Gen.SelfSrcF_Inline_pRetVoid
public import Lanius.Faithful.Gen.SelfSrcF_Inline_pSelfParamTyped
public import Lanius.Faithful.Gen.SelfSrcF_argView
public import Lanius.Faithful.Gen.SelfSrcF_collect
public import Lanius.Faithful.Gen.SelfSrcF_negWideI32
public import Lanius.Faithful.Gen.SelfSrcF_readInst
import all Lanius.Faithful.Gen.SelfLiveTab
import all Lanius.Faithful.Gen.SelfPureTab
import all Lanius.Faithful.Gen.SelfSrcC_armBodyScope
import all Lanius.Faithful.Gen.SelfSrcC_declareProgram
import all Lanius.Faithful.Gen.SelfSrcC_lowerTagged
import all Lanius.Faithful.Gen.SelfSrcF_Inline_pModTail
import all Lanius.Faithful.Gen.SelfSrcF_Inline_pRetVoid
import all Lanius.Faithful.Gen.SelfSrcF_Inline_pSelfParamTyped
import all Lanius.Faithful.Gen.SelfSrcF_argView
import all Lanius.Faithful.Gen.SelfSrcF_collect
import all Lanius.Faithful.Gen.SelfSrcF_negWideI32
import all Lanius.Faithful.Gen.SelfSrcF_readInst
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

/-- mini::selfhost::funcs_return -/
theorem lok37 : LiveOk prims outside liveBad 37 (src_funcs_return 37 57 58 59) := by decide +kernel

/-- mini::selfhost::declare_program -/
theorem lok39 : LiveOk prims outside liveBad 39 (src_declare_program 63 64 65) := by decide +kernel

/-- mini::selfhost::file_decls -/
theorem lok100 : LiveOk prims outside liveBad 100 (src_file_decls 153 154 155 156 157 158) := by decide +kernel

/-- mini::selfhost::collect_files -/
theorem lok102 : LiveOk prims outside liveBad 102 (src_collect_files 100 103 164) := by decide +kernel

/-- mini::selfhost::file_items -/
theorem lok157 : LiveOk prims outside liveBad 157 (src_file_items 263 264) := by decide +kernel

/-- mini::selfhost::viewed_type -/
theorem lok185 : LiveOk prims outside liveBad 185 (src_viewed_type) := by decide +kernel

/-- mini::selfhost::lower_enum_value -/
theorem lok199 : LiveOk prims outside liveBad 199 (src_lower_enum_value 183 326) := by decide +kernel

/-- mini::selfhost::arm_body_scope -/
theorem lok233 : LiveOk prims outside liveBad 233 (src_arm_body_scope 194) := by decide +kernel

/-- mini::selfhost::file_collected -/
theorem lok263 : LiveOk prims outside liveBad 263 (src_file_collected) := by decide +kernel

/-- mini::selfhost::collect -/
theorem lok264 : LiveOk prims outside liveBad 264 (src_collect 103 264 425 426 427) := by decide +kernel

/-- mini::selfhost::well_named -/
theorem lok268 : LiveOk prims outside liveBad 268 (src_well_named 163 431 432 433 434 435) := by decide +kernel

/-- mini::selfhost::collected_with -/
theorem lok277 : LiveOk prims outside liveBad 277 (src_collected_with 104 161 163 435 451 452 453 454 455 456 457 458 459 460 461) := by decide +kernel

/-- mini::selfhost::lower_tagged -/
theorem lok326 : LiveOk prims outside liveBad 326 (src_lower_tagged 385 386 517) := by decide +kernel

/-- mini::selfhost::p_module -/
theorem lok428 : LiveOk prims outside liveBad 428 (src_p_module) := by decide +kernel

/-- mini::selfhost::modules_distinct_names -/
theorem lok432 : LiveOk prims outside liveBad 432 (src_modules_distinct_names 432 651 652) := by decide +kernel

/-- mini::selfhost::no_primitive -/
theorem lok433 : LiveOk prims outside liveBad 433 (src_no_primitive 276 433 653 654) := by decide +kernel

/-- mini::selfhost::no_primitive_alias -/
theorem lok434 : LiveOk prims outside liveBad 434 (src_no_primitive_alias 434 653 654 655) := by decide +kernel

/-- mini::selfhost::read_inst -/
theorem lok444 : LiveOk prims outside liveBad 444 (src_read_inst 680 681 682 683) := by decide +kernel

/-- mini::selfhost::no_names -/
theorem lok446 : LiveOk prims outside liveBad 446 (src_no_names) := by decide +kernel

/-- mini::selfhost::p_path_ident -/
theorem lok645 : LiveOk prims outside liveBad 645 (src_p_path_ident) := by decide +kernel

/-- mini::selfhost::p_path_end -/
theorem lok646 : LiveOk prims outside liveBad 646 (src_p_path_end) := by decide +kernel

/-- mini::selfhost::module_names_ok -/
theorem lok652 : LiveOk prims outside liveBad 652 (src_module_names_ok 940 941 942 943 944 945 946) := by decide +kernel

/-- mini::selfhost::is_none_type -/
theorem lok653 : LiveOk prims outside liveBad 653 (src_is_none_type) := by decide +kernel

/-- mini::selfhost::lit_funcs -/
theorem lok659 : LiveOk prims outside liveBad 659 (src_lit_funcs 59 659 952 965 966 967) := by decide +kernel

/-- mini::selfhost::unit_payload -/
theorem lok820 : LiveOk prims outside liveBad 820 (src_unit_payload 541) := by decide +kernel

/-- mini::selfhost::field_payload -/
theorem lok821 : LiveOk prims outside liveBad 821 (src_field_payload) := by decide +kernel

/-- mini::selfhost::p_params_none -/
theorem lok851 : LiveOk prims outside liveBad 851 (src_p_params_none) := by decide +kernel

/-- mini::selfhost::p_params_some -/
theorem lok852 : LiveOk prims outside liveBad 852 (src_p_params_some) := by decide +kernel

/-- mini::selfhost::p_params_more -/
theorem lok853 : LiveOk prims outside liveBad 853 (src_p_params_more) := by decide +kernel

/-- mini::selfhost::p_params_end -/
theorem lok854 : LiveOk prims outside liveBad 854 (src_p_params_end) := by decide +kernel

/-- mini::selfhost::p_params_after_comma_more -/
theorem lok855 : LiveOk prims outside liveBad 855 (src_p_params_after_comma_more) := by decide +kernel

/-- mini::selfhost::p_params_after_comma_trailing -/
theorem lok856 : LiveOk prims outside liveBad 856 (src_p_params_after_comma_trailing) := by decide +kernel

/-- mini::selfhost::fn_names_in -/
theorem lok942 : LiveOk prims outside liveBad 942 (src_fn_names_in 265 274 1143) := by decide +kernel

/-- mini::selfhost::type_only_names_in -/
theorem lok943 : LiveOk prims outside liveBad 943 (src_type_only_names_in 265 276 1144) := by decide +kernel

/-- mini::selfhost::alias_names_in -/
theorem lok944 : LiveOk prims outside liveBad 944 (src_alias_names_in 265 655 1145) := by decide +kernel

/-- mini::selfhost::const_names_in -/
theorem lok945 : LiveOk prims outside liveBad 945 (src_const_names_in 265 688 1146) := by decide +kernel

/-- mini::selfhost::enums_named_ok -/
theorem lok946 : LiveOk prims outside liveBad 946 (src_enums_named_ok 276 946 1147) := by decide +kernel

/-- mini::selfhost::lit_stmt -/
theorem lok966 : LiveOk prims outside liveBad 966 (src_lit_stmt 81 217 966 1201 1202 1203 1204 1205 1206 1207 1208 1209 1210 1211 1212 1213 1214) := by decide +kernel

/-- mini::selfhost::param_locals -/
theorem lok967 : LiveOk prims outside liveBad 967 (src_param_locals 174 967 1215 1216) := by decide +kernel

/-- mini::selfhost::eff_calls -/
theorem lok990 : LiveOk prims outside liveBad 990 (src_eff_calls 272 447 989 990 1228 1229 1230) := by decide +kernel

/-- mini::selfhost::low_bits -/
theorem lok1011 : LiveOk prims outside liveBad 1011 (src_low_bits) := by decide +kernel

/-- mini::selfhost::enum_named_ok -/
theorem lok1147 : LiveOk prims outside liveBad 1147 (src_enum_named_ok 939 940 1364) := by decide +kernel

/-- mini::selfhost::lit_expr -/
theorem lok1201 : LiveOk prims outside liveBad 1201 (src_lit_expr 313 1201 1424 1425 1426 1427 1428 1429 1430 1431 1432 1433) := by decide +kernel

/-- mini::selfhost::with_local -/
theorem lok1203 : LiveOk prims outside liveBad 1203 (src_with_local 1216) := by decide +kernel

/-- mini::selfhost::lit_exprs -/
theorem lok1204 : LiveOk prims outside liveBad 1204 (src_lit_exprs 321 1201 1204 1435 1436 1437 1438) := by decide +kernel

/-- mini::selfhost::callee_params -/
theorem lok1206 : LiveOk prims outside liveBad 1206 (src_callee_params 1439 1440) := by decide +kernel

/-- mini::selfhost::lit_src_arms -/
theorem lok1209 : LiveOk prims outside liveBad 1209 (src_lit_src_arms 1066 1201 1207 1209 1441 1442 1443 1444) := by decide +kernel

/-- mini::selfhost::lit_eff -/
theorem lok1213 : LiveOk prims outside liveBad 1213 (src_lit_eff 356 358 1201 1205 1206 1207 1208 1213 1216 1429 1431 1447 1448 1449 1450 1451) := by decide +kernel

/-- mini::selfhost::effs_calls -/
theorem lok1230 : LiveOk prims outside liveBad 1230 (src_effs_calls 272 989 990 1228 1230) := by decide +kernel

/-- mini::selfhost::module_globals -/
theorem lok1232 : LiveOk prims outside liveBad 1232 (src_module_globals 941 944 945 1461) := by decide +kernel

/-- mini::selfhost::signed_key -/
theorem lok1260 : LiveOk prims outside liveBad 1260 (src_signed_key 1011) := by decide +kernel

/-- mini::selfhost::p_path_ident_args -/
theorem lok1355 : LiveOk prims outside liveBad 1355 (src_p_path_ident_args) := by decide +kernel

/-- mini::selfhost::none_member -/
theorem lok1364 : LiveOk prims outside liveBad 1364 (src_none_member 558 1142 1364) := by decide +kernel

/-- mini::selfhost::wide_left -/
theorem lok1396 : LiveOk prims outside liveBad 1396 (src_wide_left 313 1396 1545) := by decide +kernel

/-- mini::selfhost::wide_left_exprs -/
theorem lok1397 : LiveOk prims outside liveBad 1397 (src_wide_left_exprs 321 1396 1397) := by decide +kernel

/-- mini::selfhost::wide_left_arms -/
theorem lok1398 : LiveOk prims outside liveBad 1398 (src_wide_left_arms 1066 1396 1398) := by decide +kernel

/-- mini::selfhost::wide_left_eff -/
theorem lok1399 : LiveOk prims outside liveBad 1399 (src_wide_left_eff 356 358 1396 1399 1546) := by decide +kernel

/-- mini::selfhost::neg_wide_at -/
theorem lok1426 : LiveOk prims outside liveBad 1426 (src_neg_wide_at 1562 1563 1564) := by decide +kernel

/-- mini::selfhost::neg_least -/
theorem lok1427 : LiveOk prims outside liveBad 1427 (src_neg_least 1565) := by decide +kernel

/-- mini::selfhost::known_expr -/
theorem lok1430 : LiveOk prims outside liveBad 1430 (src_known_expr 313 1205 1210 1211 1430 1570 1571) := by decide +kernel

/-- mini::selfhost::src_param_tys -/
theorem lok1440 : LiveOk prims outside liveBad 1440 (src_src_param_tys 174 239 240 1440) := by decide +kernel

/-- mini::selfhost::lit_effs -/
theorem lok1448 : LiveOk prims outside liveBad 1448 (src_lit_effs 356 1213 1437 1438 1448 1537 1580) := by decide +kernel

/-- mini::selfhost::known_eff -/
theorem lok1450 : LiveOk prims outside liveBad 1450 (src_known_eff 217 358 1210 1212 1430 1450 1568 1570 1582) := by decide +kernel

/-- mini::selfhost::lit_arm_effs -/
theorem lok1451 : LiveOk prims outside liveBad 1451 (src_lit_arm_effs 356 1207 1213 1443 1444 1451 1537 1580 1583 1584) := by decide +kernel

/-- mini::selfhost::type_names_in -/
theorem lok1461 : LiveOk prims outside liveBad 1461 (src_type_names_in 265 276 1590) := by decide +kernel

/-- mini::selfhost::p_ret_void -/
theorem lok1464 : LiveOk prims outside liveBad 1464 (src_p_ret_void) := by decide +kernel

/-- mini::selfhost::compute -/
theorem lok1485 : LiveOk prims outside liveBad 1485 (src_BinOp_compute) := by decide +kernel

/-- mini::selfhost::wide_left_effs -/
theorem lok1546 : LiveOk prims outside liveBad 1546 (src_wide_left_effs 356 1399 1546) := by decide +kernel

/-- mini::selfhost::neg_wide_i32 -/
theorem lok1562 : LiveOk prims outside liveBad 1562 (src_neg_wide_i32) := by decide +kernel

/-- mini::selfhost::neg_wide_isize -/
theorem lok1563 : LiveOk prims outside liveBad 1563 (src_neg_wide_isize 1428) := by decide +kernel

/-- mini::selfhost::neg_wide_sint -/
theorem lok1564 : LiveOk prims outside liveBad 1564 (src_neg_wide_sint 1428 1664) := by decide +kernel

/-- mini::selfhost::neg_least_at -/
theorem lok1565 : LiveOk prims outside liveBad 1565 (src_neg_least_at 1665) := by decide +kernel

/-- mini::selfhost::callee_ret -/
theorem lok1582 : LiveOk prims outside liveBad 1582 (src_callee_ret 1439) := by decide +kernel

/-- mini::selfhost::p_param_named -/
theorem lok1592 : LiveOk prims outside liveBad 1592 (src_p_param_named) := by decide +kernel

/-- mini::selfhost::p_param_self -/
theorem lok1593 : LiveOk prims outside liveBad 1593 (src_p_param_self) := by decide +kernel

/-- mini::selfhost::p_param_self_ref -/
theorem lok1594 : LiveOk prims outside liveBad 1594 (src_p_param_self_ref) := by decide +kernel

/-- mini::selfhost::least_cast -/
theorem lok1665 : LiveOk prims outside liveBad 1665 (src_least_cast 1428 1738) := by decide +kernel

/-- mini::selfhost::p_self_param_typed -/
theorem lok1674 : LiveOk prims outside liveBad 1674 (src_p_self_param_typed) := by decide +kernel

/-- mini::selfhost::p_type_ref -/
theorem lok1675 : LiveOk prims outside liveBad 1675 (src_p_type_ref) := by decide +kernel

/-- mini::selfhost::p_type_ref_mut -/
theorem lok1677 : LiveOk prims outside liveBad 1677 (src_p_type_ref_mut) := by decide +kernel

/-- mini::selfhost::p_neg -/
theorem lok1811 : LiveOk prims outside liveBad 1811 (src_p_neg) := by decide +kernel

/-- mini::selfhost::p_not -/
theorem lok1813 : LiveOk prims outside liveBad 1813 (src_p_not) := by decide +kernel

/-- mini::selfhost::p_path -/
theorem lok1859 : LiveOk prims outside liveBad 1859 (src_p_path) := by decide +kernel

/-- mini::selfhost::p_orexpr -/
theorem lok1861 : LiveOk prims outside liveBad 1861 (src_p_orexpr) := by decide +kernel

/-- mini::selfhost::p_mul -/
theorem lok1870 : LiveOk prims outside liveBad 1870 (src_p_mul) := by decide +kernel

/-- mini::selfhost::p_return_stmt -/
theorem lok1928 : LiveOk prims outside liveBad 1928 (src_p_return_stmt) := by decide +kernel

/-- mini::selfhost::p_return_value -/
theorem lok1929 : LiveOk prims outside liveBad 1929 (src_p_return_value) := by decide +kernel

/-- mini::selfhost::p_return_void -/
theorem lok1933 : LiveOk prims outside liveBad 1933 (src_p_return_void) := by decide +kernel

/-- mini::selfhost::p_or_tail -/
theorem lok1968 : LiveOk prims outside liveBad 1968 (src_p_or_tail) := by decide +kernel

/-- mini::selfhost::p_ne_tail -/
theorem lok1974 : LiveOk prims outside liveBad 1974 (src_p_ne_tail) := by decide +kernel

/-- mini::selfhost::p_mul_tail -/
theorem lok1983 : LiveOk prims outside liveBad 1983 (src_p_mul_tail) := by decide +kernel

/-- mini::selfhost::p_mod_tail -/
theorem lok2002 : LiveOk prims outside liveBad 2002 (src_p_mod_tail) := by decide +kernel

/-- mini::selfhost::views_of -/
theorem lok2393 : LiveOk prims outside liveBad 2393 (src_views_of 2482) := by decide +kernel

/-- mini::selfhost::arg_views -/
theorem lok2482 : LiveOk prims outside liveBad 2482 (src_arg_views 1228 1471 2043 2044 2045 2482 2528) := by decide +kernel

/-- mini::selfhost::view_of -/
theorem lok2492 : LiveOk prims outside liveBad 2492 (src_view_of 2528) := by decide +kernel

/-- mini::selfhost::arg_view -/
theorem lok2528 : LiveOk prims outside liveBad 2528 (src_arg_view 2255 2569 2570) := by decide +kernel

end Lanius.Faithful.SelfPure
