module

public import Lanius.Faithful.Gen.SelfPureTab
public import Lanius.Faithful.Gen.SelfSrcC_arities
public import Lanius.Faithful.Gen.SelfSrcC_armPayload
public import Lanius.Faithful.Gen.SelfSrcC_evalNot
public import Lanius.Faithful.Gen.SelfSrcC_floatApply
public import Lanius.Faithful.Gen.SelfSrcC_loadAtBytes
public import Lanius.Faithful.Gen.SelfSrcC_longer
public import Lanius.Faithful.Gen.SelfSrcF_flRoundUp
public import Lanius.Faithful.Gen.SelfSrcF_forRange
public import Lanius.Faithful.Gen.SelfSrcF_litWildValue
public import Lanius.Faithful.Gen.SelfSrcF_projection
public import Lanius.Faithful.Gen.SelfSrcF_typePathSpellings
public import Lanius.Faithful.Gen.SelfSrcRest
import all Lanius.Faithful.Gen.SelfPureTab
import all Lanius.Faithful.Gen.SelfSrcC_arities
import all Lanius.Faithful.Gen.SelfSrcC_armPayload
import all Lanius.Faithful.Gen.SelfSrcC_evalNot
import all Lanius.Faithful.Gen.SelfSrcC_floatApply
import all Lanius.Faithful.Gen.SelfSrcC_loadAtBytes
import all Lanius.Faithful.Gen.SelfSrcC_longer
import all Lanius.Faithful.Gen.SelfSrcF_flRoundUp
import all Lanius.Faithful.Gen.SelfSrcF_forRange
import all Lanius.Faithful.Gen.SelfSrcF_litWildValue
import all Lanius.Faithful.Gen.SelfSrcF_projection
import all Lanius.Faithful.Gen.SelfSrcF_typePathSpellings
import all Lanius.Faithful.Gen.SelfSrcRest
import all Lanius.Faithful.Gen.SelfTypes
import all Lanius.Mini.Compiler.P.DivOp_size
import all Lanius.Mini.Compiler.P.FArith_opcode
import all Lanius.Mini.Compiler.P.FloatTy_rex
import all Lanius.Mini.Compiler.P.Instr_pieces
import all Lanius.Mini.Compiler.P.Lists_empty
import all Lanius.Mini.Compiler.P.SrcExpr_guard
import all Lanius.Mini.Compiler.P.SrcType_size
import all Lanius.Mini.Compiler.P.UintTy_half
import all Lanius.Mini.Compiler.P.UintTy_isWide
import all Lanius.Mini.Compiler.P.UintTy_mask
import all Lanius.Mini.Compiler.P.applyGuard
import all Lanius.Mini.Compiler.P.arithShiftRight
import all Lanius.Mini.Compiler.P.arithUint
import all Lanius.Mini.Compiler.P.arities
import all Lanius.Mini.Compiler.P.armBodyScope
import all Lanius.Mini.Compiler.P.armPayload
import all Lanius.Mini.Compiler.P.armScope
import all Lanius.Mini.Compiler.P.arrayCallSig
import all Lanius.Mini.Compiler.P.assignFrom
import all Lanius.Mini.Compiler.P.bindingBytes
import all Lanius.Mini.Compiler.P.codeSize
import all Lanius.Mini.Compiler.P.compileArgs
import all Lanius.Mini.Compiler.P.compileModules
import all Lanius.Mini.Compiler.P.conjunction
import all Lanius.Mini.Compiler.P.consArgs
import all Lanius.Mini.Compiler.P.declareFuncs
import all Lanius.Mini.Compiler.P.declareProgram
import all Lanius.Mini.Compiler.P.elementAddress
import all Lanius.Mini.Compiler.P.elementBase
import all Lanius.Mini.Compiler.P.enumVariants
import all Lanius.Mini.Compiler.P.equality
import all Lanius.Mini.Compiler.P.evalDivide
import all Lanius.Mini.Compiler.P.evalDivideSint
import all Lanius.Mini.Compiler.P.evalNot
import all Lanius.Mini.Compiler.P.evalSame
import all Lanius.Mini.Compiler.P.floatApply
import all Lanius.Mini.Compiler.P.funcNeeds
import all Lanius.Mini.Compiler.P.guardAnd
import all Lanius.Mini.Compiler.P.hostRandomCode
import all Lanius.Mini.Compiler.P.imageLimit
import all Lanius.Mini.Compiler.P.importOk
import all Lanius.Mini.Compiler.P.importsOk
import all Lanius.Mini.Compiler.P.indexOf
import all Lanius.Mini.Compiler.P.iteThen
import all Lanius.Mini.Compiler.P.leftTrue
import all Lanius.Mini.Compiler.P.loadAtBytes
import all Lanius.Mini.Compiler.P.lowerAddress
import all Lanius.Mini.Compiler.P.lowerApply
import all Lanius.Mini.Compiler.P.lowerBody
import all Lanius.Mini.Compiler.P.lowerCallSig
import all Lanius.Mini.Compiler.P.lowerLoadType
import all Lanius.Mini.Compiler.P.lowerLocal
import all Lanius.Mini.Compiler.P.lowerReturn
import all Lanius.Mini.Compiler.P.lowerSetCallArgs
import all Lanius.Mini.Compiler.P.lowerSetValues
import all Lanius.Mini.Compiler.P.lowerShift
import all Lanius.Mini.Compiler.P.lowerSlice
import all Lanius.Mini.Compiler.P.lowerTagged
import all Lanius.Mini.Compiler.P.matchDst
import all Lanius.Mini.Compiler.P.matchVariants
import all Lanius.Mini.Compiler.P.moduleExports
import all Lanius.Mini.Compiler.P.moduleFirsts
import all Lanius.Mini.Compiler.P.modulesOk
import all Lanius.Mini.Compiler.P.needRound
import all Lanius.Mini.Compiler.P.needsAfter
import all Lanius.Mini.Compiler.P.render
import all Lanius.Mini.Compiler.P.repeatType
import all Lanius.Mini.Compiler.P.shortCircuit
import all Lanius.Mini.Compiler.P.sintToUint
import all Lanius.Mini.Compiler.P.storeArray
import all Lanius.Mini.Compiler.P.storeEvalWord
import all Lanius.Mini.Compiler.P.storeType
import all Lanius.Mini.Compiler.P.storeWordElement
import all Lanius.Mini.Compiler.P.structFields
import all Lanius.Mini.Compiler.P.usizeWidth
import all Lanius.Mini.Compiler.P.widthOf
import all Lanius.Mini.Compiler.P.withBudget
import all Lanius.Mini.Compiler.P.wordElement
import all Lanius.Mini.Compiler.P.wordStride
import all Lanius.Mini.Compiler.P.wordWidth
import all Lanius.Mini.Compiler.Types

