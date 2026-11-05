module

public import Lanius.Faithful.Gen.SelfPureTab
public import Lanius.Faithful.Gen.SelfLiveTab
public import Lanius.Faithful.Gen.SelfSrcC_SrcType_same
public import Lanius.Faithful.Gen.SelfSrcC_elementBase
public import Lanius.Faithful.Gen.SelfSrcC_indexOf
public import Lanius.Faithful.Gen.SelfSrcC_lowerReturn
public import Lanius.Faithful.Gen.SelfSrcC_storeArray
public import Lanius.Faithful.Gen.SelfSrcC_storeEvalWord
public import Lanius.Faithful.Gen.SelfSrcF_Inline_pExpr
public import Lanius.Faithful.Gen.SelfSrcF_assertClosed
public import Lanius.Faithful.Gen.SelfSrcF_divergeArm
public import Lanius.Faithful.Gen.SelfSrcF_sintAt
public import Lanius.Faithful.Gen.SelfSrcF_tryLocalOf
public import Lanius.Faithful.Gen.SelfSrcF_weightAdd
import all Lanius.Faithful.Gen.SelfLiveTab
import all Lanius.Faithful.Gen.SelfPureTab
import all Lanius.Faithful.Gen.SelfSrcC_SrcType_same
import all Lanius.Faithful.Gen.SelfSrcC_elementBase
import all Lanius.Faithful.Gen.SelfSrcC_indexOf
import all Lanius.Faithful.Gen.SelfSrcC_lowerReturn
import all Lanius.Faithful.Gen.SelfSrcC_storeArray
import all Lanius.Faithful.Gen.SelfSrcC_storeEvalWord
import all Lanius.Faithful.Gen.SelfSrcF_Inline_pExpr
import all Lanius.Faithful.Gen.SelfSrcF_assertClosed
import all Lanius.Faithful.Gen.SelfSrcF_divergeArm
import all Lanius.Faithful.Gen.SelfSrcF_sintAt
import all Lanius.Faithful.Gen.SelfSrcF_tryLocalOf
import all Lanius.Faithful.Gen.SelfSrcF_weightAdd
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

/-- mini::selfhost::size -/
theorem lok120 : LiveOk prims outside liveBad 120 (src_SrcType_size 75 105 120 180 181 182 183 184) := by decide +kernel

/-- mini::selfhost::p_file -/
theorem lok154 : LiveOk prims outside liveBad 154 (src_p_file) := by decide +kernel

/-- mini::selfhost::sizes -/
theorem lok180 : LiveOk prims outside liveBad 180 (src_sizes 75 120 180 181) := by decide +kernel

/-- mini::selfhost::max_size -/
theorem lok182 : LiveOk prims outside liveBad 182 (src_max_size 180 182 183 186) := by decide +kernel

/-- mini::selfhost::lower_return -/
theorem lok209 : LiveOk prims outside liveBad 209 (src_lower_return) := by decide +kernel

/-- mini::selfhost::lower_alloc -/
theorem lok210 : LiveOk prims outside liveBad 210 (src_lower_alloc 188 335) := by decide +kernel

/-- mini::selfhost::lower_set_field_eval -/
theorem lok229 : LiveOk prims outside liveBad 229 (src_lower_set_field_eval 383) := by decide +kernel

/-- mini::selfhost::lower_return_unit -/
theorem lok230 : LiveOk prims outside liveBad 230 (src_lower_return_unit 57 189) := by decide +kernel

/-- mini::selfhost::lower_unreachable -/
theorem lok234 : LiveOk prims outside liveBad 234 (src_lower_unreachable) := by decide +kernel

/-- mini::selfhost::same -/
theorem lok235 : LiveOk prims outside liveBad 235 (src_SrcType_same 57 181 183 184 235 338 339 387 388 389 390 391 392 393 394 395) := by decide +kernel

/-- mini::selfhost::lower_view -/
theorem lok236 : LiveOk prims outside liveBad 236 (src_lower_view 75 105 188 192 396) := by decide +kernel

/-- mini::selfhost::at_least_one -/
theorem lok335 : LiveOk prims outside liveBad 335 (src_at_least_one 337) := by decide +kernel

/-- mini::selfhost::index_guard -/
theorem lok346 : LiveOk prims outside liveBad 346 (src_index_guard 202 348 533) := by decide +kernel

