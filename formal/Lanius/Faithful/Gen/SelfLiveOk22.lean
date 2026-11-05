module

public import Lanius.Faithful.Gen.SelfPureTab
public import Lanius.Faithful.Gen.SelfLiveTab
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
public import Lanius.Faithful.Gen.SelfSrcF_setPlaceOf
public import Lanius.Faithful.Gen.SelfSrcF_stringOpen
public import Lanius.Faithful.Gen.SelfSrcF_typePathSpellings
public import Lanius.Faithful.Gen.SelfSrcRest
import all Lanius.Faithful.Gen.SelfLiveTab
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
import all Lanius.Faithful.Gen.SelfSrcF_setPlaceOf
import all Lanius.Faithful.Gen.SelfSrcF_stringOpen
import all Lanius.Faithful.Gen.SelfSrcF_typePathSpellings
import all Lanius.Faithful.Gen.SelfSrcRest
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

/-- app::main::w -/
theorem lok0 : LiveOk prims outside liveBad 0 (src_app_main_w 1 2 5 6 7 8) := by decide +kernel

/-- app::main::oracle_read -/
theorem lok1 : LiveOk prims outside liveBad 1 (src_app_main_oracle_read 1 9) := by decide +kernel

/-- app::main::oracle_put -/
theorem lok2 : LiveOk prims outside liveBad 2 (src_app_main_oracle_put 3) := by decide +kernel

/-- app::main::oracle_write -/
theorem lok3 : LiveOk prims outside liveBad 3 (src_app_main_oracle_write 4 10) := by decide +kernel

/-- app::main::oracle_write_one -/
theorem lok4 : LiveOk prims outside liveBad 4 (src_app_main_oracle_write_one 3) := by decide +kernel

/-- core::mem::typed_slice_from_storage<mini::selfhost::List<i32>> -/
theorem lok34 : LiveOk prims outside liveBad 34 (src_core_mem_typed_slice_from_storage_of_mini_selfhost_List_i32) := by decide +kernel

/-- core::mem::size_of<mini::selfhost::List<i32>> -/
theorem lok49 : LiveOk prims outside liveBad 49 (src_core_mem_size_of_of_mini_selfhost_List_i32) := by decide +kernel

/-- core::mem::size_of<mini::selfhost::List<mini::selfhost::Rule>> -/
theorem lok72 : LiveOk prims outside liveBad 72 (src_core_mem_size_of_of_mini_selfhost_List_mini_selfhost_Rule) := by decide +kernel

/-- core::mem::typed_slice_from_storage<mini::selfhost::List<mini::selfhost::Rule>> -/
theorem lok73 : LiveOk prims outside liveBad 73 (src_core_mem_typed_slice_from_storage_of_mini_selfhost_List_mini_selfhost_Rule) := by decide +kernel

/-- core::mem::typed_slice_from_storage<mini::selfhost::List<mini::selfhost::SrcFunc>> -/
theorem lok82 : LiveOk prims outside liveBad 82 (src_core_mem_typed_slice_from_storage_of_mini_selfhost_List_mini_selfhost_SrcFunc) := by decide +kernel

/-- core::mem::size_of<mini::selfhost::List<mini::selfhost::Sym>> -/
theorem lok107 : LiveOk prims outside liveBad 107 (src_core_mem_size_of_of_mini_selfhost_List_mini_selfhost_Sym) := by decide +kernel

/-- core::mem::typed_slice_from_storage<mini::selfhost::List<mini::selfhost::Sym>> -/
theorem lok108 : LiveOk prims outside liveBad 108 (src_core_mem_typed_slice_from_storage_of_mini_selfhost_List_mini_selfhost_Sym) := by decide +kernel

/-- core::mem::typed_slice_from_storage<mini::selfhost::List<usize>> -/
theorem lok109 : LiveOk prims outside liveBad 109 (src_core_mem_typed_slice_from_storage_of_mini_selfhost_List_usize) := by decide +kernel

/-- core::mem::typed_slice_from_storage<mini::selfhost::List<u8>> -/
theorem lok111 : LiveOk prims outside liveBad 111 (src_core_mem_typed_slice_from_storage_of_mini_selfhost_List_u8) := by decide +kernel

/-- core::mem::typed_slice_from_storage<mini::selfhost::SrcStmt> -/
theorem lok112 : LiveOk prims outside liveBad 112 (src_core_mem_typed_slice_from_storage_of_mini_selfhost_SrcStmt) := by decide +kernel

/-- core::mem::typed_slice_from_storage<mini::selfhost::List<mini::selfhost::Sig>> -/
theorem lok132 : LiveOk prims outside liveBad 132 (src_core_mem_typed_slice_from_storage_of_mini_selfhost_List_mini_selfhost_Sig) := by decide +kernel

/-- core::mem::typed_slice_from_storage<mini::selfhost::List<mini::selfhost::FileInput>> -/
theorem lok152 : LiveOk prims outside liveBad 152 (src_core_mem_typed_slice_from_storage_of_mini_selfhost_List_mini_selfhost_FileInput) := by decide +kernel

/-- core::mem::typed_slice_from_storage<mini::selfhost::List<mini::selfhost::CTree>> -/
theorem lok165 : LiveOk prims outside liveBad 165 (src_core_mem_typed_slice_from_storage_of_mini_selfhost_List_mini_selfhost_CTree) := by decide +kernel

/-- mini::selfhost::compile_funcs -/
theorem lok170 : LiveOk prims outside liveBad 170 (src_compile_funcs 170 283 285 286 287) := by decide +kernel

/-- mini::selfhost::arities -/
theorem lok171 : LiveOk prims outside liveBad 171 (src_arities 171 283 288 289) := by decide +kernel

/-- mini::selfhost::lower_match -/
theorem lok201 : LiveOk prims outside liveBad 201 (src_lower_match 327) := by decide +kernel

/-- mini::selfhost::lower_match_arm -/
theorem lok232 : LiveOk prims outside liveBad 232 (src_lower_match_arm 183 384 385 386) := by decide +kernel

/-- core::mem::size_of<mini::selfhost::List<mini::selfhost::FileInput>> -/
theorem lok253 : LiveOk prims outside liveBad 253 (src_core_mem_size_of_of_mini_selfhost_List_mini_selfhost_FileInput) := by decide +kernel

/-- core::mem::size_of<mini::selfhost::List<mini::selfhost::List<mini::selfhost::List<usize>>>> -/
theorem lok278 : LiveOk prims outside liveBad 278 (src_core_mem_size_of_of_mini_selfhost_List_mini_selfhost_List_mini_selfhost_List_usize) := by decide +kernel

/-- core::mem::typed_slice_from_storage<mini::selfhost::List<mini::selfhost::List<mini::selfhost::List<usize>>>> -/
theorem lok279 : LiveOk prims outside liveBad 279 (src_core_mem_typed_slice_from_storage_of_mini_selfhost_List_mini_selfhost_List_mini_selfhost_List_usize) := by decide +kernel

/-- core::mem::typed_slice_from_storage<mini::selfhost::List<mini::selfhost::Token>> -/
theorem lok280 : LiveOk prims outside liveBad 280 (src_core_mem_typed_slice_from_storage_of_mini_selfhost_List_mini_selfhost_Token) := by decide +kernel

/-- core::mem::size_of<mini::selfhost::List<mini::selfhost::Func>> -/
theorem lok294 : LiveOk prims outside liveBad 294 (src_core_mem_size_of_of_mini_selfhost_List_mini_selfhost_Func) := by decide +kernel

/-- core::mem::typed_slice_from_storage<mini::selfhost::List<mini::selfhost::Func>> -/
theorem lok295 : LiveOk prims outside liveBad 295 (src_core_mem_typed_slice_from_storage_of_mini_selfhost_List_mini_selfhost_Func) := by decide +kernel

/-- core::mem::typed_slice_from_storage<mini::selfhost::List<mini::selfhost::SrcParam>> -/
theorem lok296 : LiveOk prims outside liveBad 296 (src_core_mem_typed_slice_from_storage_of_mini_selfhost_List_mini_selfhost_SrcParam) := by decide +kernel

