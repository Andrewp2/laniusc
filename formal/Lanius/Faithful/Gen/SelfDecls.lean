module

public import Lanius.Faithful.Gen.Self
public import Lanius.Faithful.Gen.SelfDecl0
public import Lanius.Faithful.Gen.SelfDecl1
public import Lanius.Faithful.Gen.SelfDecl2
public import Lanius.Faithful.Gen.SelfDecl3
public import Lanius.Faithful.Gen.SelfDecl4
public import Lanius.Faithful.Gen.SelfDecl5
public import Lanius.Faithful.Gen.SelfDecl6
public import Lanius.Faithful.Gen.SelfDecl7
public import Lanius.Faithful.Gen.SelfDecl8
public import Lanius.Faithful.Gen.SelfDecl9
public import Lanius.Faithful.Gen.SelfDecl10
public import Lanius.Faithful.Gen.SelfDecl11
public import Lanius.Faithful.Gen.SelfDecl12
public import Lanius.Faithful.Gen.SelfDecl13
public import Lanius.Faithful.Gen.SelfDecl14
public import Lanius.Faithful.Gen.SelfDecl15
public import Lanius.Faithful.Gen.SelfDecl16
public import Lanius.Faithful.Gen.SelfDecl17
public import Lanius.Faithful.Gen.SelfDecl18
public import Lanius.Faithful.Gen.SelfDecl19
public import Lanius.Faithful.Gen.SelfDecl20
public import Lanius.Faithful.Gen.SelfDecl21
public import Lanius.Faithful.Gen.SelfDecl22
public import Lanius.Faithful.Gen.SelfDecl23
public import Lanius.Faithful.Gen.SelfDecl24
public import Lanius.Faithful.Gen.SelfDecl25
public import Lanius.Faithful.Gen.SelfDecl26
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

-- The tails unfold one function at a time.
set_option maxRecDepth 100000

theorem dt27 : declareFuncs tail_end (declAt decls 0 0) = some decls := by
  rw [declAt_zero]; rfl

theorem dt26 : declareFuncs tail_fl_exp_digits (declAt decls 0 0) = some decls := by
  rw [show tail_fl_exp_digits = dpart26 ++ tail_end from rfl]
  exact declareFuncs_append (declsStep_eq dchunk26) dt27

theorem dt25 : declareFuncs tail_core_mem_size_of_of_mini_selfhost_List_mini_selfhost_VariantTy (declAt decls 2 2) = some decls := by
  rw [show tail_core_mem_size_of_of_mini_selfhost_List_mini_selfhost_VariantTy = dpart25 ++ tail_fl_exp_digits from rfl]
  exact declareFuncs_append (declsStep_eq dchunk25) dt26

theorem dt24 : declareFuncs tail_ret_binds (declAt decls 3 4) = some decls := by
  rw [show tail_ret_binds = dpart24 ++ tail_core_mem_size_of_of_mini_selfhost_List_mini_selfhost_VariantTy from rfl]
  exact declareFuncs_append (declsStep_eq dchunk24) dt25

theorem dt23 : declareFuncs tail_call_let_head (declAt decls 4 8) = some decls := by
  rw [show tail_call_let_head = dpart23 ++ tail_ret_binds from rfl]
  exact declareFuncs_append (declsStep_eq dchunk23) dt24

theorem dt22 : declareFuncs tail_match_arm_of (declAt decls 5 8) = some decls := by
  rw [show tail_match_arm_of = dpart22 ++ tail_call_let_head from rfl]
  exact declareFuncs_append (declsStep_eq dchunk22) dt23

theorem dt21 : declareFuncs tail_tree_tokens (declAt decls 8 12) = some decls := by
  rw [show tail_tree_tokens = dpart21 ++ tail_match_arm_of from rfl]
  exact declareFuncs_append (declsStep_eq dchunk21) dt22

theorem dt20 : declareFuncs tail_p_div_tail (declAt decls 11 15) = some decls := by
  rw [show tail_p_div_tail = dpart20 ++ tail_tree_tokens from rfl]
  exact declareFuncs_append (declsStep_eq dchunk20) dt21

theorem dt19 : declareFuncs tail_find_const (declAt decls 16 24) = some decls := by
  rw [show tail_find_const = dpart19 ++ tail_p_div_tail from rfl]
  exact declareFuncs_append (declsStep_eq dchunk19) dt20