@[expose] public section

/-! Generated by formal/tools/faithful_pure.py. Do not edit. -/

namespace Lanius.Faithful.SelfPure

open Lanius.Mini
open Lanius.Faithful
open Lanius.Faithful.Self

set_option linter.unusedVariables false

/-- app::main::w -/
theorem fok0 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 0 (src_app_main_w 1 2 5 6 7 8) :=
  funcOk_outside (by decide +kernel)

/-- app::main::oracle_read -/
theorem fok1 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1 (src_app_main_oracle_read 1 9) :=
  funcOk_outside (by decide +kernel)

/-- app::main::oracle_put -/
theorem fok2 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 2 (src_app_main_oracle_put 3) :=
  funcOk_outside (by decide +kernel)

/-- app::main::oracle_write -/
theorem fok3 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 3 (src_app_main_oracle_write 4 10) :=
  funcOk_outside (by decide +kernel)

/-- app::main::oracle_write_one -/
theorem fok4 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 4 (src_app_main_oracle_write_one 3) :=
  funcOk_outside (by decide +kernel)

/-- core::mem::typed_slice_from_storage<mini::selfhost::List<i32>> -/
theorem fok34 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 34 (src_core_mem_typed_slice_from_storage_of_mini_selfhost_List_i32) :=
  funcOk_outside (by decide +kernel)

/-- core::mem::size_of<mini::selfhost::List<i32>> -/
theorem fok49 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 49 (src_core_mem_size_of_of_mini_selfhost_List_i32) :=
  funcOk_outside (by decide +kernel)

/-- core::mem::size_of<mini::selfhost::List<mini::selfhost::Rule>> -/
theorem fok72 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 72 (src_core_mem_size_of_of_mini_selfhost_List_mini_selfhost_Rule) :=
  funcOk_outside (by decide +kernel)

/-- core::mem::typed_slice_from_storage<mini::selfhost::List<mini::selfhost::Rule>> -/
theorem fok73 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 73 (src_core_mem_typed_slice_from_storage_of_mini_selfhost_List_mini_selfhost_Rule) :=
  funcOk_outside (by decide +kernel)

/-- core::mem::typed_slice_from_storage<mini::selfhost::List<mini::selfhost::SrcFunc>> -/
theorem fok82 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 82 (src_core_mem_typed_slice_from_storage_of_mini_selfhost_List_mini_selfhost_SrcFunc) :=
  funcOk_outside (by decide +kernel)

/-- core::mem::size_of<mini::selfhost::List<mini::selfhost::Sym>> -/
theorem fok107 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 107 (src_core_mem_size_of_of_mini_selfhost_List_mini_selfhost_Sym) :=
  funcOk_outside (by decide +kernel)

/-- core::mem::typed_slice_from_storage<mini::selfhost::List<mini::selfhost::Sym>> -/
theorem fok108 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 108 (src_core_mem_typed_slice_from_storage_of_mini_selfhost_List_mini_selfhost_Sym) :=
  funcOk_outside (by decide +kernel)

/-- core::mem::typed_slice_from_storage<mini::selfhost::List<usize>> -/
theorem fok109 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 109 (src_core_mem_typed_slice_from_storage_of_mini_selfhost_List_usize) :=
  funcOk_outside (by decide +kernel)

/-- core::mem::typed_slice_from_storage<mini::selfhost::List<u8>> -/
theorem fok111 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 111 (src_core_mem_typed_slice_from_storage_of_mini_selfhost_List_u8) :=
  funcOk_outside (by decide +kernel)

/-- core::mem::typed_slice_from_storage<mini::selfhost::SrcStmt> -/
theorem fok112 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 112 (src_core_mem_typed_slice_from_storage_of_mini_selfhost_SrcStmt) :=
  funcOk_outside (by decide +kernel)

/-- core::mem::typed_slice_from_storage<mini::selfhost::List<mini::selfhost::Sig>> -/
theorem fok131 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 131 (src_core_mem_typed_slice_from_storage_of_mini_selfhost_List_mini_selfhost_Sig) :=
  funcOk_outside (by decide +kernel)

/-- core::mem::typed_slice_from_storage<mini::selfhost::List<mini::selfhost::FileInput>> -/
theorem fok151 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 151 (src_core_mem_typed_slice_from_storage_of_mini_selfhost_List_mini_selfhost_FileInput) :=
  funcOk_outside (by decide +kernel)

/-- core::mem::typed_slice_from_storage<mini::selfhost::List<mini::selfhost::CTree>> -/
theorem fok164 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 164 (src_core_mem_typed_slice_from_storage_of_mini_selfhost_List_mini_selfhost_CTree) :=
  funcOk_outside (by decide +kernel)

/-- mini::selfhost::compile_funcs -/
theorem fok169 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 169 (src_compile_funcs 169 276 278 279 280) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::arities -/
theorem fok170 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 170 (src_arities 170 276 281 282) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::lower_match -/
theorem fok197 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 197 (src_lower_match 317) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::lower_match_arm -/
theorem fok227 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 227 (src_lower_match_arm 180 371 372 373) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- core::mem::size_of<mini::selfhost::List<mini::selfhost::FileInput>> -/
theorem fok246 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 246 (src_core_mem_size_of_of_mini_selfhost_List_mini_selfhost_FileInput) :=
  funcOk_outside (by decide +kernel)

/-- core::mem::size_of<mini::selfhost::List<mini::selfhost::List<mini::selfhost::List<usize>>>> -/
theorem fok271 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 271 (src_core_mem_size_of_of_mini_selfhost_List_mini_selfhost_List_mini_selfhost_List_usize) :=
  funcOk_outside (by decide +kernel)

/-- core::mem::typed_slice_from_storage<mini::selfhost::List<mini::selfhost::List<mini::selfhost::List<usize>>>> -/
theorem fok272 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 272 (src_core_mem_typed_slice_from_storage_of_mini_selfhost_List_mini_selfhost_List_mini_selfhost_List_usize) :=
  funcOk_outside (by decide +kernel)

