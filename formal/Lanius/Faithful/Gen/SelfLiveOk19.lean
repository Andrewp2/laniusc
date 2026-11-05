module

public import Lanius.Faithful.Gen.SelfPureTab
public import Lanius.Faithful.Gen.SelfLiveTab
public import Lanius.Faithful.Gen.SelfSrc7
public import Lanius.Faithful.Gen.SelfSrcC_storeWordElement
public import Lanius.Faithful.Gen.SelfSrcC_wordElement
public import Lanius.Faithful.Gen.SelfSrcF_Inline_attachNode
public import Lanius.Faithful.Gen.SelfSrcF_Inline_pBitAnd
public import Lanius.Faithful.Gen.SelfSrcF_Inline_pBoundTypeArgsAfterCommaMore
public import Lanius.Faithful.Gen.SelfSrcF_flattenTys
public import Lanius.Faithful.Gen.SelfSrcF_lxSpaceEnd
public import Lanius.Faithful.Gen.SelfSrcF_matchStmtIf
public import Lanius.Faithful.Gen.SelfSrcF_moduleOr
public import Lanius.Faithful.Gen.SelfSrcF_noToken
public import Lanius.Faithful.Gen.SelfSrcF_nullAt
public import Lanius.Faithful.Gen.SelfSrcF_retBinds
import all Lanius.Faithful.Gen.SelfLiveTab
import all Lanius.Faithful.Gen.SelfPureTab
import all Lanius.Faithful.Gen.SelfSrc7
import all Lanius.Faithful.Gen.SelfSrcC_storeWordElement
import all Lanius.Faithful.Gen.SelfSrcC_wordElement
import all Lanius.Faithful.Gen.SelfSrcF_Inline_attachNode
import all Lanius.Faithful.Gen.SelfSrcF_Inline_pBitAnd
import all Lanius.Faithful.Gen.SelfSrcF_Inline_pBoundTypeArgsAfterCommaMore
import all Lanius.Faithful.Gen.SelfSrcF_flattenTys
import all Lanius.Faithful.Gen.SelfSrcF_lxSpaceEnd
import all Lanius.Faithful.Gen.SelfSrcF_matchStmtIf
import all Lanius.Faithful.Gen.SelfSrcF_moduleOr
import all Lanius.Faithful.Gen.SelfSrcF_noToken
import all Lanius.Faithful.Gen.SelfSrcF_nullAt
import all Lanius.Faithful.Gen.SelfSrcF_retBinds
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

/-- mini::selfhost::unbox<mini::selfhost::List<i32>> -/
theorem lok10 : LiveOk prims outside liveBad 10 (src_unbox_of_mini_selfhost_List_i32 34) := by decide +kernel

/-- mini::selfhost::boxed<mini::selfhost::List<i32>> -/
theorem lok33 : LiveOk prims outside liveBad 33 (src_boxed_of_mini_selfhost_List_i32 34 49 50) := by decide +kernel

/-- mini::selfhost::minus -/
theorem lok56 : LiveOk prims outside liveBad 56 (src_minus) := by decide +kernel

/-- mini::selfhost::unbox<mini::selfhost::List<u8>> -/
theorem lok78 : LiveOk prims outside liveBad 78 (src_unbox_of_mini_selfhost_List_u8 111) := by decide +kernel

/-- mini::selfhost::cons<mini::selfhost::Func> -/
theorem lok117 : LiveOk prims outside liveBad 117 (src_cons_of_mini_selfhost_Func 173) := by decide +kernel

/-- mini::selfhost::kid -/
theorem lok156 : LiveOk prims outside liveBad 156 (src_kid 260 261 262) := by decide +kernel

/-- mini::selfhost::module_path -/
theorem lok158 : LiveOk prims outside liveBad 158 (src_module_path 103 265 266 267) := by decide +kernel

/-- mini::selfhost::unbox<mini::selfhost::List<mini::selfhost::Token>> -/
theorem lok167 : LiveOk prims outside liveBad 167 (src_unbox_of_mini_selfhost_List_mini_selfhost_Token 280) := by decide +kernel

