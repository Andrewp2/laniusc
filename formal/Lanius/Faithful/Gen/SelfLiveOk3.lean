module

public import Lanius.Faithful.Gen.SelfPureTab
public import Lanius.Faithful.Gen.SelfLiveTab
public import Lanius.Faithful.Gen.SelfSrcC_evalSame
public import Lanius.Faithful.Gen.SelfSrcC_optimizeNeg
public import Lanius.Faithful.Gen.SelfSrcC_shortCircuit
public import Lanius.Faithful.Gen.SelfSrcC_storeType
public import Lanius.Faithful.Gen.SelfSrcC_wordStride
public import Lanius.Faithful.Gen.SelfSrcF_Inline_pAddTail
public import Lanius.Faithful.Gen.SelfSrcF_digitBelow
public import Lanius.Faithful.Gen.SelfSrcF_flExpFirst
public import Lanius.Faithful.Gen.SelfSrcF_lxLeadingDot
public import Lanius.Faithful.Gen.SelfSrcF_namesFieldBase
public import Lanius.Faithful.Gen.SelfSrcF_nestedUsed
import all Lanius.Faithful.Gen.SelfLiveTab
import all Lanius.Faithful.Gen.SelfPureTab
import all Lanius.Faithful.Gen.SelfSrcC_evalSame
import all Lanius.Faithful.Gen.SelfSrcC_optimizeNeg
import all Lanius.Faithful.Gen.SelfSrcC_shortCircuit
import all Lanius.Faithful.Gen.SelfSrcC_storeType
import all Lanius.Faithful.Gen.SelfSrcC_wordStride
import all Lanius.Faithful.Gen.SelfSrcF_Inline_pAddTail
import all Lanius.Faithful.Gen.SelfSrcF_digitBelow
import all Lanius.Faithful.Gen.SelfSrcF_flExpFirst
import all Lanius.Faithful.Gen.SelfSrcF_lxLeadingDot
import all Lanius.Faithful.Gen.SelfSrcF_namesFieldBase
import all Lanius.Faithful.Gen.SelfSrcF_nestedUsed
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

/-- mini::selfhost::eval -/
theorem lok223 : LiveOk prims outside liveBad 223 (src_SrcEff_eval 75 223 324 344 345 354 355 356 357 358 359 360 361 362 363 364 365 366 367 368 369 370 371 372 373 374 375 376 377 378 379) := by decide +kernel

/-- mini::selfhost::within_layout -/
theorem lok341 : LiveOk prims outside liveBad 341 (src_within_layout 75 180 181 183 526 527) := by decide +kernel

/-- mini::selfhost::eval_same -/
theorem lok350 : LiveOk prims outside liveBad 350 (src_eval_same 235) := by decide +kernel

/-- mini::selfhost::eval_args -/
theorem lok355 : LiveOk prims outside liveBad 355 (src_eval_args 75 120 223 239 355 356 545 546) := by decide +kernel

/-- mini::selfhost::eval_apply -/
theorem lok357 : LiveOk prims outside liveBad 357 (src_eval_apply 548) := by decide +kernel

/-- mini::selfhost::eval_struct -/
theorem lok362 : LiveOk prims outside liveBad 362 (src_eval_struct 181 184 323 554) := by decide +kernel

/-- mini::selfhost::eval_variant -/
theorem lok363 : LiveOk prims outside liveBad 363 (src_eval_variant 183 555) := by decide +kernel

/-- mini::selfhost::eval_arms -/
theorem lok365 : LiveOk prims outside liveBad 365 (src_eval_arms 75 183 356 365 375 557 558) := by decide +kernel

/-- mini::selfhost::eval_stride -/
theorem lok371 : LiveOk prims outside liveBad 371 (src_eval_stride 202 380 561) := by decide +kernel

/-- mini::selfhost::eval_len -/
theorem lok378 : LiveOk prims outside liveBad 378 (src_eval_len 202 565) := by decide +kernel

/-- mini::selfhost::eval_str -/
theorem lok379 : LiveOk prims outside liveBad 379 (src_eval_str 52 75 188 291 566) := by decide +kernel

/-- mini::selfhost::element_of -/
theorem lok380 : LiveOk prims outside liveBad 380 (src_element_of 184) := by decide +kernel

/-- mini::selfhost::within_layouts -/
theorem lok526 : LiveOk prims outside liveBad 526 (src_within_layouts 181 341 526) := by decide +kernel

/-- mini::selfhost::within_payloads -/
theorem lok527 : LiveOk prims outside liveBad 527 (src_within_payloads 180 183 526 527) := by decide +kernel

/-- mini::selfhost::eval_operands -/
theorem lok548 : LiveOk prims outside liveBad 548 (src_eval_operands 75 188 317 387 763 796 797 798 799) := by decide +kernel

/-- mini::selfhost::eval_struct_of -/
theorem lok554 : LiveOk prims outside liveBad 554 (src_eval_struct_of 180 388) := by decide +kernel

