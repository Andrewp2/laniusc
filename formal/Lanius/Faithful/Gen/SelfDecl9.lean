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
public import Lanius.Faithful.Gen.SelfSrcC_arithShiftRight
public import Lanius.Faithful.Gen.SelfSrcC_arities
public import Lanius.Faithful.Gen.SelfSrcC_assignFrom
public import Lanius.Faithful.Gen.SelfSrcC_binaryConstant
public import Lanius.Faithful.Gen.SelfSrcC_conjunction
public import Lanius.Faithful.Gen.SelfSrcC_declareProgram
public import Lanius.Faithful.Gen.SelfSrcC_equality
public import Lanius.Faithful.Gen.SelfSrcC_floatApply
public import Lanius.Faithful.Gen.SelfSrcC_guardAnd
public import Lanius.Faithful.Gen.SelfSrcC_killShared
public import Lanius.Faithful.Gen.SelfSrcC_loadAtBytes
public import Lanius.Faithful.Gen.SelfSrcC_longer
public import Lanius.Faithful.Gen.SelfSrcC_lowerLocal
public import Lanius.Faithful.Gen.SelfSrcC_lowerShift
public import Lanius.Faithful.Gen.SelfSrcC_optimizeLeft
public import Lanius.Faithful.Gen.SelfSrcC_repeatType
public import Lanius.Faithful.Gen.SelfSrcC_sintToUint
public import Lanius.Faithful.Gen.SelfSrcF_effNamedTys
public import Lanius.Faithful.Gen.SelfSrcF_externBody
public import Lanius.Faithful.Gen.SelfSrcF_findConst
public import Lanius.Faithful.Gen.SelfSrcF_ifNotWrites
public import Lanius.Faithful.Gen.SelfSrcF_projectionRet
public import Lanius.Faithful.Gen.SelfSrcF_readInst
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
import all Lanius.Faithful.Gen.SelfSrcC_arithShiftRight
import all Lanius.Faithful.Gen.SelfSrcC_arities
import all Lanius.Faithful.Gen.SelfSrcC_assignFrom
import all Lanius.Faithful.Gen.SelfSrcC_binaryConstant
import all Lanius.Faithful.Gen.SelfSrcC_conjunction
import all Lanius.Faithful.Gen.SelfSrcC_declareProgram
import all Lanius.Faithful.Gen.SelfSrcC_equality
import all Lanius.Faithful.Gen.SelfSrcC_floatApply
import all Lanius.Faithful.Gen.SelfSrcC_guardAnd
import all Lanius.Faithful.Gen.SelfSrcC_killShared
import all Lanius.Faithful.Gen.SelfSrcC_loadAtBytes
import all Lanius.Faithful.Gen.SelfSrcC_longer
import all Lanius.Faithful.Gen.SelfSrcC_lowerLocal
import all Lanius.Faithful.Gen.SelfSrcC_lowerShift
import all Lanius.Faithful.Gen.SelfSrcC_optimizeLeft
import all Lanius.Faithful.Gen.SelfSrcC_repeatType
import all Lanius.Faithful.Gen.SelfSrcC_sintToUint
import all Lanius.Faithful.Gen.SelfSrcF_effNamedTys
import all Lanius.Faithful.Gen.SelfSrcF_externBody
import all Lanius.Faithful.Gen.SelfSrcF_findConst
import all Lanius.Faithful.Gen.SelfSrcF_ifNotWrites
import all Lanius.Faithful.Gen.SelfSrcF_projectionRet
import all Lanius.Faithful.Gen.SelfSrcF_readInst
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
def dpart9 : List SrcFunc := [(src_unbox_of_mini_selfhost_List_mini_selfhost_MParam 1126), (src_unbox_of_mini_selfhost_MStmt 1127), (src_eff_named_tys 403 603 606 902 1128 1129 1130), (src_core_mem_typed_slice_from_storage_of_mini_selfhost_List_mini_selfhost_MFunc), (src_add_inst 905 906 1123), (src_single_of_mini_selfhost_Inst 618), (src_concat_of_mini_selfhost_Inst 605 618 906), (src_eff_calls 253 402 906 907 1129 1130 1131), (src_boxed_of_mini_selfhost_List_mini_selfhost_MFunc 50 903 1132), (src_extern_func 146 147 339 567 863 868 1133 1134 1135 1136 1137 1138 1139), (src_diverges 75 339 868 1135 1140), (src_diverge_func 913 1141 1142 1143 1144), (src_read_fn 146 147 339 567 868 1133 1134 1135 1137 1138 1139 1145 1146 1147 1148 1149), (src_init_tys 403 600 603 913), (src_single_of_mini_selfhost_MParam 1150), (src_length_of_mini_selfhost_FnDecl 75 255 915), (src_struct_field_tys 600 1151), (src_get_of_mini_selfhost_Ty 56 600 917), (src_core_mem_size_of_of_mini_selfhost_List_mini_selfhost_Inst), (src_core_mem_size_of_of_mini_selfhost_List_mini_selfhost_TypeDecl), (src_core_mem_size_of_of_mini_selfhost_List_mini_selfhost_FnDecl), (src_core_mem_size_of_of_mini_selfhost_List_mini_selfhost_ConstDecl), (src_core_mem_typed_slice_from_storage_of_mini_selfhost_List_mini_selfhost_ConstDecl), (src_core_mem_size_of_of_mini_selfhost_List_mini_selfhost_ImportDecl), (src_core_mem_typed_slice_from_storage_of_mini_selfhost_List_mini_selfhost_ImportDecl), (src_core_mem_size_of_of_mini_selfhost_List_mini_selfhost_AliasDecl), (src_core_mem_size_of_of_mini_selfhost_List_mini_selfhost_ImplDecl), (src_core_mem_typed_slice_from_storage_of_mini_selfhost_List_mini_selfhost_ImplDecl), (src_low_bits), (src_optimize_both 311 1152 1153), (src_optimize_left 311 1154 1155 1156 1157 1158), (src_optimize_right 311 1154 1156 1157 1158), (src_Word_test 1159 1160), (src_fact_or 632), (src_unbox_of_mini_selfhost_List_mini_selfhost_Fact 1161), (src_assigned 419 936 1162 1163 1164 1165), (src_kill_shared 1166 1167), (src_Stmt_kills 281 937 1163 1168 1169 1170), (src_Expr_agrees 441 628 646 1171 1172 1173 1174 1175 1176), (src_negate_constant 928), (src_binary_constant 1177 1178), (src_compare_constant 451 932), (src_constant_is), (src_args_agree 442 938 943), (src_MemWidth_bytes), (src_Word_number), (src_DivOp_number), (src_Syscall_number), (src_get_of_mini_selfhost_Arity 56 948 1179), (src_core_mem_size_of_of_mini_selfhost_List_mini_selfhost_Instr), (src_core_mem_typed_slice_from_storage_of_mini_selfhost_List_mini_selfhost_Instr), (src_BinOp_size), (src_Word_prefix), (src_MemWidth_prefix), (src_DivOp_size 75 952), (src_FOp_size 75 105 952 1180), (src_core_mem_size_of_of_mini_selfhost_List_u8), (src_le64 684 685), (src_slot_load 438 684 685 686 1181), (src_slot_store 438 684 685 686 1181), (src_BinOp_bytes 438 1182 1183 1184), (src_slot_compare 438 684 685 1182 1183 1185), (src_relative), (src_copy_bytes 75 76 110 438 958 959 963), (src_arg_base 75 687), (src_fsp_save 438 684 685 686 1181), (src_get_or_of_usize 56 76 966), (src_fsp_load 438 684 685 686 1181), (src_slot_range 56 75 229 374 968), (src_epilogue 684 685), (src_bump_bytes 438 684 685 957 1186), (src_load_at_bytes 684 685), (src_store_at_bytes 438 684 685 686 1181), (src_load_word_bytes 438 684 685 1187), (src_store_word_bytes 438 684 685 686 1181 1187), (src_DivOp_bytes 438 684 685 1182 1183 1188 1189 1190), (src_FOp_bytes 438 1182 1191), (src_sys_bytes 75 438 684 685 686 1181 1192 1193 1194), (src_frame_memory_bytes 438 684 685 957), (src_literal_below), (src_UintTy_bits), (src_lower_field_at 1195), (src_offset_or_arith 311 313 354 983), (src_arith 311 312 355 730 732 733 741 1196 1197 1198 1199), (src_lower_shift 983 1200), (src_arith_shift_right 312 355 984 1197), (src_order 311 312 355 356 730 732 733 741 1197 1201 1202 1203 1204), (src_equality 218 311 730 732 1201 1205), (src_conjunction 311 351), (src_disjunction 311 351), (src_cast_to_i32 1206 1207), (src_cast_to_uint 1206 1208 1209), (src_cast_to_isize 1208 1210), (src_cast_to_float 1211 1212 1213 1214), (src_cast_to_sint 291 351 354 730 992 1010 1011), (src_copy_field_at 1215), (src_concat_of_mini_selfhost_Expr 285 442 996), (src_unbox_of_mini_selfhost_List_mini_selfhost_SrcArm 1216), (src_lower_arm 172 286 290 311), (src_arm_guard 175)]