/-- mini::selfhost::lower_index -/
theorem lok348 : LiveOk prims outside liveBad 348 (src_lower_index 315 537) := by decide +kernel

/-- mini::selfhost::store_eval_element -/
theorem lok381 : LiveOk prims outside liveBad 381 (src_store_eval_element 338 339 567 568 569) := by decide +kernel

/-- mini::selfhost::store_array -/
theorem lok382 : LiveOk prims outside liveBad 382 (src_store_array 184 570) := by decide +kernel

/-- mini::selfhost::set_field_eval_of -/
theorem lok383 : LiveOk prims outside liveBad 383 (src_set_field_eval_of 75 181 520 521 571) := by decide +kernel

/-- mini::selfhost::types_same -/
theorem lok388 : LiveOk prims outside liveBad 388 (src_types_same 181 235 388) := by decide +kernel

/-- mini::selfhost::variants_same -/
theorem lok389 : LiveOk prims outside liveBad 389 (src_variants_same 183 388 389) := by decide +kernel

/-- mini::selfhost::view_stores -/
theorem lok396 : LiveOk prims outside liveBad 396 (src_view_stores 56 75 188 337 396) := by decide +kernel

/-- mini::selfhost::str_ascii -/
theorem lok397 : LiveOk prims outside liveBad 397 (src_str_ascii 76 397) := by decide +kernel

/-- mini::selfhost::str_words -/
theorem lok399 : LiveOk prims outside liveBad 399 (src_str_words 75 76 105 399 576 577) := by decide +kernel

/-- mini::selfhost::field_offset -/
theorem lok520 : LiveOk prims outside liveBad 520 (src_field_offset 181 773) := by decide +kernel

/-- mini::selfhost::index_of -/
theorem lok537 : LiveOk prims outside liveBad 537 (src_index_of 338 339) := by decide +kernel

/-- mini::selfhost::store_eval -/
theorem lok567 : LiveOk prims outside liveBad 567 (src_store_eval 75 188 312 337 338 339 533) := by decide +kernel

/-- mini::selfhost::store_eval_byte -/
theorem lok568 : LiveOk prims outside liveBad 568 (src_store_eval_byte 75 188 312 337 338 339 533) := by decide +kernel

/-- mini::selfhost::store_eval_word -/
theorem lok569 : LiveOk prims outside liveBad 569 (src_store_eval_word 75 120 340 353 533 815 816 817) := by decide +kernel

/-- mini::selfhost::store_array_element -/
theorem lok570 : LiveOk prims outside liveBad 570 (src_store_array_element 818) := by decide +kernel

/-- mini::selfhost::set_field_eval_at -/
theorem lok571 : LiveOk prims outside liveBad 571 (src_set_field_eval_at 819) := by decide +kernel

/-- mini::selfhost::p_fn -/
theorem lok620 : LiveOk prims outside liveBad 620 (src_p_fn) := by decide +kernel

/-- mini::selfhost::p_extern_fn -/
theorem lok640 : LiveOk prims outside liveBad 640 (src_p_extern_fn) := by decide +kernel

/-- mini::selfhost::element_base -/
theorem lok817 : LiveOk prims outside liveBad 817 (src_element_base 105 337) := by decide +kernel

/-- mini::selfhost::store_pick -/
theorem lok818 : LiveOk prims outside liveBad 818 (src_store_pick 120 188 235 312 337 338 339 1094) := by decide +kernel

/-- mini::selfhost::p_extern_abi -/
theorem lok933 : LiveOk prims outside liveBad 933 (src_p_extern_abi) := by decide +kernel

/-- mini::selfhost::cons_func -/
theorem lok953 : LiveOk prims outside liveBad 953 (src_cons_func 1149) := by decide +kernel

/-- mini::selfhost::src_func -/
theorem lok954 : LiveOk prims outside liveBad 954 (src_src_func) := by decide +kernel

/-- mini::selfhost::close_params -/
theorem lok955 : LiveOk prims outside liveBad 955 (src_close_params 955 982 1150 1151 1152) := by decide +kernel

/-- mini::selfhost::close_ret -/
theorem lok956 : LiveOk prims outside liveBad 956 (src_close_ret 1152) := by decide +kernel

/-- mini::selfhost::close_stmt -/
theorem lok957 : LiveOk prims outside liveBad 957 (src_close_stmt 957 983 1152 1153 1154 1155 1156 1157 1158 1159 1160 1161 1162 1163 1164 1165 1166 1167 1168 1169 1170 1171 1172 1173 1174 1175 1176 1177 1178 1179 1180 1181 1182 1183) := by decide +kernel

