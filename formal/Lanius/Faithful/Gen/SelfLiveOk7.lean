module

public import Lanius.Faithful.Gen.SelfPureTab
public import Lanius.Faithful.Gen.SelfLiveTab
public import Lanius.Faithful.Gen.SelfSrcC_arithShiftRight
public import Lanius.Faithful.Gen.SelfSrcC_needCapped
public import Lanius.Faithful.Gen.SelfSrcC_needLimit
public import Lanius.Faithful.Gen.SelfSrcF_Inline_lxFilterAt
public import Lanius.Faithful.Gen.SelfSrcF_joinInsts
public import Lanius.Faithful.Gen.SelfSrcF_litIf
public import Lanius.Faithful.Gen.SelfSrcF_setFieldOrEval
public import Lanius.Faithful.Gen.SelfSrcF_wideLeftStmt
import all Lanius.Faithful.Gen.SelfLiveTab
import all Lanius.Faithful.Gen.SelfPureTab
import all Lanius.Faithful.Gen.SelfSrcC_arithShiftRight
import all Lanius.Faithful.Gen.SelfSrcC_needCapped
import all Lanius.Faithful.Gen.SelfSrcC_needLimit
import all Lanius.Faithful.Gen.SelfSrcF_Inline_lxFilterAt
import all Lanius.Faithful.Gen.SelfSrcF_joinInsts
import all Lanius.Faithful.Gen.SelfSrcF_litIf
import all Lanius.Faithful.Gen.SelfSrcF_setFieldOrEval
import all Lanius.Faithful.Gen.SelfSrcF_wideLeftStmt
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

/-- mini::selfhost::front_end_files -/
theorem lok42 : LiveOk prims outside liveBad 42 (src_front_end_files 69 70 71) := by decide +kernel

/-- mini::selfhost::validate_files -/
theorem lok69 : LiveOk prims outside liveBad 69 (src_validate_files 69 96 97 98 99) := by decide +kernel

/-- mini::selfhost::build_files -/
theorem lok70 : LiveOk prims outside liveBad 70 (src_build_files 100 101 102 103 104) := by decide +kernel

/-- mini::selfhost::files_fuel -/
theorem lok71 : LiveOk prims outside liveBad 71 (src_files_fuel 52 71 75 99 105 106) := by decide +kernel

/-- mini::selfhost::cons_root -/
theorem lok97 : LiveOk prims outside liveBad 97 (src_cons_root 148) := by decide +kernel

/-- mini::selfhost::build_collected -/
theorem lok101 : LiveOk prims outside liveBad 101 (src_build_collected 159 160 161 162 163) := by decide +kernel

/-- mini::selfhost::need_limit -/
theorem lok123 : LiveOk prims outside liveBad 123 (src_need_limit) := by decide +kernel

/-- mini::selfhost::rest_needs -/
theorem lok137 : LiveOk prims outside liveBad 137 (src_rest_needs 76 139) := by decide +kernel

/-- mini::selfhost::build_checked -/
theorem lok159 : LiveOk prims outside liveBad 159 (src_build_checked 268 269 270 271) := by decide +kernel

/-- mini::selfhost::need_round -/
theorem lok241 : LiveOk prims outside liveBad 241 (src_need_round 403) := by decide +kernel

/-- mini::selfhost::same_needs -/
theorem lok242 : LiveOk prims outside liveBad 242 (src_same_needs 76 242) := by decide +kernel

/-- mini::selfhost::build_mono -/
theorem lok269 : LiveOk prims outside liveBad 269 (src_build_mono 436 437 438 439 440 441) := by decide +kernel

/-- mini::selfhost::need_round_at -/
theorem lok403 : LiveOk prims outside liveBad 403 (src_need_round_at 59 75 119 136 137 139 403 418 579 580) := by decide +kernel

/-- mini::selfhost::build_closed -/
theorem lok436 : LiveOk prims outside liveBad 436 (src_build_closed 656 657 658 659) := by decide +kernel

/-- mini::selfhost::need_capped -/
theorem lok579 : LiveOk prims outside liveBad 579 (src_need_capped 123) := by decide +kernel

/-- mini::selfhost::lx_tokens_at -/
theorem lok597 : LiveOk prims outside liveBad 597 (src_lx_tokens_at 414 834 835) := by decide +kernel

