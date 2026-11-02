module

public import Lanius.Faithful.Gen.SelfPureTab
public import Lanius.Faithful.Gen.SelfSrc0
public import Lanius.Faithful.Gen.SelfSrcF_Inline_charOpen
public import Lanius.Faithful.Gen.SelfSrcF_Inline_pPathMore
public import Lanius.Faithful.Gen.SelfSrcF_anyNested
public import Lanius.Faithful.Gen.SelfSrcF_armsNaming
public import Lanius.Faithful.Gen.SelfSrcF_armsOf
public import Lanius.Faithful.Gen.SelfSrcF_callParts
public import Lanius.Faithful.Gen.SelfSrcF_consBinder
public import Lanius.Faithful.Gen.SelfSrcF_consTreeTail
public import Lanius.Faithful.Gen.SelfSrcF_flDecimal
public import Lanius.Faithful.Gen.SelfSrcF_isPathCall
public import Lanius.Faithful.Gen.SelfSrcF_isUnderscore
public import Lanius.Faithful.Gen.SelfSrcF_matchLetHead
public import Lanius.Faithful.Gen.SelfSrcF_matchTysOrNone
public import Lanius.Faithful.Gen.SelfSrcF_namesSome
public import Lanius.Faithful.Gen.SelfSrcF_nestedUsed
public import Lanius.Faithful.Gen.SelfSrcF_paramGoals
public import Lanius.Faithful.Gen.SelfSrcF_plainNaming
public import Lanius.Faithful.Gen.SelfSrcF_shadowUse
public import Lanius.Faithful.Gen.SelfSrcF_triedErr
public import Lanius.Faithful.Gen.SelfSrcF_variantArm
public import Lanius.Faithful.Gen.SelfSrcRest
import all Lanius.Faithful.Gen.SelfPureTab
import all Lanius.Faithful.Gen.SelfSrc0
import all Lanius.Faithful.Gen.SelfSrcF_Inline_charOpen
import all Lanius.Faithful.Gen.SelfSrcF_Inline_pPathMore
import all Lanius.Faithful.Gen.SelfSrcF_anyNested
import all Lanius.Faithful.Gen.SelfSrcF_armsNaming
import all Lanius.Faithful.Gen.SelfSrcF_armsOf
import all Lanius.Faithful.Gen.SelfSrcF_callParts
import all Lanius.Faithful.Gen.SelfSrcF_consBinder
import all Lanius.Faithful.Gen.SelfSrcF_consTreeTail
import all Lanius.Faithful.Gen.SelfSrcF_flDecimal
import all Lanius.Faithful.Gen.SelfSrcF_isPathCall
import all Lanius.Faithful.Gen.SelfSrcF_isUnderscore
import all Lanius.Faithful.Gen.SelfSrcF_matchLetHead
import all Lanius.Faithful.Gen.SelfSrcF_matchTysOrNone
import all Lanius.Faithful.Gen.SelfSrcF_namesSome
import all Lanius.Faithful.Gen.SelfSrcF_nestedUsed
import all Lanius.Faithful.Gen.SelfSrcF_paramGoals
import all Lanius.Faithful.Gen.SelfSrcF_plainNaming
import all Lanius.Faithful.Gen.SelfSrcF_shadowUse
import all Lanius.Faithful.Gen.SelfSrcF_triedErr
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