/-- mini::selfhost::boxed<mini::selfhost::List<mini::selfhost::Func>> -/
theorem lok173 : LiveOk prims outside liveBad 173 (src_boxed_of_mini_selfhost_List_mini_selfhost_Func 50 294 295) := by decide +kernel

/-- mini::selfhost::unbox<mini::selfhost::List<mini::selfhost::SrcParam>> -/
theorem lok174 : LiveOk prims outside liveBad 174 (src_unbox_of_mini_selfhost_List_mini_selfhost_SrcParam 296) := by decide +kernel

/-- mini::selfhost::unbox<mini::selfhost::List<mini::selfhost::Sym>> -/
theorem lok256 : LiveOk prims outside liveBad 256 (src_unbox_of_mini_selfhost_List_mini_selfhost_Sym 108) := by decide +kernel

/-- mini::selfhost::kids_of -/
theorem lok260 : LiveOk prims outside liveBad 260 (src_kids_of 96 103) := by decide +kernel

/-- mini::selfhost::no_token -/
theorem lok262 : LiveOk prims outside liveBad 262 (src_no_token 139) := by decide +kernel

/-- mini::selfhost::item_body -/
theorem lok267 : LiveOk prims outside liveBad 267 (src_item_body 153 156 430) := by decide +kernel

/-- mini::selfhost::empty<mini::selfhost::Arity> -/
theorem lok288 : LiveOk prims outside liveBad 288 (src_empty_of_mini_selfhost_Arity) := by decide +kernel

/-- mini::selfhost::boxed<mini::selfhost::List<mini::selfhost::Expr>> -/
theorem lok311 : LiveOk prims outside liveBad 311 (src_boxed_of_mini_selfhost_List_mini_selfhost_Expr 50 494 495) := by decide +kernel

/-- mini::selfhost::word_element -/
theorem lok340 : LiveOk prims outside liveBad 340 (src_word_element 339 394 525) := by decide +kernel

/-- mini::selfhost::no_decls -/
theorem lok425 : LiveOk prims outside liveBad 425 (src_no_decls 608 609 610 611 612 613 614) := by decide +kernel

/-- ?<mini::selfhost::Decls> -/
theorem lok435 : LiveOk prims outside liveBad 435 (src_field_aliases_Decls_of_mini_selfhost_Decls) := by decide +kernel

/-- ?<mini::selfhost::Decls> -/
theorem lok459 : LiveOk prims outside liveBad 459 (src_field_impls_Decls_of_mini_selfhost_Decls) := by decide +kernel

/-- mini::selfhost::boxed<mini::selfhost::List<mini::selfhost::Arity>> -/
theorem lok482 : LiveOk prims outside liveBad 482 (src_boxed_of_mini_selfhost_List_mini_selfhost_Arity 50 752 753) := by decide +kernel

/-- mini::selfhost::lower_set_index_of -/
theorem lok538 : LiveOk prims outside liveBad 538 (src_lower_set_index_of 380 786) := by decide +kernel

/-- mini::selfhost::cons<mini::selfhost::Expr> -/
theorem lok542 : LiveOk prims outside liveBad 542 (src_cons_of_mini_selfhost_Expr 311) := by decide +kernel

/-- mini::selfhost::unbox<mini::selfhost::List<mini::selfhost::List<usize>>> -/
theorem lok558 : LiveOk prims outside liveBad 558 (src_unbox_of_mini_selfhost_List_mini_selfhost_List_usize 807) := by decide +kernel

/-- mini::selfhost::join_decls -/
theorem lok615 : LiveOk prims outside liveBad 615 (src_join_decls 451 452 453 455 457 458 460) := by decide +kernel

/-- mini::selfhost::type_decl -/
theorem lok619 : LiveOk prims outside liveBad 619 (src_type_decl 153 155 156 616 617 627 628 637 639 921 922 923) := by decide +kernel

/-- mini::selfhost::cons_fn_decl -/
theorem lok622 : LiveOk prims outside liveBad 622 (src_cons_fn_decl 924) := by decide +kernel

