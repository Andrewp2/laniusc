module

public import Lanius.Faithful.Gen.SelfPureTab
public import Lanius.Faithful.Gen.SelfSrc1
public import Lanius.Faithful.Gen.SelfSrc2
public import Lanius.Faithful.Gen.SelfSrc5
public import Lanius.Faithful.Gen.SelfSrc6
public import Lanius.Faithful.Gen.SelfSrc7
public import Lanius.Faithful.Gen.SelfSrcF_Inline_pAndTail
public import Lanius.Faithful.Gen.SelfSrcF_Inline_pArgsMore
public import Lanius.Faithful.Gen.SelfSrcF_Inline_pArrayAfterCommaTrailing
public import Lanius.Faithful.Gen.SelfSrcF_Inline_pArrayMore
public import Lanius.Faithful.Gen.SelfSrcF_Inline_pBoundTypeArgsAfterCommaMore
public import Lanius.Faithful.Gen.SelfSrcF_Inline_pEnumTypeParam
public import Lanius.Faithful.Gen.SelfSrcF_Inline_pExpr
public import Lanius.Faithful.Gen.SelfSrcF_Inline_pIdentPlain
public import Lanius.Faithful.Gen.SelfSrcF_Inline_pImplMethodsSome
public import Lanius.Faithful.Gen.SelfSrcF_Inline_pLeTail
public import Lanius.Faithful.Gen.SelfSrcF_Inline_pModTail
public import Lanius.Faithful.Gen.SelfSrcF_Inline_pPathMore
public import Lanius.Faithful.Gen.SelfSrcF_Inline_pSelfValue
public import Lanius.Faithful.Gen.SelfSrcF_Inline_pStructFieldsAfterCommaMore
public import Lanius.Faithful.Gen.SelfSrcF_Inline_pStructFieldsMore
public import Lanius.Faithful.Gen.SelfSrcF_Inline_pTypeArgsNone
public import Lanius.Faithful.Gen.SelfSrcF_collect
public import Lanius.Faithful.Gen.SelfSrcF_distinct
public import Lanius.Faithful.Gen.SelfSrcF_hasKids
public import Lanius.Faithful.Gen.SelfSrcF_methodDecl
public import Lanius.Faithful.Gen.SelfSrcF_moduleOr
public import Lanius.Faithful.Gen.SelfSrcF_textSelf
import all Lanius.Faithful.Gen.SelfPureTab
import all Lanius.Faithful.Gen.SelfSrc1
import all Lanius.Faithful.Gen.SelfSrc2
import all Lanius.Faithful.Gen.SelfSrc5
import all Lanius.Faithful.Gen.SelfSrc6
import all Lanius.Faithful.Gen.SelfSrc7
import all Lanius.Faithful.Gen.SelfSrcF_Inline_pAndTail
import all Lanius.Faithful.Gen.SelfSrcF_Inline_pArgsMore
import all Lanius.Faithful.Gen.SelfSrcF_Inline_pArrayAfterCommaTrailing
import all Lanius.Faithful.Gen.SelfSrcF_Inline_pArrayMore
import all Lanius.Faithful.Gen.SelfSrcF_Inline_pBoundTypeArgsAfterCommaMore
import all Lanius.Faithful.Gen.SelfSrcF_Inline_pEnumTypeParam
import all Lanius.Faithful.Gen.SelfSrcF_Inline_pExpr
import all Lanius.Faithful.Gen.SelfSrcF_Inline_pIdentPlain
import all Lanius.Faithful.Gen.SelfSrcF_Inline_pImplMethodsSome
import all Lanius.Faithful.Gen.SelfSrcF_Inline_pLeTail
import all Lanius.Faithful.Gen.SelfSrcF_Inline_pModTail
import all Lanius.Faithful.Gen.SelfSrcF_Inline_pPathMore
import all Lanius.Faithful.Gen.SelfSrcF_Inline_pSelfValue
import all Lanius.Faithful.Gen.SelfSrcF_Inline_pStructFieldsAfterCommaMore
import all Lanius.Faithful.Gen.SelfSrcF_Inline_pStructFieldsMore
import all Lanius.Faithful.Gen.SelfSrcF_Inline_pTypeArgsNone
import all Lanius.Faithful.Gen.SelfSrcF_collect
import all Lanius.Faithful.Gen.SelfSrcF_distinct
import all Lanius.Faithful.Gen.SelfSrcF_hasKids
import all Lanius.Faithful.Gen.SelfSrcF_methodDecl
import all Lanius.Faithful.Gen.SelfSrcF_moduleOr
import all Lanius.Faithful.Gen.SelfSrcF_textSelf
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

