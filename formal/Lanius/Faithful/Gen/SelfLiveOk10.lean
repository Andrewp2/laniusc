module

public import Lanius.Faithful.Gen.SelfPureTab
public import Lanius.Faithful.Gen.SelfLiveTab
public import Lanius.Faithful.Gen.SelfSrc3
public import Lanius.Faithful.Gen.SelfSrcC_Expr_agrees
public import Lanius.Faithful.Gen.SelfSrcC_Lists_empty
public import Lanius.Faithful.Gen.SelfSrcC_UintTy_isWide
public import Lanius.Faithful.Gen.SelfSrcC_evalHost
public import Lanius.Faithful.Gen.SelfSrcC_optimizeIte
public import Lanius.Faithful.Gen.SelfSrcF_Inline_pElseStmt
public import Lanius.Faithful.Gen.SelfSrcF_Inline_tLparen
public import Lanius.Faithful.Gen.SelfSrcF_eStructClosed
public import Lanius.Faithful.Gen.SelfSrcF_funcsBytes
public import Lanius.Faithful.Gen.SelfSrcF_hasKids
public import Lanius.Faithful.Gen.SelfSrcF_lxExponent
public import Lanius.Faithful.Gen.SelfSrcF_noBlock
public import Lanius.Faithful.Gen.SelfSrcF_stringLast
import all Lanius.Faithful.Gen.SelfLiveTab
import all Lanius.Faithful.Gen.SelfPureTab
import all Lanius.Faithful.Gen.SelfSrc3
import all Lanius.Faithful.Gen.SelfSrcC_Expr_agrees
import all Lanius.Faithful.Gen.SelfSrcC_Lists_empty
import all Lanius.Faithful.Gen.SelfSrcC_UintTy_isWide
import all Lanius.Faithful.Gen.SelfSrcC_evalHost
import all Lanius.Faithful.Gen.SelfSrcC_optimizeIte
import all Lanius.Faithful.Gen.SelfSrcF_Inline_pElseStmt
import all Lanius.Faithful.Gen.SelfSrcF_Inline_tLparen
import all Lanius.Faithful.Gen.SelfSrcF_eStructClosed
import all Lanius.Faithful.Gen.SelfSrcF_funcsBytes
import all Lanius.Faithful.Gen.SelfSrcF_hasKids
import all Lanius.Faithful.Gen.SelfSrcF_lxExponent
import all Lanius.Faithful.Gen.SelfSrcF_noBlock
import all Lanius.Faithful.Gen.SelfSrcF_stringLast
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

/-- mini::selfhost::cons<mini::selfhost::Sym> -/
theorem lok46 : LiveOk prims outside liveBad 46 (src_cons_of_mini_selfhost_Sym 74) := by decide +kernel

/-- mini::selfhost::empty<mini::selfhost::Sym> -/
theorem lok47 : LiveOk prims outside liveBad 47 (src_empty_of_mini_selfhost_Sym) := by decide +kernel

/-- mini::selfhost::empty<mini::selfhost::SrcStructDecl> -/
theorem lok64 : LiveOk prims outside liveBad 64 (src_empty_of_mini_selfhost_SrcStructDecl) := by decide +kernel

/-- mini::selfhost::empty<mini::selfhost::SrcEnumDecl> -/
theorem lok65 : LiveOk prims outside liveBad 65 (src_empty_of_mini_selfhost_SrcEnumDecl) := by decide +kernel

/-- mini::selfhost::empty<mini::selfhost::CTree> -/
theorem lok96 : LiveOk prims outside liveBad 96 (src_empty_of_mini_selfhost_CTree) := by decide +kernel

/-- mini::selfhost::single<mini::selfhost::List<mini::selfhost::List<usize>>> -/
theorem lok104 : LiveOk prims outside liveBad 104 (src_single_of_mini_selfhost_List_mini_selfhost_List_usize 166) := by decide +kernel

/-- mini::selfhost::optimize_program -/
theorem lok113 : LiveOk prims outside liveBad 113 (src_optimize_program 168) := by decide +kernel