/-- core::mem::typed_slice_from_storage<mini::selfhost::List<mini::selfhost::SrcType>> -/
theorem lok303 : LiveOk prims outside liveBad 303 (src_core_mem_typed_slice_from_storage_of_mini_selfhost_List_mini_selfhost_SrcType) := by decide +kernel

/-- core::mem::typed_slice_from_storage<mini::selfhost::List<mini::selfhost::List<mini::selfhost::SrcType>>> -/
theorem lok304 : LiveOk prims outside liveBad 304 (src_core_mem_typed_slice_from_storage_of_mini_selfhost_List_mini_selfhost_List_mini_selfhost_SrcType) := by decide +kernel

/-- core::mem::typed_slice_from_storage<mini::selfhost::SrcType> -/
theorem lok305 : LiveOk prims outside liveBad 305 (src_core_mem_typed_slice_from_storage_of_mini_selfhost_SrcType) := by decide +kernel

/-- core::mem::size_of<mini::selfhost::Stmt> -/
theorem lok309 : LiveOk prims outside liveBad 309 (src_core_mem_size_of_of_mini_selfhost_Stmt) := by decide +kernel

/-- core::mem::typed_slice_from_storage<mini::selfhost::Stmt> -/
theorem lok310 : LiveOk prims outside liveBad 310 (src_core_mem_typed_slice_from_storage_of_mini_selfhost_Stmt) := by decide +kernel

/-- mini::selfhost::lower_match_on -/
theorem lok327 : LiveOk prims outside liveBad 327 (src_lower_match_on 183 518) := by decide +kernel

/-- core::mem::size_of<mini::selfhost::SrcType> -/
theorem lok342 : LiveOk prims outside liveBad 342 (src_core_mem_size_of_of_mini_selfhost_SrcType) := by decide +kernel

/-- mini::selfhost::eval_not -/
theorem lok360 : LiveOk prims outside liveBad 360 (src_eval_not 550 552) := by decide +kernel

/-- mini::selfhost::eval_cast -/
theorem lok361 : LiveOk prims outside liveBad 361 (src_eval_cast 550 553) := by decide +kernel

/-- mini::selfhost::lower_arm_found -/
theorem lok384 : LiveOk prims outside liveBad 384 (src_lower_arm_found 572 573) := by decide +kernel

/-- core::mem::size_of<mini::selfhost::List<mini::selfhost::Sig>> -/
theorem lok401 : LiveOk prims outside liveBad 401 (src_core_mem_size_of_of_mini_selfhost_List_mini_selfhost_Sig) := by decide +kernel

/-- core::mem::size_of<mini::selfhost::List<mini::selfhost::CTree>> -/
theorem lok419 : LiveOk prims outside liveBad 419 (src_core_mem_size_of_of_mini_selfhost_List_mini_selfhost_CTree) := by decide +kernel

/-- core::mem::typed_slice_from_storage<mini::selfhost::List<mini::selfhost::FnDecl>> -/
theorem lok449 : LiveOk prims outside liveBad 449 (src_core_mem_typed_slice_from_storage_of_mini_selfhost_List_mini_selfhost_FnDecl) := by decide +kernel

/-- core::mem::typed_slice_from_storage<mini::selfhost::List<mini::selfhost::TypeDecl>> -/
theorem lok450 : LiveOk prims outside liveBad 450 (src_core_mem_typed_slice_from_storage_of_mini_selfhost_List_mini_selfhost_TypeDecl) := by decide +kernel

/-- mini::selfhost::size -/
theorem lok484 : LiveOk prims outside liveBad 484 (src_Code_size 75 480) := by decide +kernel

/-- mini::selfhost::layout -/
theorem lok486 : LiveOk prims outside liveBad 486 (src_layout 75 139 418 484 485 486) := by decide +kernel

/-- mini::selfhost::link_onto -/
theorem lok487 : LiveOk prims outside liveBad 487 (src_link_onto 75 484 485 487 754 755 756) := by decide +kernel

/-- core::mem::size_of<mini::selfhost::List<mini::selfhost::Expr>> -/
theorem lok494 : LiveOk prims outside liveBad 494 (src_core_mem_size_of_of_mini_selfhost_List_mini_selfhost_Expr) := by decide +kernel

/-- core::mem::typed_slice_from_storage<mini::selfhost::List<mini::selfhost::Expr>> -/
theorem lok495 : LiveOk prims outside liveBad 495 (src_core_mem_typed_slice_from_storage_of_mini_selfhost_List_mini_selfhost_Expr) := by decide +kernel

/-- core::mem::typed_slice_from_storage<mini::selfhost::SrcExpr> -/
theorem lok497 : LiveOk prims outside liveBad 497 (src_core_mem_typed_slice_from_storage_of_mini_selfhost_SrcExpr) := by decide +kernel

/-- core::mem::size_of<mini::selfhost::List<mini::selfhost::Binding>> -/
theorem lok513 : LiveOk prims outside liveBad 513 (src_core_mem_size_of_of_mini_selfhost_List_mini_selfhost_Binding) := by decide +kernel

/-- core::mem::typed_slice_from_storage<mini::selfhost::List<mini::selfhost::Binding>> -/
theorem lok514 : LiveOk prims outside liveBad 514 (src_core_mem_typed_slice_from_storage_of_mini_selfhost_List_mini_selfhost_Binding) := by decide +kernel

/-- core::mem::typed_slice_from_storage<mini::selfhost::List<mini::selfhost::SrcExpr>> -/
theorem lok515 : LiveOk prims outside liveBad 515 (src_core_mem_typed_slice_from_storage_of_mini_selfhost_List_mini_selfhost_SrcExpr) := by decide +kernel

/-- mini::selfhost::lower_match_arms -/
theorem lok518 : LiveOk prims outside liveBad 518 (src_lower_match_arms 120 185 385 770 771) := by decide +kernel

/-- core::mem::size_of<mini::selfhost::Expr> -/
theorem lok522 : LiveOk prims outside liveBad 522 (src_core_mem_size_of_of_mini_selfhost_Expr) := by decide +kernel

/-- core::mem::typed_slice_from_storage<mini::selfhost::Expr> -/
theorem lok523 : LiveOk prims outside liveBad 523 (src_core_mem_typed_slice_from_storage_of_mini_selfhost_Expr) := by decide +kernel

/-- core::mem::typed_slice_from_storage<mini::selfhost::List<mini::selfhost::SrcEff>> -/
theorem lok547 : LiveOk prims outside liveBad 547 (src_core_mem_typed_slice_from_storage_of_mini_selfhost_List_mini_selfhost_SrcEff) := by decide +kernel

/-- core::mem::typed_slice_from_storage<mini::selfhost::SrcEff> -/
theorem lok549 : LiveOk prims outside liveBad 549 (src_core_mem_typed_slice_from_storage_of_mini_selfhost_SrcEff) := by decide +kernel

/-- mini::selfhost::lower_arm_stmt -/
theorem lok572 : LiveOk prims outside liveBad 572 (src_lower_arm_stmt 188 316 337) := by decide +kernel

/-- mini::selfhost::arm_payload -/
theorem lok573 : LiveOk prims outside liveBad 573 (src_arm_payload 75 120 139 375 418 820 821 822) := by decide +kernel

/-- core::mem::size_of<mini::selfhost::List<mini::selfhost::SrcType>> -/
theorem lok578 : LiveOk prims outside liveBad 578 (src_core_mem_size_of_of_mini_selfhost_List_mini_selfhost_SrcType) := by decide +kernel

/-- mini::selfhost::facts_after -/
theorem lok699 : LiveOk prims outside liveBad 699 (src_Stmt_facts_after 282 307 699 1018 1019) := by decide +kernel

/-- mini::selfhost::is_skip -/
theorem lok706 : LiveOk prims outside liveBad 706 (src_Stmt_is_skip) := by decide +kernel

/-- mini::selfhost::is_brk -/
theorem lok718 : LiveOk prims outside liveBad 718 (src_Stmt_is_brk) := by decide +kernel

/-- mini::selfhost::is_cont -/
theorem lok719 : LiveOk prims outside liveBad 719 (src_Stmt_is_cont) := by decide +kernel

