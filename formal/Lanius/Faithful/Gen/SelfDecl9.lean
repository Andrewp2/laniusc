module

public import Lanius.Faithful.Gen.SelfPureTab
public import Lanius.Faithful.Gen.SelfSrc0
public import Lanius.Faithful.Gen.SelfSrc1
public import Lanius.Faithful.Gen.SelfSrc2
public import Lanius.Faithful.Gen.SelfSrc3
public import Lanius.Faithful.Gen.SelfSrc4
public import Lanius.Faithful.Gen.SelfSrc5
public import Lanius.Faithful.Gen.SelfSrc6
public import Lanius.Faithful.Gen.SelfSrc7
public import Lanius.Faithful.Gen.SelfSrcF_Inline_findMethodAt
public import Lanius.Faithful.Gen.SelfSrcF_Inline_pArgsMore
public import Lanius.Faithful.Gen.SelfSrcF_Inline_pArrayAfterCommaTrailing
public import Lanius.Faithful.Gen.SelfSrcF_Inline_pArrayMore
public import Lanius.Faithful.Gen.SelfSrcF_Inline_pBoundTypeArgsAfterCommaMore
public import Lanius.Faithful.Gen.SelfSrcF_Inline_pExpr
public import Lanius.Faithful.Gen.SelfSrcF_Inline_pIdentPlain
public import Lanius.Faithful.Gen.SelfSrcF_Inline_pImplMethodsSome
public import Lanius.Faithful.Gen.SelfSrcF_assertClosed
public import Lanius.Faithful.Gen.SelfSrcF_collect
public import Lanius.Faithful.Gen.SelfSrcF_distinct
public import Lanius.Faithful.Gen.SelfSrcF_effNamedTys
public import Lanius.Faithful.Gen.SelfSrcF_externBody
public import Lanius.Faithful.Gen.SelfSrcF_findConst
public import Lanius.Faithful.Gen.SelfSrcF_funcsBytes
public import Lanius.Faithful.Gen.SelfSrcF_funcsOnto
public import Lanius.Faithful.Gen.SelfSrcF_hasKids
public import Lanius.Faithful.Gen.SelfSrcF_ifNotWrites
public import Lanius.Faithful.Gen.SelfSrcF_joinInsts
public import Lanius.Faithful.Gen.SelfSrcF_lowerTy
public import Lanius.Faithful.Gen.SelfSrcF_methodDecl
public import Lanius.Faithful.Gen.SelfSrcF_moduleOr
public import Lanius.Faithful.Gen.SelfSrcF_negWideI32
public import Lanius.Faithful.Gen.SelfSrcF_projectionRet
public import Lanius.Faithful.Gen.SelfSrcF_readInst
public import Lanius.Faithful.Gen.SelfSrcF_textSelf
public import Lanius.Faithful.Gen.SelfSrcF_wideLeftStmt
public import Lanius.Faithful.Gen.SelfSrcF_wideOf
public import Lanius.Faithful.Gen.SelfSrcRest
import all Lanius.Faithful.Gen.SelfPureTab
import all Lanius.Faithful.Gen.SelfSrc0
import all Lanius.Faithful.Gen.SelfSrc1
import all Lanius.Faithful.Gen.SelfSrc2
import all Lanius.Faithful.Gen.SelfSrc3
import all Lanius.Faithful.Gen.SelfSrc4
import all Lanius.Faithful.Gen.SelfSrc5
import all Lanius.Faithful.Gen.SelfSrc6
import all Lanius.Faithful.Gen.SelfSrc7
import all Lanius.Faithful.Gen.SelfSrcF_Inline_findMethodAt
import all Lanius.Faithful.Gen.SelfSrcF_Inline_pArgsMore
import all Lanius.Faithful.Gen.SelfSrcF_Inline_pArrayAfterCommaTrailing
import all Lanius.Faithful.Gen.SelfSrcF_Inline_pArrayMore
import all Lanius.Faithful.Gen.SelfSrcF_Inline_pBoundTypeArgsAfterCommaMore
import all Lanius.Faithful.Gen.SelfSrcF_Inline_pExpr
import all Lanius.Faithful.Gen.SelfSrcF_Inline_pIdentPlain
import all Lanius.Faithful.Gen.SelfSrcF_Inline_pImplMethodsSome
import all Lanius.Faithful.Gen.SelfSrcF_assertClosed
import all Lanius.Faithful.Gen.SelfSrcF_collect
import all Lanius.Faithful.Gen.SelfSrcF_distinct
import all Lanius.Faithful.Gen.SelfSrcF_effNamedTys
import all Lanius.Faithful.Gen.SelfSrcF_externBody
import all Lanius.Faithful.Gen.SelfSrcF_findConst
import all Lanius.Faithful.Gen.SelfSrcF_funcsBytes
import all Lanius.Faithful.Gen.SelfSrcF_funcsOnto
import all Lanius.Faithful.Gen.SelfSrcF_hasKids
import all Lanius.Faithful.Gen.SelfSrcF_ifNotWrites
import all Lanius.Faithful.Gen.SelfSrcF_joinInsts
import all Lanius.Faithful.Gen.SelfSrcF_lowerTy
import all Lanius.Faithful.Gen.SelfSrcF_methodDecl
import all Lanius.Faithful.Gen.SelfSrcF_moduleOr
import all Lanius.Faithful.Gen.SelfSrcF_negWideI32
import all Lanius.Faithful.Gen.SelfSrcF_projectionRet
import all Lanius.Faithful.Gen.SelfSrcF_readInst
import all Lanius.Faithful.Gen.SelfSrcF_textSelf
import all Lanius.Faithful.Gen.SelfSrcF_wideLeftStmt
import all Lanius.Faithful.Gen.SelfSrcF_wideOf
import all Lanius.Faithful.Gen.SelfSrcRest
import all Lanius.Faithful.Gen.SelfTypes
import all Lanius.Mini.Compiler.P.DivOp_size
import all Lanius.Mini.Compiler.P.Lists_empty
import all Lanius.Mini.Compiler.P.SrcExpr_guard
import all Lanius.Mini.Compiler.P.SrcType_same
import all Lanius.Mini.Compiler.P.UintTy_half
import all Lanius.Mini.Compiler.P.UintTy_isWide
import all Lanius.Mini.Compiler.P.arithShiftRight
import all Lanius.Mini.Compiler.P.arrayCallSig
import all Lanius.Mini.Compiler.P.codeSize
import all Lanius.Mini.Compiler.P.declareFuncs
import all Lanius.Mini.Compiler.P.declareProgram
import all Lanius.Mini.Compiler.P.enumVariants
import all Lanius.Mini.Compiler.P.equality
import all Lanius.Mini.Compiler.P.floatApply
import all Lanius.Mini.Compiler.P.loadAtBytes
import all Lanius.Mini.Compiler.P.lowerBody
import all Lanius.Mini.Compiler.P.matchVariants
import all Lanius.Mini.Compiler.P.render
import all Lanius.Mini.Compiler.P.structFields
import all Lanius.Mini.Compiler.P.wordElement
import all Lanius.Mini.Compiler.P.wordWidth
import all Lanius.Mini.Compiler.Types