/-- mini::selfhost::single<mini::selfhost::Sym> -/
theorem lok150 : LiveOk prims outside liveBad 150 (src_single_of_mini_selfhost_Sym 74) := by decide +kernel

/-- mini::selfhost::list_items -/
theorem lok155 : LiveOk prims outside liveBad 155 (src_list_items 56 259 260) := by decide +kernel

/-- mini::selfhost::optimize_funcs -/
theorem lok168 : LiveOk prims outside liveBad 168 (src_optimize_funcs 84 117 168 281 282 283) := by decide +kernel

/-- mini::selfhost::unbox<mini::selfhost::List<mini::selfhost::List<mini::selfhost::SrcType>>> -/
theorem lok183 : LiveOk prims outside liveBad 183 (src_unbox_of_mini_selfhost_List_mini_selfhost_List_mini_selfhost_SrcType 304) := by decide +kernel

/-- mini::selfhost::boxed<mini::selfhost::List<mini::selfhost::CTree>> -/
theorem lok254 : LiveOk prims outside liveBad 254 (src_boxed_of_mini_selfhost_List_mini_selfhost_CTree 50 165 419) := by decide +kernel

/-- mini::selfhost::items_in -/
theorem lok259 : LiveOk prims outside liveBad 259 (src_items_in 56 96 103 424) := by decide +kernel

/-- mini::selfhost::optimize -/
theorem lok281 : LiveOk prims outside liveBad 281 (src_Stmt_optimize 281 282 307 462 463 464 465 466 467 468 469) := by decide +kernel

/-- mini::selfhost::length<u8> -/
theorem lok291 : LiveOk prims outside liveBad 291 (src_length_of_u8 75 78 291) := by decide +kernel

/-- mini::selfhost::boxed<mini::selfhost::Expr> -/
theorem lok337 : LiveOk prims outside liveBad 337 (src_boxed_of_mini_selfhost_Expr 50 522 523) := by decide +kernel

/-- mini::selfhost::eval_call -/
theorem lok354 : LiveOk prims outside liveBad 354 (src_eval_call 543 544) := by decide +kernel

/-- mini::selfhost::length<mini::selfhost::List<usize>> -/
theorem lok368 : LiveOk prims outside liveBad 368 (src_length_of_mini_selfhost_List_usize 75 368 558) := by decide +kernel

/-- mini::selfhost::single<mini::selfhost::SrcType> -/
theorem lok377 : LiveOk prims outside liveBad 377 (src_single_of_mini_selfhost_SrcType 402) := by decide +kernel

/-- mini::selfhost::items_cons -/
theorem lok424 : LiveOk prims outside liveBad 424 (src_items_cons 56 153 155 259 604 605 606 607) := by decide +kernel

/-- mini::selfhost::get<mini::selfhost::Inst> -/
theorem lok442 : LiveOk prims outside liveBad 442 (src_get_of_mini_selfhost_Inst 56 442 671) := by decide +kernel

/-- mini::selfhost::cons<mini::selfhost::Inst> -/
theorem lok447 : LiveOk prims outside liveBad 447 (src_cons_of_mini_selfhost_Inst 684) := by decide +kernel

/-- mini::selfhost::concat<mini::selfhost::ImplDecl> -/
theorem lok458 : LiveOk prims outside liveBad 458 (src_concat_of_mini_selfhost_ImplDecl 458 692 693) := by decide +kernel

/-- mini::selfhost::concat<mini::selfhost::List<mini::selfhost::List<usize>>> -/
theorem lok460 : LiveOk prims outside liveBad 460 (src_concat_of_mini_selfhost_List_mini_selfhost_List_usize 166 460 651) := by decide +kernel

/-- ?<mini::selfhost::Decls> -/
theorem lok461 : LiveOk prims outside liveBad 461 (src_field_homes_Decls_of_mini_selfhost_Decls) := by decide +kernel

/-- mini::selfhost::optimize_ite -/
theorem lok466 : LiveOk prims outside liveBad 466 (src_optimize_ite 702 703 704) := by decide +kernel

/-- mini::selfhost::optimize_loop -/
theorem lok467 : LiveOk prims outside liveBad 467 (src_optimize_loop 188 702 705) := by decide +kernel