/-- core::mem::size_of<mini::selfhost::List<mini::selfhost::Code>> -/
theorem lok750 : LiveOk prims outside liveBad 750 (src_core_mem_size_of_of_mini_selfhost_List_mini_selfhost_Code) := by decide +kernel

/-- core::mem::typed_slice_from_storage<mini::selfhost::List<mini::selfhost::Code>> -/
theorem lok751 : LiveOk prims outside liveBad 751 (src_core_mem_typed_slice_from_storage_of_mini_selfhost_List_mini_selfhost_Code) := by decide +kernel

/-- core::mem::size_of<mini::selfhost::List<mini::selfhost::Arity>> -/
theorem lok752 : LiveOk prims outside liveBad 752 (src_core_mem_size_of_of_mini_selfhost_List_mini_selfhost_Arity) := by decide +kernel

/-- core::mem::typed_slice_from_storage<mini::selfhost::List<mini::selfhost::Arity>> -/
theorem lok753 : LiveOk prims outside liveBad 753 (src_core_mem_typed_slice_from_storage_of_mini_selfhost_List_mini_selfhost_Arity) := by decide +kernel

/-- mini::selfhost::prologue -/
theorem lok755 : LiveOk prims outside liveBad 755 (src_prologue 754 1042 1043 1044 1045 1046) := by decide +kernel

/-- mini::selfhost::encode_onto -/
theorem lok756 : LiveOk prims outside liveBad 756 (src_encode_onto 75 741 749 754 756 1047) := by decide +kernel

/-- core::mem::size_of<mini::selfhost::List<usize>> -/
theorem lok757 : LiveOk prims outside liveBad 757 (src_core_mem_size_of_of_mini_selfhost_List_usize) := by decide +kernel

/-- core::mem::typed_slice_from_storage<mini::selfhost::List<mini::selfhost::List<usize>>> -/
theorem lok807 : LiveOk prims outside liveBad 807 (src_core_mem_typed_slice_from_storage_of_mini_selfhost_List_mini_selfhost_List_usize) := by decide +kernel

/-- core::mem::typed_slice_from_storage<mini::selfhost::List<u64>> -/
theorem lok823 : LiveOk prims outside liveBad 823 (src_core_mem_typed_slice_from_storage_of_mini_selfhost_List_u64) := by decide +kernel

/-- core::mem::typed_slice_from_storage<mini::selfhost::List<mini::selfhost::SrcStructDecl>> -/
theorem lok827 : LiveOk prims outside liveBad 827 (src_core_mem_typed_slice_from_storage_of_mini_selfhost_List_mini_selfhost_SrcStructDecl) := by decide +kernel

/-- core::mem::typed_slice_from_storage<mini::selfhost::List<mini::selfhost::SrcEnumDecl>> -/
theorem lok829 : LiveOk prims outside liveBad 829 (src_core_mem_typed_slice_from_storage_of_mini_selfhost_List_mini_selfhost_SrcEnumDecl) := by decide +kernel

/-- core::mem::typed_slice_from_storage<mini::selfhost::List<mini::selfhost::RawTok>> -/
theorem lok836 : LiveOk prims outside liveBad 836 (src_core_mem_typed_slice_from_storage_of_mini_selfhost_List_mini_selfhost_RawTok) := by decide +kernel

/-- core::mem::typed_slice_from_storage<mini::selfhost::List<mini::selfhost::AliasDecl>> -/
theorem lok951 : LiveOk prims outside liveBad 951 (src_core_mem_typed_slice_from_storage_of_mini_selfhost_List_mini_selfhost_AliasDecl) := by decide +kernel

/-- core::mem::typed_slice_from_storage<mini::selfhost::List<mini::selfhost::Ty>> -/
theorem lok976 : LiveOk prims outside liveBad 976 (src_core_mem_typed_slice_from_storage_of_mini_selfhost_List_mini_selfhost_Ty) := by decide +kernel

/-- core::mem::size_of<mini::selfhost::List<mini::selfhost::Ty>> -/
theorem lok980 : LiveOk prims outside liveBad 980 (src_core_mem_size_of_of_mini_selfhost_List_mini_selfhost_Ty) := by decide +kernel

/-- core::mem::typed_slice_from_storage<mini::selfhost::List<mini::selfhost::Inst>> -/
theorem lok981 : LiveOk prims outside liveBad 981 (src_core_mem_typed_slice_from_storage_of_mini_selfhost_List_mini_selfhost_Inst) := by decide +kernel

/-- core::mem::typed_slice_from_storage<mini::selfhost::List<mini::selfhost::MFunc>> -/
theorem lok986 : LiveOk prims outside liveBad 986 (src_core_mem_typed_slice_from_storage_of_mini_selfhost_List_mini_selfhost_MFunc) := by decide +kernel

/-- core::mem::size_of<mini::selfhost::List<mini::selfhost::Inst>> -/
theorem lok1001 : LiveOk prims outside liveBad 1001 (src_core_mem_size_of_of_mini_selfhost_List_mini_selfhost_Inst) := by decide +kernel

/-- core::mem::size_of<mini::selfhost::List<mini::selfhost::TypeDecl>> -/
theorem lok1002 : LiveOk prims outside liveBad 1002 (src_core_mem_size_of_of_mini_selfhost_List_mini_selfhost_TypeDecl) := by decide +kernel

/-- core::mem::size_of<mini::selfhost::List<mini::selfhost::FnDecl>> -/
theorem lok1003 : LiveOk prims outside liveBad 1003 (src_core_mem_size_of_of_mini_selfhost_List_mini_selfhost_FnDecl) := by decide +kernel

/-- core::mem::size_of<mini::selfhost::List<mini::selfhost::ConstDecl>> -/
theorem lok1004 : LiveOk prims outside liveBad 1004 (src_core_mem_size_of_of_mini_selfhost_List_mini_selfhost_ConstDecl) := by decide +kernel

/-- core::mem::typed_slice_from_storage<mini::selfhost::List<mini::selfhost::ConstDecl>> -/
theorem lok1005 : LiveOk prims outside liveBad 1005 (src_core_mem_typed_slice_from_storage_of_mini_selfhost_List_mini_selfhost_ConstDecl) := by decide +kernel

/-- core::mem::size_of<mini::selfhost::List<mini::selfhost::ImportDecl>> -/
theorem lok1006 : LiveOk prims outside liveBad 1006 (src_core_mem_size_of_of_mini_selfhost_List_mini_selfhost_ImportDecl) := by decide +kernel

/-- core::mem::typed_slice_from_storage<mini::selfhost::List<mini::selfhost::ImportDecl>> -/
theorem lok1007 : LiveOk prims outside liveBad 1007 (src_core_mem_typed_slice_from_storage_of_mini_selfhost_List_mini_selfhost_ImportDecl) := by decide +kernel

/-- core::mem::size_of<mini::selfhost::List<mini::selfhost::AliasDecl>> -/
theorem lok1008 : LiveOk prims outside liveBad 1008 (src_core_mem_size_of_of_mini_selfhost_List_mini_selfhost_AliasDecl) := by decide +kernel

/-- core::mem::size_of<mini::selfhost::List<mini::selfhost::ImplDecl>> -/
theorem lok1009 : LiveOk prims outside liveBad 1009 (src_core_mem_size_of_of_mini_selfhost_List_mini_selfhost_ImplDecl) := by decide +kernel

/-- core::mem::typed_slice_from_storage<mini::selfhost::List<mini::selfhost::ImplDecl>> -/
theorem lok1010 : LiveOk prims outside liveBad 1010 (src_core_mem_typed_slice_from_storage_of_mini_selfhost_List_mini_selfhost_ImplDecl) := by decide +kernel

/-- mini::selfhost::assigned -/
theorem lok1018 : LiveOk prims outside liveBad 1018 (src_assigned 464 1019 1262 1263 1264 1265) := by decide +kernel

/-- core::mem::size_of<mini::selfhost::List<mini::selfhost::Instr>> -/
theorem lok1034 : LiveOk prims outside liveBad 1034 (src_core_mem_size_of_of_mini_selfhost_List_mini_selfhost_Instr) := by decide +kernel