/-- mini::selfhost::eval_tagged -/
theorem lok555 : LiveOk prims outside liveBad 555 (src_eval_tagged 385 386 805) := by decide +kernel

/-- mini::selfhost::eval_stride_of -/
theorem lok561 : LiveOk prims outside liveBad 561 (src_eval_stride_of 338 339 812) := by decide +kernel

/-- mini::selfhost::eval_len_of -/
theorem lok565 : LiveOk prims outside liveBad 565 (src_eval_len_of 75 380) := by decide +kernel

/-- mini::selfhost::str_placed -/
theorem lok566 : LiveOk prims outside liveBad 566 (src_str_placed 75 76 566 813 814) := by decide +kernel

/-- mini::selfhost::projection_func -/
theorem lok682 : LiveOk prims outside liveBad 682 (src_projection_func 56 997 998) := by decide +kernel

/-- mini::selfhost::optimize_neg -/
theorem lok695 : LiveOk prims outside liveBad 695 (src_optimize_neg 337 702 1011) := by decide +kernel

/-- mini::selfhost::eval_load -/
theorem lok778 : LiveOk prims outside liveBad 778 (src_eval_load 188 312 337 338 339 533) := by decide +kernel

/-- mini::selfhost::short_circuit -/
theorem lok796 : LiveOk prims outside liveBad 796 (src_short_circuit) := by decide +kernel

/-- mini::selfhost::operand_guard -/
theorem lok798 : LiveOk prims outside liveBad 798 (src_operand_guard 758 759) := by decide +kernel

/-- mini::selfhost::eval_right -/
theorem lok799 : LiveOk prims outside liveBad 799 (src_eval_right 75 188) := by decide +kernel

/-- mini::selfhost::eval_payload -/
theorem lok805 : LiveOk prims outside liveBad 805 (src_eval_payload 188 388) := by decide +kernel

/-- mini::selfhost::eval_arm -/
theorem lok806 : LiveOk prims outside liveBad 806 (src_eval_arm 188 337) := by decide +kernel

/-- mini::selfhost::signed_div -/
theorem lok808 : LiveOk prims outside liveBad 808 (src_signed_div) := by decide +kernel

/-- mini::selfhost::eval_divide_uint -/
theorem lok811 : LiveOk prims outside liveBad 811 (src_eval_divide_uint 75 188 339 1086) := by decide +kernel

/-- mini::selfhost::eval_word_stride -/
theorem lok812 : LiveOk prims outside liveBad 812 (src_eval_word_stride 120 340 1087) := by decide +kernel

/-- mini::selfhost::static_byte_is -/
theorem lok813 : LiveOk prims outside liveBad 813 (src_static_byte_is) := by decide +kernel

/-- mini::selfhost::store_eval_then -/
theorem lok815 : LiveOk prims outside liveBad 815 (src_store_eval_then 188 235 312 338 339) := by decide +kernel

/-- mini::selfhost::store_type -/
theorem lok816 : LiveOk prims outside liveBad 816 (src_store_type 75 181 183 200 1088 1089 1090 1091 1092 1093) := by decide +kernel

/-- mini::selfhost::diverge_func -/
theorem lok994 : LiveOk prims outside liveBad 994 (src_diverge_func 996 1240 1241 1242 1243) := by decide +kernel

/-- mini::selfhost::read_fn -/
theorem lok995 : LiveOk prims outside liveBad 995 (src_read_fn 155 156 368 628 941 1232 1233 1234 1236 1237 1238 1244 1245 1246 1247 1248 1249) := by decide +kernel

/-- mini::selfhost::overflow_guard -/
theorem lok1085 : LiveOk prims outside liveBad 1085 (src_overflow_guard 75 337 1333) := by decide +kernel

/-- mini::selfhost::unsigned_div -/
theorem lok1086 : LiveOk prims outside liveBad 1086 (src_unsigned_div) := by decide +kernel

/-- mini::selfhost::word_stride -/
theorem lok1087 : LiveOk prims outside liveBad 1087 (src_word_stride 105 337) := by decide +kernel

/-- mini::selfhost::store_types -/
theorem lok1092 : LiveOk prims outside liveBad 1092 (src_store_types 75 105 120 181 200 816 1092) := by decide +kernel

/-- mini::selfhost::store_cases -/
theorem lok1093 : LiveOk prims outside liveBad 1093 (src_store_cases 75 183 337 1092 1093 1335) := by decide +kernel

/-- mini::selfhost::lx_from_number -/
theorem lok1102 : LiveOk prims outside liveBad 1102 (src_lx_from_number) := by decide +kernel

/-- mini::selfhost::lx_delimited -/
theorem lok1106 : LiveOk prims outside liveBad 1106 (src_lx_delimited) := by decide +kernel

/-- mini::selfhost::param_effs -/
theorem lok1243 : LiveOk prims outside liveBad 1243 (src_param_effs 982 1243 1471 1472) := by decide +kernel