/-- mini::selfhost::unbox<mini::selfhost::Expr> -/
theorem lok492 : LiveOk prims outside liveBad 492 (src_unbox_of_mini_selfhost_Expr 523) := by decide +kernel

/-- mini::selfhost::eval_host -/
theorem lok544 : LiveOk prims outside liveBad 544 (src_eval_host 188 240 377 388 789 790 791 792 793 794 795) := by decide +kernel

/-- mini::selfhost::unbox<mini::selfhost::List<u64>> -/
theorem lok575 : LiveOk prims outside liveBad 575 (src_unbox_of_mini_selfhost_List_u64 823) := by decide +kernel

/-- mini::selfhost::unbox<mini::selfhost::List<mini::selfhost::SrcEnumDecl>> -/
theorem lok588 : LiveOk prims outside liveBad 588 (src_unbox_of_mini_selfhost_List_mini_selfhost_SrcEnumDecl 829) := by decide +kernel

/-- mini::selfhost::is_link -/
theorem lok604 : LiveOk prims outside liveBad 604 (src_is_link 847 848 849 850 851 852 853 854 855 856 857 858 859 860 861 862 863 864 865 866 867 868 869 870 871 872 873 874 875 876 877 878 879 880 881 882 883 884 885 886 887 888 889 890 891 892 893 894 895 896 897 898 899 900 901 902 903 904 905 906 907 908 909 910 911 912 913 914 915 916 917 918) := by decide +kernel

/-- mini::selfhost::join_items -/
theorem lok605 : LiveOk prims outside liveBad 605 (src_join_items 919) := by decide +kernel

/-- mini::selfhost::has_kids -/
theorem lok606 : LiveOk prims outside liveBad 606 (src_has_kids 260) := by decide +kernel

/-- mini::selfhost::empty<mini::selfhost::ImplDecl> -/
theorem lok613 : LiveOk prims outside liveBad 613 (src_empty_of_mini_selfhost_ImplDecl) := by decide +kernel

/-- mini::selfhost::empty<mini::selfhost::List<mini::selfhost::List<usize>>> -/
theorem lok614 : LiveOk prims outside liveBad 614 (src_empty_of_mini_selfhost_List_mini_selfhost_List_usize) := by decide +kernel

/-- mini::selfhost::p_enum -/
theorem lok617 : LiveOk prims outside liveBad 617 (src_p_enum) := by decide +kernel

/-- ?<mini::selfhost::Token> -/
theorem lok627 : LiveOk prims outside liveBad 627 (src_field_text_Token_of_mini_selfhost_Token) := by decide +kernel

/-- mini::selfhost::kid_token -/
theorem lok628 : LiveOk prims outside liveBad 628 (src_kid_token 156 926) := by decide +kernel

/-- mini::selfhost::concat<mini::selfhost::Ty> -/
theorem lok672 : LiveOk prims outside liveBad 672 (src_concat_of_mini_selfhost_Ty 666 670 672) := by decide +kernel

/-- mini::selfhost::boxed<mini::selfhost::List<mini::selfhost::Inst>> -/
theorem lok684 : LiveOk prims outside liveBad 684 (src_boxed_of_mini_selfhost_List_mini_selfhost_Inst 50 981 1001) := by decide +kernel

/-- mini::selfhost::dead_before -/
theorem lok700 : LiveOk prims outside liveBad 700 (src_Stmt_dead_before 1020) := by decide +kernel

/-- mini::selfhost::loop_unless_zero -/
theorem lok705 : LiveOk prims outside liveBad 705 (src_loop_unless_zero 188) := by decide +kernel

/-- mini::selfhost::boxed<mini::selfhost::List<u64>> -/
theorem lok824 : LiveOk prims outside liveBad 824 (src_boxed_of_mini_selfhost_List_u64 50 823 1095) := by decide +kernel

/-- mini::selfhost::boxed<mini::selfhost::List<mini::selfhost::SrcStructDecl>> -/
theorem lok826 : LiveOk prims outside liveBad 826 (src_boxed_of_mini_selfhost_List_mini_selfhost_SrcStructDecl 50 827 1097) := by decide +kernel