/-- core::mem::typed_slice_from_storage<mini::selfhost::List<mini::selfhost::Instr>> -/
theorem lok1035 : LiveOk prims outside liveBad 1035 (src_core_mem_typed_slice_from_storage_of_mini_selfhost_List_mini_selfhost_Instr) := by decide +kernel

/-- mini::selfhost::le32 -/
theorem lok1044 : LiveOk prims outside liveBad 1044 (src_le32 1042 1043) := by decide +kernel

/-- mini::selfhost::frame_size -/
theorem lok1045 : LiveOk prims outside liveBad 1045 (src_frame_size 75 105) := by decide +kernel

/-- mini::selfhost::stack_check -/
theorem lok1046 : LiveOk prims outside liveBad 1046 (src_stack_check 1042 1043) := by decide +kernel

/-- mini::selfhost::encode -/
theorem lok1047 : LiveOk prims outside liveBad 1047 (src_Instr_encode 52 75 105 136 754 1042 1043 1044 1282 1283 1284 1285 1286 1287 1288 1289 1290 1291 1292 1293 1294 1295 1296 1297 1298 1299 1300 1301 1302) := by decide +kernel

/-- mini::selfhost::arith -/
theorem lok1052 : LiveOk prims outside liveBad 1052 (src_arith 337 338 391 800 802 803 810 1304 1305 1306 1307) := by decide +kernel

/-- core::mem::size_of<mini::selfhost::List<u64>> -/
theorem lok1095 : LiveOk prims outside liveBad 1095 (src_core_mem_size_of_of_mini_selfhost_List_u64) := by decide +kernel

/-- core::mem::size_of<mini::selfhost::List<mini::selfhost::SrcStructDecl>> -/
theorem lok1097 : LiveOk prims outside liveBad 1097 (src_core_mem_size_of_of_mini_selfhost_List_mini_selfhost_SrcStructDecl) := by decide +kernel

/-- core::mem::size_of<mini::selfhost::List<mini::selfhost::SrcEnumDecl>> -/
theorem lok1098 : LiveOk prims outside liveBad 1098 (src_core_mem_size_of_of_mini_selfhost_List_mini_selfhost_SrcEnumDecl) := by decide +kernel

/-- core::mem::size_of<mini::selfhost::List<mini::selfhost::SymRule>> -/
theorem lok1111 : LiveOk prims outside liveBad 1111 (src_core_mem_size_of_of_mini_selfhost_List_mini_selfhost_SymRule) := by decide +kernel

/-- core::mem::typed_slice_from_storage<mini::selfhost::List<mini::selfhost::SymRule>> -/
theorem lok1112 : LiveOk prims outside liveBad 1112 (src_core_mem_typed_slice_from_storage_of_mini_selfhost_List_mini_selfhost_SymRule) := by decide +kernel

/-- core::mem::size_of<mini::selfhost::List<mini::selfhost::List<usize>>> -/
theorem lok1140 : LiveOk prims outside liveBad 1140 (src_core_mem_size_of_of_mini_selfhost_List_mini_selfhost_List_usize) := by decide +kernel

/-- core::mem::typed_slice_from_storage<mini::selfhost::List<core::option::Option<usize>>> -/
theorem lok1217 : LiveOk prims outside liveBad 1217 (src_core_mem_typed_slice_from_storage_of_mini_selfhost_List_core_option_Option_usize) := by decide +kernel

/-- core::mem::typed_slice_from_storage<mini::selfhost::Ty> -/
theorem lok1222 : LiveOk prims outside liveBad 1222 (src_core_mem_typed_slice_from_storage_of_mini_selfhost_Ty) := by decide +kernel

/-- core::mem::typed_slice_from_storage<mini::selfhost::List<mini::selfhost::MParam>> -/
theorem lok1224 : LiveOk prims outside liveBad 1224 (src_core_mem_typed_slice_from_storage_of_mini_selfhost_List_mini_selfhost_MParam) := by decide +kernel

/-- core::mem::typed_slice_from_storage<mini::selfhost::MStmt> -/
theorem lok1225 : LiveOk prims outside liveBad 1225 (src_core_mem_typed_slice_from_storage_of_mini_selfhost_MStmt) := by decide +kernel

/-- core::mem::size_of<mini::selfhost::Ty> -/
theorem lok1226 : LiveOk prims outside liveBad 1226 (src_core_mem_size_of_of_mini_selfhost_Ty) := by decide +kernel

/-- core::mem::size_of<mini::selfhost::List<mini::selfhost::MFunc>> -/
theorem lok1231 : LiveOk prims outside liveBad 1231 (src_core_mem_size_of_of_mini_selfhost_List_mini_selfhost_MFunc) := by decide +kernel

/-- core::mem::typed_slice_from_storage<mini::selfhost::List<mini::selfhost::Fact>> -/
theorem lok1261 : LiveOk prims outside liveBad 1261 (src_core_mem_typed_slice_from_storage_of_mini_selfhost_List_mini_selfhost_Fact) := by decide +kernel

/-- mini::selfhost::trim_facts -/
theorem lok1265 : LiveOk prims outside liveBad 1265 (src_trim_facts 1488 1489) := by decide +kernel

/-- mini::selfhost::ignores -/
theorem lok1268 : LiveOk prims outside liveBad 1268 (src_Stmt_ignores 307 1263 1268 1270) := by decide +kernel

/-- mini::selfhost::jumps -/
theorem lok1269 : LiveOk prims outside liveBad 1269 (src_Stmt_jumps 307 1269) := by decide +kernel

/-- core::mem::size_of<mini::selfhost::List<u8>> -/
theorem lok1281 : LiveOk prims outside liveBad 1281 (src_core_mem_size_of_of_mini_selfhost_List_u8) := by decide +kernel

/-- mini::selfhost::le64 -/
theorem lok1282 : LiveOk prims outside liveBad 1282 (src_le64 1042 1043) := by decide +kernel

/-- mini::selfhost::slot_load -/
theorem lok1283 : LiveOk prims outside liveBad 1283 (src_slot_load 754 1042 1043 1044 1498) := by decide +kernel

/-- mini::selfhost::slot_store -/
theorem lok1284 : LiveOk prims outside liveBad 1284 (src_slot_store 754 1042 1043 1044 1498) := by decide +kernel

/-- mini::selfhost::bytes -/
theorem lok1285 : LiveOk prims outside liveBad 1285 (src_BinOp_bytes 754 1499 1500 1501) := by decide +kernel

/-- mini::selfhost::slot_compare -/
theorem lok1286 : LiveOk prims outside liveBad 1286 (src_slot_compare 754 1042 1043 1499 1500 1502) := by decide +kernel

/-- mini::selfhost::relative -/
theorem lok1287 : LiveOk prims outside liveBad 1287 (src_relative) := by decide +kernel

/-- mini::selfhost::copy_bytes -/
theorem lok1288 : LiveOk prims outside liveBad 1288 (src_copy_bytes 75 76 110 754 1283 1284 1288) := by decide +kernel

/-- mini::selfhost::arg_base -/
theorem lok1289 : LiveOk prims outside liveBad 1289 (src_arg_base 75 1045) := by decide +kernel

/-- mini::selfhost::fsp_save -/
theorem lok1290 : LiveOk prims outside liveBad 1290 (src_fsp_save 754 1042 1043 1044 1498) := by decide +kernel

/-- mini::selfhost::fsp_load -/
theorem lok1291 : LiveOk prims outside liveBad 1291 (src_fsp_load 754 1042 1043 1044 1498) := by decide +kernel

/-- mini::selfhost::slot_range -/
theorem lok1292 : LiveOk prims outside liveBad 1292 (src_slot_range 56 75 139 418 1292) := by decide +kernel

/-- mini::selfhost::epilogue -/
theorem lok1293 : LiveOk prims outside liveBad 1293 (src_epilogue 1042 1043) := by decide +kernel

/-- mini::selfhost::load_at_bytes -/
theorem lok1295 : LiveOk prims outside liveBad 1295 (src_load_at_bytes 1042 1043) := by decide +kernel

/-- mini::selfhost::store_at_bytes -/
theorem lok1296 : LiveOk prims outside liveBad 1296 (src_store_at_bytes 754 1042 1043 1044 1498) := by decide +kernel