/-- `declareFuncs` of functions 2300 to 2399. -/
theorem dchunk23 : declsStep [(src_text_result_ty 377 462), (src_text_ok 377 462), (src_text_err 377 462), (src_text_option 377 462), (src_text_option_ty 377 462), (src_text_some 377 462), (src_text_none 377 462), (src_core_mem_size_of_of_mini_selfhost_List_mini_selfhost_Bind), (src_fl_exp_first_at 56 1927 2333), (src_view_local 1967 2334), (src_want_elem 1907), (src_infer_ret 1792 1794 2166 2173 2276), (src_cons_tree_tail 147), (src_fit_of), (src_fit_if), (src_fit_decl 56 2335), (src_and_known), (src_not_known), (src_block_value 56 152 155 569 1646 1647 1648 1650 1652 1658 1718 2253 2318), (src_core_mem_size_of_of_mini_selfhost_List_mini_selfhost_EffArm), (src_diverge_eff 2336), (src_is_binder_pat 152 155 1723 2185 2187 2337), (src_is_wild_arm 152 155 1723 2185 2187 2338), (src_names_some 1977 2323 2339), (src_wild_used 2340), (src_cons_use 2341), (src_variant_arm 103 2182 2342 2343), (src_rows_naming 96 103 2327 2344 2345), (src_arms_naming 96 103 2328 2339 2346), (src_wild_arm_for 147 152 155 247 570 591 2347), (src_tried_err 629), (src_single_ty 629), (src_if_same_tys), (src_fl_exp_digits 76 1835 2348), (src_view_array 1532 1746 1873), (src_fit_same_decl 56 2349), (src_diverge_call 355 643 897 1173 1178 2350), (src_binder_name_ok 162 1099 2295), (src_is_underscore 890 2351), (src_arm_names 152 155 403 2185 2186), (src_used_arms), (src_join_use 147), (src_wild_use 2329), (src_rows_use 2352), (src_row_cons 2346), (src_arm_naming 155 403 2353), (src_arms_naming_at 147), (src_wild_tail 147 155 247 570 850 2354 2355), (src_fl_exp_digit_at 56 75 105 1927 2333), (src_fit_args 56 103 629 2356 2357), (src_diverge_checked 635 928), (src_text_underscore 462), (src_nested_or_plain 2358 2359), (src_named_known 2186), (src_p_pattern_tuple), (src_wild_binders 75 96 147 629 2355 2360), (src_fit_args_next 56 2349), (src_fit_arg 56 152 155 1642 2165), (src_nest_use 2361 2362), (src_plain_use 2070 2363), (src_wild_binder 75 147 152 155 247 570 591), (src_row_pats 152 154 155 2185 2187), (src_nest_pats 2364 2365), (src_shadow_use 2366), (src_first_nested 75 103 2321 2364 2367), (src_nest_at 952 2368 2369 2370), (src_shadow_if), (src_first_at), (src_get_of_mini_selfhost_CTree 56 103 2368), (src_nest_inner 2371 2372), (src_column_arms 96 103 2361 2370 2373 2374), (src_wild_inner 2372 2375 2376 2377), (src_nest_arm 147 152 155 247 570 844 850 1680 2378 2379 2380), (src_column_arm 2368 2381 2382 2383), (src_is_last), (src_ends_wild 2247), (src_known_use 2384), (src_covers 162 1138 1871 2385), (src_replace_at 56 96 103 147 2378), (src_hidden_pat 96 147 247 570 2185 2187 2386), (src_hidden_expr 96 147 247 570 1661 1721 2386), (src_column_fit 2312), (src_row_fits 75 103 2382 2387), (src_column_sub 155 1723 2321 2388 2389 2390), (src_covered_use 155 2372 2391 2392), (src_covers_decl 2393), (src_hidden_path 2394 2395), (src_col_fits 155 1723 2321 2396), (src_quiet_sub 2397), (src_quiet_in 570 2317 2398), (src_sub_arm 147 152 155 247 570), (src_quiet_use 2399), (src_cols_quiet 75 103 2316 2392 2400), (src_covers_enum 2401), (src_named_path 96 147 155 247 570 591 608 609 1831), (src_text_hidden 462), (src_same_opt_name 890), (src_quiet_arm 2390 2402), (src_mentions 56 103 890 1079 2181 2398), (src_appended_use 570 1079 2372)]
    decls 1 1 0 0 = true := by decide +kernel

end Lanius.Faithful.SelfPure
