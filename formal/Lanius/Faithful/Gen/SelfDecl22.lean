module

public import Lanius.Faithful.Gen.SelfPureTab
public import Lanius.Faithful.Gen.SelfSrc0
public import Lanius.Faithful.Gen.SelfSrc4
public import Lanius.Faithful.Gen.SelfSrc5
public import Lanius.Faithful.Gen.SelfSrc7
public import Lanius.Faithful.Gen.SelfSrcF_Inline_charOpen
public import Lanius.Faithful.Gen.SelfSrcF_Inline_pArrayMore
public import Lanius.Faithful.Gen.SelfSrcF_Inline_pPathMore
public import Lanius.Faithful.Gen.SelfSrcF_anyNested
public import Lanius.Faithful.Gen.SelfSrcF_armsNaming
public import Lanius.Faithful.Gen.SelfSrcF_armsOf
public import Lanius.Faithful.Gen.SelfSrcF_consBinder
public import Lanius.Faithful.Gen.SelfSrcF_consTreeTail
public import Lanius.Faithful.Gen.SelfSrcF_divergeArm
public import Lanius.Faithful.Gen.SelfSrcF_flDecimal
public import Lanius.Faithful.Gen.SelfSrcF_flExpFirst
public import Lanius.Faithful.Gen.SelfSrcF_fnInstRet
public import Lanius.Faithful.Gen.SelfSrcF_hasConst
public import Lanius.Faithful.Gen.SelfSrcF_intLiteral
public import Lanius.Faithful.Gen.SelfSrcF_isPathCall
public import Lanius.Faithful.Gen.SelfSrcF_isTryEnum
public import Lanius.Faithful.Gen.SelfSrcF_isUnderscore
public import Lanius.Faithful.Gen.SelfSrcF_matchLetHead
public import Lanius.Faithful.Gen.SelfSrcF_matchTysOrNone
public import Lanius.Faithful.Gen.SelfSrcF_namesSome
public import Lanius.Faithful.Gen.SelfSrcF_nestedUsed
public import Lanius.Faithful.Gen.SelfSrcF_noBlock
public import Lanius.Faithful.Gen.SelfSrcF_paramGoals
public import Lanius.Faithful.Gen.SelfSrcF_plainNaming
public import Lanius.Faithful.Gen.SelfSrcF_shadowUse
public import Lanius.Faithful.Gen.SelfSrcF_sliceHead
public import Lanius.Faithful.Gen.SelfSrcF_triedErr
public import Lanius.Faithful.Gen.SelfSrcF_triedIf
public import Lanius.Faithful.Gen.SelfSrcF_variantArm
public import Lanius.Faithful.Gen.SelfSrcRest
import all Lanius.Faithful.Gen.SelfPureTab
import all Lanius.Faithful.Gen.SelfSrc0
import all Lanius.Faithful.Gen.SelfSrc4
import all Lanius.Faithful.Gen.SelfSrc5
import all Lanius.Faithful.Gen.SelfSrc7
import all Lanius.Faithful.Gen.SelfSrcF_Inline_charOpen
import all Lanius.Faithful.Gen.SelfSrcF_Inline_pArrayMore
import all Lanius.Faithful.Gen.SelfSrcF_Inline_pPathMore
import all Lanius.Faithful.Gen.SelfSrcF_anyNested
import all Lanius.Faithful.Gen.SelfSrcF_armsNaming
import all Lanius.Faithful.Gen.SelfSrcF_armsOf
import all Lanius.Faithful.Gen.SelfSrcF_consBinder
import all Lanius.Faithful.Gen.SelfSrcF_consTreeTail
import all Lanius.Faithful.Gen.SelfSrcF_divergeArm
import all Lanius.Faithful.Gen.SelfSrcF_flDecimal
import all Lanius.Faithful.Gen.SelfSrcF_flExpFirst
import all Lanius.Faithful.Gen.SelfSrcF_fnInstRet
import all Lanius.Faithful.Gen.SelfSrcF_hasConst
import all Lanius.Faithful.Gen.SelfSrcF_intLiteral
import all Lanius.Faithful.Gen.SelfSrcF_isPathCall
import all Lanius.Faithful.Gen.SelfSrcF_isTryEnum
import all Lanius.Faithful.Gen.SelfSrcF_isUnderscore
import all Lanius.Faithful.Gen.SelfSrcF_matchLetHead
import all Lanius.Faithful.Gen.SelfSrcF_matchTysOrNone
import all Lanius.Faithful.Gen.SelfSrcF_namesSome
import all Lanius.Faithful.Gen.SelfSrcF_nestedUsed
import all Lanius.Faithful.Gen.SelfSrcF_noBlock
import all Lanius.Faithful.Gen.SelfSrcF_paramGoals
import all Lanius.Faithful.Gen.SelfSrcF_plainNaming
import all Lanius.Faithful.Gen.SelfSrcF_shadowUse
import all Lanius.Faithful.Gen.SelfSrcF_sliceHead
import all Lanius.Faithful.Gen.SelfSrcF_triedErr
import all Lanius.Faithful.Gen.SelfSrcF_triedIf
import all Lanius.Faithful.Gen.SelfSrcF_variantArm
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
import all Lanius.Mini.Compiler.P.assignFrom
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
import all Lanius.Mini.Compiler.P.render
import all Lanius.Mini.Compiler.P.repeatType
import all Lanius.Mini.Compiler.P.shortCircuit
import all Lanius.Mini.Compiler.P.sigs
import all Lanius.Mini.Compiler.P.sintToUint
import all Lanius.Mini.Compiler.P.storeArray
import all Lanius.Mini.Compiler.P.storeEvalWord
import all Lanius.Mini.Compiler.P.storeType
import all Lanius.Mini.Compiler.P.storeWordElement
import all Lanius.Mini.Compiler.P.structFields
import all Lanius.Mini.Compiler.P.usizeWidth
import all Lanius.Mini.Compiler.P.widthOf
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