/-- mini::selfhost::load_word_bytes -/
theorem lok1297 : LiveOk prims outside liveBad 1297 (src_load_word_bytes 754 1042 1043 1504) := by decide +kernel

/-- mini::selfhost::store_word_bytes -/
theorem lok1298 : LiveOk prims outside liveBad 1298 (src_store_word_bytes 754 1042 1043 1044 1498 1504) := by decide +kernel

/-- mini::selfhost::bytes -/
theorem lok1299 : LiveOk prims outside liveBad 1299 (src_DivOp_bytes 754 1042 1043 1499 1500 1505 1506 1507) := by decide +kernel

/-- mini::selfhost::sys_bytes -/
theorem lok1301 : LiveOk prims outside liveBad 1301 (src_sys_bytes 75 754 1042 1043 1044 1498 1509 1510 1511) := by decide +kernel

/-- mini::selfhost::float_arith -/
theorem lok1304 : LiveOk prims outside liveBad 1304 (src_float_arith 1512) := by decide +kernel

/-- mini::selfhost::float_order -/
theorem lok1309 : LiveOk prims outside liveBad 1309 (src_float_order 1515) := by decide +kernel

/-- core::mem::typed_slice_from_storage<mini::selfhost::List<mini::selfhost::SrcArm>> -/
theorem lok1324 : LiveOk prims outside liveBad 1324 (src_core_mem_typed_slice_from_storage_of_mini_selfhost_List_mini_selfhost_SrcArm) := by decide +kernel

/-- core::mem::size_of<mini::selfhost::List<mini::selfhost::RawTok>> -/
theorem lok1343 : LiveOk prims outside liveBad 1343 (src_core_mem_size_of_of_mini_selfhost_List_mini_selfhost_RawTok) := by decide +kernel

/-- core::mem::size_of<mini::selfhost::List<mini::selfhost::Token>> -/
theorem lok1344 : LiveOk prims outside liveBad 1344 (src_core_mem_size_of_of_mini_selfhost_List_mini_selfhost_Token) := by decide +kernel

/-- core::mem::size_of<mini::selfhost::List<core::option::Option<mini::selfhost::SrcType>>> -/
theorem lok1389 : LiveOk prims outside liveBad 1389 (src_core_mem_size_of_of_mini_selfhost_List_core_option_Option_mini_selfhost_SrcType) := by decide +kernel

/-- core::mem::typed_slice_from_storage<mini::selfhost::List<core::option::Option<mini::selfhost::SrcType>>> -/
theorem lok1390 : LiveOk prims outside liveBad 1390 (src_core_mem_typed_slice_from_storage_of_mini_selfhost_List_core_option_Option_mini_selfhost_SrcType) := by decide +kernel

/-- core::mem::size_of<mini::selfhost::List<mini::selfhost::SrcFunc>> -/
theorem lok1423 : LiveOk prims outside liveBad 1423 (src_core_mem_size_of_of_mini_selfhost_List_mini_selfhost_SrcFunc) := by decide +kernel

/-- core::mem::size_of<mini::selfhost::SrcStmt> -/
theorem lok1434 : LiveOk prims outside liveBad 1434 (src_core_mem_size_of_of_mini_selfhost_SrcStmt) := by decide +kernel

/-- core::mem::size_of<mini::selfhost::List<core::option::Option<usize>>> -/
theorem lok1455 : LiveOk prims outside liveBad 1455 (src_core_mem_size_of_of_mini_selfhost_List_core_option_Option_usize) := by decide +kernel

/-- core::mem::typed_slice_from_storage<mini::selfhost::List<mini::selfhost::MEff>> -/
theorem lok1459 : LiveOk prims outside liveBad 1459 (src_core_mem_typed_slice_from_storage_of_mini_selfhost_List_mini_selfhost_MEff) := by decide +kernel

/-- core::mem::typed_slice_from_storage<mini::selfhost::MEff> -/
theorem lok1460 : LiveOk prims outside liveBad 1460 (src_core_mem_typed_slice_from_storage_of_mini_selfhost_MEff) := by decide +kernel

/-- core::mem::size_of<mini::selfhost::MStmt> -/
theorem lok1469 : LiveOk prims outside liveBad 1469 (src_core_mem_size_of_of_mini_selfhost_MStmt) := by decide +kernel

/-- core::mem::size_of<mini::selfhost::List<mini::selfhost::MEff>> -/
theorem lok1470 : LiveOk prims outside liveBad 1470 (src_core_mem_size_of_of_mini_selfhost_List_mini_selfhost_MEff) := by decide +kernel

/-- core::mem::size_of<mini::selfhost::List<mini::selfhost::MParam>> -/
theorem lok1482 : LiveOk prims outside liveBad 1482 (src_core_mem_size_of_of_mini_selfhost_List_mini_selfhost_MParam) := by decide +kernel

/-- mini::selfhost::longer -/
theorem lok1488 : LiveOk prims outside liveBad 1488 (src_longer 56 1017 1488) := by decide +kernel

/-- mini::selfhost::slot_offset -/
theorem lok1498 : LiveOk prims outside liveBad 1498 (src_slot_offset 75 105) := by decide +kernel

/-- mini::selfhost::slot_operands -/
theorem lok1499 : LiveOk prims outside liveBad 1499 (src_slot_operands 754 1042 1043 1283) := by decide +kernel

/-- mini::selfhost::rex -/
theorem lok1500 : LiveOk prims outside liveBad 1500 (src_Word_rex 110 1043) := by decide +kernel

/-- mini::selfhost::opcode -/
theorem lok1501 : LiveOk prims outside liveBad 1501 (src_BinOp_opcode 1042 1043) := by decide +kernel

/-- mini::selfhost::setcc -/
theorem lok1502 : LiveOk prims outside liveBad 1502 (src_CmpOp_setcc 1628 1629) := by decide +kernel

/-- mini::selfhost::extend -/
theorem lok1505 : LiveOk prims outside liveBad 1505 (src_DivOp_extend 754 1042 1043 1500) := by decide +kernel

/-- mini::selfhost::opcode -/
theorem lok1506 : LiveOk prims outside liveBad 1506 (src_DivOp_opcode 1042 1043) := by decide +kernel

/-- mini::selfhost::result -/
theorem lok1507 : LiveOk prims outside liveBad 1507 (src_DivOp_result 110 1042 1043) := by decide +kernel

/-- mini::selfhost::syscall_rsi_bytes -/
theorem lok1509 : LiveOk prims outside liveBad 1509 (src_syscall_rsi_bytes 1042 1043) := by decide +kernel

/-- mini::selfhost::syscall_linux_byte -/
theorem lok1510 : LiveOk prims outside liveBad 1510 (src_syscall_linux_byte) := by decide +kernel

/-- mini::selfhost::syscall_linux_high -/
theorem lok1511 : LiveOk prims outside liveBad 1511 (src_syscall_linux_high) := by decide +kernel

/-- core::mem::size_of<mini::selfhost::SrcExpr> -/
theorem lok1566 : LiveOk prims outside liveBad 1566 (src_core_mem_size_of_of_mini_selfhost_SrcExpr) := by decide +kernel

/-- core::mem::typed_slice_from_storage<mini::selfhost::List<mini::selfhost::LocalTy>> -/
theorem lok1578 : LiveOk prims outside liveBad 1578 (src_core_mem_typed_slice_from_storage_of_mini_selfhost_List_mini_selfhost_LocalTy) := by decide +kernel

/-- core::mem::size_of<mini::selfhost::List<mini::selfhost::SrcEff>> -/
theorem lok1579 : LiveOk prims outside liveBad 1579 (src_core_mem_size_of_of_mini_selfhost_List_mini_selfhost_SrcEff) := by decide +kernel

/-- core::mem::size_of<mini::selfhost::SrcEff> -/
theorem lok1581 : LiveOk prims outside liveBad 1581 (src_core_mem_size_of_of_mini_selfhost_SrcEff) := by decide +kernel