theorem dt18 : declareFuncs tail_path_name (declAt decls 26 39) = some decls := by
  rw [show tail_path_name = dpart18 ++ tail_find_const from rfl]
  exact declareFuncs_append (declsStep_eq dchunk18) dt19

theorem dt17 : declareFuncs tail_and_known (declAt decls 26 40) = some decls := by
  rw [show tail_and_known = dpart17 ++ tail_path_name from rfl]
  exact declareFuncs_append (declsStep_eq dchunk17) dt18

theorem dt16 : declareFuncs tail_p_type_array (declAt decls 27 45) = some decls := by
  rw [show tail_p_type_array = dpart16 ++ tail_and_known from rfl]
  exact declareFuncs_append (declsStep_eq dchunk16) dt17

theorem dt15 : declareFuncs tail_Word_rex (declAt decls 27 46) = some decls := by
  rw [show tail_Word_rex = dpart15 ++ tail_p_type_array from rfl]
  exact declareFuncs_append (declsStep_eq dchunk15) dt16

theorem dt14 : declareFuncs tail_lim_bind (declAt decls 30 48) = some decls := by
  rw [show tail_lim_bind = dpart14 ++ tail_Word_rex from rfl]
  exact declareFuncs_append (declsStep_eq dchunk14) dt15

theorem dt13 : declareFuncs tail_FOp_bytes (declAt decls 31 52) = some decls := by
  rw [show tail_FOp_bytes = dpart13 ++ tail_lim_bind from rfl]
  exact declareFuncs_append (declsStep_eq dchunk13) dt14

theorem dt12 : declareFuncs tail_boxed_of_mini_selfhost_List_mini_selfhost_SrcFunc (declAt decls 34 56) = some decls := by
  rw [show tail_boxed_of_mini_selfhost_List_mini_selfhost_SrcFunc = dpart12 ++ tail_FOp_bytes from rfl]
  exact declareFuncs_append (declsStep_eq dchunk12) dt13

theorem dt11 : declareFuncs tail_lx_ident_end (declAt decls 35 59) = some decls := by
  rw [show tail_lx_ident_end = dpart11 ++ tail_boxed_of_mini_selfhost_List_mini_selfhost_SrcFunc from rfl]
  exact declareFuncs_append (declsStep_eq dchunk11) dt12

theorem dt10 : declareFuncs tail_get_of_mini_selfhost_Ty (declAt decls 35 60) = some decls := by
  rw [show tail_get_of_mini_selfhost_Ty = dpart10 ++ tail_lx_ident_end from rfl]
  exact declareFuncs_append (declsStep_eq dchunk10) dt11

theorem dt9 : declareFuncs tail_p_enum_type_params_more (declAt decls 39 66) = some decls := by
  rw [show tail_p_enum_type_params_more = dpart9 ++ tail_get_of_mini_selfhost_Ty from rfl]
  exact declareFuncs_append (declsStep_eq dchunk9) dt10

theorem dt8 : declareFuncs tail_SrcType_is_float_any (declAt decls 39 69) = some decls := by
  rw [show tail_SrcType_is_float_any = dpart8 ++ tail_p_enum_type_params_more from rfl]
  exact declareFuncs_append (declsStep_eq dchunk8) dt9

theorem dt7 : declareFuncs tail_Stmt_dead_before (declAt decls 40 71) = some decls := by
  rw [show tail_Stmt_dead_before = dpart7 ++ tail_SrcType_is_float_any from rfl]
  exact declareFuncs_append (declsStep_eq dchunk7) dt8

theorem dt6 : declareFuncs tail_lx_ranges_at (declAt decls 41 75) = some decls := by
  rw [show tail_lx_ranges_at = dpart6 ++ tail_Stmt_dead_before from rfl]
  exact declareFuncs_append (declsStep_eq dchunk6) dt7

theorem dt5 : declareFuncs tail_left_false (declAt decls 41 76) = some decls := by
  rw [show tail_left_false = dpart5 ++ tail_lx_ranges_at from rfl]
  exact declareFuncs_append (declsStep_eq dchunk5) dt6

theorem dt4 : declareFuncs tail_str_stores (declAt decls 46 87) = some decls := by
  rw [show tail_str_stores = dpart4 ++ tail_left_false from rfl]
  exact declareFuncs_append (declsStep_eq dchunk4) dt5