/-- mini::selfhost::load_type -/
theorem lok1070 : LiveOk prims outside liveBad 1070 (src_load_type 181 183 188 1089 1090 1325 1326) := by decide +kernel

/-- mini::selfhost::norm -/
theorem lok1084 : LiveOk prims outside liveBad 1084 (src_norm 337 1332) := by decide +kernel

/-- mini::selfhost::address_below -/
theorem lok1090 : LiveOk prims outside liveBad 1090 (src_address_below 337) := by decide +kernel

/-- mini::selfhost::put_element -/
theorem lok1094 : LiveOk prims outside liveBad 1094 (src_put_element 56 75 105 188 316 337 353 1094) := by decide +kernel

/-- mini::selfhost::cons_func_tail -/
theorem lok1149 : LiveOk prims outside liveBad 1149 (src_cons_func_tail 965) := by decide +kernel

/-- mini::selfhost::cons_src_param -/
theorem lok1151 : LiveOk prims outside liveBad 1151 (src_cons_src_param 1366) := by decide +kernel

/-- mini::selfhost::set_field_eval_closed -/
theorem lok1177 : LiveOk prims outside liveBad 1177 (src_set_field_eval_closed) := by decide +kernel

/-- mini::selfhost::assert_closed -/
theorem lok1178 : LiveOk prims outside liveBad 1178 (src_assert_closed) := by decide +kernel

/-- mini::selfhost::src_fields -/
theorem lok1205 : LiveOk prims outside liveBad 1205 (src_src_fields 181 184 1214) := by decide +kernel

/-- mini::selfhost::payload_at -/
theorem lok1207 : LiveOk prims outside liveBad 1207 (src_payload_at 386) := by decide +kernel

/-- mini::selfhost::src_variants -/
theorem lok1208 : LiveOk prims outside liveBad 1208 (src_src_variants 183) := by decide +kernel

/-- mini::selfhost::ty_local -/
theorem lok1210 : LiveOk prims outside liveBad 1210 (src_ty_local 1445 1446) := by decide +kernel

/-- mini::selfhost::ty_at -/
theorem lok1211 : LiveOk prims outside liveBad 1211 (src_ty_at 521) := by decide +kernel

/-- mini::selfhost::src_element -/
theorem lok1212 : LiveOk prims outside liveBad 1212 (src_src_element 184) := by decide +kernel

/-- mini::selfhost::repeat_src -/
theorem lok1214 : LiveOk prims outside liveBad 1214 (src_repeat_src 56 239 240 1214) := by decide +kernel

/-- mini::selfhost::wrap -/
theorem lok1314 : LiveOk prims outside liveBad 1314 (src_wrap 337 760 1083) := by decide +kernel

/-- mini::selfhost::load_types -/
theorem lok1325 : LiveOk prims outside liveBad 1325 (src_load_types 75 105 120 181 1070 1325) := by decide +kernel

/-- mini::selfhost::load_cases -/
theorem lok1326 : LiveOk prims outside liveBad 1326 (src_load_cases 75 183 188 337 1325 1326) := by decide +kernel

/-- mini::selfhost::p_expr_stmt -/
theorem lok1353 : LiveOk prims outside liveBad 1353 (src_p_expr_stmt) := by decide +kernel

/-- mini::selfhost::array_type -/
theorem lok1369 : LiveOk prims outside liveBad 1369 (src_array_type 217 1536) := by decide +kernel

/-- mini::selfhost::enum_src -/
theorem lok1391 : LiveOk prims outside liveBad 1391 (src_enum_src 1539) := by decide +kernel

/-- mini::selfhost::struct_src -/
theorem lok1394 : LiveOk prims outside liveBad 1394 (src_struct_src 402) := by decide +kernel

/-- mini::selfhost::int_at -/
theorem lok1424 : LiveOk prims outside liveBad 1424 (src_int_at 1560) := by decide +kernel

/-- mini::selfhost::weighed -/
theorem lok1536 : LiveOk prims outside liveBad 1536 (src_weighed 1651) := by decide +kernel

/-- mini::selfhost::weight_array -/
theorem lok1550 : LiveOk prims outside liveBad 1550 (src_weight_array 186 1660) := by decide +kernel

