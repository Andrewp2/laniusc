module

public import Lanius.Faithful.Gen.SelfPureTab
public import Lanius.Faithful.Gen.SelfLiveTab
public import Lanius.Faithful.Gen.SelfSrcC_binaryConstant
public import Lanius.Faithful.Gen.SelfSrcC_funcNeeds
public import Lanius.Faithful.Gen.SelfSrcC_larger
public import Lanius.Faithful.Gen.SelfSrcC_lowerShift
public import Lanius.Faithful.Gen.SelfSrcF_Inline_pStructFieldsMore
public import Lanius.Faithful.Gen.SelfSrcF_armsOf
public import Lanius.Faithful.Gen.SelfSrcF_basedLimit
public import Lanius.Faithful.Gen.SelfSrcF_checkedFunc
public import Lanius.Faithful.Gen.SelfSrcF_frontEndRead
public import Lanius.Faithful.Gen.SelfSrcF_isMatchStmt
public import Lanius.Faithful.Gen.SelfSrcF_letStructClosed
public import Lanius.Faithful.Gen.SelfSrcF_lowerTy
public import Lanius.Faithful.Gen.SelfSrcF_projectionRet
public import Lanius.Faithful.Gen.SelfSrcF_textSliceLen
import all Lanius.Faithful.Gen.SelfLiveTab
import all Lanius.Faithful.Gen.SelfPureTab
import all Lanius.Faithful.Gen.SelfSrcC_binaryConstant
import all Lanius.Faithful.Gen.SelfSrcC_funcNeeds
import all Lanius.Faithful.Gen.SelfSrcC_larger
import all Lanius.Faithful.Gen.SelfSrcC_lowerShift
import all Lanius.Faithful.Gen.SelfSrcF_Inline_pStructFieldsMore
import all Lanius.Faithful.Gen.SelfSrcF_armsOf
import all Lanius.Faithful.Gen.SelfSrcF_basedLimit
import all Lanius.Faithful.Gen.SelfSrcF_checkedFunc
import all Lanius.Faithful.Gen.SelfSrcF_frontEndRead
import all Lanius.Faithful.Gen.SelfSrcF_isMatchStmt
import all Lanius.Faithful.Gen.SelfSrcF_letStructClosed
import all Lanius.Faithful.Gen.SelfSrcF_lowerTy
import all Lanius.Faithful.Gen.SelfSrcF_projectionRet
import all Lanius.Faithful.Gen.SelfSrcF_textSliceLen
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

/-- mini::selfhost::front_end_read -/
theorem lok14 : LiveOk prims outside liveBad 14 (src_front_end_read 42) := by decide +kernel

/-- mini::selfhost::sigs -/
theorem lok62 : LiveOk prims outside liveBad 62 (src_sigs 88 89) := by decide +kernel

/-- mini::selfhost::sigs_with -/
theorem lok88 : LiveOk prims outside liveBad 88 (src_sigs_with 59 88 133 134 135 136 137) := by decide +kernel

/-- mini::selfhost::func_needs -/
theorem lok89 : LiveOk prims outside liveBad 89 (src_func_needs 138 139 140) := by decide +kernel

/-- mini::selfhost::link -/
theorem lok172 : LiveOk prims outside liveBad 172 (src_link 56 290 291 292 293) := by decide +kernel

/-- mini::selfhost::extent -/
theorem lok187 : LiveOk prims outside liveBad 187 (src_Stmt_extent 75 186 187 306 307 308) := by decide +kernel

/-- mini::selfhost::link_fitting -/
theorem lok293 : LiveOk prims outside liveBad 293 (src_link_fitting 486 487) := by decide +kernel

/-- mini::selfhost::extent -/
theorem lok306 : LiveOk prims outside liveBad 306 (src_Expr_extent 75 186 306 492) := by decide +kernel

/-- mini::selfhost::args_extent -/
theorem lok308 : LiveOk prims outside liveBad 308 (src_args_extent 186 306 308 493) := by decide +kernel