/-- core::mem::typed_slice_from_storage<mini::selfhost::List<mini::selfhost::Token>> -/
theorem fok273 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 273 (src_core_mem_typed_slice_from_storage_of_mini_selfhost_List_mini_selfhost_Token) :=
  funcOk_outside (by decide +kernel)

/-- mini::selfhost::layout -/
theorem fok283 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 283 (src_layout 75 138 283 384 461 462) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::link_onto -/
theorem fok284 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 284 (src_link_onto 75 110 284 461 462 463 464 465) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- core::mem::size_of<mini::selfhost::List<mini::selfhost::Func>> -/
theorem fok287 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 287 (src_core_mem_size_of_of_mini_selfhost_List_mini_selfhost_Func) :=
  funcOk_outside (by decide +kernel)

/-- core::mem::typed_slice_from_storage<mini::selfhost::List<mini::selfhost::Func>> -/
theorem fok288 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 288 (src_core_mem_typed_slice_from_storage_of_mini_selfhost_List_mini_selfhost_Func) :=
  funcOk_outside (by decide +kernel)

/-- core::mem::typed_slice_from_storage<mini::selfhost::List<mini::selfhost::SrcParam>> -/
theorem fok289 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 289 (src_core_mem_typed_slice_from_storage_of_mini_selfhost_List_mini_selfhost_SrcParam) :=
  funcOk_outside (by decide +kernel)

/-- core::mem::typed_slice_from_storage<mini::selfhost::List<mini::selfhost::SrcType>> -/
theorem fok293 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 293 (src_core_mem_typed_slice_from_storage_of_mini_selfhost_List_mini_selfhost_SrcType) :=
  funcOk_outside (by decide +kernel)

/-- core::mem::typed_slice_from_storage<mini::selfhost::List<mini::selfhost::List<mini::selfhost::SrcType>>> -/
theorem fok294 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 294 (src_core_mem_typed_slice_from_storage_of_mini_selfhost_List_mini_selfhost_List_mini_selfhost_SrcType) :=
  funcOk_outside (by decide +kernel)

/-- core::mem::typed_slice_from_storage<mini::selfhost::SrcType> -/
theorem fok295 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 295 (src_core_mem_typed_slice_from_storage_of_mini_selfhost_SrcType) :=
  funcOk_outside (by decide +kernel)

/-- core::mem::size_of<mini::selfhost::Stmt> -/
theorem fok299 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 299 (src_core_mem_size_of_of_mini_selfhost_Stmt) :=
  funcOk_outside (by decide +kernel)

/-- core::mem::typed_slice_from_storage<mini::selfhost::Stmt> -/
theorem fok300 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 300 (src_core_mem_typed_slice_from_storage_of_mini_selfhost_Stmt) :=
  funcOk_outside (by decide +kernel)

/-- mini::selfhost::lower_match_on -/
theorem fok317 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 317 (src_lower_match_on 180 496) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- core::mem::size_of<mini::selfhost::SrcType> -/
theorem fok332 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 332 (src_core_mem_size_of_of_mini_selfhost_SrcType) :=
  funcOk_outside (by decide +kernel)

/-- mini::selfhost::eval_not -/
theorem fok347 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 347 (src_eval_not 523 525) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::eval_cast -/
theorem fok348 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 348 (src_eval_cast 523 526) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::lower_arm_found -/
theorem fok371 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 371 (src_lower_arm_found 546 547) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- core::mem::size_of<mini::selfhost::List<mini::selfhost::Sig>> -/
theorem fok382 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 382 (src_core_mem_size_of_of_mini_selfhost_List_mini_selfhost_Sig) :=
  funcOk_outside (by decide +kernel)

/-- core::mem::size_of<mini::selfhost::List<mini::selfhost::CTree>> -/
theorem fok400 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 400 (src_core_mem_size_of_of_mini_selfhost_List_mini_selfhost_CTree) :=
  funcOk_outside (by decide +kernel)

/-- core::mem::typed_slice_from_storage<mini::selfhost::List<mini::selfhost::FnDecl>> -/
theorem fok429 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 429 (src_core_mem_typed_slice_from_storage_of_mini_selfhost_List_mini_selfhost_FnDecl) :=
  funcOk_outside (by decide +kernel)

/-- core::mem::typed_slice_from_storage<mini::selfhost::List<mini::selfhost::TypeDecl>> -/
theorem fok430 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 430 (src_core_mem_typed_slice_from_storage_of_mini_selfhost_List_mini_selfhost_TypeDecl) :=
  funcOk_outside (by decide +kernel)

/-- mini::selfhost::size -/
theorem fok461 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 461 (src_Code_size 75 458) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::prologue -/
theorem fok464 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 464 (src_prologue 463 715 716 717 718 719) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::encode_onto -/
theorem fok465 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 465 (src_encode_onto 75 463 465 701 709 720) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- core::mem::size_of<mini::selfhost::List<mini::selfhost::Expr>> -/
theorem fok472 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 472 (src_core_mem_size_of_of_mini_selfhost_List_mini_selfhost_Expr) :=
  funcOk_outside (by decide +kernel)

/-- core::mem::typed_slice_from_storage<mini::selfhost::List<mini::selfhost::Expr>> -/
theorem fok473 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 473 (src_core_mem_typed_slice_from_storage_of_mini_selfhost_List_mini_selfhost_Expr) :=
  funcOk_outside (by decide +kernel)

/-- core::mem::typed_slice_from_storage<mini::selfhost::SrcExpr> -/
theorem fok475 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 475 (src_core_mem_typed_slice_from_storage_of_mini_selfhost_SrcExpr) :=
  funcOk_outside (by decide +kernel)

/-- core::mem::size_of<mini::selfhost::List<mini::selfhost::Binding>> -/
theorem fok491 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 491 (src_core_mem_size_of_of_mini_selfhost_List_mini_selfhost_Binding) :=
  funcOk_outside (by decide +kernel)

/-- core::mem::typed_slice_from_storage<mini::selfhost::List<mini::selfhost::Binding>> -/
theorem fok492 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 492 (src_core_mem_typed_slice_from_storage_of_mini_selfhost_List_mini_selfhost_Binding) :=
  funcOk_outside (by decide +kernel)

/-- core::mem::typed_slice_from_storage<mini::selfhost::List<mini::selfhost::SrcExpr>> -/
theorem fok493 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 493 (src_core_mem_typed_slice_from_storage_of_mini_selfhost_List_mini_selfhost_SrcExpr) :=
  funcOk_outside (by decide +kernel)

