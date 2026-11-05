module

public import Lanius.Faithful.Gen.SelfPureTab
public import Lanius.Faithful.Gen.SelfLiveTab
public import Lanius.Faithful.Gen.SelfSrcC_Inline_factOr
public import Lanius.Faithful.Gen.SelfSrcC_equality
public import Lanius.Faithful.Gen.SelfSrcC_optimizeLeft
public import Lanius.Faithful.Gen.SelfSrcC_repeatType
public import Lanius.Faithful.Gen.SelfSrcF_Inline_pTypePathIdent
public import Lanius.Faithful.Gen.SelfSrcF_externBody
public import Lanius.Faithful.Gen.SelfSrcF_flLog2Or0
public import Lanius.Faithful.Gen.SelfSrcF_matchLetHead
public import Lanius.Faithful.Gen.SelfSrcF_methodDecl
public import Lanius.Faithful.Gen.SelfSrcF_setEvalClosed
public import Lanius.Faithful.Gen.SelfSrcF_shrFirst
import all Lanius.Faithful.Gen.SelfLiveTab
import all Lanius.Faithful.Gen.SelfPureTab
import all Lanius.Faithful.Gen.SelfSrcC_Inline_factOr
import all Lanius.Faithful.Gen.SelfSrcC_equality
import all Lanius.Faithful.Gen.SelfSrcC_optimizeLeft
import all Lanius.Faithful.Gen.SelfSrcC_repeatType
import all Lanius.Faithful.Gen.SelfSrcF_Inline_pTypePathIdent
import all Lanius.Faithful.Gen.SelfSrcF_externBody
import all Lanius.Faithful.Gen.SelfSrcF_flLog2Or0
import all Lanius.Faithful.Gen.SelfSrcF_matchLetHead
import all Lanius.Faithful.Gen.SelfSrcF_methodDecl
import all Lanius.Faithful.Gen.SelfSrcF_setEvalClosed
import all Lanius.Faithful.Gen.SelfSrcF_shrFirst
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

/-- mini::selfhost::attach -/
theorem lok149 : LiveOk prims outside liveBad 149 (src_attach 56 96 255 256) := by decide +kernel

/-- mini::selfhost::lower_value -/
theorem lok193 : LiveOk prims outside liveBad 193 (src_lower_value 207 317 318 319) := by decide +kernel

/-- mini::selfhost::lower_literal -/
theorem lok196 : LiveOk prims outside liveBad 196 (src_lower_literal 181 184 322 323) := by decide +kernel

/-- mini::selfhost::only -/
theorem lok258 : LiveOk prims outside liveBad 258 (src_only) := by decide +kernel

/-- mini::selfhost::lower_single -/
theorem lok318 : LiveOk prims outside liveBad 318 (src_lower_single 189) := by decide +kernel

/-- mini::selfhost::lower_copy -/
theorem lok319 : LiveOk prims outside liveBad 319 (src_lower_copy 202 511 512) := by decide +kernel

/-- mini::selfhost::lower_struct_fields -/
theorem lok322 : LiveOk prims outside liveBad 322 (src_lower_struct_fields 180 516) := by decide +kernel

/-- mini::selfhost::repeat_type -/
theorem lok323 : LiveOk prims outside liveBad 323 (src_repeat_type 56 239 240 323) := by decide +kernel

/-- mini::selfhost::collect_front -/
theorem lok426 : LiveOk prims outside liveBad 426 (src_collect_front 615) := by decide +kernel

/-- mini::selfhost::item_decls -/
theorem lok427 : LiveOk prims outside liveBad 427 (src_item_decls 153 156 265 267 425 428 429 608 609 611 612 613 614 616 617 618 619 620 621 622 623 624 625 626 627 628 629 630 631 632 633 634 635 636 637 638 639 640 641 642 643 644) := by decide +kernel

/-- mini::selfhost::optimize_assign -/
theorem lok462 : LiveOk prims outside liveBad 462 (src_optimize_assign 694) := by decide +kernel

/-- mini::selfhost::optimize -/
theorem lok463 : LiveOk prims outside liveBad 463 (src_Expr_optimize 337 463 492 695 696 697) := by decide +kernel