/-- mini::selfhost::refs_checked -/
theorem lok1246 : LiveOk prims outside liveBad 1246 (src_refs_checked 148 156 607 1476 1477) := by decide +kernel

/-- mini::selfhost::float_want -/
theorem lok1433 : LiveOk prims outside liveBad 1433 (src_float_want 1575) := by decide +kernel

/-- mini::selfhost::refs_used_ok -/
theorem lok1477 : LiveOk prims outside liveBad 1477 (src_refs_used_ok 103 627 982 1477 1591 1615 1616 1617) := by decide +kernel

/-- mini::selfhost::float_pick -/
theorem lok1575 : LiveOk prims outside liveBad 1575 (src_float_pick 313 1545 1667) := by decide +kernel

/-- mini::selfhost::ref_uses_ok -/
theorem lok1617 : LiveOk prims outside liveBad 1617 (src_ref_uses_ok 56 103 934 1120 1617 1700 1701) := by decide +kernel

/-- mini::selfhost::lx_leading_dot -/
theorem lok1644 : LiveOk prims outside liveBad 1644 (src_lx_leading_dot 75 1338 1716) := by decide +kernel

/-- mini::selfhost::lx_best -/
theorem lok1645 : LiveOk prims outside liveBad 1645 (src_lx_best 1347 1645 1717) := by decide +kernel

/-- mini::selfhost::lx_fixed_at -/
theorem lok1646 : LiveOk prims outside liveBad 1646 (src_lx_fixed_at 52 75 1106 1718 1719) := by decide +kernel

/-- mini::selfhost::float_pick_of -/
theorem lok1667 : LiveOk prims outside liveBad 1667 (src_float_pick_of) := by decide +kernel

/-- mini::selfhost::ref_kids -/
theorem lok1701 : LiveOk prims outside liveBad 1701 (src_ref_kids 153 156 260 607 858 861 1763 1764 1765) := by decide +kernel

/-- mini::selfhost::lx_best_at -/
theorem lok1717 : LiveOk prims outside liveBad 1717 (src_lx_best_at 1776 1777) := by decide +kernel

/-- mini::selfhost::names_field_base -/
theorem lok1765 : LiveOk prims outside liveBad 1765 (src_names_field_base 153 156 1350 1796 1797 1799 1800 1801 1802) := by decide +kernel

/-- mini::selfhost::lx_starts_with -/
theorem lok1776 : LiveOk prims outside liveBad 1776 (src_lx_starts_with 76 1776) := by decide +kernel

/-- mini::selfhost::lx_longer -/
theorem lok1777 : LiveOk prims outside liveBad 1777 (src_lx_longer 52) := by decide +kernel

/-- mini::selfhost::float_literal -/
theorem lok1828 : LiveOk prims outside liveBad 1828 (src_float_literal 1882 1883 1884) := by decide +kernel

/-- mini::selfhost::fl_int_part -/
theorem lok1882 : LiveOk prims outside liveBad 1882 (src_fl_int_part 76 1997 1998) := by decide +kernel

/-- mini::selfhost::float_marker -/
theorem lok1884 : LiveOk prims outside liveBad 1884 (src_float_marker 1428 1999) := by decide +kernel

/-- mini::selfhost::p_add_tail -/
theorem lok1981 : LiveOk prims outside liveBad 1981 (src_p_add_tail) := by decide +kernel

/-- mini::selfhost::fl_frac_part -/
theorem lok2108 : LiveOk prims outside liveBad 2108 (src_fl_frac_part 76 1997 2232) := by decide +kernel

/-- mini::selfhost::fl_exp_part -/
theorem lok2109 : LiveOk prims outside liveBad 2109 (src_fl_exp_part 76 1997 2233) := by decide +kernel

/-- mini::selfhost::fl_exp_sign -/
theorem lok2370 : LiveOk prims outside liveBad 2370 (src_fl_exp_sign 76 2477) := by decide +kernel

/-- mini::selfhost::base_digit -/
theorem lok2476 : LiveOk prims outside liveBad 2476 (src_base_digit 56 2525) := by decide +kernel

/-- mini::selfhost::nested_with -/
theorem lok2511 : LiveOk prims outside liveBad 2511 (src_nested_with 2547 2548 2549) := by decide +kernel

/-- mini::selfhost::digit_below -/
theorem lok2525 : LiveOk prims outside liveBad 2525 (src_digit_below) := by decide +kernel

/-- mini::selfhost::fl_exp_first -/
theorem lok2526 : LiveOk prims outside liveBad 2526 (src_fl_exp_first 76 2568) := by decide +kernel

/-- mini::selfhost::nested_used -/
theorem lok2548 : LiveOk prims outside liveBad 2548 (src_nested_used 2591) := by decide +kernel

/-- mini::selfhost::block_value -/
theorem lok2577 : LiveOk prims outside liveBad 2577 (src_block_value 56 153 156 606 1764 1798 1803 1804 1805 1807 1809 2507 2577) := by decide +kernel

end Lanius.Faithful.SelfPure