/-- mini::selfhost::lower_match_arms -/
theorem fok496 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 496 (src_lower_match_arms 120 372 734 735) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- core::mem::size_of<mini::selfhost::Expr> -/
theorem fok500 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 500 (src_core_mem_size_of_of_mini_selfhost_Expr) :=
  funcOk_outside (by decide +kernel)

/-- core::mem::typed_slice_from_storage<mini::selfhost::Expr> -/
theorem fok501 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 501 (src_core_mem_typed_slice_from_storage_of_mini_selfhost_Expr) :=
  funcOk_outside (by decide +kernel)

/-- core::mem::typed_slice_from_storage<mini::selfhost::List<mini::selfhost::SrcEff>> -/
theorem fok520 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 520 (src_core_mem_typed_slice_from_storage_of_mini_selfhost_List_mini_selfhost_SrcEff) :=
  funcOk_outside (by decide +kernel)

/-- core::mem::typed_slice_from_storage<mini::selfhost::SrcEff> -/
theorem fok522 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 522 (src_core_mem_typed_slice_from_storage_of_mini_selfhost_SrcEff) :=
  funcOk_outside (by decide +kernel)

/-- mini::selfhost::lower_arm_stmt -/
theorem fok546 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 546 (src_lower_arm_stmt 184 306 327) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::arm_payload -/
theorem fok547 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 547 (src_arm_payload 75 120 138 362 384 779 780 781) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- core::mem::size_of<mini::selfhost::List<mini::selfhost::SrcType>> -/
theorem fok549 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 549 (src_core_mem_size_of_of_mini_selfhost_List_mini_selfhost_SrcType) :=
  funcOk_outside (by decide +kernel)

/-- mini::selfhost::facts_after -/
theorem fok664 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 664 (src_Stmt_facts_after 275 297 664 965 966) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::is_skip -/
theorem fok671 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 671 (src_Stmt_is_skip) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::is_brk -/
theorem fok683 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 683 (src_Stmt_is_brk) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::is_cont -/
theorem fok684 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 684 (src_Stmt_is_cont) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- core::mem::size_of<mini::selfhost::List<mini::selfhost::Code>> -/
theorem fok710 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 710 (src_core_mem_size_of_of_mini_selfhost_List_mini_selfhost_Code) :=
  funcOk_outside (by decide +kernel)

/-- core::mem::typed_slice_from_storage<mini::selfhost::List<mini::selfhost::Code>> -/
theorem fok711 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 711 (src_core_mem_typed_slice_from_storage_of_mini_selfhost_List_mini_selfhost_Code) :=
  funcOk_outside (by decide +kernel)

/-- core::mem::size_of<mini::selfhost::List<mini::selfhost::Arity>> -/
theorem fok712 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 712 (src_core_mem_size_of_of_mini_selfhost_List_mini_selfhost_Arity) :=
  funcOk_outside (by decide +kernel)

/-- core::mem::typed_slice_from_storage<mini::selfhost::List<mini::selfhost::Arity>> -/
theorem fok713 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 713 (src_core_mem_typed_slice_from_storage_of_mini_selfhost_List_mini_selfhost_Arity) :=
  funcOk_outside (by decide +kernel)

/-- mini::selfhost::le32 -/
theorem fok717 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 717 (src_le32 715 716) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::frame_size -/
theorem fok718 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 718 (src_frame_size 75 105) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::stack_check -/
theorem fok719 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 719 (src_stack_check 715 716) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::encode -/
theorem fok720 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 720 (src_Instr_encode 52 75 105 135 463 715 716 717 987 988 989 990 991 992 993 994 995 996 997 998 999 1000 1001 1002 1003 1004 1005 1006 1007) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- core::mem::size_of<mini::selfhost::List<usize>> -/
theorem fok721 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 721 (src_core_mem_size_of_of_mini_selfhost_List_usize) :=
  funcOk_outside (by decide +kernel)

/-- core::mem::typed_slice_from_storage<mini::selfhost::List<mini::selfhost::List<usize>>> -/
theorem fok768 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 768 (src_core_mem_typed_slice_from_storage_of_mini_selfhost_List_mini_selfhost_List_usize) :=
  funcOk_outside (by decide +kernel)

/-- core::mem::typed_slice_from_storage<mini::selfhost::List<mini::selfhost::SrcStructDecl>> -/
theorem fok784 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 784 (src_core_mem_typed_slice_from_storage_of_mini_selfhost_List_mini_selfhost_SrcStructDecl) :=
  funcOk_outside (by decide +kernel)

/-- core::mem::typed_slice_from_storage<mini::selfhost::List<mini::selfhost::SrcEnumDecl>> -/
theorem fok786 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 786 (src_core_mem_typed_slice_from_storage_of_mini_selfhost_List_mini_selfhost_SrcEnumDecl) :=
  funcOk_outside (by decide +kernel)

/-- core::mem::typed_slice_from_storage<mini::selfhost::List<mini::selfhost::RawTok>> -/
theorem fok793 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 793 (src_core_mem_typed_slice_from_storage_of_mini_selfhost_List_mini_selfhost_RawTok) :=
  funcOk_outside (by decide +kernel)

/-- core::mem::typed_slice_from_storage<mini::selfhost::List<mini::selfhost::AliasDecl>> -/
theorem fok908 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 908 (src_core_mem_typed_slice_from_storage_of_mini_selfhost_List_mini_selfhost_AliasDecl) :=
  funcOk_outside (by decide +kernel)

/-- core::mem::typed_slice_from_storage<mini::selfhost::List<mini::selfhost::Ty>> -/
theorem fok924 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 924 (src_core_mem_typed_slice_from_storage_of_mini_selfhost_List_mini_selfhost_Ty) :=
  funcOk_outside (by decide +kernel)

/-- core::mem::size_of<mini::selfhost::List<mini::selfhost::Ty>> -/
theorem fok928 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 928 (src_core_mem_size_of_of_mini_selfhost_List_mini_selfhost_Ty) :=
  funcOk_outside (by decide +kernel)

/-- core::mem::typed_slice_from_storage<mini::selfhost::List<mini::selfhost::Inst>> -/
theorem fok929 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 929 (src_core_mem_typed_slice_from_storage_of_mini_selfhost_List_mini_selfhost_Inst) :=
  funcOk_outside (by decide +kernel)