/-- mini::selfhost::int_literal_at -/
theorem lok1560 : LiveOk prims outside liveBad 1560 (src_int_literal_at 1428 1662 1663) := by decide +kernel

/-- mini::selfhost::src_weight -/
theorem lok1651 : LiveOk prims outside liveBad 1651 (src_src_weight 181 183 184 1547 1550 1651 1734 1735) := by decide +kernel

/-- mini::selfhost::weight_add -/
theorem lok1659 : LiveOk prims outside liveBad 1659 (src_weight_add 1547) := by decide +kernel

/-- mini::selfhost::weight_times -/
theorem lok1660 : LiveOk prims outside liveBad 1660 (src_weight_times 105 1551 1661) := by decide +kernel

/-- mini::selfhost::sint_at -/
theorem lok1663 : LiveOk prims outside liveBad 1663 (src_sint_at 1428 1738) := by decide +kernel

/-- mini::selfhost::p_generic_argument_integer -/
theorem lok1681 : LiveOk prims outside liveBad 1681 (src_p_generic_argument_integer) := by decide +kernel

/-- mini::selfhost::src_weights -/
theorem lok1734 : LiveOk prims outside liveBad 1734 (src_src_weights 181 1651 1659 1734) := by decide +kernel

/-- mini::selfhost::variant_weights -/
theorem lok1735 : LiveOk prims outside liveBad 1735 (src_variant_weights 183 1659 1734 1735) := by decide +kernel

/-- mini::selfhost::p_generic_argument_type -/
theorem lok1791 : LiveOk prims outside liveBad 1791 (src_p_generic_argument_type) := by decide +kernel

/-- mini::selfhost::p_ident -/
theorem lok1796 : LiveOk prims outside liveBad 1796 (src_p_ident) := by decide +kernel

/-- mini::selfhost::p_expr -/
theorem lok1803 : LiveOk prims outside liveBad 1803 (src_p_expr) := by decide +kernel

/-- mini::selfhost::p_group -/
theorem lok1816 : LiveOk prims outside liveBad 1816 (src_p_group) := by decide +kernel

/-- mini::selfhost::p_false -/
theorem lok1824 : LiveOk prims outside liveBad 1824 (src_p_false) := by decide +kernel

/-- mini::selfhost::p_float -/
theorem lok1827 : LiveOk prims outside liveBad 1827 (src_p_float) := by decide +kernel

/-- mini::selfhost::p_for_stmt -/
theorem lok1942 : LiveOk prims outside liveBad 1942 (src_p_for_stmt) := by decide +kernel

/-- mini::selfhost::p_gt_tail -/
theorem lok1976 : LiveOk prims outside liveBad 1976 (src_p_gt_tail) := by decide +kernel

/-- mini::selfhost::p_ge_tail -/
theorem lok1978 : LiveOk prims outside liveBad 1978 (src_p_ge_tail) := by decide +kernel

/-- mini::selfhost::try_of_init -/
theorem lok2062 : LiveOk prims outside liveBad 2062 (src_try_of_init 1795 2176) := by decide +kernel

/-- mini::selfhost::try_head -/
theorem lok2174 : LiveOk prims outside liveBad 2174 (src_try_head) := by decide +kernel

/-- mini::selfhost::try_postfix -/
theorem lok2176 : LiveOk prims outside liveBad 2176 (src_try_postfix 2212 2214 2308 2309 2310 2311) := by decide +kernel

/-- mini::selfhost::p_for_iter_range_from_start -/
theorem lok2190 : LiveOk prims outside liveBad 2190 (src_p_for_iter_range_from_start) := by decide +kernel

/-- mini::selfhost::p_for_iter_path -/
theorem lok2196 : LiveOk prims outside liveBad 2196 (src_p_for_iter_path) := by decide +kernel

/-- mini::selfhost::try_local_of -/
theorem lok2311 : LiveOk prims outside liveBad 2311 (src_try_local_of 56 156 628 1233 1595 1820 2436) := by decide +kernel

/-- mini::selfhost::binds_zip -/
theorem lok2401 : LiveOk prims outside liveBad 2401 (src_binds_zip 558 666 2401 2466) := by decide +kernel

/-- mini::selfhost::diverge_arm -/
theorem lok2538 : LiveOk prims outside liveBad 2538 (src_diverge_arm 2579) := by decide +kernel

end Lanius.Faithful.SelfPure
