module

public import Lanius.Faithful.Gen.SelfPureTab
public import Lanius.Faithful.Gen.SelfLiveTab
public import Lanius.Faithful.Gen.SelfSrc5
public import Lanius.Faithful.Gen.SelfSrcC_widthOf
public import Lanius.Faithful.Gen.SelfSrcF_Inline_pRangeStartInt
public import Lanius.Faithful.Gen.SelfSrcF_Inline_pTypeArgsNone
public import Lanius.Faithful.Gen.SelfSrcF_findConst
public import Lanius.Faithful.Gen.SelfSrcF_firstSrc
public import Lanius.Faithful.Gen.SelfSrcF_isEmptyUsize
public import Lanius.Faithful.Gen.SelfSrcF_lxBlockEnd
public import Lanius.Faithful.Gen.SelfSrcF_namesSome
public import Lanius.Faithful.Gen.SelfSrcF_typeDeclAt
import all Lanius.Faithful.Gen.SelfLiveTab
import all Lanius.Faithful.Gen.SelfPureTab
import all Lanius.Faithful.Gen.SelfSrc5
import all Lanius.Faithful.Gen.SelfSrcC_widthOf
import all Lanius.Faithful.Gen.SelfSrcF_Inline_pRangeStartInt
import all Lanius.Faithful.Gen.SelfSrcF_Inline_pTypeArgsNone
import all Lanius.Faithful.Gen.SelfSrcF_findConst
import all Lanius.Faithful.Gen.SelfSrcF_firstSrc
import all Lanius.Faithful.Gen.SelfSrcF_isEmptyUsize
import all Lanius.Faithful.Gen.SelfSrcF_lxBlockEnd
import all Lanius.Faithful.Gen.SelfSrcF_namesSome
import all Lanius.Faithful.Gen.SelfSrcF_typeDeclAt
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

/-- mini::selfhost::empty<i32> -/
theorem lok5 : LiveOk prims outside liveBad 5 (src_empty_of_i32) := by decide +kernel

/-- mini::selfhost::empty<mini::selfhost::Rule> -/
theorem lok48 : LiveOk prims outside liveBad 48 (src_empty_of_mini_selfhost_Rule) := by decide +kernel

/-- mini::selfhost::validate_tree -/
theorem lok98 : LiveOk prims outside liveBad 98 (src_validate_tree 52 75 105 106 149 150 151) := by decide +kernel

/-- mini::selfhost::length<mini::selfhost::SrcFunc> -/
theorem lok140 : LiveOk prims outside liveBad 140 (src_length_of_mini_selfhost_SrcFunc 59 75 140) := by decide +kernel

/-- mini::selfhost::whole -/
theorem lok151 : LiveOk prims outside liveBad 151 (src_whole 103 257 258) := by decide +kernel

/-- mini::selfhost::node_prod -/
theorem lok153 : LiveOk prims outside liveBad 153 (src_node_prod) := by decide +kernel

/-- mini::selfhost::boxed<mini::selfhost::List<mini::selfhost::List<mini::selfhost::List<usize>>>> -/
theorem lok166 : LiveOk prims outside liveBad 166 (src_boxed_of_mini_selfhost_List_mini_selfhost_List_mini_selfhost_List_usize 50 278 279) := by decide +kernel

/-- mini::selfhost::boxed<mini::selfhost::Stmt> -/
theorem lok188 : LiveOk prims outside liveBad 188 (src_boxed_of_mini_selfhost_Stmt 50 309 310) := by decide +kernel

/-- mini::selfhost::empty<mini::selfhost::SrcType> -/
theorem lok239 : LiveOk prims outside liveBad 239 (src_empty_of_mini_selfhost_SrcType) := by decide +kernel

/-- mini::selfhost::cons<mini::selfhost::SrcType> -/
theorem lok240 : LiveOk prims outside liveBad 240 (src_cons_of_mini_selfhost_SrcType 402) := by decide +kernel

/-- mini::selfhost::used_up -/
theorem lok257 : LiveOk prims outside liveBad 257 (src_used_up 422 423) := by decide +kernel

/-- mini::selfhost::empty<mini::selfhost::MFunc> -/
theorem lok271 : LiveOk prims outside liveBad 271 (src_empty_of_mini_selfhost_MFunc) := by decide +kernel