/-- mini::selfhost::fn_decl_of -/
theorem lok623 : LiveOk prims outside liveBad 623 (src_fn_decl_of 627 628) := by decide +kernel

/-- mini::selfhost::type_params -/
theorem lok624 : LiveOk prims outside liveBad 624 (src_type_params 155 925) := by decide +kernel

/-- mini::selfhost::p_const -/
theorem lok625 : LiveOk prims outside liveBad 625 (src_p_const) := by decide +kernel

/-- mini::selfhost::import_decls -/
theorem lok635 : LiveOk prims outside liveBad 635 (src_import_decls 608 609 610 612 613 614 929) := by decide +kernel

/-- mini::selfhost::free_params -/
theorem lok639 : LiveOk prims outside liveBad 639 (src_free_params 155 925 931 932) := by decide +kernel

/-- mini::selfhost::module_decls -/
theorem lok643 : LiveOk prims outside liveBad 643 (src_module_decls 104 608 609 610 611 612 613) := by decide +kernel

/-- mini::selfhost::unbox<mini::selfhost::List<mini::selfhost::List<mini::selfhost::List<usize>>>> -/
theorem lok651 : LiveOk prims outside liveBad 651 (src_unbox_of_mini_selfhost_List_mini_selfhost_List_mini_selfhost_List_usize 279) := by decide +kernel

/-- mini::selfhost::boxed<mini::selfhost::List<mini::selfhost::Ty>> -/
theorem lok670 : LiveOk prims outside liveBad 670 (src_boxed_of_mini_selfhost_List_mini_selfhost_Ty 50 976 980) := by decide +kernel

/-- mini::selfhost::boxed<mini::selfhost::List<mini::selfhost::ImplDecl>> -/
theorem lok692 : LiveOk prims outside liveBad 692 (src_boxed_of_mini_selfhost_List_mini_selfhost_ImplDecl 50 1009 1010) := by decide +kernel

/-- mini::selfhost::boxed<mini::selfhost::List<mini::selfhost::Instr>> -/
theorem lok739 : LiveOk prims outside liveBad 739 (src_boxed_of_mini_selfhost_List_mini_selfhost_Instr 50 1034 1035) := by decide +kernel

/-- mini::selfhost::empty<mini::selfhost::Instr> -/
theorem lok740 : LiveOk prims outside liveBad 740 (src_empty_of_mini_selfhost_Instr) := by decide +kernel

/-- mini::selfhost::concat<u8> -/
theorem lok754 : LiveOk prims outside liveBad 754 (src_concat_of_u8 78 754 1041) := by decide +kernel

/-- mini::selfhost::length<mini::selfhost::SrcArm> -/
theorem lok770 : LiveOk prims outside liveBad 770 (src_length_of_mini_selfhost_SrcArm 75 770 1066) := by decide +kernel

/-- mini::selfhost::store_any -/
theorem lok786 : LiveOk prims outside liveBad 786 (src_store_any 338 339 340 1074 1075 1076) := by decide +kernel

/-- mini::selfhost::cons<mini::selfhost::Token> -/
theorem lok834 : LiveOk prims outside liveBad 834 (src_cons_of_mini_selfhost_Token 1113) := by decide +kernel

/-- mini::selfhost::with_kid -/
theorem lok841 : LiveOk prims outside liveBad 841 (src_with_kid 148) := by decide +kernel

/-- mini::selfhost::t_gt -/
theorem lok843 : LiveOk prims outside liveBad 843 (src_t_gt) := by decide +kernel

/-- mini::selfhost::attach_prod -/
theorem lok846 : LiveOk prims outside liveBad 846 (src_attach_prod 1117 1118 1119) := by decide +kernel

/-- mini::selfhost::p_type_param_bound_more -/
theorem lok909 : LiveOk prims outside liveBad 909 (src_p_type_param_bound_more) := by decide +kernel

/-- mini::selfhost::p_where_predicates_more -/
theorem lok910 : LiveOk prims outside liveBad 910 (src_p_where_predicates_more) := by decide +kernel