/-- mini::selfhost::optimize_sequence -/
theorem lok465 : LiveOk prims outside liveBad 465 (src_optimize_sequence 281 699 700 701) := by decide +kernel

/-- mini::selfhost::optimize_all -/
theorem lok468 : LiveOk prims outside liveBad 468 (src_optimize_all 463 468 493 541 542) := by decide +kernel

/-- mini::selfhost::copy_binding -/
theorem lok511 : LiveOk prims outside liveBad 511 (src_copy_binding 766) := by decide +kernel

/-- mini::selfhost::copy_field -/
theorem lok512 : LiveOk prims outside liveBad 512 (src_copy_field 767) := by decide +kernel

/-- mini::selfhost::lower_args -/
theorem lok516 : LiveOk prims outside liveBad 516 (src_lower_args 181 193 321 516 541 768) := by decide +kernel

/-- mini::selfhost::lower_variant -/
theorem lok517 : LiveOk prims outside liveBad 517 (src_lower_variant 516 769) := by decide +kernel

/-- mini::selfhost::type_decls -/
theorem lok618 : LiveOk prims outside liveBad 618 (src_type_decls 609 610 611 612 613 614 920) := by decide +kernel

/-- mini::selfhost::fns_decls -/
theorem lok621 : LiveOk prims outside liveBad 621 (src_fns_decls 608 610 611 612 613 614) := by decide +kernel

/-- mini::selfhost::impl_methods -/
theorem lok630 : LiveOk prims outside liveBad 630 (src_impl_methods 155 621 927) := by decide +kernel

/-- mini::selfhost::with_impl -/
theorem lok632 : LiveOk prims outside liveBad 632 (src_with_impl 928) := by decide +kernel

/-- mini::selfhost::alias_decls -/
theorem lok638 : LiveOk prims outside liveBad 638 (src_alias_decls 608 609 610 611 613 614 930) := by decide +kernel

/-- mini::selfhost::host_extern -/
theorem lok641 : LiveOk prims outside liveBad 641 (src_host_extern 153 156 627 628 637 933 934 935 936) := by decide +kernel

/-- mini::selfhost::extern_tree -/
theorem lok642 : LiveOk prims outside liveBad 642 (src_extern_tree 148 156 254 607 640) := by decide +kernel

/-- mini::selfhost::optimize_binary -/
theorem lok696 : LiveOk prims outside liveBad 696 (src_optimize_binary 337 702 1012 1013 1014) := by decide +kernel

/-- mini::selfhost::optimize_compare -/
theorem lok697 : LiveOk prims outside liveBad 697 (src_optimize_compare 337 502 702 1015) := by decide +kernel

/-- mini::selfhost::optimize_seq -/
theorem lok701 : LiveOk prims outside liveBad 701 (src_optimize_seq 188 706) := by decide +kernel

/-- mini::selfhost::pick_branch -/
theorem lok703 : LiveOk prims outside liveBad 703 (src_pick_branch) := by decide +kernel

/-- mini::selfhost::ite_or_skip -/
theorem lok704 : LiveOk prims outside liveBad 704 (src_ite_or_skip 188 706) := by decide +kernel

/-- mini::selfhost::seq_agrees -/
theorem lok708 : LiveOk prims outside liveBad 708 (src_seq_agrees 307 470 699) := by decide +kernel

/-- mini::selfhost::dead_agrees -/
theorem lok709 : LiveOk prims outside liveBad 709 (src_dead_agrees 470 1018 1020) := by decide +kernel

/-- mini::selfhost::ite_agrees -/
theorem lok710 : LiveOk prims outside liveBad 710 (src_ite_agrees 307 470 1021) := by decide +kernel

/-- mini::selfhost::branch_agrees -/
theorem lok711 : LiveOk prims outside liveBad 711 (src_branch_agrees 470) := by decide +kernel

/-- mini::selfhost::unknown -/
theorem lok713 : LiveOk prims outside liveBad 713 (src_unknown) := by decide +kernel

/-- mini::selfhost::loop_agrees -/
theorem lok715 : LiveOk prims outside liveBad 715 (src_loop_agrees 282 307 470 1021) := by decide +kernel

/-- mini::selfhost::copy_field_of -/
theorem lok767 : LiveOk prims outside liveBad 767 (src_copy_field_of 75 181 520 521 1064) := by decide +kernel