/-- core::mem::typed_slice_from_storage<mini::selfhost::List<mini::selfhost::MFunc>> -/
theorem fok933 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 933 (src_core_mem_typed_slice_from_storage_of_mini_selfhost_List_mini_selfhost_MFunc) :=
  funcOk_outside (by decide +kernel)

/-- core::mem::size_of<mini::selfhost::List<mini::selfhost::Inst>> -/
theorem fok948 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 948 (src_core_mem_size_of_of_mini_selfhost_List_mini_selfhost_Inst) :=
  funcOk_outside (by decide +kernel)

/-- core::mem::size_of<mini::selfhost::List<mini::selfhost::TypeDecl>> -/
theorem fok949 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 949 (src_core_mem_size_of_of_mini_selfhost_List_mini_selfhost_TypeDecl) :=
  funcOk_outside (by decide +kernel)

/-- core::mem::size_of<mini::selfhost::List<mini::selfhost::FnDecl>> -/
theorem fok950 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 950 (src_core_mem_size_of_of_mini_selfhost_List_mini_selfhost_FnDecl) :=
  funcOk_outside (by decide +kernel)

/-- core::mem::size_of<mini::selfhost::List<mini::selfhost::ConstDecl>> -/
theorem fok951 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 951 (src_core_mem_size_of_of_mini_selfhost_List_mini_selfhost_ConstDecl) :=
  funcOk_outside (by decide +kernel)

/-- core::mem::typed_slice_from_storage<mini::selfhost::List<mini::selfhost::ConstDecl>> -/
theorem fok952 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 952 (src_core_mem_typed_slice_from_storage_of_mini_selfhost_List_mini_selfhost_ConstDecl) :=
  funcOk_outside (by decide +kernel)

/-- core::mem::size_of<mini::selfhost::List<mini::selfhost::ImportDecl>> -/
theorem fok953 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 953 (src_core_mem_size_of_of_mini_selfhost_List_mini_selfhost_ImportDecl) :=
  funcOk_outside (by decide +kernel)

/-- core::mem::typed_slice_from_storage<mini::selfhost::List<mini::selfhost::ImportDecl>> -/
theorem fok954 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 954 (src_core_mem_typed_slice_from_storage_of_mini_selfhost_List_mini_selfhost_ImportDecl) :=
  funcOk_outside (by decide +kernel)

/-- core::mem::size_of<mini::selfhost::List<mini::selfhost::AliasDecl>> -/
theorem fok955 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 955 (src_core_mem_size_of_of_mini_selfhost_List_mini_selfhost_AliasDecl) :=
  funcOk_outside (by decide +kernel)

/-- core::mem::size_of<mini::selfhost::List<mini::selfhost::ImplDecl>> -/
theorem fok956 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 956 (src_core_mem_size_of_of_mini_selfhost_List_mini_selfhost_ImplDecl) :=
  funcOk_outside (by decide +kernel)

/-- core::mem::typed_slice_from_storage<mini::selfhost::List<mini::selfhost::ImplDecl>> -/
theorem fok957 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 957 (src_core_mem_typed_slice_from_storage_of_mini_selfhost_List_mini_selfhost_ImplDecl) :=
  funcOk_outside (by decide +kernel)

/-- mini::selfhost::assigned -/
theorem fok965 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 965 (src_assigned 444 966 1191 1192 1193 1194) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- core::mem::size_of<mini::selfhost::List<mini::selfhost::Instr>> -/
theorem fok979 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 979 (src_core_mem_size_of_of_mini_selfhost_List_mini_selfhost_Instr) :=
  funcOk_outside (by decide +kernel)

/-- core::mem::typed_slice_from_storage<mini::selfhost::List<mini::selfhost::Instr>> -/
theorem fok980 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 980 (src_core_mem_typed_slice_from_storage_of_mini_selfhost_List_mini_selfhost_Instr) :=
  funcOk_outside (by decide +kernel)

/-- core::mem::size_of<mini::selfhost::List<u8>> -/
theorem fok986 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 986 (src_core_mem_size_of_of_mini_selfhost_List_u8) :=
  funcOk_outside (by decide +kernel)

/-- mini::selfhost::le64 -/
theorem fok987 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 987 (src_le64 715 716) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::slot_load -/
theorem fok988 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 988 (src_slot_load 463 715 716 717 1210) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::slot_store -/
theorem fok989 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 989 (src_slot_store 463 715 716 717 1210) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::bytes -/
theorem fok990 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 990 (src_BinOp_bytes 463 1211 1212 1213) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::slot_compare -/
theorem fok991 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 991 (src_slot_compare 463 715 716 1211 1212 1214) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::relative -/
theorem fok992 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 992 (src_relative) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::copy_bytes -/
theorem fok993 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 993 (src_copy_bytes 75 76 110 463 988 989 993) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::arg_base -/
theorem fok994 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 994 (src_arg_base 75 718) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::fsp_save -/
theorem fok995 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 995 (src_fsp_save 463 715 716 717 1210) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::fsp_load -/
theorem fok996 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 996 (src_fsp_load 463 715 716 717 1210) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::slot_range -/
theorem fok997 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 997 (src_slot_range 56 75 138 384 997) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::epilogue -/
theorem fok998 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 998 (src_epilogue 715 716) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::load_at_bytes -/
theorem fok1000 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1000 (src_load_at_bytes 715 716) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::store_at_bytes -/
theorem fok1001 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1001 (src_store_at_bytes 463 715 716 717 1210) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::load_word_bytes -/
theorem fok1002 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1002 (src_load_word_bytes 463 715 716 1216) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::store_word_bytes -/
theorem fok1003 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1003 (src_store_word_bytes 463 715 716 717 1210 1216) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::bytes -/
theorem fok1004 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1004 (src_DivOp_bytes 463 715 716 1211 1212 1217 1218 1219) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::sys_bytes -/
theorem fok1006 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1006 (src_sys_bytes 75 463 715 716 717 1210 1221 1222 1223) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::arith -/
theorem fok1012 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1012 (src_arith 327 328 378 761 763 764 771 1225 1226 1227 1228) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- core::mem::size_of<mini::selfhost::List<mini::selfhost::SrcStructDecl>> -/
theorem fok1051 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1051 (src_core_mem_size_of_of_mini_selfhost_List_mini_selfhost_SrcStructDecl) :=
  funcOk_outside (by decide +kernel)

