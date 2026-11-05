module

public import Lanius.Faithful.Gen.SelfPureTab
public import Lanius.Faithful.Gen.SelfSrcC_evalDivideSint
public import Lanius.Faithful.Gen.SelfSrcF_Inline_pArrayAfterCommaTrailing
public import Lanius.Faithful.Gen.SelfSrcF_Inline_pEnumTypeParam
public import Lanius.Faithful.Gen.SelfSrcF_Inline_pSelfValue
public import Lanius.Faithful.Gen.SelfSrcF_blockArmsOf
public import Lanius.Faithful.Gen.SelfSrcF_consTreeTail
public import Lanius.Faithful.Gen.SelfSrcF_nullConst
public import Lanius.Faithful.Gen.SelfSrcF_paramGoals
public import Lanius.Faithful.Gen.SelfSrcF_variantLetHead
import all Lanius.Faithful.Gen.SelfPureTab
import all Lanius.Faithful.Gen.SelfSrcC_evalDivideSint
import all Lanius.Faithful.Gen.SelfSrcF_Inline_pArrayAfterCommaTrailing
import all Lanius.Faithful.Gen.SelfSrcF_Inline_pEnumTypeParam
import all Lanius.Faithful.Gen.SelfSrcF_Inline_pSelfValue
import all Lanius.Faithful.Gen.SelfSrcF_blockArmsOf
import all Lanius.Faithful.Gen.SelfSrcF_consTreeTail
import all Lanius.Faithful.Gen.SelfSrcF_nullConst
import all Lanius.Faithful.Gen.SelfSrcF_paramGoals
import all Lanius.Faithful.Gen.SelfSrcF_variantLetHead
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

