module

public import Lanius.Faithful.Gen.SelfPureTab
public import Lanius.Faithful.Gen.SelfLiveTab
public import Lanius.Faithful.Gen.SelfSrcC_SrcExpr_guard
public import Lanius.Faithful.Gen.SelfSrcC_wordWidth
public import Lanius.Faithful.Gen.SelfSrcF_Inline_pStructFieldsAfterCommaMore
public import Lanius.Faithful.Gen.SelfSrcF_consTys
public import Lanius.Faithful.Gen.SelfSrcF_hasConst
public import Lanius.Faithful.Gen.SelfSrcF_isFnPath
public import Lanius.Faithful.Gen.SelfSrcF_limExprs
public import Lanius.Faithful.Gen.SelfSrcF_limNumsEff
public import Lanius.Faithful.Gen.SelfSrcF_lxSymbolStart
public import Lanius.Faithful.Gen.SelfSrcF_noTrees
public import Lanius.Faithful.Gen.SelfSrcF_setIndexOrEval
public import Lanius.Faithful.Gen.SelfSrcF_typedLiteral
import all Lanius.Faithful.Gen.SelfLiveTab
import all Lanius.Faithful.Gen.SelfPureTab
import all Lanius.Faithful.Gen.SelfSrcC_SrcExpr_guard
import all Lanius.Faithful.Gen.SelfSrcC_wordWidth
import all Lanius.Faithful.Gen.SelfSrcF_Inline_pStructFieldsAfterCommaMore
import all Lanius.Faithful.Gen.SelfSrcF_consTys
import all Lanius.Faithful.Gen.SelfSrcF_hasConst
import all Lanius.Faithful.Gen.SelfSrcF_isFnPath
import all Lanius.Faithful.Gen.SelfSrcF_limExprs
import all Lanius.Faithful.Gen.SelfSrcF_limNumsEff
import all Lanius.Faithful.Gen.SelfSrcF_lxSymbolStart
import all Lanius.Faithful.Gen.SelfSrcF_noTrees
import all Lanius.Faithful.Gen.SelfSrcF_setIndexOrEval
import all Lanius.Faithful.Gen.SelfSrcF_typedLiteral
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

/-- mini::selfhost::guarded -/
theorem lok190 : LiveOk prims outside liveBad 190 (src_guarded 312) := by decide +kernel

/-- mini::selfhost::guard -/
theorem lok191 : LiveOk prims outside liveBad 191 (src_SrcExpr_guard 191 313 314 315) := by decide +kernel

/-- mini::selfhost::guard_all -/
theorem lok195 : LiveOk prims outside liveBad 195 (src_guard_all 191 195 211 321) := by decide +kernel

/-- mini::selfhost::lower_as -/
theorem lok207 : LiveOk prims outside liveBad 207 (src_lower_as 315 333) := by decide +kernel

/-- mini::selfhost::check_then -/
theorem lok312 : LiveOk prims outside liveBad 312 (src_check_then 188 336 496) := by decide +kernel

/-- mini::selfhost::expect_type -/
theorem lok333 : LiveOk prims outside liveBad 333 (src_expect_type 235) := by decide +kernel

/-- mini::selfhost::slot_vars -/
theorem lok353 : LiveOk prims outside liveBad 353 (src_slot_vars 56 75 353 541 542) := by decide +kernel

/-- mini::selfhost::path_spellings -/
theorem lok429 : LiveOk prims outside liveBad 429 (src_path_spellings 56 153 156 429 627 628 645 646 647 648 649) := by decide +kernel

/-- mini::selfhost::trap -/
theorem lok496 : LiveOk prims outside liveBad 496 (src_trap) := by decide +kernel

/-- mini::selfhost::word_type -/
theorem lok525 : LiveOk prims outside liveBad 525 (src_word_type 180 181 183 385 407 410 774 775 776 777) := by decide +kernel

/-- mini::selfhost::bounds_guard -/
theorem lok533 : LiveOk prims outside liveBad 533 (src_bounds_guard 75 337) := by decide +kernel

/-- mini::selfhost::lx_drop -/
theorem lok593 : LiveOk prims outside liveBad 593 (src_lx_drop 56 76 139 593) := by decide +kernel

/-- mini::selfhost::lower_append -/
theorem lok768 : LiveOk prims outside liveBad 768 (src_lower_append 1065) := by decide +kernel

/-- mini::selfhost::declared_same -/
theorem lok774 : LiveOk prims outside liveBad 774 (src_declared_same 388) := by decide +kernel

/-- mini::selfhost::word_types -/
theorem lok775 : LiveOk prims outside liveBad 775 (src_word_types 181 525 775) := by decide +kernel

/-- mini::selfhost::declared_variants -/
theorem lok776 : LiveOk prims outside liveBad 776 (src_declared_variants 389) := by decide +kernel

/-- mini::selfhost::word_variants -/
theorem lok777 : LiveOk prims outside liveBad 777 (src_word_variants 183 775 777) := by decide +kernel

