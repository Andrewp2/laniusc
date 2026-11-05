module

public import Lanius.Faithful.Gen.SelfPureTab
public import Lanius.Faithful.Gen.SelfLiveTab
public import Lanius.Faithful.Gen.SelfSrcC_Inline_arithOf
public import Lanius.Faithful.Gen.SelfSrcC_compileArgs
public import Lanius.Faithful.Gen.SelfSrcC_lowerApply
public import Lanius.Faithful.Gen.SelfSrcC_lowerCallSig
public import Lanius.Faithful.Gen.SelfSrcF_Inline_pStmtsMore
public import Lanius.Faithful.Gen.SelfSrcF_closeFuncs
public import Lanius.Faithful.Gen.SelfSrcF_compoundOf
public import Lanius.Faithful.Gen.SelfSrcF_consBinder
public import Lanius.Faithful.Gen.SelfSrcF_isTypedSliceSegments
public import Lanius.Faithful.Gen.SelfSrcF_litWants
public import Lanius.Faithful.Gen.SelfSrcF_lxDotAt
public import Lanius.Faithful.Gen.SelfSrcF_strBytes
import all Lanius.Faithful.Gen.SelfLiveTab
import all Lanius.Faithful.Gen.SelfPureTab
import all Lanius.Faithful.Gen.SelfSrcC_Inline_arithOf
import all Lanius.Faithful.Gen.SelfSrcC_compileArgs
import all Lanius.Faithful.Gen.SelfSrcC_lowerApply
import all Lanius.Faithful.Gen.SelfSrcC_lowerCallSig
import all Lanius.Faithful.Gen.SelfSrcF_Inline_pStmtsMore
import all Lanius.Faithful.Gen.SelfSrcF_closeFuncs
import all Lanius.Faithful.Gen.SelfSrcF_compoundOf
import all Lanius.Faithful.Gen.SelfSrcF_consBinder
import all Lanius.Faithful.Gen.SelfSrcF_isTypedSliceSegments
import all Lanius.Faithful.Gen.SelfSrcF_litWants
import all Lanius.Faithful.Gen.SelfSrcF_lxDotAt
import all Lanius.Faithful.Gen.SelfSrcF_strBytes
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

/-- mini::selfhost::lower_call -/
theorem lok198 : LiveOk prims outside liveBad 198 (src_lower_call 324 325) := by decide +kernel

/-- mini::selfhost::image_limit -/
theorem lok290 : LiveOk prims outside liveBad 290 (src_image_limit) := by decide +kernel

/-- mini::selfhost::spend -/
theorem lok300 : LiveOk prims outside liveBad 300 (src_spend 56) := by decide +kernel

/-- mini::selfhost::lower -/
theorem lok315 : LiveOk prims outside liveBad 315 (src_SrcExpr_lower 202 313 315 502 503 504 505 506 507 508 509 510) := by decide +kernel

/-- mini::selfhost::lower_call_sig -/
theorem lok325 : LiveOk prims outside liveBad 325 (src_lower_call_sig 235 516) := by decide +kernel

/-- mini::selfhost::is_one -/
theorem lok336 : LiveOk prims outside liveBad 336 (src_is_one) := by decide +kernel

/-- mini::selfhost::eval_pure -/
theorem lok345 : LiveOk prims outside liveBad 345 (src_eval_pure 191 202 315 530 531 532) := by decide +kernel

/-- mini::selfhost::lx_raw -/
theorem lok412 : LiveOk prims outside liveBad 412 (src_lx_raw 56 75 412 589 590 591 592 593) := by decide +kernel

/-- mini::selfhost::stmt_room -/
theorem lok472 : LiveOk prims outside liveBad 472 (src_stmt_room 300 307 472 729 730 731 732) := by decide +kernel

/-- mini::selfhost::temps -/
theorem lok473 : LiveOk prims outside liveBad 473 (src_Stmt_temps 75 186 307 473 733 734) := by decide +kernel

/-- mini::selfhost::within -/
theorem lok474 : LiveOk prims outside liveBad 474 (src_Stmt_within 75 307 474 735 736 737 738) := by decide +kernel

/-- mini::selfhost::frame_limit -/
theorem lok475 : LiveOk prims outside liveBad 475 (src_frame_limit) := by decide +kernel

/-- mini::selfhost::zero_locals -/
theorem lok477 : LiveOk prims outside liveBad 477 (src_zero_locals 56 75 476 477 740) := by decide +kernel

/-- mini::selfhost::compile_stmt -/
theorem lok479 : LiveOk prims outside liveBad 479 (src_compile_stmt 307 476 478 479 740 742 743 744 745 746 747 748) := by decide +kernel

/-- mini::selfhost::lower_apply -/
theorem lok508 : LiveOk prims outside liveBad 508 (src_lower_apply 763) := by decide +kernel