/-- mini::selfhost::lx_ranges_at -/
theorem lok600 : LiveOk prims outside liveBad 600 (src_lx_ranges_at 415 832 837 838) := by decide +kernel

/-- mini::selfhost::lx_filter_at -/
theorem lok601 : LiveOk prims outside liveBad 601 (src_lx_filter_at 416 832 839 840) := by decide +kernel

/-- mini::selfhost::untyped_rejected -/
theorem lok658 : LiveOk prims outside liveBad 658 (src_untyped_rejected 110 961 962 963 964) := by decide +kernel

/-- mini::selfhost::ty_insts -/
theorem lok668 : LiveOk prims outside liveBad 668 (src_ty_insts 56 272 666 668 977 978 979) := by decide +kernel

/-- mini::selfhost::wide_left_funcs -/
theorem lok961 : LiveOk prims outside liveBad 961 (src_wide_left_funcs 59 961 1187) := by decide +kernel

/-- mini::selfhost::cons_inst -/
theorem lok978 : LiveOk prims outside liveBad 978 (src_cons_inst 447) := by decide +kernel

/-- mini::selfhost::named_insts -/
theorem lok979 : LiveOk prims outside liveBad 979 (src_named_insts 56 1185 1223) := by decide +kernel

/-- mini::selfhost::offset_or_arith -/
theorem lok1051 : LiveOk prims outside liveBad 1051 (src_offset_or_arith 337 339 390 1052) := by decide +kernel

/-- mini::selfhost::arith_shift_right -/
theorem lok1054 : LiveOk prims outside liveBad 1054 (src_arith_shift_right 338 391 1053 1305) := by decide +kernel

/-- mini::selfhost::order -/
theorem lok1055 : LiveOk prims outside liveBad 1055 (src_order 337 338 391 392 800 802 803 810 1305 1309 1310 1311 1312) := by decide +kernel

/-- mini::selfhost::lx_ident_start -/
theorem lok1099 : LiveOk prims outside liveBad 1099 (src_lx_ident_start) := by decide +kernel

/-- mini::selfhost::lx_digit -/
theorem lok1101 : LiveOk prims outside liveBad 1101 (src_lx_digit) := by decide +kernel

/-- mini::selfhost::lx_space -/
theorem lok1104 : LiveOk prims outside liveBad 1104 (src_lx_space) := by decide +kernel

/-- mini::selfhost::wide_left_stmt -/
theorem lok1187 : LiveOk prims outside liveBad 1187 (src_wide_left_stmt 81 1187 1396 1397 1398 1399) := by decide +kernel

/-- mini::selfhost::decl_insts -/
theorem lok1223 : LiveOk prims outside liveBad 1223 (src_decl_insts 56 1251 1393 1457 1458) := by decide +kernel

/-- mini::selfhost::params_of -/
theorem lok1236 : LiveOk prims outside liveBad 1236 (src_params_of 103 1462 1463) := by decide +kernel

/-- mini::selfhost::result_of -/
theorem lok1238 : LiveOk prims outside liveBad 1238 (src_result_of 153 156 1464 1465 1466 1467 1468) := by decide +kernel

/-- mini::selfhost::ret_expected -/
theorem lok1244 : LiveOk prims outside liveBad 1244 (src_ret_expected) := by decide +kernel

/-- mini::selfhost::func_params -/
theorem lok1248 : LiveOk prims outside liveBad 1248 (src_func_params 1480) := by decide +kernel

/-- mini::selfhost::sign_key -/
theorem lok1310 : LiveOk prims outside liveBad 1310 (src_sign_key 337) := by decide +kernel

/-- mini::selfhost::order_sint -/
theorem lok1311 : LiveOk prims outside liveBad 1311 (src_order_sint 1516) := by decide +kernel

/-- mini::selfhost::order_uint -/
theorem lok1312 : LiveOk prims outside liveBad 1312 (src_order_uint 1517) := by decide +kernel

/-- mini::selfhost::tys_insts -/
theorem lok1457 : LiveOk prims outside liveBad 1457 (src_tys_insts 56 272 666 668 1457 1588) := by decide +kernel

/-- mini::selfhost::ret_of_ty -/
theorem lok1467 : LiveOk prims outside liveBad 1467 (src_ret_of_ty) := by decide +kernel