/-- mini::selfhost::then_check -/
theorem lok797 : LiveOk prims outside liveBad 797 (src_then_check 188 336 496) := by decide +kernel

/-- mini::selfhost::p_struct_fields_end -/
theorem lok866 : LiveOk prims outside liveBad 866 (src_p_struct_fields_end) := by decide +kernel

/-- mini::selfhost::p_struct_fields_after_comma_more -/
theorem lok867 : LiveOk prims outside liveBad 867 (src_p_struct_fields_after_comma_more) := by decide +kernel

/-- mini::selfhost::p_struct_fields_after_comma_trailing -/
theorem lok868 : LiveOk prims outside liveBad 868 (src_p_struct_fields_after_comma_trailing) := by decide +kernel

/-- mini::selfhost::lim_funcs -/
theorem lok962 : LiveOk prims outside liveBad 962 (src_lim_funcs 59 962 968 1188 1189 1190 1191 1192 1193 1194 1195 1196) := by decide +kernel

/-- mini::selfhost::lx_ident_end -/
theorem lok1100 : LiveOk prims outside liveBad 1100 (src_lx_ident_end 75 593 1336) := by decide +kernel

/-- mini::selfhost::lx_symbol_start -/
theorem lok1108 : LiveOk prims outside liveBad 1108 (src_lx_symbol_start) := by decide +kernel

/-- mini::selfhost::lx_take -/
theorem lok1115 : LiveOk prims outside liveBad 1115 (src_lx_take 56 76 139 418 1115) := by decide +kernel

/-- mini::selfhost::lim_nums_params -/
theorem lok1194 : LiveOk prims outside liveBad 1194 (src_lim_nums_params 174 1194 1195 1413) := by decide +kernel

/-- mini::selfhost::lim_nums_stmt -/
theorem lok1196 : LiveOk prims outside liveBad 1196 (src_lim_nums_stmt 81 1195 1196 1413 1416 1417 1418 1419 1420) := by decide +kernel

/-- mini::selfhost::field_tys -/
theorem lok1251 : LiveOk prims outside liveBad 1251 (src_field_tys 1185 1483 1484) := by decide +kernel

/-- mini::selfhost::word_width -/
theorem lok1334 : LiveOk prims outside liveBad 1334 (src_word_width 1521) := by decide +kernel

/-- mini::selfhost::lx_ident_run -/
theorem lok1336 : LiveOk prims outside liveBad 1336 (src_lx_ident_run 76 1522) := by decide +kernel

/-- mini::selfhost::lx_space_run -/
theorem lok1340 : LiveOk prims outside liveBad 1340 (src_lx_space_run 76 1527) := by decide +kernel

/-- mini::selfhost::payload_tys -/
theorem lok1393 : LiveOk prims outside liveBad 1393 (src_payload_tys 1185 1484 1542) := by decide +kernel

/-- mini::selfhost::lim_bind -/
theorem lok1400 : LiveOk prims outside liveBad 1400 (src_lim_bind 1411) := by decide +kernel

/-- mini::selfhost::lim_exprs -/
theorem lok1403 : LiveOk prims outside liveBad 1403 (src_lim_exprs 321 1402 1403) := by decide +kernel

/-- mini::selfhost::lim_arms -/
theorem lok1404 : LiveOk prims outside liveBad 1404 (src_lim_arms 1066 1402 1404) := by decide +kernel

/-- mini::selfhost::lim_eff -/
theorem lok1410 : LiveOk prims outside liveBad 1410 (src_lim_eff 356 358 1190 1402 1410 1552) := by decide +kernel

/-- mini::selfhost::lim_nums_eff -/
theorem lok1419 : LiveOk prims outside liveBad 1419 (src_lim_nums_eff 356 358 1195 1413 1416 1419 1420 1555 1556) := by decide +kernel

/-- mini::selfhost::lx_is_byte -/
theorem lok1523 : LiveOk prims outside liveBad 1523 (src_lx_is_byte) := by decide +kernel

/-- mini::selfhost::payload_list -/
theorem lok1542 : LiveOk prims outside liveBad 1542 (src_payload_list 1483 1542 1655 1656 1657) := by decide +kernel

/-- mini::selfhost::lim_effs -/
theorem lok1552 : LiveOk prims outside liveBad 1552 (src_lim_effs 356 1410 1552) := by decide +kernel

/-- mini::selfhost::lim_nums_effs -/
theorem lok1555 : LiveOk prims outside liveBad 1555 (src_lim_nums_effs 356 1419 1555) := by decide +kernel

/-- mini::selfhost::cons_tys -/
theorem lok1656 : LiveOk prims outside liveBad 1656 (src_cons_tys 1737) := by decide +kernel

/-- mini::selfhost::lx_line_run -/
theorem lok1778 : LiveOk prims outside liveBad 1778 (src_lx_line_run 76 1846) := by decide +kernel

/-- mini::selfhost::path_name -/
theorem lok1800 : LiveOk prims outside liveBad 1800 (src_path_name 153 156 627 628 645 646 1859) := by decide +kernel

