module

public import Lanius.Faithful.Gen.SelfPureTab
public import Lanius.Faithful.Gen.SelfLiveTab
public import Lanius.Faithful.Gen.SelfSrc6
public import Lanius.Faithful.Gen.SelfSrcC_Word_narrows
public import Lanius.Faithful.Gen.SelfSrcC_assignAgrees
public import Lanius.Faithful.Gen.SelfSrcC_elementAddress
public import Lanius.Faithful.Gen.SelfSrcC_killShared
public import Lanius.Faithful.Gen.SelfSrcC_lowerBody
public import Lanius.Faithful.Gen.SelfSrcC_substAll
public import Lanius.Faithful.Gen.SelfSrcF_Inline_pImplMethodsSome
public import Lanius.Faithful.Gen.SelfSrcF_Inline_pPathMore
public import Lanius.Faithful.Gen.SelfSrcF_armsNaming
public import Lanius.Faithful.Gen.SelfSrcF_consBound
public import Lanius.Faithful.Gen.SelfSrcF_ifNotWrites
import all Lanius.Faithful.Gen.SelfLiveTab
import all Lanius.Faithful.Gen.SelfPureTab
import all Lanius.Faithful.Gen.SelfSrc6
import all Lanius.Faithful.Gen.SelfSrcC_Word_narrows
import all Lanius.Faithful.Gen.SelfSrcC_assignAgrees
import all Lanius.Faithful.Gen.SelfSrcC_elementAddress
import all Lanius.Faithful.Gen.SelfSrcC_killShared
import all Lanius.Faithful.Gen.SelfSrcC_lowerBody
import all Lanius.Faithful.Gen.SelfSrcC_substAll
import all Lanius.Faithful.Gen.SelfSrcF_Inline_pImplMethodsSome
import all Lanius.Faithful.Gen.SelfSrcF_Inline_pPathMore
import all Lanius.Faithful.Gen.SelfSrcF_armsNaming
import all Lanius.Faithful.Gen.SelfSrcF_consBound
import all Lanius.Faithful.Gen.SelfSrcF_ifNotWrites
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

/-- mini::selfhost::returns -/
theorem lok58 : LiveOk prims outside liveBad 58 (src_SrcStmt_returns 58 81) := by decide +kernel

/-- mini::selfhost::unbox<mini::selfhost::List<mini::selfhost::SrcFunc>> -/
theorem lok59 : LiveOk prims outside liveBad 59 (src_unbox_of_mini_selfhost_List_mini_selfhost_SrcFunc 82) := by decide +kernel

/-- mini::selfhost::lower_funcs -/
theorem lok61 : LiveOk prims outside liveBad 61 (src_lower_funcs 59 61 84 85 86 87) := by decide +kernel

/-- mini::selfhost::boxed<mini::selfhost::List<mini::selfhost::Sym>> -/
theorem lok74 : LiveOk prims outside liveBad 74 (src_boxed_of_mini_selfhost_List_mini_selfhost_Sym 50 107 108) := by decide +kernel

/-- mini::selfhost::unbox<mini::selfhost::List<usize>> -/
theorem lok76 : LiveOk prims outside liveBad 76 (src_unbox_of_mini_selfhost_List_usize 109) := by decide +kernel

/-- mini::selfhost::unbox<mini::selfhost::SrcStmt> -/
theorem lok81 : LiveOk prims outside liveBad 81 (src_unbox_of_mini_selfhost_SrcStmt 112) := by decide +kernel

/-- mini::selfhost::lower_func_cons -/
theorem lok85 : LiveOk prims outside liveBad 85 (src_lower_func_cons 117) := by decide +kernel

/-- mini::selfhost::lower_func -/
theorem lok86 : LiveOk prims outside liveBad 86 (src_lower_func 56 118 119 120 121 122 123 124 125 126 127 128 129 130 131) := by decide +kernel

