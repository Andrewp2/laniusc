module

public import Lanius.Faithful.Gen.SelfPureTab
public import Lanius.Faithful.Gen.SelfLiveTab
public import Lanius.Faithful.Gen.SelfSrc4
public import Lanius.Faithful.Gen.SelfSrcC_assignFrom
public import Lanius.Faithful.Gen.SelfSrcC_consArgs
public import Lanius.Faithful.Gen.SelfSrcC_lowerAddress
public import Lanius.Faithful.Gen.SelfSrcC_matchDst
public import Lanius.Faithful.Gen.SelfSrcF_Inline_charEnd
public import Lanius.Faithful.Gen.SelfSrcF_Inline_pLeTail
public import Lanius.Faithful.Gen.SelfSrcF_Inline_pTypeSliceTail
public import Lanius.Faithful.Gen.SelfSrcF_allWeighed
public import Lanius.Faithful.Gen.SelfSrcF_anyNested
public import Lanius.Faithful.Gen.SelfSrcF_depthLimit
public import Lanius.Faithful.Gen.SelfSrcF_effNamedTys
public import Lanius.Faithful.Gen.SelfSrcF_freshId
public import Lanius.Faithful.Gen.SelfSrcF_genericOpen
public import Lanius.Faithful.Gen.SelfSrcF_grammarPart8
public import Lanius.Faithful.Gen.SelfSrcF_lxCanonicalKind
public import Lanius.Faithful.Gen.SelfSrcF_pickTy
public import Lanius.Faithful.Gen.SelfSrcF_readCountedBytes
public import Lanius.Faithful.Gen.SelfSrcF_rootInsts
public import Lanius.Faithful.Gen.SelfSrcF_tryLetHead
import all Lanius.Faithful.Gen.SelfLiveTab
import all Lanius.Faithful.Gen.SelfPureTab
import all Lanius.Faithful.Gen.SelfSrc4
import all Lanius.Faithful.Gen.SelfSrcC_assignFrom
import all Lanius.Faithful.Gen.SelfSrcC_consArgs
import all Lanius.Faithful.Gen.SelfSrcC_lowerAddress
import all Lanius.Faithful.Gen.SelfSrcC_matchDst
import all Lanius.Faithful.Gen.SelfSrcF_Inline_charEnd
import all Lanius.Faithful.Gen.SelfSrcF_Inline_pLeTail
import all Lanius.Faithful.Gen.SelfSrcF_Inline_pTypeSliceTail
import all Lanius.Faithful.Gen.SelfSrcF_allWeighed
import all Lanius.Faithful.Gen.SelfSrcF_anyNested
import all Lanius.Faithful.Gen.SelfSrcF_depthLimit
import all Lanius.Faithful.Gen.SelfSrcF_effNamedTys
import all Lanius.Faithful.Gen.SelfSrcF_freshId
import all Lanius.Faithful.Gen.SelfSrcF_genericOpen
import all Lanius.Faithful.Gen.SelfSrcF_grammarPart8
import all Lanius.Faithful.Gen.SelfSrcF_lxCanonicalKind
import all Lanius.Faithful.Gen.SelfSrcF_pickTy
import all Lanius.Faithful.Gen.SelfSrcF_readCountedBytes
import all Lanius.Faithful.Gen.SelfSrcF_rootInsts
import all Lanius.Faithful.Gen.SelfSrcF_tryLetHead
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

/-- mini::selfhost::read_counted_files -/
theorem lok13 : LiveOk prims outside liveBad 13 (src_read_counted_files 10 40 41) := by decide +kernel

/-- mini::selfhost::grammar_part_8 -/
theorem lok24 : LiveOk prims outside liveBad 24 (src_grammar_part_8 45 46 47 48) := by decide +kernel

/-- mini::selfhost::grammar_part_9 -/
theorem lok25 : LiveOk prims outside liveBad 25 (src_grammar_part_9 45 46 47 48) := by decide +kernel

/-- mini::selfhost::grammar_part_10 -/
theorem lok26 : LiveOk prims outside liveBad 26 (src_grammar_part_10 45 46 47 48) := by decide +kernel

/-- mini::selfhost::grammar_part_11 -/
theorem lok27 : LiveOk prims outside liveBad 27 (src_grammar_part_11 45 46 47 48) := by decide +kernel

/-- mini::selfhost::grammar_part_12 -/
theorem lok28 : LiveOk prims outside liveBad 28 (src_grammar_part_12 45 46 47 48) := by decide +kernel

