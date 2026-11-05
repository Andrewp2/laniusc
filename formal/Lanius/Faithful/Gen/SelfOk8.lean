module

public import Lanius.Faithful.Gen.SelfPureTab
public import Lanius.Faithful.Gen.SelfSrcC_binaryConstant
public import Lanius.Faithful.Gen.SelfSrcC_funcNeeds
public import Lanius.Faithful.Gen.SelfSrcC_larger
public import Lanius.Faithful.Gen.SelfSrcC_lowerShift
public import Lanius.Faithful.Gen.SelfSrcF_Inline_pStructFieldsMore
public import Lanius.Faithful.Gen.SelfSrcF_armsOf
public import Lanius.Faithful.Gen.SelfSrcF_basedLimit
public import Lanius.Faithful.Gen.SelfSrcF_checkedFunc
public import Lanius.Faithful.Gen.SelfSrcF_frontEndRead
public import Lanius.Faithful.Gen.SelfSrcF_isMatchStmt
public import Lanius.Faithful.Gen.SelfSrcF_letStructClosed
public import Lanius.Faithful.Gen.SelfSrcF_lowerTy
public import Lanius.Faithful.Gen.SelfSrcF_projectionRet
public import Lanius.Faithful.Gen.SelfSrcF_textSliceLen
import all Lanius.Faithful.Gen.SelfPureTab
import all Lanius.Faithful.Gen.SelfSrcC_binaryConstant
import all Lanius.Faithful.Gen.SelfSrcC_funcNeeds
import all Lanius.Faithful.Gen.SelfSrcC_larger
import all Lanius.Faithful.Gen.SelfSrcC_lowerShift
import all Lanius.Faithful.Gen.SelfSrcF_Inline_pStructFieldsMore
import all Lanius.Faithful.Gen.SelfSrcF_armsOf
import all Lanius.Faithful.Gen.SelfSrcF_basedLimit
import all Lanius.Faithful.Gen.SelfSrcF_checkedFunc
import all Lanius.Faithful.Gen.SelfSrcF_frontEndRead
import all Lanius.Faithful.Gen.SelfSrcF_isMatchStmt
import all Lanius.Faithful.Gen.SelfSrcF_letStructClosed
import all Lanius.Faithful.Gen.SelfSrcF_lowerTy
import all Lanius.Faithful.Gen.SelfSrcF_projectionRet
import all Lanius.Faithful.Gen.SelfSrcF_textSliceLen
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

