module

public import Lanius.Faithful.Gen.SelfPureTab
public import Lanius.Faithful.Gen.SelfLiveTab
public import Lanius.Faithful.Gen.SelfSrcC_compileOr
public import Lanius.Faithful.Gen.SelfSrcC_guardAnd
public import Lanius.Faithful.Gen.SelfSrcC_hostRandomCode
public import Lanius.Faithful.Gen.SelfSrcC_iteThen
public import Lanius.Faithful.Gen.SelfSrcC_linkedSize
public import Lanius.Faithful.Gen.SelfSrcC_sintToUint
public import Lanius.Faithful.Gen.SelfSrcC_structFields
public import Lanius.Faithful.Gen.SelfSrcF_Inline_positionAt
public import Lanius.Faithful.Gen.SelfSrcF_letClosed
public import Lanius.Faithful.Gen.SelfSrcF_selfRefOf
public import Lanius.Faithful.Gen.SelfSrcF_wideOf
import all Lanius.Faithful.Gen.SelfLiveTab
import all Lanius.Faithful.Gen.SelfPureTab
import all Lanius.Faithful.Gen.SelfSrcC_compileOr
import all Lanius.Faithful.Gen.SelfSrcC_guardAnd
import all Lanius.Faithful.Gen.SelfSrcC_hostRandomCode
import all Lanius.Faithful.Gen.SelfSrcC_iteThen
import all Lanius.Faithful.Gen.SelfSrcC_linkedSize
import all Lanius.Faithful.Gen.SelfSrcC_sintToUint
import all Lanius.Faithful.Gen.SelfSrcC_structFields
import all Lanius.Faithful.Gen.SelfSrcF_Inline_positionAt
import all Lanius.Faithful.Gen.SelfSrcF_letClosed
import all Lanius.Faithful.Gen.SelfSrcF_selfRefOf
import all Lanius.Faithful.Gen.SelfSrcF_wideOf
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

/-- mini::selfhost::compile_declared -/
theorem lok38 : LiveOk prims outside liveBad 38 (src_compile_declared 60 61 62) := by decide +kernel

/-- mini::selfhost::compile_lowered -/
theorem lok60 : LiveOk prims outside liveBad 60 (src_compile_lowered 83) := by decide +kernel

/-- mini::selfhost::compile_optimized -/
theorem lok83 : LiveOk prims outside liveBad 83 (src_compile_optimized 113 114 115 116) := by decide +kernel

/-- mini::selfhost::compile_or -/
theorem lok115 : LiveOk prims outside liveBad 115 (src_compile_or 116) := by decide +kernel

/-- mini::selfhost::compile_program -/
theorem lok116 : LiveOk prims outside liveBad 116 (src_compile_program 170 171 172) := by decide +kernel

/-- mini::selfhost::collect_file_next -/
theorem lok164 : LiveOk prims outside liveBad 164 (src_collect_file_next 102 277) := by decide +kernel

/-- mini::selfhost::guard_and -/
theorem lok211 : LiveOk prims outside liveBad 211 (src_guard_and 336 337) := by decide +kernel

/-- mini::selfhost::module_at -/
theorem lok266 : LiveOk prims outside liveBad 266 (src_module_at 153 156 158 428 429) := by decide +kernel

/-- mini::selfhost::root_at -/
theorem lok273 : LiveOk prims outside liveBad 273 (src_root_at 75 160 446 447 448) := by decide +kernel

/-- mini::selfhost::seed_at -/
theorem lok275 : LiveOk prims outside liveBad 275 (src_seed_at 75 162 446 447 448) := by decide +kernel

/-- mini::selfhost::room_after -/
theorem lok292 : LiveOk prims outside liveBad 292 (src_room_after 483 484 485) := by decide +kernel

/-- mini::selfhost::struct_fields -/
theorem lok407 : LiveOk prims outside liveBad 407 (src_struct_fields 584 585) := by decide +kernel

/-- mini::selfhost::shift_guard -/
theorem lok498 : LiveOk prims outside liveBad 498 (src_shift_guard 758 759) := by decide +kernel