/-- mini::selfhost::read_files -/
theorem lok40 : LiveOk prims outside liveBad 40 (src_read_files 40 56 66 67 68) := by decide +kernel

/-- mini::selfhost::word_num -/
theorem lok41 : LiveOk prims outside liveBad 41 (src_word_num) := by decide +kernel

/-- mini::selfhost::concat<i32> -/
theorem lok51 : LiveOk prims outside liveBad 51 (src_concat_of_i32 10 33 51) := by decide +kernel

/-- mini::selfhost::length<usize> -/
theorem lok52 : LiveOk prims outside liveBad 52 (src_length_of_usize 52 75 76) := by decide +kernel

/-- mini::selfhost::read_file -/
theorem lok67 : LiveOk prims outside liveBad 67 (src_read_file 92 93 94) := by decide +kernel

/-- mini::selfhost::files_after -/
theorem lok68 : LiveOk prims outside liveBad 68 (src_files_after 95) := by decide +kernel

/-- mini::selfhost::read_counted_bytes -/
theorem lok92 : LiveOk prims outside liveBad 92 (src_read_counted_bytes 10 41 144) := by decide +kernel

/-- mini::selfhost::read_file_parents -/
theorem lok93 : LiveOk prims outside liveBad 93 (src_read_file_parents 94 145) := by decide +kernel

/-- mini::selfhost::read_counted_nums -/
theorem lok94 : LiveOk prims outside liveBad 94 (src_read_counted_nums 10 41 146) := by decide +kernel

/-- mini::selfhost::empty<mini::selfhost::Binding> -/
theorem lok131 : LiveOk prims outside liveBad 131 (src_empty_of_mini_selfhost_Binding) := by decide +kernel

/-- mini::selfhost::empty<mini::selfhost::Sig> -/
theorem lok133 : LiveOk prims outside liveBad 133 (src_empty_of_mini_selfhost_Sig) := by decide +kernel

/-- mini::selfhost::cons<mini::selfhost::Sig> -/
theorem lok134 : LiveOk prims outside liveBad 134 (src_cons_of_mini_selfhost_Sig 238) := by decide +kernel

/-- mini::selfhost::read_bytes -/
theorem lok144 : LiveOk prims outside liveBad 144 (src_read_bytes 10 41 56 139 144 249) := by decide +kernel

/-- mini::selfhost::read_file_end -/
theorem lok145 : LiveOk prims outside liveBad 145 (src_read_file_end 250 251) := by decide +kernel

/-- mini::selfhost::read_nums -/
theorem lok146 : LiveOk prims outside liveBad 146 (src_read_nums 10 41 56 139 146 252) := by decide +kernel

/-- mini::selfhost::root_insts -/
theorem lok160 : LiveOk prims outside liveBad 160 (src_root_insts 272 273 274) := by decide +kernel

/-- mini::selfhost::seed_insts -/
theorem lok162 : LiveOk prims outside liveBad 162 (src_seed_insts 272 275 276) := by decide +kernel

/-- ?<mini::selfhost::Decls> -/
theorem lok163 : LiveOk prims outside liveBad 163 (src_field_types_Decls_of_mini_selfhost_Decls) := by decide +kernel

/-- mini::selfhost::unbox<mini::selfhost::List<mini::selfhost::SrcType>> -/
theorem lok181 : LiveOk prims outside liveBad 181 (src_unbox_of_mini_selfhost_List_mini_selfhost_SrcType 303) := by decide +kernel

/-- mini::selfhost::single<mini::selfhost::Expr> -/
theorem lok189 : LiveOk prims outside liveBad 189 (src_single_of_mini_selfhost_Expr 311) := by decide +kernel

/-- mini::selfhost::cons<mini::selfhost::Binding> -/
theorem lok194 : LiveOk prims outside liveBad 194 (src_cons_of_mini_selfhost_Binding 320) := by decide +kernel

/-- mini::selfhost::lower_load -/
theorem lok212 : LiveOk prims outside liveBad 212 (src_lower_load 188) := by decide +kernel

/-- mini::selfhost::lower_address -/
theorem lok213 : LiveOk prims outside liveBad 213 (src_lower_address 337) := by decide +kernel

/-- mini::selfhost::lower_store -/
theorem lok214 : LiveOk prims outside liveBad 214 (src_lower_store) := by decide +kernel

/-- mini::selfhost::lower_free -/
theorem lok215 : LiveOk prims outside liveBad 215 (src_lower_free) := by decide +kernel

/-- mini::selfhost::boxed<mini::selfhost::SrcType> -/
theorem lok217 : LiveOk prims outside liveBad 217 (src_boxed_of_mini_selfhost_SrcType 50 305 342) := by decide +kernel

