module

public import Lanius.Faithful.Gen.SelfPureTab
public import Lanius.Faithful.Gen.SelfLiveTab
public import Lanius.Faithful.Gen.SelfSrcC_FArith_opcode
public import Lanius.Faithful.Gen.SelfSrcC_callAgrees
public import Lanius.Faithful.Gen.SelfSrcC_lowerLoadType
public import Lanius.Faithful.Gen.SelfSrcF_ifEff
public import Lanius.Faithful.Gen.SelfSrcF_ifSome
public import Lanius.Faithful.Gen.SelfSrcF_isUnderscore
public import Lanius.Faithful.Gen.SelfSrcF_purePart
public import Lanius.Faithful.Gen.SelfSrcF_scalarOf
public import Lanius.Faithful.Gen.SelfSrcF_unitTy
public import Lanius.Faithful.Gen.SelfSrcF_variantArm
public import Lanius.Faithful.Gen.SelfSrcF_variantIn
import all Lanius.Faithful.Gen.SelfLiveTab
import all Lanius.Faithful.Gen.SelfPureTab
import all Lanius.Faithful.Gen.SelfSrcC_FArith_opcode
import all Lanius.Faithful.Gen.SelfSrcC_callAgrees
import all Lanius.Faithful.Gen.SelfSrcC_lowerLoadType
import all Lanius.Faithful.Gen.SelfSrcF_ifEff
import all Lanius.Faithful.Gen.SelfSrcF_ifSome
import all Lanius.Faithful.Gen.SelfSrcF_isUnderscore
import all Lanius.Faithful.Gen.SelfSrcF_purePart
import all Lanius.Faithful.Gen.SelfSrcF_scalarOf
import all Lanius.Faithful.Gen.SelfSrcF_unitTy
import all Lanius.Faithful.Gen.SelfSrcF_variantArm
import all Lanius.Faithful.Gen.SelfSrcF_variantIn
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

/-- mini::selfhost::lower_let_index_any -/
theorem lok218 : LiveOk prims outside liveBad 218 (src_lower_let_index_any 190 191 202 211 220 343 344 345 346 347 348) := by decide +kernel

/-- mini::selfhost::is_array_local -/
theorem lok343 : LiveOk prims outside liveBad 343 (src_is_array_local) := by decide +kernel

/-- mini::selfhost::eval_index -/
theorem lok344 : LiveOk prims outside liveBad 344 (src_eval_index 202 380 528 529) := by decide +kernel

/-- mini::selfhost::lower_let_index -/
theorem lok347 : LiveOk prims outside liveBad 347 (src_lower_let_index 212 338 339 534 535 536) := by decide +kernel

/-- mini::selfhost::lower_set_index -/
theorem lok349 : LiveOk prims outside liveBad 349 (src_lower_set_index 538) := by decide +kernel

/-- mini::selfhost::subst -/
theorem lok464 : LiveOk prims outside liveBad 464 (src_Expr_subst 337 464 492 698) := by decide +kernel

/-- mini::selfhost::eval_element -/
theorem lok528 : LiveOk prims outside liveBad 528 (src_eval_element 338 339 778 779 780) := by decide +kernel

/-- mini::selfhost::eval_array_index -/
theorem lok529 : LiveOk prims outside liveBad 529 (src_eval_array_index 184 781) := by decide +kernel

/-- mini::selfhost::lower_load_type -/
theorem lok536 : LiveOk prims outside liveBad 536 (src_lower_load_type 785) := by decide +kernel

/-- mini::selfhost::fact_value -/
theorem lok698 : LiveOk prims outside liveBad 698 (src_fact_value 1016 1017) := by decide +kernel

/-- mini::selfhost::call_agrees -/
theorem lok716 : LiveOk prims outside liveBad 716 (src_call_agrees 1026) := by decide +kernel

/-- mini::selfhost::ret_agrees -/
theorem lok717 : LiveOk prims outside liveBad 717 (src_ret_agrees 1026) := by decide +kernel

/-- mini::selfhost::alloc_agrees -/
theorem lok720 : LiveOk prims outside liveBad 720 (src_alloc_agrees 1021) := by decide +kernel

/-- mini::selfhost::load_byte_agrees -/
theorem lok721 : LiveOk prims outside liveBad 721 (src_load_byte_agrees 1021) := by decide +kernel