/-- mini::selfhost::p_where_predicate_more_after_comma -/
theorem lok911 : LiveOk prims outside liveBad 911 (src_p_where_predicate_more_after_comma) := by decide +kernel

/-- mini::selfhost::p_bound_type_args_more -/
theorem lok912 : LiveOk prims outside liveBad 912 (src_p_bound_type_args_more) := by decide +kernel

/-- mini::selfhost::p_bound_type_args_after_comma_more -/
theorem lok913 : LiveOk prims outside liveBad 913 (src_p_bound_type_args_after_comma_more) := by decide +kernel

/-- mini::selfhost::struct_decl_of -/
theorem lok921 : LiveOk prims outside liveBad 921 (src_struct_decl_of 1121 1122) := by decide +kernel

/-- mini::selfhost::enum_decl_of -/
theorem lok922 : LiveOk prims outside liveBad 922 (src_enum_decl_of 96 265) := by decide +kernel

/-- mini::selfhost::variants_of -/
theorem lok923 : LiveOk prims outside liveBad 923 (src_variants_of 103 265 627 628 923 1123 1124 1125) := by decide +kernel

/-- mini::selfhost::param_spellings -/
theorem lok925 : LiveOk prims outside liveBad 925 (src_param_spellings 103 265 1126) := by decide +kernel

/-- mini::selfhost::if_unbounded -/
theorem lok931 : LiveOk prims outside liveBad 931 (src_if_unbounded) := by decide +kernel

/-- mini::selfhost::unbounded -/
theorem lok932 : LiveOk prims outside liveBad 932 (src_unbounded 103 153 156 932 1129) := by decide +kernel

/-- mini::selfhost::concat<mini::selfhost::List<usize>> -/
theorem lok941 : LiveOk prims outside liveBad 941 (src_concat_of_mini_selfhost_List_usize 558 937 941) := by decide +kernel

/-- mini::selfhost::empty<mini::selfhost::SrcFunc> -/
theorem lok952 : LiveOk prims outside liveBad 952 (src_empty_of_mini_selfhost_SrcFunc) := by decide +kernel

/-- mini::selfhost::cons<mini::selfhost::SrcFunc> -/
theorem lok965 : LiveOk prims outside liveBad 965 (src_cons_of_mini_selfhost_SrcFunc 1200) := by decide +kernel

/-- mini::selfhost::get<mini::selfhost::Ty> -/
theorem lok1000 : LiveOk prims outside liveBad 1000 (src_get_of_mini_selfhost_Ty 56 666 1000) := by decide +kernel

/-- mini::selfhost::single<u8> -/
theorem lok1043 : LiveOk prims outside liveBad 1043 (src_single_of_u8 1041) := by decide +kernel

/-- mini::selfhost::store_word_element -/
theorem lok1076 : LiveOk prims outside liveBad 1076 (src_store_word_element 120 193 816 817) := by decide +kernel

/-- mini::selfhost::get<mini::selfhost::Expr> -/
theorem lok1091 : LiveOk prims outside liveBad 1091 (src_get_of_mini_selfhost_Expr 56 493 1091) := by decide +kernel

/-- mini::selfhost::lx_space_end -/
theorem lok1105 : LiveOk prims outside liveBad 1105 (src_lx_space_end 75 593 1340) := by decide +kernel

/-- mini::selfhost::lx_quoted -/
theorem lok1107 : LiveOk prims outside liveBad 1107 (src_lx_quoted 76 1341) := by decide +kernel

/-- mini::selfhost::attach_node -/
theorem lok1119 : LiveOk prims outside liveBad 1119 (src_attach_node 75 149 1356) := by decide +kernel

/-- mini::selfhost::struct_decl_fields -/
theorem lok1121 : LiveOk prims outside liveBad 1121 (src_struct_decl_fields 265 940 1123) := by decide +kernel

/-- mini::selfhost::fields_of -/
theorem lok1122 : LiveOk prims outside liveBad 1122 (src_fields_of 96 103 265 1122 1357) := by decide +kernel

/-- mini::selfhost::cons_variant -/
theorem lok1124 : LiveOk prims outside liveBad 1124 (src_cons_variant 1358) := by decide +kernel