/-- mini::selfhost::func_ret -/
theorem lok1480 : LiveOk prims outside liveBad 1480 (src_func_ret 1618 1619 1620) := by decide +kernel

/-- mini::selfhost::join_insts -/
theorem lok1588 : LiveOk prims outside liveBad 1588 (src_join_insts 989) := by decide +kernel

/-- mini::selfhost::param_token -/
theorem lok1591 : LiveOk prims outside liveBad 1591 (src_param_token 153 628 1594) := by decide +kernel

/-- mini::selfhost::param_ty_of -/
theorem lok1597 : LiveOk prims outside liveBad 1597 (src_param_ty_of 153 156 1468 1675 1676 1677) := by decide +kernel

/-- mini::selfhost::cons_param -/
theorem lok1598 : LiveOk prims outside liveBad 1598 (src_cons_param 1678) := by decide +kernel

/-- mini::selfhost::func_body -/
theorem lok1618 : LiveOk prims outside liveBad 1618 (src_func_body) := by decide +kernel

/-- mini::selfhost::contracts_of -/
theorem lok1619 : LiveOk prims outside liveBad 1619 (src_contracts_of 56 153 156 1619 1702 1703 1704 1705 1706) := by decide +kernel

/-- mini::selfhost::block_of -/
theorem lok1620 : LiveOk prims outside liveBad 1620 (src_block_of 56 155 1707) := by decide +kernel

/-- mini::selfhost::lx_ident_continue -/
theorem lok1639 : LiveOk prims outside liveBad 1639 (src_lx_ident_continue 1099 1101) := by decide +kernel

/-- mini::selfhost::ref_ty -/
theorem lok1676 : LiveOk prims outside liveBad 1676 (src_ref_ty 984) := by decide +kernel

/-- mini::selfhost::contract_then -/
theorem lok1705 : LiveOk prims outside liveBad 1705 (src_contract_then 1241) := by decide +kernel

/-- mini::selfhost::stmts_of -/
theorem lok1707 : LiveOk prims outside liveBad 1707 (src_stmts_of 56 103 1768) := by decide +kernel

/-- mini::selfhost::stmt_first -/
theorem lok1768 : LiveOk prims outside liveBad 1768 (src_stmt_first 56 153 1707 1839 1840 1841 1842) := by decide +kernel

/-- mini::selfhost::is_level -/
theorem lok1807 : LiveOk prims outside liveBad 1807 (src_is_level 1861 1862 1863 1864 1865 1866 1867 1868 1869 1870) := by decide +kernel

/-- mini::selfhost::negated -/
theorem lok1812 : LiveOk prims outside liveBad 1812 (src_negated 1428) := by decide +kernel

/-- mini::selfhost::notted -/
theorem lok1814 : LiveOk prims outside liveBad 1814 (src_notted 1428) := by decide +kernel

/-- mini::selfhost::let_first -/
theorem lok1840 : LiveOk prims outside liveBad 1840 (src_let_first 56 153 156 628 1142 1468 1595 1599 1707 1912 1913 1914 1915 1916 1917 1918 1919 1920 1921 1922 1923 1924 1925 1926 1927) := by decide +kernel

/-- mini::selfhost::stmt_of -/
theorem lok1841 : LiveOk prims outside liveBad 1841 (src_stmt_of 56 153 156 1351 1353 1620 1916 1928 1929 1930 1931 1932 1933 1934 1935 1936 1937 1938 1939 1940 1941 1942 1943 1944 1945 1946 1947 1948) := by decide +kernel

/-- mini::selfhost::p_add -/
theorem lok1869 : LiveOk prims outside liveBad 1869 (src_p_add) := by decide +kernel

/-- mini::selfhost::tail_op -/
theorem lok1872 : LiveOk prims outside liveBad 1872 (src_tail_op 1968 1969 1970 1971 1972 1973 1974 1975 1976 1977 1978 1979 1980 1981 1982 1983) := by decide +kernel

/-- mini::selfhost::lit_let_of -/
theorem lok1917 : LiveOk prims outside liveBad 1917 (src_lit_let_of 56 1930 1931) := by decide +kernel

/-- mini::selfhost::let_match_of -/
theorem lok1919 : LiveOk prims outside liveBad 1919 (src_let_match_of 56 1930 2052 2053 2054 2055) := by decide +kernel

