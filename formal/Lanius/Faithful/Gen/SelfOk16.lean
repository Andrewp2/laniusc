module

public import Lanius.Faithful.Gen.SelfPureTab
public import Lanius.Faithful.Gen.SelfSrc0
public import Lanius.Faithful.Gen.SelfSrcC_Stmt_kills
public import Lanius.Faithful.Gen.SelfSrcC_applyGuard
public import Lanius.Faithful.Gen.SelfSrcC_strStores
public import Lanius.Faithful.Gen.SelfSrcC_usizeWidth
public import Lanius.Faithful.Gen.SelfSrcF_Inline_pContractsNone
public import Lanius.Faithful.Gen.SelfSrcF_frontEndWords
public import Lanius.Faithful.Gen.SelfSrcF_funcsOnto
public import Lanius.Faithful.Gen.SelfSrcF_genericClose
public import Lanius.Faithful.Gen.SelfSrcF_limNumsArms
public import Lanius.Faithful.Gen.SelfSrcF_lxFixed
public import Lanius.Faithful.Gen.SelfSrcF_pathRef
public import Lanius.Faithful.Gen.SelfSrcF_stringReturn
public import Lanius.Faithful.Gen.SelfSrcF_structHead
public import Lanius.Faithful.Gen.SelfSrcF_wideMarker
import all Lanius.Faithful.Gen.SelfPureTab
import all Lanius.Faithful.Gen.SelfSrc0
import all Lanius.Faithful.Gen.SelfSrcC_Stmt_kills
import all Lanius.Faithful.Gen.SelfSrcC_applyGuard
import all Lanius.Faithful.Gen.SelfSrcC_strStores
import all Lanius.Faithful.Gen.SelfSrcC_usizeWidth
import all Lanius.Faithful.Gen.SelfSrcF_Inline_pContractsNone
import all Lanius.Faithful.Gen.SelfSrcF_frontEndWords
import all Lanius.Faithful.Gen.SelfSrcF_funcsOnto
import all Lanius.Faithful.Gen.SelfSrcF_genericClose
import all Lanius.Faithful.Gen.SelfSrcF_limNumsArms
import all Lanius.Faithful.Gen.SelfSrcF_lxFixed
import all Lanius.Faithful.Gen.SelfSrcF_pathRef
import all Lanius.Faithful.Gen.SelfSrcF_stringReturn
import all Lanius.Faithful.Gen.SelfSrcF_structHead
import all Lanius.Faithful.Gen.SelfSrcF_wideMarker
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

set_option linter.unusedVariables false

/-- mini::selfhost::front_end_words -/
theorem fok7 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 7 (src_front_end_words 13 14) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::grammar_part_0 -/
theorem fok16 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 16 (src_grammar_part_0 45 46 47 48) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::grammar_part_1 -/
theorem fok17 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 17 (src_grammar_part_1 45 46 47 48) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::grammar_part_2 -/
theorem fok18 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 18 (src_grammar_part_2 45 46 47 48) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::grammar_part_3 -/
theorem fok19 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 19 (src_grammar_part_3 45 46 47 48) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::grammar_part_4 -/
theorem fok20 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 20 (src_grammar_part_4 45 46 47 48) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::grammar_part_5 -/
theorem fok21 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 21 (src_grammar_part_5 45 46 47 48) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::grammar_part_6 -/
theorem fok22 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 22 (src_grammar_part_6 45 46 47 48) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::grammar_part_7 -/
theorem fok23 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 23 (src_grammar_part_7 45 46 47 48) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::boxed<mini::selfhost::List<mini::selfhost::Rule>> -/
theorem fok43 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 43 (src_boxed_of_mini_selfhost_List_mini_selfhost_Rule 50 72 73) :=
  funcOk_prim (by decide +kernel)

/-- mini::selfhost::cons<mini::selfhost::Rule> -/
theorem fok45 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 45 (src_cons_of_mini_selfhost_Rule 43) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- core::panic::panic -/
theorem fok50 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 50 (src_core_panic_panic) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::unbox<mini::selfhost::List<mini::selfhost::Sig>> -/
theorem fok87 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 87 (src_unbox_of_mini_selfhost_List_mini_selfhost_Sig 132) :=
  funcOk_prim (by decide +kernel)