/-- mini::selfhost::declare_func -/
theorem lok91 : LiveOk prims outside liveBad 91 (src_declare_func 141 142 143) := by decide +kernel

/-- mini::selfhost::unbox<mini::selfhost::List<mini::selfhost::FileInput>> -/
theorem lok99 : LiveOk prims outside liveBad 99 (src_unbox_of_mini_selfhost_List_mini_selfhost_FileInput 152) := by decide +kernel

/-- mini::selfhost::lower_body -/
theorem lok124 : LiveOk prims outside liveBad 124 (src_lower_body 75 186 187) := by decide +kernel

/-- mini::selfhost::unit_tail -/
theorem lok126 : LiveOk prims outside liveBad 126 (src_unit_tail 57 188 189) := by decide +kernel

/-- mini::selfhost::with_frame -/
theorem lok127 : LiveOk prims outside liveBad 127 (src_with_frame 188) := by decide +kernel

/-- mini::selfhost::declare_params -/
theorem lok141 : LiveOk prims outside liveBad 141 (src_declare_params 143 174 243) := by decide +kernel

/-- mini::selfhost::declare -/
theorem lok143 : LiveOk prims outside liveBad 143 (src_SrcType_declare 143 181 183 184 245 246 247 248) := by decide +kernel

/-- mini::selfhost::declare -/
theorem lok244 : LiveOk prims outside liveBad 244 (src_SrcStmt_declare 81 142 143 240 244 246 404 405) := by decide +kernel

/-- mini::selfhost::declare_struct -/
theorem lok245 : LiveOk prims outside liveBad 245 (src_declare_struct 406 407) := by decide +kernel

/-- mini::selfhost::declare_types -/
theorem lok246 : LiveOk prims outside liveBad 246 (src_declare_types 143 181 408) := by decide +kernel

/-- mini::selfhost::declare_enum -/
theorem lok247 : LiveOk prims outside liveBad 247 (src_declare_enum 409 410) := by decide +kernel

/-- mini::selfhost::declare_variants -/
theorem lok248 : LiveOk prims outside liveBad 248 (src_declare_variants 183 246 411) := by decide +kernel

/-- mini::selfhost::empty<mini::selfhost::List<usize>> -/
theorem lok265 : LiveOk prims outside liveBad 265 (src_empty_of_mini_selfhost_List_usize) := by decide +kernel

/-- mini::selfhost::empty<mini::selfhost::Inst> -/
theorem lok272 : LiveOk prims outside liveBad 272 (src_empty_of_mini_selfhost_Inst) := by decide +kernel

/-- mini::selfhost::unbox<mini::selfhost::List<mini::selfhost::Func>> -/
theorem lok283 : LiveOk prims outside liveBad 283 (src_unbox_of_mini_selfhost_List_mini_selfhost_Func 295) := by decide +kernel

/-- mini::selfhost::cons<mini::selfhost::Arity> -/
theorem lok289 : LiveOk prims outside liveBad 289 (src_cons_of_mini_selfhost_Arity 482) := by decide +kernel

/-- mini::selfhost::unbox<mini::selfhost::List<mini::selfhost::SrcExpr>> -/
theorem lok321 : LiveOk prims outside liveBad 321 (src_unbox_of_mini_selfhost_List_mini_selfhost_SrcExpr 515) := by decide +kernel

/-- mini::selfhost::length<mini::selfhost::SrcEff> -/
theorem lok369 : LiveOk prims outside liveBad 369 (src_length_of_mini_selfhost_SrcEff 75 356 369) := by decide +kernel

/-- mini::selfhost::concat<mini::selfhost::SrcType> -/
theorem lok405 : LiveOk prims outside liveBad 405 (src_concat_of_mini_selfhost_SrcType 181 402 405) := by decide +kernel

/-- mini::selfhost::p_item_pub -/
theorem lok430 : LiveOk prims outside liveBad 430 (src_p_item_pub) := by decide +kernel

