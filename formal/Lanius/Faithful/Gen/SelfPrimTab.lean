module

public import Lanius.Faithful.Gen.SelfPureTab
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

theorem word33 : wordElement decls ty1 = true := by decide +kernel

theorem words33 : (NativeLayout.valueWords? (declsCore decls) (ty1).toCore).isSome = true := by
  decide +kernel

theorem word43 : wordElement decls ty44 = true := by decide +kernel

theorem words43 : (NativeLayout.valueWords? (declsCore decls) (ty44).toCore).isSome = true := by
  decide +kernel

theorem word74 : wordElement decls ty41 = true := by decide +kernel

theorem words74 : (NativeLayout.valueWords? (declsCore decls) (ty41).toCore).isSome = true := by
  decide +kernel

theorem word147 : wordElement decls ty50 = true := by decide +kernel

theorem words147 : (NativeLayout.valueWords? (declsCore decls) (ty50).toCore).isSome = true := by
  decide +kernel

theorem word166 : wordElement decls ty127 = true := by decide +kernel

theorem words166 : (NativeLayout.valueWords? (declsCore decls) (ty127).toCore).isSome = true := by
  decide +kernel

theorem word173 : wordElement decls ty98 = true := by decide +kernel

theorem words173 : (NativeLayout.valueWords? (declsCore decls) (ty98).toCore).isSome = true := by
  decide +kernel

theorem word188 : wordElement decls ty95 = true := by decide +kernel

theorem words188 : (NativeLayout.valueWords? (declsCore decls) (ty95).toCore).isSome = true := by
  decide +kernel

theorem word217 : wordElement decls ty9 = true := by decide +kernel

theorem words217 : (NativeLayout.valueWords? (declsCore decls) (ty9).toCore).isSome = true := by
  decide +kernel

theorem word238 : wordElement decls ty103 = true := by decide +kernel

theorem words238 : (NativeLayout.valueWords? (declsCore decls) (ty103).toCore).isSome = true := by
  decide +kernel

theorem word254 : wordElement decls ty86 = true := by decide +kernel

theorem words254 : (NativeLayout.valueWords? (declsCore decls) (ty86).toCore).isSome = true := by
  decide +kernel

theorem word311 : wordElement decls ty94 = true := by decide +kernel

theorem words311 : (NativeLayout.valueWords? (declsCore decls) (ty94).toCore).isSome = true := by
  decide +kernel

theorem word320 : wordElement decls ty150 = true := by decide +kernel

theorem words320 : (NativeLayout.valueWords? (declsCore decls) (ty150).toCore).isSome = true := by
  decide +kernel

theorem word337 : wordElement decls ty91 = true := by decide +kernel

theorem words337 : (NativeLayout.valueWords? (declsCore decls) (ty91).toCore).isSome = true := by
  decide +kernel

theorem word402 : wordElement decls ty72 = true := by decide +kernel

theorem words402 : (NativeLayout.valueWords? (declsCore decls) (ty72).toCore).isSome = true := by
  decide +kernel

theorem word481 : wordElement decls ty68 = true := by decide +kernel

theorem words481 : (NativeLayout.valueWords? (declsCore decls) (ty68).toCore).isSome = true := by
  decide +kernel

theorem word482 : wordElement decls ty163 = true := by decide +kernel

theorem words482 : (NativeLayout.valueWords? (declsCore decls) (ty163).toCore).isSome = true := by
  decide +kernel

theorem word488 : wordElement decls ty20 = true := by decide +kernel

theorem words488 : (NativeLayout.valueWords? (declsCore decls) (ty20).toCore).isSome = true := by
  decide +kernel

theorem word670 : wordElement decls ty155 = true := by decide +kernel

theorem words670 : (NativeLayout.valueWords? (declsCore decls) (ty155).toCore).isSome = true := by
  decide +kernel

theorem word684 : wordElement decls ty158 = true := by decide +kernel

theorem words684 : (NativeLayout.valueWords? (declsCore decls) (ty158).toCore).isSome = true := by
  decide +kernel

theorem word685 : wordElement decls ty110 = true := by decide +kernel

theorem words685 : (NativeLayout.valueWords? (declsCore decls) (ty110).toCore).isSome = true := by
  decide +kernel

theorem word686 : wordElement decls ty113 = true := by decide +kernel