/-- mini::selfhost::byte_after -/
theorem lok249 : LiveOk prims outside liveBad 249 (src_byte_after 252) := by decide +kernel

/-- mini::selfhost::file_lexed -/
theorem lok250 : LiveOk prims outside liveBad 250 (src_file_lexed) := by decide +kernel

/-- mini::selfhost::lex_source -/
theorem lok251 : LiveOk prims outside liveBad 251 (src_lex_source 52 75 412 413 414 415 416 417) := by decide +kernel

/-- mini::selfhost::nums_after -/
theorem lok252 : LiveOk prims outside liveBad 252 (src_nums_after 418) := by decide +kernel

/-- mini::selfhost::get_or<mini::selfhost::CTree> -/
theorem lok261 : LiveOk prims outside liveBad 261 (src_get_or_of_mini_selfhost_CTree 56 103 261) := by decide +kernel

/-- mini::selfhost::empty<mini::selfhost::Fact> -/
theorem lok282 : LiveOk prims outside liveBad 282 (src_empty_of_mini_selfhost_Fact) := by decide +kernel

/-- mini::selfhost::cons<mini::selfhost::Code> -/
theorem lok287 : LiveOk prims outside liveBad 287 (src_cons_of_mini_selfhost_Code 481) := by decide +kernel

/-- mini::selfhost::assign_from -/
theorem lok316 : LiveOk prims outside liveBad 316 (src_assign_from 75 188 316 493) := by decide +kernel

/-- mini::selfhost::boxed<mini::selfhost::List<mini::selfhost::Binding>> -/
theorem lok320 : LiveOk prims outside liveBad 320 (src_boxed_of_mini_selfhost_List_mini_selfhost_Binding 50 513 514) := by decide +kernel

/-- mini::selfhost::match_dst -/
theorem lok366 : LiveOk prims outside liveBad 366 (src_match_dst 75 120 186) := by decide +kernel

/-- mini::selfhost::length<u64> -/
theorem lok398 : LiveOk prims outside liveBad 398 (src_length_of_u64 75 398 575) := by decide +kernel

/-- mini::selfhost::lx_symbol_rules -/
theorem lok413 : LiveOk prims outside liveBad 413 (src_lx_symbol_rules 376 418 594 595) := by decide +kernel

/-- mini::selfhost::lx_tokens -/
theorem lok414 : LiveOk prims outside liveBad 414 (src_lx_tokens 596 597 598 599) := by decide +kernel

/-- mini::selfhost::lx_ranges -/
theorem lok415 : LiveOk prims outside liveBad 415 (src_lx_ranges 589 599 600) := by decide +kernel

/-- mini::selfhost::lx_filter -/
theorem lok416 : LiveOk prims outside liveBad 416 (src_lx_filter 589 598 599 601) := by decide +kernel

/-- mini::selfhost::lx_keyword_rules -/
theorem lok417 : LiveOk prims outside liveBad 417 (src_lx_keyword_rules 376 418 594 595) := by decide +kernel

/-- mini::selfhost::types_weighed -/
theorem lok437 : LiveOk prims outside liveBad 437 (src_types_weighed 660 661 662 663 664) := by decide +kernel

/-- mini::selfhost::concat<mini::selfhost::FnDecl> -/
theorem lok452 : LiveOk prims outside liveBad 452 (src_concat_of_mini_selfhost_FnDecl 274 452 686) := by decide +kernel

/-- mini::selfhost::concat<mini::selfhost::Instr> -/
theorem lok478 : LiveOk prims outside liveBad 478 (src_concat_of_mini_selfhost_Instr 478 739 741) := by decide +kernel

/-- mini::selfhost::boxed<mini::selfhost::List<mini::selfhost::Code>> -/
theorem lok481 : LiveOk prims outside liveBad 481 (src_boxed_of_mini_selfhost_List_mini_selfhost_Code 50 750 751) := by decide +kernel

/-- mini::selfhost::cons_args -/
theorem lok546 : LiveOk prims outside liveBad 546 (src_cons_args 188 240) := by decide +kernel

/-- mini::selfhost::p_where_none -/
theorem lok637 : LiveOk prims outside liveBad 637 (src_p_where_none) := by decide +kernel

/-- mini::selfhost::table_weighed -/
theorem lok660 : LiveOk prims outside liveBad 660 (src_table_weighed) := by decide +kernel

/-- mini::selfhost::all_weighed -/
theorem lok661 : LiveOk prims outside liveBad 661 (src_all_weighed 661 968 969) := by decide +kernel