/-- mini::selfhost::subst_all -/
theorem lok469 : LiveOk prims outside liveBad 469 (src_subst_all 464 469 493 541 542) := by decide +kernel

/-- mini::selfhost::cons<mini::selfhost::Instr> -/
theorem lok476 : LiveOk prims outside liveBad 476 (src_cons_of_mini_selfhost_Instr 739) := by decide +kernel

/-- mini::selfhost::unbox<mini::selfhost::List<mini::selfhost::Expr>> -/
theorem lok493 : LiveOk prims outside liveBad 493 (src_unbox_of_mini_selfhost_List_mini_selfhost_Expr 495) := by decide +kernel

/-- mini::selfhost::lower_load_word -/
theorem lok534 : LiveOk prims outside liveBad 534 (src_lower_load_word 188) := by decide +kernel

/-- mini::selfhost::lower_element -/
theorem lok535 : LiveOk prims outside liveBad 535 (src_lower_element 784) := by decide +kernel

/-- mini::selfhost::cons<u64> -/
theorem lok577 : LiveOk prims outside liveBad 577 (src_cons_of_u64 824) := by decide +kernel

/-- mini::selfhost::keep_if -/
theorem lok582 : LiveOk prims outside liveBad 582 (src_keep_if) := by decide +kernel

/-- mini::selfhost::empty<mini::selfhost::Token> -/
theorem lok596 : LiveOk prims outside liveBad 596 (src_empty_of_mini_selfhost_Token) := by decide +kernel

/-- mini::selfhost::p_impl_trait -/
theorem lok631 : LiveOk prims outside liveBad 631 (src_p_impl_trait) := by decide +kernel

/-- mini::selfhost::p_import -/
theorem lok633 : LiveOk prims outside liveBad 633 (src_p_import) := by decide +kernel

/-- mini::selfhost::p_import_path -/
theorem lok634 : LiveOk prims outside liveBad 634 (src_p_import_path) := by decide +kernel

/-- mini::selfhost::p_path_more -/
theorem lok648 : LiveOk prims outside liveBad 648 (src_p_path_more) := by decide +kernel

/-- mini::selfhost::length<mini::selfhost::Inst> -/
theorem lok663 : LiveOk prims outside liveBad 663 (src_length_of_mini_selfhost_Inst 75 663 671) := by decide +kernel

/-- mini::selfhost::unbox<mini::selfhost::List<mini::selfhost::ConstDecl>> -/
theorem lok688 : LiveOk prims outside liveBad 688 (src_unbox_of_mini_selfhost_List_mini_selfhost_ConstDecl 1005) := by decide +kernel

/-- mini::selfhost::boxed<mini::selfhost::List<mini::selfhost::ImportDecl>> -/
theorem lok689 : LiveOk prims outside liveBad 689 (src_boxed_of_mini_selfhost_List_mini_selfhost_ImportDecl 50 1006 1007) := by decide +kernel

/-- mini::selfhost::assign_agrees -/
theorem lok707 : LiveOk prims outside liveBad 707 (src_assign_agrees 1021) := by decide +kernel

/-- mini::selfhost::unbox<mini::selfhost::List<mini::selfhost::Instr>> -/
theorem lok741 : LiveOk prims outside liveBad 741 (src_unbox_of_mini_selfhost_List_mini_selfhost_Instr 1035) := by decide +kernel

/-- mini::selfhost::p_items_more -/
theorem lok847 : LiveOk prims outside liveBad 847 (src_p_items_more) := by decide +kernel

/-- mini::selfhost::p_items_end -/
theorem lok848 : LiveOk prims outside liveBad 848 (src_p_items_end) := by decide +kernel

/-- mini::selfhost::p_patterns_none -/
theorem lok893 : LiveOk prims outside liveBad 893 (src_p_patterns_none) := by decide +kernel

/-- mini::selfhost::p_patterns_some -/
theorem lok894 : LiveOk prims outside liveBad 894 (src_p_patterns_some) := by decide +kernel