/-- `declareFuncs` of functions 2200 to 2299. -/
theorem dchunk22 : declsStep [(src_p_assign_shr), (src_shift_of_u64 56 75 105 2201), (src_cons_expr_tail 1296), (src_tried_if 2229), (src_is_try_enum 586 861 866 1064 2230 2231 2232 2233 2234 2235 2236 2237 2238), (src_boxed_of_mini_selfhost_List_mini_selfhost_Bind 50 2159 2239), (src_fl_exp_first 76 2240), (src_fl_sub 1673 1967 2074 2075 2167 2207), (src_infer_ret 1733 1735 2108 2109 2173), (src_cons_tree_tail 139), (src_fit_named 56 1486 1501 1811 2052 2053 2054 2241 2242 2243), (src_no_block 103 147 2211 2244 2245 2246), (src_boxed_of_mini_selfhost_List_mini_selfhost_EffArm 50 2176 2247), (src_arm_eff 1810), (src_diverge_arm 2248), (src_all_binders 103 2215 2249), (src_wild_alone 96 2250), (src_cons_wild 139), (src_all_name_some 103 2218 2251), (src_nested_used 2252), (src_variant_arms 96 1915 2220 2253 2254 2255), (src_uses_wild 1915 2221 2256), (src_arms_or_wild 96 103 1915 2209 2222 2256 2257), (src_length_of_mini_selfhost_CTree 75 103 2223), (src_length_of_mini_selfhost_VariantTy 75 1915 2224), (src_arms_by_variant 96 103 1915 2209 2225 2256), (src_is_some_name), (src_any_variant 257 1065 2227), (src_cons_binder 374), (src_tried_shape 1418 1890 2258 2259 2260), (src_text_core 374 532), (src_text_result 374 532), (src_text_result_ty 374 532), (src_text_ok 374 532), (src_text_err 374 532), (src_text_option 374 532), (src_text_option_ty 374 532), (src_text_some 374 532), (src_text_none 374 532), (src_core_mem_size_of_of_mini_selfhost_List_mini_selfhost_Bind), (src_fl_exp_first_at 56 1866 2261), (src_fit_of), (src_fit_if), (src_fit_decl 56 2262), (src_and_known), (src_not_known), (src_block_value 56 144 147 545 1590 1591 1592 1594 1596 1602 1660 2189 2246), (src_core_mem_size_of_of_mini_selfhost_List_mini_selfhost_EffArm), (src_diverge_eff 2263), (src_is_binder_pat 144 147 1665 2128 2130 2264), (src_is_wild_arm 144 147 1665 2128 2130 2265), (src_names_some 1915 2251 2266), (src_wild_used 2267), (src_cons_use 2268), (src_variant_arm 103 2125 2269 2270), (src_rows_naming 96 103 2255 2271 2272), (src_arms_naming 96 103 2256 2266 2273), (src_wild_arm_for 139 144 147 235 546 567 2274), (src_tried_err 600), (src_single_ty 600), (src_if_same_tys), (src_fl_exp_digits 76 1776 2275), (src_fit_same_decl 56 2276), (src_diverge_call 339 614 868 1135 1140 2277), (src_binder_name_ok 154 1065 2227), (src_is_underscore 861 2278), (src_arm_names 144 147 385 2128 2129), (src_used_arms), (src_join_use 139), (src_wild_use 2257), (src_rows_use 2279), (src_row_cons 2273), (src_arm_naming 147 385 2280), (src_arms_naming_at 139), (src_wild_tail 139 147 235 546 821 2281 2282), (src_fl_exp_digit_at 56 75 105 1866 2261), (src_fit_args 56 103 600 2283 2284), (src_diverge_checked 606 893), (src_text_underscore 532), (src_nested_or_plain 2285 2286), (src_named_known 2129), (src_p_pattern_tuple), (src_wild_binders 75 96 139 600 2282 2287), (src_fit_args_next 56 2276), (src_fit_arg 56 144 147 1586 2110), (src_nest_use 2288 2289), (src_plain_use 2012 2290), (src_wild_binder 75 139 144 147 235 546 567), (src_row_pats 144 146 147 2128 2130), (src_nest_pats 2291 2292), (src_shadow_use 2293), (src_first_nested 75 103 2249 2291 2294), (src_nest_at 917 2295 2296 2297), (src_shadow_if), (src_first_at), (src_get_of_mini_selfhost_CTree 56 103 2295), (src_nest_inner 2298 2299), (src_column_arms 96 103 2288 2297 2300 2301), (src_wild_inner 2299 2302 2303 2304), (src_nest_arm 139 144 147 235 546 815 821 1624 2305 2306 2307)]
    decls 2 2 0 0 = true := by decide +kernel

end Lanius.Faithful.SelfPure