/-- core::mem::size_of<mini::selfhost::List<mini::selfhost::LocalTy>> -/
theorem lok1585 : LiveOk prims outside liveBad 1585 (src_core_mem_size_of_of_mini_selfhost_List_mini_selfhost_LocalTy) := by decide +kernel

/-- mini::selfhost::type_path_spellings -/
theorem lok1609 : LiveOk prims outside liveBad 1609 (src_type_path_spellings 56 153 156 627 628 647 649 1609 1685 1686 1687) := by decide +kernel

/-- mini::selfhost::is_ref_ty -/
theorem lok1615 : LiveOk prims outside liveBad 1615 (src_is_ref_ty 1698 1699) := by decide +kernel

/-- core::mem::size_of<mini::selfhost::List<mini::selfhost::Fact>> -/
theorem lok1623 : LiveOk prims outside liveBad 1623 (src_core_mem_size_of_of_mini_selfhost_List_mini_selfhost_Fact) := by decide +kernel

/-- mini::selfhost::setcc_signed -/
theorem lok1628 : LiveOk prims outside liveBad 1628 (src_CmpOp_setcc_signed) := by decide +kernel

/-- mini::selfhost::setcc_unsigned -/
theorem lok1629 : LiveOk prims outside liveBad 1629 (src_CmpOp_setcc_unsigned) := by decide +kernel

/-- mini::selfhost::float_apply -/
theorem lok1635 : LiveOk prims outside liveBad 1635 (src_float_apply 337) := by decide +kernel

/-- mini::selfhost::float_compare -/
theorem lok1637 : LiveOk prims outside liveBad 1637 (src_float_compare 337) := by decide +kernel

/-- core::mem::size_of<mini::selfhost::List<mini::selfhost::SrcParam>> -/
theorem lok1649 : LiveOk prims outside liveBad 1649 (src_core_mem_size_of_of_mini_selfhost_List_mini_selfhost_SrcParam) := by decide +kernel

/-- core::mem::size_of<mini::selfhost::List<mini::selfhost::List<mini::selfhost::SrcType>>> -/
theorem lok1652 : LiveOk prims outside liveBad 1652 (src_core_mem_size_of_of_mini_selfhost_List_mini_selfhost_List_mini_selfhost_SrcType) := by decide +kernel

/-- core::mem::typed_slice_from_storage<mini::selfhost::List<mini::selfhost::List<mini::selfhost::Ty>>> -/
theorem lok1654 : LiveOk prims outside liveBad 1654 (src_core_mem_typed_slice_from_storage_of_mini_selfhost_List_mini_selfhost_List_mini_selfhost_Ty) := by decide +kernel

/-- core::mem::size_of<mini::selfhost::List<mini::selfhost::SrcExpr>> -/
theorem lok1668 : LiveOk prims outside liveBad 1668 (src_core_mem_size_of_of_mini_selfhost_List_mini_selfhost_SrcExpr) := by decide +kernel

/-- core::mem::size_of<mini::selfhost::List<mini::selfhost::SrcArm>> -/
theorem lok1669 : LiveOk prims outside liveBad 1669 (src_core_mem_size_of_of_mini_selfhost_List_mini_selfhost_SrcArm) := by decide +kernel

/-- mini::selfhost::referent -/
theorem lok1699 : LiveOk prims outside liveBad 1699 (src_referent 977) := by decide +kernel

/-- mini::selfhost::eff_of -/
theorem lok1706 : LiveOk prims outside liveBad 1706 (src_eff_of 56 1766 1767) := by decide +kernel

/-- core::mem::size_of<mini::selfhost::List<mini::selfhost::List<mini::selfhost::CTree>>> -/
theorem lok1732 : LiveOk prims outside liveBad 1732 (src_core_mem_size_of_of_mini_selfhost_List_mini_selfhost_List_mini_selfhost_CTree) := by decide +kernel

/-- core::mem::typed_slice_from_storage<mini::selfhost::List<mini::selfhost::List<mini::selfhost::CTree>>> -/
theorem lok1733 : LiveOk prims outside liveBad 1733 (src_core_mem_typed_slice_from_storage_of_mini_selfhost_List_mini_selfhost_List_mini_selfhost_CTree) := by decide +kernel

/-- core::mem::typed_slice_from_storage<mini::selfhost::List<mini::selfhost::Local>> -/
theorem lok1743 : LiveOk prims outside liveBad 1743 (src_core_mem_typed_slice_from_storage_of_mini_selfhost_List_mini_selfhost_Local) := by decide +kernel

/-- core::mem::size_of<mini::selfhost::List<mini::selfhost::Local>> -/
theorem lok1744 : LiveOk prims outside liveBad 1744 (src_core_mem_size_of_of_mini_selfhost_List_mini_selfhost_Local) := by decide +kernel

/-- mini::selfhost::split_last -/
theorem lok1750 : LiveOk prims outside liveBad 1750 (src_split_last 558 1750 1787) := by decide +kernel

/-- core::mem::typed_slice_from_storage<mini::selfhost::List<mini::selfhost::BoundGoal>> -/
theorem lok1759 : LiveOk prims outside liveBad 1759 (src_core_mem_typed_slice_from_storage_of_mini_selfhost_List_mini_selfhost_BoundGoal) := by decide +kernel

/-- mini::selfhost::eff_node -/
theorem lok1767 : LiveOk prims outside liveBad 1767 (src_eff_node 56 153 156 606 1706 1764 1796 1803 1804 1805 1807 1809 1811 1813 1816 1829 1830 1831 1832 1833 1834 1835 1836 1837 1838) := by decide +kernel

/-- mini::selfhost::split_more -/
theorem lok1787 : LiveOk prims outside liveBad 1787 (src_split_more 265 1141) := by decide +kernel

/-- mini::selfhost::eff_fold -/
theorem lok1829 : LiveOk prims outside liveBad 1829 (src_eff_fold 56 153 156 606 1706 1829 1885) := by decide +kernel

/-- mini::selfhost::eff_postfix -/
theorem lok1833 : LiveOk prims outside liveBad 1833 (src_eff_postfix 56 153 156 1706 1767 1796 1797 1798 1802 1820 1889 1890 1891 1892 1893 1894 1895 1896) := by decide +kernel

/-- mini::selfhost::eff_ident -/
theorem lok1834 : LiveOk prims outside liveBad 1834 (src_eff_ident 56 96 153 155 156 163 429 454 1185 1688 1750 1752 1797 1820 1897 1898 1899 1900 1901 1902 1903 1904) := by decide +kernel

/-- mini::selfhost::eff_match -/
theorem lok1836 : LiveOk prims outside liveBad 1836 (src_eff_match 56 156 1706 1905) := by decide +kernel

/-- mini::selfhost::eff_array -/
theorem lok1838 : LiveOk prims outside liveBad 1838 (src_eff_array 56 153 155 156 627 628 914 1682 1706 1906 1907 1908 1909 1910 1911) := by decide +kernel

/-- core::mem::size_of<mini::selfhost::List<mini::selfhost::BoundGoal>> -/
theorem lok1855 : LiveOk prims outside liveBad 1855 (src_core_mem_size_of_of_mini_selfhost_List_mini_selfhost_BoundGoal) := by decide +kernel

/-- mini::selfhost::eff_path_call -/
theorem lok1890 : LiveOk prims outside liveBad 1890 (src_eff_path_call 56 155 156 429 647 2005 2006 2007 2008 2009 2010 2011 2012 2013 2014 2015) := by decide +kernel

/-- mini::selfhost::eff_method -/
theorem lok1892 : LiveOk prims outside liveBad 1892 (src_eff_method 56 155 156 161 627 628 1820 2017 2018 2019) := by decide +kernel

/-- mini::selfhost::eff_chain -/
theorem lok1895 : LiveOk prims outside liveBad 1895 (src_eff_chain 56 153 1798 2020) := by decide +kernel

/-- mini::selfhost::eff_primary -/
theorem lok1896 : LiveOk prims outside liveBad 1896 (src_eff_primary 1767 1820) := by decide +kernel

/-- mini::selfhost::eff_variant -/
theorem lok1901 : LiveOk prims outside liveBad 1901 (src_eff_variant 56 163 1185 1897 1910 2022 2023 2024 2025) := by decide +kernel