/-- core::mem::size_of<mini::selfhost::List<mini::selfhost::SrcEnumDecl>> -/
theorem fok1052 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1052 (src_core_mem_size_of_of_mini_selfhost_List_mini_selfhost_SrcEnumDecl) :=
  funcOk_outside (by decide +kernel)

/-- core::mem::size_of<mini::selfhost::List<mini::selfhost::SymRule>> -/
theorem fok1065 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1065 (src_core_mem_size_of_of_mini_selfhost_List_mini_selfhost_SymRule) :=
  funcOk_outside (by decide +kernel)

/-- core::mem::typed_slice_from_storage<mini::selfhost::List<mini::selfhost::SymRule>> -/
theorem fok1066 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1066 (src_core_mem_typed_slice_from_storage_of_mini_selfhost_List_mini_selfhost_SymRule) :=
  funcOk_outside (by decide +kernel)

/-- core::mem::size_of<mini::selfhost::List<mini::selfhost::List<usize>>> -/
theorem fok1092 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1092 (src_core_mem_size_of_of_mini_selfhost_List_mini_selfhost_List_usize) :=
  funcOk_outside (by decide +kernel)

/-- core::mem::typed_slice_from_storage<mini::selfhost::Ty> -/
theorem fok1153 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1153 (src_core_mem_typed_slice_from_storage_of_mini_selfhost_Ty) :=
  funcOk_outside (by decide +kernel)

/-- core::mem::typed_slice_from_storage<mini::selfhost::List<mini::selfhost::MParam>> -/
theorem fok1155 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1155 (src_core_mem_typed_slice_from_storage_of_mini_selfhost_List_mini_selfhost_MParam) :=
  funcOk_outside (by decide +kernel)

/-- core::mem::typed_slice_from_storage<mini::selfhost::MStmt> -/
theorem fok1156 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1156 (src_core_mem_typed_slice_from_storage_of_mini_selfhost_MStmt) :=
  funcOk_outside (by decide +kernel)

/-- core::mem::size_of<mini::selfhost::List<mini::selfhost::MFunc>> -/
theorem fok1161 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1161 (src_core_mem_size_of_of_mini_selfhost_List_mini_selfhost_MFunc) :=
  funcOk_outside (by decide +kernel)

/-- core::mem::typed_slice_from_storage<mini::selfhost::List<mini::selfhost::Fact>> -/
theorem fok1190 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1190 (src_core_mem_typed_slice_from_storage_of_mini_selfhost_List_mini_selfhost_Fact) :=
  funcOk_outside (by decide +kernel)

/-- mini::selfhost::trim_facts -/
theorem fok1194 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1194 (src_trim_facts 1376 1377) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::ignores -/
theorem fok1197 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1197 (src_Stmt_ignores 297 1192 1197 1199) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::jumps -/
theorem fok1198 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1198 (src_Stmt_jumps 297 1198) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::slot_offset -/
theorem fok1210 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1210 (src_slot_offset 75 105) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::slot_operands -/
theorem fok1211 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1211 (src_slot_operands 463 715 716 988) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::rex -/
theorem fok1212 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1212 (src_Word_rex 110 716) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::opcode -/
theorem fok1213 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1213 (src_BinOp_opcode 715 716) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::setcc -/
theorem fok1214 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1214 (src_CmpOp_setcc 1386 1387) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::extend -/
theorem fok1217 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1217 (src_DivOp_extend 463 715 716 1212) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::opcode -/
theorem fok1218 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1218 (src_DivOp_opcode 715 716) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::result -/
theorem fok1219 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1219 (src_DivOp_result 110 715 716) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::syscall_rsi_bytes -/
theorem fok1221 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1221 (src_syscall_rsi_bytes 715 716) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::syscall_linux_byte -/
theorem fok1222 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1222 (src_syscall_linux_byte) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::syscall_linux_high -/
theorem fok1223 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1223 (src_syscall_linux_high) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::float_arith -/
theorem fok1225 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1225 (src_float_arith 1393) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::float_order -/
theorem fok1230 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1230 (src_float_order 1396) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- core::mem::typed_slice_from_storage<mini::selfhost::List<mini::selfhost::SrcArm>> -/
theorem fok1245 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1245 (src_core_mem_typed_slice_from_storage_of_mini_selfhost_List_mini_selfhost_SrcArm) :=
  funcOk_outside (by decide +kernel)

/-- core::mem::size_of<mini::selfhost::List<mini::selfhost::RawTok>> -/
theorem fok1262 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1262 (src_core_mem_size_of_of_mini_selfhost_List_mini_selfhost_RawTok) :=
  funcOk_outside (by decide +kernel)

/-- core::mem::size_of<mini::selfhost::List<mini::selfhost::Token>> -/
theorem fok1263 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1263 (src_core_mem_size_of_of_mini_selfhost_List_mini_selfhost_Token) :=
  funcOk_outside (by decide +kernel)

/-- core::mem::size_of<mini::selfhost::List<core::option::Option<mini::selfhost::SrcType>>> -/
theorem fok1304 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1304 (src_core_mem_size_of_of_mini_selfhost_List_core_option_Option_mini_selfhost_SrcType) :=
  funcOk_outside (by decide +kernel)

/-- core::mem::typed_slice_from_storage<mini::selfhost::List<core::option::Option<mini::selfhost::SrcType>>> -/
theorem fok1305 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1305 (src_core_mem_typed_slice_from_storage_of_mini_selfhost_List_core_option_Option_mini_selfhost_SrcType) :=
  funcOk_outside (by decide +kernel)

/-- core::mem::size_of<mini::selfhost::List<mini::selfhost::SrcFunc>> -/
theorem fok1315 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1315 (src_core_mem_size_of_of_mini_selfhost_List_mini_selfhost_SrcFunc) :=
  funcOk_outside (by decide +kernel)

/-- core::mem::size_of<mini::selfhost::SrcStmt> -/
theorem fok1326 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1326 (src_core_mem_size_of_of_mini_selfhost_SrcStmt) :=
  funcOk_outside (by decide +kernel)

/-- core::mem::typed_slice_from_storage<mini::selfhost::List<mini::selfhost::MEff>> -/
theorem fok1349 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1349 (src_core_mem_typed_slice_from_storage_of_mini_selfhost_List_mini_selfhost_MEff) :=
  funcOk_outside (by decide +kernel)

/-- core::mem::typed_slice_from_storage<mini::selfhost::MEff> -/
theorem fok1350 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1350 (src_core_mem_typed_slice_from_storage_of_mini_selfhost_MEff) :=
  funcOk_outside (by decide +kernel)