/-- mini::selfhost::lookup_at -/
theorem lok328 : LiveOk prims outside liveBad 328 (src_lookup_at 202) := by decide +kernel

/-- mini::selfhost::room_next -/
theorem lok483 : LiveOk prims outside liveBad 483 (src_room_next 56 292) := by decide +kernel

/-- mini::selfhost::p_type_alias -/
theorem lok636 : LiveOk prims outside liveBad 636 (src_p_type_alias) := by decide +kernel

/-- mini::selfhost::p_trait -/
theorem lok644 : LiveOk prims outside liveBad 644 (src_p_trait) := by decide +kernel

/-- mini::selfhost::projection_ret -/
theorem lok683 : LiveOk prims outside liveBad 683 (src_projection_ret 56 998 999 1000) := by decide +kernel

/-- mini::selfhost::is_var -/
theorem lok694 : LiveOk prims outside liveBad 694 (src_Expr_is_var) := by decide +kernel

/-- mini::selfhost::constant -/
theorem lok712 : LiveOk prims outside liveBad 712 (src_Expr_constant 492 712 1022 1023 1024) := by decide +kernel

/-- mini::selfhost::is_zero -/
theorem lok714 : LiveOk prims outside liveBad 714 (src_Expr_is_zero 712 1025) := by decide +kernel

/-- mini::selfhost::expr_then -/
theorem lok729 : LiveOk prims outside liveBad 729 (src_expr_then 1031) := by decide +kernel

/-- mini::selfhost::stmt_then -/
theorem lok730 : LiveOk prims outside liveBad 730 (src_stmt_then 472) := by decide +kernel

/-- mini::selfhost::args_then -/
theorem lok731 : LiveOk prims outside liveBad 731 (src_args_then 1032) := by decide +kernel

/-- mini::selfhost::spend_then -/
theorem lok732 : LiveOk prims outside liveBad 732 (src_spend_then 300) := by decide +kernel

/-- mini::selfhost::seq_code -/
theorem lok744 : LiveOk prims outside liveBad 744 (src_seq_code 75 478 479 480) := by decide +kernel

/-- mini::selfhost::ite_code -/
theorem lok745 : LiveOk prims outside liveBad 745 (src_ite_code 75 478 479 480 743) := by decide +kernel

/-- mini::selfhost::loop_code -/
theorem lok746 : LiveOk prims outside liveBad 746 (src_loop_code 75 478 479 480 743) := by decide +kernel

/-- mini::selfhost::offset_after -/
theorem lok773 : LiveOk prims outside liveBad 773 (src_offset_after 56 75 120 520) := by decide +kernel

/-- mini::selfhost::p_struct_fields_none -/
theorem lok863 : LiveOk prims outside liveBad 863 (src_p_struct_fields_none) := by decide +kernel

/-- mini::selfhost::p_struct_fields_some -/
theorem lok864 : LiveOk prims outside liveBad 864 (src_p_struct_fields_some) := by decide +kernel

/-- mini::selfhost::p_struct_fields_more -/
theorem lok865 : LiveOk prims outside liveBad 865 (src_p_struct_fields_more) := by decide +kernel

/-- mini::selfhost::p_struct_lit_fields_none -/
theorem lok869 : LiveOk prims outside liveBad 869 (src_p_struct_lit_fields_none) := by decide +kernel

/-- mini::selfhost::p_struct_lit_fields_some -/
theorem lok870 : LiveOk prims outside liveBad 870 (src_p_struct_lit_fields_some) := by decide +kernel

/-- mini::selfhost::p_struct_lit_fields_more -/
theorem lok871 : LiveOk prims outside liveBad 871 (src_p_struct_lit_fields_more) := by decide +kernel

/-- mini::selfhost::p_struct_lit_fields_end -/
theorem lok872 : LiveOk prims outside liveBad 872 (src_p_struct_lit_fields_end) := by decide +kernel