theorem words686 : (NativeLayout.valueWords? (declsCore decls) (ty113).toCore).isSome = true := by
  decide +kernel

theorem word687 : wordElement decls ty116 = true := by decide +kernel

theorem words687 : (NativeLayout.valueWords? (declsCore decls) (ty116).toCore).isSome = true := by
  decide +kernel

theorem word689 : wordElement decls ty119 = true := by decide +kernel

theorem words689 : (NativeLayout.valueWords? (declsCore decls) (ty119).toCore).isSome = true := by
  decide +kernel

theorem word691 : wordElement decls ty122 = true := by decide +kernel

theorem words691 : (NativeLayout.valueWords? (declsCore decls) (ty122).toCore).isSome = true := by
  decide +kernel

theorem word692 : wordElement decls ty125 = true := by decide +kernel

theorem words692 : (NativeLayout.valueWords? (declsCore decls) (ty125).toCore).isSome = true := by
  decide +kernel

theorem word739 : wordElement decls ty65 = true := by decide +kernel

theorem words739 : (NativeLayout.valueWords? (declsCore decls) (ty65).toCore).isSome = true := by
  decide +kernel

theorem word824 : wordElement decls ty219 = true := by decide +kernel

theorem words824 : (NativeLayout.valueWords? (declsCore decls) (ty219).toCore).isSome = true := by
  decide +kernel

theorem word826 : wordElement decls ty75 = true := by decide +kernel

theorem words826 : (NativeLayout.valueWords? (declsCore decls) (ty75).toCore).isSome = true := by
  decide +kernel

theorem word828 : wordElement decls ty79 = true := by decide +kernel

theorem words828 : (NativeLayout.valueWords? (declsCore decls) (ty79).toCore).isSome = true := by
  decide +kernel

theorem word833 : wordElement decls ty223 = true := by decide +kernel

theorem words833 : (NativeLayout.valueWords? (declsCore decls) (ty223).toCore).isSome = true := by
  decide +kernel

theorem word937 : wordElement decls ty27 = true := by decide +kernel

theorem words937 : (NativeLayout.valueWords? (declsCore decls) (ty27).toCore).isSome = true := by
  decide +kernel

theorem word984 : wordElement decls ty154 = true := by decide +kernel

theorem words984 : (NativeLayout.valueWords? (declsCore decls) (ty154).toCore).isSome = true := by
  decide +kernel

theorem word991 : wordElement decls ty197 = true := by decide +kernel

theorem words991 : (NativeLayout.valueWords? (declsCore decls) (ty197).toCore).isSome = true := by
  decide +kernel

theorem word1041 : wordElement decls ty36 = true := by decide +kernel

theorem words1041 : (NativeLayout.valueWords? (declsCore decls) (ty36).toCore).isSome = true := by
  decide +kernel

theorem word1110 : wordElement decls ty183 = true := by decide +kernel

theorem words1110 : (NativeLayout.valueWords? (declsCore decls) (ty183).toCore).isSome = true := by
  decide +kernel

theorem word1113 : wordElement decls ty47 = true := by decide +kernel

theorem words1113 : (NativeLayout.valueWords? (declsCore decls) (ty47).toCore).isSome = true := by
  decide +kernel

theorem word1184 : wordElement decls ty229 = true := by decide +kernel

theorem words1184 : (NativeLayout.valueWords? (declsCore decls) (ty229).toCore).isSome = true := by
  decide +kernel

theorem word1200 : wordElement decls ty34 = true := by decide +kernel

theorem words1200 : (NativeLayout.valueWords? (declsCore decls) (ty34).toCore).isSome = true := by
  decide +kernel

theorem word1202 : wordElement decls ty31 = true := by decide +kernel

theorem words1202 : (NativeLayout.valueWords? (declsCore decls) (ty31).toCore).isSome = true := by
  decide +kernel

theorem word1220 : wordElement decls ty247 = true := by decide +kernel

theorem words1220 : (NativeLayout.valueWords? (declsCore decls) (ty247).toCore).isSome = true := by
  decide +kernel

theorem word1241 : wordElement decls ty194 = true := by decide +kernel

theorem words1241 : (NativeLayout.valueWords? (declsCore decls) (ty194).toCore).isSome = true := by
  decide +kernel

theorem word1242 : wordElement decls ty287 = true := by decide +kernel

theorem words1242 : (NativeLayout.valueWords? (declsCore decls) (ty287).toCore).isSome = true := by
  decide +kernel

