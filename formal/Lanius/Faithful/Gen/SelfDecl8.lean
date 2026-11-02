module

public import Lanius.Faithful.Gen.SelfPureTab
public import Lanius.Faithful.Gen.SelfSrc1
public import Lanius.Faithful.Gen.SelfSrc2
public import Lanius.Faithful.Gen.SelfSrc3
public import Lanius.Faithful.Gen.SelfSrc4
public import Lanius.Faithful.Gen.SelfSrc5
public import Lanius.Faithful.Gen.SelfSrc6
public import Lanius.Faithful.Gen.SelfSrc7
public import Lanius.Faithful.Gen.SelfSrcF_Inline_pArgsMore
public import Lanius.Faithful.Gen.SelfSrcF_Inline_pArrayAfterCommaTrailing
public import Lanius.Faithful.Gen.SelfSrcF_Inline_pArrayMore
public import Lanius.Faithful.Gen.SelfSrcF_Inline_pBoundTypeArgsAfterCommaMore
public import Lanius.Faithful.Gen.SelfSrcF_Inline_pEnumTypeParam
public import Lanius.Faithful.Gen.SelfSrcF_Inline_pExpr
public import Lanius.Faithful.Gen.SelfSrcF_Inline_pIdentPlain
public import Lanius.Faithful.Gen.SelfSrcF_Inline_pImplMethodsSome
public import Lanius.Faithful.Gen.SelfSrcF_Inline_pLeTail
public import Lanius.Faithful.Gen.SelfSrcF_Inline_pPathMore
public import Lanius.Faithful.Gen.SelfSrcF_Inline_pStructFieldsMore
public import Lanius.Faithful.Gen.SelfSrcF_Inline_pTypeArgsNone
public import Lanius.Faithful.Gen.SelfSrcF_assertClosed
public import Lanius.Faithful.Gen.SelfSrcF_collect
public import Lanius.Faithful.Gen.SelfSrcF_distinct
public import Lanius.Faithful.Gen.SelfSrcF_funcsOnto
public import Lanius.Faithful.Gen.SelfSrcF_hasKids
public import Lanius.Faithful.Gen.SelfSrcF_joinInsts
public import Lanius.Faithful.Gen.SelfSrcF_lowerTy
public import Lanius.Faithful.Gen.SelfSrcF_methodDecl
public import Lanius.Faithful.Gen.SelfSrcF_moduleOr
public import Lanius.Faithful.Gen.SelfSrcF_negWideI32
public import Lanius.Faithful.Gen.SelfSrcF_textSelf
public import Lanius.Faithful.Gen.SelfSrcF_wideLeftStmt
public import Lanius.Faithful.Gen.SelfSrcRest
import all Lanius.Faithful.Gen.SelfPureTab
import all Lanius.Faithful.Gen.SelfSrc1
import all Lanius.Faithful.Gen.SelfSrc2
import all Lanius.Faithful.Gen.SelfSrc3
import all Lanius.Faithful.Gen.SelfSrc4
import all Lanius.Faithful.Gen.SelfSrc5
import all Lanius.Faithful.Gen.SelfSrc6
import all Lanius.Faithful.Gen.SelfSrc7
import all Lanius.Faithful.Gen.SelfSrcF_Inline_pArgsMore
import all Lanius.Faithful.Gen.SelfSrcF_Inline_pArrayAfterCommaTrailing
import all Lanius.Faithful.Gen.SelfSrcF_Inline_pArrayMore
import all Lanius.Faithful.Gen.SelfSrcF_Inline_pBoundTypeArgsAfterCommaMore
import all Lanius.Faithful.Gen.SelfSrcF_Inline_pEnumTypeParam
import all Lanius.Faithful.Gen.SelfSrcF_Inline_pExpr
import all Lanius.Faithful.Gen.SelfSrcF_Inline_pIdentPlain
import all Lanius.Faithful.Gen.SelfSrcF_Inline_pImplMethodsSome
import all Lanius.Faithful.Gen.SelfSrcF_Inline_pLeTail
import all Lanius.Faithful.Gen.SelfSrcF_Inline_pPathMore
import all Lanius.Faithful.Gen.SelfSrcF_Inline_pStructFieldsMore
import all Lanius.Faithful.Gen.SelfSrcF_Inline_pTypeArgsNone
import all Lanius.Faithful.Gen.SelfSrcF_assertClosed
import all Lanius.Faithful.Gen.SelfSrcF_collect
import all Lanius.Faithful.Gen.SelfSrcF_distinct
import all Lanius.Faithful.Gen.SelfSrcF_funcsOnto
import all Lanius.Faithful.Gen.SelfSrcF_hasKids
import all Lanius.Faithful.Gen.SelfSrcF_joinInsts
import all Lanius.Faithful.Gen.SelfSrcF_lowerTy
import all Lanius.Faithful.Gen.SelfSrcF_methodDecl
import all Lanius.Faithful.Gen.SelfSrcF_moduleOr
import all Lanius.Faithful.Gen.SelfSrcF_negWideI32
import all Lanius.Faithful.Gen.SelfSrcF_textSelf
import all Lanius.Faithful.Gen.SelfSrcF_wideLeftStmt
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