theorem dt3 : declareFuncs tail_spend (declAt decls 48 92) = some decls := by
  rw [show tail_spend = dpart3 ++ tail_str_stores from rfl]
  exact declareFuncs_append (declsStep_eq dchunk3) dt4

theorem dt2 : declareFuncs tail_lower_then (declAt decls 62 109) = some decls := by
  rw [show tail_lower_then = dpart2 ++ tail_spend from rfl]
  exact declareFuncs_append (declsStep_eq dchunk2) dt3

theorem dt1 : declareFuncs tail_file_decls (declAt decls 70 122) = some decls := by
  rw [show tail_file_decls = dpart1 ++ tail_lower_then from rfl]
  exact declareFuncs_append (declsStep_eq dchunk1) dt2

theorem dt0 : declareFuncs tail_app_main_w (declAt decls 137 188) = some decls := by
  rw [show tail_app_main_w = dpart0 ++ tail_file_decls from rfl]
  exact declareFuncs_append (declsStep_eq dchunk0) dt1

theorem decls_start : declAt decls 137 188 = ⟨[], [], prog.statics⟩ := by
  unfold declAt
  rw [List.drop_eq_nil_of_le (by decide +kernel : decls.structs.length ≤ 137),
    List.drop_eq_nil_of_le (by decide +kernel : decls.enums.length ≤ 188),
    (by rfl : decls.statics = prog.statics)]

theorem prog_decls : prog.decls = decls :=
  decls_of_funcs (by rw [← decls_start]; exact dt0)

-- The signatures fit a run of functions at a time.
theorem funcs_dparts : prog.funcs = dpart0 ++ (dpart1 ++ (dpart2 ++ (dpart3 ++ (dpart4 ++ (dpart5 ++ (dpart6 ++ (dpart7 ++ (dpart8 ++ (dpart9 ++ (dpart10 ++ (dpart11 ++ (dpart12 ++ (dpart13 ++ (dpart14 ++ (dpart15 ++ (dpart16 ++ (dpart17 ++ (dpart18 ++ (dpart19 ++ (dpart20 ++ (dpart21 ++ (dpart22 ++ (dpart23 ++ (dpart24 ++ (dpart25 ++ (dpart26)))))))))))))))))))))))))) := by rfl

theorem entries_dents : (sigBlocks.map Prod.snd).flatten = dents0 ++ (dents1 ++ (dents2 ++ (dents3 ++ (dents4 ++ (dents5 ++ (dents6 ++ (dents7 ++ (dents8 ++ (dents9 ++ (dents10 ++ (dents11 ++ (dents12 ++ (dents13 ++ (dents14 ++ (dents15 ++ (dents16 ++ (dents17 ++ (dents18 ++ (dents19 ++ (dents20 ++ (dents21 ++ (dents22 ++ (dents23 ++ (dents24 ++ (dents25 ++ (dents26)))))))))))))))))))))))))) := by rfl

theorem sigBlocks_fit : entriesFit prog.funcs (sigBlocks.map Prod.snd).flatten = true := by
  rw [funcs_dparts, entries_dents]
  exact entriesFit_append (entriesFit_append (entriesFit_append (entriesFit_append (entriesFit_append (entriesFit_append (entriesFit_append (entriesFit_append (entriesFit_append (entriesFit_append (entriesFit_append (entriesFit_append (entriesFit_append (entriesFit_append (entriesFit_append (entriesFit_append (entriesFit_append (entriesFit_append (entriesFit_append (entriesFit_append (entriesFit_append (entriesFit_append (entriesFit_append (entriesFit_append (entriesFit_append (entriesFit_append (dfit26) dfit25) dfit24) dfit23) dfit22) dfit21) dfit20) dfit19) dfit18) dfit17) dfit16) dfit15) dfit14) dfit13) dfit12) dfit11) dfit10) dfit9) dfit8) dfit7) dfit6) dfit5) dfit4) dfit3) dfit2) dfit1) dfit0

theorem callTy_self : callTy prog outside = sigCall (blockGet sigBlocks) :=
  callTy_eq_blocks sigBlocks_len sigBlocks_fit sigBlocks_outside

end Lanius.Faithful.SelfPure