/-- mini::selfhost::variant_payload -/
theorem lok1125 : LiveOk prims outside liveBad 1125 (src_variant_payload 96 153 155 156 1359) := by decide +kernel

/-- mini::selfhost::p_type_param_bound_none -/
theorem lok1129 : LiveOk prims outside liveBad 1129 (src_p_type_param_bound_none) := by decide +kernel

/-- mini::selfhost::boxed<mini::selfhost::List<mini::selfhost::SrcFunc>> -/
theorem lok1200 : LiveOk prims outside liveBad 1200 (src_boxed_of_mini_selfhost_List_mini_selfhost_SrcFunc 50 82 1423) := by decide +kernel

/-- mini::selfhost::p_block_stmt -/
theorem lok1351 : LiveOk prims outside liveBad 1351 (src_p_block_stmt) := by decide +kernel

/-- mini::selfhost::cons_field -/
theorem lok1357 : LiveOk prims outside liveBad 1357 (src_cons_field 148 156 627 628 1141) := by decide +kernel

/-- mini::selfhost::cons_variant_tail -/
theorem lok1358 : LiveOk prims outside liveBad 1358 (src_cons_variant_tail 1141 1533) := by decide +kernel

/-- mini::selfhost::slice_type -/
theorem lok1367 : LiveOk prims outside liveBad 1367 (src_slice_type 217) := by decide +kernel

/-- mini::selfhost::ref_type -/
theorem lok1370 : LiveOk prims outside liveBad 1370 (src_ref_type 217) := by decide +kernel

/-- mini::selfhost::empty<mini::selfhost::SrcExpr> -/
theorem lok1435 : LiveOk prims outside liveBad 1435 (src_empty_of_mini_selfhost_SrcExpr) := by decide +kernel

/-- mini::selfhost::cons<mini::selfhost::SrcExpr> -/
theorem lok1436 : LiveOk prims outside liveBad 1436 (src_cons_of_mini_selfhost_SrcExpr 1576) := by decide +kernel

/-- mini::selfhost::get<mini::selfhost::SrcFunc> -/
theorem lok1439 : LiveOk prims outside liveBad 1439 (src_get_of_mini_selfhost_SrcFunc 56 59 1439) := by decide +kernel

/-- mini::selfhost::unbox<mini::selfhost::List<mini::selfhost::LocalTy>> -/
theorem lok1446 : LiveOk prims outside liveBad 1446 (src_unbox_of_mini_selfhost_List_mini_selfhost_LocalTy 1578) := by decide +kernel

/-- mini::selfhost::flat_payloads -/
theorem lok1458 : LiveOk prims outside liveBad 1458 (src_flat_payloads 1589) := by decide +kernel

/-- mini::selfhost::t_lbrace -/
theorem lok1532 : LiveOk prims outside liveBad 1532 (src_t_lbrace) := by decide +kernel

/-- mini::selfhost::cons<mini::selfhost::List<mini::selfhost::CTree>> -/
theorem lok1533 : LiveOk prims outside liveBad 1533 (src_cons_of_mini_selfhost_List_mini_selfhost_CTree 1648) := by decide +kernel

/-- mini::selfhost::cons_types -/
theorem lok1540 : LiveOk prims outside liveBad 1540 (src_cons_types 1653) := by decide +kernel

/-- mini::selfhost::cons_type -/
theorem lok1543 : LiveOk prims outside liveBad 1543 (src_cons_type 1658) := by decide +kernel

/-- mini::selfhost::weight_add_to -/
theorem lok1547 : LiveOk prims outside liveBad 1547 (src_weight_add_to 1551) := by decide +kernel

/-- mini::selfhost::weight_sum -/
theorem lok1551 : LiveOk prims outside liveBad 1551 (src_weight_sum 56 75 1661) := by decide +kernel

/-- mini::selfhost::boxed<mini::selfhost::List<mini::selfhost::SrcExpr>> -/
theorem lok1576 : LiveOk prims outside liveBad 1576 (src_boxed_of_mini_selfhost_List_mini_selfhost_SrcExpr 50 515 1668) := by decide +kernel