/-- mini::selfhost::eff_literal -/
theorem lok1904 : LiveOk prims outside liveBad 1904 (src_eff_literal 56 1897 1910 2022 2023 2030 2031 2032 2033) := by decide +kernel

/-- mini::selfhost::eff_match_on -/
theorem lok1905 : LiveOk prims outside liveBad 1905 (src_eff_match_on 56 155 156 163 628 1185 1233 1393 1910 2034 2035 2036 2037 2038 2039) := by decide +kernel

/-- mini::selfhost::eff_list -/
theorem lok1910 : LiveOk prims outside liveBad 1910 (src_eff_list 56 103 1471 1706 1910 2043 2044 2045) := by decide +kernel

/-- mini::selfhost::match_primary -/
theorem lok1945 : LiveOk prims outside liveBad 1945 (src_match_primary 153 156 606 1795 1803 1805 1860 2066) := by decide +kernel

/-- core::mem::size_of<mini::selfhost::List<mini::selfhost::List<mini::selfhost::Ty>>> -/
theorem lok1951 : LiveOk prims outside liveBad 1951 (src_core_mem_size_of_of_mini_selfhost_List_mini_selfhost_List_mini_selfhost_Ty) := by decide +kernel

/-- core::mem::size_of<mini::selfhost::MEff> -/
theorem lok2004 : LiveOk prims outside liveBad 2004 (src_core_mem_size_of_of_mini_selfhost_MEff) := by decide +kernel

/-- mini::selfhost::stride_arg -/
theorem lok2010 : LiveOk prims outside liveBad 2010 (src_stride_arg 103 1795 2116) := by decide +kernel

/-- mini::selfhost::len_arg -/
theorem lok2012 : LiveOk prims outside liveBad 2012 (src_len_arg 103 1795 2117) := by decide +kernel

/-- mini::selfhost::eff_named -/
theorem lok2015 : LiveOk prims outside liveBad 2015 (src_eff_named 56 1901 1902 2121 2122 2123) := by decide +kernel

/-- mini::selfhost::eff_found_with -/
theorem lok2017 : LiveOk prims outside liveBad 2017 (src_eff_found_with 56 161 680 2124 2125) := by decide +kernel

/-- mini::selfhost::eff_step -/
theorem lok2020 : LiveOk prims outside liveBad 2020 (src_eff_step 56 153 155 156 627 628 1350 1706 1801 1802 1893 1894 1895 2016 2017 2019 2034 2127 2128 2129 2130 2131 2132) := by decide +kernel

/-- mini::selfhost::eff_match_enum -/
theorem lok2036 : LiveOk prims outside liveBad 2036 (src_eff_match_enum 56 155 156 2152 2153 2154) := by decide +kernel

/-- mini::selfhost::is_str_type -/
theorem lok2046 : LiveOk prims outside liveBad 2046 (src_is_str_type 153 156 647 1606 1607 1609 2005 2159) := by decide +kernel

/-- mini::selfhost::string_init -/
theorem lok2047 : LiveOk prims outside liveBad 2047 (src_string_init 156 1795 2160) := by decide +kernel

/-- mini::selfhost::match_of_postfix -/
theorem lok2066 : LiveOk prims outside liveBad 2066 (src_match_of_postfix 153 156 1798 1835) := by decide +kernel

/-- mini::selfhost::assign_target -/
theorem lok2077 : LiveOk prims outside liveBad 2077 (src_assign_target 153 156 627 628 1350 1798 1801 1820 1893 2201 2202 2203 2204 2205) := by decide +kernel

/-- mini::selfhost::call_stmt -/
theorem lok2079 : LiveOk prims outside liveBad 2079 (src_call_stmt 155 156 429 647 1833 1889 1891 2005 2007 2207 2208 2209 2210 2211 2212 2213 2214) := by decide +kernel

/-- mini::selfhost::fl_decimal_at -/
theorem lok2111 : LiveOk prims outside liveBad 2111 (src_fl_decimal_at 56 75 105 2236 2237 2238 2239) := by decide +kernel

/-- mini::selfhost::stride_of_postfix -/
theorem lok2116 : LiveOk prims outside liveBad 2116 (src_stride_of_postfix 153 156 1798 1820 2240) := by decide +kernel

/-- mini::selfhost::len_of_postfix -/
theorem lok2117 : LiveOk prims outside liveBad 2117 (src_len_of_postfix 153 156 1798 1820 2241) := by decide +kernel

/-- mini::selfhost::eff_fn_path -/
theorem lok2122 : LiveOk prims outside liveBad 2122 (src_eff_fn_path 56 161 680 1471 1683 1752 2018 2123 2243 2245 2246 2247) := by decide +kernel

/-- mini::selfhost::eff_bound -/
theorem lok2124 : LiveOk prims outside liveBad 2124 (src_eff_bound 56 2248) := by decide +kernel

/-- mini::selfhost::eff_place -/
theorem lok2130 : LiveOk prims outside liveBad 2130 (src_eff_place) := by decide +kernel

/-- mini::selfhost::x_at_of -/
theorem lok2131 : LiveOk prims outside liveBad 2131 (src_x_at_of 1888) := by decide +kernel

/-- mini::selfhost::eff_arms_ordered -/
theorem lok2153 : LiveOk prims outside liveBad 2153 (src_eff_arms_ordered 56 2273 2274) := by decide +kernel

/-- mini::selfhost::lit_result -/
theorem lok2156 : LiveOk prims outside liveBad 2156 (src_lit_result 2034) := by decide +kernel

/-- mini::selfhost::string_primary -/
theorem lok2160 : LiveOk prims outside liveBad 2160 (src_string_primary 153 627 628 1798 2279 2280) := by decide +kernel

/-- mini::selfhost::return_eff -/
theorem lok2187 : LiveOk prims outside liveBad 2187 (src_return_eff 1887) := by decide +kernel

/-- mini::selfhost::for_range -/
theorem lok2195 : LiveOk prims outside liveBad 2195 (src_for_range 1241 1428 1479 2322) := by decide +kernel

/-- mini::selfhost::array_local -/
theorem lok2197 : LiveOk prims outside liveBad 2197 (src_array_local 2040 2323) := by decide +kernel

/-- mini::selfhost::for_array -/
theorem lok2198 : LiveOk prims outside liveBad 2198 (src_for_array 1241 1428) := by decide +kernel

/-- mini::selfhost::for_slice -/
theorem lok2199 : LiveOk prims outside liveBad 2199 (src_for_slice 1241 1428 1479 2322) := by decide +kernel

/-- mini::selfhost::set_place_of -/
theorem lok2202 : LiveOk prims outside liveBad 2202 (src_set_place_of 161 998 1698 1706 2034 2130 2326 2327) := by decide +kernel

/-- mini::selfhost::free_of -/
theorem lok2207 : LiveOk prims outside liveBad 2207 (src_free_of 321 2336 2337) := by decide +kernel

/-- mini::selfhost::assert_arg -/
theorem lok2210 : LiveOk prims outside liveBad 2210 (src_assert_arg 103 1706 2339) := by decide +kernel

/-- mini::selfhost::discard_of -/
theorem lok2211 : LiveOk prims outside liveBad 2211 (src_discard_of) := by decide +kernel

/-- mini::selfhost::fl_round -/
theorem lok2237 : LiveOk prims outside liveBad 2237 (src_fl_round 56 75 105 2236 2365 2373 2374 2375 2376 2377 2378 2379 2380 2381 2382) := by decide +kernel

/-- mini::selfhost::stride_of_local -/
theorem lok2240 : LiveOk prims outside liveBad 2240 (src_stride_of_local 2083) := by decide +kernel

/-- mini::selfhost::len_of_local -/
theorem lok2241 : LiveOk prims outside liveBad 2241 (src_len_of_local 2083) := by decide +kernel

/-- mini::selfhost::eff_found -/
theorem lok2246 : LiveOk prims outside liveBad 2246 (src_eff_found 56 161 680 2248) := by decide +kernel

/-- mini::selfhost::eff_free -/
theorem lok2247 : LiveOk prims outside liveBad 2247 (src_eff_free 56 1242 1471 1910 1955 2022 2123 2248 2390 2391 2392 2393) := by decide +kernel