/-- mini::selfhost::unbox<mini::selfhost::Stmt> -/
theorem lok307 : LiveOk prims outside liveBad 307 (src_unbox_of_mini_selfhost_Stmt 310) := by decide +kernel

/-- mini::selfhost::unbox<mini::selfhost::List<mini::selfhost::Binding>> -/
theorem lok329 : LiveOk prims outside liveBad 329 (src_unbox_of_mini_selfhost_List_mini_selfhost_Binding 514) := by decide +kernel

/-- mini::selfhost::unbox<mini::selfhost::List<mini::selfhost::SrcEff>> -/
theorem lok356 : LiveOk prims outside liveBad 356 (src_unbox_of_mini_selfhost_List_mini_selfhost_SrcEff 547) := by decide +kernel

/-- mini::selfhost::single<usize> -/
theorem lok376 : LiveOk prims outside liveBad 376 (src_single_of_usize 488) := by decide +kernel

/-- mini::selfhost::get<mini::selfhost::List<mini::selfhost::SrcType>> -/
theorem lok386 : LiveOk prims outside liveBad 386 (src_get_of_mini_selfhost_List_mini_selfhost_SrcType 56 183 386) := by decide +kernel

/-- mini::selfhost::boxed<mini::selfhost::List<mini::selfhost::SrcType>> -/
theorem lok402 : LiveOk prims outside liveBad 402 (src_boxed_of_mini_selfhost_List_mini_selfhost_SrcType 50 303 578) := by decide +kernel

/-- mini::selfhost::is_empty_usize -/
theorem lok422 : LiveOk prims outside liveBad 422 (src_is_empty_usize) := by decide +kernel

/-- mini::selfhost::no_tokens -/
theorem lok423 : LiveOk prims outside liveBad 423 (src_no_tokens) := by decide +kernel

/-- mini::selfhost::empty<mini::selfhost::Ty> -/
theorem lok448 : LiveOk prims outside liveBad 448 (src_empty_of_mini_selfhost_Ty) := by decide +kernel

/-- mini::selfhost::concat<mini::selfhost::TypeDecl> -/
theorem lok451 : LiveOk prims outside liveBad 451 (src_concat_of_mini_selfhost_TypeDecl 276 451 685) := by decide +kernel

/-- ?<mini::selfhost::Decls> -/
theorem lok454 : LiveOk prims outside liveBad 454 (src_field_consts_Decls_of_mini_selfhost_Decls) := by decide +kernel

/-- ?<mini::selfhost::Decls> -/
theorem lok456 : LiveOk prims outside liveBad 456 (src_field_imports_Decls_of_mini_selfhost_Decls) := by decide +kernel

/-- mini::selfhost::unbox<mini::selfhost::List<mini::selfhost::Code>> -/
theorem lok485 : LiveOk prims outside liveBad 485 (src_unbox_of_mini_selfhost_List_mini_selfhost_Code 751) := by decide +kernel

/-- mini::selfhost::get<mini::selfhost::SrcType> -/
theorem lok521 : LiveOk prims outside liveBad 521 (src_get_of_mini_selfhost_SrcType 56 181 521) := by decide +kernel

/-- mini::selfhost::empty<mini::selfhost::List<mini::selfhost::SrcType>> -/
theorem lok559 : LiveOk prims outside liveBad 559 (src_empty_of_mini_selfhost_List_mini_selfhost_SrcType) := by decide +kernel

/-- mini::selfhost::single<mini::selfhost::CTree> -/
theorem lok607 : LiveOk prims outside liveBad 607 (src_single_of_mini_selfhost_CTree 254) := by decide +kernel

/-- mini::selfhost::empty<mini::selfhost::TypeDecl> -/
theorem lok608 : LiveOk prims outside liveBad 608 (src_empty_of_mini_selfhost_TypeDecl) := by decide +kernel

/-- mini::selfhost::single<mini::selfhost::ConstDecl> -/
theorem lok626 : LiveOk prims outside liveBad 626 (src_single_of_mini_selfhost_ConstDecl 687) := by decide +kernel

/-- mini::selfhost::unbox<mini::selfhost::List<mini::selfhost::AliasDecl>> -/
theorem lok655 : LiveOk prims outside liveBad 655 (src_unbox_of_mini_selfhost_List_mini_selfhost_AliasDecl 951) := by decide +kernel

/-- mini::selfhost::add_insts -/
theorem lok677 : LiveOk prims outside liveBad 677 (src_add_insts 671 677 987) := by decide +kernel