/-- mini::selfhost::p_patterns_more -/
theorem lok895 : LiveOk prims outside liveBad 895 (src_p_patterns_more) := by decide +kernel

/-- mini::selfhost::p_patterns_end -/
theorem lok896 : LiveOk prims outside liveBad 896 (src_p_patterns_end) := by decide +kernel

/-- mini::selfhost::p_patterns_after_comma_more -/
theorem lok897 : LiveOk prims outside liveBad 897 (src_p_patterns_after_comma_more) := by decide +kernel

/-- mini::selfhost::p_patterns_after_comma_trailing -/
theorem lok898 : LiveOk prims outside liveBad 898 (src_p_patterns_after_comma_trailing) := by decide +kernel

/-- mini::selfhost::p_path_type_args_more -/
theorem lok905 : LiveOk prims outside liveBad 905 (src_p_path_type_args_more) := by decide +kernel

/-- mini::selfhost::p_path_type_args_after_comma_more -/
theorem lok906 : LiveOk prims outside liveBad 906 (src_p_path_type_args_after_comma_more) := by decide +kernel

/-- mini::selfhost::p_impl_methods_some -/
theorem lok907 : LiveOk prims outside liveBad 907 (src_p_impl_methods_some) := by decide +kernel

/-- mini::selfhost::single<mini::selfhost::TypeDecl> -/
theorem lok920 : LiveOk prims outside liveBad 920 (src_single_of_mini_selfhost_TypeDecl 685) := by decide +kernel

/-- mini::selfhost::single<mini::selfhost::AliasDecl> -/
theorem lok930 : LiveOk prims outside liveBad 930 (src_single_of_mini_selfhost_AliasDecl 691) := by decide +kernel

/-- mini::selfhost::single<mini::selfhost::MParam> -/
theorem lok997 : LiveOk prims outside liveBad 997 (src_single_of_mini_selfhost_MParam 1250) := by decide +kernel

/-- mini::selfhost::kill_shared -/
theorem lok1019 : LiveOk prims outside liveBad 1019 (src_kill_shared 1266 1267) := by decide +kernel

/-- mini::selfhost::negate_constant -/
theorem lok1022 : LiveOk prims outside liveBad 1022 (src_negate_constant 1011) := by decide +kernel

/-- mini::selfhost::number -/
theorem lok1028 : LiveOk prims outside liveBad 1028 (src_Word_number) := by decide +kernel

/-- mini::selfhost::cons<u8> -/
theorem lok1042 : LiveOk prims outside liveBad 1042 (src_cons_of_u8 1041) := by decide +kernel

/-- mini::selfhost::concat<mini::selfhost::Expr> -/
theorem lok1065 : LiveOk prims outside liveBad 1065 (src_concat_of_mini_selfhost_Expr 311 493 1065) := by decide +kernel

/-- mini::selfhost::element_address -/
theorem lok1073 : LiveOk prims outside liveBad 1073 (src_element_address 380 1329) := by decide +kernel

/-- mini::selfhost::store_byte_element -/
theorem lok1075 : LiveOk prims outside liveBad 1075 (src_store_byte_element 207 1073) := by decide +kernel

/-- mini::selfhost::boxed<mini::selfhost::List<mini::selfhost::RawTok>> -/
theorem lok1110 : LiveOk prims outside liveBad 1110 (src_boxed_of_mini_selfhost_List_mini_selfhost_RawTok 50 836 1343) := by decide +kernel

/-- mini::selfhost::boxed<mini::selfhost::List<mini::selfhost::Token>> -/
theorem lok1113 : LiveOk prims outside liveBad 1113 (src_boxed_of_mini_selfhost_List_mini_selfhost_Token 50 280 1344) := by decide +kernel

/-- mini::selfhost::empty<mini::selfhost::LocalTy> -/
theorem lok1215 : LiveOk prims outside liveBad 1215 (src_empty_of_mini_selfhost_LocalTy) := by decide +kernel