/-- mini::selfhost::eval_divide_sint -/
theorem fok809 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 809 (src_eval_divide_sint 75 188 312 394 808 1083 1085) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::p_stmts_end -/
theorem fok850 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 850 (src_p_stmts_end) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::p_enum_variants_none -/
theorem fok875 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 875 (src_p_enum_variants_none) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::p_enum_variants_some -/
theorem fok876 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 876 (src_p_enum_variants_some) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::p_enum_variants_more -/
theorem fok877 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 877 (src_p_enum_variants_more) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::p_enum_variants_end -/
theorem fok878 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 878 (src_p_enum_variants_end) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::p_enum_variants_after_comma_more -/
theorem fok879 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 879 (src_p_enum_variants_after_comma_more) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::p_enum_variants_after_comma_trailing -/
theorem fok880 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 880 (src_p_enum_variants_after_comma_trailing) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::p_enum_variant_fields_none -/
theorem fok881 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 881 (src_p_enum_variant_fields_none) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::p_enum_variant_fields_some -/
theorem fok882 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 882 (src_p_enum_variant_fields_some) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::p_enum_variant_fields_more -/
theorem fok883 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 883 (src_p_enum_variant_fields_more) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::p_enum_variant_fields_end -/
theorem fok884 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 884 (src_p_enum_variant_fields_end) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::p_enum_variant_fields_after_comma_more -/
theorem fok885 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 885 (src_p_enum_variant_fields_after_comma_more) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::p_enum_variant_fields_after_comma_trailing -/
theorem fok886 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 886 (src_p_enum_variant_fields_after_comma_trailing) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::p_enum_type_params_some -/
theorem fok899 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 899 (src_p_enum_type_params_some) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::p_enum_type_params_more -/
theorem fok900 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 900 (src_p_enum_type_params_more) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::p_enum_type_params_after_comma_more -/
theorem fok901 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 901 (src_p_enum_type_params_after_comma_more) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::p_array_end -/
theorem fok916 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 916 (src_p_array_end) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::p_array_after_comma_trailing -/
theorem fok918 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 918 (src_p_array_after_comma_trailing) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::fn_bounds_ok -/
theorem fok1245 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1245 (src_fn_bounds_ok 156 1473 1474 1475) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::p_enum_variant_unit -/
theorem fok1359 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1359 (src_p_enum_variant_unit) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::p_enum_type_param -/
theorem fok1360 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1360 (src_p_enum_type_param) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::goals_hold -/
theorem fok1473 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1473 (src_goals_hold 56 1611) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::item_goals -/
theorem fok1474 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1474 (src_item_goals 155 1612 1613 1614) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::impl_where -/
theorem fok1475 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1475 (src_impl_where 153 156 631) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::pattern_of -/
theorem fok1596 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1596 (src_pattern_of 153 156 1592 1593 1594 1673 1674) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::all_hold -/
theorem fok1611 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1611 (src_all_hold 56 1611 1691 1692) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::join_goals -/
theorem fok1612 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1612 (src_join_goals 1693) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::params_goals -/
theorem fok1613 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1613 (src_params_goals 103 1612 1613 1694 1695) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::where_goals -/
theorem fok1614 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1614 (src_where_goals 153 155 1694 1696 1697) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::sint_wide -/
theorem fok1664 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1664 (src_sint_wide) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::trait_holds -/
theorem fok1691 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1691 (src_trait_holds 56 1758) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::join_goals_tail -/
theorem fok1693 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1693 (src_join_goals_tail 1760) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::param_goals -/
theorem fok1695 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1695 (src_param_goals 153 155 156 627 628 1694 1761 1762) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::preds_goals -/
theorem fok1697 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1697 (src_preds_goals 103 155 156 627 628 1612 1694 1697 1762) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::sint_fits -/
theorem fok1738 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1738 (src_sint_fits) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::any_impl -/
theorem fok1758 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1758 (src_any_impl 56 693 1758 1792) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::bound_goals -/
theorem fok1762 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1762 (src_bound_goals 1794) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::impl_gives -/
theorem fok1792 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1792 (src_impl_gives 56 1484 1853 1854) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::goals_of -/
theorem fok1794 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1794 (src_goals_of 103 1694 1747 1794 1856 1857 1858) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::p_self_value -/
theorem fok1818 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1818 (src_p_self_value) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::p_array_lit -/
theorem fok1837 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1837 (src_p_array_lit) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::impl_args -/
theorem fok1853 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1853 (src_impl_args 155 156 265 448 1484 1954 1955 1956 1957 1958) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::impl_fits -/
theorem fok1854 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1854 (src_impl_fits 56 156 1468 1473 1474 1959 1960 1961) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::cons_goal -/
theorem fok1856 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1856 (src_cons_goal 1962) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::goal_at -/
theorem fok1857 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1857 (src_goal_at) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::trait_of_bound -/
theorem fok1858 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1858 (src_trait_of_bound 153 155 156 1963 1964 1965 1966) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::p_equality -/
theorem fok1866 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1866 (src_p_equality) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::p_shift -/
theorem fok1868 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1868 (src_p_shift) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::is_lit_init -/
theorem fok1916 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1916 (src_is_lit_init 1930 2049 2050) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::is_block_match -/
theorem fok1918 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1918 (src_is_block_match 155 156 1930 2051) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::is_lit_stmt -/
theorem fok1944 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1944 (src_is_lit_stmt 1945 2049) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::bound_or_none -/
theorem fok1956 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1956 (src_bound_or_none 2085) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::trait_is -/
theorem fok1959 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1959 (src_trait_is 2088) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::trait_of_ty -/
theorem fok1960 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1960 (src_trait_of_ty 153 155 156 1606 1609 1964 1966) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::ty_is -/
theorem fok1961 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1961 (src_ty_is 1671) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::cons_goal_tail -/
theorem fok1962 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1962 (src_cons_goal_tail 2089) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::trait_at -/
theorem fok1964 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1964 (src_trait_at 1750 2090) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::bound_path_spellings -/
theorem fok1965 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1965 (src_bound_path_spellings 56 153 156 627 628 647 649 1965 2091 2092 2093) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::args_of_items -/
theorem fok1966 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1966 (src_args_of_items 1690) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::p_eq_tail -/
theorem fok1973 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1973 (src_p_eq_tail) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::p_shl_tail -/
theorem fok1979 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1979 (src_p_shl_tail) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::p_shr_tail -/
theorem fok1980 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1980 (src_p_shr_tail) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::find_method -/
theorem fok2018 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 2018 (src_find_method 274 2126) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::lit_first -/
theorem fok2049 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 2049 (src_lit_first 153 156 888 2162) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::lit_wanted -/
theorem fok2050 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 2050 (src_lit_wanted 155 156 2163) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::block_arms_of -/
theorem fok2051 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 2051 (src_block_arms_of 2164 2165) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::lit_match_parts -/
theorem fok2067 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 2067 (src_lit_match_parts 156 1706 2034 2183) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::same_trait -/
theorem fok2088 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 2088 (src_same_trait 934 939 1587) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::trait_split -/
theorem fok2090 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 2090 (src_trait_split 1752) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::lit_pattern -/
theorem fok2162 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 2162 (src_lit_pattern 153 2283 2284 2285) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::any_block_arm -/
theorem fok2163 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 2163 (src_any_block_arm 103 2163 2286) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::lit_match_typed -/
theorem fok2183 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 2183 (src_lit_match_typed 56 628 1233 2155 2314) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::lit_end -/
theorem fok2184 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 2184 (src_lit_end) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::impl_fit -/
theorem fok2250 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 2250 (src_impl_fit 1955 2402 2403) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::unique_found -/
theorem fok2251 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 2251 (src_unique_found) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::no_method -/
theorem fok2252 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 2252 (src_no_method 274 934 2250 2252 2404) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::variant_let_head -/
theorem fok2305 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 2305 (src_variant_let_head) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::pure_arms -/
theorem fok2307 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 2307 (src_pure_arms 558 1228 1441 1442 1887 2307) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::lit_match_head -/
theorem fok2314 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 2314 (src_lit_match_head 1595 2255 2438) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::lit_last -/
theorem fok2316 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 2316 (src_lit_last) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::lit_cond -/
theorem fok2319 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 2319 (src_lit_cond 153 627 628 1428 1671 1822 2283 2284 2285 2440) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::null_const -/
theorem fok2353 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 2353 (src_null_const) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::sint_const -/
theorem fok2354 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 2354 (src_sint_const 1428 1738) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::neg_sint_const -/
theorem fok2357 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 2357 (src_neg_sint_const 2354) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::explicit_inst -/
theorem fok2390 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 2390 (src_explicit_inst 368 446 1234 1690 2481) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::param_patterns -/
theorem fok2397 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 2397 (src_param_patterns 155 156 2487) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::fit_ty -/
theorem fok2402 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 2402 (src_fit_ty 56 153 155 156 1600 1601 1606 1609 2083 2402 2495) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::callee_env -/
theorem fok2403 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 2403 (src_callee_env 265 448 1484) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::is_misfit -/
theorem fok2404 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 2404 (src_is_misfit) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::ret_pattern -/
theorem fok2409 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 2409 (src_ret_pattern 153 156 1465) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::lit_head_if -/
theorem fok2438 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 2438 (src_lit_head_if) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::eq_lit -/
theorem fok2440 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 2440 (src_eq_lit 1428) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::explicit_checked -/
theorem fok2481 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 2481 (src_explicit_checked) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::patterns_of -/
theorem fok2487 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 2487 (src_patterns_of 96 103 1596 2487 2531) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::fit_path -/
theorem fok2495 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 2495 (src_fit_path 56 2534) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::infer_inst -/
theorem fok2529 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 2529 (src_infer_inst 446 448 941 2258 2397 2403 2571) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::cons_tree -/
theorem fok2531 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 2531 (src_cons_tree 2572) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::inst_from -/
theorem fok2532 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 2532 (src_inst_from) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::fit_named -/
theorem fok2534 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 2534 (src_fit_named 56 1671 1688 2035 2342 2343 2344 2573 2574 2575) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::infer_ret -/
theorem fok2571 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 2571 (src_infer_ret 1954 1956 2403 2409 2532) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::cons_tree_tail -/
theorem fok2572 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 2572 (src_cons_tree_tail 148) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::fit_of -/
theorem fok2573 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 2573 (src_fit_of) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::fit_if -/
theorem fok2574 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 2574 (src_fit_if) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::fit_decl -/
theorem fok2575 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 2575 (src_fit_decl 56 2602) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::fit_same_decl -/
theorem fok2602 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 2602 (src_fit_same_decl 56 2620) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::fit_args -/
theorem fok2620 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 2620 (src_fit_args 56 103 666 2628 2629) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::fit_args_next -/
theorem fok2628 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 2628 (src_fit_args_next 56 2620) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::fit_arg -/
theorem fok2629 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 2629 (src_fit_arg 56 153 156 1791 2402) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

end Lanius.Faithful.SelfPure