/-- mini::selfhost::unbox<mini::selfhost::List<mini::selfhost::Ty>> -/
theorem lok666 : LiveOk prims outside liveBad 666 (src_unbox_of_mini_selfhost_List_mini_selfhost_Ty 976) := by decide +kernel

/-- mini::selfhost::unbox<mini::selfhost::List<mini::selfhost::MFunc>> -/
theorem lok676 : LiveOk prims outside liveBad 676 (src_unbox_of_mini_selfhost_List_mini_selfhost_MFunc 986) := by decide +kernel

/-- mini::selfhost::stmt_calls -/
theorem lok678 : LiveOk prims outside liveBad 678 (src_stmt_calls 272 447 678 983 988 989 990) := by decide +kernel

/-- mini::selfhost::cons<mini::selfhost::MFunc> -/
theorem lok679 : LiveOk prims outside liveBad 679 (src_cons_of_mini_selfhost_MFunc 991) := by decide +kernel

/-- mini::selfhost::unbox<mini::selfhost::List<mini::selfhost::ImplDecl>> -/
theorem lok693 : LiveOk prims outside liveBad 693 (src_unbox_of_mini_selfhost_List_mini_selfhost_ImplDecl 1010) := by decide +kernel

/-- mini::selfhost::lower_arms -/
theorem lok771 : LiveOk prims outside liveBad 771 (src_lower_arms 75 183 375 771 822 1066 1067 1068) := by decide +kernel

/-- mini::selfhost::lower_arm_value -/
theorem lok822 : LiveOk prims outside liveBad 822 (src_lower_arm_value 193) := by decide +kernel

/-- mini::selfhost::boxed<mini::selfhost::List<mini::selfhost::SrcEnumDecl>> -/
theorem lok828 : LiveOk prims outside liveBad 828 (src_boxed_of_mini_selfhost_List_mini_selfhost_SrcEnumDecl 50 829 1098) := by decide +kernel

/-- mini::selfhost::get<usize> -/
theorem lok830 : LiveOk prims outside liveBad 830 (src_get_of_usize 56 76 830) := by decide +kernel

/-- mini::selfhost::lx_token -/
theorem lok835 : LiveOk prims outside liveBad 835 (src_lx_token 56 1114 1115) := by decide +kernel

/-- mini::selfhost::single<mini::selfhost::RawTok> -/
theorem lok837 : LiveOk prims outside liveBad 837 (src_single_of_mini_selfhost_RawTok 1110) := by decide +kernel

/-- mini::selfhost::lx_range_pair -/
theorem lok838 : LiveOk prims outside liveBad 838 (src_lx_range_pair) := by decide +kernel

/-- mini::selfhost::lx_canonical_kind -/
theorem lok840 : LiveOk prims outside liveBad 840 (src_lx_canonical_kind 56 1115 1116) := by decide +kernel

/-- mini::selfhost::p_match_arms_none -/
theorem lok887 : LiveOk prims outside liveBad 887 (src_p_match_arms_none) := by decide +kernel

/-- mini::selfhost::p_match_arms_some -/
theorem lok888 : LiveOk prims outside liveBad 888 (src_p_match_arms_some) := by decide +kernel

/-- mini::selfhost::p_match_arms_more -/
theorem lok889 : LiveOk prims outside liveBad 889 (src_p_match_arms_more) := by decide +kernel

/-- mini::selfhost::p_match_arms_end -/
theorem lok890 : LiveOk prims outside liveBad 890 (src_p_match_arms_end) := by decide +kernel

/-- mini::selfhost::p_match_arms_after_comma_more -/
theorem lok891 : LiveOk prims outside liveBad 891 (src_p_match_arms_after_comma_more) := by decide +kernel

/-- mini::selfhost::p_match_arms_after_comma_trailing -/
theorem lok892 : LiveOk prims outside liveBad 892 (src_p_match_arms_after_comma_trailing) := by decide +kernel

/-- mini::selfhost::empty<core::option::Option<usize>> -/
theorem lok972 : LiveOk prims outside liveBad 972 (src_empty_of_core_option_Option_usize) := by decide +kernel

/-- mini::selfhost::single<mini::selfhost::Ty> -/
theorem lok975 : LiveOk prims outside liveBad 975 (src_single_of_mini_selfhost_Ty 670) := by decide +kernel

/-- mini::selfhost::eff_named_tys -/
theorem lok985 : LiveOk prims outside liveBad 985 (src_eff_named_tys 448 669 672 975 985 1227 1228 1229) := by decide +kernel

