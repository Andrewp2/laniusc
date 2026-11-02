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
public import Lanius.Faithful.Gen.SelfSrcC_BinOp_folds
public import Lanius.Faithful.Gen.SelfSrcC_DivOp_size
public import Lanius.Faithful.Gen.SelfSrcC_Expr_agrees
public import Lanius.Faithful.Gen.SelfSrcC_Inline_factOr
public import Lanius.Faithful.Gen.SelfSrcC_Lists_empty
public import Lanius.Faithful.Gen.SelfSrcC_Stmt_kills
public import Lanius.Faithful.Gen.SelfSrcC_Word_compute
public import Lanius.Faithful.Gen.SelfSrcC_Word_narrows
public import Lanius.Faithful.Gen.SelfSrcC_arities
public import Lanius.Faithful.Gen.SelfSrcC_binaryConstant
public import Lanius.Faithful.Gen.SelfSrcC_declareProgram
public import Lanius.Faithful.Gen.SelfSrcC_killShared
public import Lanius.Faithful.Gen.SelfSrcC_longer
public import Lanius.Faithful.Gen.SelfSrcC_optimizeLeft
public import Lanius.Faithful.Gen.SelfSrcF_Inline_findMethodAt
public import Lanius.Faithful.Gen.SelfSrcF_assertClosed
public import Lanius.Faithful.Gen.SelfSrcF_collect
public import Lanius.Faithful.Gen.SelfSrcF_distinct
public import Lanius.Faithful.Gen.SelfSrcF_effNamedTys
public import Lanius.Faithful.Gen.SelfSrcF_externBody
public import Lanius.Faithful.Gen.SelfSrcF_findConst
public import Lanius.Faithful.Gen.SelfSrcF_funcsOnto
public import Lanius.Faithful.Gen.SelfSrcF_ifNotWrites
public import Lanius.Faithful.Gen.SelfSrcF_joinInsts
public import Lanius.Faithful.Gen.SelfSrcF_lowerTy
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
import all Lanius.Faithful.Gen.SelfSrcC_BinOp_folds
import all Lanius.Faithful.Gen.SelfSrcC_DivOp_size
import all Lanius.Faithful.Gen.SelfSrcC_Expr_agrees
import all Lanius.Faithful.Gen.SelfSrcC_Inline_factOr
import all Lanius.Faithful.Gen.SelfSrcC_Lists_empty
import all Lanius.Faithful.Gen.SelfSrcC_Stmt_kills
import all Lanius.Faithful.Gen.SelfSrcC_Word_compute
import all Lanius.Faithful.Gen.SelfSrcC_Word_narrows
import all Lanius.Faithful.Gen.SelfSrcC_arities
import all Lanius.Faithful.Gen.SelfSrcC_binaryConstant
import all Lanius.Faithful.Gen.SelfSrcC_declareProgram
import all Lanius.Faithful.Gen.SelfSrcC_killShared
import all Lanius.Faithful.Gen.SelfSrcC_longer
import all Lanius.Faithful.Gen.SelfSrcC_optimizeLeft
import all Lanius.Faithful.Gen.SelfSrcF_Inline_findMethodAt
import all Lanius.Faithful.Gen.SelfSrcF_assertClosed
import all Lanius.Faithful.Gen.SelfSrcF_collect
import all Lanius.Faithful.Gen.SelfSrcF_distinct
import all Lanius.Faithful.Gen.SelfSrcF_effNamedTys
import all Lanius.Faithful.Gen.SelfSrcF_externBody
import all Lanius.Faithful.Gen.SelfSrcF_findConst
import all Lanius.Faithful.Gen.SelfSrcF_funcsOnto
import all Lanius.Faithful.Gen.SelfSrcF_ifNotWrites
import all Lanius.Faithful.Gen.SelfSrcF_joinInsts
import all Lanius.Faithful.Gen.SelfSrcF_lowerTy
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
import all Lanius.Mini.Compiler.P.SrcType_size
import all Lanius.Mini.Compiler.P.UintTy_half
import all Lanius.Mini.Compiler.P.UintTy_isWide
import all Lanius.Mini.Compiler.P.arithShiftRight
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
def dpart9 : List SrcFunc := [(src_boxed_of_mini_selfhost_List_mini_selfhost_List_usize 50 774 1106), (src_cons_name_tail 1107), (src_same_spellings 534 897 902), (src_distinct 534 903 1108), (src_concat_of_mini_selfhost_List_usize 534 900 904), (src_fn_names_in 259 268 1109), (src_type_only_names_in 259 270 1110), (src_alias_names_in 259 623 1111), (src_const_names_in 259 656 1112), (src_enums_named_ok 270 909 1113), (src_spelled3 76 912), (src_spelled4 76 910), (src_spelled2 76 1114), (src_spelled5 76 911), (src_core_mem_typed_slice_from_storage_of_mini_selfhost_List_mini_selfhost_AliasDecl), (src_empty_of_mini_selfhost_SrcFunc), (src_cons_func 1115), (src_src_func), (src_close_params 918 942 1116 1117 1118), (src_close_ret 1118), (src_close_stmt 920 943 1118 1119 1120 1121 1122 1123 1124 1125 1126 1127 1128 1129 1130 1131 1132 1133 1134 1135 1136 1137 1138 1139 1140 1141 1142 1143 1144 1145), (src_empty_of_core_option_Option_mini_selfhost_SrcType), (src_cons_of_core_option_Option_mini_selfhost_SrcType 1146), (src_lower_named 56 1122 1147 1148), (src_wide_left_funcs 59 924 1149), (src_cons_of_mini_selfhost_SrcFunc 1150), (src_lit_stmt 81 213 926 1151 1152 1153 1154 1155 1156 1157 1158 1159 1160 1161 1162 1163), (src_param_locals 173 927 1164 1165), (src_is_none_weight), (src_unbox_of_mini_selfhost_List_core_option_Option_usize 1166), (src_weigh_next 630 1167), (src_weigh_round 639 932 1168), (src_empty_of_core_option_Option_usize), (src_cons_of_core_option_Option_usize 1169), (src_ty_known 634 934 937 1170), (src_single_of_mini_selfhost_Ty 638), (src_core_mem_typed_slice_from_storage_of_mini_selfhost_List_mini_selfhost_Ty), (src_unbox_of_mini_selfhost_Ty 1171), (src_cons_inst 424), (src_named_insts 56 1147 1172), (src_core_mem_size_of_of_mini_selfhost_List_mini_selfhost_Ty), (src_core_mem_typed_slice_from_storage_of_mini_selfhost_List_mini_selfhost_Inst), (src_unbox_of_mini_selfhost_List_mini_selfhost_MParam 1173), (src_unbox_of_mini_selfhost_MStmt 1174), (src_eff_named_tys 425 637 640 935 944 1175 1176 1177), (src_core_mem_typed_slice_from_storage_of_mini_selfhost_List_mini_selfhost_MFunc), (src_add_inst 947 948 1170), (src_single_of_mini_selfhost_Inst 652), (src_concat_of_mini_selfhost_Inst 639 652 948), (src_eff_calls 266 424 948 949 1176 1177 1178), (src_boxed_of_mini_selfhost_List_mini_selfhost_MFunc 50 945 1179), (src_extern_func 154 155 359 596 899 904 1180 1181 1182 1183 1184 1185 1186), (src_diverges 75 359 904 1182 1187), (src_diverge_func 955 1188 1189 1190 1191), (src_read_fn 154 155 359 596 904 1180 1181 1182 1184 1185 1186 1192 1193 1194 1195 1196), (src_init_tys 425 634 637 955), (src_single_of_mini_selfhost_MParam 1197), (src_length_of_mini_selfhost_FnDecl 75 268 957), (src_struct_field_tys 634 1198), (src_get_of_mini_selfhost_Ty 56 634 959), (src_core_mem_size_of_of_mini_selfhost_List_mini_selfhost_Inst), (src_core_mem_size_of_of_mini_selfhost_List_mini_selfhost_TypeDecl), (src_core_mem_size_of_of_mini_selfhost_List_mini_selfhost_FnDecl), (src_core_mem_size_of_of_mini_selfhost_List_mini_selfhost_ConstDecl), (src_core_mem_typed_slice_from_storage_of_mini_selfhost_List_mini_selfhost_ConstDecl), (src_core_mem_size_of_of_mini_selfhost_List_mini_selfhost_ImportDecl), (src_core_mem_typed_slice_from_storage_of_mini_selfhost_List_mini_selfhost_ImportDecl), (src_core_mem_size_of_of_mini_selfhost_List_mini_selfhost_AliasDecl), (src_core_mem_size_of_of_mini_selfhost_List_mini_selfhost_ImplDecl), (src_core_mem_typed_slice_from_storage_of_mini_selfhost_List_mini_selfhost_ImplDecl), (src_low_bits), (src_optimize_both 328 1199 1200), (src_optimize_left 328 1201 1202 1203 1204 1205), (src_optimize_right 328 1201 1203 1204 1205), (src_Word_test 1206 1207), (src_fact_or 666), (src_unbox_of_mini_selfhost_List_mini_selfhost_Fact 1208), (src_assigned 441 978 1209 1210 1211 1212), (src_kill_shared 1213 1214), (src_Stmt_kills 298 979 1210 1215 1216 1217), (src_Expr_agrees 468 662 680 1218 1219 1220 1221 1222 1223), (src_negate_constant 970), (src_binary_constant 1224 1225), (src_compare_constant 478 974), (src_constant_is), (src_args_agree 469 980 985), (src_MemWidth_bytes), (src_Word_number), (src_DivOp_number), (src_Syscall_number), (src_get_of_mini_selfhost_Arity 56 990 1226), (src_core_mem_size_of_of_mini_selfhost_List_mini_selfhost_Instr), (src_core_mem_typed_slice_from_storage_of_mini_selfhost_List_mini_selfhost_Instr), (src_BinOp_size), (src_Word_prefix), (src_MemWidth_prefix), (src_DivOp_size 75 994), (src_FOp_size 75 105 994 1227), (src_core_mem_size_of_of_mini_selfhost_List_u8), (src_le64 718 719)]