/-- `declareFuncs` of functions 800 to 899. -/
theorem dchunk8 : declsStep [(src_p_struct_lit_fields_more), (src_p_struct_lit_fields_end), (src_p_struct_lit_fields_after_comma_more), (src_p_struct_lit_fields_after_comma_trailing), (src_p_enum_variants_none), (src_p_enum_variants_some), (src_p_enum_variants_more), (src_p_enum_variants_end), (src_p_enum_variants_after_comma_more), (src_p_enum_variants_after_comma_trailing), (src_p_enum_variant_fields_none), (src_p_enum_variant_fields_some), (src_p_enum_variant_fields_more), (src_p_enum_variant_fields_end), (src_p_enum_variant_fields_after_comma_more), (src_p_enum_variant_fields_after_comma_trailing), (src_p_match_arms_none), (src_p_match_arms_some), (src_p_match_arms_more), (src_p_match_arms_end), (src_p_match_arms_after_comma_more), (src_p_match_arms_after_comma_trailing), (src_p_patterns_none), (src_p_patterns_some), (src_p_patterns_more), (src_p_patterns_end), (src_p_patterns_after_comma_more), (src_p_patterns_after_comma_trailing), (src_p_enum_type_params_some), (src_p_enum_type_params_more), (src_p_enum_type_params_after_comma_more), (src_p_type_args_some), (src_p_type_args_more), (src_p_type_args_after_comma_more), (src_p_path_type_args_more), (src_p_path_type_args_after_comma_more), (src_p_impl_methods_some), (src_p_impl_methods_more), (src_p_type_param_bound_more), (src_p_where_predicates_more), (src_p_where_predicate_more_after_comma), (src_p_bound_type_args_more), (src_p_bound_type_args_after_comma_more), (src_p_array_some), (src_p_array_more), (src_p_array_end), (src_p_array_after_comma_more), (src_p_array_after_comma_trailing), (src_join_second 1047), (src_single_of_mini_selfhost_TypeDecl 622), (src_struct_decl_of 1048 1049), (src_enum_decl_of 97 249), (src_variants_of 104 249 569 570 852 1050 1051 1052), (src_cons_of_mini_selfhost_FnDecl 623), (src_param_spellings 104 249 1053), (src_leaf_token 246), (src_methods_of 104 551 564 856 1054), (src_with_impl_decl 1055), (src_single_of_mini_selfhost_ImportDecl 626), (src_single_of_mini_selfhost_AliasDecl 628), (src_if_unbounded), (src_unbounded 104 148 151 861 1056), (src_p_extern_abi), (src_same_text 76 863), (src_text_lanius_std 377 535), (src_host_id 863 1057 1058 1059 1060 1061 1062 1063 1064), (src_boxed_of_mini_selfhost_List_mini_selfhost_List_usize 50 740 1065), (src_cons_name_tail 1066), (src_same_spellings 506 863 868), (src_distinct 506 869 1067), (src_concat_of_mini_selfhost_List_usize 506 866 870), (src_fn_names_in 249 258 1068), (src_type_only_names_in 249 260 1069), (src_alias_names_in 249 597 1070), (src_const_names_in 249 625 1071), (src_enums_named_ok 260 875 1072), (src_spelled3 76 878), (src_spelled4 76 876), (src_spelled2 76 1073), (src_spelled5 76 877), (src_core_mem_typed_slice_from_storage_of_mini_selfhost_List_mini_selfhost_AliasDecl), (src_empty_of_mini_selfhost_SrcFunc), (src_cons_func 1074), (src_src_func), (src_close_params 884 902 1075 1076 1077), (src_close_ret 1077), (src_close_stmt 886 903 1077 1078 1079 1080 1081 1082 1083 1084 1085 1086 1087 1088 1089 1090 1091 1092 1093 1094 1095 1096 1097 1098 1099 1100 1101 1102 1103 1104), (src_empty_of_core_option_Option_mini_selfhost_SrcType), (src_cons_of_core_option_Option_mini_selfhost_SrcType 1105), (src_lower_named 56 1081 1106 1107), (src_wide_left_funcs 59 890 1108), (src_cons_of_mini_selfhost_SrcFunc 1109), (src_lit_stmt 81 205 892 1110 1111 1112 1113 1114 1115 1116 1117 1118 1119 1120 1121 1122), (src_param_locals 135 893 1123 1124), (src_ty_known 603 894 897 1125), (src_single_of_mini_selfhost_Ty 607), (src_core_mem_typed_slice_from_storage_of_mini_selfhost_List_mini_selfhost_Ty), (src_unbox_of_mini_selfhost_Ty 1126), (src_cons_inst 405), (src_named_insts 56 1106 1127)]
    decls 36 60 33 55 = true := by decide +kernel

end Lanius.Faithful.SelfPure