/-- mini::selfhost::flatten_tys -/
theorem lok1589 : LiveOk prims outside liveBad 1589 (src_flatten_tys 448 672 1541 1589) := by decide +kernel

/-- mini::selfhost::cons_types_tail -/
theorem lok1653 : LiveOk prims outside liveBad 1653 (src_cons_types_tail 1736) := by decide +kernel

/-- mini::selfhost::unbox<mini::selfhost::List<mini::selfhost::List<mini::selfhost::CTree>>> -/
theorem lok1657 : LiveOk prims outside liveBad 1657 (src_unbox_of_mini_selfhost_List_mini_selfhost_List_mini_selfhost_CTree 1733) := by decide +kernel

/-- mini::selfhost::cons_type_tail -/
theorem lok1658 : LiveOk prims outside liveBad 1658 (src_cons_type_tail 240) := by decide +kernel

/-- mini::selfhost::weight_limit -/
theorem lok1661 : LiveOk prims outside liveBad 1661 (src_weight_limit) := by decide +kernel

/-- mini::selfhost::null_at -/
theorem lok1662 : LiveOk prims outside liveBad 1662 (src_null_at) := by decide +kernel

/-- mini::selfhost::p_where_some -/
theorem lok1696 : LiveOk prims outside liveBad 1696 (src_p_where_some) := by decide +kernel

/-- mini::selfhost::lx_line_end -/
theorem lok1718 : LiveOk prims outside liveBad 1718 (src_lx_line_end 75 593 1778) := by decide +kernel

/-- mini::selfhost::t_eqeq -/
theorem lok1721 : LiveOk prims outside liveBad 1721 (src_t_eqeq) := by decide +kernel

/-- mini::selfhost::t_le -/
theorem lok1723 : LiveOk prims outside liveBad 1723 (src_t_le) := by decide +kernel

/-- mini::selfhost::t_ge -/
theorem lok1724 : LiveOk prims outside liveBad 1724 (src_t_ge) := by decide +kernel

/-- mini::selfhost::t_lbracket -/
theorem lok1726 : LiveOk prims outside liveBad 1726 (src_t_lbracket) := by decide +kernel

/-- mini::selfhost::generic_tail -/
theorem lok1731 : LiveOk prims outside liveBad 1731 (src_generic_tail 167 1532 1725 1780 1781) := by decide +kernel

/-- mini::selfhost::cons<mini::selfhost::List<mini::selfhost::SrcType>> -/
theorem lok1736 : LiveOk prims outside liveBad 1736 (src_cons_of_mini_selfhost_List_mini_selfhost_SrcType 1539) := by decide +kernel

/-- mini::selfhost::p_type_param_bound -/
theorem lok1761 : LiveOk prims outside liveBad 1761 (src_p_type_param_bound) := by decide +kernel

/-- mini::selfhost::lx_block -/
theorem lok1779 : LiveOk prims outside liveBad 1779 (src_lx_block 76 1847) := by decide +kernel

/-- mini::selfhost::t_colon -/
theorem lok1780 : LiveOk prims outside liveBad 1780 (src_t_colon) := by decide +kernel

/-- mini::selfhost::starts_with_kind -/
theorem lok1781 : LiveOk prims outside liveBad 1781 (src_starts_with_kind) := by decide +kernel

/-- mini::selfhost::p_cast -/
theorem lok1809 : LiveOk prims outside liveBad 1809 (src_p_cast) := by decide +kernel

/-- mini::selfhost::p_char -/
theorem lok1825 : LiveOk prims outside liveBad 1825 (src_p_char) := by decide +kernel

/-- mini::selfhost::p_bit_or -/
theorem lok1863 : LiveOk prims outside liveBad 1863 (src_p_bit_or) := by decide +kernel

/-- mini::selfhost::p_bit_xor -/
theorem lok1864 : LiveOk prims outside liveBad 1864 (src_p_bit_xor) := by decide +kernel

/-- mini::selfhost::p_bit_and -/
theorem lok1865 : LiveOk prims outside liveBad 1865 (src_p_bit_and) := by decide +kernel

