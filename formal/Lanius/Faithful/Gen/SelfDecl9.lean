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
public import Lanius.Faithful.Gen.SelfSrcC_FArith_opcode
public import Lanius.Faithful.Gen.SelfSrcC_Inline_factOr
public import Lanius.Faithful.Gen.SelfSrcC_Lists_empty
public import Lanius.Faithful.Gen.SelfSrcC_Stmt_kills
public import Lanius.Faithful.Gen.SelfSrcC_Word_compute
public import Lanius.Faithful.Gen.SelfSrcC_Word_narrows
public import Lanius.Faithful.Gen.SelfSrcC_arities
public import Lanius.Faithful.Gen.SelfSrcC_binaryConstant
public import Lanius.Faithful.Gen.SelfSrcC_declareProgram
public import Lanius.Faithful.Gen.SelfSrcC_killShared
public import Lanius.Faithful.Gen.SelfSrcC_loadAtBytes
public import Lanius.Faithful.Gen.SelfSrcC_longer
public import Lanius.Faithful.Gen.SelfSrcC_optimizeLeft
public import Lanius.Faithful.Gen.SelfSrcF_assertClosed
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
import all Lanius.Faithful.Gen.SelfSrcC_FArith_opcode
import all Lanius.Faithful.Gen.SelfSrcC_Inline_factOr
import all Lanius.Faithful.Gen.SelfSrcC_Lists_empty
import all Lanius.Faithful.Gen.SelfSrcC_Stmt_kills
import all Lanius.Faithful.Gen.SelfSrcC_Word_compute
import all Lanius.Faithful.Gen.SelfSrcC_Word_narrows
import all Lanius.Faithful.Gen.SelfSrcC_arities
import all Lanius.Faithful.Gen.SelfSrcC_binaryConstant
import all Lanius.Faithful.Gen.SelfSrcC_declareProgram
import all Lanius.Faithful.Gen.SelfSrcC_killShared
import all Lanius.Faithful.Gen.SelfSrcC_loadAtBytes
import all Lanius.Faithful.Gen.SelfSrcC_longer
import all Lanius.Faithful.Gen.SelfSrcC_optimizeLeft
import all Lanius.Faithful.Gen.SelfSrcF_assertClosed
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
def dpart9 : List SrcFunc := [(src_spelled5 76 898), (src_core_mem_typed_slice_from_storage_of_mini_selfhost_List_mini_selfhost_AliasDecl), (src_empty_of_mini_selfhost_SrcFunc), (src_cons_func 1094), (src_src_func), (src_close_params 905 923 1095 1096 1097), (src_close_ret 1097), (src_close_stmt 907 924 1097 1098 1099 1100 1101 1102 1103 1104 1105 1106 1107 1108 1109 1110 1111 1112 1113 1114 1115 1116 1117 1118 1119 1120 1121 1122 1123 1124), (src_empty_of_core_option_Option_mini_selfhost_SrcType), (src_cons_of_core_option_Option_mini_selfhost_SrcType 1125), (src_lower_named 56 1101 1126 1127), (src_wide_left_funcs 59 911 1128), (src_cons_of_mini_selfhost_SrcFunc 1129), (src_lit_stmt 81 213 913 1130 1131 1132 1133 1134 1135 1136 1137 1138 1139 1140 1141 1142), (src_param_locals 173 914 1143 1144), (src_ty_known 623 915 918 1145), (src_single_of_mini_selfhost_Ty 627), (src_core_mem_typed_slice_from_storage_of_mini_selfhost_List_mini_selfhost_Ty), (src_unbox_of_mini_selfhost_Ty 1146), (src_cons_inst 420), (src_named_insts 56 1126 1147), (src_core_mem_size_of_of_mini_selfhost_List_mini_selfhost_Ty), (src_core_mem_typed_slice_from_storage_of_mini_selfhost_List_mini_selfhost_Inst), (src_unbox_of_mini_selfhost_List_mini_selfhost_MParam 1148), (src_unbox_of_mini_selfhost_MStmt 1149), (src_eff_named_tys 421 626 629 916 925 1150 1151 1152), (src_core_mem_typed_slice_from_storage_of_mini_selfhost_List_mini_selfhost_MFunc), (src_add_inst 928 929 1145), (src_single_of_mini_selfhost_Inst 641), (src_concat_of_mini_selfhost_Inst 628 641 929), (src_eff_calls 265 420 929 930 1151 1152 1153), (src_boxed_of_mini_selfhost_List_mini_selfhost_MFunc 50 926 1154), (src_extern_func 154 155 355 590 886 891 1155 1156 1157 1158 1159 1160 1161), (src_diverges 75 355 891 1157 1162), (src_diverge_func 936 1163 1164 1165 1166), (src_read_fn 154 155 355 590 891 1155 1156 1157 1159 1160 1161 1167 1168 1169 1170 1171), (src_init_tys 421 623 626 936), (src_single_of_mini_selfhost_MParam 1172), (src_length_of_mini_selfhost_FnDecl 75 267 938), (src_struct_field_tys 623 1173), (src_get_of_mini_selfhost_Ty 56 623 940), (src_core_mem_size_of_of_mini_selfhost_List_mini_selfhost_Inst), (src_core_mem_size_of_of_mini_selfhost_List_mini_selfhost_TypeDecl), (src_core_mem_size_of_of_mini_selfhost_List_mini_selfhost_FnDecl), (src_core_mem_size_of_of_mini_selfhost_List_mini_selfhost_ConstDecl), (src_core_mem_typed_slice_from_storage_of_mini_selfhost_List_mini_selfhost_ConstDecl), (src_core_mem_size_of_of_mini_selfhost_List_mini_selfhost_ImportDecl), (src_core_mem_typed_slice_from_storage_of_mini_selfhost_List_mini_selfhost_ImportDecl), (src_core_mem_size_of_of_mini_selfhost_List_mini_selfhost_AliasDecl), (src_core_mem_size_of_of_mini_selfhost_List_mini_selfhost_ImplDecl), (src_core_mem_typed_slice_from_storage_of_mini_selfhost_List_mini_selfhost_ImplDecl), (src_low_bits), (src_optimize_both 327 1174 1175), (src_optimize_left 327 1176 1177 1178 1179 1180), (src_optimize_right 327 1176 1178 1179 1180), (src_Word_test 1181 1182), (src_fact_or 655), (src_unbox_of_mini_selfhost_List_mini_selfhost_Fact 1183), (src_assigned 437 959 1184 1185 1186 1187), (src_kill_shared 1188 1189), (src_Stmt_kills 297 960 1185 1190 1191 1192), (src_Expr_agrees 464 651 669 1193 1194 1195 1196 1197 1198), (src_negate_constant 951), (src_binary_constant 1199 1200), (src_compare_constant 474 955), (src_constant_is), (src_args_agree 465 961 966), (src_MemWidth_bytes), (src_Word_number), (src_DivOp_number), (src_Syscall_number), (src_get_of_mini_selfhost_Arity 56 971 1201), (src_core_mem_size_of_of_mini_selfhost_List_mini_selfhost_Instr), (src_core_mem_typed_slice_from_storage_of_mini_selfhost_List_mini_selfhost_Instr), (src_BinOp_size), (src_Word_prefix), (src_MemWidth_prefix), (src_DivOp_size 75 975), (src_FOp_size 75 105 975 1202), (src_core_mem_size_of_of_mini_selfhost_List_u8), (src_le64 707 708), (src_slot_load 456 707 708 709 1203), (src_slot_store 456 707 708 709 1203), (src_BinOp_bytes 456 1204 1205 1206), (src_slot_compare 456 707 708 1204 1205 1207), (src_relative), (src_copy_bytes 75 76 110 456 981 982 986), (src_arg_base 75 710), (src_fsp_save 456 707 708 709 1203), (src_fsp_load 456 707 708 709 1203), (src_slot_range 56 75 138 377 990), (src_epilogue 707 708), (src_bump_bytes 456 707 708 980 1208), (src_load_at_bytes 707 708), (src_store_at_bytes 456 707 708 709 1203), (src_load_word_bytes 456 707 708 1209), (src_store_word_bytes 456 707 708 709 1203 1209), (src_DivOp_bytes 456 707 708 1204 1205 1210 1211 1212), (src_FOp_bytes 456 1204 1213), (src_sys_bytes 75 456 707 708 709 1203 1214 1215 1216)]

