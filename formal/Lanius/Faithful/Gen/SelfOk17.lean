module

public import Lanius.Faithful.Gen.SelfPureTab
public import Lanius.Faithful.Gen.SelfSrcC_DivOp_size
public import Lanius.Faithful.Gen.SelfSrcC_Word_compute
public import Lanius.Faithful.Gen.SelfSrcC_armScope
public import Lanius.Faithful.Gen.SelfSrcC_leftTrue
public import Lanius.Faithful.Gen.SelfSrcF_Inline_litValueAt
public import Lanius.Faithful.Gen.SelfSrcF_Inline_tRparen
public import Lanius.Faithful.Gen.SelfSrcF_distinct
public import Lanius.Faithful.Gen.SelfSrcF_eDivideClosed
public import Lanius.Faithful.Gen.SelfSrcF_fieldValue
public import Lanius.Faithful.Gen.SelfSrcF_fnInstRet
public import Lanius.Faithful.Gen.SelfSrcF_oneTreeNames
public import Lanius.Faithful.Gen.SelfSrcF_stringCons
public import Lanius.Faithful.Gen.SelfSrcF_treeTokens
import all Lanius.Faithful.Gen.SelfPureTab
import all Lanius.Faithful.Gen.SelfSrcC_DivOp_size
import all Lanius.Faithful.Gen.SelfSrcC_Word_compute
import all Lanius.Faithful.Gen.SelfSrcC_armScope
import all Lanius.Faithful.Gen.SelfSrcC_leftTrue
import all Lanius.Faithful.Gen.SelfSrcF_Inline_litValueAt
import all Lanius.Faithful.Gen.SelfSrcF_Inline_tRparen
import all Lanius.Faithful.Gen.SelfSrcF_distinct
import all Lanius.Faithful.Gen.SelfSrcF_eDivideClosed
import all Lanius.Faithful.Gen.SelfSrcF_fieldValue
import all Lanius.Faithful.Gen.SelfSrcF_fnInstRet
import all Lanius.Faithful.Gen.SelfSrcF_oneTreeNames
import all Lanius.Faithful.Gen.SelfSrcF_stringCons
import all Lanius.Faithful.Gen.SelfSrcF_treeTokens
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

