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
public import Lanius.Faithful.Gen.SelfSrcF_paramGoals
public import Lanius.Faithful.Gen.SelfSrcF_plainNaming
public import Lanius.Faithful.Gen.SelfSrcF_shadowUse
public import Lanius.Faithful.Gen.SelfSrcF_triedErr
public import Lanius.Faithful.Gen.SelfSrcF_variantArm
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
import all Lanius.Faithful.Gen.SelfSrcF_paramGoals
import all Lanius.Faithful.Gen.SelfSrcF_plainNaming
import all Lanius.Faithful.Gen.SelfSrcF_shadowUse
import all Lanius.Faithful.Gen.SelfSrcF_triedErr
import all Lanius.Faithful.Gen.SelfSrcF_variantArm
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

/-- `declareFuncs` of functions 2300 to 2382. -/
theorem dchunk23 : declsStep [(src_is_wild_arm 144 147 1701 2163 2165 2316), (src_names_some 1955 2301 2317), (src_wild_used 2318), (src_cons_use 2319), (src_variant_arm 103 2160 2320 2321), (src_rows_naming 96 103 2305 2322 2323), (src_arms_naming 96 103 2306 2317 2324), (src_wild_arm_for 139 144 147 235 548 569 2325), (src_tried_err 607), (src_single_ty 607), (src_if_same_tys), (src_fl_exp_digits 76 1813 2326), (src_view_array 1510 1724 1851), (src_fit_same_decl 56 2327), (src_diverge_call 339 621 874 1151 1156 2328), (src_binder_name_ok 154 1077 2273), (src_is_underscore 867 2329), (src_arm_names 144 147 385 2163 2164), (src_used_arms), (src_join_use 139), (src_wild_use 2307), (src_rows_use 2330), (src_row_cons 2324), (src_arm_naming 147 385 2331), (src_arms_naming_at 139), (src_wild_tail 139 147 235 548 827 2332 2333), (src_fl_exp_digit_at 56 75 105 1905 2311), (src_fit_args 56 103 607 2334 2335), (src_diverge_checked 613 905), (src_text_underscore 534), (src_nested_or_plain 2336 2337), (src_named_known 2164), (src_p_pattern_tuple), (src_wild_binders 75 96 139 607 2333 2338), (src_fit_args_next 56 2327), (src_fit_arg 56 144 147 1620 2143), (src_nest_use 2339 2340), (src_plain_use 2048 2341), (src_wild_binder 75 139 144 147 235 548 569), (src_row_pats 144 146 147 2163 2165), (src_nest_pats 2342 2343), (src_shadow_use 2344), (src_first_nested 75 103 2299 2342 2345), (src_nest_at 929 2346 2347 2348), (src_shadow_if), (src_first_at), (src_get_of_mini_selfhost_CTree 56 103 2346), (src_nest_inner 2349 2350), (src_column_arms 96 103 2339 2348 2351 2352), (src_wild_inner 2350 2353 2354 2355), (src_nest_arm 139 144 147 235 548 821 827 1658 2356 2357 2358), (src_column_arm 2346 2359 2360 2361), (src_is_last), (src_ends_wild 2225), (src_known_use 2362), (src_covers 154 1116 1849 2363), (src_replace_at 56 96 103 139 2356), (src_hidden_pat 96 139 235 548 2163 2165 2364), (src_hidden_expr 96 139 235 548 1639 1699 2364), (src_column_fit 2290), (src_row_fits 75 103 2360 2365), (src_column_sub 147 1701 2299 2366 2367 2368), (src_covered_use 147 2350 2369 2370), (src_covers_decl 2371), (src_hidden_path 2372 2373), (src_col_fits 147 1701 2299 2374), (src_quiet_sub 2375), (src_quiet_in 548 2295 2376), (src_sub_arm 139 144 147 235 548), (src_quiet_use 2377), (src_cols_quiet 75 103 2294 2370 2378), (src_covers_enum 2379), (src_named_path 96 139 147 235 548 569 586 587 1809), (src_text_hidden 534), (src_same_opt_name 867), (src_quiet_arm 2368 2380), (src_mentions 56 103 867 1057 2159 2376), (src_appended_use 548 1057 2350), (src_col_quiet 147 1701 2367), (src_covers_all 505 2294 2379 2381), (src_wild_pat 96 139 235 548 2163 2165 2329 2372), (src_covered_by 103 2159 2381 2382), (src_plain_naming 2160 2294 2295 2323)]
    decls 1 1 0 0 = true := by decide +kernel

end Lanius.Faithful.SelfPure
