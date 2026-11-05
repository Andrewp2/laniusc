module

public import Lanius.Faithful.Gen.SelfPureTab
public import Lanius.Faithful.Gen.SelfSrcC_Inline_blockLeft
public import Lanius.Faithful.Gen.SelfSrcC_UintTy_half
public import Lanius.Faithful.Gen.SelfSrcC_arithUint
public import Lanius.Faithful.Gen.SelfSrcC_codeSize
public import Lanius.Faithful.Gen.SelfSrcC_declareFuncs
public import Lanius.Faithful.Gen.SelfSrcC_enumVariants
public import Lanius.Faithful.Gen.SelfSrcC_evalSlotLimit
public import Lanius.Faithful.Gen.SelfSrcC_lowerLocal
public import Lanius.Faithful.Gen.SelfSrcC_packRound
public import Lanius.Faithful.Gen.SelfSrcC_render
public import Lanius.Faithful.Gen.SelfSrcF_Inline_attachParent
public import Lanius.Faithful.Gen.SelfSrcF_Inline_findMethodAt
public import Lanius.Faithful.Gen.SelfSrcF_Inline_pAndTail
public import Lanius.Faithful.Gen.SelfSrcF_Inline_pArgsMore
public import Lanius.Faithful.Gen.SelfSrcF_Inline_variantsNamedAt
public import Lanius.Faithful.Gen.SelfSrcF_basedDigits
public import Lanius.Faithful.Gen.SelfSrcF_litEffMatch
public import Lanius.Faithful.Gen.SelfSrcF_matchTysOrNone
public import Lanius.Faithful.Gen.SelfSrcF_tryLet
public import Lanius.Faithful.Gen.SelfSrcF_viewHead
import all Lanius.Faithful.Gen.SelfPureTab
import all Lanius.Faithful.Gen.SelfSrcC_Inline_blockLeft
import all Lanius.Faithful.Gen.SelfSrcC_UintTy_half
import all Lanius.Faithful.Gen.SelfSrcC_arithUint
import all Lanius.Faithful.Gen.SelfSrcC_codeSize
import all Lanius.Faithful.Gen.SelfSrcC_declareFuncs
import all Lanius.Faithful.Gen.SelfSrcC_enumVariants
import all Lanius.Faithful.Gen.SelfSrcC_evalSlotLimit
import all Lanius.Faithful.Gen.SelfSrcC_lowerLocal
import all Lanius.Faithful.Gen.SelfSrcC_packRound
import all Lanius.Faithful.Gen.SelfSrcC_render
import all Lanius.Faithful.Gen.SelfSrcF_Inline_attachParent
import all Lanius.Faithful.Gen.SelfSrcF_Inline_findMethodAt
import all Lanius.Faithful.Gen.SelfSrcF_Inline_pAndTail
import all Lanius.Faithful.Gen.SelfSrcF_Inline_pArgsMore
import all Lanius.Faithful.Gen.SelfSrcF_Inline_variantsNamedAt
import all Lanius.Faithful.Gen.SelfSrcF_basedDigits
import all Lanius.Faithful.Gen.SelfSrcF_litEffMatch
import all Lanius.Faithful.Gen.SelfSrcF_matchTysOrNone
import all Lanius.Faithful.Gen.SelfSrcF_tryLet
import all Lanius.Faithful.Gen.SelfSrcF_viewHead
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