/-- mini::selfhost::arm_scope -/
theorem fok375 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 375 (src_arm_scope 76 181 564) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::distinct_modules -/
theorem fok431 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 431 (src_distinct_modules 431 650 651) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::left_true -/
theorem fok501 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 501 (src_left_true) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::number -/
theorem fok574 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 574 (src_FloatTy_number) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::cons_name -/
theorem fok649 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 649 (src_cons_name 938) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::module_member -/
theorem fok650 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 650 (src_module_member 650 651 939) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::size -/
theorem fok749 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 749 (src_Instr_size 52 75 105 1036 1037 1038 1039 1040) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::mask -/
theorem fok765 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 765 (src_FloatTy_mask) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::t_shr -/
theorem fok842 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 842 (src_t_shr) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::cons_name_tail -/
theorem fok938 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 938 (src_cons_name_tail 1141) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::same_spellings -/
theorem fok939 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 939 (src_same_spellings 558 934 939) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::distinct -/
theorem fok940 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 940 (src_distinct 558 940 1142) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::test -/
theorem fok1015 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1015 (src_Word_test 1259 1260) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::size -/
theorem fok1039 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1039 (src_DivOp_size 75 1037) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::size -/
theorem fok1040 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1040 (src_FOp_size 75 105 1037 1280) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::sign_word -/
theorem fok1081 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1081 (src_FloatTy_sign_word) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::sign_bit -/
theorem fok1082 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1082 (src_FloatTy_sign_bit) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::compute -/
theorem fok1253 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1253 (src_Word_compute 1011 1485) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::same_operand -/
theorem fok1256 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1256 (src_Word_same_operand 1011) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::rex_size -/
theorem fok1280 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1280 (src_FloatTy_rex_size) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::e_neg_closed -/
theorem fok1375 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1375 (src_e_neg_closed 1449) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::e_not_closed -/
theorem fok1376 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1376 (src_e_not_closed 1449) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::e_cast_closed -/
theorem fok1377 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1377 (src_e_cast_closed 1449) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::e_divide_closed -/
theorem fok1382 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1382 (src_e_divide_closed 1449) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::t_rparen -/
theorem fok1727 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1727 (src_t_rparen) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::t_semicolon -/
theorem fok1730 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1730 (src_t_semicolon) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::single_name -/
theorem fok1746 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1746 (src_single_name 558) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::position -/
theorem fok1785 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1785 (src_position 558 1850) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::lit_value_at -/
theorem fok1994 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1994 (src_lit_value_at 76 2102 2103 2104) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::eff_ty -/
theorem fok2034 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 2034 (src_eff_ty 56 984 1229 1569 1851 2034 2143 2144 2145 2146 2147 2148 2149 2150 2151) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::head_ty -/
theorem fok2044 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 2044 (src_head_ty) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::tail_tys -/
theorem fok2045 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 2045 (src_tail_tys 666) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::tree_tokens -/
theorem fok2100 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 2100 (src_tree_tokens 103 2221 2222) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::step_expected -/
theorem fok2127 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 2127 (src_step_expected 153 1798) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::method_of_ty -/
theorem fok2128 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 2128 (src_method_of_ty 161 2018) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::field_of_ty -/
theorem fok2129 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 2129 (src_field_of_ty 1991 2253 2254) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::eff_slice_local -/
theorem fok2132 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 2132 (src_eff_slice_local 2149 2255) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::inst_ret -/
theorem fok2144 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 2144 (src_inst_ret 680 683 2266) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::bare_eff -/
theorem fok2147 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 2147 (src_bare_eff 1229 1567 1569 2147 2265) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::index_ty -/
theorem fok2148 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 2148 (src_index_ty 2267) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::field_ty_of -/
theorem fok2150 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 2150 (src_field_ty_of 2269) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::elem_ty_of -/
theorem fok2151 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 2151 (src_elem_ty_of 2267) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::x_match_of -/
theorem fok2152 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 2152 (src_x_match_of 1242 1888 2270 2271 2272) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::args_of -/
theorem fok2208 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 2208 (src_args_of 155 2338) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::trees_tokens -/
theorem fok2222 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 2222 (src_trees_tokens 103 596 2100 2222 2351) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::is_type_owner -/
theorem fok2243 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 2243 (src_is_type_owner 1688 1746 2387 2388) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::is_some_index -/
theorem fok2244 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 2244 (src_is_some_index) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::field_value -/
theorem fok2254 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 2254 (src_field_value 1242 1699 1888 2019 2130 2255 2405) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::effs_tys -/
theorem fok2256 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 2256 (src_effs_tys 448 1228 1621 2034 2256) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::fn_inst_ret -/
theorem fok2266 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 2266 (src_fn_inst_ret 941 993 1240 1468 1484 2409) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::field_ty_at -/
theorem fok2269 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 2269 (src_field_ty_at 999 1000) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::result_ty -/
theorem fok2270 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 2270 (src_result_ty) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::arm_binders -/
theorem fok2271 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 2271 (src_arm_binders 265 1141 2271 2410) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::arm_values -/
theorem fok2272 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 2272 (src_arm_values 1471 1472 2272 2410) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::exprs_of -/
theorem fok2338 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 2338 (src_exprs_of 103 1435 1766 2338 2463) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::is_scalar_owner -/
theorem fok2387 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 2387 (src_is_scalar_owner 653 654 1142) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::is_owner_at -/
theorem fok2388 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 2388 (src_is_owner_at 163 1142 1185) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::cons_eff_arm -/
theorem fok2413 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 2413 (src_cons_eff_arm 2498) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::cons_expr -/
theorem fok2463 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 2463 (src_cons_expr 2521) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::wide_i32 -/
theorem fok2470 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 2470 (src_wide_i32) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::wide_uint -/
theorem fok2471 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 2471 (src_wide_uint 2352) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::wide_isize -/
theorem fok2472 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 2472 (src_wide_isize 56 75 1428) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::wide_sint -/
theorem fok2473 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 2473 (src_wide_sint 56 75 1428 1664) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::string_body -/
theorem fok2505 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 2505 (src_string_body 76 2541) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::cons_expr_tail -/
theorem fok2521 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 2521 (src_cons_expr_tail 1436) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::string_args -/
theorem fok2543 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 2543 (src_string_args 103 2585 2586 2587 2588) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::string_cons -/
theorem fok2581 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 2581 (src_string_cons 418) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::plain_string_byte -/
theorem fok2582 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 2582 (src_plain_string_byte) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::string_slice -/
theorem fok2585 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 2585 (src_string_slice 1241) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::is_data_ptr_of -/
theorem fok2587 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 2587 (src_is_data_ptr_of 155 156 429 1795 1889 2005 2606 2607) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::int_tree -/
theorem fok2588 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 2588 (src_int_tree 156 1795 2608) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::one_tree_names -/
theorem fok2607 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 2607 (src_one_tree_names 103 1763 2586) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::int_primary -/
theorem fok2608 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 2608 (src_int_primary 153 627 628 1798 1821 1822) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

end Lanius.Faithful.SelfPure