/-- mini::selfhost::guard_or -/
theorem lok499 : LiveOk prims outside liveBad 499 (src_guard_or 336 337) := by decide +kernel

/-- mini::selfhost::left_false -/
theorem lok500 : LiveOk prims outside liveBad 500 (src_left_false 337) := by decide +kernel

/-- mini::selfhost::lower_cast -/
theorem lok509 : LiveOk prims outside liveBad 509 (src_lower_cast 764) := by decide +kernel

/-- mini::selfhost::lower_float -/
theorem lok510 : LiveOk prims outside liveBad 510 (src_lower_float 765) := by decide +kernel

/-- mini::selfhost::amount_guard -/
theorem lok758 : LiveOk prims outside liveBad 758 (src_amount_guard 337 1048) := by decide +kernel

/-- mini::selfhost::shift_width -/
theorem lok759 : LiveOk prims outside liveBad 759 (src_shift_width 1049) := by decide +kernel

/-- mini::selfhost::cast_to -/
theorem lok764 : LiveOk prims outside liveBad 764 (src_cast_to 1059 1060 1061 1062 1063) := by decide +kernel

/-- mini::selfhost::host_random_code -/
theorem lok794 : LiveOk prims outside liveBad 794 (src_host_random_code 75 188 189 337 542) := by decide +kernel

/-- mini::selfhost::eval_host_text -/
theorem lok795 : LiveOk prims outside liveBad 795 (src_eval_host_text 188 240 377 388 1079 1080) := by decide +kernel

/-- mini::selfhost::struct_field_tys -/
theorem lok999 : LiveOk prims outside liveBad 999 (src_struct_field_tys 666 1251) := by decide +kernel

/-- mini::selfhost::literal_below -/
theorem lok1048 : LiveOk prims outside liveBad 1048 (src_literal_below) := by decide +kernel

/-- mini::selfhost::bits -/
theorem lok1049 : LiveOk prims outside liveBad 1049 (src_UintTy_bits) := by decide +kernel

/-- mini::selfhost::cast_to_i32 -/
theorem lok1059 : LiveOk prims outside liveBad 1059 (src_cast_to_i32 1314 1315) := by decide +kernel

/-- mini::selfhost::cast_to_uint -/
theorem lok1060 : LiveOk prims outside liveBad 1060 (src_cast_to_uint 1314 1316 1317) := by decide +kernel

/-- mini::selfhost::cast_to_isize -/
theorem lok1061 : LiveOk prims outside liveBad 1061 (src_cast_to_isize 1316 1318) := by decide +kernel

/-- mini::selfhost::cast_to_float -/
theorem lok1062 : LiveOk prims outside liveBad 1062 (src_cast_to_float 1319 1320 1321 1322) := by decide +kernel

/-- mini::selfhost::cast_to_sint -/
theorem lok1063 : LiveOk prims outside liveBad 1063 (src_cast_to_sint 317 387 390 800 1061 1083 1084) := by decide +kernel

/-- mini::selfhost::host_text_code -/
theorem lok1079 : LiveOk prims outside liveBad 1079 (src_host_text_code 75 188 337 790) := by decide +kernel

/-- mini::selfhost::host_newline_code -/
theorem lok1080 : LiveOk prims outside liveBad 1080 (src_host_newline_code 75 188 789) := by decide +kernel

/-- mini::selfhost::store_one -/
theorem lok1088 : LiveOk prims outside liveBad 1088 (src_store_one) := by decide +kernel

/-- mini::selfhost::param_spelling_at -/
theorem lok1126 : LiveOk prims outside liveBad 1126 (src_param_spelling_at 153 627 628 649 925 1360) := by decide +kernel

/-- mini::selfhost::fn_name_at -/
theorem lok1143 : LiveOk prims outside liveBad 1143 (src_fn_name_at 939 942 1141) := by decide +kernel