/-- mini::selfhost::eff_infer -/
theorem lok2248 : LiveOk prims outside liveBad 2248 (src_eff_infer 56 446 448 941 1897 2022 2392 2393 2394 2395 2396 2397 2398 2399 2400) := by decide +kernel

/-- mini::selfhost::referent_or -/
theorem lok2253 : LiveOk prims outside liveBad 2253 (src_referent_or 1699) := by decide +kernel

/-- core::mem::typed_slice_from_storage<mini::selfhost::List<mini::selfhost::VariantAt>> -/
theorem lok2261 : LiveOk prims outside liveBad 2261 (src_core_mem_typed_slice_from_storage_of_mini_selfhost_List_mini_selfhost_VariantAt) := by decide +kernel

/-- mini::selfhost::eff_arms -/
theorem lok2274 : LiveOk prims outside liveBad 2274 (src_eff_arms 56 103 2169 2274 2412 2413 2414) := by decide +kernel

/-- mini::selfhost::lit_chain -/
theorem lok2277 : LiveOk prims outside liveBad 2277 (src_lit_chain 103 1228 2277 2320 2321 2416) := by decide +kernel

/-- mini::selfhost::string_literal -/
theorem lok2280 : LiveOk prims outside liveBad 2280 (src_string_literal 76 2417) := by decide +kernel

/-- core::mem::typed_slice_from_storage<mini::selfhost::List<mini::selfhost::VariantTy>> -/
theorem lok2296 : LiveOk prims outside liveBad 2296 (src_core_mem_typed_slice_from_storage_of_mini_selfhost_List_mini_selfhost_VariantTy) := by decide +kernel

/-- mini::selfhost::array_local_of -/
theorem lok2323 : LiveOk prims outside liveBad 2323 (src_array_local_of) := by decide +kernel

/-- mini::selfhost::set_place_op_of -/
theorem lok2331 : LiveOk prims outside liveBad 2331 (src_set_place_op_of 161 998 1698 1706 2034 2130 2326 2447) := by decide +kernel

/-- mini::selfhost::assign_op_of -/
theorem lok2332 : LiveOk prims outside liveBad 2332 (src_assign_op_of 2448 2449 2450 2451 2452 2453 2454 2455) := by decide +kernel

/-- mini::selfhost::compound_eff -/
theorem lok2334 : LiveOk prims outside liveBad 2334 (src_compound_eff 2001 2003 2457 2458 2459) := by decide +kernel

/-- mini::selfhost::compound_field_eval -/
theorem lok2335 : LiveOk prims outside liveBad 2335 (src_compound_field_eval 1698 1706 2269 2326 2329 2334) := by decide +kernel

/-- mini::selfhost::free_shifted -/
theorem lok2336 : LiveOk prims outside liveBad 2336 (src_free_shifted) := by decide +kernel

/-- mini::selfhost::assert_of -/
theorem lok2339 : LiveOk prims outside liveBad 2339 (src_assert_of) := by decide +kernel

/-- core::mem::typed_slice_from_storage<mini::selfhost::List<bool>> -/
theorem lok2372 : LiveOk prims outside liveBad 2372 (src_core_mem_typed_slice_from_storage_of_mini_selfhost_List_bool) := by decide +kernel

/-- mini::selfhost::fl_ratio_ok -/
theorem lok2376 : LiveOk prims outside liveBad 2376 (src_fl_ratio_ok 2374 2377 2379) := by decide +kernel

/-- mini::selfhost::fl_round_up -/
theorem lok2381 : LiveOk prims outside liveBad 2381 (src_fl_round_up 1883 2229) := by decide +kernel

/-- mini::selfhost::arg_list -/
theorem lok2396 : LiveOk prims outside liveBad 2396 (src_arg_list 56 103 1471 2043 2044 2045 2396 2486) := by decide +kernel

/-- mini::selfhost::eff_args_bound -/
theorem lok2399 : LiveOk prims outside liveBad 2399 (src_eff_args_bound 56 103 1228 1471 1698 1706 2022 2085 2399 2489 2490 2491 2492 2493 2494) := by decide +kernel

/-- mini::selfhost::projection -/
theorem lok2405 : LiveOk prims outside liveBad 2405 (src_projection 75 975 998) := by decide +kernel

/-- core::mem::size_of<mini::selfhost::List<mini::selfhost::VariantAt>> -/
theorem lok2408 : LiveOk prims outside liveBad 2408 (src_core_mem_size_of_of_mini_selfhost_List_mini_selfhost_VariantAt) := by decide +kernel

/-- mini::selfhost::eff_arm -/
theorem lok2414 : LiveOk prims outside liveBad 2414 (src_eff_arm 56 139 153 155 156 429 2425 2426 2427 2428 2499) := by decide +kernel

/-- mini::selfhost::lit_link -/
theorem lok2416 : LiveOk prims outside liveBad 2416 (src_lit_link 156 2315 2501 2502 2503 2504) := by decide +kernel

/-- mini::selfhost::string_open -/
theorem lok2417 : LiveOk prims outside liveBad 2417 (src_string_open 2505) := by decide +kernel

/-- mini::selfhost::has_at -/
theorem lok2442 : LiveOk prims outside liveBad 2442 (src_has_at 1229 2442) := by decide +kernel

/-- mini::selfhost::set_place_op_value -/
theorem lok2447 : LiveOk prims outside liveBad 2447 (src_set_place_op_value 2322 2442 2443) := by decide +kernel

/-- mini::selfhost::compound_op -/
theorem lok2459 : LiveOk prims outside liveBad 2459 (src_compound_op 2448 2449 2450 2451 2452 2453 2454 2455) := by decide +kernel

/-- core::mem::typed_slice_from_storage<mini::selfhost::List<mini::selfhost::Bind>> -/
theorem lok2469 : LiveOk prims outside liveBad 2469 (src_core_mem_typed_slice_from_storage_of_mini_selfhost_List_mini_selfhost_Bind) := by decide +kernel

/-- core::mem::size_of<mini::selfhost::List<bool>> -/
theorem lok2480 : LiveOk prims outside liveBad 2480 (src_core_mem_size_of_of_mini_selfhost_List_bool) := by decide +kernel

/-- mini::selfhost::arg_eff -/
theorem lok2486 : LiveOk prims outside liveBad 2486 (src_arg_eff 56 1706 2047) := by decide +kernel

/-- mini::selfhost::eff_arg_next -/
theorem lok2491 : LiveOk prims outside liveBad 2491 (src_eff_arg_next 56 1471 2399 2493 2494) := by decide +kernel

/-- core::mem::typed_slice_from_storage<mini::selfhost::List<mini::selfhost::EffArm>> -/
theorem lok2496 : LiveOk prims outside liveBad 2496 (src_core_mem_typed_slice_from_storage_of_mini_selfhost_List_mini_selfhost_EffArm) := by decide +kernel

/-- mini::selfhost::eff_arm_bound -/
theorem lok2499 : LiveOk prims outside liveBad 2499 (src_eff_arm_bound 56 1706 2537 2538) := by decide +kernel

/-- core::mem::size_of<mini::selfhost::List<mini::selfhost::VariantTy>> -/
theorem lok2500 : LiveOk prims outside liveBad 2500 (src_core_mem_size_of_of_mini_selfhost_List_mini_selfhost_VariantTy) := by decide +kernel

/-- mini::selfhost::lit_wild_value -/
theorem lok2501 : LiveOk prims outside liveBad 2501 (src_lit_wild_value) := by decide +kernel

/-- core::mem::size_of<mini::selfhost::List<mini::selfhost::Bind>> -/
theorem lok2567 : LiveOk prims outside liveBad 2567 (src_core_mem_size_of_of_mini_selfhost_List_mini_selfhost_Bind) := by decide +kernel

/-- core::mem::size_of<mini::selfhost::List<mini::selfhost::EffArm>> -/
theorem lok2578 : LiveOk prims outside liveBad 2578 (src_core_mem_size_of_of_mini_selfhost_List_mini_selfhost_EffArm) := by decide +kernel

end Lanius.Faithful.SelfPure
