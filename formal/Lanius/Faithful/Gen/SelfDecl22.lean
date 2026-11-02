module

public import Lanius.Faithful.Gen.SelfPureTab
public import Lanius.Faithful.Gen.SelfSrc4
public import Lanius.Faithful.Gen.SelfSrc5
public import Lanius.Faithful.Gen.SelfSrc7
public import Lanius.Faithful.Gen.SelfSrcF_Inline_charOpen
public import Lanius.Faithful.Gen.SelfSrcF_Inline_pArrayMore
public import Lanius.Faithful.Gen.SelfSrcF_Inline_pPathMore
public import Lanius.Faithful.Gen.SelfSrcF_anyNested
public import Lanius.Faithful.Gen.SelfSrcF_argView
public import Lanius.Faithful.Gen.SelfSrcF_armsNaming
public import Lanius.Faithful.Gen.SelfSrcF_armsOf
public import Lanius.Faithful.Gen.SelfSrcF_callParts
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
public import Lanius.Faithful.Gen.SelfSrcF_shadowUse
public import Lanius.Faithful.Gen.SelfSrcF_sliceHead
public import Lanius.Faithful.Gen.SelfSrcF_triedErr
public import Lanius.Faithful.Gen.SelfSrcF_triedIf
public import Lanius.Faithful.Gen.SelfSrcF_variantArm
public import Lanius.Faithful.Gen.SelfSrcRest
import all Lanius.Faithful.Gen.SelfPureTab
import all Lanius.Faithful.Gen.SelfSrc4
import all Lanius.Faithful.Gen.SelfSrc5
import all Lanius.Faithful.Gen.SelfSrc7
import all Lanius.Faithful.Gen.SelfSrcF_Inline_charOpen
import all Lanius.Faithful.Gen.SelfSrcF_Inline_pArrayMore
import all Lanius.Faithful.Gen.SelfSrcF_Inline_pPathMore
import all Lanius.Faithful.Gen.SelfSrcF_anyNested
import all Lanius.Faithful.Gen.SelfSrcF_argView
import all Lanius.Faithful.Gen.SelfSrcF_armsNaming
import all Lanius.Faithful.Gen.SelfSrcF_armsOf
import all Lanius.Faithful.Gen.SelfSrcF_callParts
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
theorem dchunk22 : declsStep [(src_p_assign_add), (src_p_assign_sub), (src_p_assign_mul), (src_p_assign_band), (src_p_assign_bor), (src_p_assign_xor), (src_p_assign_shl), (src_p_assign_shr), (src_shift_of_u64 56 75 106 2208), (src_cons_expr_tail 1299), (src_tried_if 2240), (src_is_try_enum 589 863 868 1066 2241 2242 2243 2244 2245 2246 2247 2248 2249), (src_boxed_of_mini_selfhost_List_mini_selfhost_Bind 50 2159 2250), (src_fl_exp_first 76 2251), (src_fl_sub 1676 1972 2075 2076 2167 2214), (src_arg_view 1989 2252 2253), (src_infer_inst 404 406 870 1992 2103 2109 2254), (src_infer_args 404 406 870 1738 1992 2103 2109 2219), (src_cons_tree 2255), (src_inst_from), (src_match_tys_or_none 1992), (src_fit_named 56 1489 1504 1815 2053 2054 2055 2256 2257 2258), (src_no_block 104 151 2222 2259 2260 2261), (src_boxed_of_mini_selfhost_List_mini_selfhost_EffArm 50 2183 2262), (src_arm_eff 1814), (src_diverge_arm 2263), (src_all_binders 104 2226 2264), (src_wild_alone 97 2265), (src_cons_wild 143), (src_all_name_some 104 2229 2266), (src_nested_used 2267), (src_variant_arms 97 1920 2231 2268 2269 2270), (src_uses_wild 1920 2232 2271), (src_arms_or_wild 97 104 1920 2233 2255 2271 2272), (src_length_of_mini_selfhost_CTree 75 104 2234), (src_length_of_mini_selfhost_VariantTy 75 1920 2235), (src_arms_by_variant 97 104 1920 2236 2255 2271), (src_is_some_name), (src_any_variant 260 1067 2238), (src_cons_binder 377), (src_tried_shape 1421 1895 2273 2274 2275), (src_text_core 377 535), (src_text_result 377 535), (src_text_result_ty 377 535), (src_text_ok 377 535), (src_text_err 377 535), (src_text_option 377 535), (src_text_option_ty 377 535), (src_text_some 377 535), (src_text_none 377 535), (src_core_mem_size_of_of_mini_selfhost_List_mini_selfhost_Bind), (src_fl_exp_first_at 56 1870 2276), (src_view_local 1910 2277), (src_want_elem 1850), (src_infer_ret 1736 1738 2109 2116 2219), (src_cons_tree_tail 143), (src_fit_of), (src_fit_if), (src_fit_decl 56 2278), (src_and_known), (src_not_known), (src_block_value 56 148 151 548 1593 1594 1595 1597 1599 1605 1663 2196 2261), (src_core_mem_size_of_of_mini_selfhost_List_mini_selfhost_EffArm), (src_diverge_eff 2279), (src_is_binder_pat 148 151 1668 2128 2130 2280), (src_is_wild_arm 148 151 1668 2128 2130 2281), (src_names_some 1920 2266 2282), (src_wild_used 2283), (src_cons_use 2284), (src_variant_arm 104 2125 2285 2286), (src_rows_naming 97 104 2270 2287 2288), (src_arms_naming 97 104 2271 2282 2289), (src_wild_arm_for 143 148 151 238 549 570 2290), (src_tried_err 603), (src_single_ty 603), (src_if_same_tys), (src_fl_exp_digits 76 1779 2291), (src_view_array 1489 1691 1817), (src_fit_same_decl 56 2292), (src_diverge_call 342 617 870 1137 1142 2293), (src_binder_name_ok 158 1067 2238), (src_is_underscore 863 2294), (src_arm_names 148 151 388 2128 2129), (src_used_arms), (src_join_use 143), (src_wild_use 2272), (src_rows_use 2295), (src_row_cons 2289), (src_arm_naming 151 388 2296), (src_arms_naming_at 143), (src_wild_tail 143 151 238 549 823 2297 2298), (src_fl_exp_digit_at 56 75 106 1870 2276), (src_fit_args 56 104 603 2299 2300), (src_diverge_checked 609 895), (src_text_underscore 535), (src_nested_or_plain 2301 2302), (src_named_known 2129), (src_p_pattern_tuple), (src_wild_binders 75 97 143 603 2298 2303), (src_fit_args_next 56 2292)]
    decls 2 2 0 0 = true := by decide +kernel

end Lanius.Faithful.SelfPure