/-- core::mem::size_of<mini::selfhost::MStmt> -/
theorem fok1359 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1359 (src_core_mem_size_of_of_mini_selfhost_MStmt) :=
  funcOk_outside (by decide +kernel)

/-- core::mem::size_of<mini::selfhost::List<mini::selfhost::MEff>> -/
theorem fok1360 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1360 (src_core_mem_size_of_of_mini_selfhost_List_mini_selfhost_MEff) :=
  funcOk_outside (by decide +kernel)

/-- core::mem::size_of<mini::selfhost::List<mini::selfhost::MParam>> -/
theorem fok1370 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1370 (src_core_mem_size_of_of_mini_selfhost_List_mini_selfhost_MParam) :=
  funcOk_outside (by decide +kernel)

/-- mini::selfhost::longer -/
theorem fok1376 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1376 (src_longer 56 964 1376) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::setcc_signed -/
theorem fok1386 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1386 (src_CmpOp_setcc_signed) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::setcc_unsigned -/
theorem fok1387 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1387 (src_CmpOp_setcc_unsigned) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- core::mem::size_of<mini::selfhost::SrcExpr> -/
theorem fok1430 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1430 (src_core_mem_size_of_of_mini_selfhost_SrcExpr) :=
  funcOk_outside (by decide +kernel)

/-- core::mem::typed_slice_from_storage<mini::selfhost::List<mini::selfhost::LocalTy>> -/
theorem fok1442 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1442 (src_core_mem_typed_slice_from_storage_of_mini_selfhost_List_mini_selfhost_LocalTy) :=
  funcOk_outside (by decide +kernel)

/-- core::mem::size_of<mini::selfhost::List<mini::selfhost::SrcEff>> -/
theorem fok1443 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1443 (src_core_mem_size_of_of_mini_selfhost_List_mini_selfhost_SrcEff) :=
  funcOk_outside (by decide +kernel)

/-- core::mem::size_of<mini::selfhost::SrcEff> -/
theorem fok1445 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1445 (src_core_mem_size_of_of_mini_selfhost_SrcEff) :=
  funcOk_outside (by decide +kernel)

/-- core::mem::size_of<mini::selfhost::List<mini::selfhost::LocalTy>> -/
theorem fok1449 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1449 (src_core_mem_size_of_of_mini_selfhost_List_mini_selfhost_LocalTy) :=
  funcOk_outside (by decide +kernel)

/-- mini::selfhost::type_path_spellings -/
theorem fok1471 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1471 (src_type_path_spellings 56 152 155 597 598 617 619 1471 1530 1531 1532) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- core::mem::size_of<mini::selfhost::List<mini::selfhost::Fact>> -/
theorem fok1482 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1482 (src_core_mem_size_of_of_mini_selfhost_List_mini_selfhost_Fact) :=
  funcOk_outside (by decide +kernel)

/-- mini::selfhost::float_apply -/
theorem fok1488 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1488 (src_float_apply 327) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::float_compare -/
theorem fok1490 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1490 (src_float_compare 327) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- core::mem::size_of<mini::selfhost::List<mini::selfhost::SrcParam>> -/
theorem fok1501 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1501 (src_core_mem_size_of_of_mini_selfhost_List_mini_selfhost_SrcParam) :=
  funcOk_outside (by decide +kernel)

/-- core::mem::size_of<mini::selfhost::List<mini::selfhost::List<mini::selfhost::SrcType>>> -/
theorem fok1503 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1503 (src_core_mem_size_of_of_mini_selfhost_List_mini_selfhost_List_mini_selfhost_SrcType) :=
  funcOk_outside (by decide +kernel)

/-- core::mem::typed_slice_from_storage<mini::selfhost::List<mini::selfhost::List<mini::selfhost::Ty>>> -/
theorem fok1505 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1505 (src_core_mem_typed_slice_from_storage_of_mini_selfhost_List_mini_selfhost_List_mini_selfhost_Ty) :=
  funcOk_outside (by decide +kernel)

/-- core::mem::size_of<mini::selfhost::List<mini::selfhost::SrcExpr>> -/
theorem fok1516 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1516 (src_core_mem_size_of_of_mini_selfhost_List_mini_selfhost_SrcExpr) :=
  funcOk_outside (by decide +kernel)

/-- core::mem::size_of<mini::selfhost::List<mini::selfhost::SrcArm>> -/
theorem fok1517 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1517 (src_core_mem_size_of_of_mini_selfhost_List_mini_selfhost_SrcArm) :=
  funcOk_outside (by decide +kernel)

/-- core::mem::size_of<mini::selfhost::List<mini::selfhost::List<mini::selfhost::CTree>>> -/
theorem fok1570 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1570 (src_core_mem_size_of_of_mini_selfhost_List_mini_selfhost_List_mini_selfhost_CTree) :=
  funcOk_outside (by decide +kernel)

/-- core::mem::typed_slice_from_storage<mini::selfhost::List<mini::selfhost::List<mini::selfhost::CTree>>> -/
theorem fok1571 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1571 (src_core_mem_typed_slice_from_storage_of_mini_selfhost_List_mini_selfhost_List_mini_selfhost_CTree) :=
  funcOk_outside (by decide +kernel)

/-- core::mem::typed_slice_from_storage<mini::selfhost::List<mini::selfhost::Local>> -/
theorem fok1577 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1577 (src_core_mem_typed_slice_from_storage_of_mini_selfhost_List_mini_selfhost_Local) :=
  funcOk_outside (by decide +kernel)

/-- core::mem::size_of<mini::selfhost::List<mini::selfhost::Local>> -/
theorem fok1578 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1578 (src_core_mem_size_of_of_mini_selfhost_List_mini_selfhost_Local) :=
  funcOk_outside (by decide +kernel)

/-- core::mem::size_of<mini::selfhost::Ty> -/
theorem fok1579 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1579 (src_core_mem_size_of_of_mini_selfhost_Ty) :=
  funcOk_outside (by decide +kernel)

/-- mini::selfhost::split_last -/
theorem fok1585 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1585 (src_split_last 531 1585 1614) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- core::mem::typed_slice_from_storage<mini::selfhost::List<mini::selfhost::BoundGoal>> -/
theorem fok1594 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1594 (src_core_mem_typed_slice_from_storage_of_mini_selfhost_List_mini_selfhost_BoundGoal) :=
  funcOk_outside (by decide +kernel)