/-- mini::selfhost::boxed<mini::selfhost::List<mini::selfhost::FnDecl>> -/
theorem lok686 : LiveOk prims outside liveBad 686 (src_boxed_of_mini_selfhost_List_mini_selfhost_FnDecl 50 449 1003) := by decide +kernel

/-- mini::selfhost::get<u8> -/
theorem lok814 : LiveOk prims outside liveBad 814 (src_get_of_u8 56 78 814) := by decide +kernel

/-- mini::selfhost::p_type_args_some -/
theorem lok902 : LiveOk prims outside liveBad 902 (src_p_type_args_some) := by decide +kernel

/-- mini::selfhost::single<mini::selfhost::ImportDecl> -/
theorem lok929 : LiveOk prims outside liveBad 929 (src_single_of_mini_selfhost_ImportDecl 689) := by decide +kernel

/-- mini::selfhost::unbox<mini::selfhost::List<core::option::Option<usize>>> -/
theorem lok969 : LiveOk prims outside liveBad 969 (src_unbox_of_mini_selfhost_List_core_option_Option_usize 1217) := by decide +kernel

/-- mini::selfhost::add_inst -/
theorem lok987 : LiveOk prims outside liveBad 987 (src_add_inst 988 989 1221) := by decide +kernel

/-- mini::selfhost::boxed<mini::selfhost::List<mini::selfhost::MFunc>> -/
theorem lok991 : LiveOk prims outside liveBad 991 (src_boxed_of_mini_selfhost_List_mini_selfhost_MFunc 50 986 1231) := by decide +kernel

/-- mini::selfhost::width_of -/
theorem lok1089 : LiveOk prims outside liveBad 1089 (src_width_of 1334) := by decide +kernel

/-- mini::selfhost::inst_index -/
theorem lok1156 : LiveOk prims outside liveBad 1156 (src_inst_index 671 1371) := by decide +kernel

/-- mini::selfhost::inst_member -/
theorem lok1221 : LiveOk prims outside liveBad 1221 (src_inst_member 671 1221 1456) := by decide +kernel

/-- mini::selfhost::unbox<mini::selfhost::MEff> -/
theorem lok1229 : LiveOk prims outside liveBad 1229 (src_unbox_of_mini_selfhost_MEff 1460) := by decide +kernel

/-- mini::selfhost::empty<mini::selfhost::Local> -/
theorem lok1237 : LiveOk prims outside liveBad 1237 (src_empty_of_mini_selfhost_Local) := by decide +kernel

/-- mini::selfhost::boxed<mini::selfhost::MStmt> -/
theorem lok1241 : LiveOk prims outside liveBad 1241 (src_boxed_of_mini_selfhost_MStmt 50 1225 1469) := by decide +kernel

/-- mini::selfhost::lx_digit_run -/
theorem lok1338 : LiveOk prims outside liveBad 1338 (src_lx_digit_run 76 593 1525) := by decide +kernel

/-- mini::selfhost::operand_want -/
theorem lok1429 : LiveOk prims outside liveBad 1429 (src_operand_want 1567 1568 1569) := by decide +kernel

/-- mini::selfhost::amount_want -/
theorem lok1431 : LiveOk prims outside liveBad 1431 (src_amount_want 1429 1568 1569) := by decide +kernel

/-- mini::selfhost::wide_at -/
theorem lok1432 : LiveOk prims outside liveBad 1432 (src_wide_at 1572 1573 1574) := by decide +kernel

/-- mini::selfhost::first_src -/
theorem lok1437 : LiveOk prims outside liveBad 1437 (src_first_src 1211) := by decide +kernel

/-- mini::selfhost::rest_src -/
theorem lok1438 : LiveOk prims outside liveBad 1438 (src_rest_src 181) := by decide +kernel

/-- mini::selfhost::bound_tys -/
theorem lok1443 : LiveOk prims outside liveBad 1443 (src_bound_tys 76 1216 1437 1438 1443) := by decide +kernel

/-- mini::selfhost::rest_payloads -/
theorem lok1444 : LiveOk prims outside liveBad 1444 (src_rest_payloads 183) := by decide +kernel

/-- mini::selfhost::same_inst -/
theorem lok1456 : LiveOk prims outside liveBad 1456 (src_same_inst 1587) := by decide +kernel