/-- `declareFuncs` of functions 800 to 899. -/
theorem dchunk8 : declsStep [(src_p_stmts_end), (src_p_params_none), (src_p_params_some), (src_p_params_more), (src_p_params_end), (src_p_params_after_comma_more), (src_p_params_after_comma_trailing), (src_p_args_none), (src_p_args_some), (src_p_args_more), (src_p_args_end), (src_p_args_after_comma_more), (src_p_args_after_comma_trailing), (src_p_struct_fields_none), (src_p_struct_fields_some), (src_p_struct_fields_more), (src_p_struct_fields_end), (src_p_struct_fields_after_comma_more), (src_p_struct_fields_after_comma_trailing), (src_p_struct_lit_fields_none), (src_p_struct_lit_fields_some), (src_p_struct_lit_fields_more), (src_p_struct_lit_fields_end), (src_p_struct_lit_fields_after_comma_more), (src_p_struct_lit_fields_after_comma_trailing), (src_p_enum_variants_none), (src_p_enum_variants_some), (src_p_enum_variants_more), (src_p_enum_variants_end), (src_p_enum_variants_after_comma_more), (src_p_enum_variants_after_comma_trailing), (src_p_enum_variant_fields_none), (src_p_enum_variant_fields_some), (src_p_enum_variant_fields_more), (src_p_enum_variant_fields_end), (src_p_enum_variant_fields_after_comma_more), (src_p_enum_variant_fields_after_comma_trailing), (src_p_match_arms_none), (src_p_match_arms_some), (src_p_match_arms_more), (src_p_match_arms_end), (src_p_match_arms_after_comma_more), (src_p_match_arms_after_comma_trailing), (src_p_patterns_none), (src_p_patterns_some), (src_p_patterns_more), (src_p_patterns_end), (src_p_patterns_after_comma_more), (src_p_patterns_after_comma_trailing), (src_p_enum_type_params_some), (src_p_enum_type_params_more), (src_p_enum_type_params_after_comma_more), (src_p_type_args_some), (src_p_type_args_more), (src_p_type_args_after_comma_more), (src_p_path_type_args_more), (src_p_path_type_args_after_comma_more), (src_p_impl_methods_some), (src_p_impl_methods_more), (src_p_type_param_bound_more), (src_p_where_predicates_more), (src_p_where_predicate_more_after_comma), (src_p_bound_type_args_more), (src_p_bound_type_args_after_comma_more), (src_p_array_some), (src_p_array_more), (src_p_array_end), (src_p_array_after_comma_more), (src_p_array_after_comma_trailing), (src_join_second 1067), (src_single_of_mini_selfhost_TypeDecl 642), (src_struct_decl_of 1068 1069), (src_enum_decl_of 96 258), (src_variants_of 103 258 589 590 873 1070 1071 1072), (src_cons_of_mini_selfhost_FnDecl 643), (src_param_spellings 103 258 1073), (src_leaf_token 255), (src_methods_of 103 571 584 877 1074), (src_with_impl_decl 1075), (src_single_of_mini_selfhost_ImportDecl 646), (src_single_of_mini_selfhost_AliasDecl 648), (src_if_unbounded), (src_unbounded 103 152 155 882 1076), (src_p_extern_abi), (src_same_text 76 884), (src_text_lanius_std 377 461), (src_host_id 884 1077 1078 1079 1080 1081 1082 1083 1084), (src_boxed_of_mini_selfhost_List_mini_selfhost_List_usize 50 761 1085), (src_cons_name_tail 1086), (src_same_spellings 526 884 889), (src_distinct 526 890 1087), (src_concat_of_mini_selfhost_List_usize 526 887 891), (src_fn_names_in 258 267 1088), (src_type_only_names_in 258 269 1089), (src_alias_names_in 258 617 1090), (src_const_names_in 258 645 1091), (src_enums_named_ok 269 896 1092), (src_spelled3 76 899), (src_spelled4 76 897), (src_spelled2 76 1093)]
    decls 36 60 35 59 = true := by decide +kernel

end Lanius.Faithful.SelfPure