/-- mini::selfhost::split_more -/
theorem fok1614 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1614 (src_split_more 258 1093) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- core::mem::size_of<mini::selfhost::List<mini::selfhost::BoundGoal>> -/
theorem fok1673 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1673 (src_core_mem_size_of_of_mini_selfhost_List_mini_selfhost_BoundGoal) :=
  funcOk_outside (by decide +kernel)

/-- mini::selfhost::match_primary -/
theorem fok1762 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1762 (src_match_primary 152 155 576 1622 1624 1677 1877 1878) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- core::mem::size_of<mini::selfhost::List<mini::selfhost::List<mini::selfhost::Ty>>> -/
theorem fok1768 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1768 (src_core_mem_size_of_of_mini_selfhost_List_mini_selfhost_List_mini_selfhost_Ty) :=
  funcOk_outside (by decide +kernel)

/-- core::mem::size_of<mini::selfhost::MEff> -/
theorem fok1821 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1821 (src_core_mem_size_of_of_mini_selfhost_MEff) :=
  funcOk_outside (by decide +kernel)

/-- mini::selfhost::match_of_postfix -/
theorem fok1878 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1878 (src_match_of_postfix 152 155 1656 1692) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::fl_decimal_at -/
theorem fok1922 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1922 (src_fl_decimal_at 56 75 105 2035 2036 2037 2038) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::step_expected -/
theorem fok1938 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1938 (src_step_expected 152 1692) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::method_of_ty -/
theorem fok1939 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1939 (src_method_of_ty 160 1835) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::field_of_ty -/
theorem fok1940 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1940 (src_field_of_ty 1807 2051) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::eff_slice_local -/
theorem fok1941 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1941 (src_eff_slice_local 1958 2052) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::lit_result -/
theorem fok1963 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1963 (src_lit_result 1851) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::for_range -/
theorem fok1996 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1996 (src_for_range 1171 1320 1367 2112) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::array_local -/
theorem fok1998 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1998 (src_array_local 1857 2113) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::for_array -/
theorem fok1999 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 1999 (src_for_array 1171 1320) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::for_slice -/
theorem fok2000 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 2000 (src_for_slice 1171 1320 1367 2112) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::fl_round -/
theorem fok2036 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 2036 (src_fl_round 56 75 105 2035 2153 2161 2162 2163 2164 2165 2166 2167 2168 2169 2170) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::field_value -/
theorem fok2051 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 2051 (src_field_value 1172 1836 2052 2189) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- core::mem::typed_slice_from_storage<mini::selfhost::List<mini::selfhost::VariantAt>> -/
theorem fok2058 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 2058 (src_core_mem_typed_slice_from_storage_of_mini_selfhost_List_mini_selfhost_VariantAt) :=
  funcOk_outside (by decide +kernel)

/-- mini::selfhost::lit_chain -/
theorem fok2073 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 2073 (src_lit_chain 103 1158 2073 2110 2111 2201) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- core::mem::typed_slice_from_storage<mini::selfhost::List<mini::selfhost::VariantTy>> -/
theorem fok2088 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 2088 (src_core_mem_typed_slice_from_storage_of_mini_selfhost_List_mini_selfhost_VariantTy) :=
  funcOk_outside (by decide +kernel)

/-- mini::selfhost::array_local_of -/
theorem fok2113 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 2113 (src_array_local_of) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- core::mem::typed_slice_from_storage<mini::selfhost::List<bool>> -/
theorem fok2160 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 2160 (src_core_mem_typed_slice_from_storage_of_mini_selfhost_List_bool) :=
  funcOk_outside (by decide +kernel)

/-- mini::selfhost::fl_ratio_ok -/
theorem fok2164 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 2164 (src_fl_ratio_ok 2162 2165 2167) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::fl_round_up -/
theorem fok2169 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 2169 (src_fl_round_up 1704 2028) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- mini::selfhost::projection -/
theorem fok2189 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 2189 (src_projection 75 923 945) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- core::mem::size_of<mini::selfhost::List<mini::selfhost::VariantAt>> -/
theorem fok2193 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 2193 (src_core_mem_size_of_of_mini_selfhost_List_mini_selfhost_VariantAt) :=
  funcOk_outside (by decide +kernel)

/-- mini::selfhost::lit_link -/
theorem fok2201 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 2201 (src_lit_link 155 2105 2272 2273 2274 2275) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- core::mem::typed_slice_from_storage<mini::selfhost::List<mini::selfhost::Bind>> -/
theorem fok2241 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 2241 (src_core_mem_typed_slice_from_storage_of_mini_selfhost_List_mini_selfhost_Bind) :=
  funcOk_outside (by decide +kernel)

/-- core::mem::size_of<mini::selfhost::List<bool>> -/
theorem fok2252 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 2252 (src_core_mem_size_of_of_mini_selfhost_List_bool) :=
  funcOk_outside (by decide +kernel)

/-- core::mem::typed_slice_from_storage<mini::selfhost::List<mini::selfhost::EffArm>> -/
theorem fok2267 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 2267 (src_core_mem_typed_slice_from_storage_of_mini_selfhost_List_mini_selfhost_EffArm) :=
  funcOk_outside (by decide +kernel)

/-- core::mem::size_of<mini::selfhost::List<mini::selfhost::VariantTy>> -/
theorem fok2271 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 2271 (src_core_mem_size_of_of_mini_selfhost_List_mini_selfhost_VariantTy) :=
  funcOk_outside (by decide +kernel)

/-- mini::selfhost::lit_wild_value -/
theorem fok2272 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 2272 (src_lit_wild_value) :=
  funcOk_pure (pureFunc_fast hb hc (by decide +kernel))

/-- core::mem::size_of<mini::selfhost::List<mini::selfhost::Bind>> -/
theorem fok2342 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 2342 (src_core_mem_size_of_of_mini_selfhost_List_mini_selfhost_Bind) :=
  funcOk_outside (by decide +kernel)

/-- core::mem::size_of<mini::selfhost::List<mini::selfhost::EffArm>> -/
theorem fok2354 {sp : SrcProgram} (hb : boxElem sp prims = lookupBox boxPairs)
    (hc : callTy sp outside = sigCall (blockGet sigBlocks)) :
    FuncOk sp prims outside 2354 (src_core_mem_size_of_of_mini_selfhost_List_mini_selfhost_EffArm) :=
  funcOk_outside (by decide +kernel)

end Lanius.Faithful.SelfPure