/-- mini::selfhost::get<mini::selfhost::Arity> -/
theorem lok1033 : LiveOk prims outside liveBad 1033 (src_get_of_mini_selfhost_Arity 56 1033 1279) := by decide +kernel

/-- mini::selfhost::unbox<mini::selfhost::List<mini::selfhost::SrcArm>> -/
theorem lok1066 : LiveOk prims outside liveBad 1066 (src_unbox_of_mini_selfhost_List_mini_selfhost_SrcArm 1324) := by decide +kernel

/-- mini::selfhost::lower_arm -/
theorem lok1067 : LiveOk prims outside liveBad 1067 (src_lower_arm 188 312 316 337) := by decide +kernel

/-- mini::selfhost::arm_guard -/
theorem lok1068 : LiveOk prims outside liveBad 1068 (src_arm_guard 191) := by decide +kernel

/-- mini::selfhost::lx_token_text -/
theorem lok1114 : LiveOk prims outside liveBad 1114 (src_lx_token_text 934 1345) := by decide +kernel

/-- mini::selfhost::picks -/
theorem lok1117 : LiveOk prims outside liveBad 1117 (src_picks 645 1348 1349 1350 1351 1352 1353 1354 1355) := by decide +kernel

/-- mini::selfhost::close_ty -/
theorem lok1152 : LiveOk prims outside liveBad 1152 (src_close_ty 56 666 977 1152 1156 1367 1368 1369 1370) := by decide +kernel

/-- mini::selfhost::src_enum_id -/
theorem lok1159 : LiveOk prims outside liveBad 1159 (src_src_enum_id) := by decide +kernel

/-- mini::selfhost::lim_ty -/
theorem lok1190 : LiveOk prims outside liveBad 1190 (src_lim_ty 968 1401) := by decide +kernel

/-- mini::selfhost::depth_limit -/
theorem lok1192 : LiveOk prims outside liveBad 1192 (src_depth_limit) := by decide +kernel

/-- mini::selfhost::effs_named_tys -/
theorem lok1227 : LiveOk prims outside liveBad 1227 (src_effs_named_tys 448 672 985 1227 1228) := by decide +kernel

/-- ?<mini::selfhost::Token> -/
theorem lok1233 : LiveOk prims outside liveBad 1233 (src_field_start_Token_of_mini_selfhost_Token) := by decide +kernel

/-- mini::selfhost::boxed<mini::selfhost::List<mini::selfhost::MParam>> -/
theorem lok1250 : LiveOk prims outside liveBad 1250 (src_boxed_of_mini_selfhost_List_mini_selfhost_MParam 50 1224 1482) := by decide +kernel

/-- mini::selfhost::lx_as_text -/
theorem lok1345 : LiveOk prims outside liveBad 1345 (src_lx_as_text 376 418) := by decide +kernel

/-- mini::selfhost::p_member_type_args_some -/
theorem lok1348 : LiveOk prims outside liveBad 1348 (src_p_member_type_args_some) := by decide +kernel

/-- mini::selfhost::generic_open -/
theorem lok1349 : LiveOk prims outside liveBad 1349 (src_generic_open 167 1530 1531) := by decide +kernel

/-- mini::selfhost::p_member_type_args_none -/
theorem lok1350 : LiveOk prims outside liveBad 1350 (src_p_member_type_args_none) := by decide +kernel

/-- mini::selfhost::opens_block -/
theorem lok1352 : LiveOk prims outside liveBad 1352 (src_opens_block 1532) := by decide +kernel

/-- mini::selfhost::generic_path_at -/
theorem lok1354 : LiveOk prims outside liveBad 1354 (src_generic_path_at 167 1349) := by decide +kernel

/-- mini::selfhost::close_named -/
theorem lok1368 : LiveOk prims outside liveBad 1368 (src_close_named 56 960 1535) := by decide +kernel

/-- mini::selfhost::lim_slots -/
theorem lok1401 : LiveOk prims outside liveBad 1401 (src_lim_slots 181 183 184 1401 1547 1548 1549 1550 1551) := by decide +kernel

/-- mini::selfhost::lim_expr -/
theorem lok1402 : LiveOk prims outside liveBad 1402 (src_lim_expr 313 1190 1402) := by decide +kernel

/-- mini::selfhost::depth_sum -/
theorem lok1411 : LiveOk prims outside liveBad 1411 (src_depth_sum 56 75 1192) := by decide +kernel