/-- mini::selfhost::compile_words -/
theorem fok6 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 6 (src_compile_words 11 12) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::binary_words -/
theorem fok11 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 11 (src_binary_words 35 36) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::image_words -/
theorem fok35 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 35 (src_image_words 9 51 52 53) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::pack_rounds -/
theorem fok36 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 36 (src_pack_rounds 36 54 55 56) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::pack_round -/
theorem fok54 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 54 (src_pack_round 5 54 56 77 78 79 80) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::round_join -/
theorem fok55 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 55 (src_round_join 51 75) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::is_unit -/
theorem fok57 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 57 (src_SrcType_is_unit) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::declare_funcs -/
theorem fok63 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 63 (src_declare_funcs 59 90 91) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::declare_funcs_after -/
theorem fok90 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 90 (src_declare_funcs_after 63) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::declare_in -/
theorem fok142 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 142 (src_declare_in 244) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::block_left -/
theorem fok178 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 178 (src_block_left 56 177) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::lookup -/
theorem fok202 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 202 (src_lookup 328 329) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::declare_params_after -/
theorem fok243 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 243 (src_declare_params_after 141) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::attach_sym -/
theorem fok255 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 255 (src_attach_sym 420 421) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::is_scalar -/
theorem fok317 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 317 (src_SrcType_is_scalar) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::is_i32 -/
theorem fok338 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 338 (src_SrcType_is_i32) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::is_uint -/
theorem fok339 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 339 (src_SrcType_is_uint 524) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::is_bool -/
theorem fok387 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 387 (src_SrcType_is_bool) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::is_ptr -/
theorem fok390 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 390 (src_SrcType_is_ptr) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::is_isize -/
theorem fok391 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 391 (src_SrcType_is_isize) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::is_char -/
theorem fok392 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 392 (src_SrcType_is_char) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::is_float -/
theorem fok393 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 393 (src_SrcType_is_float 574) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::is_sint -/
theorem fok394 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 394 (src_SrcType_is_sint 524) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::is_str -/
theorem fok395 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 395 (src_SrcType_is_str) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::declare_struct_in -/
theorem fok406 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 406 (src_declare_struct_in 388 582 583) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::declare_types_after -/
theorem fok408 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 408 (src_declare_types_after 246) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::declare_enum_in -/
theorem fok409 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 409 (src_declare_enum_in 389 582 586) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::enum_variants -/
theorem fok410 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 410 (src_enum_variants 587 588) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::declare_variants_after -/
theorem fok411 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 411 (src_declare_variants_after 248) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::attach_nonterm -/
theorem fok421 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 421 (src_attach_nonterm 76 603) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::mono_next -/
theorem fok443 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 443 (src_mono_next 75 270 677 678 679) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::code_size -/
theorem fok480 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 480 (src_code_size 75 480 741 749) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::bool_bits -/
theorem fok502 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 502 (src_bool_bits) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::lower_unsigned -/
theorem fok503 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 503 (src_lower_unsigned 760) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::lower_local -/
theorem fok504 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 504 (src_lower_local 761) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::lower_field -/
theorem fok505 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 505 (src_lower_field 762) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::lower_negate -/
theorem fok506 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 506 (src_lower_negate 551) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::lower_not -/
theorem fok507 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 507 (src_lower_not 552) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::code -/
theorem fok524 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 524 (src_UintTy_code) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::eval_slot_limit -/
theorem fok545 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 545 (src_eval_slot_limit) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::lower_negate_typed -/
theorem fok551 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 551 (src_lower_negate_typed 337 338 391 800 801 802 803 804) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::lower_not_typed -/
theorem fok552 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 552 (src_lower_not_typed 337 387) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::attach_leaf -/
theorem fok602 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 602 (src_attach_leaf 149 834 841 842 843 844 845) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::attach_parent -/
theorem fok603 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 603 (src_attach_parent 76 846) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::type_table_more_at -/
theorem fok665 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 665 (src_type_table_more_at 438 439 974 975) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::type_table_next -/
theorem fok667 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 667 (src_type_table_next 439 677) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::compile_expr -/
theorem fok742 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 742 (src_compile_expr 75 478 492 742 743) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::lower_field_of -/
theorem fok762 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 762 (src_lower_field_of 75 181 520 521 1050) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::is_float_any -/
theorem fok800 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 800 (src_SrcType_is_float_any) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::negate_float -/
theorem fok801 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 801 (src_negate_float 337 1081 1082) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::float_ty -/
theorem fok802 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 802 (src_SrcType_float_ty) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::sint_kind -/
theorem fok803 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 803 (src_SrcType_sint_kind) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::negate_signed -/
theorem fok804 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 804 (src_negate_signed 337 1083 1084) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::uint_kind -/
theorem fok810 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 810 (src_SrcType_uint_kind) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::p_args_none -/
theorem fok857 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 857 (src_p_args_none) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::p_args_some -/
theorem fok858 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 858 (src_p_args_some) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::p_args_more -/
theorem fok859 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 859 (src_p_args_more) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::p_args_end -/
theorem fok860 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 860 (src_p_args_end) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::p_args_after_comma_more -/
theorem fok861 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 861 (src_p_args_after_comma_more) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::p_args_after_comma_trailing -/
theorem fok862 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 862 (src_p_args_after_comma_trailing) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::p_array_after_comma_more -/
theorem fok917 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 917 (src_p_array_after_comma_more) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::weigh_next -/
theorem fok970 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 970 (src_weigh_next 662 1218) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::lower_field_at -/
theorem fok1050 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1050 (src_lower_field_at 1303) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::weigh_round_at -/
theorem fok1219 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1219 (src_weigh_round_at 969 971 972 973 1454) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::neg_agrees -/
theorem fok1272 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1272 (src_neg_agrees 492 1021) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::binary_agrees -/
theorem fok1273 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1273 (src_binary_agrees 492 1021 1028 1494) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::unit_agrees -/
theorem fok1274 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1274 (src_unit_agrees 1021 1255 1258 1495) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::compare_agrees -/
theorem fok1275 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1275 (src_compare_agrees 492 1021 1028 1496) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::fp_agrees -/
theorem fok1276 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1276 (src_fp_agrees 492 1021 1497) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::is_sint_any -/
theorem fok1305 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1305 (src_SrcType_is_sint_any) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::arith_sint -/
theorem fok1306 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1306 (src_arith_sint 1513) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::arith_uint -/
theorem fok1307 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1307 (src_arith_uint 1514) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::is_integer -/
theorem fok1308 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1308 (src_SrcType_is_integer) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::word -/
theorem fok1313 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1313 (src_SrcType_word 1322) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::sint_to_i32 -/
theorem fok1315 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1315 (src_sint_to_i32 1083 1314) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::from_i32 -/
theorem fok1316 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1316 (src_from_i32 337 1083 1314) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::signed_word -/
theorem fok1322 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1322 (src_UintTy_signed_word 1083) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::spare -/
theorem fok1332 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1332 (src_UintTy_spare) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::least_bits -/
theorem fok1333 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1333 (src_UintTy_least_bits) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::lx_quoted_at -/
theorem fok1341 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1341 (src_lx_quoted_at 75 1107) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::ty_local_at -/
theorem fok1445 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1445 (src_ty_local_at 1210) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::weighed_more_at -/
theorem fok1453 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1453 (src_weighed_more_at 968 969 1218) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::param_of -/
theorem fok1463 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1463 (src_param_of 56 153 1142 1236 1591 1592 1593 1594 1595 1596 1597 1598 1599) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::lx_ident_run_at -/
theorem fok1522 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1522 (src_lx_ident_run_at 75 1336 1639) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::lx_digit_run_at -/
theorem fok1525 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1525 (src_lx_digit_run_at 75 1640 1641) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::lx_space_run_at -/
theorem fok1527 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1527 (src_lx_space_run_at 75 1104 1340) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::float_op -/
theorem fok1636 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1636 (src_float_op) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::lx_digit_tail_at -/
theorem fok1713 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1713 (src_lx_digit_tail_at 75 76 1640 1641 1773) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::decimal_digit -/
theorem fok1745 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1745 (src_decimal_digit 56 75 105 1682) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::lx_digit_sep -/
theorem fok1773 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1773 (src_lx_digit_sep 75 1640 1641) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::lx_exponent_sign -/
theorem fok1774 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1774 (src_lx_exponent_sign 75) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::int_literal -/
theorem fok1822 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1822 (src_int_literal 1879 1880) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::char_literal -/
theorem fok1826 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1826 (src_char_literal 76 1881) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::then_of -/
theorem fok1842 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1842 (src_then_of 1949) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::lx_line_run_at -/
theorem fok1846 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1846 (src_lx_line_run_at 75 1778) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::lx_block_at -/
theorem fok1847 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1847 (src_lx_block_at 75 1950) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::item_import_at -/
theorem fok1852 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1852 (src_item_import_at 939 1789 1953) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::p_andexpr -/
theorem fok1862 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1862 (src_p_andexpr) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::lit_value -/
theorem fok1879 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1879 (src_lit_value 76 1994) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::lit_sized -/
theorem fok1880 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1880 (src_lit_sized 1995) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::array_repeat_of -/
theorem fok1908 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1908 (src_array_repeat_of 1242 1887 1897 2041) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::array_of -/
theorem fok1909 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1909 (src_array_of 1242 1897 2042) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::let_head_or_eval -/
theorem fok1921 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1921 (src_let_head_or_eval 1706 2059 2060 2061) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::untyped_head -/
theorem fok1926 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1926 (src_untyped_head 1706 2062 2063 2064) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::then_rest -/
theorem fok1949 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1949 (src_then_rest 1241) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::lx_block_next -/
theorem fok1950 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1950 (src_lx_block_next 75 1779) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::p_and_tail -/
theorem fok1969 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1969 (src_p_and_tail) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::char_body -/
theorem fok1996 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1996 (src_char_body 76 2105) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::lit_eff_match -/
theorem fok2037 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 2037 (src_lit_eff_match 2155 2156 2157) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::literal_head -/
theorem fok2056 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 2056 (src_literal_head) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::untyped_try -/
theorem fok2063 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 2063 (src_untyped_try) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::untyped_eval -/
theorem fok2064 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 2064 (src_untyped_eval 2034 2175 2177 2178) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::for_of -/
theorem fok2074 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 2074 (src_for_of 56 153 156 627 628 1142 1233 1595 1599 1620 1798 1800 1822 1877 2083 2190 2191 2192 2193 2194 2195 2196 2197 2198 2199) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::lit_prefixed -/
theorem fok2102 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 2102 (src_lit_prefixed 2104 2224) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::lit_base -/
theorem fok2103 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 2103 (src_lit_base) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::find_method_at -/
theorem fok2126 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 2126 (src_find_method_at 75 934 2018 2250 2251 2252) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::variants_named_at -/
theorem fok2142 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 2142 (src_variants_named_at 75 939 1785 2029 2138) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::untyped_if -/
theorem fok2177 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 2177 (src_untyped_if) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::inferred -/
theorem fok2178 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 2178 (src_inferred 2312) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::is_ptr_ty -/
theorem fok2180 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 2180 (src_is_ptr_ty) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::try_let -/
theorem fok2182 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 2182 (src_try_let 1241 2313) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::try_stmt -/
theorem fok2213 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 2213 (src_try_stmt 2313) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::based_digits -/
theorem fok2224 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 2224 (src_based_digits 76 2359) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::wide_digit -/
theorem fok2225 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 2225 (src_wide_digit 56 75 105 2104) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::char_close -/
theorem fok2227 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 2227 (src_char_close 76 2362) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::char_tail -/
theorem fok2228 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 2228 (src_char_tail 76 2363) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::fl_add -/
theorem fok2229 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 2229 (src_fl_add 1883 2229 2235 2364 2365 2366 2367) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::fl_mul10 -/
theorem fok2230 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 2230 (src_fl_mul10 2229 2365) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::fl_times10 -/
theorem fok2238 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 2238 (src_fl_times10 56 2230 2238) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::imported_variants_at -/
theorem fok2259 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 2259 (src_imported_variants_at 939 2029 2137 2407) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::pure_inferred -/
theorem fok2312 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 2312 (src_pure_inferred) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::based_digit -/
theorem fok2359 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 2359 (src_based_digit 75 105 2224 2475 2476) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::char_close_opt -/
theorem fok2360 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 2360 (src_char_close_opt 2227) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::escaped_byte -/
theorem fok2361 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 2361 (src_escaped_byte) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::fl_carry_out -/
theorem fok2364 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 2364 (src_fl_carry_out 1883 2239) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::fl_xor -/
theorem fok2366 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 2366 (src_fl_xor) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::fl_carry -/
theorem fok2367 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 2367 (src_fl_carry) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::fl_shl -/
theorem fok2377 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 2377 (src_fl_shl 56 2365 2377) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::fl_less -/
theorem fok2379 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 2379 (src_fl_less 1883 2235 2379 2479) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::eff_inferred -/
theorem fok2398 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 2398 (src_eff_inferred 2483 2488) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::view_head -/
theorem fok2435 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 2435 (src_view_head 321) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::fl_borrow_bit -/
theorem fok2479 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 2479 (src_fl_borrow_bit) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::inst_bound -/
theorem fok2488 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 2488 (src_inst_bound 1956 2085 2256 2403 2532 2533) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::p_arm_block -/
theorem fok2507 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 2507 (src_p_arm_block) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::binder_of -/
theorem fok2515 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 2515 (src_binder_of 56 153 156 163 628 1142 1595 1599 1800 2425 2427 2428 2555 2556 2557) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::fl_sub -/
theorem fok2527 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 2527 (src_fl_sub 1883 2235 2365 2366 2479 2527) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::match_tys_or_none -/
theorem fok2533 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 2533 (src_match_tys_or_none 2258) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::string_byte -/
theorem fok2541 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 2541 (src_string_byte 2505 2580 2581 2582) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::diverge_eff -/
theorem fok2579 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 2579 (src_diverge_eff 2603) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::string_close -/
theorem fok2580 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 2580 (src_string_close 139) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::diverge_call -/
theorem fok2603 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 2603 (src_diverge_call 368 680 941 1234 1239 2621) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::diverge_checked -/
theorem fok2621 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 2621 (src_diverge_checked 672 975) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

end Lanius.Faithful.SelfPure