/-- mini::selfhost::type_only_at -/
theorem lok1144 : LiveOk prims outside liveBad 1144 (src_type_only_at 939 943 1141) := by decide +kernel

/-- mini::selfhost::alias_name_at -/
theorem lok1145 : LiveOk prims outside liveBad 1145 (src_alias_name_at 939 944 1141) := by decide +kernel

/-- mini::selfhost::const_name_at -/
theorem lok1146 : LiveOk prims outside liveBad 1146 (src_const_name_at 939 945 1141) := by decide +kernel

/-- mini::selfhost::let_closed -/
theorem lok1153 : LiveOk prims outside liveBad 1153 (src_let_closed 1202) := by decide +kernel

/-- mini::selfhost::sint_to_uint -/
theorem lok1317 : LiveOk prims outside liveBad 1317 (src_sint_to_uint 1083 1314 1316) := by decide +kernel

/-- mini::selfhost::sint_to_wide -/
theorem lok1318 : LiveOk prims outside liveBad 1318 (src_sint_to_wide 1083 1316) := by decide +kernel

/-- mini::selfhost::int_to_float -/
theorem lok1319 : LiveOk prims outside liveBad 1319 (src_int_to_float 337) := by decide +kernel

/-- mini::selfhost::if_narrow -/
theorem lok1320 : LiveOk prims outside liveBad 1320 (src_if_narrow 1083) := by decide +kernel

/-- mini::selfhost::float_to_float -/
theorem lok1321 : LiveOk prims outside liveBad 1321 (src_float_to_float 337) := by decide +kernel

/-- mini::selfhost::ite_then -/
theorem lok1335 : LiveOk prims outside liveBad 1335 (src_ite_then 188) := by decide +kernel

/-- mini::selfhost::inst_index_at -/
theorem lok1371 : LiveOk prims outside liveBad 1371 (src_inst_index_at 75 1156 1456) := by decide +kernel

/-- mini::selfhost::wide_value -/
theorem lok1425 : LiveOk prims outside liveBad 1425 (src_wide_value 313 1561) := by decide +kernel

/-- mini::selfhost::self_ref_of -/
theorem lok1481 : LiveOk prims outside liveBad 1481 (src_self_ref_of 56 153 628 1233 1594) := by decide +kernel

/-- mini::selfhost::wide_inner -/
theorem lok1561 : LiveOk prims outside liveBad 1561 (src_wide_inner 1545) := by decide +kernel

/-- mini::selfhost::gives_bool -/
theorem lok1567 : LiveOk prims outside liveBad 1567 (src_gives_bool) := by decide +kernel

/-- mini::selfhost::shift_op -/
theorem lok1569 : LiveOk prims outside liveBad 1569 (src_shift_op) := by decide +kernel

/-- mini::selfhost::type_name_at -/
theorem lok1590 : LiveOk prims outside liveBad 1590 (src_type_name_at 939 941 1141 1461) := by decide +kernel

/-- mini::selfhost::expr_of -/
theorem lok1766 : LiveOk prims outside liveBad 1766 (src_expr_of 56 153 156 627 628 1764 1766 1796 1803 1804 1805 1806 1807 1808 1809 1810 1811 1812 1813 1814 1815 1816 1817 1818 1819 1820 1821 1822 1823 1824 1825 1826 1827 1828) := by decide +kernel

/-- mini::selfhost::find_alias_at -/
theorem lok1788 : LiveOk prims outside liveBad 1788 (src_find_alias_at 934 939 1751) := by decide +kernel

/-- mini::selfhost::find_type_at -/
theorem lok1790 : LiveOk prims outside liveBad 1790 (src_find_type_at 75 934 939 1754) := by decide +kernel

/-- mini::selfhost::peel -/
theorem lok1795 : LiveOk prims outside liveBad 1795 (src_peel 56 153 156 606 1764 1795 1803 1804 1805 1807 1809) := by decide +kernel

/-- mini::selfhost::assign_value -/
theorem lok1806 : LiveOk prims outside liveBad 1806 (src_assign_value 56 153 156 1766 1860) := by decide +kernel