@[expose] public section

/-! Generated by formal/tools/faithful_pure.py. Do not edit. -/

namespace Lanius.Faithful.SelfPure

open Lanius.Mini
open Lanius.Faithful
open Lanius.Faithful.Self

/-- Functions 900 to 999, and their signature entries. -/
def dpart9 : List SrcFunc := [(src_p_impl_methods_some), (src_p_impl_methods_more), (src_p_type_param_bound_more), (src_p_where_predicates_more), (src_p_where_predicate_more_after_comma), (src_p_bound_type_args_more), (src_p_bound_type_args_after_comma_more), (src_p_array_some), (src_p_array_more), (src_p_array_end), (src_p_array_after_comma_more), (src_p_array_after_comma_trailing), (src_join_second 1110), (src_single_of_mini_selfhost_TypeDecl 677), (src_struct_decl_of 1111 1112), (src_enum_decl_of 96 262), (src_variants_of 103 262 619 620 916 1113 1114 1115), (src_cons_of_mini_selfhost_FnDecl 678), (src_param_spellings 103 262 1116), (src_leaf_token 259), (src_methods_of 103 601 614 920 1117), (src_with_impl_decl 1118), (src_single_of_mini_selfhost_ImportDecl 681), (src_single_of_mini_selfhost_AliasDecl 683), (src_if_unbounded), (src_unbounded 103 152 155 925 1119), (src_p_extern_abi), (src_same_text 76 927), (src_text_lanius_std 370 397), (src_host_id 927 1120 1121 1122 1123 1124 1125 1126 1127 1128 1129), (src_boxed_of_mini_selfhost_List_mini_selfhost_List_usize 50 800 1130), (src_cons_name_tail 1131), (src_same_spellings 551 927 932), (src_distinct 551 933 1132), (src_concat_of_mini_selfhost_List_usize 551 930 934), (src_fn_names_in 262 271 1133), (src_type_only_names_in 262 273 1134), (src_alias_names_in 262 647 1135), (src_const_names_in 262 680 1136), (src_enums_named_ok 273 939 1137), (src_spelled3 76 942), (src_spelled4 76 940), (src_spelled2 76 1138), (src_spelled5 76 941), (src_core_mem_typed_slice_from_storage_of_mini_selfhost_List_mini_selfhost_AliasDecl), (src_empty_of_mini_selfhost_SrcFunc), (src_cons_func 1139), (src_src_func), (src_close_params 948 973 1140 1141 1142), (src_close_ret 1142), (src_close_stmt 950 974 1142 1143 1144 1145 1146 1147 1148 1149 1150 1151 1152 1153 1154 1155 1156 1157 1158 1159 1160 1161 1162 1163 1164 1165 1166 1167 1168 1169 1170 1171), (src_empty_of_core_option_Option_mini_selfhost_SrcType), (src_cons_of_core_option_Option_mini_selfhost_SrcType 1172), (src_lower_named 56 1146 1173 1174), (src_wide_left_funcs 59 954 1175), (src_placed_program 110 1176 1177), (src_cons_of_mini_selfhost_SrcFunc 1178), (src_lit_stmt 81 214 957 1179 1180 1181 1182 1183 1184 1185 1186 1187 1188 1189 1190 1191 1192), (src_param_locals 173 958 1193 1194), (src_is_none_weight), (src_unbox_of_mini_selfhost_List_core_option_Option_usize 1195), (src_weigh_next 654 1196), (src_weigh_round 663 963 1197), (src_empty_of_core_option_Option_usize), (src_cons_of_core_option_Option_usize 1198), (src_ty_known 658 965 968 1199), (src_single_of_mini_selfhost_Ty 662), (src_core_mem_typed_slice_from_storage_of_mini_selfhost_List_mini_selfhost_Ty), (src_unbox_of_mini_selfhost_Ty 1200), (src_cons_inst 441), (src_named_insts 56 1173 1201), (src_core_mem_size_of_of_mini_selfhost_List_mini_selfhost_Ty), (src_core_mem_typed_slice_from_storage_of_mini_selfhost_List_mini_selfhost_Inst), (src_unbox_of_mini_selfhost_List_mini_selfhost_MParam 1202), (src_unbox_of_mini_selfhost_MStmt 1203), (src_boxed_of_mini_selfhost_Ty 50 1200 1204), (src_eff_named_tys 442 661 664 966 976 1205 1206 1207), (src_core_mem_typed_slice_from_storage_of_mini_selfhost_List_mini_selfhost_MFunc), (src_add_inst 979 980 1199), (src_single_of_mini_selfhost_Inst 676), (src_concat_of_mini_selfhost_Inst 663 676 980), (src_eff_calls 269 441 980 981 1206 1207 1208), (src_boxed_of_mini_selfhost_List_mini_selfhost_MFunc 50 977 1209), (src_extern_func 154 155 362 620 929 934 1210 1211 1212 1213 1214 1215 1216), (src_diverges 75 362 934 1212 1217), (src_diverge_func 987 1218 1219 1220 1221), (src_read_fn 154 155 362 620 934 1210 1211 1212 1214 1215 1216 1222 1223 1224 1225 1226), (src_init_tys 442 658 661 987), (src_single_of_mini_selfhost_MParam 1227), (src_length_of_mini_selfhost_FnDecl 75 271 989), (src_struct_field_tys 658 1228), (src_get_of_mini_selfhost_Ty 56 658 991), (src_core_mem_size_of_of_mini_selfhost_List_mini_selfhost_Inst), (src_core_mem_size_of_of_mini_selfhost_List_mini_selfhost_TypeDecl), (src_core_mem_size_of_of_mini_selfhost_List_mini_selfhost_FnDecl), (src_core_mem_size_of_of_mini_selfhost_List_mini_selfhost_ConstDecl), (src_core_mem_typed_slice_from_storage_of_mini_selfhost_List_mini_selfhost_ConstDecl), (src_core_mem_size_of_of_mini_selfhost_List_mini_selfhost_ImportDecl), (src_core_mem_typed_slice_from_storage_of_mini_selfhost_List_mini_selfhost_ImportDecl), (src_core_mem_size_of_of_mini_selfhost_List_mini_selfhost_AliasDecl)]