/-- mini::selfhost::empty<mini::selfhost::SrcArm> -/
theorem lok1441 : LiveOk prims outside liveBad 1441 (src_empty_of_mini_selfhost_SrcArm) := by decide +kernel

/-- mini::selfhost::cons<mini::selfhost::SrcArm> -/
theorem lok1442 : LiveOk prims outside liveBad 1442 (src_cons_of_mini_selfhost_SrcArm 1577) := by decide +kernel

/-- mini::selfhost::empty<mini::selfhost::MEff> -/
theorem lok1471 : LiveOk prims outside liveBad 1471 (src_empty_of_mini_selfhost_MEff) := by decide +kernel

/-- mini::selfhost::boxed<mini::selfhost::List<mini::selfhost::SrcParam>> -/
theorem lok1534 : LiveOk prims outside liveBad 1534 (src_boxed_of_mini_selfhost_List_mini_selfhost_SrcParam 50 296 1649) := by decide +kernel

/-- mini::selfhost::lim_slots_list -/
theorem lok1548 : LiveOk prims outside liveBad 1548 (src_lim_slots_list 181 1401 1548 1659) := by decide +kernel

/-- mini::selfhost::lim_slots_variants -/
theorem lok1549 : LiveOk prims outside liveBad 1549 (src_lim_slots_variants 183 1548 1549 1659) := by decide +kernel

/-- mini::selfhost::fresh_id -/
theorem lok1595 : LiveOk prims outside liveBad 1595 (src_fresh_id 1595 1672) := by decide +kernel

/-- mini::selfhost::cons<mini::selfhost::Local> -/
theorem lok1599 : LiveOk prims outside liveBad 1599 (src_cons_of_mini_selfhost_Local 1679) := by decide +kernel

/-- mini::selfhost::p_type_slice_tail -/
theorem lok1601 : LiveOk prims outside liveBad 1601 (src_p_type_slice_tail) := by decide +kernel

/-- mini::selfhost::unbox<mini::selfhost::List<mini::selfhost::Local>> -/
theorem lok1672 : LiveOk prims outside liveBad 1672 (src_unbox_of_mini_selfhost_List_mini_selfhost_Local 1743) := by decide +kernel

/-- mini::selfhost::unbox<mini::selfhost::List<mini::selfhost::BoundGoal>> -/
theorem lok1692 : LiveOk prims outside liveBad 1692 (src_unbox_of_mini_selfhost_List_mini_selfhost_BoundGoal 1759) := by decide +kernel

/-- mini::selfhost::find_type -/
theorem lok1754 : LiveOk prims outside liveBad 1754 (src_find_type 276 1790) := by decide +kernel

/-- mini::selfhost::local_expr -/
theorem lok1819 : LiveOk prims outside liveBad 1819 (src_local_expr) := by decide +kernel

/-- mini::selfhost::p_match_expr -/
theorem lok1835 : LiveOk prims outside liveBad 1835 (src_p_match_expr) := by decide +kernel

/-- mini::selfhost::p_let_stmt -/
theorem lok1839 : LiveOk prims outside liveBad 1839 (src_p_let_stmt) := by decide +kernel

/-- mini::selfhost::member_of -/
theorem lok1875 : LiveOk prims outside liveBad 1875 (src_member_of 153 156 627 628 1350 1798 1820 1990 1991) := by decide +kernel

/-- mini::selfhost::expected_array -/
theorem lok1907 : LiveOk prims outside liveBad 1907 (src_expected_array 2040) := by decide +kernel

/-- mini::selfhost::repeat_ty -/
theorem lok1911 : LiveOk prims outside liveBad 1911 (src_repeat_ty 56 448 669 1911) := by decide +kernel

/-- mini::selfhost::p_let_type -/
theorem lok1914 : LiveOk prims outside liveBad 1914 (src_p_let_type) := by decide +kernel

/-- mini::selfhost::p_let_init -/
theorem lok1915 : LiveOk prims outside liveBad 1915 (src_p_let_init) := by decide +kernel

/-- mini::selfhost::p_let_type_none -/
theorem lok1925 : LiveOk prims outside liveBad 1925 (src_p_let_type_none) := by decide +kernel

/-- mini::selfhost::p_lt_tail -/
theorem lok1975 : LiveOk prims outside liveBad 1975 (src_p_lt_tail) := by decide +kernel

/-- mini::selfhost::p_le_tail -/
theorem lok1977 : LiveOk prims outside liveBad 1977 (src_p_le_tail) := by decide +kernel

/-- mini::selfhost::field_expr -/
theorem lok1990 : LiveOk prims outside liveBad 1990 (src_field_expr) := by decide +kernel