/-- mini::selfhost::fold -/
theorem lok1808 : LiveOk prims outside liveBad 1808 (src_fold 56 153 606 1871 1872) := by decide +kernel

/-- mini::selfhost::postfix_value -/
theorem lok1815 : LiveOk prims outside liveBad 1815 (src_postfix_value 56 153 1766 1798 1801 1875) := by decide +kernel

/-- mini::selfhost::ident_expr -/
theorem lok1817 : LiveOk prims outside liveBad 1817 (src_ident_expr 56 153 156 429 1797 1820 1876) := by decide +kernel

/-- mini::selfhost::position_at -/
theorem lok1850 : LiveOk prims outside liveBad 1850 (src_position_at 75 934 1785) := by decide +kernel

/-- mini::selfhost::fold_op -/
theorem lok1871 : LiveOk prims outside liveBad 1871 (src_fold_op 56 1967) := by decide +kernel

/-- mini::selfhost::const_ref -/
theorem lok1876 : LiveOk prims outside liveBad 1876 (src_const_ref 56 454 1750 1752 1900 1992) := by decide +kernel

/-- mini::selfhost::fold_left -/
theorem lok1967 : LiveOk prims outside liveBad 1967 (src_fold_left 56 156 1766 1808 2094) := by decide +kernel

/-- mini::selfhost::const_value -/
theorem lok1992 : LiveOk prims outside liveBad 1992 (src_const_value 56 265 448 1237 1468 1484 1766 2098 2099 2100 2101) := by decide +kernel

/-- mini::selfhost::find_const_at -/
theorem lok2021 : LiveOk prims outside liveBad 2021 (src_find_const_at 934 939 1900) := by decide +kernel

/-- mini::selfhost::wide_read_of -/
theorem lok2098 : LiveOk prims outside liveBad 2098 (src_wide_read_of 2217) := by decide +kernel

/-- mini::selfhost::wide_const -/
theorem lok2099 : LiveOk prims outside liveBad 2099 (src_wide_const 167 934 1879 2218 2219 2220) := by decide +kernel

/-- mini::selfhost::apply_ty -/
theorem lok2145 : LiveOk prims outside liveBad 2145 (src_apply_ty 1567) := by decide +kernel

/-- mini::selfhost::wide_read -/
theorem lok2217 : LiveOk prims outside liveBad 2217 (src_wide_read 313 1425 1561 2349) := by decide +kernel

/-- mini::selfhost::wide_digits -/
theorem lok2218 : LiveOk prims outside liveBad 2218 (src_wide_digits 2350) := by decide +kernel

/-- mini::selfhost::wide_signed -/
theorem lok2219 : LiveOk prims outside liveBad 2219 (src_wide_signed 2218) := by decide +kernel

/-- mini::selfhost::dash_text -/
theorem lok2220 : LiveOk prims outside liveBad 2220 (src_dash_text 376) := by decide +kernel

/-- mini::selfhost::local_ty -/
theorem lok2263 : LiveOk prims outside liveBad 2263 (src_local_ty) := by decide +kernel

/-- mini::selfhost::field_ty -/
theorem lok2264 : LiveOk prims outside liveBad 2264 (src_field_ty 999 1000) := by decide +kernel

/-- mini::selfhost::bare_int -/
theorem lok2265 : LiveOk prims outside liveBad 2265 (src_bare_int 313 1545 1567 1569 2265) := by decide +kernel

/-- mini::selfhost::has_wide -/
theorem lok2349 : LiveOk prims outside liveBad 2349 (src_has_wide) := by decide +kernel

/-- mini::selfhost::wide_of -/
theorem lok2350 : LiveOk prims outside liveBad 2350 (src_wide_of 2470 2471 2472 2473) := by decide +kernel

/-- mini::selfhost::find_fn_at -/
theorem lok2389 : LiveOk prims outside liveBad 2389 (src_find_fn_at 75 934 939 2245) := by decide +kernel

end Lanius.Faithful.SelfPure