/-- mini::selfhost::p_compare -/
theorem lok1867 : LiveOk prims outside liveBad 1867 (src_p_compare) := by decide +kernel

/-- mini::selfhost::match_init -/
theorem lok1930 : LiveOk prims outside liveBad 1930 (src_match_init 1795 2066) := by decide +kernel

/-- mini::selfhost::p_break_stmt -/
theorem lok1934 : LiveOk prims outside liveBad 1934 (src_p_break_stmt) := by decide +kernel

/-- mini::selfhost::p_continue_stmt -/
theorem lok1935 : LiveOk prims outside liveBad 1935 (src_p_continue_stmt) := by decide +kernel

/-- mini::selfhost::p_while_stmt -/
theorem lok1940 : LiveOk prims outside liveBad 1940 (src_p_while_stmt) := by decide +kernel

/-- ?<mini::selfhost::TraitRef> -/
theorem lok1958 : LiveOk prims outside liveBad 1958 (src_field_args_TraitRef_of_mini_selfhost_TraitRef) := by decide +kernel

/-- mini::selfhost::p_bound_type_ident -/
theorem lok1963 : LiveOk prims outside liveBad 1963 (src_p_bound_type_ident) := by decide +kernel

/-- mini::selfhost::p_bor_tail -/
theorem lok1970 : LiveOk prims outside liveBad 1970 (src_p_bor_tail) := by decide +kernel

/-- mini::selfhost::p_xor_tail -/
theorem lok1971 : LiveOk prims outside liveBad 1971 (src_p_xor_tail) := by decide +kernel

/-- mini::selfhost::p_cast_type_name -/
theorem lok1985 : LiveOk prims outside liveBad 1985 (src_p_cast_type_name) := by decide +kernel

/-- mini::selfhost::p_cast_type_path -/
theorem lok1986 : LiveOk prims outside liveBad 1986 (src_p_cast_type_path) := by decide +kernel

/-- mini::selfhost::p_cast_type_path_ident -/
theorem lok1987 : LiveOk prims outside liveBad 1987 (src_p_cast_type_path_ident) := by decide +kernel

/-- mini::selfhost::p_cast_type_path_end -/
theorem lok1988 : LiveOk prims outside liveBad 1988 (src_p_cast_type_path_end) := by decide +kernel

/-- mini::selfhost::match_stmt_parts -/
theorem lok2052 : LiveOk prims outside liveBad 2052 (src_match_stmt_parts 156 1706 2166) := by decide +kernel

/-- mini::selfhost::stmt_arms -/
theorem lok2053 : LiveOk prims outside liveBad 2053 (src_stmt_arms 155 156 2167) := by decide +kernel

/-- mini::selfhost::match_stmt_value -/
theorem lok2054 : LiveOk prims outside liveBad 2054 (src_match_stmt_value 1241) := by decide +kernel

/-- mini::selfhost::p_bound_type_path_ident -/
theorem lok2091 : LiveOk prims outside liveBad 2091 (src_p_bound_type_path_ident) := by decide +kernel

/-- mini::selfhost::p_bound_type_path_end -/
theorem lok2092 : LiveOk prims outside liveBad 2092 (src_p_bound_type_path_end) := by decide +kernel

/-- mini::selfhost::p_bound_type_path_more -/
theorem lok2093 : LiveOk prims outside liveBad 2093 (src_p_bound_type_path_more) := by decide +kernel

/-- mini::selfhost::get<mini::selfhost::List<mini::selfhost::Ty>> -/
theorem lok2134 : LiveOk prims outside liveBad 2134 (src_get_of_mini_selfhost_List_mini_selfhost_Ty 56 1541 2134) := by decide +kernel

/-- mini::selfhost::get<mini::selfhost::List<mini::selfhost::CTree>> -/
theorem lok2136 : LiveOk prims outside liveBad 2136 (src_get_of_mini_selfhost_List_mini_selfhost_CTree 56 1657 2136) := by decide +kernel