def dents9 : List SigEntry := [some ([ty20, (.uint .usize), (.uint .usize), (.uint .usize), (.uint .usize), (.uint .usize)], .bool), none, some ([], ty33), some ([ty257, ty227], ty227), some ([ty258, ty177, ty259], ty257), some ([(.uint .usize), ty226, ty186], ty258), some ([(.uint .usize), ty226, ty187], ty177), some ([(.uint .usize), ty226, ty192], ty259), some ([], ty225), some ([ty177, ty225], ty225), some ([(.uint .usize), ty127, ty156, (.uint .usize), ty153], ty177), some ([ty33], .bool), some ([ty31, ty33], ty33), some ([ty33, ty9, ty262, ty30], ty30), some ([ty12], ty262), some ([ty156, ty152], .bool), some ([ty152], ty153), none, some ([ty150], ty152), some ([ty154, ty223], ty223), some ([(.uint .usize), ty127, (.uint .usize), ty153], ty223), none, none, some ([ty185], ty186), some ([ty188], ty192), some ([ty191], ty153), none, some ([ty156, ty154], ty156), some ([ty154], ty156), some ([ty156, ty156], ty156), some ([ty191], ty156), some ([ty195], ty194), some ([(.uint .usize), ty127, ty110, ty153], ty228), some ([ty110, ty154], .bool), some ([ty228, ty154], ty228), some ([(.uint .usize), ty127, ty110, ty153], ty228), some ([ty153], ty153), some ([ty184], ty186), some ([ty112], (.uint .usize)), some ([(.uint .usize), ty127, ty152], ty246), some ([ty153, (.uint .usize)], ty245), none, none, none, none, none, none, none, none, none, none, some ([(.uint .uint64)], (.uint .uint64)), some ([ty51, ty52, (.uint .uint64), (.uint .uint64), ty90, ty90], ty90), some ([ty51, ty52, (.uint .uint64), ty90, ty90], ty90), some ([ty51, ty52, ty90, ty90, (.uint .uint64)], ty90), some ([ty51, ty53, (.uint .uint64), (.uint .uint64)], .bool), some ([ty201, (.uint .usize), ty203], ty90), some ([ty202], ty203), some ([ty203, (.uint .usize), ty90], ty203), some ([ty203, (.uint .usize)], ty203), some ([ty94, (.uint .usize)], .bool), some ([ty90, ty90], .bool), some ([ty230], ty230), some ([ty51, ty52, ty230, ty230], ty230), some ([ty51, ty53, ty230, ty230], ty230), some ([ty230, (.uint .uint64)], .bool), some ([ty93, ty93], .bool), some ([ty54], (.uint .usize)), some ([ty51], (.uint .usize)), some ([ty55], (.uint .usize)), some ([ty59], (.uint .usize)), some ([ty161, (.uint .usize)], ty250), none, none, some ([ty52], (.uint .usize)), some ([ty51], (.uint .usize)), some ([ty54], (.uint .usize)), some ([ty55, ty51], (.uint .usize)), some ([ty58], (.uint .usize)), none, some ([(.uint .uint64)], ty67), some ([(.uint .usize)], ty67), some ([(.uint .usize)], ty67), some ([ty52, ty51, (.uint .usize)], ty67), some ([ty51, ty53, (.uint .usize)], ty67), some ([(.uint .usize), (.uint .usize)], .i32), some ([(.uint .usize), ty20, (.uint .usize)], ty67), some ([(.uint .usize)], (.uint .usize)), some ([(.uint .usize)], ty67), some ([(.uint .usize)], ty67), some ([(.uint .usize), (.uint .usize)], ty20), some ([], ty67), some ([(.uint .usize)], ty67), some ([], ty67), some ([(.uint .usize)], ty67), some ([ty54], ty67), some ([ty54, (.uint .usize)], ty67), some ([ty55, ty51, (.uint .usize)], ty67), some ([ty58, (.uint .usize)], ty67), some ([ty59, (.uint .usize)], ty67)]

/-- `declareFuncs` of functions 900 to 999. -/
theorem dchunk9 : declsStep dpart9 decls 35 59 32 54 = true := by decide +kernel

theorem dfit9 : entriesFit dpart9 dents9 = true := by decide +kernel

end Lanius.Faithful.SelfPure