/-- mini::selfhost::front_end_read -/
theorem fok14 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 14 (src_front_end_read 42) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::sigs -/
theorem fok62 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 62 (src_sigs 88 89) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::sigs_with -/
theorem fok88 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 88 (src_sigs_with 59 88 133 134 135 136 137) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::func_needs -/
theorem fok89 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 89 (src_func_needs 138 139 140) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::link -/
theorem fok172 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 172 (src_link 56 290 291 292 293) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::extent -/
theorem fok187 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 187 (src_Stmt_extent 75 186 187 306 307 308) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::link_fitting -/
theorem fok293 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 293 (src_link_fitting 486 487) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::extent -/
theorem fok306 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 306 (src_Expr_extent 75 186 306 492) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::args_extent -/
theorem fok308 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 308 (src_args_extent 186 306 308 493) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::lookup_at -/
theorem fok328 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 328 (src_lookup_at 202) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::room_next -/
theorem fok483 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 483 (src_room_next 56 292) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::p_type_alias -/
theorem fok636 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 636 (src_p_type_alias) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::p_trait -/
theorem fok644 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 644 (src_p_trait) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::projection_ret -/
theorem fok683 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 683 (src_projection_ret 56 998 999 1000) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::is_var -/
theorem fok694 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 694 (src_Expr_is_var) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::constant -/
theorem fok712 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 712 (src_Expr_constant 492 712 1022 1023 1024) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::is_zero -/
theorem fok714 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 714 (src_Expr_is_zero 712 1025) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::expr_then -/
theorem fok729 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 729 (src_expr_then 1031) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::stmt_then -/
theorem fok730 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 730 (src_stmt_then 472) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::args_then -/
theorem fok731 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 731 (src_args_then 1032) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::spend_then -/
theorem fok732 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 732 (src_spend_then 300) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::seq_code -/
theorem fok744 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 744 (src_seq_code 75 478 479 480) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::ite_code -/
theorem fok745 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 745 (src_ite_code 75 478 479 480 743) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::loop_code -/
theorem fok746 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 746 (src_loop_code 75 478 479 480 743) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::offset_after -/
theorem fok773 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 773 (src_offset_after 56 75 120 520) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::p_struct_fields_none -/
theorem fok863 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 863 (src_p_struct_fields_none) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::p_struct_fields_some -/
theorem fok864 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 864 (src_p_struct_fields_some) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::p_struct_fields_more -/
theorem fok865 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 865 (src_p_struct_fields_more) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::p_struct_lit_fields_none -/
theorem fok869 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 869 (src_p_struct_lit_fields_none) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::p_struct_lit_fields_some -/
theorem fok870 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 870 (src_p_struct_lit_fields_some) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::p_struct_lit_fields_more -/
theorem fok871 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 871 (src_p_struct_lit_fields_more) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::p_struct_lit_fields_end -/
theorem fok872 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 872 (src_p_struct_lit_fields_end) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::p_struct_lit_fields_after_comma_more -/
theorem fok873 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 873 (src_p_struct_lit_fields_after_comma_more) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::p_struct_lit_fields_after_comma_trailing -/
theorem fok874 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 874 (src_p_struct_lit_fields_after_comma_trailing) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::p_type_args_more -/
theorem fok903 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 903 (src_p_type_args_more) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::p_type_args_after_comma_more -/
theorem fok904 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 904 (src_p_type_args_after_comma_more) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::lower_named -/
theorem fok960 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 960 (src_lower_named 56 1156 1185 1186) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::diverges -/
theorem fok993 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 993 (src_diverges 75 368 941 1234 1239) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::init_tys -/
theorem fok996 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 996 (src_init_tys 448 666 669 996) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::binary_constant -/
theorem fok1023 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1023 (src_binary_constant 1277 1278) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::compare_constant -/
theorem fok1024 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1024 (src_compare_constant 502 1015) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::constant_is -/
theorem fok1025 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1025 (src_constant_is) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::lower_shift -/
theorem fok1053 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1053 (src_lower_shift 1052 1308) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::let_struct_closed -/
theorem fok1154 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1154 (src_let_struct_closed 1202) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::let_call_closed -/
theorem fok1155 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1155 (src_let_call_closed 1202) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::let_enum_closed -/
theorem fok1157 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1157 (src_let_enum_closed 1202) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::let_match_closed -/
theorem fok1158 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1158 (src_let_match_closed 1202) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::set_call_closed -/
theorem fok1160 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1160 (src_set_call_closed) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::then_closed -/
theorem fok1161 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1161 (src_then_closed 1202) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::if_closed -/
theorem fok1162 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1162 (src_if_closed 1202) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::while_closed -/
theorem fok1163 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1163 (src_while_closed 1202) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::match_arm_closed -/
theorem fok1179 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1179 (src_match_arm_closed 1202) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::arm_ty_closed -/
theorem fok1180 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1180 (src_arm_ty_closed) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::unreachable_closed -/
theorem fok1181 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1181 (src_unreachable_closed) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::lower_decl -/
theorem fok1186 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1186 (src_lower_decl 56 1251 1391 1392 1393 1394 1395) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::never_ret -/
theorem fok1239 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1239 (src_never_ret 153 156 1465 1466) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::last_ty -/
theorem fok1240 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1240 (src_last_ty 666 1240) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::is_constant -/
theorem fok1271 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1271 (src_Expr_is_constant 1025) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::lower_variants -/
theorem fok1392 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1392 (src_lower_variants 56 559 1392 1395 1540 1541) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::lower_tys -/
theorem fok1395 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1395 (src_lower_tys 56 239 666 1395 1543 1544) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::checked_func -/
theorem fok1476 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1476 (src_checked_func) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::unit_of -/
theorem fok1495 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1495 (src_Expr_unit_of 712 1256 1257) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::lower_ty -/
theorem fok1544 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1544 (src_lower_ty 56 666 960 977 1367 1369 1370 1544) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::and_known -/
theorem fok1700 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1700 (src_and_known) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::p_true -/
theorem fok1823 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1823 (src_p_true) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::p_struct_lit -/
theorem fok1903 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1903 (src_p_struct_lit) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::is_match_stmt -/
theorem fok1946 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1946 (src_is_match_stmt 1945) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::p_sub_tail -/
theorem fok1982 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1982 (src_p_sub_tail) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::text_slice_len -/
theorem fok2011 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 2011 (src_text_slice_len 376 418) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::or_known -/
theorem fok2421 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 2421 (src_or_known) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::arm_nested -/
theorem fok2422 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 2422 (src_arm_nested 153 155 156 2425 2427 2509) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::based_limit -/
theorem fok2475 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 2475 (src_based_limit) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::pats_nested -/
theorem fok2509 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 2509 (src_pats_nested 2544) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::all_binders -/
theorem fok2544 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 2544 (src_all_binders 103 2544 2589) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::not_known -/
theorem fok2576 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 2576 (src_not_known) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::is_binder_pat -/
theorem fok2589 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 2589 (src_is_binder_pat 153 156 1800 2425 2427 2609) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::binder_name_ok -/
theorem fok2609 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 2609 (src_binder_name_ok 163 1142 2556) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

end Lanius.Faithful.SelfPure