/-- mini::selfhost::p_ret_type -/
theorem lok1465 : LiveOk prims outside liveBad 1465 (src_p_ret_type) := by decide +kernel

/-- mini::selfhost::p_type_never -/
theorem lok1466 : LiveOk prims outside liveBad 1466 (src_p_type_never) := by decide +kernel

/-- mini::selfhost::ty_of -/
theorem lok1468 : LiveOk prims outside liveBad 1468 (src_ty_of 56 153 155 156 902 1468 1600 1601 1602 1603 1604 1605 1606 1607 1608 1609 1610) := by decide +kernel

/-- mini::selfhost::ty_list -/
theorem lok1483 : LiveOk prims outside liveBad 1483 (src_ty_list 56 103 448 1468 1483 1621) := by decide +kernel

/-- mini::selfhost::decl_env -/
theorem lok1484 : LiveOk prims outside liveBad 1484 (src_decl_env 265) := by decide +kernel

/-- mini::selfhost::empty<mini::selfhost::SrcEff> -/
theorem lok1537 : LiveOk prims outside liveBad 1537 (src_empty_of_mini_selfhost_SrcEff) := by decide +kernel

/-- mini::selfhost::boxed<mini::selfhost::List<mini::selfhost::List<mini::selfhost::SrcType>>> -/
theorem lok1539 : LiveOk prims outside liveBad 1539 (src_boxed_of_mini_selfhost_List_mini_selfhost_List_mini_selfhost_SrcType 50 304 1652) := by decide +kernel

/-- mini::selfhost::either_ty -/
theorem lok1568 : LiveOk prims outside liveBad 1568 (src_either_ty) := by decide +kernel

/-- mini::selfhost::known_apply -/
theorem lok1570 : LiveOk prims outside liveBad 1570 (src_known_apply 1567 1568 1569) := by decide +kernel

/-- mini::selfhost::known_cast -/
theorem lok1571 : LiveOk prims outside liveBad 1571 (src_known_cast 1545) := by decide +kernel

/-- mini::selfhost::wide_uint_at -/
theorem lok1572 : LiveOk prims outside liveBad 1572 (src_wide_uint_at 1666) := by decide +kernel

/-- mini::selfhost::wide_isize_at -/
theorem lok1573 : LiveOk prims outside liveBad 1573 (src_wide_isize_at 1428) := by decide +kernel

/-- mini::selfhost::wide_sint_at -/
theorem lok1574 : LiveOk prims outside liveBad 1574 (src_wide_sint_at 1428 1664) := by decide +kernel

/-- mini::selfhost::cons<mini::selfhost::SrcEff> -/
theorem lok1580 : LiveOk prims outside liveBad 1580 (src_cons_of_mini_selfhost_SrcEff 1447) := by decide +kernel

/-- mini::selfhost::first_ids -/
theorem lok1583 : LiveOk prims outside liveBad 1583 (src_first_ids 139) := by decide +kernel

/-- mini::selfhost::rest_ids -/
theorem lok1584 : LiveOk prims outside liveBad 1584 (src_rest_ids 265 558) := by decide +kernel

/-- mini::selfhost::same_tys -/
theorem lok1587 : LiveOk prims outside liveBad 1587 (src_same_tys 666 1587 1671) := by decide +kernel

/-- mini::selfhost::p_type_array -/
theorem lok1600 : LiveOk prims outside liveBad 1600 (src_p_type_array) := by decide +kernel

/-- mini::selfhost::slice_ty -/
theorem lok1602 : LiveOk prims outside liveBad 1602 (src_slice_ty 984) := by decide +kernel

/-- mini::selfhost::p_type_array_tail -/
theorem lok1603 : LiveOk prims outside liveBad 1603 (src_p_type_array_tail) := by decide +kernel

/-- mini::selfhost::array_ty -/
theorem lok1604 : LiveOk prims outside liveBad 1604 (src_array_ty 984) := by decide +kernel

/-- mini::selfhost::array_len -/
theorem lok1605 : LiveOk prims outside liveBad 1605 (src_array_len 153 156 627 628 1680 1681 1682) := by decide +kernel

/-- mini::selfhost::p_type_ident -/
theorem lok1606 : LiveOk prims outside liveBad 1606 (src_p_type_ident) := by decide +kernel

/-- mini::selfhost::p_type_args_none -/
theorem lok1607 : LiveOk prims outside liveBad 1607 (src_p_type_args_none) := by decide +kernel