/-- mini::selfhost::store_byte_agrees -/
theorem lok722 : LiveOk prims outside liveBad 722 (src_store_byte_agrees 1021) := by decide +kernel

/-- mini::selfhost::load_word_agrees -/
theorem lok723 : LiveOk prims outside liveBad 723 (src_load_word_agrees 1021 1027) := by decide +kernel

/-- mini::selfhost::store_word_agrees -/
theorem lok724 : LiveOk prims outside liveBad 724 (src_store_word_agrees 1021 1027) := by decide +kernel

/-- mini::selfhost::divide_agrees -/
theorem lok725 : LiveOk prims outside liveBad 725 (src_divide_agrees 1021 1028 1029) := by decide +kernel

/-- mini::selfhost::sys_agrees -/
theorem lok726 : LiveOk prims outside liveBad 726 (src_sys_agrees 1026 1030) := by decide +kernel

/-- mini::selfhost::frame_agrees -/
theorem lok727 : LiveOk prims outside liveBad 727 (src_frame_agrees) := by decide +kernel

/-- mini::selfhost::static_agrees -/
theorem lok728 : LiveOk prims outside liveBad 728 (src_static_agrees) := by decide +kernel

/-- mini::selfhost::eval_load_byte -/
theorem lok779 : LiveOk prims outside liveBad 779 (src_eval_load_byte 188 312 337 338 339 533) := by decide +kernel

/-- mini::selfhost::eval_word_element -/
theorem lok780 : LiveOk prims outside liveBad 780 (src_eval_word_element 75 120 188 312 316 338 339 340 353 533 817 1070) := by decide +kernel

/-- mini::selfhost::eval_array_element -/
theorem lok781 : LiveOk prims outside liveBad 781 (src_eval_array_element 1071) := by decide +kernel

/-- mini::selfhost::eval_pick -/
theorem lok1071 : LiveOk prims outside liveBad 1071 (src_eval_pick 120 188 312 337 338 339 1327) := by decide +kernel

/-- mini::selfhost::is_atom -/
theorem lok1262 : LiveOk prims outside liveBad 1262 (src_Expr_is_atom) := by decide +kernel

/-- mini::selfhost::mentions -/
theorem lok1263 : LiveOk prims outside liveBad 1263 (src_Expr_mentions 492 1263) := by decide +kernel

/-- mini::selfhost::bump_bytes -/
theorem lok1294 : LiveOk prims outside liveBad 1294 (src_bump_bytes 754 1042 1043 1282 1503) := by decide +kernel

/-- mini::selfhost::bytes -/
theorem lok1300 : LiveOk prims outside liveBad 1300 (src_FOp_bytes 754 1499 1508) := by decide +kernel

/-- mini::selfhost::frame_memory_bytes -/
theorem lok1302 : LiveOk prims outside liveBad 1302 (src_frame_memory_bytes 754 1042 1043 1282) := by decide +kernel

/-- mini::selfhost::pick_element -/
theorem lok1327 : LiveOk prims outside liveBad 1327 (src_pick_element 56 75 105 188 316 337 353 1327) := by decide +kernel

/-- mini::selfhost::pow2 -/
theorem lok1503 : LiveOk prims outside liveBad 1503 (src_pow2 56 1503) := by decide +kernel

/-- mini::selfhost::opcode_bytes -/
theorem lok1508 : LiveOk prims outside liveBad 1508 (src_FOp_opcode_bytes 754 1042 1043 1500 1630 1631 1632 1633 1634) := by decide +kernel

/-- mini::selfhost::unit_ty -/
theorem lok1545 : LiveOk prims outside liveBad 1545 (src_unit_ty) := by decide +kernel

/-- mini::selfhost::float_operands -/
theorem lok1630 : LiveOk prims outside liveBad 1630 (src_float_operands 754 1042 1043 1710) := by decide +kernel

/-- mini::selfhost::opcode -/
theorem lok1632 : LiveOk prims outside liveBad 1632 (src_FArith_opcode) := by decide +kernel

/-- mini::selfhost::float_result -/
theorem lok1633 : LiveOk prims outside liveBad 1633 (src_float_result 754 1042 1043 1710) := by decide +kernel

/-- mini::selfhost::predicate -/
theorem lok1634 : LiveOk prims outside liveBad 1634 (src_FCmp_predicate) := by decide +kernel