/-- mini::selfhost::lower_tag -/
theorem lok769 : LiveOk prims outside liveBad 769 (src_lower_tag 542) := by decide +kernel

/-- mini::selfhost::shr_first -/
theorem lok844 : LiveOk prims outside liveBad 844 (src_shr_first 376 843) := by decide +kernel

/-- mini::selfhost::shr_second -/
theorem lok845 : LiveOk prims outside liveBad 845 (src_shr_second 75 376 843) := by decide +kernel

/-- mini::selfhost::methods_of -/
theorem lok927 : LiveOk prims outside liveBad 927 (src_methods_of 103 609 622 927 1127) := by decide +kernel

/-- mini::selfhost::with_impl_decl -/
theorem lok928 : LiveOk prims outside liveBad 928 (src_with_impl_decl 1128) := by decide +kernel

/-- mini::selfhost::text_lanius_std -/
theorem lok935 : LiveOk prims outside liveBad 935 (src_text_lanius_std 376 418) := by decide +kernel

/-- mini::selfhost::host_id -/
theorem lok936 : LiveOk prims outside liveBad 936 (src_host_id 934 1130 1131 1132 1133 1134 1135 1136 1137 1138 1139) := by decide +kernel

/-- mini::selfhost::extern_func -/
theorem lok992 : LiveOk prims outside liveBad 992 (src_extern_func 155 156 368 628 936 941 1232 1233 1234 1235 1236 1237 1238) := by decide +kernel

/-- mini::selfhost::optimize_both -/
theorem lok1012 : LiveOk prims outside liveBad 1012 (src_optimize_both 337 1252 1253) := by decide +kernel

/-- mini::selfhost::optimize_left -/
theorem lok1013 : LiveOk prims outside liveBad 1013 (src_optimize_left 337 1254 1255 1256 1257 1258) := by decide +kernel

/-- mini::selfhost::optimize_right -/
theorem lok1014 : LiveOk prims outside liveBad 1014 (src_optimize_right 337 1254 1256 1257 1258) := by decide +kernel

/-- mini::selfhost::fact_or -/
theorem lok1016 : LiveOk prims outside liveBad 1016 (src_fact_or 698) := by decide +kernel

/-- mini::selfhost::equality -/
theorem lok1056 : LiveOk prims outside liveBad 1056 (src_equality 235 337 800 802 1309 1313) := by decide +kernel

/-- mini::selfhost::copy_field_at -/
theorem lok1064 : LiveOk prims outside liveBad 1064 (src_copy_field_at 1323) := by decide +kernel

/-- mini::selfhost::method_decl -/
theorem lok1127 : LiveOk prims outside liveBad 1127 (src_method_decl 153 156 623 624 1361 1362 1363) := by decide +kernel

/-- mini::selfhost::text_write_byte -/
theorem lok1130 : LiveOk prims outside liveBad 1130 (src_text_write_byte 376 418) := by decide +kernel

/-- mini::selfhost::text_write_stdout -/
theorem lok1131 : LiveOk prims outside liveBad 1131 (src_text_write_stdout 376 418) := by decide +kernel

/-- mini::selfhost::text_write_stderr -/
theorem lok1132 : LiveOk prims outside liveBad 1132 (src_text_write_stderr 376 418) := by decide +kernel

/-- mini::selfhost::text_read_stdin -/
theorem lok1133 : LiveOk prims outside liveBad 1133 (src_text_read_stdin 376 418) := by decide +kernel

/-- mini::selfhost::text_sleep_ms_i32 -/
theorem lok1134 : LiveOk prims outside liveBad 1134 (src_text_sleep_ms_i32 376 418) := by decide +kernel

/-- mini::selfhost::text_monotonic_read -/
theorem lok1135 : LiveOk prims outside liveBad 1135 (src_text_monotonic_read 376 418) := by decide +kernel

/-- mini::selfhost::text_system_read -/
theorem lok1136 : LiveOk prims outside liveBad 1136 (src_text_system_read 376 418) := by decide +kernel

/-- mini::selfhost::text_fill_secure_bytes -/
theorem lok1137 : LiveOk prims outside liveBad 1137 (src_text_fill_secure_bytes 376 418) := by decide +kernel