/-- mini::selfhost::p_struct_lit_fields_after_comma_more -/
theorem lok873 : LiveOk prims outside liveBad 873 (src_p_struct_lit_fields_after_comma_more) := by decide +kernel

/-- mini::selfhost::p_struct_lit_fields_after_comma_trailing -/
theorem lok874 : LiveOk prims outside liveBad 874 (src_p_struct_lit_fields_after_comma_trailing) := by decide +kernel

/-- mini::selfhost::p_type_args_more -/
theorem lok903 : LiveOk prims outside liveBad 903 (src_p_type_args_more) := by decide +kernel

/-- mini::selfhost::p_type_args_after_comma_more -/
theorem lok904 : LiveOk prims outside liveBad 904 (src_p_type_args_after_comma_more) := by decide +kernel

/-- mini::selfhost::lower_named -/
theorem lok960 : LiveOk prims outside liveBad 960 (src_lower_named 56 1156 1185 1186) := by decide +kernel

/-- mini::selfhost::diverges -/
theorem lok993 : LiveOk prims outside liveBad 993 (src_diverges 75 368 941 1234 1239) := by decide +kernel

/-- mini::selfhost::init_tys -/
theorem lok996 : LiveOk prims outside liveBad 996 (src_init_tys 448 666 669 996) := by decide +kernel

/-- mini::selfhost::binary_constant -/
theorem lok1023 : LiveOk prims outside liveBad 1023 (src_binary_constant 1277 1278) := by decide +kernel

/-- mini::selfhost::compare_constant -/
theorem lok1024 : LiveOk prims outside liveBad 1024 (src_compare_constant 502 1015) := by decide +kernel

/-- mini::selfhost::constant_is -/
theorem lok1025 : LiveOk prims outside liveBad 1025 (src_constant_is) := by decide +kernel

/-- mini::selfhost::lower_shift -/
theorem lok1053 : LiveOk prims outside liveBad 1053 (src_lower_shift 1052 1308) := by decide +kernel

/-- mini::selfhost::let_struct_closed -/
theorem lok1154 : LiveOk prims outside liveBad 1154 (src_let_struct_closed 1202) := by decide +kernel

/-- mini::selfhost::let_call_closed -/
theorem lok1155 : LiveOk prims outside liveBad 1155 (src_let_call_closed 1202) := by decide +kernel

/-- mini::selfhost::let_enum_closed -/
theorem lok1157 : LiveOk prims outside liveBad 1157 (src_let_enum_closed 1202) := by decide +kernel

/-- mini::selfhost::let_match_closed -/
theorem lok1158 : LiveOk prims outside liveBad 1158 (src_let_match_closed 1202) := by decide +kernel

/-- mini::selfhost::set_call_closed -/
theorem lok1160 : LiveOk prims outside liveBad 1160 (src_set_call_closed) := by decide +kernel

/-- mini::selfhost::then_closed -/
theorem lok1161 : LiveOk prims outside liveBad 1161 (src_then_closed 1202) := by decide +kernel

/-- mini::selfhost::if_closed -/
theorem lok1162 : LiveOk prims outside liveBad 1162 (src_if_closed 1202) := by decide +kernel

/-- mini::selfhost::while_closed -/
theorem lok1163 : LiveOk prims outside liveBad 1163 (src_while_closed 1202) := by decide +kernel

/-- mini::selfhost::match_arm_closed -/
theorem lok1179 : LiveOk prims outside liveBad 1179 (src_match_arm_closed 1202) := by decide +kernel

/-- mini::selfhost::arm_ty_closed -/
theorem lok1180 : LiveOk prims outside liveBad 1180 (src_arm_ty_closed) := by decide +kernel

/-- mini::selfhost::unreachable_closed -/
theorem lok1181 : LiveOk prims outside liveBad 1181 (src_unreachable_closed) := by decide +kernel

/-- mini::selfhost::lower_decl -/
theorem lok1186 : LiveOk prims outside liveBad 1186 (src_lower_decl 56 1251 1391 1392 1393 1394 1395) := by decide +kernel