/-- mini::selfhost::join_second -/
theorem lok919 : LiveOk prims outside liveBad 919 (src_join_second 1120) := by decide +kernel

/-- mini::selfhost::leaf_token -/
theorem lok926 : LiveOk prims outside liveBad 926 (src_leaf_token 262) := by decide +kernel

/-- mini::selfhost::same_text -/
theorem lok934 : LiveOk prims outside liveBad 934 (src_same_text 76 934) := by decide +kernel

/-- mini::selfhost::empty<core::option::Option<mini::selfhost::SrcType>> -/
theorem lok958 : LiveOk prims outside liveBad 958 (src_empty_of_core_option_Option_mini_selfhost_SrcType) := by decide +kernel

/-- mini::selfhost::place_funcs -/
theorem lok963 : LiveOk prims outside liveBad 963 (src_place_funcs 59 754 952 963 965 1197 1198) := by decide +kernel

/-- mini::selfhost::placed_program -/
theorem lok964 : LiveOk prims outside liveBad 964 (src_placed_program 110 963 1199) := by decide +kernel

/-- mini::selfhost::unbox<mini::selfhost::List<mini::selfhost::MParam>> -/
theorem lok982 : LiveOk prims outside liveBad 982 (src_unbox_of_mini_selfhost_List_mini_selfhost_MParam 1224) := by decide +kernel

/-- mini::selfhost::agrees -/
theorem lok1021 : LiveOk prims outside liveBad 1021 (src_Expr_agrees 492 694 712 1271 1272 1273 1274 1275 1276) := by decide +kernel

/-- mini::selfhost::args_agree -/
theorem lok1026 : LiveOk prims outside liveBad 1026 (src_args_agree 493 1021 1026) := by decide +kernel

/-- mini::selfhost::bytes -/
theorem lok1027 : LiveOk prims outside liveBad 1027 (src_MemWidth_bytes) := by decide +kernel

/-- mini::selfhost::size -/
theorem lok1036 : LiveOk prims outside liveBad 1036 (src_BinOp_size) := by decide +kernel

/-- mini::selfhost::prefix -/
theorem lok1037 : LiveOk prims outside liveBad 1037 (src_Word_prefix) := by decide +kernel

/-- mini::selfhost::prefix -/
theorem lok1038 : LiveOk prims outside liveBad 1038 (src_MemWidth_prefix) := by decide +kernel

/-- mini::selfhost::is_wide -/
theorem lok1083 : LiveOk prims outside liveBad 1083 (src_UintTy_is_wide) := by decide +kernel

/-- mini::selfhost::lx_number -/
theorem lok1103 : LiveOk prims outside liveBad 1103 (src_lx_number 75 1337 1338 1339) := by decide +kernel

/-- mini::selfhost::cons<mini::selfhost::List<usize>> -/
theorem lok1141 : LiveOk prims outside liveBad 1141 (src_cons_of_mini_selfhost_List_usize 937) := by decide +kernel

/-- mini::selfhost::let_eval_closed -/
theorem lok1169 : LiveOk prims outside liveBad 1169 (src_let_eval_closed 1202) := by decide +kernel

/-- mini::selfhost::close_eff -/
theorem lok1170 : LiveOk prims outside liveBad 1170 (src_close_eff 1152 1156 1170 1228 1229 1372 1373 1374 1375 1376 1377 1378 1379 1380 1381 1382 1383 1384 1385 1386 1387 1388) := by decide +kernel

/-- mini::selfhost::boxed<mini::selfhost::List<core::option::Option<mini::selfhost::SrcType>>> -/
theorem lok1184 : LiveOk prims outside liveBad 1184 (src_boxed_of_mini_selfhost_List_core_option_Option_mini_selfhost_SrcType 50 1389 1390) := by decide +kernel

/-- mini::selfhost::funcs_bytes -/
theorem lok1199 : LiveOk prims outside liveBad 1199 (src_funcs_bytes 59 110 754 1198 1199) := by decide +kernel

/-- mini::selfhost::boxed<mini::selfhost::List<core::option::Option<usize>>> -/
theorem lok1220 : LiveOk prims outside liveBad 1220 (src_boxed_of_mini_selfhost_List_core_option_Option_usize 50 1217 1455) := by decide +kernel