/-- mini::selfhost::bare_or_alias -/
theorem lok1608 : LiveOk prims outside liveBad 1608 (src_bare_or_alias 56 448 1683 1684) := by decide +kernel

/-- mini::selfhost::applied_of -/
theorem lok1610 : LiveOk prims outside liveBad 1610 (src_applied_of 56 1684 1688 1689 1690) := by decide +kernel

/-- mini::selfhost::cons_ty -/
theorem lok1621 : LiveOk prims outside liveBad 1621 (src_cons_ty 1708) := by decide +kernel

/-- mini::selfhost::lx_base_digit -/
theorem lok1640 : LiveOk prims outside liveBad 1640 (src_lx_base_digit 56 75) := by decide +kernel

/-- mini::selfhost::lx_digit_tail -/
theorem lok1641 : LiveOk prims outside liveBad 1641 (src_lx_digit_tail 76 1713) := by decide +kernel

/-- mini::selfhost::unbox<mini::selfhost::List<core::option::Option<mini::selfhost::SrcType>>> -/
theorem lok1650 : LiveOk prims outside liveBad 1650 (src_unbox_of_mini_selfhost_List_core_option_Option_mini_selfhost_SrcType 1390) := by decide +kernel

/-- mini::selfhost::same_ty -/
theorem lok1671 : LiveOk prims outside liveBad 1671 (src_same_ty 666 977 1587 1671 1741 1742) := by decide +kernel

/-- mini::selfhost::boxed<mini::selfhost::List<mini::selfhost::Local>> -/
theorem lok1679 : LiveOk prims outside liveBad 1679 (src_boxed_of_mini_selfhost_List_mini_selfhost_Local 50 1743 1744) := by decide +kernel

/-- mini::selfhost::p_type_array_len_constant -/
theorem lok1680 : LiveOk prims outside liveBad 1680 (src_p_type_array_len_constant) := by decide +kernel

/-- mini::selfhost::decimal -/
theorem lok1682 : LiveOk prims outside liveBad 1682 (src_decimal 76 1745) := by decide +kernel

/-- mini::selfhost::bare_ty -/
theorem lok1683 : LiveOk prims outside liveBad 1683 (src_bare_ty 448 1688 1746 1747 1748 1749) := by decide +kernel

/-- mini::selfhost::alias_ty -/
theorem lok1684 : LiveOk prims outside liveBad 1684 (src_alias_ty 56 435 1750 1751 1752 1753) := by decide +kernel

/-- mini::selfhost::p_type_path_end -/
theorem lok1686 : LiveOk prims outside liveBad 1686 (src_p_type_path_end) := by decide +kernel

/-- mini::selfhost::type_decl_at -/
theorem lok1688 : LiveOk prims outside liveBad 1688 (src_type_decl_at 163 1750 1752 1754) := by decide +kernel

/-- mini::selfhost::named_args -/
theorem lok1689 : LiveOk prims outside liveBad 1689 (src_named_args 1755 1756) := by decide +kernel

/-- mini::selfhost::args_tys -/
theorem lok1690 : LiveOk prims outside liveBad 1690 (src_args_tys 56 103 448 1621 1690 1757) := by decide +kernel

/-- mini::selfhost::cons_ty_tail -/
theorem lok1708 : LiveOk prims outside liveBad 1708 (src_cons_ty_tail 669) := by decide +kernel

/-- mini::selfhost::lx_exponent_digits -/
theorem lok1714 : LiveOk prims outside liveBad 1714 (src_lx_exponent_digits 75 830 1774) := by decide +kernel

/-- mini::selfhost::lx_block_end -/
theorem lok1719 : LiveOk prims outside liveBad 1719 (src_lx_block_end 75 593 1779) := by decide +kernel

/-- mini::selfhost::cons_tys_tail -/
theorem lok1737 : LiveOk prims outside liveBad 1737 (src_cons_tys_tail 1782) := by decide +kernel

/-- mini::selfhost::uint_code -/
theorem lok1741 : LiveOk prims outside liveBad 1741 (src_uint_code) := by decide +kernel

/-- mini::selfhost::same_float -/
theorem lok1742 : LiveOk prims outside liveBad 1742 (src_same_float 1784) := by decide +kernel

/-- mini::selfhost::prim_or_named -/
theorem lok1748 : LiveOk prims outside liveBad 1748 (src_prim_or_named 448 1688 1749 1786) := by decide +kernel