/-- mini::selfhost::eval_checked -/
theorem lok530 : LiveOk prims outside liveBad 530 (src_eval_checked 312) := by decide +kernel

/-- mini::selfhost::eval_copy -/
theorem lok531 : LiveOk prims outside liveBad 531 (src_eval_copy 193 782) := by decide +kernel

/-- mini::selfhost::eval_field_copy -/
theorem lok532 : LiveOk prims outside liveBad 532 (src_eval_field_copy 783) := by decide +kernel

/-- mini::selfhost::eval_call_sig -/
theorem lok543 : LiveOk prims outside liveBad 543 (src_eval_call_sig 120 180 188 353 388) := by decide +kernel

/-- mini::selfhost::eval_arm_in -/
theorem lok557 : LiveOk prims outside liveBad 557 (src_eval_arm_in 223 350 545 806) := by decide +kernel

/-- mini::selfhost::arm_bind -/
theorem lok564 : LiveOk prims outside liveBad 564 (src_arm_bind 75 120 185 194 375) := by decide +kernel

/-- mini::selfhost::lx_one_at -/
theorem lok590 : LiveOk prims outside liveBad 590 (src_lx_one_at 830 831) := by decide +kernel

/-- mini::selfhost::lx_prepend -/
theorem lok591 : LiveOk prims outside liveBad 591 (src_lx_prepend 832) := by decide +kernel

/-- mini::selfhost::lx_shift -/
theorem lok592 : LiveOk prims outside liveBad 592 (src_lx_shift 75) := by decide +kernel

/-- mini::selfhost::lx_drop_to -/
theorem lok598 : LiveOk prims outside liveBad 598 (src_lx_drop_to 56 593) := by decide +kernel

/-- mini::selfhost::p_struct -/
theorem lok616 : LiveOk prims outside liveBad 616 (src_p_struct) := by decide +kernel

/-- mini::selfhost::close_funcs -/
theorem lok656 : LiveOk prims outside liveBad 656 (src_close_funcs 656 676 952 953 954 955 956 957) := by decide +kernel

/-- mini::selfhost::temps -/
theorem lok733 : LiveOk prims outside liveBad 733 (src_Expr_temps 75 186 492 733) := by decide +kernel

/-- mini::selfhost::args_temps -/
theorem lok734 : LiveOk prims outside liveBad 734 (src_args_temps 75 186 493 733 734) := by decide +kernel

/-- mini::selfhost::within -/
theorem lok735 : LiveOk prims outside liveBad 735 (src_Expr_within 492 735) := by decide +kernel

/-- mini::selfhost::arity_is -/
theorem lok736 : LiveOk prims outside liveBad 736 (src_arity_is 1033) := by decide +kernel

/-- mini::selfhost::all_within -/
theorem lok738 : LiveOk prims outside liveBad 738 (src_all_within 493 735 738) := by decide +kernel

/-- mini::selfhost::compile_args -/
theorem lok747 : LiveOk prims outside liveBad 747 (src_compile_args 75 478 493 740 742 743 747) := by decide +kernel

/-- mini::selfhost::arg_slots -/
theorem lok748 : LiveOk prims outside liveBad 748 (src_arg_slots 75 139 418 493 748) := by decide +kernel

/-- mini::selfhost::copy_same -/
theorem lok766 : LiveOk prims outside liveBad 766 (src_copy_same 120 235 353) := by decide +kernel

/-- mini::selfhost::eval_values -/
theorem lok782 : LiveOk prims outside liveBad 782 (src_eval_values 316) := by decide +kernel

/-- mini::selfhost::eval_field_of -/
theorem lok783 : LiveOk prims outside liveBad 783 (src_eval_field_of 181 521 1072) := by decide +kernel

/-- mini::selfhost::host_byte_code -/
theorem lok789 : LiveOk prims outside liveBad 789 (src_host_byte_code 75 188 189 337 542) := by decide +kernel

/-- mini::selfhost::host_write_code -/
theorem lok790 : LiveOk prims outside liveBad 790 (src_host_write_code 75 188 189 337 542) := by decide +kernel

/-- mini::selfhost::host_read_code -/
theorem lok791 : LiveOk prims outside liveBad 791 (src_host_read_code 75 188 189 337 542) := by decide +kernel

/-- mini::selfhost::host_sleep_code -/
theorem lok792 : LiveOk prims outside liveBad 792 (src_host_sleep_code 75 188 189 337 542) := by decide +kernel

/-- mini::selfhost::host_clock_code -/
theorem lok793 : LiveOk prims outside liveBad 793 (src_host_clock_code 75 188 189 337 542) := by decide +kernel