theorem word1250 : wordElement decls ty188 = true := by decide +kernel

theorem words1250 : (NativeLayout.valueWords? (declsCore decls) (ty188).toCore).isSome = true := by
  decide +kernel

theorem word1428 : wordElement decls ty15 = true := by decide +kernel

theorem words1428 : (NativeLayout.valueWords? (declsCore decls) (ty15).toCore).isSome = true := by
  decide +kernel

theorem word1447 : wordElement decls ty213 = true := by decide +kernel

theorem words1447 : (NativeLayout.valueWords? (declsCore decls) (ty213).toCore).isSome = true := by
  decide +kernel

theorem word1449 : wordElement decls ty29 = true := by decide +kernel

theorem words1449 : (NativeLayout.valueWords? (declsCore decls) (ty29).toCore).isSome = true := by
  decide +kernel

theorem word1452 : wordElement decls ty271 = true := by decide +kernel

theorem words1452 : (NativeLayout.valueWords? (declsCore decls) (ty271).toCore).isSome = true := by
  decide +kernel

theorem word1487 : wordElement decls ty205 = true := by decide +kernel

theorem words1487 : (NativeLayout.valueWords? (declsCore decls) (ty205).toCore).isSome = true := by
  decide +kernel

theorem word1534 : wordElement decls ty12 = true := by decide +kernel

theorem words1534 : (NativeLayout.valueWords? (declsCore decls) (ty12).toCore).isSome = true := by
  decide +kernel

theorem word1539 : wordElement decls ty76 = true := by decide +kernel

theorem words1539 : (NativeLayout.valueWords? (declsCore decls) (ty76).toCore).isSome = true := by
  decide +kernel

theorem word1576 : wordElement decls ty18 = true := by decide +kernel

theorem words1576 : (NativeLayout.valueWords? (declsCore decls) (ty18).toCore).isSome = true := by
  decide +kernel

theorem word1577 : wordElement decls ty23 = true := by decide +kernel

theorem words1577 : (NativeLayout.valueWords? (declsCore decls) (ty23).toCore).isSome = true := by
  decide +kernel

theorem word1648 : wordElement decls ty107 = true := by decide +kernel

theorem words1648 : (NativeLayout.valueWords? (declsCore decls) (ty107).toCore).isSome = true := by
  decide +kernel

theorem word1679 : wordElement decls ty292 = true := by decide +kernel

theorem words1679 : (NativeLayout.valueWords? (declsCore decls) (ty292).toCore).isSome = true := by
  decide +kernel

theorem word1793 : wordElement decls ty304 = true := by decide +kernel

theorem words1793 : (NativeLayout.valueWords? (declsCore decls) (ty304).toCore).isSome = true := by
  decide +kernel

theorem word1848 : wordElement decls ty298 = true := by decide +kernel

theorem words1848 : (NativeLayout.valueWords? (declsCore decls) (ty298).toCore).isSome = true := by
  decide +kernel

theorem word1888 : wordElement decls ty193 = true := by decide +kernel

theorem words1888 : (NativeLayout.valueWords? (declsCore decls) (ty193).toCore).isSome = true := by
  decide +kernel

theorem word2260 : wordElement decls ty360 = true := by decide +kernel

theorem words2260 : (NativeLayout.valueWords? (declsCore decls) (ty360).toCore).isSome = true := by
  decide +kernel

theorem word2383 : wordElement decls ty320 = true := by decide +kernel

theorem words2383 : (NativeLayout.valueWords? (declsCore decls) (ty320).toCore).isSome = true := by
  decide +kernel

theorem word2415 : wordElement decls ty348 = true := by decide +kernel

theorem words2415 : (NativeLayout.valueWords? (declsCore decls) (ty348).toCore).isSome = true := by
  decide +kernel

theorem word2524 : wordElement decls ty335 = true := by decide +kernel

theorem words2524 : (NativeLayout.valueWords? (declsCore decls) (ty335).toCore).isSome = true := by
  decide +kernel

theorem word2536 : wordElement decls ty367 = true := by decide +kernel

theorem words2536 : (NativeLayout.valueWords? (declsCore decls) (ty367).toCore).isSome = true := by
  decide +kernel

theorem word10 : wordElement decls ty1 = true := by decide +kernel

theorem word44 : wordElement decls ty44 = true := by decide +kernel