/-- mini::selfhost::field_index -/
theorem lok1991 : LiveOk prims outside liveBad 1991 (src_field_index 163 1185 2097) := by decide +kernel

/-- mini::selfhost::array_parts -/
theorem lok2040 : LiveOk prims outside liveBad 2040 (src_array_parts 977) := by decide +kernel

/-- mini::selfhost::length<mini::selfhost::MEff> -/
theorem lok2042 : LiveOk prims outside liveBad 2042 (src_length_of_mini_selfhost_MEff 75 1228 2042) := by decide +kernel

/-- mini::selfhost::try_let_head -/
theorem lok2060 : LiveOk prims outside liveBad 2060 (src_try_let_head 2062 2174) := by decide +kernel

/-- mini::selfhost::slice_elem -/
theorem lok2083 : LiveOk prims outside liveBad 2083 (src_slice_elem 977) := by decide +kernel

/-- mini::selfhost::field_in -/
theorem lok2097 : LiveOk prims outside liveBad 2097 (src_field_in 1785) := by decide +kernel

/-- mini::selfhost::char_first -/
theorem lok2105 : LiveOk prims outside liveBad 2105 (src_char_first 56 2226 2227 2228) := by decide +kernel

/-- mini::selfhost::unbox<mini::selfhost::List<mini::selfhost::VariantAt>> -/
theorem lok2139 : LiveOk prims outside liveBad 2139 (src_unbox_of_mini_selfhost_List_mini_selfhost_VariantAt 2261) := by decide +kernel

/-- mini::selfhost::expr_ty -/
theorem lok2143 : LiveOk prims outside liveBad 2143 (src_expr_ty 56 313 1569 1851 2143 2145 2146 2149 2263 2264 2265) := by decide +kernel

/-- mini::selfhost::pick_ty -/
theorem lok2146 : LiveOk prims outside liveBad 2146 (src_pick_ty) := by decide +kernel

/-- mini::selfhost::find_bind -/
theorem lok2216 : LiveOk prims outside liveBad 2216 (src_find_bind 2347 2348) := by decide +kernel

/-- mini::selfhost::char_escape -/
theorem lok2226 : LiveOk prims outside liveBad 2226 (src_char_escape 76 2360 2361) := by decide +kernel

/-- mini::selfhost::find_fn -/
theorem lok2245 : LiveOk prims outside liveBad 2245 (src_find_fn 274 2389) := by decide +kernel

/-- mini::selfhost::index_elem -/
theorem lok2267 : LiveOk prims outside liveBad 2267 (src_index_elem 977) := by decide +kernel

/-- mini::selfhost::any_nested -/
theorem lok2290 : LiveOk prims outside liveBad 2290 (src_any_nested 103 2290 2421 2422) := by decide +kernel

/-- mini::selfhost::try_rest -/
theorem lok2313 : LiveOk prims outside liveBad 2313 (src_try_rest 1241 1242 2437) := by decide +kernel

/-- mini::selfhost::param_spelling -/
theorem lok2342 : LiveOk prims outside liveBad 2342 (src_param_spelling 1142 1746 2123 2465) := by decide +kernel

/-- mini::selfhost::bind_ty -/
theorem lok2343 : LiveOk prims outside liveBad 2343 (src_bind_ty 1671 2216 2345 2466) := by decide +kernel

/-- mini::selfhost::bare_prim -/
theorem lok2344 : LiveOk prims outside liveBad 2344 (src_bare_prim 1746 2123 2467) := by decide +kernel

/-- mini::selfhost::same_or_none -/
theorem lok2345 : LiveOk prims outside liveBad 2345 (src_same_or_none) := by decide +kernel

/-- mini::selfhost::char_end -/
theorem lok2362 : LiveOk prims outside liveBad 2362 (src_char_end) := by decide +kernel

/-- mini::selfhost::char_tail_at -/
theorem lok2363 : LiveOk prims outside liveBad 2363 (src_char_tail_at 56 75 105 2227 2228) := by decide +kernel

/-- mini::selfhost::try_payload -/
theorem lok2437 : LiveOk prims outside liveBad 2437 (src_try_payload 1471 2019) := by decide +kernel

/-- mini::selfhost::param_named -/
theorem lok2465 : LiveOk prims outside liveBad 2465 (src_param_named) := by decide +kernel

/-- mini::selfhost::prim_if -/
theorem lok2467 : LiveOk prims outside liveBad 2467 (src_prim_if 1786) := by decide +kernel