/-- mini::selfhost::lx_one_first -/
theorem lok831 : LiveOk prims outside liveBad 831 (src_lx_one_first 75 593 1099 1100 1101 1102 1103 1104 1105 1106 1107 1108 1109) := by decide +kernel

/-- mini::selfhost::lx_trivia -/
theorem lok839 : LiveOk prims outside liveBad 839 (src_lx_trivia) := by decide +kernel

/-- mini::selfhost::p_stmts_more -/
theorem lok849 : LiveOk prims outside liveBad 849 (src_p_stmts_more) := by decide +kernel

/-- mini::selfhost::expr_room -/
theorem lok1031 : LiveOk prims outside liveBad 1031 (src_expr_room 300 492 729) := by decide +kernel

/-- mini::selfhost::args_room -/
theorem lok1032 : LiveOk prims outside liveBad 1032 (src_args_room 300 493 729 731) := by decide +kernel

/-- mini::selfhost::eval_field_type -/
theorem lok1072 : LiveOk prims outside liveBad 1072 (src_eval_field_type 193 1328) := by decide +kernel

/-- mini::selfhost::lx_symbol -/
theorem lok1109 : LiveOk prims outside liveBad 1109 (src_lx_symbol 830 1342) := by decide +kernel

/-- mini::selfhost::lx_keyword -/
theorem lok1116 : LiveOk prims outside liveBad 1116 (src_lx_keyword 1346 1347) := by decide +kernel

/-- mini::selfhost::place_stmt -/
theorem lok1197 : LiveOk prims outside liveBad 1197 (src_place_stmt 81 754 1197 1198 1202 1421 1422) := by decide +kernel

/-- mini::selfhost::stmt_bytes -/
theorem lok1198 : LiveOk prims outside liveBad 1198 (src_stmt_bytes 81 110 754 1198 1422) := by decide +kernel

/-- mini::selfhost::lower_scalar_slot -/
theorem lok1303 : LiveOk prims outside liveBad 1303 (src_lower_scalar_slot 317) := by decide +kernel

/-- mini::selfhost::copy_slots -/
theorem lok1323 : LiveOk prims outside liveBad 1323 (src_copy_slots 120 235 353) := by decide +kernel

/-- mini::selfhost::eval_sized -/
theorem lok1328 : LiveOk prims outside liveBad 1328 (src_eval_sized 120 782) := by decide +kernel

/-- mini::selfhost::lx_symbol_at -/
theorem lok1342 : LiveOk prims outside liveBad 1342 (src_lx_symbol_at 75 830 1528 1529) := by decide +kernel

/-- mini::selfhost::place_eff -/
theorem lok1421 : LiveOk prims outside liveBad 1421 (src_place_eff 291 356 358 754 1421 1422 1447 1449 1557) := by decide +kernel

/-- mini::selfhost::eff_bytes -/
theorem lok1422 : LiveOk prims outside liveBad 1422 (src_eff_bytes 110 356 358 754 1422 1558 1559) := by decide +kernel

/-- mini::selfhost::writes_local -/
theorem lok1479 : LiveOk prims outside liveBad 1479 (src_writes_local 983 1479) := by decide +kernel

/-- mini::selfhost::float_arith_of -/
theorem lok1512 : LiveOk prims outside liveBad 1512 (src_float_arith_of 393 1635 1636) := by decide +kernel

/-- mini::selfhost::arith_signed_of -/
theorem lok1513 : LiveOk prims outside liveBad 1513 (src_arith_signed_of 337 394 1083 1084) := by decide +kernel

/-- mini::selfhost::arith_of -/
theorem lok1514 : LiveOk prims outside liveBad 1514 (src_arith_of 337 339 1314) := by decide +kernel

/-- mini::selfhost::float_order_of -/
theorem lok1515 : LiveOk prims outside liveBad 1515 (src_float_order_of 393 1637) := by decide +kernel

/-- mini::selfhost::order_signed_of -/
theorem lok1516 : LiveOk prims outside liveBad 1516 (src_order_signed_of 337 394 1083 1310) := by decide +kernel

/-- mini::selfhost::order_of -/
theorem lok1517 : LiveOk prims outside liveBad 1517 (src_order_of 337 339) := by decide +kernel

/-- mini::selfhost::lx_dot_at -/
theorem lok1528 : LiveOk prims outside liveBad 1528 (src_lx_dot_at 1101 1102 1529 1644) := by decide +kernel

/-- mini::selfhost::place_effs -/
theorem lok1557 : LiveOk prims outside liveBad 1557 (src_place_effs 356 754 1421 1422 1537 1557 1580) := by decide +kernel

/-- mini::selfhost::effs_bytes -/
theorem lok1558 : LiveOk prims outside liveBad 1558 (src_effs_bytes 110 356 754 1422 1558) := by decide +kernel