theorem word59 : wordElement decls ty34 = true := by decide +kernel

theorem word76 : wordElement decls ty20 = true := by decide +kernel

theorem word78 : wordElement decls ty36 = true := by decide +kernel

theorem word81 : wordElement decls ty31 = true := by decide +kernel

theorem word87 : wordElement decls ty103 = true := by decide +kernel

theorem word99 : wordElement decls ty50 = true := by decide +kernel

theorem word103 : wordElement decls ty86 = true := by decide +kernel

theorem word167 : wordElement decls ty47 = true := by decide +kernel

theorem word174 : wordElement decls ty12 = true := by decide +kernel

theorem word181 : wordElement decls ty72 = true := by decide +kernel

theorem word183 : wordElement decls ty76 = true := by decide +kernel

theorem word184 : wordElement decls ty9 = true := by decide +kernel

theorem word256 : wordElement decls ty41 = true := by decide +kernel

theorem word274 : wordElement decls ty113 = true := by decide +kernel

theorem word276 : wordElement decls ty110 = true := by decide +kernel

theorem word283 : wordElement decls ty98 = true := by decide +kernel

theorem word307 : wordElement decls ty95 = true := by decide +kernel

theorem word313 : wordElement decls ty15 = true := by decide +kernel

theorem word321 : wordElement decls ty18 = true := by decide +kernel

theorem word329 : wordElement decls ty150 = true := by decide +kernel

theorem word356 : wordElement decls ty213 = true := by decide +kernel

theorem word358 : wordElement decls ty29 = true := by decide +kernel

theorem word485 : wordElement decls ty68 = true := by decide +kernel

theorem word492 : wordElement decls ty91 = true := by decide +kernel

theorem word493 : wordElement decls ty94 = true := by decide +kernel

theorem word558 : wordElement decls ty27 = true := by decide +kernel

theorem word575 : wordElement decls ty219 = true := by decide +kernel

theorem word585 : wordElement decls ty75 = true := by decide +kernel

theorem word588 : wordElement decls ty79 = true := by decide +kernel

theorem word599 : wordElement decls ty183 = true := by decide +kernel

theorem word651 : wordElement decls ty127 = true := by decide +kernel

theorem word655 : wordElement decls ty122 = true := by decide +kernel

theorem word666 : wordElement decls ty155 = true := by decide +kernel

theorem word671 : wordElement decls ty158 = true := by decide +kernel

theorem word676 : wordElement decls ty197 = true := by decide +kernel

theorem word688 : wordElement decls ty116 = true := by decide +kernel

theorem word690 : wordElement decls ty119 = true := by decide +kernel

theorem word693 : wordElement decls ty125 = true := by decide +kernel

theorem word741 : wordElement decls ty65 = true := by decide +kernel

theorem word969 : wordElement decls ty247 = true := by decide +kernel

theorem word977 : wordElement decls ty154 = true := by decide +kernel

theorem word982 : wordElement decls ty188 = true := by decide +kernel

theorem word983 : wordElement decls ty194 = true := by decide +kernel

theorem word1017 : wordElement decls ty205 = true := by decide +kernel

theorem word1066 : wordElement decls ty23 = true := by decide +kernel

theorem word1228 : wordElement decls ty287 = true := by decide +kernel

theorem word1229 : wordElement decls ty193 = true := by decide +kernel

theorem word1279 : wordElement decls ty163 = true := by decide +kernel

theorem word1347 : wordElement decls ty223 = true := by decide +kernel

theorem word1446 : wordElement decls ty271 = true := by decide +kernel

theorem word1541 : wordElement decls ty298 = true := by decide +kernel

theorem word1650 : wordElement decls ty229 = true := by decide +kernel

theorem word1657 : wordElement decls ty107 = true := by decide +kernel

theorem word1672 : wordElement decls ty292 = true := by decide +kernel

theorem word1692 : wordElement decls ty304 = true := by decide +kernel

theorem word2139 : wordElement decls ty360 = true := by decide +kernel

theorem word2169 : wordElement decls ty348 = true := by decide +kernel

theorem word2235 : wordElement decls ty320 = true := by decide +kernel

theorem word2348 : wordElement decls ty335 = true := by decide +kernel

theorem word2410 : wordElement decls ty367 = true := by decide +kernel

end Lanius.Faithful.SelfPure