/-- mini::selfhost::length<mini::selfhost::CTree> -/
theorem lok2552 : LiveOk prims outside liveBad 2552 (src_length_of_mini_selfhost_CTree 75 103 2552) := by decide +kernel

/-- mini::selfhost::length<mini::selfhost::VariantTy> -/
theorem lok2553 : LiveOk prims outside liveBad 2553 (src_length_of_mini_selfhost_VariantTy 75 2169 2553) := by decide +kernel

/-- mini::selfhost::rows_naming -/
theorem lok2594 : LiveOk prims outside liveBad 2594 (src_rows_naming 96 103 2594 2615 2616) := by decide +kernel

/-- mini::selfhost::row_cons -/
theorem lok2615 : LiveOk prims outside liveBad 2615 (src_row_cons 2617) := by decide +kernel

/-- mini::selfhost::arm_naming -/
theorem lok2616 : LiveOk prims outside liveBad 2616 (src_arm_naming 156 429 2625) := by decide +kernel

/-- mini::selfhost::named_known -/
theorem lok2625 : LiveOk prims outside liveBad 2625 (src_named_known 2426) := by decide +kernel

/-- mini::selfhost::row_pats -/
theorem lok2635 : LiveOk prims outside liveBad 2635 (src_row_pats 153 155 156 2425 2427) := by decide +kernel

/-- mini::selfhost::first_nested -/
theorem lok2638 : LiveOk prims outside liveBad 2638 (src_first_nested 75 103 2589 2638 2641) := by decide +kernel

/-- mini::selfhost::first_at -/
theorem lok2641 : LiveOk prims outside liveBad 2641 (src_first_at) := by decide +kernel

/-- mini::selfhost::column_arms -/
theorem lok2644 : LiveOk prims outside liveBad 2644 (src_column_arms 96 103 2635 2644 2647 2648) := by decide +kernel

/-- mini::selfhost::column_arm -/
theorem lok2647 : LiveOk prims outside liveBad 2647 (src_column_arm 2642 2655 2656 2657) := by decide +kernel

/-- mini::selfhost::is_last -/
theorem lok2648 : LiveOk prims outside liveBad 2648 (src_is_last) := by decide +kernel

/-- mini::selfhost::ends_wild -/
theorem lok2649 : LiveOk prims outside liveBad 2649 (src_ends_wild 2510) := by decide +kernel

/-- mini::selfhost::column_fit -/
theorem lok2655 : LiveOk prims outside liveBad 2655 (src_column_fit 2572) := by decide +kernel

/-- mini::selfhost::row_fits -/
theorem lok2656 : LiveOk prims outside liveBad 2656 (src_row_fits 75 103 2656 2661) := by decide +kernel

/-- mini::selfhost::column_sub -/
theorem lok2657 : LiveOk prims outside liveBad 2657 (src_column_sub 156 1800 2589 2662 2663 2664) := by decide +kernel

/-- mini::selfhost::col_fits -/
theorem lok2661 : LiveOk prims outside liveBad 2661 (src_col_fits 156 1800 2589 2670) := by decide +kernel

/-- mini::selfhost::quiet_sub -/
theorem lok2662 : LiveOk prims outside liveBad 2662 (src_quiet_sub 2671) := by decide +kernel

/-- mini::selfhost::quiet_in -/
theorem lok2663 : LiveOk prims outside liveBad 2663 (src_quiet_in 607 2576 2672) := by decide +kernel

/-- mini::selfhost::sub_arm -/
theorem lok2664 : LiveOk prims outside liveBad 2664 (src_sub_arm 148 153 156 254 607) := by decide +kernel

/-- mini::selfhost::named_path -/
theorem lok2668 : LiveOk prims outside liveBad 2668 (src_named_path 96 148 156 254 607 628 645 646 1859) := by decide +kernel

/-- mini::selfhost::same_opt_name -/
theorem lok2670 : LiveOk prims outside liveBad 2670 (src_same_opt_name 934) := by decide +kernel

/-- mini::selfhost::quiet_arm -/
theorem lok2671 : LiveOk prims outside liveBad 2671 (src_quiet_arm 2664 2676) := by decide +kernel

/-- mini::selfhost::mentions -/
theorem lok2672 : LiveOk prims outside liveBad 2672 (src_mentions 56 103 934 1120 2421 2672) := by decide +kernel

/-- mini::selfhost::wild_pat -/
theorem lok2676 : LiveOk prims outside liveBad 2676 (src_wild_pat 96 148 254 607 2425 2427 2517 2668) := by decide +kernel

end Lanius.Faithful.SelfPure