/-- mini::selfhost::empty<u8> -/
theorem fok110 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 110 (src_empty_of_u8) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::validate -/
theorem fok114 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 114 (src_validate 169) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::empty<usize> -/
theorem fok139 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 139 (src_empty_of_usize) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- ?<mini::selfhost::Decls> -/
theorem fok161 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 161 (src_field_fns_Decls_of_mini_selfhost_Decls) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::funcs_agree -/
theorem fok169 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 169 (src_funcs_agree 169 283 284) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::lower_set_index_any -/
theorem fok219 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 219 (src_lower_set_index_any 75 190 191 202 211 228 343 345 346 348 349) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::lower_set_index_eval -/
theorem fok228 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 228 (src_lower_set_index_eval 380 381 382) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::lower_assert -/
theorem fok231 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 231 (src_lower_assert 188 350) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::lower_str -/
theorem fok237 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 237 (src_lower_str 52 105 188 397 398 399 400) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::mono_loop -/
theorem fok270 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 270 (src_mono_loop 56 271 442 443 444 445) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::agrees -/
theorem fok284 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 284 (src_Func_agrees 282 470) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::unbox<mini::selfhost::SrcExpr> -/
theorem fok313 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 313 (src_unbox_of_mini_selfhost_SrcExpr 497) :=
  funcOk_prim (by decide +kernel)

/-- mini::selfhost::apply_guard -/
theorem fok314 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 314 (src_apply_guard 211 498 499 500 501) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::get<mini::selfhost::Sig> -/
theorem fok324 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 324 (src_get_of_mini_selfhost_Sig 56 87 324) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::length<mini::selfhost::List<mini::selfhost::SrcType>> -/
theorem fok385 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 385 (src_length_of_mini_selfhost_List_mini_selfhost_SrcType 75 183 385) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::str_stores -/
theorem fok400 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 400 (src_str_stores 75 188 337 400 575) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::type_table_more -/
theorem fok438 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 438 (src_type_table_more 665 666) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::type_table -/
theorem fok439 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 439 (src_type_table 666 667 668) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::seed_tys -/
theorem fok440 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 440 (src_seed_tys 440 448 669 670 671) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::funcs_tys -/
theorem fok441 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 441 (src_funcs_tys 441 448 672 673 674 675 676) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::funcs_onto -/
theorem fok445 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 445 (src_funcs_onto 445 676 679) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::concat<mini::selfhost::ImportDecl> -/
theorem fok455 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 455 (src_concat_of_mini_selfhost_ImportDecl 455 689 690) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::agrees -/
theorem fok470 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 470 (src_Stmt_agrees 307 464 469 470 699 706 707 708 709 710 711 712 713 714 715 716 717 718 719 720 721 722 723 724 725 726 727 728) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::id_absent -/
theorem fok490 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 490 (src_id_absent 76 490) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::cons<mini::selfhost::SrcEnumDecl> -/
theorem fok586 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 586 (src_cons_of_mini_selfhost_SrcEnumDecl 828) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::lowered_all -/
theorem fok657 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 657 (src_lowered_all 56 657 671 958 959 960) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::weigh_rounds -/
theorem fok662 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 662 (src_weigh_rounds 56 970 971) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::unweighed -/
theorem fok664 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 664 (src_unweighed 664 671 972 973) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::param_tys -/
theorem fok673 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 673 (src_param_tys 448 669 673 982) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::ret_tys -/
theorem fok674 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 674 (src_ret_tys 448 975) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::stmt_tys -/
theorem fok675 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 675 (src_stmt_tys 448 669 672 675 975 983 984 985) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::unbox<mini::selfhost::List<mini::selfhost::ImportDecl>> -/
theorem fok690 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 690 (src_unbox_of_mini_selfhost_List_mini_selfhost_ImportDecl 1007) :=
  funcOk_prim (by decide +kernel)

/-- mini::selfhost::literal -/
theorem fok702 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 702 (src_Expr_literal) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::is_none_weight -/
theorem fok968 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 968 (src_is_none_weight) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::weigh_round -/
theorem fok971 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 971 (src_weigh_round 671 972 1219) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::ty_known -/
theorem fok974 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 974 (src_ty_known 666 974 977 1221) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::single<mini::selfhost::Inst> -/
theorem fok988 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 988 (src_single_of_mini_selfhost_Inst 684) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::unbox<mini::selfhost::List<mini::selfhost::Fact>> -/
theorem fok1017 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1017 (src_unbox_of_mini_selfhost_List_mini_selfhost_Fact 1261) :=
  funcOk_prim (by decide +kernel)

/-- mini::selfhost::kills -/
theorem fok1020 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1020 (src_Stmt_kills 307 1020 1263 1268 1269 1270) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::get<mini::selfhost::Rule> -/
theorem fok1118 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1118 (src_get_of_mini_selfhost_Rule 44 56 1118) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::concat<mini::selfhost::CTree> -/
theorem fok1120 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1120 (src_concat_of_mini_selfhost_CTree 103 254 1120) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::empty<mini::selfhost::SrcParam> -/
theorem fok1150 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1150 (src_empty_of_mini_selfhost_SrcParam) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::boxed<mini::selfhost::SrcStmt> -/
theorem fok1202 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1202 (src_boxed_of_mini_selfhost_SrcStmt 50 112 1434) :=
  funcOk_prim (by decide +kernel)

