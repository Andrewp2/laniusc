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
public import Lanius.Faithful.Gen.SelfSrcF_flDecimal
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
import all Lanius.Faithful.Gen.SelfSrcF_flDecimal
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

/-- `declareFuncs` of functions 2300 to 2389. -/
theorem dchunk23 : declsStep [(src_fit_decl 56 2320), (src_and_known), (src_not_known), (src_block_value 56 152 155 573 1635 1636 1637 1639 1641 1647 1705 2238 2303), (src_core_mem_size_of_of_mini_selfhost_List_mini_selfhost_EffArm), (src_diverge_eff 2321), (src_is_binder_pat 152 155 1710 2170 2172 2322), (src_is_wild_arm 152 155 1710 2170 2172 2323), (src_names_some 1962 2308 2324), (src_wild_used 2325), (src_cons_use 2326), (src_variant_arm 103 2167 2327 2328), (src_rows_naming 96 103 2312 2329 2330), (src_arms_naming 96 103 2313 2324 2331), (src_wild_arm_for 147 152 155 248 574 595 2332), (src_tried_err 628), (src_single_ty 628), (src_if_same_tys), (src_fl_exp_digits 76 1821 2333), (src_view_array 1524 1733 1859), (src_fit_same_decl 56 2334), (src_diverge_call 359 642 898 1166 1171 2335), (src_binder_name_ok 162 1096 2280), (src_is_underscore 891 2336), (src_arm_names 152 155 406 2170 2171), (src_used_arms), (src_join_use 147), (src_wild_use 2314), (src_rows_use 2337), (src_row_cons 2331), (src_arm_naming 155 406 2338), (src_arms_naming_at 147), (src_wild_tail 147 155 248 574 851 2339 2340), (src_fl_exp_digit_at 56 75 105 1912 2318), (src_fit_args 56 103 628 2341 2342), (src_diverge_checked 634 923), (src_text_underscore 464), (src_nested_or_plain 2343 2344), (src_named_known 2171), (src_p_pattern_tuple), (src_wild_binders 75 96 147 628 2340 2345), (src_fit_args_next 56 2334), (src_fit_arg 56 152 155 1631 2150), (src_nest_use 2346 2347), (src_plain_use 2055 2348), (src_wild_binder 75 147 152 155 248 574 595), (src_row_pats 152 154 155 2170 2172), (src_nest_pats 2349 2350), (src_shadow_use 2351), (src_first_nested 75 103 2306 2349 2352), (src_nest_at 947 2353 2354 2355), (src_shadow_if), (src_first_at), (src_get_of_mini_selfhost_CTree 56 103 2353), (src_nest_inner 2356 2357), (src_column_arms 96 103 2346 2355 2358 2359), (src_wild_inner 2357 2360 2361 2362), (src_nest_arm 147 152 155 248 574 845 851 1669 2363 2364 2365), (src_column_arm 2353 2366 2367 2368), (src_is_last), (src_ends_wild 2232), (src_known_use 2369), (src_covers 162 1135 1857 2370), (src_replace_at 56 96 103 147 2363), (src_hidden_pat 96 147 248 574 2170 2172 2371), (src_hidden_expr 96 147 248 574 1650 1708 2371), (src_column_fit 2297), (src_row_fits 75 103 2367 2372), (src_column_sub 155 1710 2306 2373 2374 2375), (src_covered_use 155 2357 2376 2377), (src_covers_decl 2378), (src_hidden_path 2379 2380), (src_col_fits 155 1710 2306 2381), (src_quiet_sub 2382), (src_quiet_in 574 2302 2383), (src_sub_arm 147 152 155 248 574), (src_quiet_use 2384), (src_cols_quiet 75 103 2301 2377 2385), (src_covers_enum 2386), (src_named_path 96 147 155 248 574 595 612 613 1817), (src_text_hidden 464), (src_same_opt_name 891), (src_quiet_arm 2375 2387), (src_mentions 56 103 891 1076 2166 2383), (src_appended_use 574 1076 2357), (src_col_quiet 155 1710 2374), (src_covers_all 533 2301 2386 2388), (src_wild_pat 96 147 248 574 2170 2172 2336 2379), (src_covered_by 103 2166 2388 2389), (src_plain_naming 2167 2301 2302 2330)]
    decls 1 1 0 0 = true := by decide +kernel

end Lanius.Faithful.SelfPure