/-- mini::selfhost::named_of -/
theorem lok1749 : LiveOk prims outside liveBad 1749 (src_named_of 1689) := by decide +kernel

/-- mini::selfhost::find_alias -/
theorem lok1751 : LiveOk prims outside liveBad 1751 (src_find_alias 655 1788) := by decide +kernel

/-- mini::selfhost::alias_at -/
theorem lok1753 : LiveOk prims outside liveBad 1753 (src_alias_at 56 368 1234 1468 1484) := by decide +kernel

/-- mini::selfhost::named_checked -/
theorem lok1755 : LiveOk prims outside liveBad 1755 (src_named_checked 670) := by decide +kernel

/-- mini::selfhost::arity_ok -/
theorem lok1756 : LiveOk prims outside liveBad 1756 (src_arity_ok 163 368 1185 1234) := by decide +kernel

/-- mini::selfhost::arg_ty -/
theorem lok1757 : LiveOk prims outside liveBad 1757 (src_arg_ty 56 153 156 1468 1791) := by decide +kernel

/-- mini::selfhost::float_code -/
theorem lok1784 : LiveOk prims outside liveBad 1784 (src_float_code) := by decide +kernel

/-- mini::selfhost::boxed<mini::selfhost::MEff> -/
theorem lok1888 : LiveOk prims outside liveBad 1888 (src_boxed_of_mini_selfhost_MEff 50 1460 2004) := by decide +kernel

/-- mini::selfhost::find_const -/
theorem lok1900 : LiveOk prims outside liveBad 1900 (src_find_const 688 2021) := by decide +kernel

/-- mini::selfhost::variants_named -/
theorem lok2029 : LiveOk prims outside liveBad 2029 (src_variants_named 276 2141 2142) := by decide +kernel

/-- mini::selfhost::if_item -/
theorem lok2081 : LiveOk prims outside liveBad 2081 (src_if_item) := by decide +kernel

/-- mini::selfhost::is_module -/
theorem lok2082 : LiveOk prims outside liveBad 2082 (src_is_module 650) := by decide +kernel

/-- mini::selfhost::unbox<mini::selfhost::List<mini::selfhost::VariantTy>> -/
theorem lok2169 : LiveOk prims outside liveBad 2169 (src_unbox_of_mini_selfhost_List_mini_selfhost_VariantTy 2296) := by decide +kernel

/-- mini::selfhost::p_range_start_int -/
theorem lok2191 : LiveOk prims outside liveBad 2191 (src_p_range_start_int) := by decide +kernel

/-- mini::selfhost::concat<mini::selfhost::Token> -/
theorem lok2351 : LiveOk prims outside liveBad 2351 (src_concat_of_mini_selfhost_Token 167 1113 2351) := by decide +kernel

/-- mini::selfhost::arms_in_order -/
theorem lok2424 : LiveOk prims outside liveBad 2424 (src_arms_in_order 2510 2512 2513) := by decide +kernel

/-- mini::selfhost::wild_order -/
theorem lok2512 : LiveOk prims outside liveBad 2512 (src_wild_order 2547 2550 2551) := by decide +kernel

/-- mini::selfhost::arms_exact -/
theorem lok2513 : LiveOk prims outside liveBad 2513 (src_arms_exact 2552 2553 2554) := by decide +kernel

/-- mini::selfhost::boxed<mini::selfhost::List<mini::selfhost::EffArm>> -/
theorem lok2536 : LiveOk prims outside liveBad 2536 (src_boxed_of_mini_selfhost_List_mini_selfhost_EffArm 50 2496 2578) := by decide +kernel

/-- mini::selfhost::all_name_some -/
theorem lok2547 : LiveOk prims outside liveBad 2547 (src_all_name_some 103 2547 2590) := by decide +kernel

/-- mini::selfhost::uses_wild -/
theorem lok2550 : LiveOk prims outside liveBad 2550 (src_uses_wild 2169 2550 2595) := by decide +kernel

/-- mini::selfhost::arms_or_wild -/
theorem lok2551 : LiveOk prims outside liveBad 2551 (src_arms_or_wild 96 103 2169 2551 2572 2595 2596) := by decide +kernel

/-- mini::selfhost::names_some -/
theorem lok2590 : LiveOk prims outside liveBad 2590 (src_names_some 2169 2590 2610) := by decide +kernel

end Lanius.Faithful.SelfPure
