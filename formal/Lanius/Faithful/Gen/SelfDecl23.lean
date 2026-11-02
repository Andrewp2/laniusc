module

public import Lanius.Faithful.Gen.SelfPureTab
public import Lanius.Faithful.Gen.SelfSrc0
public import Lanius.Faithful.Gen.SelfSrcF_Inline_charOpen
public import Lanius.Faithful.Gen.SelfSrcF_Inline_pPathMore
public import Lanius.Faithful.Gen.SelfSrcF_anyNested
public import Lanius.Faithful.Gen.SelfSrcF_armsNaming
public import Lanius.Faithful.Gen.SelfSrcF_armsOf
public import Lanius.Faithful.Gen.SelfSrcF_consBinder
public import Lanius.Faithful.Gen.SelfSrcF_isUnderscore
public import Lanius.Faithful.Gen.SelfSrcF_matchTysOrNone
public import Lanius.Faithful.Gen.SelfSrcF_paramGoals
public import Lanius.Faithful.Gen.SelfSrcF_plainNaming
public import Lanius.Faithful.Gen.SelfSrcF_shadowUse
public import Lanius.Faithful.Gen.SelfSrcF_variantArm
import all Lanius.Faithful.Gen.SelfPureTab
import all Lanius.Faithful.Gen.SelfSrc0
import all Lanius.Faithful.Gen.SelfSrcF_Inline_charOpen
import all Lanius.Faithful.Gen.SelfSrcF_Inline_pPathMore
import all Lanius.Faithful.Gen.SelfSrcF_anyNested
import all Lanius.Faithful.Gen.SelfSrcF_armsNaming
import all Lanius.Faithful.Gen.SelfSrcF_armsOf
import all Lanius.Faithful.Gen.SelfSrcF_consBinder
import all Lanius.Faithful.Gen.SelfSrcF_isUnderscore
import all Lanius.Faithful.Gen.SelfSrcF_matchTysOrNone
import all Lanius.Faithful.Gen.SelfSrcF_paramGoals
import all Lanius.Faithful.Gen.SelfSrcF_plainNaming
import all Lanius.Faithful.Gen.SelfSrcF_shadowUse
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

/-- `declareFuncs` of functions 2300 to 2367. -/
theorem dchunk23 : declsStep [(src_binder_name_ok 162 1087 2258), (src_is_underscore 884 2314), (src_arm_names 152 155 403 2148 2149), (src_used_arms), (src_join_use 147), (src_wild_use 2292), (src_rows_use 2315), (src_row_cons 2309), (src_arm_naming 155 403 2316), (src_arms_naming_at 147), (src_wild_tail 147 155 247 569 844 2317 2318), (src_fl_exp_digit_at 56 75 105 1890 2296), (src_fit_args 56 103 623 2319 2320), (src_diverge_checked 629 916), (src_text_underscore 461), (src_nested_or_plain 2321 2322), (src_named_known 2149), (src_p_pattern_tuple), (src_wild_binders 75 96 147 623 2318 2323), (src_fit_args_next 56 2312), (src_fit_arg 56 152 155 1609 2128), (src_nest_use 2324 2325), (src_plain_use 2033 2326), (src_wild_binder 75 147 152 155 247 569 590), (src_row_pats 152 154 155 2148 2150), (src_nest_pats 2327 2328), (src_shadow_use 2329), (src_first_nested 75 103 2284 2327 2330), (src_nest_at 940 2331 2332 2333), (src_shadow_if), (src_first_at), (src_get_of_mini_selfhost_CTree 56 103 2331), (src_nest_inner 2334 2335), (src_column_arms 96 103 2324 2333 2336 2337), (src_wild_inner 2335 2338 2339 2340), (src_nest_arm 147 152 155 247 569 838 844 1647 2341 2342 2343), (src_column_arm 2331 2344 2345 2346), (src_is_last), (src_ends_wild 2210), (src_known_use 2347), (src_covers 162 1126 1835 2348), (src_replace_at 56 96 103 147 2341), (src_hidden_pat 96 147 247 569 2148 2150 2349), (src_hidden_expr 96 147 247 569 1628 1686 2349), (src_column_fit 2275), (src_row_fits 75 103 2345 2350), (src_column_sub 155 1688 2284 2351 2352 2353), (src_covered_use 155 2335 2354 2355), (src_covers_decl 2356), (src_hidden_path 2357 2358), (src_col_fits 155 1688 2284 2359), (src_quiet_sub 2360), (src_quiet_in 569 2280 2361), (src_sub_arm 147 152 155 247 569), (src_quiet_use 2362), (src_cols_quiet 75 103 2279 2355 2363), (src_covers_enum 2364), (src_named_path 96 147 155 247 569 590 607 608 1795), (src_text_hidden 461), (src_same_opt_name 884), (src_quiet_arm 2353 2365), (src_mentions 56 103 884 1067 2144 2361), (src_appended_use 569 1067 2335), (src_col_quiet 155 1688 2352), (src_covers_all 526 2279 2364 2366), (src_wild_pat 96 147 247 569 2148 2150 2314 2357), (src_covered_by 103 2144 2366 2367), (src_plain_naming 2145 2279 2280 2308)]
    decls 0 0 0 0 = true := by decide +kernel

end Lanius.Faithful.SelfPure