/-- mini::selfhost::text_write_text -/
theorem lok1138 : LiveOk prims outside liveBad 1138 (src_text_write_text 376 418) := by decide +kernel

/-- mini::selfhost::text_write_newline -/
theorem lok1139 : LiveOk prims outside liveBad 1139 (src_text_write_newline 376 418) := by decide +kernel

/-- mini::selfhost::set_eval_closed -/
theorem lok1171 : LiveOk prims outside liveBad 1171 (src_set_eval_closed) := by decide +kernel

/-- mini::selfhost::if_eval_closed -/
theorem lok1172 : LiveOk prims outside liveBad 1172 (src_if_eval_closed 1202) := by decide +kernel

/-- mini::selfhost::while_eval_closed -/
theorem lok1173 : LiveOk prims outside liveBad 1173 (src_while_eval_closed 1202) := by decide +kernel

/-- mini::selfhost::return_eval_closed -/
theorem lok1174 : LiveOk prims outside liveBad 1174 (src_return_eval_closed) := by decide +kernel

/-- mini::selfhost::discard_closed -/
theorem lok1175 : LiveOk prims outside liveBad 1175 (src_discard_closed) := by decide +kernel

/-- mini::selfhost::set_index_eval_closed -/
theorem lok1176 : LiveOk prims outside liveBad 1176 (src_set_index_eval_closed) := by decide +kernel

/-- mini::selfhost::extern_body -/
theorem lok1235 : LiveOk prims outside liveBad 1235 (src_extern_body 1242 1243) := by decide +kernel

/-- mini::selfhost::p_type_path_ident -/
theorem lok1685 : LiveOk prims outside liveBad 1685 (src_p_type_path_ident) := by decide +kernel

/-- mini::selfhost::p_type_path_more -/
theorem lok1687 : LiveOk prims outside liveBad 1687 (src_p_type_path_more) := by decide +kernel

/-- mini::selfhost::kept -/
theorem lok1709 : LiveOk prims outside liveBad 1709 (src_kept 1263 1264) := by decide +kernel

/-- mini::selfhost::eval_head -/
theorem lok2061 : LiveOk prims outside liveBad 2061 (src_eval_head 2175) := by decide +kernel

/-- mini::selfhost::eval_let_head -/
theorem lok2175 : LiveOk prims outside liveBad 2175 (src_eval_let_head 1228 1229 1671 1887 2255 2300 2301 2302 2303 2304 2305 2306 2307) := by decide +kernel

/-- mini::selfhost::call_let_head -/
theorem lok2300 : LiveOk prims outside liveBad 2300 (src_call_let_head) := by decide +kernel

/-- mini::selfhost::index_let_head -/
theorem lok2302 : LiveOk prims outside liveBad 2302 (src_index_let_head) := by decide +kernel

/-- mini::selfhost::match_let_head -/
theorem lok2306 : LiveOk prims outside liveBad 2306 (src_match_let_head) := by decide +kernel

/-- mini::selfhost::fl_log2_or0 -/
theorem lok2373 : LiveOk prims outside liveBad 2373 (src_fl_log2_or0 2110) := by decide +kernel

/-- mini::selfhost::fl_sat -/
theorem lok2374 : LiveOk prims outside liveBad 2374 (src_fl_sat 56) := by decide +kernel

/-- mini::selfhost::fl_divmod -/
theorem lok2378 : LiveOk prims outside liveBad 2378 (src_fl_divmod 1883 2235 2378 2478) := by decide +kernel

/-- mini::selfhost::fl_odd -/
theorem lok2380 : LiveOk prims outside liveBad 2380 (src_fl_odd) := by decide +kernel

/-- mini::selfhost::fl_div_step -/
theorem lok2478 : LiveOk prims outside liveBad 2478 (src_fl_div_step 2365 2379 2527) := by decide +kernel

/-- mini::selfhost::single_ty -/
theorem lok2598 : LiveOk prims outside liveBad 2598 (src_single_ty 666) := by decide +kernel

/-- mini::selfhost::if_same_tys -/
theorem lok2599 : LiveOk prims outside liveBad 2599 (src_if_same_tys) := by decide +kernel

end Lanius.Faithful.SelfPure