/-- mini::selfhost::some_block_arm -/
theorem lok2164 : LiveOk prims outside liveBad 2164 (src_some_block_arm 103 2164 2287) := by decide +kernel

/-- mini::selfhost::value_arms -/
theorem lok2165 : LiveOk prims outside liveBad 2165 (src_value_arms 75 103 2165 2287 2288) := by decide +kernel

/-- mini::selfhost::match_stmt_on -/
theorem lok2166 : LiveOk prims outside liveBad 2166 (src_match_stmt_on 163 1185 1393 2034 2035 2289) := by decide +kernel

/-- mini::selfhost::arm_block_list -/
theorem lok2286 : LiveOk prims outside liveBad 2286 (src_arm_block_list 156 1795 2419) := by decide +kernel

/-- mini::selfhost::is_block_arm -/
theorem lok2287 : LiveOk prims outside liveBad 2287 (src_is_block_arm 2286) := by decide +kernel

/-- mini::selfhost::if_one -/
theorem lok2288 : LiveOk prims outside liveBad 2288 (src_if_one) := by decide +kernel

/-- mini::selfhost::match_stmt_enum -/
theorem lok2289 : LiveOk prims outside liveBad 2289 (src_match_stmt_enum 56 628 1233 2154 2420) := by decide +kernel

/-- mini::selfhost::arm_binding -/
theorem lok2292 : LiveOk prims outside liveBad 2292 (src_arm_binding 139 153 155 156 429 2425 2426 2427 2428) := by decide +kernel

/-- mini::selfhost::arm_stmt -/
theorem lok2293 : LiveOk prims outside liveBad 2293 (src_arm_stmt 2429) := by decide +kernel

/-- mini::selfhost::bound_scope -/
theorem lok2294 : LiveOk prims outside liveBad 2294 (src_bound_scope) := by decide +kernel

/-- mini::selfhost::cons<bool> -/
theorem lok2365 : LiveOk prims outside liveBad 2365 (src_cons_of_bool 2383) := by decide +kernel

/-- mini::selfhost::ret_binds -/
theorem lok2400 : LiveOk prims outside liveBad 2400 (src_ret_binds 1954 2403 2409) := by decide +kernel

/-- mini::selfhost::arm_block_of -/
theorem lok2419 : LiveOk prims outside liveBad 2419 (src_arm_block_of 153 156 1798 2507) := by decide +kernel

/-- mini::selfhost::match_stmt_head -/
theorem lok2420 : LiveOk prims outside liveBad 2420 (src_match_stmt_head 1595 2255 2508) := by decide +kernel

/-- mini::selfhost::arm_binder -/
theorem lok2429 : LiveOk prims outside liveBad 2429 (src_arm_binder 76 1241) := by decide +kernel

/-- mini::selfhost::local_id_of -/
theorem lok2431 : LiveOk prims outside liveBad 2431 (src_local_id_of) := by decide +kernel

/-- mini::selfhost::local_ty_of -/
theorem lok2432 : LiveOk prims outside liveBad 2432 (src_local_ty_of) := by decide +kernel

/-- mini::selfhost::cons<mini::selfhost::Bind> -/
theorem lok2466 : LiveOk prims outside liveBad 2466 (src_cons_of_mini_selfhost_Bind 2524) := by decide +kernel

/-- mini::selfhost::arg_expected -/
theorem lok2490 : LiveOk prims outside liveBad 2490 (src_arg_expected 1468 1484 2085) := by decide +kernel

/-- mini::selfhost::bind_arg -/
theorem lok2494 : LiveOk prims outside liveBad 2494 (src_bind_arg 1954 2034 2147 2403) := by decide +kernel

/-- mini::selfhost::match_stmt_if -/
theorem lok2508 : LiveOk prims outside liveBad 2508 (src_match_stmt_if) := by decide +kernel

/-- mini::selfhost::boxed<mini::selfhost::List<mini::selfhost::Bind>> -/
theorem lok2524 : LiveOk prims outside liveBad 2524 (src_boxed_of_mini_selfhost_List_mini_selfhost_Bind 50 2469 2567) := by decide +kernel

end Lanius.Faithful.SelfPure