/-- mini::selfhost::str_bytes -/
theorem lok1559 : LiveOk prims outside liveBad 1559 (src_str_bytes 76 110 1042 1559) := by decide +kernel

/-- mini::selfhost::tree_names -/
theorem lok1763 : LiveOk prims outside liveBad 1763 (src_tree_names 153 156 1795 1796 1797 1798 1799 1800) := by decide +kernel

/-- mini::selfhost::is_text -/
theorem lok1799 : LiveOk prims outside liveBad 1799 (src_is_text 934) := by decide +kernel

/-- mini::selfhost::assignment -/
theorem lok1948 : LiveOk prims outside liveBad 1948 (src_assignment 56 153 156 606 628 1233 1795 1803 1805 1860 2076 2077 2078 2079) := by decide +kernel

/-- mini::selfhost::lit_wants -/
theorem lok2038 : LiveOk prims outside liveBad 2038 (src_lit_wants 2158) := by decide +kernel

/-- mini::selfhost::compound_of -/
theorem lok2078 : LiveOk prims outside liveBad 2078 (src_compound_of 2206) := by decide +kernel

/-- mini::selfhost::zip_variants -/
theorem lok2154 : LiveOk prims outside liveBad 2154 (src_zip_variants 558 1541 2154 2275 2276) := by decide +kernel

/-- mini::selfhost::p_string -/
theorem lok2279 : LiveOk prims outside liveBad 2279 (src_p_string) := by decide +kernel

/-- mini::selfhost::is_u8_slice -/
theorem lok2281 : LiveOk prims outside liveBad 2281 (src_is_u8_slice 984 1671) := by decide +kernel

/-- mini::selfhost::arm_named -/
theorem lok2426 : LiveOk prims outside liveBad 2426 (src_arm_named 934 1750 2514) := by decide +kernel

/-- mini::selfhost::binders_of -/
theorem lok2428 : LiveOk prims outside liveBad 2428 (src_binders_of 103 139 666 2515) := by decide +kernel

/-- mini::selfhost::lit_last_value -/
theorem lok2502 : LiveOk prims outside liveBad 2502 (src_lit_last_value 2539) := by decide +kernel

/-- mini::selfhost::lit_test -/
theorem lok2503 : LiveOk prims outside liveBad 2503 (src_lit_test 153 627 628 1428 1671 1822 2283 2284 2285 2540) := by decide +kernel

/-- mini::selfhost::lit_if_of -/
theorem lok2504 : LiveOk prims outside liveBad 2504 (src_lit_if_of 1888) := by decide +kernel

/-- mini::selfhost::arm_prefix -/
theorem lok2514 : LiveOk prims outside liveBad 2514 (src_arm_prefix 446 647 939 941) := by decide +kernel

/-- mini::selfhost::lit_value_if -/
theorem lok2539 : LiveOk prims outside liveBad 2539 (src_lit_value_if) := by decide +kernel

/-- mini::selfhost::eq_on -/
theorem lok2540 : LiveOk prims outside liveBad 2540 (src_eq_on 1428) := by decide +kernel

/-- mini::selfhost::is_typed_slice_path -/
theorem lok2542 : LiveOk prims outside liveBad 2542 (src_is_typed_slice_path 156 2013 2583 2584) := by decide +kernel

/-- mini::selfhost::any_variant -/
theorem lok2556 : LiveOk prims outside liveBad 2556 (src_any_variant 276 1142 2556) := by decide +kernel

/-- mini::selfhost::cons_binder -/
theorem lok2557 : LiveOk prims outside liveBad 2557 (src_cons_binder 418) := by decide +kernel

/-- mini::selfhost::is_typed_slice_segments -/
theorem lok2583 : LiveOk prims outside liveBad 2583 (src_is_typed_slice_segments 558 934 2384 2604) := by decide +kernel

/-- mini::selfhost::u8_args -/
theorem lok2584 : LiveOk prims outside liveBad 2584 (src_u8_args 103 1757 2586 2605) := by decide +kernel

/-- mini::selfhost::is_empty_trees -/
theorem lok2586 : LiveOk prims outside liveBad 2586 (src_is_empty_trees) := by decide +kernel

/-- mini::selfhost::is_u8_ty -/
theorem lok2605 : LiveOk prims outside liveBad 2605 (src_is_u8_ty 1671) := by decide +kernel

/-- mini::selfhost::arm_names -/
theorem lok2610 : LiveOk prims outside liveBad 2610 (src_arm_names 153 156 429 2425 2426) := by decide +kernel

/-- mini::selfhost::arms_naming_at -/
theorem lok2617 : LiveOk prims outside liveBad 2617 (src_arms_naming_at 148) := by decide +kernel

end Lanius.Faithful.SelfPure