/-- mini::selfhost::eff_casts -/
theorem lok1830 : LiveOk prims outside liveBad 1830 (src_eff_casts 56 156 606 1830 1874 1886) := by decide +kernel

/-- mini::selfhost::eff_binary -/
theorem lok1885 : LiveOk prims outside liveBad 1885 (src_eff_binary 1872 2000 2001 2002 2003) := by decide +kernel

/-- mini::selfhost::is_method_form -/
theorem lok1891 : LiveOk prims outside liveBad 1891 (src_is_method_form 153 156 1796 1797 1798 1801 1802 1818 2016) := by decide +kernel

/-- mini::selfhost::has_const -/
theorem lok1899 : LiveOk prims outside liveBad 1899 (src_has_const) := by decide +kernel

/-- mini::selfhost::member_args -/
theorem lok2016 : LiveOk prims outside liveBad 2016 (src_member_args 1348 1350) := by decide +kernel

/-- mini::selfhost::known_args -/
theorem lok2023 : LiveOk prims outside liveBad 2023 (src_known_args 446 448 2035 2133) := by decide +kernel

/-- mini::selfhost::variant_expects -/
theorem lok2024 : LiveOk prims outside liveBad 2024 (src_variant_expects 1393 2134) := by decide +kernel

/-- mini::selfhost::x_variant_of -/
theorem lok2025 : LiveOk prims outside liveBad 2025 (src_x_variant_of 1242 2135 2136) := by decide +kernel

/-- mini::selfhost::field_expects -/
theorem lok2031 : LiveOk prims outside liveBad 2031 (src_field_expects 1251) := by decide +kernel

/-- mini::selfhost::x_struct_of -/
theorem lok2032 : LiveOk prims outside liveBad 2032 (src_x_struct_of 1242 2135) := by decide +kernel

/-- mini::selfhost::literal_as -/
theorem lok2101 : LiveOk prims outside liveBad 2101 (src_literal_as 2223) := by decide +kernel

/-- mini::selfhost::args_segment -/
theorem lok2118 : LiveOk prims outside liveBad 2118 (src_args_segment 647) := by decide +kernel

/-- mini::selfhost::cons_segment -/
theorem lok2119 : LiveOk prims outside liveBad 2119 (src_cons_segment 1141) := by decide +kernel

/-- mini::selfhost::is_fn_path -/
theorem lok2121 : LiveOk prims outside liveBad 2121 (src_is_fn_path 161 1752 2243 2244 2245) := by decide +kernel

/-- mini::selfhost::no_trees -/
theorem lok2123 : LiveOk prims outside liveBad 2123 (src_no_trees) := by decide +kernel

/-- mini::selfhost::decl_inst -/
theorem lok2135 : LiveOk prims outside liveBad 2135 (src_decl_inst 265 448 670 1484 1955 1956 2256 2257 2258) := by decide +kernel

/-- mini::selfhost::set_index_or_eval -/
theorem lok2205 : LiveOk prims outside liveBad 2205 (src_set_index_or_eval 161 998 1706 2267 2330) := by decide +kernel

/-- mini::selfhost::typed_literal -/
theorem lok2223 : LiveOk prims outside liveBad 2223 (src_typed_literal 313 1428 2352 2353 2354 2355 2356 2357 2358) := by decide +kernel

/-- mini::selfhost::named_inferred -/
theorem lok2257 : LiveOk prims outside liveBad 2257 (src_named_inferred 670) := by decide +kernel

/-- mini::selfhost::pure_list -/
theorem lok2304 : LiveOk prims outside liveBad 2304 (src_pure_list 1228 1435 1436 1887 2304) := by decide +kernel

/-- mini::selfhost::field_eval_stmt -/
theorem lok2329 : LiveOk prims outside liveBad 2329 (src_field_eval_stmt 2445) := by decide +kernel

/-- mini::selfhost::param_expects -/
theorem lok2392 : LiveOk prims outside liveBad 2392 (src_param_expects 941 1483 1484 2397) := by decide +kernel

/-- mini::selfhost::eff_called -/
theorem lok2394 : LiveOk prims outside liveBad 2394 (src_eff_called 2256 2483 2484 2485) := by decide +kernel

/-- mini::selfhost::skip_expects -/
theorem lok2395 : LiveOk prims outside liveBad 2395 (src_skip_expects 2045) := by decide +kernel

/-- mini::selfhost::infer_eff -/
theorem lok2484 : LiveOk prims outside liveBad 2484 (src_infer_eff 2529 2530) := by decide +kernel

/-- mini::selfhost::infer_args -/
theorem lok2530 : LiveOk prims outside liveBad 2530 (src_infer_args 446 448 941 1956 2258 2397 2403 2532) := by decide +kernel

/-- mini::selfhost::arm_eff -/
theorem lok2537 : LiveOk prims outside liveBad 2537 (src_arm_eff 2034) := by decide +kernel

end Lanius.Faithful.SelfPure