/-- mini::selfhost::lx_prefixed_base -/
theorem lok1337 : LiveOk prims outside liveBad 1337 (src_lx_prefixed_base 75 830 1523 1524) := by decide +kernel

/-- mini::selfhost::lx_finish_decimal -/
theorem lok1339 : LiveOk prims outside liveBad 1339 (src_lx_finish_decimal 830 1526) := by decide +kernel

/-- mini::selfhost::unbox<mini::selfhost::List<mini::selfhost::SymRule>> -/
theorem lok1347 : LiveOk prims outside liveBad 1347 (src_unbox_of_mini_selfhost_List_mini_selfhost_SymRule 1112) := by decide +kernel

/-- mini::selfhost::close_effs -/
theorem lok1373 : LiveOk prims outside liveBad 1373 (src_close_effs 1170 1228 1373 1537 1538) := by decide +kernel

/-- mini::selfhost::e_struct_closed -/
theorem lok1379 : LiveOk prims outside liveBad 1379 (src_e_struct_closed 1447) := by decide +kernel

/-- mini::selfhost::e_variant_closed -/
theorem lok1380 : LiveOk prims outside liveBad 1380 (src_e_variant_closed 1447) := by decide +kernel

/-- mini::selfhost::e_match_closed -/
theorem lok1381 : LiveOk prims outside liveBad 1381 (src_e_match_closed 1447 1449) := by decide +kernel

/-- mini::selfhost::e_if_closed -/
theorem lok1384 : LiveOk prims outside liveBad 1384 (src_e_if_closed 1449) := by decide +kernel

/-- mini::selfhost::e_let_closed -/
theorem lok1385 : LiveOk prims outside liveBad 1385 (src_e_let_closed 1449) := by decide +kernel

/-- mini::selfhost::boxed<mini::selfhost::SrcEff> -/
theorem lok1449 : LiveOk prims outside liveBad 1449 (src_boxed_of_mini_selfhost_SrcEff 50 549 1581) := by decide +kernel

/-- mini::selfhost::empty<mini::selfhost::MParam> -/
theorem lok1462 : LiveOk prims outside liveBad 1462 (src_empty_of_mini_selfhost_MParam) := by decide +kernel

/-- mini::selfhost::rex -/
theorem lok1504 : LiveOk prims outside liveBad 1504 (src_MemWidth_rex 110 1043) := by decide +kernel

/-- mini::selfhost::lx_base_of -/
theorem lok1524 : LiveOk prims outside liveBad 1524 (src_lx_base_of) := by decide +kernel

/-- mini::selfhost::t_lt -/
theorem lok1530 : LiveOk prims outside liveBad 1530 (src_t_lt) := by decide +kernel

/-- mini::selfhost::get<core::option::Option<mini::selfhost::SrcType>> -/
theorem lok1535 : LiveOk prims outside liveBad 1535 (src_get_of_core_option_Option_mini_selfhost_SrcType 56 1535 1650) := by decide +kernel

/-- mini::selfhost::cons_src_eff -/
theorem lok1538 : LiveOk prims outside liveBad 1538 (src_cons_src_eff 1580) := by decide +kernel

/-- mini::selfhost::boxed<mini::selfhost::List<mini::selfhost::SrcArm>> -/
theorem lok1577 : LiveOk prims outside liveBad 1577 (src_boxed_of_mini_selfhost_List_mini_selfhost_SrcArm 50 1324 1669) := by decide +kernel

/-- mini::selfhost::lx_exponent -/
theorem lok1642 : LiveOk prims outside liveBad 1642 (src_lx_exponent 1338 1714) := by decide +kernel

/-- mini::selfhost::lx_fraction -/
theorem lok1643 : LiveOk prims outside liveBad 1643 (src_lx_fraction 830 1715) := by decide +kernel

/-- mini::selfhost::boxed<mini::selfhost::List<mini::selfhost::List<mini::selfhost::CTree>>> -/
theorem lok1648 : LiveOk prims outside liveBad 1648 (src_boxed_of_mini_selfhost_List_mini_selfhost_List_mini_selfhost_CTree 50 1732 1733) := by decide +kernel