def dents9 : List SigEntry := [some ([], (.uint .usize)), some ([], (.uint .usize)), some ([], (.uint .usize)), some ([], (.uint .usize)), some ([], (.uint .usize)), some ([], (.uint .usize)), some ([], (.uint .usize)), some ([], (.uint .usize)), some ([], (.uint .usize)), some ([], (.uint .usize)), some ([], (.uint .usize)), some ([], (.uint .usize)), some ([ty85, ty86], ty86), some ([ty107], ty109), some ([ty27, ty20, ty149, ty86], ty243), some ([ty27, ty20, ty149, ty264], ty243), some ([(.uint .usize), ty85], ty264), some ([ty110, ty112], ty112), some ([ty85], ty149), some ([ty84], ty44), some ([(.uint .usize), ty27, ty27, ty84, ty84, ty85], ty224), some ([ty122, ty127], ty127), some ([ty116], ty118), some ([ty119], ty121), some ([.bool, ty149], ty149), some ([ty85], .bool), some ([], (.uint .usize)), some ([ty20, ty20], .bool), some ([], ty20), some ([ty20], (.uint .usize)), some ([ty27], ty26), some ([ty20, ty149], ty149), some ([ty27, ty27], .bool), some ([ty27], .bool), some ([ty27, ty27], ty27), some ([ty112, ty27], ty27), some ([ty109, ty27], ty27), some ([ty121, ty27], ty27), some ([ty115, ty27], ty27), some ([ty109, ty27, ty27], .bool), some ([ty20, (.uint .usize), (.uint .usize), (.uint .usize)], .bool), some ([ty20, (.uint .usize), (.uint .usize), (.uint .usize), (.uint .usize)], .bool), some ([ty20, (.uint .usize), (.uint .usize)], .bool), some ([ty20, (.uint .usize), (.uint .usize), (.uint .usize), (.uint .usize), (.uint .usize)], .bool), none, some ([], ty33), some ([ty265, ty230], ty230), some ([ty266, ty178, ty267], ty265), some ([(.uint .usize), ty229, ty187], ty266), some ([(.uint .usize), ty229, ty188], ty178), some ([(.uint .usize), ty229, ty193], ty267), some ([], ty228), some ([ty178, ty228], ty228), some ([(.uint .usize), ty127, ty156, (.uint .usize), ty153], ty178), some ([ty33], .bool), some ([ty33], ty36), some ([ty31, ty33], ty33), some ([ty33, ty9, ty270, ty30], ty30), some ([ty12], ty270), some ([ty163], .bool), some ([ty245], ty246), some ([(.uint .usize), (.uint .usize), ty127, ty156, ty246, ty246], ty246), some ([(.uint .usize), ty127, ty156, ty246, ty156, ty246], ty246), some ([], ty246), some ([ty163, ty246], ty246), some ([ty156, ty152], .bool), some ([ty152], ty153), none, some ([ty150], ty152), some ([ty154, ty226], ty226), some ([(.uint .usize), ty127, (.uint .usize), ty153], ty226), none, none, some ([ty186], ty187), some ([ty189], ty193), some ([ty152], ty150), some ([ty192], ty153), none, some ([ty156, ty154], ty156), some ([ty154], ty156), some ([ty156, ty156], ty156), some ([ty192], ty156), some ([ty196], ty195), some ([(.uint .usize), ty127, ty110, ty153], ty231), some ([ty110, ty154], .bool), some ([ty231, ty154], ty231), some ([(.uint .usize), ty127, ty110, ty153], ty231), some ([ty153], ty153), some ([ty185], ty187), some ([ty112], (.uint .usize)), some ([(.uint .usize), ty127, ty152], ty251), some ([ty153, (.uint .usize)], ty250), none, none, none, none, none, none, none, none]

/-- `declareFuncs` of functions 900 to 999. -/
theorem dchunk9 : declsStep dpart9 decls 39 65 35 59 = true := by decide +kernel

theorem dfit9 : entriesFit dpart9 dents9 = true := by decide +kernel

end Lanius.Faithful.SelfPure