def dents9 : List SigEntry := [some ([ty27], ty26), some ([ty20, ty149], ty149), some ([ty27, ty27], .bool), some ([ty27], .bool), some ([ty27, ty27], ty27), some ([ty112, ty27], ty27), some ([ty109, ty27], ty27), some ([ty121, ty27], ty27), some ([ty115, ty27], ty27), some ([ty109, ty27, ty27], .bool), some ([ty20, (.uint .usize), (.uint .usize), (.uint .usize)], .bool), some ([ty20, (.uint .usize), (.uint .usize), (.uint .usize), (.uint .usize)], .bool), some ([ty20, (.uint .usize), (.uint .usize)], .bool), some ([ty20, (.uint .usize), (.uint .usize), (.uint .usize), (.uint .usize), (.uint .usize)], .bool), none, some ([], ty33), some ([ty261, ty227], ty227), some ([ty262, ty177, ty263], ty261), some ([(.uint .usize), ty226, ty186], ty262), some ([(.uint .usize), ty226, ty187], ty177), some ([(.uint .usize), ty226, ty192], ty263), some ([], ty225), some ([ty177, ty225], ty225), some ([(.uint .usize), ty127, ty156, (.uint .usize), ty153], ty177), some ([ty33], .bool), some ([ty31, ty33], ty33), some ([ty33, ty9, ty266, ty30], ty30), some ([ty12], ty266), some ([ty238], .bool), some ([ty242], ty243), some ([(.uint .usize), (.uint .usize), ty127, ty156, ty243, ty243], ty243), some ([(.uint .usize), ty127, ty156, ty243, ty156, ty243], ty243), some ([], ty243), some ([ty238, ty243], ty243), some ([ty156, ty152], .bool), some ([ty152], ty153), none, some ([ty150], ty152), some ([ty154, ty223], ty223), some ([(.uint .usize), ty127, (.uint .usize), ty153], ty223), none, none, some ([ty185], ty186), some ([ty188], ty192), some ([ty191], ty153), none, some ([ty156, ty154], ty156), some ([ty154], ty156), some ([ty156, ty156], ty156), some ([ty191], ty156), some ([ty195], ty194), some ([(.uint .usize), ty127, ty110, ty153], ty228), some ([ty110, ty154], .bool), some ([ty228, ty154], ty228), some ([(.uint .usize), ty127, ty110, ty153], ty228), some ([ty153], ty153), some ([ty184], ty186), some ([ty112], (.uint .usize)), some ([(.uint .usize), ty127, ty152], ty248), some ([ty153, (.uint .usize)], ty247), none, none, none, none, none, none, none, none, none, none, some ([(.uint .uint64)], (.uint .uint64)), some ([ty51, ty52, (.uint .uint64), (.uint .uint64), ty90, ty90], ty90), some ([ty51, ty52, (.uint .uint64), ty90, ty90], ty90), some ([ty51, ty52, ty90, ty90, (.uint .uint64)], ty90), some ([ty51, ty53, (.uint .uint64), (.uint .uint64)], .bool), some ([ty201, (.uint .usize), ty203], ty90), some ([ty202], ty203), some ([ty203, (.uint .usize), ty90], ty203), some ([ty203, (.uint .usize)], ty203), some ([ty94, (.uint .usize)], .bool), some ([ty90, ty90], .bool), some ([ty230], ty230), some ([ty51, ty52, ty230, ty230], ty230), some ([ty51, ty53, ty230, ty230], ty230), some ([ty230, (.uint .uint64)], .bool), some ([ty93, ty93], .bool), some ([ty54], (.uint .usize)), some ([ty51], (.uint .usize)), some ([ty55], (.uint .usize)), some ([ty59], (.uint .usize)), some ([ty161, (.uint .usize)], ty252), none, none, some ([ty52], (.uint .usize)), some ([ty51], (.uint .usize)), some ([ty54], (.uint .usize)), some ([ty55, ty51], (.uint .usize)), some ([ty58], (.uint .usize)), none, some ([(.uint .uint64)], ty67)]

/-- `declareFuncs` of functions 900 to 999. -/
theorem dchunk9 : declsStep dpart9 decls 35 60 32 55 = true := by decide +kernel

theorem dfit9 : entriesFit dpart9 dents9 = true := by decide +kernel

end Lanius.Faithful.SelfPure