/-- mini::selfhost::cons<mini::selfhost::MParam> -/
theorem lok1678 : LiveOk prims outside liveBad 1678 (src_cons_of_mini_selfhost_MParam 1250) := by decide +kernel

/-- mini::selfhost::empty<mini::selfhost::BoundGoal> -/
theorem lok1694 : LiveOk prims outside liveBad 1694 (src_empty_of_mini_selfhost_BoundGoal) := by decide +kernel

/-- mini::selfhost::has_ty -/
theorem lok1698 : LiveOk prims outside liveBad 1698 (src_has_ty) := by decide +kernel

/-- mini::selfhost::lx_fraction_digits -/
theorem lok1716 : LiveOk prims outside liveBad 1716 (src_lx_fraction_digits 1775) := by decide +kernel

/-- mini::selfhost::t_oror -/
theorem lok1720 : LiveOk prims outside liveBad 1720 (src_t_oror) := by decide +kernel

/-- mini::selfhost::t_not_equal -/
theorem lok1722 : LiveOk prims outside liveBad 1722 (src_t_not_equal) := by decide +kernel

/-- mini::selfhost::t_lparen -/
theorem lok1725 : LiveOk prims outside liveBad 1725 (src_t_lparen) := by decide +kernel

/-- mini::selfhost::t_rbracket -/
theorem lok1728 : LiveOk prims outside liveBad 1728 (src_t_rbracket) := by decide +kernel

/-- mini::selfhost::t_rbrace -/
theorem lok1729 : LiveOk prims outside liveBad 1729 (src_t_rbrace) := by decide +kernel

/-- mini::selfhost::lx_after_fraction -/
theorem lok1775 : LiveOk prims outside liveBad 1775 (src_lx_after_fraction 830 1845) := by decide +kernel

/-- mini::selfhost::boxed<mini::selfhost::List<mini::selfhost::BoundGoal>> -/
theorem lok1793 : LiveOk prims outside liveBad 1793 (src_boxed_of_mini_selfhost_List_mini_selfhost_BoundGoal 50 1759 1855) := by decide +kernel

/-- mini::selfhost::empty<bool> -/
theorem lok1883 : LiveOk prims outside liveBad 1883 (src_empty_of_bool) := by decide +kernel

/-- mini::selfhost::checked_eff -/
theorem lok1897 : LiveOk prims outside liveBad 1897 (src_checked_eff) := by decide +kernel

/-- mini::selfhost::has_local -/
theorem lok1898 : LiveOk prims outside liveBad 1898 (src_has_local) := by decide +kernel

/-- mini::selfhost::is_str_let -/
theorem lok1912 : LiveOk prims outside liveBad 1912 (src_is_str_let 56 153 156 628 1142 1595 1914 1915 2046) := by decide +kernel

/-- mini::selfhost::string_let -/
theorem lok1913 : LiveOk prims outside liveBad 1913 (src_string_let 2047 2048) := by decide +kernel

/-- mini::selfhost::let_of -/
theorem lok1924 : LiveOk prims outside liveBad 1924 (src_let_of 1927) := by decide +kernel

/-- mini::selfhost::let_body -/
theorem lok1927 : LiveOk prims outside liveBad 1927 (src_let_body 2065) := by decide +kernel

/-- mini::selfhost::return_or_eval -/
theorem lok1932 : LiveOk prims outside liveBad 1932 (src_return_or_eval 1706 2070 2071) := by decide +kernel

/-- mini::selfhost::p_else_stmt -/
theorem lok1937 : LiveOk prims outside liveBad 1937 (src_p_else_stmt) := by decide +kernel

/-- mini::selfhost::if_or_eval -/
theorem lok1938 : LiveOk prims outside liveBad 1938 (src_if_or_eval 1706 2072) := by decide +kernel

/-- mini::selfhost::has_tys -/
theorem lok2022 : LiveOk prims outside liveBad 2022 (src_has_tys) := by decide +kernel