/-- mini::selfhost::uint_mask -/
theorem lok1666 : LiveOk prims outside liveBad 1666 (src_uint_mask) := by decide +kernel

/-- mini::selfhost::param_ty -/
theorem lok1747 : LiveOk prims outside liveBad 1747 (src_param_ty 1000 1785) := by decide +kernel

/-- mini::selfhost::prim_ty -/
theorem lok1786 : LiveOk prims outside liveBad 1786 (src_prim_ty 654 1851) := by decide +kernel

/-- mini::selfhost::casts -/
theorem lok1810 : LiveOk prims outside liveBad 1810 (src_casts 56 156 606 1810 1873 1874) := by decide +kernel

/-- mini::selfhost::x_neg_of -/
theorem lok1831 : LiveOk prims outside liveBad 1831 (src_x_neg_of 1428 1887 1888) := by decide +kernel

/-- mini::selfhost::x_not_of -/
theorem lok1832 : LiveOk prims outside liveBad 1832 (src_x_not_of 1428 1887 1888) := by decide +kernel

/-- mini::selfhost::src_ty -/
theorem lok1851 : LiveOk prims outside liveBad 1851 (src_src_ty) := by decide +kernel

/-- mini::selfhost::cast_into -/
theorem lok1873 : LiveOk prims outside liveBad 1873 (src_cast_into 1984) := by decide +kernel

/-- mini::selfhost::cast_type_of -/
theorem lok1874 : LiveOk prims outside liveBad 1874 (src_cast_type_of 153 156 627 628 1985 1986 1987 1988 1989) := by decide +kernel

/-- mini::selfhost::x_cast_into -/
theorem lok1886 : LiveOk prims outside liveBad 1886 (src_x_cast_into 1428 1887 1888) := by decide +kernel

/-- mini::selfhost::pure_part -/
theorem lok1887 : LiveOk prims outside liveBad 1887 (src_pure_part) := by decide +kernel

/-- mini::selfhost::x_index_of -/
theorem lok1894 : LiveOk prims outside liveBad 1894 (src_x_index_of 1888) := by decide +kernel

/-- mini::selfhost::variant_by_path -/
theorem lok1902 : LiveOk prims outside liveBad 1902 (src_variant_by_path 163 446 2026 2027 2028 2029) := by decide +kernel

/-- mini::selfhost::cast_value -/
theorem lok1984 : LiveOk prims outside liveBad 1984 (src_cast_value 1428) := by decide +kernel

/-- mini::selfhost::named_scalar -/
theorem lok1989 : LiveOk prims outside liveBad 1989 (src_named_scalar 448 647 1684 1747 1786 2095 2096) := by decide +kernel

/-- mini::selfhost::x_divide_of -/
theorem lok2001 : LiveOk prims outside liveBad 2001 (src_x_divide_of 1888) := by decide +kernel

/-- mini::selfhost::x_apply_of -/
theorem lok2003 : LiveOk prims outside liveBad 2003 (src_x_apply_of 2112) := by decide +kernel

/-- mini::selfhost::enum_variant -/
theorem lok2027 : LiveOk prims outside liveBad 2027 (src_enum_variant 163 1750 1752 1754 2140) := by decide +kernel

/-- mini::selfhost::cons_eff -/
theorem lok2043 : LiveOk prims outside liveBad 2043 (src_cons_eff 1472) := by decide +kernel

/-- mini::selfhost::apply_of -/
theorem lok2094 : LiveOk prims outside liveBad 2094 (src_apply_of 1428) := by decide +kernel

/-- mini::selfhost::scalar_src -/
theorem lok2095 : LiveOk prims outside liveBad 2095 (src_scalar_src) := by decide +kernel

/-- mini::selfhost::scalar_of -/
theorem lok2096 : LiveOk prims outside liveBad 2096 (src_scalar_of 2095) := by decide +kernel

/-- mini::selfhost::apply_eff -/
theorem lok2112 : LiveOk prims outside liveBad 2112 (src_apply_eff 1428 1887 1888) := by decide +kernel

/-- mini::selfhost::variant_in -/
theorem lok2140 : LiveOk prims outside liveBad 2140 (src_variant_in 1185 2262) := by decide +kernel

/-- mini::selfhost::if_some -/
theorem lok2170 : LiveOk prims outside liveBad 2170 (src_if_some) := by decide +kernel