/-- mini::selfhost::lit_match_of -/
theorem lok1931 : LiveOk prims outside liveBad 1931 (src_lit_match_of 56 155 156 2067 2068 2069) := by decide +kernel

/-- mini::selfhost::nested_of -/
theorem lok1943 : LiveOk prims outside liveBad 1943 (src_nested_of 56 153 156 1351 1620 1942 2074) := by decide +kernel

/-- mini::selfhost::match_stmt_of -/
theorem lok1947 : LiveOk prims outside liveBad 1947 (src_match_stmt_of 56 1945 2052 2053 2054 2075) := by decide +kernel

/-- mini::selfhost::let_arms_of -/
theorem lok2055 : LiveOk prims outside liveBad 2055 (src_let_arms_of 56 75 103 2055 2168 2169) := by decide +kernel

/-- mini::selfhost::lit_bind -/
theorem lok2068 : LiveOk prims outside liveBad 2068 (src_lit_bind 1241) := by decide +kernel

/-- mini::selfhost::lit_arms_of -/
theorem lok2069 : LiveOk prims outside liveBad 2069 (src_lit_arms_of 56 103 2184 2185) := by decide +kernel

/-- mini::selfhost::match_arms_of -/
theorem lok2075 : LiveOk prims outside liveBad 2075 (src_match_arms_of 56 75 103 2075 2169 2200) := by decide +kernel

/-- mini::selfhost::wide_decimal -/
theorem lok2104 : LiveOk prims outside liveBad 2104 (src_wide_decimal 76 2225) := by decide +kernel

/-- mini::selfhost::let_arm_of -/
theorem lok2168 : LiveOk prims outside liveBad 2168 (src_let_arm_of 56 1620 2286 2292 2293 2294 2295) := by decide +kernel

/-- mini::selfhost::lit_arm_of -/
theorem lok2185 : LiveOk prims outside liveBad 2185 (src_lit_arm_of 56 156 2069 2315 2316 2317 2318 2319 2320 2321) := by decide +kernel

/-- mini::selfhost::match_arm_of -/
theorem lok2200 : LiveOk prims outside liveBad 2200 (src_match_arm_of 56 2292 2293 2294 2324) := by decide +kernel

/-- mini::selfhost::ref_target -/
theorem lok2201 : LiveOk prims outside liveBad 2201 (src_ref_target 153 156 1798 1820 2325) := by decide +kernel

/-- mini::selfhost::set_field_or_eval -/
theorem lok2204 : LiveOk prims outside liveBad 2204 (src_set_field_or_eval 1698 1706 1991 2269 2326 2329) := by decide +kernel

/-- mini::selfhost::let_body_of -/
theorem lok2295 : LiveOk prims outside liveBad 2295 (src_let_body_of 56 153 156 1835 1921 1924 2430 2431 2432) := by decide +kernel

/-- mini::selfhost::lit_body_of -/
theorem lok2317 : LiveOk prims outside liveBad 2317 (src_lit_body_of 56 156 1620 1921 1924 1932 2286 2431 2432) := by decide +kernel

/-- mini::selfhost::lit_if -/
theorem lok2318 : LiveOk prims outside liveBad 2318 (src_lit_if 1241) := by decide +kernel

/-- mini::selfhost::arm_body_of -/
theorem lok2324 : LiveOk prims outside liveBad 2324 (src_arm_body_of 56 156 1620 2286 2441) := by decide +kernel

/-- mini::selfhost::ref_rooted -/
theorem lok2325 : LiveOk prims outside liveBad 2325 (src_ref_rooted 1615) := by decide +kernel

/-- mini::selfhost::set_place_value -/
theorem lok2327 : LiveOk prims outside liveBad 2327 (src_set_place_value 2322 2442 2443) := by decide +kernel

/-- mini::selfhost::inner_let_of -/
theorem lok2430 : LiveOk prims outside liveBad 2430 (src_inner_let_of 56 2052 2053 2054 2055) := by decide +kernel

/-- mini::selfhost::inner_match_of -/
theorem lok2441 : LiveOk prims outside liveBad 2441 (src_inner_match_of 56 153 1835 2052 2053 2054 2075) := by decide +kernel

end Lanius.Faithful.SelfPure