def dents9 : List SigEntry := [some ([ty185], ty186), some ([ty188], ty192), some ([ty191], ty154), none, some ([ty157, ty155], ty157), some ([ty155], ty157), some ([ty157, ty157], ty157), some ([ty191], ty157), some ([ty195], ty194), some ([(.uint .usize), ty127, ty110, ty154], ty228), some ([ty110, ty155], .bool), some ([ty228, ty155], ty228), some ([(.uint .usize), ty127, ty110, ty154], ty228), some ([ty154], ty154), some ([ty184], ty186), some ([ty112], (.uint .usize)), some ([(.uint .usize), ty127, ty153], ty246), some ([ty154, (.uint .usize)], ty245), none, none, none, none, none, none, none, none, none, none, some ([(.uint .uint64)], (.uint .uint64)), some ([ty51, ty52, (.uint .uint64), (.uint .uint64), ty90, ty90], ty90), some ([ty51, ty52, (.uint .uint64), ty90, ty90], ty90), some ([ty51, ty52, ty90, ty90, (.uint .uint64)], ty90), some ([ty51, ty53, (.uint .uint64), (.uint .uint64)], .bool), some ([ty201, (.uint .usize), ty203], ty90), some ([ty202], ty203), some ([ty203, (.uint .usize), ty90], ty203), some ([ty203, (.uint .usize)], ty203), some ([ty94, (.uint .usize)], .bool), some ([ty90, ty90], .bool), some ([ty230], ty230), some ([ty51, ty52, ty230, ty230], ty230), some ([ty51, ty53, ty230, ty230], ty230), some ([ty230, (.uint .uint64)], .bool), some ([ty93, ty93], .bool), some ([ty54], (.uint .usize)), some ([ty51], (.uint .usize)), some ([ty55], (.uint .usize)), some ([ty59], (.uint .usize)), some ([ty162, (.uint .usize)], ty250), none, none, some ([ty52], (.uint .usize)), some ([ty51], (.uint .usize)), some ([ty54], (.uint .usize)), some ([ty55, ty51], (.uint .usize)), some ([ty58], (.uint .usize)), none, some ([(.uint .uint64)], ty67), some ([(.uint .usize)], ty67), some ([(.uint .usize)], ty67), some ([ty52, ty51, (.uint .usize)], ty67), some ([ty51, ty53, (.uint .usize)], ty67), some ([(.uint .usize), (.uint .usize)], .i32), some ([(.uint .usize), ty20, (.uint .usize)], ty67), some ([(.uint .usize)], (.uint .usize)), some ([(.uint .usize)], ty67), some ([ty20, (.uint .usize), (.uint .usize)], (.uint .usize)), some ([(.uint .usize)], ty67), some ([(.uint .usize), (.uint .usize)], ty20), some ([], ty67), some ([(.uint .usize)], ty67), some ([], ty67), some ([(.uint .usize)], ty67), some ([ty54], ty67), some ([ty54, (.uint .usize)], ty67), some ([ty55, ty51, (.uint .usize)], ty67), some ([ty58, (.uint .usize)], ty67), some ([ty59, (.uint .usize)], ty67), some ([(.uint .usize)], ty67), some ([ty90, (.uint .uint64)], .bool), some ([ty4], (.uint .uint64)), some ([(.uint .usize), ty177], ty174), some ([ty52, ty173, ty173], ty174), some ([ty52, ty173, ty173], ty174), some ([ty52, ty173, ty173], ty174), some ([ty173, ty173], ty174), some ([ty53, ty173, ty173], ty174), some ([ty53, ty173, ty173], ty174), some ([ty173, ty173], ty174), some ([ty173, ty173], ty174), some ([ty173], ty174), some ([ty4, ty173], ty174), some ([ty173], ty174), some ([ty8, ty173], ty174), some ([ty4, ty173], ty174), some ([(.uint .usize), ty177, ty9], ty169), some ([ty93, ty93], ty93), some ([ty22], ty23), some ([(.uint .usize), (.uint .usize), (.uint .usize), ty90, ty169, ty23, ty144], ty144), some ([ty234, ty15], ty90)]

/-- `declareFuncs` of functions 900 to 999. -/
theorem dchunk9 : declsStep dpart9 decls 33 55 32 54 = true := by decide +kernel

theorem dfit9 : entriesFit dpart9 dents9 = true := by decide +kernel

end Lanius.Faithful.SelfPure