/-- mini::selfhost::if_eff -/
theorem lok2188 : LiveOk prims outside liveBad 2188 (src_if_eff 1241 1887) := by decide +kernel

/-- mini::selfhost::while_eff -/
theorem lok2189 : LiveOk prims outside liveBad 2189 (src_while_eff 1241 1887) := by decide +kernel

/-- mini::selfhost::is_wild_arm -/
theorem lok2315 : LiveOk prims outside liveBad 2315 (src_is_wild_arm 153 156 1800 2425 2427 2439) := by decide +kernel

/-- mini::selfhost::uint_in_range -/
theorem lok2352 : LiveOk prims outside liveBad 2352 (src_uint_in_range 1666) := by decide +kernel

/-- mini::selfhost::negated_int -/
theorem lok2355 : LiveOk prims outside liveBad 2355 (src_negated_int) := by decide +kernel

/-- mini::selfhost::is_underscore -/
theorem lok2439 : LiveOk prims outside liveBad 2439 (src_is_underscore 934 2517) := by decide +kernel

/-- mini::selfhost::set_field_eff -/
theorem lok2445 : LiveOk prims outside liveBad 2445 (src_set_field_eff 1887) := by decide +kernel

/-- mini::selfhost::set_index_eff -/
theorem lok2446 : LiveOk prims outside liveBad 2446 (src_set_index_eff 1887 2519) := by decide +kernel

/-- mini::selfhost::set_eff -/
theorem lok2456 : LiveOk prims outside liveBad 2456 (src_set_eff 1887) := by decide +kernel

/-- mini::selfhost::x_call_of -/
theorem lok2483 : LiveOk prims outside liveBad 2483 (src_x_call_of 1242) := by decide +kernel

/-- mini::selfhost::wild_split -/
theorem lok2510 : LiveOk prims outside liveBad 2510 (src_wild_split 103 2510 2545 2546) := by decide +kernel

/-- mini::selfhost::set_index_pure -/
theorem lok2519 : LiveOk prims outside liveBad 2519 (src_set_index_pure 1887) := by decide +kernel

/-- mini::selfhost::wild_alone -/
theorem lok2545 : LiveOk prims outside liveBad 2545 (src_wild_alone 96 2315) := by decide +kernel

/-- mini::selfhost::cons_wild -/
theorem lok2546 : LiveOk prims outside liveBad 2546 (src_cons_wild 148) := by decide +kernel

/-- mini::selfhost::variant_arms -/
theorem lok2549 : LiveOk prims outside liveBad 2549 (src_variant_arms 96 2169 2549 2592 2593 2594) := by decide +kernel

/-- mini::selfhost::wild_used -/
theorem lok2591 : LiveOk prims outside liveBad 2591 (src_wild_used 2611) := by decide +kernel

/-- mini::selfhost::cons_use -/
theorem lok2592 : LiveOk prims outside liveBad 2592 (src_cons_use 2612) := by decide +kernel

/-- mini::selfhost::variant_arm -/
theorem lok2593 : LiveOk prims outside liveBad 2593 (src_variant_arm 103 2422 2613 2614) := by decide +kernel

/-- mini::selfhost::wild_arm_for -/
theorem lok2596 : LiveOk prims outside liveBad 2596 (src_wild_arm_for 148 153 156 254 607 628 2618) := by decide +kernel

/-- mini::selfhost::used_arms -/
theorem lok2611 : LiveOk prims outside liveBad 2611 (src_used_arms) := by decide +kernel

/-- mini::selfhost::join_use -/
theorem lok2612 : LiveOk prims outside liveBad 2612 (src_join_use 148) := by decide +kernel

/-- mini::selfhost::wild_tail -/
theorem lok2618 : LiveOk prims outside liveBad 2618 (src_wild_tail 148 156 254 607 894 2626 2627) := by decide +kernel

/-- mini::selfhost::wild_binders -/
theorem lok2627 : LiveOk prims outside liveBad 2627 (src_wild_binders 75 96 148 666 2627 2634) := by decide +kernel

/-- mini::selfhost::wild_binder -/
theorem lok2634 : LiveOk prims outside liveBad 2634 (src_wild_binder 75 148 153 156 254 607 628) := by decide +kernel

end Lanius.Faithful.SelfPure