/-- mini::selfhost::never_ret -/
theorem lok1239 : LiveOk prims outside liveBad 1239 (src_never_ret 153 156 1465 1466) := by decide +kernel

/-- mini::selfhost::last_ty -/
theorem lok1240 : LiveOk prims outside liveBad 1240 (src_last_ty 666 1240) := by decide +kernel

/-- mini::selfhost::is_constant -/
theorem lok1271 : LiveOk prims outside liveBad 1271 (src_Expr_is_constant 1025) := by decide +kernel

/-- mini::selfhost::lower_variants -/
theorem lok1392 : LiveOk prims outside liveBad 1392 (src_lower_variants 56 559 1392 1395 1540 1541) := by decide +kernel

/-- mini::selfhost::lower_tys -/
theorem lok1395 : LiveOk prims outside liveBad 1395 (src_lower_tys 56 239 666 1395 1543 1544) := by decide +kernel

/-- mini::selfhost::checked_func -/
theorem lok1476 : LiveOk prims outside liveBad 1476 (src_checked_func) := by decide +kernel

/-- mini::selfhost::unit_of -/
theorem lok1495 : LiveOk prims outside liveBad 1495 (src_Expr_unit_of 712 1256 1257) := by decide +kernel

/-- mini::selfhost::lower_ty -/
theorem lok1544 : LiveOk prims outside liveBad 1544 (src_lower_ty 56 666 960 977 1367 1369 1370 1544) := by decide +kernel

/-- mini::selfhost::and_known -/
theorem lok1700 : LiveOk prims outside liveBad 1700 (src_and_known) := by decide +kernel

/-- mini::selfhost::p_true -/
theorem lok1823 : LiveOk prims outside liveBad 1823 (src_p_true) := by decide +kernel

/-- mini::selfhost::p_struct_lit -/
theorem lok1903 : LiveOk prims outside liveBad 1903 (src_p_struct_lit) := by decide +kernel

/-- mini::selfhost::is_match_stmt -/
theorem lok1946 : LiveOk prims outside liveBad 1946 (src_is_match_stmt 1945) := by decide +kernel

/-- mini::selfhost::p_sub_tail -/
theorem lok1982 : LiveOk prims outside liveBad 1982 (src_p_sub_tail) := by decide +kernel

/-- mini::selfhost::text_slice_len -/
theorem lok2011 : LiveOk prims outside liveBad 2011 (src_text_slice_len 376 418) := by decide +kernel

/-- mini::selfhost::or_known -/
theorem lok2421 : LiveOk prims outside liveBad 2421 (src_or_known) := by decide +kernel

/-- mini::selfhost::arm_nested -/
theorem lok2422 : LiveOk prims outside liveBad 2422 (src_arm_nested 153 155 156 2425 2427 2509) := by decide +kernel

/-- mini::selfhost::based_limit -/
theorem lok2475 : LiveOk prims outside liveBad 2475 (src_based_limit) := by decide +kernel

/-- mini::selfhost::pats_nested -/
theorem lok2509 : LiveOk prims outside liveBad 2509 (src_pats_nested 2544) := by decide +kernel

/-- mini::selfhost::all_binders -/
theorem lok2544 : LiveOk prims outside liveBad 2544 (src_all_binders 103 2544 2589) := by decide +kernel

/-- mini::selfhost::not_known -/
theorem lok2576 : LiveOk prims outside liveBad 2576 (src_not_known) := by decide +kernel

/-- mini::selfhost::is_binder_pat -/
theorem lok2589 : LiveOk prims outside liveBad 2589 (src_is_binder_pat 153 156 1800 2425 2427 2609) := by decide +kernel

/-- mini::selfhost::binder_name_ok -/
theorem lok2609 : LiveOk prims outside liveBad 2609 (src_binder_name_ok 163 1142 2556) := by decide +kernel

end Lanius.Faithful.SelfPure