/-- mini::selfhost::weighed_more -/
theorem fok1218 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1218 (src_weighed_more 969 1453) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::unbox<mini::selfhost::List<mini::selfhost::MEff>> -/
theorem fok1228 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1228 (src_unbox_of_mini_selfhost_List_mini_selfhost_MEff 1459) :=
  funcOk_prim (by decide +kernel)

/-- mini::selfhost::length<mini::selfhost::Ty> -/
theorem fok1234 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1234 (src_length_of_mini_selfhost_Ty 75 666 1234) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::lim_nums_arms -/
theorem fok1418 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1418 (src_lim_nums_arms 1066 1416 1418 1420) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::weigh_again -/
theorem fok1454 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1454 (src_weigh_again 1586) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::usize_width -/
theorem fok1521 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1521 (src_usize_width) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::lx_fixed -/
theorem fok1529 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1529 (src_lx_fixed 593 1115 1645 1646) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::generic_close -/
theorem fok1531 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1531 (src_generic_close 167 1647) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::inst_weight -/
theorem fok1586 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1586 (src_inst_weight 1185 1670) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::empty<mini::selfhost::List<mini::selfhost::Ty>> -/
theorem fok1655 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1655 (src_empty_of_mini_selfhost_List_mini_selfhost_Ty) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::decl_weight -/
theorem fok1670 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1670 (src_decl_weight 1251 1393 1739 1740) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::p_contracts_none -/
theorem fok1702 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1702 (src_p_contracts_none) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::p_contracts_more -/
theorem fok1703 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1703 (src_p_contracts_more) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::p_requires -/
theorem fok1704 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1704 (src_p_requires) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::packed_width -/
theorem fok1711 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1711 (src_packed_width 235) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::payloads_weight -/
theorem fok1739 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1739 (src_payloads_weight 1547 1589 1783) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::fields_weight -/
theorem fok1740 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1740 (src_fields_weight 1547 1783) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::concat<mini::selfhost::BoundGoal> -/
theorem fok1760 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1760 (src_concat_of_mini_selfhost_BoundGoal 1692 1760 1793) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::element_stores -/
theorem fok1770 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1770 (src_element_stores 56 75 188 1770 1843) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::block_at -/
theorem fok1771 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1771 (src_block_at 337) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::element_loads -/
theorem fok1772 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1772 (src_element_loads 56 75 188 1772 1844) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::cons<mini::selfhost::List<mini::selfhost::Ty>> -/
theorem fok1782 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1782 (src_cons_of_mini_selfhost_List_mini_selfhost_Ty 1848) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::tys_weight -/
theorem fok1783 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1783 (src_tys_weight 666 1659 1783 1849) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::block_store -/
theorem fok1843 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1843 (src_block_store 1771) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::block_load -/
theorem fok1844 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1844 (src_block_load 1771) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::boxed<mini::selfhost::List<mini::selfhost::List<mini::selfhost::Ty>>> -/
theorem fok1848 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1848 (src_boxed_of_mini_selfhost_List_mini_selfhost_List_mini_selfhost_Ty 50 1654 1951) :=
  funcOk_prim (by decide +kernel)

/-- mini::selfhost::ty_weight -/
theorem fok1849 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1849 (src_ty_weight 666 977 1156 1547 1550 1849 1952) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::p_else_none -/
theorem fok1939 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1939 (src_p_else_none) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::named_weight -/
theorem fok1952 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1952 (src_named_weight 2080) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::wide_marker -/
theorem fok1995 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1995 (src_wide_marker 1428) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::p_div_tail -/
theorem fok2000 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 2000 (src_p_div_tail) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::path_ref -/
theorem fok2013 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 2013 (src_path_ref 56 96 153 155 156 627 628 645 646 647 648 1355 2013 2118 2119) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::cons<mini::selfhost::BoundGoal> -/
theorem fok2089 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 2089 (src_cons_of_mini_selfhost_BoundGoal 1793) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::cons<mini::selfhost::VariantAt> -/
theorem fok2138 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 2138 (src_cons_of_mini_selfhost_VariantAt 2260) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::string_return -/
theorem fok2161 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 2161 (src_string_return 153 156 1928 1929 2281 2282) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::single<mini::selfhost::Token> -/
theorem fok2221 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 2221 (src_single_of_mini_selfhost_Token 1113) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::struct_head -/
theorem fok2303 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 2303 (src_struct_head) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::concat<mini::selfhost::VariantAt> -/
theorem fok2407 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 2407 (src_concat_of_mini_selfhost_VariantAt 2139 2260 2407) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::concat<mini::selfhost::MEff> -/
theorem fok2485 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 2485 (src_concat_of_mini_selfhost_MEff 1228 1242 2485) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::get<mini::selfhost::CTree> -/
theorem fok2642 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 2642 (src_get_of_mini_selfhost_CTree 56 103 2642) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

end Lanius.Faithful.SelfPure