/-- mini::selfhost::string_last -/
theorem lok2048 : LiveOk prims outside liveBad 2048 (src_string_last 103 2161) := by decide +kernel

/-- mini::selfhost::let_head -/
theorem lok2059 : LiveOk prims outside liveBad 2059 (src_let_head 1795 2173) := by decide +kernel

/-- mini::selfhost::let_stmt -/
theorem lok2065 : LiveOk prims outside liveBad 2065 (src_let_stmt 1241 1671 2083 2179 2180 2181 2182) := by decide +kernel

/-- mini::selfhost::return_slice -/
theorem lok2070 : LiveOk prims outside liveBad 2070 (src_return_slice 56 2059 2083 2100 2186) := by decide +kernel

/-- mini::selfhost::return_eval_of -/
theorem lok2071 : LiveOk prims outside liveBad 2071 (src_return_eval_of 2187) := by decide +kernel

/-- mini::selfhost::if_eval_of -/
theorem lok2072 : LiveOk prims outside liveBad 2072 (src_if_eval_of 2188) := by decide +kernel

/-- mini::selfhost::same_decl_args -/
theorem lok2133 : LiveOk prims outside liveBad 2133 (src_same_decl_args) := by decide +kernel

/-- mini::selfhost::empty<mini::selfhost::VariantAt> -/
theorem lok2141 : LiveOk prims outside liveBad 2141 (src_empty_of_mini_selfhost_VariantAt) := by decide +kernel

/-- mini::selfhost::stmt_arm_order -/
theorem lok2167 : LiveOk prims outside liveBad 2167 (src_stmt_arm_order 2290 2291) := by decide +kernel

/-- mini::selfhost::postfix_head -/
theorem lok2173 : LiveOk prims outside liveBad 2173 (src_postfix_head 156 1889 2299) := by decide +kernel

/-- mini::selfhost::alloc_let -/
theorem lok2179 : LiveOk prims outside liveBad 2179 (src_alloc_let 1241) := by decide +kernel

/-- mini::selfhost::slice_let -/
theorem lok2181 : LiveOk prims outside liveBad 2181 (src_slice_let 1241) := by decide +kernel

/-- mini::selfhost::slice_returned -/
theorem lok2186 : LiveOk prims outside liveBad 2186 (src_slice_returned 1241) := by decide +kernel

/-- mini::selfhost::boxed<mini::selfhost::List<mini::selfhost::VariantAt>> -/
theorem lok2260 : LiveOk prims outside liveBad 2260 (src_boxed_of_mini_selfhost_List_mini_selfhost_VariantAt 50 2261 2408) := by decide +kernel

/-- mini::selfhost::match_order -/
theorem lok2273 : LiveOk prims outside liveBad 2273 (src_match_order 2290 2411) := by decide +kernel

/-- mini::selfhost::stmt_order_by -/
theorem lok2291 : LiveOk prims outside liveBad 2291 (src_stmt_order_by 2423 2424) := by decide +kernel

/-- mini::selfhost::checked_stmt -/
theorem lok2326 : LiveOk prims outside liveBad 2326 (src_checked_stmt) := by decide +kernel

/-- mini::selfhost::checked_effs -/
theorem lok2391 : LiveOk prims outside liveBad 2391 (src_checked_effs) := by decide +kernel

/-- mini::selfhost::order_by -/
theorem lok2411 : LiveOk prims outside liveBad 2411 (src_order_by 2424 2497) := by decide +kernel

/-- mini::selfhost::nested_checked -/
theorem lok2423 : LiveOk prims outside liveBad 2423 (src_nested_checked 2510 2511) := by decide +kernel

/-- mini::selfhost::checked_bound -/
theorem lok2489 : LiveOk prims outside liveBad 2489 (src_checked_bound) := by decide +kernel

/-- mini::selfhost::nested_order -/
theorem lok2497 : LiveOk prims outside liveBad 2497 (src_nested_order 2423 2535) := by decide +kernel

/-- mini::selfhost::no_block -/
theorem lok2535 : LiveOk prims outside liveBad 2535 (src_no_block 103 156 1700 2535 2576 2577) := by decide +kernel

end Lanius.Faithful.SelfPure