/-- mini::selfhost::cons<mini::selfhost::LocalTy> -/
theorem lok1216 : LiveOk prims outside liveBad 1216 (src_cons_of_mini_selfhost_LocalTy 1452) := by decide +kernel

/-- mini::selfhost::ref_checked -/
theorem lok1247 : LiveOk prims outside liveBad 1247 (src_ref_checked 1478 1479) := by decide +kernel

/-- mini::selfhost::self_ref_id -/
theorem lok1249 : LiveOk prims outside liveBad 1249 (src_self_ref_id 1481) := by decide +kernel

/-- mini::selfhost::keeps -/
theorem lok1258 : LiveOk prims outside liveBad 1258 (src_Word_keeps 1486) := by decide +kernel

/-- mini::selfhost::mentions_any -/
theorem lok1270 : LiveOk prims outside liveBad 1270 (src_mentions_any 493 1263 1270) := by decide +kernel

/-- mini::selfhost::fold_constant -/
theorem lok1277 : LiveOk prims outside liveBad 1277 (src_fold_constant 1252 1253) := by decide +kernel

/-- mini::selfhost::absorbed -/
theorem lok1278 : LiveOk prims outside liveBad 1278 (src_absorbed 1254) := by decide +kernel

/-- mini::selfhost::unbox<mini::selfhost::List<mini::selfhost::Arity>> -/
theorem lok1279 : LiveOk prims outside liveBad 1279 (src_unbox_of_mini_selfhost_List_mini_selfhost_Arity 753) := by decide +kernel

/-- mini::selfhost::boxed<mini::selfhost::SrcExpr> -/
theorem lok1428 : LiveOk prims outside liveBad 1428 (src_boxed_of_mini_selfhost_SrcExpr 50 497 1566) := by decide +kernel

/-- mini::selfhost::boxed<mini::selfhost::List<mini::selfhost::LocalTy>> -/
theorem lok1452 : LiveOk prims outside liveBad 1452 (src_boxed_of_mini_selfhost_List_mini_selfhost_LocalTy 50 1578 1585) := by decide +kernel

/-- mini::selfhost::if_not_writes -/
theorem lok1478 : LiveOk prims outside liveBad 1478 (src_if_not_writes) := by decide +kernel

/-- mini::selfhost::narrow -/
theorem lok1486 : LiveOk prims outside liveBad 1486 (src_Expr_narrow 1622) := by decide +kernel

/-- mini::selfhost::first_facts -/
theorem lok1489 : LiveOk prims outside liveBad 1489 (src_first_facts 56 282 1017 1264 1489) := by decide +kernel

/-- mini::selfhost::kill_tail -/
theorem lok1490 : LiveOk prims outside liveBad 1490 (src_kill_tail 1624 1625) := by decide +kernel

/-- mini::selfhost::fact_dies -/
theorem lok1493 : LiveOk prims outside liveBad 1493 (src_fact_dies 1263) := by decide +kernel

/-- mini::selfhost::number -/
theorem lok1497 : LiveOk prims outside liveBad 1497 (src_FOp_number 75 105 574 1028 1626 1627) := by decide +kernel

/-- mini::selfhost::known_true -/
theorem lok1616 : LiveOk prims outside liveBad 1616 (src_known_true) := by decide +kernel

/-- mini::selfhost::narrows -/
theorem lok1622 : LiveOk prims outside liveBad 1622 (src_Word_narrows) := by decide +kernel

/-- mini::selfhost::none_dies -/
theorem lok1624 : LiveOk prims outside liveBad 1624 (src_none_dies 1017 1493 1624) := by decide +kernel

/-- mini::selfhost::kill -/
theorem lok1625 : LiveOk prims outside liveBad 1625 (src_kill 282 1017 1625 1709) := by decide +kernel

/-- mini::selfhost::number -/
theorem lok1626 : LiveOk prims outside liveBad 1626 (src_FArith_number) := by decide +kernel

/-- mini::selfhost::number -/
theorem lok1627 : LiveOk prims outside liveBad 1627 (src_FCmp_number) := by decide +kernel

/-- mini::selfhost::p_postfix -/
theorem lok1764 : LiveOk prims outside liveBad 1764 (src_p_postfix) := by decide +kernel

/-- mini::selfhost::p_postfix_end -/
theorem lok1798 : LiveOk prims outside liveBad 1798 (src_p_postfix_end) := by decide +kernel

/-- mini::selfhost::p_postfix_member -/
theorem lok1801 : LiveOk prims outside liveBad 1801 (src_p_postfix_member) := by decide +kernel

/-- mini::selfhost::p_postfix_call -/
theorem lok1802 : LiveOk prims outside liveBad 1802 (src_p_postfix_call) := by decide +kernel

/-- mini::selfhost::p_int -/
theorem lok1821 : LiveOk prims outside liveBad 1821 (src_p_int) := by decide +kernel

/-- mini::selfhost::p_postfix_index -/
theorem lok1893 : LiveOk prims outside liveBad 1893 (src_p_postfix_index) := by decide +kernel

/-- mini::selfhost::p_range_exclusive -/
theorem lok2192 : LiveOk prims outside liveBad 2192 (src_p_range_exclusive) := by decide +kernel

/-- mini::selfhost::p_range_bound -/
theorem lok2193 : LiveOk prims outside liveBad 2193 (src_p_range_bound) := by decide +kernel

/-- mini::selfhost::p_range_bound_name -/
theorem lok2194 : LiveOk prims outside liveBad 2194 (src_p_range_bound_name) := by decide +kernel

/-- mini::selfhost::p_pattern_int -/
theorem lok2283 : LiveOk prims outside liveBad 2283 (src_p_pattern_int) := by decide +kernel

/-- mini::selfhost::p_pattern_true -/
theorem lok2284 : LiveOk prims outside liveBad 2284 (src_p_pattern_true) := by decide +kernel

/-- mini::selfhost::p_pattern_false -/
theorem lok2285 : LiveOk prims outside liveBad 2285 (src_p_pattern_false) := by decide +kernel

/-- mini::selfhost::p_postfix_try -/
theorem lok2340 : LiveOk prims outside liveBad 2340 (src_p_postfix_try) := by decide +kernel

/-- mini::selfhost::unbox<mini::selfhost::List<mini::selfhost::Bind>> -/
theorem lok2348 : LiveOk prims outside liveBad 2348 (src_unbox_of_mini_selfhost_List_mini_selfhost_Bind 2469) := by decide +kernel

/-- mini::selfhost::p_pattern_ident -/
theorem lok2425 : LiveOk prims outside liveBad 2425 (src_p_pattern_ident) := by decide +kernel

/-- mini::selfhost::p_pattern_plain -/
theorem lok2427 : LiveOk prims outside liveBad 2427 (src_p_pattern_plain) := by decide +kernel

/-- mini::selfhost::cons_bound -/
theorem lok2493 : LiveOk prims outside liveBad 2493 (src_cons_bound 1472) := by decide +kernel

/-- mini::selfhost::text_underscore -/
theorem lok2517 : LiveOk prims outside liveBad 2517 (src_text_underscore 376) := by decide +kernel

/-- mini::selfhost::arms_by_variant -/
theorem lok2554 : LiveOk prims outside liveBad 2554 (src_arms_by_variant 96 103 2169 2554 2572 2595) := by decide +kernel

/-- mini::selfhost::arms_naming -/
theorem lok2595 : LiveOk prims outside liveBad 2595 (src_arms_naming 96 103 2595 2610 2617) := by decide +kernel

/-- mini::selfhost::p_pattern_tuple -/
theorem lok2626 : LiveOk prims outside liveBad 2626 (src_p_pattern_tuple) := by decide +kernel

end Lanius.Faithful.SelfPure
